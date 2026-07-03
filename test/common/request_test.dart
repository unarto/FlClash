import 'package:fl_clash/common/common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCheckForUpdateResponse', () {
    test('returns upToDate when remote tag matches local version', () {
      final result = parseCheckForUpdateResponse(
        data: {'tag_name': 'v0.8.93'},
        version: '0.8.93',
      );

      expect(result.status, CheckForUpdateStatus.upToDate);
      expect(result.data, isNull);
    });

    test('returns available when remote tag is newer than local version', () {
      final result = parseCheckForUpdateResponse(
        data: {'tag_name': 'v0.8.94'},
        version: '0.8.93',
      );

      expect(result.status, CheckForUpdateStatus.available);
      expect(result.data, {'tag_name': 'v0.8.94'});
    });
  });

  group('subscription request user agent', () {
    test('uses provider-compatible ua instead of browser ua', () {
      final info = PackageInfo(
        appName: 'FlClash',
        packageName: 'com.follow.clash',
        version: '0.8.93',
        buildNumber: '1',
      );

      final ua = subscriptionRequestUserAgent(info);

      expect(ua, info.providerCompatibleUa);
      expect(ua, isNot(browserUa));
    });
  });
}
