package main

import (
	"errors"
	"io"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type concurrentWriteDetector struct {
	activeWrites     atomic.Int32
	sawConcurrent    atomic.Bool
	firstWriteEntered chan struct{}
	secondWriteEntered chan struct{}
}

func newConcurrentWriteDetector() *concurrentWriteDetector {
	return &concurrentWriteDetector{
		firstWriteEntered:  make(chan struct{}),
		secondWriteEntered: make(chan struct{}),
	}
}

func (d *concurrentWriteDetector) Read(_ []byte) (int, error) {
	return 0, io.EOF
}

func (d *concurrentWriteDetector) Write(p []byte) (int, error) {
	activeWrites := d.activeWrites.Add(1)
	if activeWrites > 1 {
		d.sawConcurrent.Store(true)
	}
	if activeWrites == 1 {
		select {
		case <-d.firstWriteEntered:
		default:
			close(d.firstWriteEntered)
		}
		time.Sleep(100 * time.Millisecond)
	} else {
		select {
		case <-d.secondWriteEntered:
		default:
			close(d.secondWriteEntered)
		}
	}
	d.activeWrites.Add(-1)
	return len(p), nil
}

func (d *concurrentWriteDetector) Close() error {
	return nil
}

func TestSendSerializesFrameWrites(t *testing.T) {
	originalConn := conn
	connMu.Lock()
	conn = nil
	connMu.Unlock()
	t.Cleanup(func() {
		connMu.Lock()
		conn = originalConn
		connMu.Unlock()
	})

	detector := newConcurrentWriteDetector()
	connMu.Lock()
	conn = detector
	connMu.Unlock()

	var sendWG sync.WaitGroup
	sendWG.Add(2)

	go func() {
		defer sendWG.Done()
		send([]byte(`{"id":1}`))
	}()

	select {
	case <-detector.firstWriteEntered:
	case <-time.After(time.Second):
		t.Fatal("first send did not reach write")
	}

	go func() {
		defer sendWG.Done()
		send([]byte(`{"id":2}`))
	}()

	sendWG.Wait()

	if detector.sawConcurrent.Load() {
		t.Fatal("expected send to serialize frame writes")
	}
}

type blockingConn struct{}

func (blockingConn) Read(_ []byte) (int, error) {
	select {}
}

func (blockingConn) Write(p []byte) (int, error) {
	return len(p), nil
}

func (blockingConn) Close() error {
	return nil
}

func TestDetachedStartDoesNotPublishConnAfterStopBeforeDialCompletes(t *testing.T) {
	originalConn := conn
	originalDial := dialServer
	originalGeneration := detachedServerGeneration.Load()
	connMu.Lock()
	conn = nil
	connMu.Unlock()
	detachedServerGeneration.Store(0)
	t.Cleanup(func() {
		connMu.Lock()
		conn = originalConn
		connMu.Unlock()
		dialServer = originalDial
		detachedServerGeneration.Store(originalGeneration)
	})

	dialStarted := make(chan struct{})
	releaseDial := make(chan struct{})
	dialReturned := make(chan struct{})
	dialServer = func(string) (io.ReadWriteCloser, error) {
		close(dialStarted)
		<-releaseDial
		close(dialReturned)
		return blockingConn{}, nil
	}

	go startServerProcessDetached(nil, nil)

	select {
	case <-dialStarted:
	case <-time.After(time.Second):
		t.Fatal("detached start did not begin dialing")
	}

	stopServerProcessDetached()
	close(releaseDial)

	select {
	case <-dialReturned:
	case <-time.After(time.Second):
		t.Fatal("dial did not finish after release")
	}

	deadline := time.Now().Add(200 * time.Millisecond)
	for {
		connMu.Lock()
		currentConn := conn
		connMu.Unlock()
		if currentConn == nil {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("expected stop before dial completion to keep conn nil")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

type stallWriteConn struct {
	closed chan struct{}
	once   sync.Once
}

func (c *stallWriteConn) Read(_ []byte) (int, error) {
	select {}
}

func (c *stallWriteConn) Write(_ []byte) (int, error) {
	<-c.closed
	return 0, errors.New("conn closed")
}

func (c *stallWriteConn) Close() error {
	c.once.Do(func() { close(c.closed) })
	return nil
}

// A Write that stalls (peer buffer full / dead reader) must not keep stopServer
// from swapping conn out and closing the fd — closing the fd is what unblocks
// the stalled Write. send() therefore must not hold connMu across writeFrame.
func TestStopServerUnblocksStalledWrite(t *testing.T) {
	originalConn := conn
	connMu.Lock()
	conn = nil
	connMu.Unlock()
	t.Cleanup(func() {
		connMu.Lock()
		conn = originalConn
		connMu.Unlock()
	})

	stalled := &stallWriteConn{closed: make(chan struct{})}
	connMu.Lock()
	conn = stalled
	connMu.Unlock()

	sendDone := make(chan struct{})
	go func() {
		send([]byte(`{"id":1}`))
		close(sendDone)
	}()

	// Give the send goroutine time to enter the blocking Write.
	time.Sleep(50 * time.Millisecond)

	stopDone := make(chan struct{})
	go func() {
		stopServer()
		close(stopDone)
	}()

	select {
	case <-stopDone:
	case <-time.After(time.Second):
		t.Fatal("stopServer blocked behind a stalled write (deadlock)")
	}

	select {
	case <-sendDone:
	case <-time.After(time.Second):
		t.Fatal("send did not return after conn was closed")
	}
}

func TestDetachedStartDoesNotPanicWhenStopPreemptsDial(t *testing.T) {
	originalDial := dialServer
	originalGeneration := detachedServerGeneration.Load()
	detachedServerGeneration.Store(0)
	t.Cleanup(func() {
		dialServer = originalDial
		detachedServerGeneration.Store(originalGeneration)
	})

	dialServer = func(string) (io.ReadWriteCloser, error) {
		return nil, errors.New("dial canceled")
	}

	stopServerProcessDetached()
	startServerProcessDetached(nil, nil)
}
