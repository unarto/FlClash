import 'dart:io';

import 'package:fl_clash/common/file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DirectoryExt.safeClear', () {
    test('removes nested contents but keeps root directory', () async {
      final rootDir = await Directory.systemTemp.createTemp(
        'flclash-safe-clear',
      );
      final nestedDir = Directory('${rootDir.path}/nested/deeper');
      await nestedDir.create(recursive: true);
      await File('${rootDir.path}/root.txt').writeAsString('root');
      await File('${nestedDir.path}/child.txt').writeAsString('child');

      await rootDir.safeClear();

      expect(await rootDir.exists(), isTrue);
      expect(await rootDir.list().toList(), isEmpty);

      await rootDir.safeDelete(recursive: true);
    });

    test('is a no-op when directory does not exist', () async {
      final rootDir = Directory(
        '${Directory.systemTemp.path}/flclash-safe-clear-missing-${DateTime.now().microsecondsSinceEpoch}',
      );

      await rootDir.safeClear();

      expect(await rootDir.exists(), isFalse);
    });
  });
}
