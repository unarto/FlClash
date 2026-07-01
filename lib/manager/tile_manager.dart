import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/tile.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool shouldShowTileStartTip({
  required bool isOhos,
  required bool startSucceeded,
}) {
  return !isOhos && startSucceeded;
}

bool shouldShowTileStopTip({
  required bool isOhos,
  required bool stopSucceeded,
}) {
  return !isOhos && stopSucceeded;
}

class TileManager extends ConsumerStatefulWidget {
  final Widget child;

  const TileManager({super.key, required this.child});

  @override
  ConsumerState<TileManager> createState() => _TileContainerState();
}

class _TileContainerState extends ConsumerState<TileManager> with TileListener {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  bool get isStart => ref.read(isStartProvider);

  @override
  Future<void> onStart() async {
    if (isStart && coreController.isCompleted) {
      return;
    }
    final setupAction = ref.read(setupActionProvider.notifier);
    await setupAction.updateStatus(true);
    if (shouldShowTileStartTip(
      isOhos: system.isOhos,
      startSucceeded: ref.read(isStartProvider),
    )) {
      app?.tip(currentAppLocalizations.startVpn);
    }
    super.onStart();
  }

  @override
  Future<void> onStop() async {
    if (!isStart) {
      return;
    }
    final setupAction = ref.read(setupActionProvider.notifier);
    await setupAction.updateStatus(false);
    if (shouldShowTileStopTip(
      isOhos: system.isOhos,
      stopSucceeded: !ref.read(isStartProvider),
    )) {
      app?.tip(currentAppLocalizations.stopVpn);
    }
    super.onStop();
  }

  @override
  void initState() {
    super.initState();
    tile?.addListener(this);
  }

  @override
  void dispose() {
    tile?.removeListener(this);
    super.dispose();
  }
}
