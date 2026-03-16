import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _russia2026Dns = Dns(
  enable: true,
  preferH3: false,
  useHosts: true,
  useSystemHosts: false,
  respectRules: true,
  ipv6: false,
  defaultNameserver: ['1.1.1.1', '8.8.8.8'],
  enhancedMode: DnsMode.fakeIp,
  fakeIpRange: '198.18.0.1/16',
  fakeIpFilter: [],
  nameserverPolicy: {},
  nameserver: ['https://1.1.1.1/dns-query', 'tls://1.1.1.1:853'],
  fallback: ['tls://8.8.4.4', 'tls://1.1.1.1'],
  proxyServerNameserver: ['https://1.1.1.1/dns-query'],
  fallbackFilter: FallbackFilter(
    geoip: false,
    geoipCode: '',
    geosite: [],
    ipcidr: ['240.0.0.0/4'],
    domain: [],
  ),
);

const _russia2026Tun = Tun(
  enable: true,
  stack: TunStack.gvisor,
  dnsHijack: ['any:53'],
);

const _russia2026Rules = [
  'DST-PORT,443,REJECT,udp',
  'GEOSITE,google,Proxy',
  'GEOIP,ru,DIRECT',
  'DOMAIN-SUFFIX,ru,DIRECT',
  'DOMAIN-SUFFIX,xn--p1ai,DIRECT',
  'DOMAIN-SUFFIX,su,DIRECT',
  'DOMAIN-KEYWORD,yandex,DIRECT',
];

void applyRussia2026Preset(WidgetRef ref) {
  ref.read(patchClashConfigProvider.notifier).update(
    (state) => state.copyWith(
      dns: _russia2026Dns,
      tun: _russia2026Tun,
      mode: Mode.rule,
      allowLan: false,
      logLevel: LogLevel.warning,
      ipv6: false,
      unifiedDelay: true,
      tcpConcurrent: false,
    ),
  );
  ref.read(overrideDnsProvider.notifier).value = true;
  ref.read(vpnSettingProvider.notifier).update(
    (state) => state.copyWith(
      enable: true, systemProxy: false, ipv6: false, allowBypass: true,
    ),
  );
  ref.read(networkSettingProvider.notifier).update(
    (state) => state.copyWith(systemProxy: false),
  );
  final globalRules = ref.read(globalRulesProvider.notifier);
  for (final ruleValue in _russia2026Rules.reversed) {
    globalRules.put(Rule.value(ruleValue));
  }
}

void resetRussia2026Preset(WidgetRef ref) {
  ref.read(patchClashConfigProvider.notifier).update(
    (state) => state.copyWith(
      dns: const Dns(),
      tun: const Tun(),
      mode: Mode.rule,
      allowLan: false,
      logLevel: LogLevel.error,
      ipv6: false,
      unifiedDelay: true,
      tcpConcurrent: true,
    ),
  );
  ref.read(overrideDnsProvider.notifier).value = false;
  ref.read(vpnSettingProvider.notifier).update(
    (state) => state.copyWith(
      enable: true, systemProxy: true, ipv6: false, allowBypass: true,
    ),
  );
  ref.read(networkSettingProvider.notifier).update(
    (state) => state.copyWith(systemProxy: true),
  );
  final globalRules = ref.read(globalRulesProvider.notifier);
  final currentRules = ref.read(globalRulesProvider).value ?? [];
  final presetRuleValues = _russia2026Rules.toSet();
  final rulesToDelete = currentRules
      .where((r) => presetRuleValues.contains(r.value))
      .map((r) => r.id);
  if (rulesToDelete.isNotEmpty) {
    globalRules.delAll(rulesToDelete);
  }
}

class Russia2026PresetItem extends ConsumerWidget {
  const Russia2026PresetItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListItem(
      leading: const Icon(Icons.flag, color: Color(0xFF4A90D9)),
      title: const Text('Россия 2026'),
      subtitle: const Text('Настройки для работы в России'),
      onTap: () async {
        final res = await globalState.showMessage(
          title: 'Россия 2026',
          message: const TextSpan(
            text: 'Применить настройки для России?\n\n'
                'YouTube, Telegram, Gemini — через VPN\n'
                'Банки и Госуслуги — напрямую\n'
                'DNS — через Cloudflare',
          ),
        );
        if (res != true) return;
        applyRussia2026Preset(ref);
      },
    );
  }
}
