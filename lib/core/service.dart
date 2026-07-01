import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';

import 'interface.dart';
import 'transport.dart';

typedef DesktopProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);
typedef CoreExecutablePathResolver = String Function();

class CoreService extends CoreHandlerInterface {
  static CoreService? _instance;
  static const _connectionTimeout = Duration(seconds: 15);

  late final IPCCoreTransport _transport;

  Completer<bool> _shutdownCompleter = Completer();

  final Map<String, Completer> _callbackCompleterMap = {};

  final Duration _connectionTimeoutDuration;
  final DesktopProcessStarter _startDesktopProcess;
  final CoreExecutablePathResolver _coreExecutablePath;

  Process? _process;
  OhosCoreLaunch _ohosCoreLaunch = const OhosCoreLaunch.none();
  bool _suppressDisconnectCrash = false;

  factory CoreService() {
    _instance ??= CoreService._internal();
    return _instance!;
  }

  CoreService._internal()
    : _connectionTimeoutDuration = _connectionTimeout,
      _startDesktopProcess = ((executable, arguments) {
        return Process.start(executable, arguments);
      }),
      _coreExecutablePath = (() {
        return appPath.corePath;
      }) {
    _transport = IPCCoreTransport(
      address: system.isWindows ? windowsPipeName : unixSocketPath,
    );
    _initializeTransport();
  }

  @visibleForTesting
  CoreService.test(
    IPCCoreTransport transport, {
    Duration connectionTimeout = _connectionTimeout,
    DesktopProcessStarter? startDesktopProcess,
    CoreExecutablePathResolver? coreExecutablePath,
  }) : _connectionTimeoutDuration = connectionTimeout,
       _startDesktopProcess =
           startDesktopProcess ??
           ((executable, arguments) {
             return Process.start(executable, arguments);
           }),
       _coreExecutablePath =
           coreExecutablePath ??
           (() {
             return appPath.corePath;
           }) {
    _transport = transport;
    _initializeTransport();
  }

  void _initializeTransport() {
    _initServer();
  }

  Future<void> handleResult(ActionResult result) async {
    if (result.id?.isEmpty ?? true) {
      coreEventManager.sendEvent(CoreEvent.fromJson(result.data));
      return;
    }
    final completer = _callbackCompleterMap[result.id];
    final data = await parasResult(result);
    if (completer?.isCompleted == true) {
      return;
    }
    completer?.complete(data);
  }

  Future<void> _initServer() async {
    await _transport.init();

    _transport.onDisconnect = () {
      _clearCompleter();
      if (_suppressDisconnectCrash) {
        commonPrint.log('Core transport disconnected during shutdown/restart');
      } else {
        _handleInvokeCrashEvent();
      }
      _suppressDisconnectCrash = false;
      if (!_shutdownCompleter.isCompleted) {
        _shutdownCompleter.complete(true);
      }
    };

    _transport.dataStream
        .transform(uint8ListToListIntConverter)
        .transform(utf8.decoder)
        .listen(
          (data) async {
            try {
              final dataJson = await data.trim().commonToJSON<dynamic>();
              await handleResult(ActionResult.fromJson(dataJson));
            } catch (e) {
              commonPrint.log(
                'Failed to parse transport data: $e',
                logLevel: LogLevel.error,
              );
            }
          },
          onError: (error) {
            commonPrint.log(
              'Transport data stream error: $error',
              logLevel: LogLevel.error,
            );
          },
        );
  }

  void _handleInvokeCrashEvent() {
    coreEventManager.sendEvent(
      const CoreEvent(type: CoreEventType.crash, data: 'core done'),
    );
  }

  Future<void> _dumpOhosCoreLogs(String tag) async {
    if (!system.isOhos) {
      return;
    }
    final homeDir = await appPath.homeDirPath;
    final files = <String>[
      join(homeDir, 'flclash-bridge.log'),
      join(homeDir, 'flclash-core.log'),
      '/data/storage/el2/base/files/flclash-core.log',
      '/data/storage/el2/base/files/flclash-libentry.log',
    ];
    for (final path in files) {
      final file = File(path);
      final label = path.startsWith(homeDir)
          ? path.substring(homeDir.length + 1)
          : path;
      if (!await file.exists()) {
        commonPrint.log('[OHOS-CORE] $tag $label missing');
        continue;
      }
      final content = await file.readAsString();
      commonPrint.log('[OHOS-CORE] $tag $label => $content');
    }
  }

  Future<bool> start() async {
    if (_process != null || _ohosCoreLaunch.hasTrackedCore) {
      await shutdown(false);
      if (system.isOhos && _ohosCoreLaunch.hasTrackedCore) {
        commonPrint.log(
          'Unable to start OHOS core because a previous tracked core is still active',
          logLevel: LogLevel.error,
        );
        return false;
      }
    }
    await _transport.readyCompleter.future;
    if (system.isWindows && await system.checkIsAdmin()) {
      final isSuccess = await request.startCoreByHelper(_transport.address);
      if (isSuccess) {
        return _waitForConnection();
      }
    }
    try {
      if (system.isOhos) {
        await appPath.initOhosPaths();
        final homeDir = await appPath.homeDirPath;
        for (final path in <String>{
          join(homeDir, 'flclash-bridge.log'),
          join(homeDir, 'flclash-core.log'),
          '/data/storage/el2/base/files/flclash-bridge.log',
          '/data/storage/el2/base/files/flclash-core.log',
          '/data/storage/el2/base/files/flclash-libentry.log',
          '/data/storage/el2/base/files/flclash-child.log',
        }) {
          await File(path).safeDelete();
        }
        final childPid = await app?.startCoreChildProcess(_transport.address);
        if (childPid != null && childPid > 0) {
          _ohosCoreLaunch = OhosCoreLaunch.child(pid: childPid);
          commonPrint.log(
            'Started OHOS core child process pid=${_ohosCoreLaunch.pid}',
          );
        } else {
          commonPrint.log(
            'OHOS native child process unavailable pid=$childPid, fallback to embedded core',
            logLevel: LogLevel.warning,
          );
          final embeddedPid = await app?.startEmbeddedCore(
            _transport.address,
            await appPath.homeDirPath,
          );
          if (embeddedPid != null && embeddedPid > 0) {
            _ohosCoreLaunch = const OhosCoreLaunch.embedded();
            commonPrint.log('Started OHOS embedded core via native bridge');
          } else {
            commonPrint.log(
              'OHOS embedded core unavailable pid=$embeddedPid, fallback to bundled executable',
              logLevel: LogLevel.warning,
            );
            final sourcePath = await _resolveOhosCoreExecutablePath();
            final pid = await app?.startBundledCoreProcess(
              sourcePath,
              _transport.address,
              await appPath.homeDirPath,
            );
            if (pid == null || pid <= 0) {
              throw StateError(
                'startBundledCoreProcess returned invalid pid: $pid',
              );
            }
            _ohosCoreLaunch = OhosCoreLaunch.bundled(pid: pid);
            commonPrint.log(
              'Started OHOS core executable via native bridge pid=${_ohosCoreLaunch.pid} source=$sourcePath',
            );
          }
        }
        unawaited(() async {
          await Future<void>.delayed(const Duration(seconds: 1));
          await _dumpOhosCoreLogs('after-start-1s');
          await Future<void>.delayed(const Duration(seconds: 2));
          await _dumpOhosCoreLogs('after-start-3s');
        }());
      } else {
        _process = await _startDesktopProcess(_coreExecutablePath(), [
          _transport.address,
        ]);
      }
    } catch (e) {
      commonPrint.log(
        'Failed to start core process: $e',
        logLevel: LogLevel.error,
      );
      _handleInvokeCrashEvent();
      return false;
    }
    _process?.stdout.listen((_) {});
    _process?.stderr.listen((e) {
      final error = utf8.decode(e);
      if (error.isNotEmpty) {
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    });
    return _waitForConnection();
  }

  Future<bool> _waitForConnection() async {
    try {
      await _transport.connectionCompleter.future.timeout(
        _connectionTimeoutDuration,
      );
      return true;
    } on TimeoutException {
      commonPrint.log(
        'Core transport connection timeout after ${_connectionTimeoutDuration.inSeconds}s',
        logLevel: LogLevel.error,
      );
      if (system.isOhos) {
        await _stopOhosTrackedCore();
      } else {
        if (system.isWindows) {
          await request.stopCoreByHelper();
        }
        _process?.kill();
        _process = null;
      }
      return false;
    }
  }

  Future<void> _stopOhosTrackedCore() async {
    final launch = _ohosCoreLaunch;
    final hadTrackedCore = _ohosCoreLaunch.hasTrackedCore;
    final stopped = hadTrackedCore
        ? (await app?.stopTrackedCore() ?? false)
        : true;
    commonPrint.log(
      '[OHOS-CORE] stopTrackedCore hadTrackedCore=$hadTrackedCore stopped=$stopped mode=${launch.mode.name} pid=${launch.pid}',
      logLevel: stopped ? LogLevel.info : LogLevel.warning,
    );
    _ohosCoreLaunch = resolveOhosCoreLaunchAfterStopAttempt(
      launch,
      stopped: stopped,
    );
  }

  Future<String> _resolveOhosCoreExecutablePath() async {
    final candidates = [
      ...appPath.ohosCorePathCandidates,
      await appPath.ohosBundledCorePath,
    ];
    for (final candidate in candidates) {
      if ((candidate.contains('/bundle/libs/') ||
              candidate.contains('/public/com.follow.clash/libs/')) &&
          (candidate.endsWith('/libFlClashCore.so') ||
              candidate.endsWith('/FlClashCore'))) {
        commonPrint.log(
          '[OHOS-CORE] prefer packaged executable candidate=$candidate',
        );
        return candidate;
      }
    }
    for (final candidate in candidates) {
      final exists = await File(candidate).exists();
      commonPrint.log(
        '[OHOS-CORE] probe executable candidate=$candidate exists=$exists',
      );
      if (exists) {
        commonPrint.log('[OHOS-CORE] use executable candidate=$candidate');
        return candidate;
      }
    }
    final fallback = await appPath.ohosBundledCorePath;
    commonPrint.log(
      '[OHOS-CORE] no executable candidate exists, fallback=$fallback',
      logLevel: LogLevel.warning,
    );
    return fallback;
  }

  @override
  FutureOr<bool> destroy() async {
    await shutdown(false);
    await _transport.close();
    return true;
  }

  Future<void> sendMessage(String message) async {
    await _transport.connectionCompleter.future;
    _transport.send(message);
  }

  Future<void> _sendInvokeMessage<T>({
    required String id,
    required Completer<T?> completer,
    required String message,
  }) async {
    try {
      await _transport.connectionCompleter.future;
    } catch (_) {
      return;
    }
    final pendingCompleter = _callbackCompleterMap[id];
    if (!identical(pendingCompleter, completer) || completer.isCompleted) {
      commonPrint.log('Skip stale invoke send id=$id');
      return;
    }
    _transport.send(message);
  }

  @override
  Future<bool> shutdown(bool isUser) async {
    _shutdownCompleter = Completer();
    _suppressDisconnectCrash = true;
    final wasConnected = _transport.connectionCompleter.isCompleted;
    if (system.isWindows) {
      await request.stopCoreByHelper();
    }
    if (system.isOhos) {
      if (wasConnected) {
        try {
          await invoke<bool>(
            method: ActionMethod.shutdown,
            timeout: const Duration(seconds: 2),
          );
        } catch (_) {}
      }
      await _transport.disconnect();
      await _stopOhosTrackedCore();
      _process?.kill();
      _process = null;
      _clearCompleter();
      _suppressDisconnectCrash = false;
      return true;
    }
    _transport.disconnected();
    _process?.kill();
    _process = null;
    _clearCompleter();
    if (isUser && wasConnected) {
      return _shutdownCompleter.future;
    }
    if (!wasConnected) {
      _suppressDisconnectCrash = false;
    }
    return true;
  }

  void _clearCompleter() {
    for (final completer in _callbackCompleterMap.values) {
      completer.safeCompleter(null);
    }
    _callbackCompleterMap.clear();
  }

  @override
  Future<String> preload() async {
    final connected = await start();
    if (!connected) {
      return 'core connection timeout';
    }
    return '';
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    final completer = Completer<T?>();
    _callbackCompleterMap[id] = completer;
    unawaited(
      _sendInvokeMessage<T>(
        id: id,
        completer: completer,
        message: json.encode(Action(id: id, method: method, data: data)),
      ),
    );
    final future = completer.future.withTimeout(
      timeout: timeout,
      onLast: () {
        final pendingCompleter = _callbackCompleterMap[id];
        pendingCompleter?.safeCompleter(null);
        _callbackCompleterMap.remove(id);
      },
      tag: id,
      onTimeout: () => null,
    );
    try {
      return await future;
    } finally {
      _callbackCompleterMap.remove(id);
    }
  }

  @override
  Completer get completer => _transport.connectionCompleter;
}

final coreService = (system.isDesktop || system.isOhos) ? CoreService() : null;
