import 'package:fl_clash/manager/core_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldForceStartLogOnInit', () {
    test('returns false when OHOS logs are disabled', () {
      expect(
        shouldForceStartLogOnInit(isOhos: true, openLogs: false),
        isFalse,
      );
    });

    test('returns true only when OHOS logs are enabled', () {
      expect(
        shouldForceStartLogOnInit(isOhos: true, openLogs: true),
        isTrue,
      );
      expect(
        shouldForceStartLogOnInit(isOhos: false, openLogs: true),
        isFalse,
      );
    });
  });
}
