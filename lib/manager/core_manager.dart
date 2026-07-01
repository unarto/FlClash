import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool shouldForceStartLogOnInit({
  required bool isOhos,
  required bool openLogs,
}) {
  return isOhos && openLogs;
}

class CoreManager extends ConsumerStatefulWidget {
  final Widget child;

  const CoreManager({super.key, required this.child});

  @override
  ConsumerState<CoreManager> createState() => _CoreContainerState();
}

class _CoreContainerState extends ConsumerState<CoreManager>
    with CoreEventListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    coreEventManager.addListener(this);
    if (shouldForceStartLogOnInit(
      isOhos: system.isOhos,
      openLogs: ref.read(appSettingProvider).openLogs,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        commonPrint.log('[OHOS-CORE] force startLog on init');
        coreController.startLog();
      });
    }
    ref.listenManual(currentProfileIdProvider, (prev, next) {
      commonPrint.log(
        '[profile-select-core] currentProfileId changed prev=$prev next=$next',
      );
      if (prev != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          () async {
            commonPrint.log(
              '[profile-select-core] fullSetup begin prev=$prev next=$next',
            );
            final applied = await ref
                .read(setupActionProvider.notifier)
                .fullSetup();
            commonPrint.log(
              '[profile-select-core] fullSetup end prev=$prev next=$next applied=$applied current=${ref.read(currentProfileIdProvider)}',
            );
            if (!applied && prev != null) {
              commonPrint.log(
                '[profile-select-core] revert currentProfileId to prev=$prev',
              );
              ref.read(currentProfileIdProvider.notifier).value = prev;
            }
          }();
        });
      }
    });
    ref.listenManual(updateParamsProvider, (prev, next) {
      if (prev != next) {
        ref.read(setupActionProvider.notifier).updateConfigDebounce();
      }
    });
    ref.listenManual(appSettingProvider.select((state) => state.openLogs), (
      prev,
      next,
    ) {
      if (system.isOhos) {
        commonPrint.log('[OHOS-CORE] startLog listener toggle next=$next');
      }
      if (next) {
        coreController.startLog();
      } else {
        coreController.stopLog();
      }
    }, fireImmediately: true);
  }

  @override
  Future<void> dispose() async {
    coreEventManager.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onDelay(Delay delay) async {
    super.onDelay(delay);
    final proxiesAction = ref.read(proxiesActionProvider.notifier);
    proxiesAction.setDelay(delay);
    debouncer.call(FunctionTag.updateDelay, () async {
      proxiesAction.updateGroupsDebounce();
    }, duration: const Duration(milliseconds: 5000));
  }

  @override
  void onLog(Log log) {
    // ref.read(logsProvider.notifier).add(log);
    if (log.logLevel == LogLevel.error) {
      globalState.showNotifier(log.payload);
    }
    super.onLog(log);
  }

  @override
  void onRequest(TrackerInfo trackerInfo) async {
    final requestsNotifier = ref.read(requestsProvider.notifier);
    requestsNotifier.addRequest(trackerInfo);
    commonPrint.log(
      '[OHOS-CORE] onRequest stored id=${trackerInfo.id} host=${trackerInfo.metadata.host} requests=${ref.read(requestsProvider).length}',
    );
    super.onRequest(trackerInfo);
  }

  @override
  Future<void> onLoaded(String providerName) async {
    final ref = globalState.container;
    ref
        .read(providersProvider.notifier)
        .setProvider(await coreController.getExternalProvider(providerName));
    debouncer.call(FunctionTag.loadedProvider, () async {
      ref.read(proxiesActionProvider.notifier).updateGroupsDebounce();
    }, duration: const Duration(milliseconds: 5000));
    super.onLoaded(providerName);
  }

  @override
  Future<void> onCrash(String message) async {
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return;
    }
    ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      context.showNotifier(message);
    }
    await coreController.shutdown(false);
    super.onCrash(message);
  }
}
