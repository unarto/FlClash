import 'dart:async';
import 'dart:convert';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/event.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';

import 'interface.dart';

class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;
  static const _ohosEventPollInterval = Duration(milliseconds: 300);

  Completer<bool> _connectedCompleter = Completer();
  bool _isConsumingOhosEvents = false;
  Timer? _ohosEventPollTimer;

  CoreLib._internal() {
    if (system.isOhos) {
      commonPrint.log('[OHOS-CORE] create CoreLib instance');
    }
  }

  @override
  Future<String> preload() async {
    if (_connectedCompleter.isCompleted) {
      return 'core is connected';
    }
    if (system.isOhos) {
      commonPrint.log('[OHOS-CORE] preload begin');
      _connectedCompleter.complete(true);
      _ensureOhosEventPolling();
      commonPrint.log('[OHOS-CORE] preload connected completer completed');
      return '';
    }
    final res = await service?.init();
    if (res?.isEmpty != true) {
      return res ?? '';
    }
    _connectedCompleter.complete(true);
    final syncRes = await service?.syncState(
      globalState.container.read(sharedStateProvider),
    );
    return syncRes ?? '';
  }

  factory CoreLib() {
    _instance ??= CoreLib._internal();
    return _instance!;
  }

  Future<T?> _handleOhosResult<T>(String data) async {
    try {
      final dataJson = await data.trim().commonToJSON<dynamic>();
      final result = ActionResult.fromJson(dataJson);
      if (result.id?.isEmpty ?? true) {
        commonPrint.log(
          '[OHOS-CORE] event result method=${result.method.name} dataType=${result.data.runtimeType}',
        );
        if (result.method == ActionMethod.message) {
          final coreEvent = CoreEvent.fromJson(result.data);
          commonPrint.log(
            '[OHOS-CORE] event message type=${coreEvent.type.name}',
          );
          if (coreEvent.type == CoreEventType.request) {
            commonPrint.log(
              '[OHOS-CORE] request event payload=${coreEvent.data}',
            );
          }
          coreEventManager.sendEvent(coreEvent);
          return null;
        }
        coreEventManager.sendEvent(CoreEvent.fromJson(result.data));
        return null;
      }
      if (result.method == ActionMethod.getConnections) {
        commonPrint.log('[OHOS-CORE] getConnections raw=${result.data}');
      }
      return parasResult<T>(result);
    } catch (e) {
      commonPrint.log(
        'Failed to parse OHOS core result: $e payload=$data',
        logLevel: LogLevel.error,
      );
      return null;
    }
  }

  Future<void> _consumeOhosEvents() async {
    if (!system.isOhos || _isConsumingOhosEvents) {
      return;
    }
    _isConsumingOhosEvents = true;
    try {
      final payload = await app?.consumeCoreEvents();
      if (payload == null || payload.isEmpty) {
        return;
      }
      commonPrint.log(
        '[OHOS-CORE] consume events raw length=${payload.length}',
      );
      final events = await payload.commonToJSON<List<dynamic>>();
      if (events.isNotEmpty) {
        commonPrint.log('[OHOS-CORE] consume events count=${events.length}');
      }
      for (final item in events) {
        await _handleOhosResult<void>(json.encode(item));
      }
    } catch (e) {
      commonPrint.log(
        '[OHOS-CORE] consume events failed error=$e',
        logLevel: LogLevel.error,
      );
    } finally {
      _isConsumingOhosEvents = false;
    }
  }

  void _ensureOhosEventPolling() {
    if (!system.isOhos || _ohosEventPollTimer != null) {
      return;
    }
    commonPrint.log('[OHOS-CORE] start event polling');
    _ohosEventPollTimer = Timer.periodic(_ohosEventPollInterval, (_) {
      unawaited(_consumeOhosEvents());
    });
  }

  void _stopOhosEventPolling() {
    if (_ohosEventPollTimer == null) {
      return;
    }
    commonPrint.log('[OHOS-CORE] stop event polling');
    _ohosEventPollTimer?.cancel();
    _ohosEventPollTimer = null;
  }

  @override
  FutureOr<bool> destroy() async {
    _stopOhosEventPolling();
    return true;
  }

  @override
  Future<bool> shutdown(_) async {
    if (!_connectedCompleter.isCompleted) {
      return false;
    }
    if (system.isOhos) {
      commonPrint.log('[OHOS-CORE] shutdown begin');
      _stopOhosEventPolling();
      final result = await invoke<bool>(
        method: ActionMethod.shutdown,
      ).withTimeout(onTimeout: () => false);
      _connectedCompleter = Completer();
      commonPrint.log('[OHOS-CORE] shutdown done result=$result');
      return result ?? false;
    }
    _connectedCompleter = Completer();
    return service?.shutdown() ?? true;
  }

  @override
  Future<bool> startListener() async {
    if (system.isOhos) {
      _ensureOhosEventPolling();
      return super.startListener();
    }
    await super.startListener();
    await service?.start();
    return true;
  }

  @override
  Future<bool> stopListener() async {
    if (system.isOhos) {
      return super.stopListener();
    }
    await super.stopListener();
    await service?.stop();
    return true;
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    if (system.isOhos) {
      final id = '${method.name}#${utils.id}';
      await _consumeOhosEvents();
      commonPrint.log('[OHOS-CORE] invoke $id begin');
      final action = json.encode(Action(id: id, method: method, data: data));
      final result = await app
          ?.invokeCore(action)
          .withTimeout(timeout: timeout, onTimeout: () => null);
      if (result == null || result.isEmpty) {
        commonPrint.log(
          '[OHOS-CORE] invoke $id empty result',
          logLevel: LogLevel.error,
        );
        return null;
      }
      final parsed = await _handleOhosResult<T>(result);
      await _consumeOhosEvents();
      commonPrint.log('[OHOS-CORE] invoke $id done');
      return parsed;
    }
    final id = '${method.name}#${utils.id}';
    final result = await service
        ?.invokeAction(Action(id: id, method: method, data: data))
        .withTimeout(onTimeout: () => null);
    if (result == null) {
      return null;
    }
    return parasResult<T>(result);
  }

  @override
  Completer get completer => _connectedCompleter;
}

CoreLib? get coreLib => (system.isAndroid || system.isOhos) ? CoreLib() : null;
