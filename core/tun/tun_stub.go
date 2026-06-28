//go:build cgo && !android && !ohos

package tun

import "github.com/metacubex/mihomo/listener/sing_tun"

func Start(int, string, string, string) *sing_tun.Listener {
	return nil
}
