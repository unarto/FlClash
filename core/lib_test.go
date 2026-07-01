package main

import (
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"golang.org/x/sync/semaphore"
	"testing"
	"unsafe"
)

type stubRawConn struct {
	control func(func(uintptr)) error
}

func (s stubRawConn) Control(fn func(uintptr)) error {
	return s.control(fn)
}

func (stubRawConn) Read(func(uintptr) bool) error {
	return nil
}

func (stubRawConn) Write(func(uintptr) bool) error {
	return nil
}

func TestTunHandlerInitHookSkipsProcessResolverWithoutCallback(t *testing.T) {
	originalSocketHook := dialer.DefaultSocketHook
	originalResolver := process.DefaultPackageNameResolver
	t.Cleanup(func() {
		dialer.DefaultSocketHook = originalSocketHook
		process.DefaultPackageNameResolver = originalResolver
	})

	handler := &TunHandler{limit: semaphore.NewWeighted(4)}
	handler.initHook()

	if dialer.DefaultSocketHook == nil {
		t.Fatal("expected socket hook to be registered")
	}
	if process.DefaultPackageNameResolver != nil {
		t.Fatal("expected process resolver to stay nil without callback")
	}
}

func TestTunHandlerInitHookRegistersProcessResolverWithCallback(t *testing.T) {
	originalSocketHook := dialer.DefaultSocketHook
	originalResolver := process.DefaultPackageNameResolver
	t.Cleanup(func() {
		dialer.DefaultSocketHook = originalSocketHook
		process.DefaultPackageNameResolver = originalResolver
	})

	handler := &TunHandler{
		callback: unsafe.Pointer(new(byte)),
		limit:    semaphore.NewWeighted(4),
	}
	handler.initHook()

	if dialer.DefaultSocketHook == nil {
		t.Fatal("expected socket hook to be registered")
	}
	if process.DefaultPackageNameResolver == nil {
		t.Fatal("expected process resolver to be registered when callback exists")
	}
}

func TestTunHandlerSocketHookSkipsProtectWithoutCallback(t *testing.T) {
	originalSocketHook := dialer.DefaultSocketHook
	originalResolver := process.DefaultPackageNameResolver
	originalProtect := protectFD
	t.Cleanup(func() {
		dialer.DefaultSocketHook = originalSocketHook
		process.DefaultPackageNameResolver = originalResolver
		protectFD = originalProtect
	})

	calls := 0
	protectFD = func(_ unsafe.Pointer, _ int) {
		calls++
	}

	handler := &TunHandler{limit: semaphore.NewWeighted(4)}
	handler.initHook()
	handler.listener = &sing_tun.Listener{}
	tunHandler = handler

	err := dialer.DefaultSocketHook("tcp", "1.1.1.1:443", stubRawConn{
		control: func(fn func(uintptr)) error {
			fn(123)
			return nil
		},
	})
	if err != nil {
		t.Fatalf("socket hook returned error: %v", err)
	}
	if calls != 0 {
		t.Fatalf("expected protect to be skipped without callback, got %d calls", calls)
	}
}

func TestFinalizeTunStartAfterSetupStartsListenerWhenCoreNotRunning(t *testing.T) {
	originalStartListener := startListenerAfterTunStart
	originalResetConnections := resetConnectionsAfterTunStart
	originalIsRunning := isRunning
	t.Cleanup(func() {
		startListenerAfterTunStart = originalStartListener
		resetConnectionsAfterTunStart = originalResetConnections
		isRunning = originalIsRunning
	})

	startCalls := 0
	resetCalls := 0
	startListenerAfterTunStart = func() bool {
		startCalls++
		isRunning = true
		return true
	}
	resetConnectionsAfterTunStart = func() bool {
		resetCalls++
		return true
	}

	isRunning = false
	finalizeTunStartAfterSetup()

	if startCalls != 1 {
		t.Fatalf("expected start listener to be called once, got %d", startCalls)
	}
	if resetCalls != 0 {
		t.Fatalf("expected reset connections to be skipped, got %d calls", resetCalls)
	}
	if !isRunning {
		t.Fatal("expected start listener path to mark core running")
	}
}

func TestFinalizeTunStartAfterSetupResetsConnectionsWhenCoreRunning(t *testing.T) {
	originalStartListener := startListenerAfterTunStart
	originalResetConnections := resetConnectionsAfterTunStart
	originalIsRunning := isRunning
	t.Cleanup(func() {
		startListenerAfterTunStart = originalStartListener
		resetConnectionsAfterTunStart = originalResetConnections
		isRunning = originalIsRunning
	})

	startCalls := 0
	resetCalls := 0
	startListenerAfterTunStart = func() bool {
		startCalls++
		return true
	}
	resetConnectionsAfterTunStart = func() bool {
		resetCalls++
		return true
	}

	isRunning = true
	finalizeTunStartAfterSetup()

	if startCalls != 0 {
		t.Fatalf("expected start listener to be skipped, got %d calls", startCalls)
	}
	if resetCalls != 1 {
		t.Fatalf("expected reset connections to be called once, got %d", resetCalls)
	}
}
