//go:build (android || ohos) && cgo

package tun

import "C"
import (
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"syscall"
	"strings"
)

func Start(fd int, stack string, address, dns string) *sing_tun.Listener {
	log.Infoln("TUN start request fd=%d stack=%s address=%s dns=%s", fd, stack, address, dns)
	if err := syscall.SetNonblock(fd, true); err != nil {
		log.Warnln("TUN set nonblock failed fd=%d err=%v", fd, err)
	} else {
		log.Infoln("TUN set nonblock fd=%d", fd)
	}
	tunStack, ok := constant.StackTypeMapping[strings.ToLower(stack)]
	if !ok {
		tunStack = constant.TunSystem
	}
	if tunBuildGOOS == "ohos" {
		// The system-stack TCP NAT (used by the "mixed" stack) rewrites each TCP
		// SYN to the tun's own address and writes it back, relying on the kernel
		// to loop the packet to the local TCP listener. That loopback does not
		// happen inside the OHOS VpnExtension, so TCP connections never reach the
		// tunnel (UDP/DNS still works because it is injected straight into gVisor).
		// Force the gVisor stack so TCP is also handled entirely in userspace.
		tunStack = constant.TunGvisor
	}
	options, err := buildTunOptions(fd, "FlClash", tunStack, address, dns)
	if err != nil {
		log.Errorln("TUN:", err)
		return nil
	}
	log.Infoln(
		"TUN options stack=%s autoRoute=%t autoDetectInterface=%t mtu=%d fd=%d inet4=%v inet6=%v dnsHijack=%v",
		tunStack.String(),
		options.AutoRoute,
		options.AutoDetectInterface,
		options.MTU,
		options.FileDescriptor,
		options.Inet4Address,
		options.Inet6Address,
		options.DNSHijack,
	)

	listener, err := sing_tun.New(options, tunnel.Tunnel)

	if err != nil {
		log.Errorln("TUN:", err)
		return nil
	}
	log.Infoln("TUN listener created stack=%s", tunStack.String())

	return listener
}
