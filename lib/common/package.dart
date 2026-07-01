import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

String resolveProviderCompatibleUa({
  required bool isOhos,
  required String ua,
}) {
  if (isOhos) {
    return 'clash.meta/1.10.0';
  }
  return ua;
}

extension PackageInfoExtension on PackageInfo {
  String get providerCompatibleUa {
    return resolveProviderCompatibleUa(isOhos: system.isOhos, ua: ua);
  }

  String get ua => [
        '$appName/v$version',
        'ClashMeta',
        'Platform/${Platform.operatingSystem}',
      ].join(' ');
}
