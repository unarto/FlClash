package main

import (
	"errors"
	"regexp"
	"strings"

	convert "github.com/metacubex/mihomo/common/convert"
	"github.com/metacubex/mihomo/config"
	"gopkg.in/yaml.v3"
)

var convertedSubscriptionMetaNamePattern = regexp.MustCompile(
	`^(剩余流量：|距离下次重置剩余：|套餐到期：)`,
)

func shouldKeepConvertedProxyName(name string) bool {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" {
		return false
	}
	return !convertedSubscriptionMetaNamePattern.MatchString(trimmed)
}

func handleConvertSubscription(data string) (string, error) {
	proxies, err := convert.ConvertsV2Ray([]byte(data))
	if err != nil {
		return "", err
	}
	if len(proxies) == 0 {
		return "", errors.New("no proxies found in subscription")
	}

	proxyNames := make([]string, 0, len(proxies)+1)
	filteredProxies := make([]map[string]any, 0, len(proxies))
	for _, proxy := range proxies {
		name, ok := proxy["name"].(string)
		if !ok || !shouldKeepConvertedProxyName(name) {
			continue
		}
		filteredProxies = append(filteredProxies, proxy)
		proxyNames = append(proxyNames, name)
	}
	if len(proxyNames) == 0 {
		return "", errors.New("no named proxies found in subscription")
	}

	groupProxies := append(append([]string{}, proxyNames...), "DIRECT")
	rawConfig := map[string]any{
		"proxies": filteredProxies,
		"proxy-groups": []map[string]any{
			{
				"name":    "PROXY",
				"type":    "select",
				"proxies": groupProxies,
			},
		},
		"rules": []string{"MATCH,PROXY"},
	}

	buf, err := yaml.Marshal(rawConfig)
	if err != nil {
		return "", err
	}
	if _, err := config.UnmarshalRawConfig(buf); err != nil {
		return "", err
	}
	return string(buf), nil
}
