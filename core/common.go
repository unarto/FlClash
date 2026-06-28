package main

import (
	b "bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/batch"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

var (
	currentConfig *config.Config
	version       = 0
	isRunning     = false
	runLock       sync.Mutex
	mBatch, _     = batch.New[bool](context.Background(), batch.WithConcurrencyNum[bool](50))
	debugError    = false
)

func getExternalProvidersRaw() map[string]cp.Provider {
	eps := make(map[string]cp.Provider)
	for n, p := range tunnel.Providers() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	for n, p := range tunnel.RuleProviders() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	return eps
}

func toExternalProvider(p cp.Provider) (*ExternalProvider, error) {
	switch p.(type) {
	case *provider.ProxySetProvider:
		psp := p.(*provider.ProxySetProvider)
		return &ExternalProvider{
			Name:             psp.Name(),
			Type:             psp.Type().String(),
			VehicleType:      psp.VehicleType().String(),
			Count:            psp.Count(),
			UpdateAt:         psp.UpdatedAt(),
			Path:             psp.Vehicle().Path(),
			SubscriptionInfo: psp.GetSubscriptionInfo(),
		}, nil
	case *rp.RuleSetProvider:
		rsp := p.(*rp.RuleSetProvider)
		return &ExternalProvider{
			Name:        rsp.Name(),
			Type:        rsp.Type().String(),
			VehicleType: rsp.VehicleType().String(),
			Count:       rsp.Count(),
			UpdateAt:    rsp.UpdatedAt(),
			Path:        rsp.Vehicle().Path(),
		}, nil
	default:
		return nil, errors.New("not external provider")
	}
}

func sideUpdateExternalProvider(p cp.Provider, bytes []byte) error {
	switch p.(type) {
	case *provider.ProxySetProvider:
		psp := p.(*provider.ProxySetProvider)
		_, _, err := psp.SideUpdate(bytes)
		if err == nil {
			return err
		}
		return nil
	case rp.RuleSetProvider:
		rsp := p.(*rp.RuleSetProvider)
		_, _, err := rsp.SideUpdate(bytes)
		if err == nil {
			return err
		}
		return nil
	default:
		return errors.New("not external provider")
	}
}

func updateListeners() {
	if !isRunning {
		return
	}
	if currentConfig == nil {
		return
	}
	listeners := currentConfig.Listeners
	general := currentConfig.General
	listener.PatchInboundListeners(listeners, tunnel.Tunnel, true)

	allowLan := general.AllowLan
	listener.SetAllowLan(allowLan)
	inbound.SetSkipAuthPrefixes(general.SkipAuthPrefixes)
	inbound.SetAllowedIPs(general.LanAllowedIPs)
	inbound.SetDisAllowedIPs(general.LanDisAllowedIPs)

	bindAddress := general.BindAddress
	listener.SetBindAddress(bindAddress)
	listener.ReCreateHTTP(general.Port, tunnel.Tunnel)
	listener.ReCreateSocks(general.SocksPort, tunnel.Tunnel)
	listener.ReCreateRedir(general.RedirPort, tunnel.Tunnel)
	listener.ReCreateTProxy(general.TProxyPort, tunnel.Tunnel)
	listener.ReCreateMixed(general.MixedPort, tunnel.Tunnel)
	listener.ReCreateShadowSocks(general.ShadowSocksConfig, tunnel.Tunnel)
	listener.ReCreateVmess(general.VmessConfig, tunnel.Tunnel)
	listener.ReCreateTuic(general.TuicServer, tunnel.Tunnel)
	if !features.Android {
		listener.ReCreateTun(general.Tun, tunnel.Tunnel)
	}
}

func stopListeners() {
	listener.StopListener()
}

func patchSelectGroup(mapping map[string]string) {
	for name, proxy := range tunnel.AllProxies() {
		outbound, ok := proxy.(*adapter.Proxy)
		if !ok {
			continue
		}

		selector, ok := outbound.ProxyAdapter.(outboundgroup.SelectAble)
		if !ok {
			continue
		}

		selected, exist := mapping[name]
		if !exist {
			continue
		}

		selector.ForceSet(selected)
	}
}

func defaultSetupParams() *SetupParams {
	return &SetupParams{
		TestURL:     "https://www.gstatic.com/generate_204",
		SelectedMap: map[string]string{},
	}
}

func readFile(path string) ([]byte, error) {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	return data, err
}

func updateConfig(params *UpdateParams) {
	runLock.Lock()
	defer runLock.Unlock()
	general := currentConfig.General
	if params.MixedPort != nil {
		general.MixedPort = *params.MixedPort
	}
	if params.Sniffing != nil {
		general.Sniffing = *params.Sniffing
		tunnel.SetSniffing(general.Sniffing)
	}
	if params.FindProcessMode != nil {
		general.FindProcessMode = *params.FindProcessMode
		tunnel.SetFindProcessMode(general.FindProcessMode)
	}
	if params.TCPConcurrent != nil {
		general.TCPConcurrent = *params.TCPConcurrent
		dialer.SetTcpConcurrent(general.TCPConcurrent)
	}
	if params.Interface != nil {
		general.Interface = *params.Interface
		dialer.DefaultInterface.Store(general.Interface)
	}
	if params.UnifiedDelay != nil {
		general.UnifiedDelay = *params.UnifiedDelay
		adapter.UnifiedDelay.Store(general.UnifiedDelay)
	}
	if params.Mode != nil {
		general.Mode = *params.Mode
		tunnel.SetMode(general.Mode)
	}
	if params.LogLevel != nil {
		general.LogLevel = *params.LogLevel
		log.SetLevel(general.LogLevel)
	}
	if params.IPv6 != nil {
		general.IPv6 = *params.IPv6
		resolver.DisableIPv6 = !general.IPv6
	}
	if params.ExternalController != nil {
		currentConfig.Controller.ExternalController = *params.ExternalController
		route.ReCreateServer(&route.Config{
			Addr: currentConfig.Controller.ExternalController,
		})
	}

	if params.Tun != nil {
		general.Tun.Enable = params.Tun.Enable
		general.Tun.AutoRoute = *params.Tun.AutoRoute
		general.Tun.Device = *params.Tun.Device
		general.Tun.RouteAddress = *params.Tun.RouteAddress
		general.Tun.DNSHijack = *params.Tun.DNSHijack
		general.Tun.Stack = *params.Tun.Stack
	}

	updateListeners()
}

func debugConfigInput(path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		debugCoreLog("applyConfig read config failed path=%s err=%v", path, err)
		return
	}
	lines := strings.Split(string(data), "\n")
	var dnsListenLine string
	var nameserverLine string
	var defaultNameserverLine string
	var nameserverPolicyLine string
	var directNameserverLine string
	var rulesHead []string
	var rawInterestingLines []string
	var rawSpecialRules []string
	inNameserver := false
	inDefaultNameserver := false
	inRules := false
	for index, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "listen:") && dnsListenLine == "" {
			dnsListenLine = trimmed
		}
		if strings.HasPrefix(trimmed, "nameserver:") && nameserverLine == "" {
			nameserverLine = trimmed
			inNameserver = true
			inDefaultNameserver = false
			continue
		}
		if strings.HasPrefix(trimmed, "default-nameserver:") && defaultNameserverLine == "" {
			defaultNameserverLine = trimmed
			inDefaultNameserver = true
			inNameserver = false
			continue
		}
		if inNameserver {
			if strings.HasPrefix(trimmed, "- ") {
				nameserverLine = strings.TrimSpace(nameserverLine + " " + trimmed)
				continue
			}
			if trimmed != "" {
				inNameserver = false
			}
		}
		if inDefaultNameserver {
			if strings.HasPrefix(trimmed, "- ") {
				defaultNameserverLine = strings.TrimSpace(defaultNameserverLine + " " + trimmed)
				continue
			}
			if trimmed != "" {
				inDefaultNameserver = false
			}
		}
		if strings.HasPrefix(trimmed, "nameserver-policy:") && nameserverPolicyLine == "" {
			nameserverPolicyLine = trimmed
		}
		if strings.HasPrefix(trimmed, "direct-nameserver:") && directNameserverLine == "" {
			directNameserverLine = trimmed
		}
		lower := strings.ToLower(trimmed)
		if strings.Contains(lower, "httpdns") ||
			strings.Contains(lower, "browsercfg-drcn.cloud.dbankcloud.cn") ||
			strings.Contains(lower, "youtube") {
			rawInterestingLines = append(rawInterestingLines, fmt.Sprintf("%d:%s", index+1, trimmed))
		}
		if strings.HasPrefix(trimmed, "rules:") {
			inRules = true
			continue
		}
		if inRules {
			if strings.HasPrefix(trimmed, "- ") {
				rule := strings.TrimPrefix(trimmed, "- ")
				rulesHead = append(rulesHead, rule)
				if strings.Contains(rule, "RULE-SET") || strings.Contains(rule, "GEOSITE") {
					rawSpecialRules = append(rawSpecialRules, fmt.Sprintf("%d:%s", index+1, rule))
				}
				if len(rulesHead) >= 14 {
					continue
				}
				continue
			}
			if trimmed != "" {
				break
			}
		}
	}
	debugCoreLog(
		"applyConfig input path=%s bytes=%d dnsListen=%s nameserver=%s defaultNameserver=%s nameserverPolicy=%s directNameserver=%s rulesHead=%s",
		path,
		len(data),
		dnsListenLine,
		nameserverLine,
		defaultNameserverLine,
		nameserverPolicyLine,
		directNameserverLine,
		strings.Join(rulesHead, " || "),
	)
	debugCoreLog(
		"applyConfig rawInteresting path=%s interesting=%s specialRules=%s",
		path,
		strings.Join(rawInterestingLines, " || "),
		strings.Join(rawSpecialRules, " || "),
	)
}

func applyConfig(params *SetupParams) error {
	runtime.GC()
	runLock.Lock()
	defer runLock.Unlock()
	var err error
	constant.DefaultTestURL = params.TestURL
	configPath := filepath.Join(constant.Path.HomeDir(), "config.yaml")
	if fileInfo, statErr := os.Stat(configPath); statErr != nil {
		debugCoreLog("applyConfig configPath=%s statErr=%v", configPath, statErr)
	} else {
		debugCoreLog(
			"applyConfig configPath=%s size=%d mode=%s",
			configPath,
			fileInfo.Size(),
			fileInfo.Mode(),
		)
	}
	debugConfigInput(configPath)
	currentConfig, err = executor.ParseWithPath(configPath)
	if err != nil {
		debugCoreLog("applyConfig parse failed configPath=%s err=%v", configPath, err)
		currentConfig, _ = config.ParseRawConfig(config.DefaultRawConfig())
		debugCoreLog("applyConfig fallback to default raw config")
	} else {
		debugCoreLog(
			"applyConfig parsed configPath=%s mixedPort=%d port=%d socksPort=%d allowLan=%v controller=%s",
			configPath,
			currentConfig.General.MixedPort,
			currentConfig.General.Port,
			currentConfig.General.SocksPort,
			currentConfig.General.AllowLan,
			currentConfig.Controller.ExternalController,
		)
		debugCoreLog(
			"applyConfig dns listen=%s nameserver=%v defaultNameserver=%v enhancedMode=%v proxyServerNameserver=%v directNameServer=%v directFollowPolicy=%v dnsHijack=%v",
			currentConfig.DNS.Listen,
			currentConfig.DNS.NameServer,
			currentConfig.DNS.DefaultNameserver,
			currentConfig.DNS.EnhancedMode,
			currentConfig.DNS.ProxyServerNameserver,
			currentConfig.DNS.DirectNameServer,
			currentConfig.DNS.DirectFollowPolicy,
			currentConfig.General.Tun.DNSHijack,
		)
		ruleCount := len(currentConfig.Rules)
		ruleHead := 12
		if ruleCount < ruleHead {
			ruleHead = ruleCount
		}
		for i := 0; i < ruleHead; i++ {
			rule := currentConfig.Rules[i]
			debugCoreLog(
				"applyConfig rule[%d]=type=%s payload=%s adapter=%s",
				i,
				rule.RuleType().String(),
				rule.Payload(),
				rule.Adapter(),
			)
		}
	}
	hub.ApplyConfig(currentConfig)
	patchSelectGroup(params.SelectedMap)
	updateListeners()
	return err
}

func UnmarshalJson(data []byte, v any) error {
	decoder := json.NewDecoder(b.NewReader(data))
	decoder.UseNumber()
	err := decoder.Decode(v)
	return err
}

func logError(format string, args ...interface{}) {
	log.Errorln(format, args...)
	if debugError {
		fmt.Fprintf(os.Stderr, "[ERROR] "+format+"\n", args...)
	}
}
