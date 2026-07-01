import 'package:fl_clash/common/path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppPath OHOS path initialization', () {
    test('applyOhosAppPaths is idempotent once completers are resolved', () async {
      final path = AppPath.testOhos();
      const paths = <String, String>{
        'filesDir': '/tmp/flclash-ohos-files',
        'tempDir': '/tmp/flclash-ohos-temp',
        'cacheDir': '/tmp/flclash-ohos-cache',
        'bundleCodeDir': '/tmp/flclash-ohos-bundle',
        'codePath': '/tmp/flclash-ohos-code',
        'nativeLibraryPath': 'libs/arm64',
      };

      await path.applyOhosAppPaths(paths);
      await path.applyOhosAppPaths(paths);

      expect(path.dataDir.isCompleted, isTrue);
      expect(path.tempDir.isCompleted, isTrue);
      expect(path.cacheDir.isCompleted, isTrue);
      expect(path.downloadDir.isCompleted, isTrue);
      expect(path.bundleCodeDir.isCompleted, isTrue);
      expect(path.appDirPath, '/tmp/flclash-ohos-files');
      expect(path.ohosCodeDirPath, '/tmp/flclash-ohos-code');
      expect(path.ohosNativeLibraryDirPath, 'libs/arm64');
    });
  });
}
