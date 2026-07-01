import 'dart:io';

import 'package:fl_clash/common/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preferences OHOS file store', () {
    test('waits for OHOS path initialization before reading file store', () async {
      final tempDir = await Directory.systemTemp.createTemp('flclash_prefs');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      var ensureCalls = 0;
      final file = File('${tempDir.path}/shared_preferences.json');
      await file.writeAsString('{"version":7}');

      final preferences = Preferences.testOhosWithFileStore(
        ensureOhosPaths: () async {
          ensureCalls += 1;
        },
        fileStore: file,
      );

      final version = await preferences.getVersion();

      expect(version, 7);
      expect(ensureCalls, 1);
    });
  });
}
