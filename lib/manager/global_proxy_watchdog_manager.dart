import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/controller.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlobalProxyWatchdogManager extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalProxyWatchdogManager({super.key, required this.child});

  @override
  ConsumerState<GlobalProxyWatchdogManager> createState() =>
      _GlobalProxyWatchdogManagerState();
}

class _GlobalProxyWatchdogManagerState
    extends ConsumerState<GlobalProxyWatchdogManager> {
  static const _checkInterval = Duration(seconds: 30);
  static const _probeTimeout = Duration(seconds: 8);
  static const _switchCooldown = Duration(minutes: 2);
  static const _resetFailureThreshold = 2;
  static const _switchFailureThreshold = 3;
  static const _maxCandidatesPerCycle = 8;

  Timer? _timer;
  bool _checking = false;
  int _failureCount = 0;
  DateTime? _lastSwitchAttemptAt;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_checkInterval, (_) => _check());
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _enabled {
    final isInit = ref.read(initProvider);
    final isStart = ref.read(runTimeProvider) != null;
    final coreConnected = ref.read(coreStatusProvider) == CoreStatus.connected;
    final mode = ref.read(patchClashConfigProvider).mode;
    return isInit && isStart && coreConnected && mode == Mode.global;
  }

  Future<void> _check() async {
    if (_checking) {
      return;
    }
    if (!_enabled) {
      _failureCount = 0;
      return;
    }
    _checking = true;
    try {
      final port = ref.read(patchClashConfigProvider).mixedPort;
      final url = ref.read(appSettingProvider).testUrl;
      final ok = await _probeMixedPort(port: port, url: url);
      if (ok) {
        if (_failureCount > 0) {
          _log('global watchdog recovered after $_failureCount failed checks');
        }
        _failureCount = 0;
        return;
      }
      _failureCount++;
      _log('global watchdog probe failed ($_failureCount)');
      if (_failureCount == _resetFailureThreshold) {
        await _resetProxyPath();
        return;
      }
      if (_failureCount >= _switchFailureThreshold) {
        await _trySwitchGlobalProxy(url);
      }
    } catch (e) {
      _log('global watchdog error: $e');
    } finally {
      _checking = false;
    }
  }

  Future<bool> _probeMixedPort({required int port, required String url}) async {
    final client = HttpClient()..connectionTimeout = _probeTimeout;
    client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(_probeTimeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>().timeout(_probeTimeout);
      return response.statusCode >= 200 && response.statusCode < 400;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _resetProxyPath() async {
    _log('global watchdog resetting stale proxy connections');
    coreController.resetConnections();
    coreController.closeConnections();
  }

  Future<void> _trySwitchGlobalProxy(String defaultTestUrl) async {
    if (_lastSwitchAttemptAt != null &&
        DateTime.now().difference(_lastSwitchAttemptAt!) < _switchCooldown) {
      return;
    }
    _lastSwitchAttemptAt = DateTime.now();
    final groups = ref.read(groupsProvider);
    final globalGroup = groups.getGroup(GroupName.GLOBAL.name);
    if (globalGroup == null || globalGroup.all.isEmpty) {
      _log('global watchdog found no GLOBAL group candidates');
      return;
    }
    final selectedMap = ref.read(selectedMapProvider);
    final currentProxyName = globalGroup.getCurrentSelectedName(
      selectedMap[GroupName.GLOBAL.name] ?? '',
    );
    final testUrl = globalGroup.testUrl.takeFirstValid([defaultTestUrl]);
    final candidates = globalGroup.all
        .where((proxy) => proxy.name != currentProxyName)
        .where((proxy) => proxy.name != UsedProxy.DIRECT.value)
        .where((proxy) => proxy.name != UsedProxy.REJECT.value)
        .take(_maxCandidatesPerCycle);

    for (final proxy in candidates) {
      final delay = await _testCandidate(
        testUrl: testUrl,
        proxyName: proxy.name,
      );
      if (delay == null || delay.value == null || delay.value! <= 0) {
        continue;
      }
      _log(
        'global watchdog switching GLOBAL from '
        '$currentProxyName to ${proxy.name} (${delay.value}ms)',
      );
      appController.updateCurrentSelectedMap(GroupName.GLOBAL.name, proxy.name);
      await appController.changeProxy(
        groupName: GroupName.GLOBAL.name,
        proxyName: proxy.name,
      );
      appController.updateGroupsDebounce();
      _failureCount = 0;
      return;
    }
    _log('global watchdog found no healthy GLOBAL candidate');
    await _resetProxyPath();
  }

  Future<Delay?> _testCandidate({
    required String testUrl,
    required String proxyName,
  }) async {
    try {
      final pending = Delay(url: testUrl, name: proxyName, value: 0);
      appController.setDelay(pending);
      final delay = await coreController
          .getDelay(testUrl, proxyName)
          .timeout(_probeTimeout);
      appController.setDelay(delay);
      return delay;
    } catch (e) {
      _log('global watchdog candidate $proxyName failed: $e');
      return null;
    }
  }

  void _log(String message) {
    commonPrint.log(message);
    ref.read(logsProvider.notifier).addLog(Log.app(message));
  }
}
