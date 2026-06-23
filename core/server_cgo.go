//go:build cgo

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
)

var (
	conn             io.ReadWriteCloser
	connMu           sync.Mutex
	coreDebugLogPath string
)

func debugCoreLog(format string, args ...interface{}) {
	if coreDebugLogPath == "" {
		return
	}
	file, err := os.OpenFile(coreDebugLogPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = fmt.Fprintf(file, format+"\n", args...)
}

func writeFrame(w io.Writer, data []byte) error {
	frame := make([]byte, 4+len(data))
	binary.LittleEndian.PutUint32(frame, uint32(len(data)))
	copy(frame[4:], data)
	_, err := w.Write(frame)
	return err
}

func readFrame(r io.Reader) ([]byte, error) {
	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(r, lenBuf); err != nil {
		return nil, err
	}
	length := binary.LittleEndian.Uint32(lenBuf)
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, err
	}
	return data, nil
}

func send(data []byte) {
	if conn == nil {
		debugCoreLog("send conn nil")
		return
	}
	connMu.Lock()
	defer connMu.Unlock()
	if err := writeFrame(conn, data); err != nil {
		debugCoreLog("server write error: %v", err)
	}
}

func startServer(socketPath string) {
	var err error
	debugCoreLog("startServer dial begin address=%s", socketPath)
	conn, err = dial(socketPath)
	if err != nil {
		debugCoreLog("startServer dial failed address=%s err=%v", socketPath, err)
		panic(err.Error())
	}
	debugCoreLog("startServer dial connected address=%s", socketPath)

	defer func(conn io.Closer) {
		debugCoreLog("startServer closing connection")
		_ = conn.Close()
	}(conn)

	for {
		data, err := readFrame(conn)
		if err != nil {
			if err != io.EOF {
				debugCoreLog("startServer read error err=%v", err)
			}
			debugCoreLog("startServer read loop exit err=%v", err)
			return
		}
		var action = &Action{}
		err = json.Unmarshal(data, action)
		if err != nil {
			debugCoreLog("server unmarshal error err=%v data=%q", err, data)
			continue
		}
		result := ActionResult{
			Id:     action.Id,
			Method: action.Method,
		}
		go handleAction(action, result)
	}
}

//export startServerProcess
func startServerProcess(socketPathChar, logPathChar *C.char) {
	socketPath := takeCString(socketPathChar)
	coreDebugLogPath = takeCString(logPathChar)
	if coreDebugLogPath == "" {
		coreDebugLogPath = filepath.Join(filepath.Dir(socketPath), "flclash-core.log")
	}
	debugCoreLog("startServerProcess socket=%s", socketPath)
	startServer(socketPath)
}
