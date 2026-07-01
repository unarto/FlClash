package tun

import (
	C "github.com/metacubex/mihomo/constant"
	LC "github.com/metacubex/mihomo/listener/config"
	"net"
	"net/netip"
	"strings"
)

const (
	ohosIPv4PrefixLength = 30
	ohosIPv6PrefixLength = 126
)

func parsePrefixesForOS(goos string, address string) ([]netip.Prefix, []netip.Prefix, error) {
	var prefix4 []netip.Prefix
	var prefix6 []netip.Prefix
	for _, a := range strings.Split(address, ",") {
		a = strings.TrimSpace(a)
		if len(a) == 0 {
			continue
		}
		prefix, err := netip.ParsePrefix(a)
		if err != nil {
			if goos != "ohos" || !strings.Contains(a, "/") {
				addr, addrErr := netip.ParseAddr(a)
				if addrErr != nil || goos != "ohos" {
					return nil, nil, err
				}
				prefixLength := ohosIPv4PrefixLength
				if addr.Is6() {
					prefixLength = ohosIPv6PrefixLength
				}
				prefix = netip.PrefixFrom(addr, prefixLength)
			} else {
				return nil, nil, err
			}
		}
		if prefix.Addr().Is4() {
			prefix4 = append(prefix4, prefix)
		} else {
			prefix6 = append(prefix6, prefix)
		}
	}
	return prefix4, prefix6, nil
}

func parseDNSHijackForOS(goos string, dns string) []string {
	var dnsHijack []string
	seen := map[string]struct{}{}
	appendHijack := func(value string) {
		if value == "" {
			return
		}
		if _, ok := seen[value]; ok {
			return
		}
		seen[value] = struct{}{}
		dnsHijack = append(dnsHijack, value)
	}
	if goos == "ohos" {
		appendHijack("0.0.0.0:53")
	}
	for _, d := range strings.Split(dns, ",") {
		d = strings.TrimSpace(d)
		if len(d) == 0 {
			continue
		}
		appendHijack(net.JoinHostPort(d, "53"))
	}
	return dnsHijack
}

func parseDNSHijack(dns string) []string {
	return parseDNSHijackForOS(tunBuildGOOS, dns)
}

func buildTunOptions(
	fd int,
	device string,
	stack C.TUNStack,
	address string,
	dns string,
) (LC.Tun, error) {
	return buildTunOptionsForOS(tunBuildGOOS, fd, device, stack, address, dns)
}

func buildTunOptionsForOS(
	goos string,
	fd int,
	device string,
	stack C.TUNStack,
	address string,
	dns string,
) (LC.Tun, error) {
	prefix4, prefix6, err := parsePrefixesForOS(goos, address)
	if err != nil {
		return LC.Tun{}, err
	}
	return LC.Tun{
		Enable:              true,
		Device:              device,
		Stack:               stack,
		DNSHijack:           parseDNSHijackForOS(goos, dns),
		AutoRoute:           false,
		AutoDetectInterface: false,
		Inet4Address:        prefix4,
		Inet6Address:        prefix6,
		MTU:                 9000,
		FileDescriptor:      fd,
	}, nil
}
