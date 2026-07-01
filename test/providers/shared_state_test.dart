import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveVpnDnsHijacking', () {
    test('preserves user preference on ohos', () {
      expect(
        resolveVpnDnsHijacking(isOhos: true, dnsHijacking: false),
        isFalse,
      );
    });
  });

  group('resolveVpnAccessControlProps', () {
    test('disables access control on ohos runtime', () {
      const accessControlProps = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['com.example.app'],
      );

      expect(
        resolveVpnAccessControlProps(
          isOhos: true,
          accessControlProps: accessControlProps,
        ),
        defaultAccessControlProps,
      );
    });

    test('preserves access control on non-ohos runtime', () {
      const accessControlProps = AccessControlProps(
        enable: true,
        mode: AccessControlMode.rejectSelected,
        rejectList: ['com.example.app'],
      );

      expect(
        resolveVpnAccessControlProps(
          isOhos: false,
          accessControlProps: accessControlProps,
        ),
        accessControlProps,
      );
    });
  });

  group('resolveVpnSystemProxy', () {
    test('forces enabled system proxy on ohos runtime', () {
      expect(resolveVpnSystemProxy(isOhos: true, systemProxy: false), isTrue);
    });

    test('preserves system proxy on non-ohos runtime', () {
      expect(resolveVpnSystemProxy(isOhos: false, systemProxy: false), isFalse);
    });
  });

  group('resolveVpnAllowBypass', () {
    test('forces enabled allowBypass on ohos runtime', () {
      expect(resolveVpnAllowBypass(isOhos: true, allowBypass: false), isTrue);
    });

    test('preserves allowBypass on non-ohos runtime', () {
      expect(resolveVpnAllowBypass(isOhos: false, allowBypass: false), isFalse);
    });
  });

  group('resolveProxyBypassDomain', () {
    test('forces default bypassDomain on ohos runtime', () {
      expect(
        resolveProxyBypassDomain(isOhos: true, bypassDomain: ['example.com']),
        defaultBypassDomain,
      );
    });

    test('preserves bypassDomain on non-ohos runtime', () {
      expect(
        resolveProxyBypassDomain(isOhos: false, bypassDomain: ['example.com']),
        ['example.com'],
      );
    });
  });

  group('sharedStateProvider', () {
    test('wires normalized vpn and setup values into shared state', () async {
      await AppLocalizations.load(const Locale('en'));
      final container = ProviderContainer(
        overrides: [
          appSettingProvider.overrideWithBuild(
            (_, ref) => const AppSettingProps(
              onlyStatisticsProxy: true,
              crashlytics: false,
              testUrl: 'https://unit.test',
            ),
          ),
          currentProfileProvider.overrideWithValue(
            const Profile(
              id: 7,
              label: 'OHOS',
              autoUpdateDuration: defaultUpdateDuration,
              selectedMap: {'GLOBAL': 'Proxy A'},
            ),
          ),
          networkSettingProvider.overrideWithBuild(
            (_, ref) => const NetworkProps(
              bypassDomain: defaultBypassDomain,
            ),
          ),
          patchClashConfigProvider.overrideWithBuild(
            (_, ref) => const PatchClashConfig(mixedPort: 7890),
          ),
          vpnSettingProvider.overrideWithBuild(
            (_, ref) => const VpnProps(
              enable: true,
              dnsHijacking: false,
              systemProxy: true,
              allowBypass: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(sharedStateProvider);

      expect(state.currentProfileName, 'OHOS');
      expect(state.onlyStatisticsProxy, isTrue);
      expect(state.crashlytics, isFalse);
      expect(
        state.setupParams,
        const SetupParams(
          selectedMap: {'GLOBAL': 'Proxy A'},
          testUrl: 'https://unit.test',
        ),
      );
      expect(state.vpnOptions?.dnsHijacking, isFalse);
      expect(state.vpnOptions?.systemProxy, isTrue);
      expect(state.vpnOptions?.allowBypass, isTrue);
      expect(state.vpnOptions?.bypassDomain, defaultBypassDomain);
      expect(state.vpnOptions?.port, 7890);
    });
  });
}
