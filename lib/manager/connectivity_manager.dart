import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wifi_ssid/wifi_ssid.dart';

class ConnectivityManager extends StatefulWidget {
  final Function(List<ConnectivityResult> results)? onConnectivityChanged;
  final Widget child;

  const ConnectivityManager({
    super.key,
    this.onConnectivityChanged,
    required this.child,
  });

  @override
  State<ConnectivityManager> createState() => _ConnectivityManagerState();
}

class _ConnectivityManagerState extends State<ConnectivityManager> {
  StreamSubscription<List<ConnectivityResult>>? subscription;

  @override
  void initState() {
    super.initState();
    if (system.isOhos) {
      commonPrint.log(
        'skip connectivity listen on ohos: plugin not implemented',
      );
      return;
    }
    try {
      subscription = Connectivity().onConnectivityChanged.listen((results) {
        if (results.contains(ConnectivityResult.wifi)) {
          WifiSsidManager.instance.getSsid().then((ssid) {
            globalState.container.read(currentSSIDProvider.notifier).value =
                ssid;
            commonPrint.log('Wi-fi SSID: $ssid ', logLevel: LogLevel.info);
          });
        } else {
          globalState.container.read(currentSSIDProvider.notifier).value = null;
        }
        if (widget.onConnectivityChanged != null) {
          widget.onConnectivityChanged!(results);
        }
      });
    } on MissingPluginException catch (error) {
      commonPrint.log(
        'connectivity listen unavailable: $error',
        logLevel: LogLevel.warning,
      );
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
