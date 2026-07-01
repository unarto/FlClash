import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to round-trip a model through JSON encode/decode.
T roundTrip<T>(
  Object? Function() toJson,
  T Function(Map<String, Object?> json) fromJson,
) {
  final encoded = jsonEncode(toJson());
  final decoded = jsonDecode(encoded) as Map<String, Object?>;
  return fromJson(decoded);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PackageInfoExtension', () {
    test('default ua uses clashmeta-compatible token', () {
      final info = PackageInfo(
        appName: appName,
        packageName: packageName,
        version: '0.8.93',
        buildNumber: '1',
      );
      final ua = info.ua;
      expect(ua, contains('FlClash/v0.8.93'));
      expect(ua, contains('ClashMeta'));
      expect(ua, contains('Platform/${Platform.operatingSystem}'));
      expect(ua, isNot(contains('clash-verge')));
    });

    test('provider compatible ua uses subscription-safe token on ohos', () {
      final info = PackageInfo(
        appName: appName,
        packageName: packageName,
        version: '0.8.93',
        buildNumber: '1',
      );

      expect(
        resolveProviderCompatibleUa(isOhos: true, ua: info.ua),
        'clash.meta/1.10.0',
      );
    });

    test('provider compatible ua preserves browser ua on non-ohos', () {
      final info = PackageInfo(
        appName: appName,
        packageName: packageName,
        version: '0.8.93',
        buildNumber: '1',
      );

      expect(
        resolveProviderCompatibleUa(isOhos: false, ua: info.ua),
        info.ua,
      );
    });
  });

  group('AppSettingProps JSON round-trip', () {
    test('default values survive round-trip', () {
      const props = AppSettingProps();
      final restored = roundTrip(
        () => props.toJson(),
        AppSettingProps.fromJson,
      );
      expect(restored.onlyStatisticsProxy, false);
      expect(restored.autoLaunch, false);
      expect(restored.silentLaunch, false);
      expect(restored.autoRun, false);
      expect(restored.openLogs, false);
      expect(restored.closeConnections, true);
      expect(restored.isAnimateToPage, true);
      expect(restored.autoCheckUpdate, true);
      expect(restored.showLabel, false);
      expect(restored.minimizeOnExit, true);
      expect(restored.restoreStrategy, RestoreStrategy.compatible);
      expect(restored.testUrl, defaultTestUrl);
    });

    test('custom values survive round-trip', () {
      const props = AppSettingProps(
        locale: 'zh_CN',
        onlyStatisticsProxy: true,
        autoLaunch: true,
        closeConnections: false,
        testUrl: 'https://custom.test',
      );
      final restored = roundTrip(
        () => props.toJson(),
        AppSettingProps.fromJson,
      );
      expect(restored.locale, 'zh_CN');
      expect(restored.onlyStatisticsProxy, true);
      expect(restored.autoLaunch, true);
      expect(restored.closeConnections, false);
      expect(restored.testUrl, 'https://custom.test');
    });

    test('safeFromJson returns default on null', () {
      final result = AppSettingProps.safeFromJson(null);
      expect(result, isA<AppSettingProps>());
      expect(result.onlyStatisticsProxy, false);
    });

    test('safeFromJson returns default on invalid JSON', () {
      final result = AppSettingProps.safeFromJson({'invalid': 'data'});
      expect(result, isA<AppSettingProps>());
    });
  });

  group('GeoXUrl defaults', () {
    test('uses jsdelivr mirror defaults for geodata downloads', () {
      expect(
        defaultGeoXUrl.mmdb,
        'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb',
      );
      expect(
        defaultGeoXUrl.asn,
        'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/GeoLite2-ASN.mmdb',
      );
      expect(
        defaultGeoXUrl.geoip,
        'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat',
      );
      expect(
        defaultGeoXUrl.geosite,
        'https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat',
      );
    });
  });

  group('normalizeOhosDnsConfig', () {
    test('preserves fake-ip enhanced mode', () {
      final dns = normalizeOhosDnsConfig(
        {
          'enable': true,
          'enhanced-mode': 'fake-ip',
          'nameserver': ['https://1.1.1.1/dns-query'],
        },
        const Dns(
          enable: true,
          enhancedMode: DnsMode.fakeIp,
          nameserver: ['https://1.1.1.1/dns-query'],
        ),
      );

      expect(dns['enhanced-mode'], 'fake-ip');
      expect(dns['enable'], true);
      expect(dns['listen'], defaultDns.listen);
      expect(dns['direct-nameserver'], ['system://']);
      expect(dns['direct-nameserver-follow-policy'], false);
    });

    test('fills listen and nameserver when missing', () {
      final dns = normalizeOhosDnsConfig(
        {'enable': false, 'enhanced-mode': 'redir-host'},
        const Dns(
          enable: true,
          listen: '127.0.0.1:5353',
          nameserver: ['system://'],
        ),
      );

      expect(dns['enable'], true);
      expect(dns['listen'], '127.0.0.1:5353');
      expect(dns['nameserver'], ['system://']);
    });

    test('keeps legacy default 1053 listener on ohos', () {
      final dns = normalizeOhosDnsConfig(
        {
          'enable': true,
          'listen': '0.0.0.0:1053',
          'enhanced-mode': 'redir-host',
          'nameserver': ['https://1.1.1.1/dns-query'],
        },
        const Dns(
          enable: true,
          listen: '0.0.0.0:1053',
          enhancedMode: DnsMode.redirHost,
          nameserver: ['https://1.1.1.1/dns-query'],
        ),
      );

      expect(dns['listen'], '0.0.0.0:1053');
    });

    test('prefers fallback over default cn-only doh nameservers for ohos', () {
      final dns = normalizeOhosDnsConfig(
        {
          'enable': true,
          'listen': '0.0.0.0:1053',
          'enhanced-mode': 'redir-host',
          'nameserver': [
            'https://doh.pub/dns-query',
            'https://dns.alidns.com/dns-query',
          ],
        },
        const Dns(
          enable: true,
          listen: '0.0.0.0:1053',
          enhancedMode: DnsMode.redirHost,
          nameserver: [
            'https://doh.pub/dns-query',
            'https://dns.alidns.com/dns-query',
          ],
          fallback: ['tls://8.8.4.4', 'tls://1.1.1.1'],
        ),
      );

      expect(dns['nameserver'], ['tls://8.8.4.4', 'tls://1.1.1.1']);
      expect(dns.containsKey('respect-rules'), false);
    });

    test(
      'prefers fallback over cn-only doh nameservers even with appended system dns',
      () {
        final dns = normalizeOhosDnsConfig(
          {
            'enable': true,
            'listen': '0.0.0.0:1053',
            'enhanced-mode': 'redir-host',
            'nameserver': [
              'https://doh.pub/dns-query',
              'https://dns.alidns.com/dns-query',
              'system://',
            ],
          },
          const Dns(
            enable: true,
            listen: '0.0.0.0:1053',
            enhancedMode: DnsMode.redirHost,
            nameserver: [
              'https://doh.pub/dns-query',
              'https://dns.alidns.com/dns-query',
            ],
            fallback: ['tls://8.8.4.4', 'tls://1.1.1.1'],
          ),
        );

        expect(dns['nameserver'], ['tls://8.8.4.4', 'tls://1.1.1.1']);
      },
    );

    test('prefers fallback over cn-only plain dns resolvers for ohos', () {
      final dns = normalizeOhosDnsConfig(
        {
          'enable': true,
          'listen': '0.0.0.0:1053',
          'enhanced-mode': 'redir-host',
          'nameserver': ['223.5.5.5', '119.29.29.29', '114.114.114.114'],
        },
        const Dns(
          enable: true,
          listen: '0.0.0.0:1053',
          enhancedMode: DnsMode.redirHost,
          nameserver: ['223.5.5.5', '119.29.29.29', '114.114.114.114'],
          fallback: ['tls://8.8.4.4', 'tls://1.1.1.1'],
        ),
      );

      expect(dns['nameserver'], ['tls://8.8.4.4', 'tls://1.1.1.1']);
      expect(dns.containsKey('respect-rules'), false);
    });

    test(
      'does not inject fallback when ohos resolvers have no custom fallback',
      () {
        final dns = normalizeOhosDnsConfig(
          {
            'enable': true,
            'listen': '0.0.0.0:1053',
            'enhanced-mode': 'redir-host',
            'nameserver': ['223.5.5.5', '119.29.29.29'],
          },
          const Dns(
            enable: true,
            listen: '0.0.0.0:1053',
            enhancedMode: DnsMode.redirHost,
            nameserver: ['223.5.5.5', '119.29.29.29'],
            fallback: [],
          ),
        );

        expect(dns['nameserver'], ['223.5.5.5', '119.29.29.29']);
        expect(dns.containsKey('respect-rules'), false);
      },
    );

    test('preserves explicit direct nameserver when already configured', () {
      final dns = normalizeOhosDnsConfig(
        {
          'enable': true,
          'listen': '0.0.0.0:1053',
          'enhanced-mode': 'redir-host',
          'nameserver': ['https://1.1.1.1/dns-query'],
          'direct-nameserver': ['tls://9.9.9.9'],
          'direct-nameserver-follow-policy': true,
        },
        const Dns(
          enable: true,
          listen: '0.0.0.0:1053',
          enhancedMode: DnsMode.redirHost,
          nameserver: ['https://1.1.1.1/dns-query'],
        ),
      );

      expect(dns['direct-nameserver'], ['tls://9.9.9.9']);
      expect(dns['direct-nameserver-follow-policy'], true);
    });

    test(
      'injects Huawei bootstrap domains into explicit direct dns policy',
      () {
        final dns = normalizeOhosDnsConfig(
          {
            'enable': true,
            'listen': '0.0.0.0:1053',
            'enhanced-mode': 'redir-host',
            'nameserver': ['https://1.1.1.1/dns-query'],
          },
          const Dns(
            enable: true,
            listen: '0.0.0.0:1053',
            enhancedMode: DnsMode.redirHost,
            nameserver: ['https://1.1.1.1/dns-query'],
          ),
        );

        final policy = Map<String, dynamic>.from(
          dns['nameserver-policy'] ?? const <String, dynamic>{},
        );
        expect(policy['browsercfg-drcn.cloud.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['browserr-drcn.dbankcdn.cn'], ['223.5.5.5']);
        expect(policy['configserver-drcn.platform.dbankcloud.cn'], [
          '223.5.5.5',
        ]);
        expect(policy['httpdns.platform.dbankcloud.com'], ['223.5.5.5']);
        expect(policy['httpdns-browser.platform.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['nps-drcn.platform.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['+.grs.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['+.grs.dbankcloud.com'], ['223.5.5.5']);
        expect(dns['direct-nameserver'], ['system://']);
      },
    );

    test('excludes OHOS browser bootstrap domains from fake-ip answers', () {
      final dns = normalizeOhosDnsConfig(
        {
          'enable': true,
          'listen': '0.0.0.0:1053',
          'enhanced-mode': 'fake-ip',
          'nameserver': ['https://1.1.1.1/dns-query'],
        },
        const Dns(
          enable: true,
          listen: '0.0.0.0:1053',
          enhancedMode: DnsMode.fakeIp,
          nameserver: ['https://1.1.1.1/dns-query'],
        ),
      );

      final fakeIpFilter = List<String>.from(
        dns['fake-ip-filter'] ?? const <String>[],
      );
      expect(fakeIpFilter, contains('browserr-drcn.dbankcdn.cn'));
      expect(
        fakeIpFilter,
        contains('configserver-drcn.platform.dbankcloud.cn'),
      );
      expect(fakeIpFilter, contains('httpdns.platform.dbankcloud.com'));
      expect(fakeIpFilter, contains('contentcenter-drcn.cloud.dbankcloud.cn'));
      expect(fakeIpFilter, contains('nps-drcn.platform.dbankcloud.cn'));
      expect(fakeIpFilter, contains('*.grs.dbankcloud.cn'));
      expect(fakeIpFilter, contains('*.grs.dbankcloud.com'));
      // YouTube is intentionally NOT in the fake-ip-filter: it must get a
      // fake-ip so it routes through the proxy by domain (the OHOS DNS
      // de-poisoning fix in lib/common/task.dart). Keep it out of the filter.
      expect(fakeIpFilter, isNot(contains('youtube.com')));
      expect(fakeIpFilter, isNot(contains('*.youtube.com')));
      expect(fakeIpFilter, isNot(contains('www.youtube.com')));
      expect(fakeIpFilter, isNot(contains('m.youtube.com')));
    });

    test(
      'preserves explicit nameserver policy entries while adding missing Huawei defaults',
      () {
        final dns = normalizeOhosDnsConfig(
          {
            'enable': true,
            'listen': '0.0.0.0:1053',
            'enhanced-mode': 'redir-host',
            'nameserver': ['https://1.1.1.1/dns-query'],
            'nameserver-policy': {
              'browsercfg-drcn.cloud.dbankcloud.cn': ['tls://9.9.9.9'],
              'example.com': ['system://'],
            },
          },
          const Dns(
            enable: true,
            listen: '0.0.0.0:1053',
            enhancedMode: DnsMode.redirHost,
            nameserver: ['https://1.1.1.1/dns-query'],
          ),
        );

        final policy = Map<String, dynamic>.from(
          dns['nameserver-policy'] ?? const <String, dynamic>{},
        );
        expect(policy['browsercfg-drcn.cloud.dbankcloud.cn'], [
          'tls://9.9.9.9',
        ]);
        expect(policy['example.com'], ['system://']);
        expect(policy['browserr-drcn.dbankcdn.cn'], ['223.5.5.5']);
        expect(policy['configserver-drcn.platform.dbankcloud.cn'], [
          '223.5.5.5',
        ]);
        expect(policy['httpdns.platform.dbankcloud.com'], ['223.5.5.5']);
        expect(policy['httpdns-browser.platform.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['nps-drcn.platform.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['+.grs.dbankcloud.cn'], ['223.5.5.5']);
        expect(policy['+.grs.dbankcloud.com'], ['223.5.5.5']);
      },
    );

    test(
      'preserves explicit fake-ip-filter entries while adding OHOS browser defaults',
      () {
        final dns = normalizeOhosDnsConfig(
          {
            'enable': true,
            'listen': '0.0.0.0:1053',
            'enhanced-mode': 'fake-ip',
            'nameserver': ['https://1.1.1.1/dns-query'],
            'fake-ip-filter': [
              'example.com',
              'httpdns.platform.dbankcloud.com',
            ],
          },
          const Dns(
            enable: true,
            listen: '0.0.0.0:1053',
            enhancedMode: DnsMode.fakeIp,
            nameserver: ['https://1.1.1.1/dns-query'],
          ),
        );

        final fakeIpFilter = List<String>.from(
          dns['fake-ip-filter'] ?? const <String>[],
        );
        expect(fakeIpFilter, contains('example.com'));
        expect(
          fakeIpFilter
              .where((item) => item == 'httpdns.platform.dbankcloud.com')
              .length,
          1,
        );
        expect(fakeIpFilter, contains('browserr-drcn.dbankcdn.cn'));
        expect(
          fakeIpFilter,
          contains('configserver-drcn.platform.dbankcloud.cn'),
        );
        expect(fakeIpFilter, contains('nps-drcn.platform.dbankcloud.cn'));
        expect(fakeIpFilter, contains('*.grs.dbankcloud.cn'));
      },
    );
  });

  group('prependOhosDirectRules', () {
    test('keeps Huawei browser bootstrap and HttpDNS direct rules', () {
      final rules = prependOhosDirectRules(['MATCH,GLOBAL']);

      expect(
        rules,
        contains('DOMAIN,browsercfg-drcn.cloud.dbankcloud.cn,DIRECT'),
      );
      expect(rules, contains('DOMAIN,httpdns.platform.dbankcloud.com,DIRECT'));
      expect(
        rules,
        contains(
          contains('DOMAIN,httpdns-browser.platform.dbankcloud.cn,DIRECT'),
        ),
      );
    });
  });

  group('prependOhosDirectRules', () {
    test('prepends Huawei browser direct rules ahead of user rules', () {
      final rules = prependOhosDirectRules([
        'DOMAIN-KEYWORD,youtube,PROXY',
        'MATCH,GLOBAL',
      ]);

      expect(rules.contains('IP-CIDR,139.9.98.98/32,DIRECT,no-resolve'), true);
      expect(rules.contains('IP-CIDR,139.9.99.99/32,DIRECT,no-resolve'), true);
      expect(
        rules.contains('DOMAIN,browsercfg-drcn.cloud.dbankcloud.cn,DIRECT'),
        true,
      );
      expect(rules.contains('DOMAIN,browserr-drcn.dbankcdn.cn,DIRECT'), true);
      expect(
        rules.contains(
          'DOMAIN,configserver-drcn.platform.dbankcloud.cn,DIRECT',
        ),
        true,
      );
      expect(
        rules.contains('DOMAIN,httpdns.platform.dbankcloud.com,DIRECT'),
        true,
      );
      expect(
        rules.contains('DOMAIN,httpdns-browser.platform.dbankcloud.cn,DIRECT'),
        true,
      );
      expect(
        rules.contains('DOMAIN,nps-drcn.platform.dbankcloud.cn,DIRECT'),
        true,
      );
      expect(
        rules.indexOf('DOMAIN,browsercfg-drcn.cloud.dbankcloud.cn,DIRECT'),
        lessThan(rules.indexOf('DOMAIN-KEYWORD,youtube,PROXY')),
      );
      expect(
        rules.indexOf('DOMAIN,configserver-drcn.platform.dbankcloud.cn,DIRECT'),
        lessThan(rules.indexOf('DOMAIN-KEYWORD,youtube,PROXY')),
      );
      expect(rules, contains('MATCH,GLOBAL'));
    });

    test('preserves user-provided Huawei rules without duplicating them', () {
      final rules = prependOhosDirectRules([
        'DOMAIN,browsercfg-drcn.cloud.dbankcloud.cn,DIRECT',
        'MATCH,GLOBAL',
      ]);

      expect(
        rules
            .where(
              (rule) =>
                  rule == 'DOMAIN,browsercfg-drcn.cloud.dbankcloud.cn,DIRECT',
            )
            .length,
        1,
      );
      expect(
        rules
            .where(
              (rule) => rule == 'DOMAIN,httpdns.platform.dbankcloud.com,DIRECT',
            )
            .length,
        1,
      );
      expect(
        rules
            .where(
              (rule) =>
                  rule ==
                  'DOMAIN,httpdns-browser.platform.dbankcloud.cn,DIRECT',
            )
            .length,
        1,
      );
      expect(
        rules
            .where((rule) => rule == 'DOMAIN,browserr-drcn.dbankcdn.cn,DIRECT')
            .length,
        1,
      );
      expect(
        rules
            .where(
              (rule) =>
                  rule ==
                  'DOMAIN,configserver-drcn.platform.dbankcloud.cn,DIRECT',
            )
            .length,
        1,
      );
      expect(
        rules
            .where(
              (rule) => rule == 'DOMAIN,nps-drcn.platform.dbankcloud.cn,DIRECT',
            )
            .length,
        1,
      );
    });

    test('preserves the cn.bing.com direct rule on ohos', () {
      final rules = prependOhosDirectRules([
        'DOMAIN,cn.bing.com,DIRECT',
        'DOMAIN-KEYWORD,youtube,PROXY',
        'MATCH,GLOBAL',
      ]);

      expect(rules.contains('DOMAIN,cn.bing.com,DIRECT'), true);
      expect(rules, contains('DOMAIN-KEYWORD,youtube,PROXY'));
      expect(rules, contains('MATCH,GLOBAL'));
    });

    test('restores the verified OHOS browser bootstrap direct rules', () {
      final rules = prependOhosDirectRules([
        'DOMAIN-KEYWORD,youtube,PROXY',
        'MATCH,GLOBAL',
      ]);

      expect(
        rules,
        contains('DOMAIN,contentcenter-drcn.cloud.dbankcloud.cn,DIRECT'),
      );
      expect(
        rules,
        contains('DOMAIN,newsfeed-drcn.cloud.dbankcloud.cn,DIRECT'),
      );
      expect(
        rules,
        contains('DOMAIN,terms-drcn.platform.dbankcloud.cn,DIRECT'),
      );
      expect(
        rules,
        contains('DOMAIN,configserver-drcn.platform.dbankcloud.cn,DIRECT'),
      );
      expect(rules, contains('DOMAIN,metrics1-drcn.dt.dbankcloud.cn,DIRECT'));
      expect(rules, contains('DOMAIN,sdkserver-drcn.op.dbankcloud.cn,DIRECT'));
      expect(rules, contains('DOMAIN,feeds-drcn.cloud.huawei.com.cn,DIRECT'));
      expect(rules, contains('DOMAIN,browserr-drcn.dbankcdn.cn,DIRECT'));
      expect(rules, contains('DOMAIN,nps-drcn.platform.dbankcloud.cn,DIRECT'));
    });
  });

  group('normalizeOhosDnsConfig', () {
    test(
      'routes restored OHOS browser bootstrap domains through explicit dns',
      () {
        final normalized = normalizeOhosDnsConfig({}, defaultDns);
        final nameserverPolicy = Map<String, dynamic>.from(
          normalized['nameserver-policy'] as Map,
        );

        expect(
          nameserverPolicy['metrics1-drcn.dt.dbankcloud.cn'],
          defaultDns.defaultNameserver,
        );
        expect(
          nameserverPolicy['feeds-drcn.cloud.huawei.com.cn'],
          defaultDns.defaultNameserver,
        );
        expect(
          nameserverPolicy['browserr-drcn.dbankcdn.cn'],
          defaultDns.defaultNameserver,
        );
        expect(
          nameserverPolicy['configserver-drcn.platform.dbankcloud.cn'],
          defaultDns.defaultNameserver,
        );
        expect(
          nameserverPolicy['nps-drcn.platform.dbankcloud.cn'],
          defaultDns.defaultNameserver,
        );
        expect(normalized['direct-nameserver'], ['system://']);
      },
    );
  });

  group('normalizeOhosTunDnsHijack', () {
    test('restores explicit ipv4 wildcard hijack on ohos', () {
      expect(normalizeOhosTunDnsHijack(['any:53', '172.19.0.2:53']), [
        '0.0.0.0:53',
        '172.19.0.2:53',
      ]);
    });

    test('preserves explicit ipv4 wildcard hijack on ohos', () {
      expect(normalizeOhosTunDnsHijack(['0.0.0.0:53', '172.19.0.2:53']), [
        '0.0.0.0:53',
        '172.19.0.2:53',
      ]);
    });

    test('defaults empty hijack list to explicit ipv4 wildcard on ohos', () {
      expect(normalizeOhosTunDnsHijack([]), ['0.0.0.0:53']);
    });

    test('preserves explicit non-legacy hijack entries', () {
      expect(normalizeOhosTunDnsHijack(['0.0.0.0:53', '[::]:53']), [
        '0.0.0.0:53',
        '[::]:53',
      ]);
    });
  });

  group('OHOS profile persistence', () {
    test('disables fake-ip persistence for OHOS VPN config generation', () {
      final profile = normalizeOhosProfileConfig({});

      expect(profile['store-selected'], false);
      expect(profile['store-fake-ip'], false);
    });
  });

  group('shouldUseOhosVpnConfigOnly', () {
    test('only enables config-only startup for OHOS VPN flows', () {
      expect(shouldUseOhosVpnConfigOnly(isOhos: true, vpnEnabled: true), true);
      expect(
        shouldUseOhosVpnConfigOnly(isOhos: true, vpnEnabled: false),
        false,
      );
      expect(
        shouldUseOhosVpnConfigOnly(isOhos: false, vpnEnabled: true),
        false,
      );
    });
  });

  group('shouldUseCoreProfileConfigForSetup', () {
    test('uses file config only for OHOS config-only setup fallback', () {
      expect(
        shouldUseCoreProfileConfigForSetup(isOhos: true, applyCore: false),
        false,
      );
      expect(
        shouldUseCoreProfileConfigForSetup(isOhos: true, applyCore: true),
        true,
      );
      expect(
        shouldUseCoreProfileConfigForSetup(isOhos: false, applyCore: false),
        true,
      );
    });
  });

  group('resolveUseCoreProfileConfigForSetup', () {
    test('falls back to file config for OHOS config-only setup', () {
      expect(
        resolveUseCoreProfileConfigForSetup(
          explicitUseCoreProfileConfig: null,
          isOhos: true,
          applyCore: false,
        ),
        false,
      );
    });

    test('keeps explicit override when provided', () {
      expect(
        resolveUseCoreProfileConfigForSetup(
          explicitUseCoreProfileConfig: true,
          isOhos: true,
          applyCore: false,
        ),
        true,
      );
      expect(
        resolveUseCoreProfileConfigForSetup(
          explicitUseCoreProfileConfig: false,
          isOhos: false,
          applyCore: true,
        ),
        false,
      );
    });
  });

  group('WindowProps JSON round-trip', () {
    test('default values', () {
      const props = WindowProps();
      expect(props.width, 0);
      expect(props.height, 0);
      expect(props.top, null);
      expect(props.left, null);
    });

    test('fromJson handles null', () {
      final props = WindowProps.fromJson(null);
      expect(props.width, 0);
    });

    test('size extension defaults to 680x580 when empty', () {
      const props = WindowProps();
      expect(props.size.width, 680);
      expect(props.size.height, 580);
    });

    test('size extension uses actual values', () {
      const props = WindowProps(width: 800, height: 600);
      expect(props.size.width, 800);
      expect(props.size.height, 600);
    });

    test('round-trip with values', () {
      const props = WindowProps(width: 1024, height: 768, top: 100, left: 200);
      final restored = roundTrip(() => props.toJson(), WindowProps.fromJson);
      expect(restored.width, 1024);
      expect(restored.height, 768);
      expect(restored.top, 100);
      expect(restored.left, 200);
    });
  });

  group('VpnProps JSON round-trip', () {
    test('default values', () {
      const props = VpnProps();
      expect(props.enable, true);
      expect(props.systemProxy, true);
      expect(props.ipv6, false);
      expect(props.allowBypass, true);
      expect(props.dnsHijacking, false);
      expect(props.accessControlProps.enable, false);
    });

    test('fromJson handles null', () {
      final props = VpnProps.fromJson(null);
      expect(props.enable, true);
    });

    test('round-trip with custom values', () {
      const accessControl = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
      );
      const props = VpnProps(
        enable: false,
        systemProxy: false,
        ipv6: true,
        accessControlProps: accessControl,
      );
      final restored = roundTrip(() => props.toJson(), VpnProps.fromJson);
      expect(restored.enable, false);
      expect(restored.systemProxy, false);
      expect(restored.ipv6, true);
    });
  });

  group('NetworkProps JSON round-trip', () {
    test('default values', () {
      const props = NetworkProps();
      expect(props.systemProxy, true);
      expect(props.bypassDomain, defaultBypassDomain);
      expect(props.routeMode, RouteMode.config);
      expect(props.autoSetSystemDns, true);
      expect(props.appendSystemDns, false);
    });

    test('round-trip with custom values', () {
      const props = NetworkProps(
        systemProxy: false,
        bypassDomain: ['example.com'],
        routeMode: RouteMode.bypassPrivate,
      );
      final restored = roundTrip(() => props.toJson(), NetworkProps.fromJson);
      expect(restored.systemProxy, false);
      expect(restored.bypassDomain, ['example.com']);
      expect(restored.routeMode, RouteMode.bypassPrivate);
    });
  });

  group('ProxiesStyleProps JSON round-trip', () {
    test('default values', () {
      const props = ProxiesStyleProps();
      expect(props.type, ProxiesType.tab);
      expect(props.sortType, ProxiesSortType.none);
      expect(props.layout, ProxiesLayout.standard);
    });

    test('round-trip with custom values', () {
      const props = ProxiesStyleProps(
        type: ProxiesType.list,
        sortType: ProxiesSortType.delay,
      );
      final restored = roundTrip(
        () => props.toJson(),
        ProxiesStyleProps.fromJson,
      );
      expect(restored.type, ProxiesType.list);
      expect(restored.sortType, ProxiesSortType.delay);
    });
  });

  group('ThemeProps JSON round-trip', () {
    test('default values', () {
      const props = ThemeProps();
      expect(props.primaryColor, null);
      expect(props.primaryColors, defaultPrimaryColors);
      expect(props.themeMode, ThemeMode.dark);
      expect(props.pureBlack, false);
      expect(props.textScale.scale, 1.0);
    });

    test('safeFromJson returns default on null', () {
      final result = ThemeProps.safeFromJson(null);
      expect(result.themeMode, ThemeMode.dark);
    });

    test('round-trip with custom values', () {
      const props = ThemeProps(
        primaryColor: 0xFF123456,
        themeMode: ThemeMode.light,
        pureBlack: true,
        textScale: TextScale(enable: true, scale: 1.5),
      );
      final restored = roundTrip(() => props.toJson(), ThemeProps.fromJson);
      expect(restored.primaryColor, 0xFF123456);
      expect(restored.themeMode, ThemeMode.light);
      expect(restored.pureBlack, true);
      expect(restored.textScale.scale, 1.5);
    });
  });

  group('AccessControlProps', () {
    test('currentList returns acceptList in acceptSelected mode', () {
      const props = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['app1', 'app2'],
        rejectList: ['app3'],
      );
      expect(props.currentList, ['app1', 'app2']);
    });

    test('currentList returns rejectList in rejectSelected mode', () {
      const props = AccessControlProps(
        enable: true,
        mode: AccessControlMode.rejectSelected,
        acceptList: ['app1'],
        rejectList: ['app3', 'app4'],
      );
      expect(props.currentList, ['app3', 'app4']);
    });
  });

  group('Config composite serialization', () {
    test('default Config round-trip', () {
      const config = Config(themeProps: ThemeProps());
      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.currentProfileId, null);
      expect(restored.overrideDns, false);
      expect(restored.networkProps.systemProxy, true);
      expect(restored.vpnProps.enable, true);
      expect(restored.hotKeyActions, isEmpty);
    });

    test('realFromJson handles null', () {
      final result = Config.realFromJson(null);
      expect(result.appSettingProps.onlyStatisticsProxy, false);
    });

    test('normalizeVpnPropsForPlatform resets unsupported ohos vpn options', () {
      const vpnProps = VpnProps(
        systemProxy: false,
        allowBypass: false,
        accessControlProps: AccessControlProps(
          enable: true,
          mode: AccessControlMode.acceptSelected,
          acceptList: ['com.example.app'],
        ),
      );

      final normalized = normalizeVpnPropsForPlatform(
        isOhos: true,
        vpnProps: vpnProps,
      );

      expect(normalized.systemProxy, isTrue);
      expect(normalized.allowBypass, isTrue);
      expect(normalized.accessControlProps, defaultAccessControlProps);
    });

    test(
      'normalizeNetworkPropsForPlatform resets unsupported ohos network options',
      () {
        const networkProps = NetworkProps(
          systemProxy: false,
          bypassDomain: ['example.com'],
        );

        final normalized = normalizeNetworkPropsForPlatform(
          isOhos: true,
          networkProps: networkProps,
        );

        expect(normalized.systemProxy, isTrue);
        expect(normalized.bypassDomain, defaultBypassDomain);
      },
    );

    test('normalizeVpnPropsForPlatform preserves non-ohos vpn options', () {
      const vpnProps = VpnProps(
        systemProxy: false,
        allowBypass: false,
      );

      expect(
        normalizeVpnPropsForPlatform(isOhos: false, vpnProps: vpnProps),
        vpnProps,
      );
    });

    test('normalizeNetworkPropsForPlatform preserves non-ohos network options', () {
      const networkProps = NetworkProps(
        systemProxy: false,
        bypassDomain: ['example.com'],
      );

      expect(
        normalizeNetworkPropsForPlatform(
          isOhos: false,
          networkProps: networkProps,
        ),
        networkProps,
      );
    });

    test('full config round-trip', () {
      const config = Config(
        currentProfileId: 42,
        overrideDns: true,
        hotKeyActions: [],
        appSettingProps: AppSettingProps(locale: 'en', autoLaunch: true),
        networkProps: NetworkProps(systemProxy: false),
        vpnProps: VpnProps(enable: false),
        themeProps: ThemeProps(
          primaryColor: 0xFF00FF00,
          themeMode: ThemeMode.system,
        ),
        windowProps: WindowProps(width: 1280, height: 720),
      );
      final restored = roundTrip(() => config.toJson(), Config.fromJson);
      expect(restored.currentProfileId, 42);
      expect(restored.overrideDns, true);
      expect(restored.appSettingProps.locale, 'en');
      expect(restored.appSettingProps.autoLaunch, true);
      expect(restored.networkProps.systemProxy, false);
      expect(restored.vpnProps.enable, false);
      expect(restored.windowProps.width, 1280);
      expect(restored.windowProps.height, 720);
    });
  });

  group('Script.saveWithPath', () {
    late Directory tempRoot;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempRoot = Directory.systemTemp.createTempSync('flclash_script_test');
      // path_provider has no platform implementation under `flutter test`;
      // return a real temp dir so appPath's directory completers resolve.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (methodCall) async => tempRoot.path,
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('copies source file into the script target path', () async {
      await appPath.initOhosPaths();
      final sourceDir = Directory(await appPath.tempPath);
      await sourceDir.create(recursive: true);
      final sourceFile = File('${sourceDir.path}/script-source.js');
      await sourceFile.writeAsString('const value = 42;');

      final script = Script.create(label: 'copy-test');
      final saved = await script.saveWithPath(sourceFile.path);
      final targetFile = File(await saved.path);

      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.readAsString(), 'const value = 42;');
    });
  });
}
