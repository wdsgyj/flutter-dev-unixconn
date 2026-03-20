package main

/*
#include "include/unixconn_dart_bridge.h"
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"unixconn/native/proxy"

	"github.com/wdsgyj/unixproxy-go"
)

const (
	errorInvalidArgument = 1
	errorNotFound        = 2
	errorInternal        = 3
)

var manager = proxy.NewManager()
var initOnce = sync.Once{}

//export unixconn_start_proxy
func unixconn_start_proxy(socketPath *C.char, timeoutMs C.int32_t, dartPort C.int64_t, errorCode *C.int32_t, errorMessage **C.char) C.int64_t {
	initOnce.Do(func() {
		// 避免 iOS 上的 socket EPIPE 错误导致进程退出
		signal.Ignore(syscall.SIGPIPE)
	})

	path := C.GoString(socketPath)
	if path == "" {
		setError(errorCode, errorMessage, errorInvalidArgument, "socket path is required")
		return 0
	}

	options := proxy.Options{}
	if timeoutMs > 0 {
		options.ClientTimeout = time.Duration(timeoutMs) * time.Millisecond
	}
	if dartPort != 0 {
		options.OnTrace = func(event unixproxy.TraceEvent) {
			postTraceEvent(C.Dart_Port_DL(dartPort), event)
		}
	}

	handle, err := manager.Start(path, options)
	if err != nil {
		setError(errorCode, errorMessage, errorInternal, err.Error())
		return 0
	}

	clearError(errorCode, errorMessage)
	return C.int64_t(handle)
}

//export unixconn_stop_proxy
func unixconn_stop_proxy(handle C.int64_t, errorCode *C.int32_t, errorMessage **C.char) C.int32_t {
	if handle <= 0 {
		setError(errorCode, errorMessage, errorInvalidArgument, "proxy handle must be positive")
		return 0
	}

	if err := manager.Stop(int64(handle)); err != nil {
		code := int32(errorInternal)
		if containsNotFound(err) {
			code = int32(errorNotFound)
		}
		setError(errorCode, errorMessage, code, err.Error())
		return 0
	}

	clearError(errorCode, errorMessage)
	return 0
}

//export unixconn_free_string
func unixconn_free_string(value *C.char) {
	if value == nil {
		return
	}
	C.free(unsafe.Pointer(value))
}

func main() {}

func clearError(errorCode *C.int32_t, errorMessage **C.char) {
	if errorCode != nil {
		*errorCode = 0
	}
	if errorMessage != nil {
		*errorMessage = nil
	}
}

func setError(errorCode *C.int32_t, errorMessage **C.char, code int32, message string) {
	if errorCode != nil {
		*errorCode = C.int32_t(code)
	}
	if errorMessage != nil {
		*errorMessage = C.CString(message)
	}
}

func containsNotFound(err error) bool {
	return err != nil && strings.Contains(err.Error(), "does not exist")
}

type traceEventPayload struct {
	RequestID             uint64          `json:"requestId"`
	Method                string          `json:"method"`
	URL                   string          `json:"url"`
	StartedAt             time.Time       `json:"startedAt"`
	FinishedAt            time.Time       `json:"finishedAt"`
	TotalDurationMicros   int64           `json:"totalDurationMicros"`
	ReusedConn            bool            `json:"reusedConn"`
	DNSDurationMicros     *int64          `json:"dnsDurationMicros,omitempty"`
	ConnectDurationMicros *int64          `json:"connectDurationMicros,omitempty"`
	RemoteIP              string          `json:"remoteIp,omitempty"`
	TLSDurationMicros     *int64          `json:"tlsDurationMicros,omitempty"`
	TLS                   *tlsInfoPayload `json:"tls,omitempty"`
	RequestSentAt         *time.Time      `json:"requestSentAt,omitempty"`
	RequestBytes          *int64          `json:"requestBytes,omitempty"`
	FirstResponseByteAt   *time.Time      `json:"firstResponseByteAt,omitempty"`
	ResponseBytes         *int64          `json:"responseBytes,omitempty"`
	StatusCode            *int            `json:"statusCode,omitempty"`
	ErrorPhase            string          `json:"errorPhase,omitempty"`
	Error                 string          `json:"error,omitempty"`
}

type tlsInfoPayload struct {
	Version                    uint16                       `json:"version"`
	VersionName                string                       `json:"versionName"`
	CipherSuite                uint16                       `json:"cipherSuite"`
	CipherSuiteName            string                       `json:"cipherSuiteName"`
	ServerName                 string                       `json:"serverName"`
	NegotiatedProtocol         string                       `json:"negotiatedProtocol"`
	NegotiatedProtocolIsMutual bool                         `json:"negotiatedProtocolIsMutual"`
	DidResume                  bool                         `json:"didResume"`
	HandshakeComplete          bool                         `json:"handshakeComplete"`
	PeerCertificates           []peerCertificateInfoPayload `json:"peerCertificates"`
}

type peerCertificateInfoPayload struct {
	Subject           string    `json:"subject"`
	Issuer            string    `json:"issuer"`
	SerialNumber      string    `json:"serialNumber"`
	DNSNames          []string  `json:"dnsNames"`
	EmailAddresses    []string  `json:"emailAddresses"`
	IPAddresses       []string  `json:"ipAddresses"`
	URIs              []string  `json:"uris"`
	NotBefore         time.Time `json:"notBefore"`
	NotAfter          time.Time `json:"notAfter"`
	SHA256Fingerprint string    `json:"sha256Fingerprint"`
}

func postTraceEvent(port C.Dart_Port_DL, event unixproxy.TraceEvent) {
	payload := traceEventPayload{
		RequestID:           event.RequestID,
		Method:              event.Method,
		URL:                 event.URL,
		StartedAt:           event.StartedAt,
		FinishedAt:          event.FinishedAt,
		TotalDurationMicros: event.TotalDuration.Microseconds(),
		ReusedConn:          event.ReusedConn,
		DNSDurationMicros:   durationMicros(event.DNSDuration),
		ConnectDurationMicros: durationMicros(
			event.ConnectDuration,
		),
		RemoteIP:            event.RemoteIP,
		TLSDurationMicros:   durationMicros(event.TLSDuration),
		TLS:                 traceTLSPayload(event.TLS),
		RequestSentAt:       event.RequestSentAt,
		RequestBytes:        event.RequestBytes,
		FirstResponseByteAt: event.FirstResponseByteAt,
		ResponseBytes:       event.ResponseBytes,
		StatusCode:          event.StatusCode,
		ErrorPhase:          string(event.ErrorPhase),
	}
	if event.Error != nil {
		payload.Error = event.Error.Error()
	}

	bytes, err := json.Marshal(payload)
	if err != nil {
		return
	}

	message := C.CString(string(bytes))
	defer C.free(unsafe.Pointer(message))

	_ = C.unixconn_post_trace_json(port, message)
}

func durationMicros(duration *time.Duration) *int64 {
	if duration == nil {
		return nil
	}
	value := duration.Microseconds()
	return &value
}

func traceTLSPayload(info *unixproxy.TLSInfo) *tlsInfoPayload {
	if info == nil {
		return nil
	}

	peerCertificates := make([]peerCertificateInfoPayload, 0, len(info.PeerCertificates))
	for _, certificate := range info.PeerCertificates {
		peerCertificates = append(peerCertificates, peerCertificateInfoPayload{
			Subject:           certificate.Subject,
			Issuer:            certificate.Issuer,
			SerialNumber:      certificate.SerialNumber,
			DNSNames:          append([]string(nil), certificate.DNSNames...),
			EmailAddresses:    append([]string(nil), certificate.EmailAddresses...),
			IPAddresses:       append([]string(nil), certificate.IPAddresses...),
			URIs:              append([]string(nil), certificate.URIs...),
			NotBefore:         certificate.NotBefore,
			NotAfter:          certificate.NotAfter,
			SHA256Fingerprint: certificate.SHA256Fingerprint,
		})
	}

	return &tlsInfoPayload{
		Version:                    info.Version,
		VersionName:                info.VersionName,
		CipherSuite:                info.CipherSuite,
		CipherSuiteName:            info.CipherSuiteName,
		ServerName:                 info.ServerName,
		NegotiatedProtocol:         info.NegotiatedProtocol,
		NegotiatedProtocolIsMutual: info.NegotiatedProtocolIsMutual,
		DidResume:                  info.DidResume,
		HandshakeComplete:          info.HandshakeComplete,
		PeerCertificates:           peerCertificates,
	}
}
