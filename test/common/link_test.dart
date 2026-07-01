import 'package:fl_clash/common/link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

void main() {
  group('shouldHandleOhosLinkEvent', () {
    test('accepts first OHOS link delivery', () {
      expect(
        shouldHandleOhosLinkEvent(
          lastUriString: null,
          lastHandledAt: null,
          uriString: 'flclash://install-config?url=https://a.example/config',
          now: DateTime(2026),
        ),
        isTrue,
      );
    });

    test('suppresses duplicate OHOS link within dedupe window', () {
      final now = DateTime(2026, 1, 1, 0, 0, 1);
      expect(
        shouldHandleOhosLinkEvent(
          lastUriString: 'flclash://install-config?url=https://a.example/config',
          lastHandledAt: now.subtract(const Duration(milliseconds: 500)),
          uriString: 'flclash://install-config?url=https://a.example/config',
          now: now,
        ),
        isFalse,
      );
    });

    test('allows same OHOS link again after dedupe window expires', () {
      final now = DateTime(2026, 1, 1, 0, 0, 3);
      expect(
        shouldHandleOhosLinkEvent(
          lastUriString: 'flclash://install-config?url=https://a.example/config',
          lastHandledAt: now.subtract(const Duration(seconds: 3)),
          uriString: 'flclash://install-config?url=https://a.example/config',
          now: now,
        ),
        isTrue,
      );
    });

    test('allows different OHOS link immediately', () {
      final now = DateTime(2026, 1, 1, 0, 0, 1);
      expect(
        shouldHandleOhosLinkEvent(
          lastUriString: 'flclash://install-config?url=https://a.example/config',
          lastHandledAt: now.subtract(const Duration(milliseconds: 500)),
          uriString: 'flclash://install-config?url=https://b.example/config',
          now: now,
        ),
        isTrue,
      );
    });

    test('OHOS cold-start pending links are drained sequentially in Dart', () async {
      final source = await File(
        path.join(Directory.current.path, 'lib/common/link.dart'),
      ).readAsString();

      expect(
        source,
        matches(
          RegExp(
            r'if \(system\.isOhos\) \{[\s\S]*app\?\.updateAppLinkListenerReady\(false\);[\s\S]*app\?\.onAppLink = \(link\) async \{',
            multiLine: true,
          ),
        ),
      );
      expect(
        source,
        matches(
          RegExp(
            r'while \(true\) \{[\s\S]*final pendingLink = await app\?\.consumePendingLink\(\);[\s\S]*if \(pendingLink == null \|\| pendingLink\.isEmpty\) \{[\s\S]*break;[\s\S]*\}[\s\S]*_handleUriString\(pendingLink, installConfigCallBack\);',
            multiLine: true,
          ),
        ),
      );
      expect(
        source,
        matches(
          RegExp(
            r'while \(true\) \{[\s\S]*_handleUriString\(pendingLink, installConfigCallBack\);[\s\S]*\}[\s\S]*await app\?\.updateAppLinkListenerReady\(true\);',
            multiLine: true,
          ),
        ),
      );
    });
  });
}
