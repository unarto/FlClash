import 'package:fl_clash/common/picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Picker user cancellation handling', () {
    test('treats file picker cancellation as non-error', () {
      expect(
        isPickerCancellation(
          PlatformException(
            code: 'cancelled',
            message: 'No file selected',
          ),
        ),
        isTrue,
      );
    });

    test('does not swallow unrelated platform exceptions', () {
      expect(
        isPickerCancellation(
          PlatformException(
            code: 'permission_denied',
            message: 'No file selected',
          ),
        ),
        isFalse,
      );
      expect(
        isPickerCancellation(
          PlatformException(
            code: 'cancelled',
            message: 'Different message',
          ),
        ),
        isFalse,
      );
    });
  });
}
