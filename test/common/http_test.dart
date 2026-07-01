import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlClashHttpOverrides.handleFindProxy', () {
    test('uses direct connection for local emulator host', () {
      expect(
        FlClashHttpOverrides.handleFindProxy(Uri.parse('http://10.0.2.2:19000')),
        'DIRECT',
      );
    });

    test('uses direct connection for localhost aliases', () {
      expect(
        FlClashHttpOverrides.handleFindProxy(Uri.parse('http://127.0.0.1:9090')),
        'DIRECT',
      );
      expect(
        FlClashHttpOverrides.handleFindProxy(Uri.parse('http://localhost:9090')),
        'DIRECT',
      );
    });
  });
}
