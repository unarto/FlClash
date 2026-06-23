package main

import "testing"

func TestShouldKeepConvertedProxyName(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		keep bool
	}{
		{name: "剩余流量：2.93 TB", keep: false},
		{name: "距离下次重置剩余：14 天", keep: false},
		{name: "套餐到期：2028-02-04", keep: false},
		{name: "🇺🇸美国洛杉矶1号", keep: true},
		{name: "DIRECT", keep: true},
		{name: "  ", keep: false},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := shouldKeepConvertedProxyName(tt.name); got != tt.keep {
				t.Fatalf("shouldKeepConvertedProxyName(%q) = %v, want %v", tt.name, got, tt.keep)
			}
		})
	}
}
