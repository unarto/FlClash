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

  group('sharedStateProvider', () {
    test('preserves vpn dns hijacking preference', () async {
      await AppLocalizations.load(const Locale('en'));
      final container = ProviderContainer(
        overrides: [
          appSettingProvider.overrideWithBuild((_, __) => const AppSettingProps()),
          currentProfileProvider.overrideWithValue(null),
          networkSettingProvider.overrideWithBuild((_, __) => const NetworkProps()),
          patchClashConfigProvider.overrideWithBuild(
            (_, __) => const PatchClashConfig(),
          ),
          vpnSettingProvider.overrideWithBuild(
            (_, __) => const VpnProps(dnsHijacking: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(sharedStateProvider);

      expect(state.vpnOptions?.dnsHijacking, isFalse);
    });
  });
}
