import 'package:fl_clash/views/dashboard/widgets/start_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dashboard start button', () {
    test('non-ohos keeps optimistic animation', () {
      expect(
        shouldOptimisticallyAnimateDashboardStartButton(isOhos: false),
        isTrue,
      );
    });

    test('ohos disables optimistic animation before native vpn sync', () {
      expect(
        shouldOptimisticallyAnimateDashboardStartButton(isOhos: true),
        isFalse,
      );
    });
  });
}
