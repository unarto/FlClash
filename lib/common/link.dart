import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';

import 'print.dart';
import 'system.dart';

typedef InstallConfigCallBack = void Function(String url);

const _ohosLinkDedupeWindow = Duration(seconds: 2);

bool shouldHandleOhosLinkEvent({
  required String? lastUriString,
  required DateTime? lastHandledAt,
  required String uriString,
  required DateTime now,
}) {
  if (lastUriString != uriString) {
    return true;
  }
  if (lastHandledAt == null) {
    return true;
  }
  return now.difference(lastHandledAt) > _ohosLinkDedupeWindow;
}

class LinkManager {
  static LinkManager? _instance;
  late AppLinks _appLinks;
  StreamSubscription? subscription;
  String? _lastOhosUriString;
  DateTime? _lastOhosHandledAt;

  LinkManager._internal() {
    _appLinks = AppLinks();
  }

  Future<void> initAppLinksListen(
    Function(String url) installConfigCallBack,
  ) async {
    commonPrint.log('initAppLinksListen');
    destroy();
    if (system.isOhos) {
      await app?.updateAppLinkListenerReady(false);
      app?.onAppLink = (link) async {
        _handleUriString(link, installConfigCallBack);
      };
      while (true) {
        final pendingLink = await app?.consumePendingLink();
        if (pendingLink == null || pendingLink.isEmpty) {
          break;
        }
        _handleUriString(pendingLink, installConfigCallBack);
      }
      await app?.updateAppLinkListenerReady(true);
      return;
    }
    subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        commonPrint.log('onAppLink: $uri');
        _handleUri(uri, installConfigCallBack);
      },
      onError: (error, stackTrace) {
        if (error is MissingPluginException) {
          commonPrint.log(
            'app links listen unavailable: $error',
            logLevel: LogLevel.warning,
          );
          return;
        }
        commonPrint.log(
          'app links listen error: $error',
          logLevel: LogLevel.error,
        );
      },
    );
  }

  void _handleUriString(
    String? uriString,
    InstallConfigCallBack installConfigCallBack,
  ) {
    if (uriString == null || uriString.isEmpty) return;
    if (system.isOhos &&
        !shouldHandleOhosLinkEvent(
          lastUriString: _lastOhosUriString,
          lastHandledAt: _lastOhosHandledAt,
          uriString: uriString,
          now: DateTime.now(),
        )) {
      return;
    }
    final uri = Uri.tryParse(uriString);
    if (uri == null) {
      commonPrint.log(
        'invalid app link: $uriString',
        logLevel: LogLevel.warning,
      );
      return;
    }
    if (system.isOhos) {
      _lastOhosUriString = uriString;
      _lastOhosHandledAt = DateTime.now();
    }
    _handleUri(uri, installConfigCallBack);
  }

  void _handleUri(Uri uri, InstallConfigCallBack installConfigCallBack) {
    if (uri.host != 'install-config') return;
    final url = uri.queryParameters['url'];
    if (url != null) {
      installConfigCallBack(url);
    }
  }

  void destroy() {
    if (system.isOhos) {
      unawaited(app?.updateAppLinkListenerReady(false));
      app?.onAppLink = null;
      _lastOhosUriString = null;
      _lastOhosHandledAt = null;
    }
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
