import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get providerCompatibleUa {
    if (system.isOhos) {
      return 'clash.meta/1.10.0';
    }
    return ua;
  }

  String get ua => [
        '$appName/v$version',
        'ClashMeta',
        'Platform/${Platform.operatingSystem}',
      ].join(' ');
}
