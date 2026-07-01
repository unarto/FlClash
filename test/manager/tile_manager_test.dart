import 'package:fl_clash/manager/tile_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tile tips', () {
    test('start tip is shown only after successful start', () {
      expect(
        shouldShowTileStartTip(isOhos: false, startSucceeded: true),
        isTrue,
      );
      expect(
        shouldShowTileStartTip(isOhos: false, startSucceeded: false),
        isFalse,
      );
    });

    test('stop tip is shown only after successful stop', () {
      expect(
        shouldShowTileStopTip(isOhos: false, stopSucceeded: true),
        isTrue,
      );
      expect(
        shouldShowTileStopTip(isOhos: false, stopSucceeded: false),
        isFalse,
      );
    });

    test('OHOS tile does not show optimistic success tips before native VPN sync', () {
      expect(
        shouldShowTileStartTip(isOhos: true, startSucceeded: true),
        isFalse,
      );
      expect(
        shouldShowTileStopTip(isOhos: true, stopSucceeded: true),
        isFalse,
      );
    });
  });
}
