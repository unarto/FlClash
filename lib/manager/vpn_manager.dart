import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class VpnManager extends ConsumerStatefulWidget {
  final Widget child;

  const VpnManager({super.key, required this.child});

  @override
  ConsumerState<VpnManager> createState() => _VpnContainerState();
}

class _VpnContainerState extends ConsumerState<VpnManager> {
  Future<void> _pendingSync = Future.value();

  @override
  void initState() {
    super.initState();
    ref.listenManual(vpnStateProvider, (prev, next) {
      if (prev != next) {
        showTip(next);
        _scheduleSync();
      }
    });
    if (system.isOhos) {
      ref.listenManual<bool>(isStartProvider, (prev, next) {
        if (prev != next) {
          _scheduleSync();
        }
      }, fireImmediately: true);
    }
  }

  void _scheduleSync() {
    if (!system.isOhos) {
      return;
    }
    _pendingSync = _pendingSync
        .then((_) => _syncVpn())
        .catchError((Object error) {
          commonPrint.log(
            '[OHOS-VPN] sync failed: $error',
            logLevel: LogLevel.warning,
          );
        });
  }

  Future<void> _syncVpn() async {
    final state = ref.read(vpnStateProvider);
    final isStart = ref.read(isStartProvider);
    if (!isStart || !state.vpnProps.enable) {
      await app?.stopVpn();
      return;
    }
    try {
      final started = await app?.startVpn(
        stack: state.stack.name,
        ipv6: state.vpnProps.ipv6,
        allowBypass: state.vpnProps.allowBypass,
      );
      if (started == false) {
        throw PlatformException(
          code: 'START_VPN_FAILED',
          message: 'OHOS VPN extension did not start',
        );
      }
    } on PlatformException catch (error) {
      final message = _formatVpnError(error);
      commonPrint.log(
        '[OHOS-VPN] start failed: $message',
        logLevel: LogLevel.warning,
      );
      globalState.showNotifier(message);
      await ref.read(setupActionProvider.notifier).updateStatus(false);
    }
  }

  String _formatVpnError(PlatformException error) {
    final detail = error.details?.toString();
    if ((detail?.contains('com.huawei.hmos.vpndialog') ?? false) ||
        (error.message?.contains('com.huawei.hmos.vpndialog') ?? false) ||
        (error.message?.contains('vpn extension not ready') ?? false) ||
        (error.message?.contains('startVpnExtensionAbility timeout') ?? false)) {
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

  void showTip(VpnState state) {
    throttler.call(
      FunctionTag.vpnTip,
      () {
        if (!ref.read(isStartProvider) || state == globalState.lastVpnState) {
          return;
        }
        globalState.showNotifier(
          currentAppLocalizations.vpnConfigChangeDetected,
          actionState: MessageActionState(
            actionText: currentAppLocalizations.restart,
            action: () async {
              final setupAction = ref.read(setupActionProvider.notifier);
              await setupAction.handleStop();
              await setupAction.updateStatus(true);
            },
          ),
        );
      },
      duration: const Duration(seconds: 6),
      fire: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
