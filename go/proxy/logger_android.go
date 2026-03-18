package proxy

/*
#cgo LDFLAGS: -landroid -llog

#include <android/log.h>
#include <stdlib.h>
#include <string.h>
*/
import "C"

import (
	"bufio"
	"log"
	"os"
	"syscall"
	"unsafe"
)

var (
	ctag    = C.CString("GoLog")
	ctagErr = C.CString("GoStderr")
	ctagOut = C.CString("GoStdout")
	// Store the writer end of the redirected stderr and stdout
	// so that they are not garbage collected and closed.
	stderr, stdout *os.File
)

type infoWriter struct{}

func (infoWriter) Write(p []byte) (n int, err error) {
	cstr := C.CString(string(p))
	C.__android_log_write(C.ANDROID_LOG_INFO, ctag, cstr)
	C.free(unsafe.Pointer(cstr))
	return len(p), nil
}

func lineLog(f *os.File, priority C.int, cTag *C.char) {
	const logSize = 1024 // matches android/log.h.
	r := bufio.NewReaderSize(f, logSize)
	for {
		line, _, err := r.ReadLine()
		str := string(line)
		if err != nil {
			str += " " + err.Error()
		}
		cstr := C.CString(str)
		C.__android_log_write(priority, cTag, cstr)
		C.free(unsafe.Pointer(cstr))
		if err != nil {
			break
		}
	}
}

// 在 android 平台会自动编译替换 log 的实现
func init() {
	var _ = log.Ldate
	log.SetOutput(infoWriter{})
	// android logcat includes all of log.LstdFlags
	log.SetFlags(log.Flags() &^ log.LstdFlags)

	r, w, err := os.Pipe()
	if err != nil {
		panic(err)
	}
	stderr = w
	if err := syscall.Dup3(int(w.Fd()), int(os.Stderr.Fd()), 0); err != nil {
		panic(err)
	}
	go lineLog(r, C.ANDROID_LOG_ERROR, ctagErr)

	r, w, err = os.Pipe()
	if err != nil {
		panic(err)
	}
	stdout = w
	if err := syscall.Dup3(int(w.Fd()), int(os.Stdout.Fd()), 0); err != nil {
		panic(err)
	}
	go lineLog(r, C.ANDROID_LOG_INFO, ctagOut)
}
