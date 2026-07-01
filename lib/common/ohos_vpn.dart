import 'package:flutter/services.dart';

const _ohosVpnStopCleanupFailureMarkers = <String>[
  'stopTun failed:',
  'stopTrackedCore failed:',
  'destroy failed:',
];

String formatOhosVpnStartError(PlatformException error) {
  final detail = error.details?.toString();
  if ((detail?.contains('com.huawei.hmos.vpndialog') ?? false) ||
      (error.message?.contains('com.huawei.hmos.vpndialog') ?? false)) {
    return 'OHOS VPN 授权组件缺失，当前模拟器无法完成系统 VPN 启动';
  }
  final message = error.message?.trim();
  if (message != null && message.isNotEmpty) {
    return 'VPN 启动失败: $message';
  }
  if (detail != null && detail.isNotEmpty) {
    return 'VPN 启动失败: $detail';
  }
  return 'VPN 启动失败';
}

String formatOhosVpnStopError(PlatformException error) {
  final message = error.message?.trim();
  if (message != null && message.isNotEmpty) {
    return 'VPN 停止失败: $message';
  }
  final detail = error.details?.toString();
  if (detail != null && detail.isNotEmpty) {
    return 'VPN 停止失败: $detail';
  }
  return 'VPN 停止失败';
}

String formatOhosVpnStopRestoreFailure(String stopFailureMessage) {
  return '$stopFailureMessage；本地运行状态恢复失败，请重新启动应用后检查 VPN 实际状态';
}

String formatOhosPendingDebugVpnRollbackFailure(String stopFailureMessage) {
  return 'VPN 启动失败；本地初始化失败后原生 VPN 回滚失败。'
      '$stopFailureMessage；请重新启动应用后检查 VPN 实际状态';
}

bool shouldRestoreOhosVpnStateAfterStopFailure(PlatformException error) {
  final candidates = <String>[
    error.message?.trim() ?? '',
    error.details?.toString().trim() ?? '',
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) {
      continue;
    }
    for (final marker in _ohosVpnStopCleanupFailureMarkers) {
      if (candidate.contains(marker)) {
        return true;
      }
    }
  }
  return false;
}
