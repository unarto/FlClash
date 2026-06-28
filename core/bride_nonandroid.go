//go:build cgo && !android && !ohos

package main

/*
#include <stdlib.h>

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

func protect(_ unsafe.Pointer, _ int) {}

func resolveProcess(
	_ unsafe.Pointer,
	_ int,
	_,
	_ string,
	_ int,
) string {
	return ""
}

func invokeResult(callback unsafe.Pointer, data string) {
	if callback == nil {
		return
	}
	s := C.CString(data)
	C.call_result_callback(callback, s)
}

func releaseObject(_ unsafe.Pointer) {}

func takeCString(s *C.char) string {
	if s == nil {
		return ""
	}
	return C.GoString(s)
}
