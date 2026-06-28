import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';

abstract mixin class CoreEventListener {
  void onLog(Log log) {}

  void onDelay(Delay delay) {}

  void onRequest(TrackerInfo connection) {}

  void onLoaded(String providerName) {}

  void onCrash(String message) {}
}

class CoreEventManager {
  final _controller = StreamController<CoreEvent>();

  CoreEventManager._() {
    _controller.stream.listen((event) {
      for (final CoreEventListener listener in _listeners) {
        switch (event.type) {
          case CoreEventType.log:
            final log = Log.fromJson(event.data);
            final payload = log.payload;
            if (payload.contains('[DNS]') ||
                payload.contains('[TUN]') ||
                payload.contains('[sing-tun]') ||
                payload.contains('DNS server')) {
              commonPrint.log('[OHOS-CORE-LOG] ${log.payload}');
            }
            listener.onLog(log);
            break;
          case CoreEventType.delay:
            listener.onDelay(Delay.fromJson(event.data));
            break;
          case CoreEventType.request:
            try {
              final trackerInfo = TrackerInfo.fromJson(event.data);
              commonPrint.log(
                '[OHOS-CORE] dispatch request event id=${trackerInfo.id} host=${trackerInfo.metadata.host} chains=${trackerInfo.chains.join(" -> ")}',
              );
              listener.onRequest(trackerInfo);
            } catch (e) {
              commonPrint.log(
                '[OHOS-CORE] request event parse failed error=$e payload=${event.data}',
                logLevel: LogLevel.error,
              );
            }
            break;
          case CoreEventType.loaded:
            listener.onLoaded(event.data);
            break;
          case CoreEventType.crash:
            listener.onCrash(event.data);
            break;
        }
      }
    });
  }

  static final CoreEventManager instance = CoreEventManager._();

  final ObserverList<CoreEventListener> _listeners =
      ObserverList<CoreEventListener>();

  bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  void sendEvent(CoreEvent event) {
    _controller.add(event);
  }

  void addListener(CoreEventListener listener) {
    _listeners.add(listener);
  }

  void removeListener(CoreEventListener listener) {
    _listeners.remove(listener);
  }
}

final coreEventManager = CoreEventManager.instance;
