import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';

import 'print.dart';
import 'system.dart';

typedef InstallConfigCallBack = void Function(String url);

class LinkManager {
  static LinkManager? _instance;
  late AppLinks _appLinks;
  StreamSubscription? subscription;

  LinkManager._internal() {
    _appLinks = AppLinks();
  }

  Future<void> initAppLinksListen(
    Function(String url) installConfigCallBack,
  ) async {
    commonPrint.log('initAppLinksListen');
    destroy();
    if (system.isOhos) {
      app?.onAppLink = (link) async {
        commonPrint.log('onAppLink from ohos channel: $link');
        _handleUriString(link, installConfigCallBack);
      };
      final pendingLink = await app?.consumePendingLink();
      commonPrint.log('consumePendingLink on ohos: $pendingLink');
      _handleUriString(pendingLink, installConfigCallBack);
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
    final uri = Uri.tryParse(uriString);
    if (uri == null) {
      commonPrint.log(
        'invalid app link: $uriString',
        logLevel: LogLevel.warning,
      );
      return;
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
      app?.onAppLink = null;
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
