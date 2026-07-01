//go:build !cgo

package main

import (
	"fmt"
	"os"
	"path/filepath"
)

var coreDebugLogPath string

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

func main() {
	args := os.Args
	if len(args) <= 1 {
		fmt.Println("Arguments error")
		os.Exit(1)
	}
	if len(args) > 2 {
		coreDebugLogPath = args[2]
	} else {
		coreDebugLogPath = filepath.Join(filepath.Dir(args[1]), "flclash-core.log")
	}
	debugCoreLog("main start socket=%s", args[1])
	startServer(args[1])
}
