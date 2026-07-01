import 'package:fl_clash/common/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveOhosBuildValue', () {
    test('prefers app-specific dart define', () {
      expect(
        resolveOhosBuildValue(
          appValue: '0.8.93',
          flutterValue: '0.8.92',
          fallbackValue: '0.8.91',
        ),
        '0.8.93',
      );
    });

    test('falls back to Flutter build define when app-specific define is empty', () {
      expect(
        resolveOhosBuildValue(
          appValue: '',
          flutterValue: '0.8.93',
          fallbackValue: '0.8.91',
        ),
        '0.8.93',
      );
    });

    test('falls back to baked-in value when both defines are empty', () {
      expect(
        resolveOhosBuildValue(
          appValue: '',
          flutterValue: '',
          fallbackValue: '0.8.93',
        ),
        '0.8.93',
      );
    });
  });
}
