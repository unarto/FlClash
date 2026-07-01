//go:build ohos && cgo

package main

/*
#include <stdlib.h>
#include "bride.h"

typedef void (*result_callback)(const char *data);

static inline void call_result_callback(void *callback, const char *data) {
	if (callback == NULL) {
		return;
	}
	((result_callback)callback)(data);
}
*/
import "C"
import "unsafe"

func protect(callback unsafe.Pointer, fd int) {
	C.protect(callback, C.int(fd))
}

func resolveProcess(callback unsafe.Pointer, protocol int, source, target string, uid int) string {
	s := C.CString(source)
	defer C.free(unsafe.Pointer(s))
	t := C.CString(target)
	defer C.free(unsafe.Pointer(t))
	res := C.resolve_process(callback, C.int(protocol), s, t, C.int(uid))
	return takeCString(res)
}

func invokeResult(callback unsafe.Pointer, data string) {
	if callback == nil {
		return
	}
	s := C.CString(data)
	defer C.free(unsafe.Pointer(s))
	C.call_result_callback(callback, s)
}

func releaseObject(_ unsafe.Pointer) {}

func takeCString(s *C.char) string {
	if s == nil {
		return ""
	}
	return C.GoString(s)
}
