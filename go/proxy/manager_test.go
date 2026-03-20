package proxy

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/wdsgyj/unixproxy-go"
)

func TestManagerStartAndStop(t *testing.T) {
	t.Parallel()

	tempDir, err := os.MkdirTemp("/tmp", "unixconn_proxy_test_")
	if err != nil {
		t.Fatalf("os.MkdirTemp() error = %v", err)
	}
	t.Cleanup(func() {
		_ = os.RemoveAll(tempDir)
	})
	upstreamSocketPath := filepath.Join(tempDir, "upstream.sock")
	upstreamListener, err := net.Listen("unix", upstreamSocketPath)
	if err != nil {
		t.Fatalf("net.Listen() error = %v", err)
	}
	defer upstreamListener.Close()

	upstreamServer := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "hello %s", r.URL.Path)
	})}
	defer upstreamServer.Close()

	go func() {
		_ = upstreamServer.Serve(upstreamListener)
	}()

	socketPath := filepath.Join(tempDir, "unixconn.sock")
	manager := NewManager()
	traceEvents := make(chan unixproxy.TraceEvent, 1)

	handle, err := manager.Start(socketPath, Options{
		ClientTimeout: 5 * time.Second,
		OnTrace: func(event unixproxy.TraceEvent) {
			traceEvents <- event
		},
		TransportConfig: func(transport *http.Transport) {
			transport.DialContext = func(_ context.Context, _, _ string) (net.Conn, error) {
				return net.Dial("unix", upstreamSocketPath)
			}
		},
	})
	if err != nil {
		t.Fatalf("Start() error = %v", err)
	}

	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer conn.Close()

	rawRequest := strings.Join([]string{
		"GET http://example.test/hello HTTP/1.1",
		"Host: example.test",
		"Connection: close",
		"",
		"",
	}, "\r\n")

	if _, err := conn.Write([]byte(rawRequest)); err != nil {
		t.Fatalf("Write() error = %v", err)
	}

	resp, err := http.ReadResponse(bufio.NewReader(conn), &http.Request{Method: http.MethodGet})
	if err != nil {
		t.Fatalf("ReadResponse() error = %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("ReadAll() error = %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("unexpected status code: got %d want %d", resp.StatusCode, http.StatusOK)
	}
	if string(body) != "hello /hello" {
		t.Fatalf("unexpected body: got %q", string(body))
	}

	select {
	case event := <-traceEvents:
		if event.RequestID == 0 {
			t.Fatalf("expected trace event request id to be populated")
		}
		if event.Method != http.MethodGet {
			t.Fatalf("unexpected trace method: got %q want %q", event.Method, http.MethodGet)
		}
		if event.URL != "http://example.test/hello" {
			t.Fatalf("unexpected trace URL: got %q", event.URL)
		}
		if event.StatusCode == nil || *event.StatusCode != http.StatusOK {
			t.Fatalf("unexpected trace status code: %#v", event.StatusCode)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for trace event")
	}

	if err := manager.Stop(handle); err != nil {
		t.Fatalf("Stop() error = %v", err)
	}

	if _, err := os.Stat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("expected proxy socket to be removed, got err = %v", err)
	}
}
