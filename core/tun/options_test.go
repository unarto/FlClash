package tun

import (
	"github.com/metacubex/mihomo/constant"
	"testing"
)

func TestBuildTunOptionsParsesCIDRPrefixesAndDnsHijack(t *testing.T) {
	options, err := buildTunOptions(
		9,
		"FlClash",
		constant.TunSystem,
		"172.19.0.1/30,fdfe:dcba:9876::1/126",
		"172.19.0.2,fdfe:dcba:9876::2",
	)
	if err != nil {
		t.Fatalf("buildTunOptions returned error: %v", err)
	}

	if options.FileDescriptor != 9 {
		t.Fatalf("unexpected file descriptor: %d", options.FileDescriptor)
	}
	if len(options.Inet4Address) != 1 || options.Inet4Address[0].String() != "172.19.0.1/30" {
		t.Fatalf("unexpected IPv4 prefixes: %#v", options.Inet4Address)
	}
	if len(options.Inet6Address) != 1 || options.Inet6Address[0].String() != "fdfe:dcba:9876::1/126" {
		t.Fatalf("unexpected IPv6 prefixes: %#v", options.Inet6Address)
	}
	if len(options.DNSHijack) != 2 ||
		options.DNSHijack[0] != "172.19.0.2:53" ||
		options.DNSHijack[1] != "[fdfe:dcba:9876::2]:53" {
		t.Fatalf("unexpected dns hijack config: %#v", options.DNSHijack)
	}
}

func TestBuildTunOptionsRejectsBareIpAddress(t *testing.T) {
	_, err := buildTunOptionsForOS(
		"android",
		9,
		"FlClash",
		constant.TunSystem,
		"172.19.0.1",
		"172.19.0.2",
	)
	if err == nil {
		t.Fatal("expected buildTunOptions to reject bare IP address")
	}
}

func TestBuildTunOptionsAllowsBareIpAddressOnOhos(t *testing.T) {
	options, err := buildTunOptionsForOS(
		"ohos",
		9,
		"FlClash",
		constant.TunSystem,
		"172.19.0.1,fdfe:dcba:9876::1",
		"172.19.0.2,fdfe:dcba:9876::2",
	)
	if err != nil {
		t.Fatalf("buildTunOptionsForOS returned error: %v", err)
	}

	if len(options.Inet4Address) != 1 || options.Inet4Address[0].String() != "172.19.0.1/30" {
		t.Fatalf("unexpected IPv4 prefixes: %#v", options.Inet4Address)
	}
	if len(options.Inet6Address) != 1 || options.Inet6Address[0].String() != "fdfe:dcba:9876::1/126" {
		t.Fatalf("unexpected IPv6 prefixes: %#v", options.Inet6Address)
	}
	if len(options.DNSHijack) != 3 ||
		options.DNSHijack[0] != "0.0.0.0:53" ||
		options.DNSHijack[1] != "172.19.0.2:53" ||
		options.DNSHijack[2] != "[fdfe:dcba:9876::2]:53" {
		t.Fatalf("unexpected dns hijack config on ohos: %#v", options.DNSHijack)
	}
}

func TestParseDNSHijackUsesProvidedDnsOnOhos(t *testing.T) {
	got := parseDNSHijackForOS("ohos", "172.19.0.2,fdfe:dcba:9876::2")

	if len(got) != 3 ||
		got[0] != "0.0.0.0:53" ||
		got[1] != "172.19.0.2:53" ||
		got[2] != "[fdfe:dcba:9876::2]:53" {
		t.Fatalf("unexpected dns hijack config on ohos: %#v", got)
	}
}
