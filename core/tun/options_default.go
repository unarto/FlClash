//go:build !ohos

package tun

import "runtime"

var tunBuildGOOS = runtime.GOOS
