import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

import 'interface.dart';
import 'transport.dart';

class CoreService extends CoreHandlerInterface {
  static CoreService? _instance;

  late final IPCCoreTransport _transport;

  Completer<bool> _shutdownCompleter = Completer();

  final Map<String, Completer> _callbackCompleterMap = {};

  Process? _process;
  int? _ohosChildPid;

  factory CoreService() {
    _instance ??= CoreService._internal();
    return _instance!;
  }

  CoreService._internal() {
    _transport = IPCCoreTransport(
      address: system.isWindows ? windowsPipeName : unixSocketPath,
    );
    _initServer();
  }

  Future<void> handleResult(ActionResult result) async {
    final completer = _callbackCompleterMap[result.id];
    final data = await parasResult(result);
    if (result.id?.isEmpty == true) {
      coreEventManager.sendEvent(CoreEvent.fromJson(result.data));
    }
    if (completer?.isCompleted == true) {
      return;
    }
    completer?.complete(data);
  }

  Future<void> _initServer() async {
    await _transport.init();

    _transport.onDisconnect = () {
      _handleInvokeCrashEvent();
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
              handleResult(ActionResult.fromJson(dataJson));
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
    for (final fileName in const ['flclash-bridge.log', 'flclash-core.log']) {
      final file = File(join(homeDir, fileName));
      if (!await file.exists()) {
        commonPrint.log('[OHOS-CORE] $tag $fileName missing');
        continue;
      }
      final content = await file.readAsString();
      commonPrint.log('[OHOS-CORE] $tag $fileName => $content');
    }
  }

  Future<void> start() async {
    if (_process != null) {
      await shutdown(false);
    }
    await _transport.readyCompleter.future;
    if (system.isWindows && await system.checkIsAdmin()) {
      final isSuccess = await request.startCoreByHelper(_transport.address);
      if (isSuccess) {
        await _transport.connectionCompleter.future;
        return;
      }
    }
    try {
      if (system.isOhos) {
        try {
          _ohosChildPid = await app?.startCoreChildProcess(_transport.address);
          commonPrint.log('Started OHOS core child process pid=$_ohosChildPid');
          await _transport.connectionCompleter.future;
          return;
        } on PlatformException catch (e) {
          commonPrint.log(
            'OHOS native child process unavailable, fallback to bundled exec: $e',
            logLevel: LogLevel.warning,
          );
        }
        final sourcePath = await appPath.ohosBundledCorePath;
        for (final fileName in const [
          'flclash-bridge.log',
          'flclash-core.log',
        ]) {
          await File(join(await appPath.homeDirPath, fileName)).safeDelete();
        }
        final pid = await app?.startBundledCoreProcess(
          sourcePath,
          _transport.address,
        );
        if (pid == null || pid <= 0) {
          throw StateError(
            'startBundledCoreProcess returned invalid pid: $pid',
          );
        }
        _ohosChildPid = pid;
        commonPrint.log(
          'Started OHOS core executable via native bridge pid=$_ohosChildPid source=$sourcePath',
        );
        unawaited(() async {
          await Future<void>.delayed(const Duration(seconds: 1));
          await _dumpOhosCoreLogs('after-start-1s');
          await Future<void>.delayed(const Duration(seconds: 2));
          await _dumpOhosCoreLogs('after-start-3s');
        }());
      } else {
        _process = await Process.start(appPath.corePath, [_transport.address]);
      }
    } catch (e) {
      commonPrint.log(
        'Failed to start core process: $e',
        logLevel: LogLevel.error,
      );
      _handleInvokeCrashEvent();
      return;
    }
    _process?.stdout.listen((_) {});
    _process?.stderr.listen((e) {
      final error = utf8.decode(e);
      if (error.isNotEmpty) {
        commonPrint.log(error, logLevel: LogLevel.warning);
      }
    });
    await _transport.connectionCompleter.future;
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

  @override
  Future<bool> shutdown(bool isUser) async {
    _shutdownCompleter = Completer();
    if (system.isWindows) {
      await request.stopCoreByHelper();
    }
    if (system.isOhos) {
      if (_transport.connectionCompleter.isCompleted) {
        try {
          await invoke<bool>(
            method: ActionMethod.shutdown,
            timeout: const Duration(seconds: 2),
          );
        } catch (_) {}
      }
      await _transport.disconnect();
      _process?.kill();
      _process = null;
      _ohosChildPid = null;
      _clearCompleter();
      return true;
    }
    _transport.disconnected();
    _process?.kill();
    _process = null;
    _clearCompleter();
    if (isUser) {
      return _shutdownCompleter.future;
    } else {
      return true;
    }
  }

  void _clearCompleter() {
    for (final completer in _callbackCompleterMap.values) {
      completer.safeCompleter(null);
    }
  }

  @override
  Future<String> preload() async {
    await start();
    return '';
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    _callbackCompleterMap[id] = Completer<T?>();
    sendMessage(json.encode(Action(id: id, method: method, data: data)));
    return (_callbackCompleterMap[id] as Completer<T?>).future.withTimeout(
      timeout: timeout,
      onLast: () {
        final completer = _callbackCompleterMap[id];
        completer?.safeCompleter(null);
        _callbackCompleterMap.remove(id);
      },
      tag: id,
      onTimeout: () => null,
    );
  }

  @override
  Completer get completer => _transport.connectionCompleter;
}

final coreService = (system.isDesktop || system.isOhos) ? CoreService() : null;
