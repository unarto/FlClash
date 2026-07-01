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
	"sync/atomic"
)

var (
	conn             io.ReadWriteCloser
	connMu           sync.Mutex
	writeMu          sync.Mutex
	coreDebugLogPath string
	dialServer       = dial

	detachedServerGeneration atomic.Uint64
)

func debugCoreLog(format string, args ...interface{}) {
	if coreDebugLogPath == "" {
		coreDebugLogPath = "/data/storage/el2/base/files/flclash-core.log"
	}
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
	connMu.Lock()
	currentConn := conn
	connMu.Unlock()
	if currentConn == nil {
		debugCoreLog("send conn nil")
		return
	}
	// Serialize frame writes with writeMu instead of connMu so that a stalled
	// Write cannot block stopServer from swapping conn out and closing the fd
	// (which is what unblocks the stalled Write).
	writeMu.Lock()
	defer writeMu.Unlock()
	if err := writeFrame(currentConn, data); err != nil {
		debugCoreLog("server write error: %v", err)
	}
}

func stopServer() {
	connMu.Lock()
	currentConn := conn
	conn = nil
	connMu.Unlock()
	if currentConn != nil {
		_ = currentConn.Close()
	}
}

// stopConnection tears down currentConn, but only clears the global conn if it
// still points at currentConn. This keeps a stale connection's teardown from
// closing a newer connection installed by a concurrent restart.
func stopConnection(currentConn io.ReadWriteCloser) {
	connMu.Lock()
	if conn == currentConn {
		conn = nil
	}
	connMu.Unlock()
	_ = currentConn.Close()
}

func serveConnection(currentConn io.ReadWriteCloser, generation uint64) {
	connMu.Lock()
	if detachedServerGeneration.Load() != generation {
		connMu.Unlock()
		debugCoreLog(
			"startServer stale before serve generation=%d current=%d",
			generation,
			detachedServerGeneration.Load(),
		)
		_ = currentConn.Close()
		return
	}
	conn = currentConn
	connMu.Unlock()

	defer func() {
		debugCoreLog("startServer closing connection")
		stopConnection(currentConn)
	}()

	for {
		data, err := readFrame(currentConn)
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

func startServer(socketPath string) {
	generation := detachedServerGeneration.Add(1)
	debugCoreLog("startServer dial begin address=%s", socketPath)
	currentConn, err := dialServer(socketPath)
	if err != nil {
		debugCoreLog("startServer dial failed address=%s err=%v", socketPath, err)
		panic(err.Error())
	}
	debugCoreLog("startServer dial connected address=%s", socketPath)
	serveConnection(currentConn, generation)
}

func prepareServerProcess(socketPathChar, logPathChar *C.char) (string, string) {
	socketPath := takeCString(socketPathChar)
	logPath := takeCString(logPathChar)
	if logPath == "" {
		logPath = filepath.Join(filepath.Dir(socketPath), "flclash-core.log")
	}
	coreDebugLogPath = logPath
	return socketPath, logPath
}

//export startServerProcess
func startServerProcess(socketPathChar, logPathChar *C.char) {
	socketPath, _ := prepareServerProcess(socketPathChar, logPathChar)
	debugCoreLog("startServerProcess socket=%s", socketPath)
	startServer(socketPath)
}

//export startServerProcessDetached
func startServerProcessDetached(socketPathChar, logPathChar *C.char) {
	socketPath, logPath := prepareServerProcess(socketPathChar, logPathChar)
	debugCoreLog("startServerProcessDetached socket=%s", socketPath)
	generation := detachedServerGeneration.Add(1)
	go func(socketPath, logPath string, generation uint64) {
		coreDebugLogPath = logPath
		defer func() {
			if recoverValue := recover(); recoverValue != nil {
				debugCoreLog(
					"startServerProcessDetached panic socket=%s panic=%v",
					socketPath,
					recoverValue,
				)
			}
		}()
		debugCoreLog("startServer dial begin address=%s generation=%d", socketPath, generation)
		currentConn, err := dialServer(socketPath)
		if err != nil {
			debugCoreLog(
				"startServer dial failed address=%s generation=%d err=%v",
				socketPath,
				generation,
				err,
			)
			panic(err.Error())
		}
		debugCoreLog("startServer dial connected address=%s generation=%d", socketPath, generation)
		// serveConnection re-checks the generation under connMu before installing
		// the connection, closing the TOCTOU window against stopServerProcessDetached.
		serveConnection(currentConn, generation)
	}(socketPath, logPath, generation)
}

//export stopServerProcessDetached
func stopServerProcessDetached() {
	debugCoreLog("stopServerProcessDetached")
	detachedServerGeneration.Add(1)
	stopServer()
}
