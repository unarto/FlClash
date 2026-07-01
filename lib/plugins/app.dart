import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class App {
  static App? _instance;
  late MethodChannel methodChannel;
  Function()? onExit;
  Future<void> Function(String link)? onAppLink;
  Future<void> Function(Map<String, dynamic>?)? onPendingDebugVpnStart;

  App._internal() {
    methodChannel = const MethodChannel('$packageName/app');
    methodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'appLink':
          final link = call.arguments as String? ?? '';
          if (onAppLink != null && link.isNotEmpty) {
            await onAppLink!(link);
            return;
          }
          throw MissingPluginException();
        case 'pendingDebugVpnStart':
          final pending = call.arguments == null
              ? null
              : Map<String, dynamic>.from(call.arguments as Map);
          if (onPendingDebugVpnStart != null) {
            await onPendingDebugVpnStart!(pending);
            return;
          }
          throw MissingPluginException();
        case 'exit':
          if (onExit != null) {
            await onExit!();
          }
          return;
        default:
          throw MissingPluginException();
      }
    });
  }

  factory App() {
    _instance ??= App._internal();
    return _instance!;
  }

  Future<bool?> moveTaskToBack() async {
    return methodChannel.invokeMethod<bool>('moveTaskToBack');
  }

  Future<bool?> exitApp() async {
    return methodChannel.invokeMethod<bool>('exitApp');
  }

  Future<Map<String, String>?> getAppPaths() async {
    final result = await methodChannel.invokeMapMethod<String, String>(
      'getAppPaths',
    );
    return result == null ? null : Map<String, String>.from(result);
  }

  Future<String?> consumePendingLink() {
    return methodChannel.invokeMethod<String>('consumePendingLink');
  }

  Future<bool?> updateAppLinkListenerReady(bool value) {
    return methodChannel.invokeMethod<bool>('updateAppLinkListenerReady', value);
  }

  Future<int?> startCoreChildProcess(String entryParams) {
    return methodChannel.invokeMethod<int>('startCoreChildProcess', {
      'entryParams': entryParams,
    });
  }

  Future<int?> startBundledCoreProcess(
    String sourcePath,
    String socketPath,
    String logDirPath,
  ) {
    return methodChannel.invokeMethod<int>('startBundledCoreProcess', {
      'sourcePath': sourcePath,
      'socketPath': socketPath,
      'logDirPath': logDirPath,
    });
  }

  Future<int?> startEmbeddedCore(String socketPath, String logDirPath) {
    return methodChannel.invokeMethod<int>('startEmbeddedCore', {
      'socketPath': socketPath,
      'logDirPath': logDirPath,
    });
  }

  Future<bool?> stopTrackedCore() {
    return methodChannel.invokeMethod<bool>('stopTrackedCore');
  }

  Future<String?> invokeCore(String action) {
    return methodChannel.invokeMethod<String>('invokeCore', {'action': action});
  }

  Future<String?> consumeCoreEvents() {
    return methodChannel.invokeMethod<String>('consumeCoreEvents');
  }

  Future<bool?> startVpn({
    required String stack,
    required bool ipv6,
    required String initParamsJson,
    required String setupParamsJson,
    required String coreSocketPath,
  }) {
    return methodChannel.invokeMethod<bool>('startVpn', {
      'stack': stack,
      'ipv6': ipv6,
      'initParamsJson': initParamsJson,
      'setupParamsJson': setupParamsJson,
      'coreSocketPath': coreSocketPath,
    });
  }

  Future<bool?> stopVpn() {
    return methodChannel.invokeMethod<bool>('stopVpn');
  }

  Future<bool?> getVpnRunning() {
    return methodChannel.invokeMethod<bool>('getVpnRunning');
  }

  Future<Map<String, dynamic>?> consumePendingDebugVpnStart() async {
    final result = await methodChannel.invokeMethod<dynamic>(
      'consumePendingDebugVpnStart',
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  Future<bool?> updatePendingDebugVpnStartListenerReady(bool value) {
    return methodChannel.invokeMethod<bool>(
      'updatePendingDebugVpnStartListenerReady',
      value,
    );
  }

  Future<bool?> markExecutable(String path) {
    return methodChannel.invokeMethod<bool>('markExecutable', {'path': path});
  }

  Future<String?> importImageToGallery(
    String path, {
    String title = 'flclash_qr_test',
  }) {
    return methodChannel.invokeMethod<String>('importImageToGallery', {
      'path': path,
      'title': title,
    });
  }

  Future<String?> prepareGalleryTestImage(
    String path, {
    String title = 'flclash_qr_test',
  }) {
    return methodChannel.invokeMethod<String>('prepareGalleryTestImage', {
      'path': path,
      'title': title,
    });
  }

  Future<String?> writeFileToSharedDownload(
    String path, {
    String fileName = 'jisu_qr_test.png',
  }) {
    return methodChannel.invokeMethod<String>('writeFileToSharedDownload', {
      'path': path,
      'fileName': fileName,
    });
  }

  Future<String?> getLastImportedGalleryUri() {
    return methodChannel.invokeMethod<String>('getLastImportedGalleryUri');
  }

  Future<String?> getLastImportedGalleryIdentifier() {
    return methodChannel.invokeMethod<String>('getLastImportedGalleryIdentifier');
  }

  Future<String?> getLastFilePickerState() {
    return methodChannel.invokeMethod<String>('getLastFilePickerState');
  }

  Future<bool?> openExternalUrl(String url) {
    return methodChannel.invokeMethod<bool>('openExternalUrl', {'url': url});
  }

  Future<bool?> setClipboardText(String text) {
    return methodChannel.invokeMethod<bool>('setClipboardText', {'text': text});
  }

  Future<String?> getClipboardText() {
    return methodChannel.invokeMethod<String>('getClipboardText');
  }

  Future<List<Package>> getPackages() async {
    final packagesString = await methodChannel.invokeMethod<String>(
      'getPackages',
    );
    final List<dynamic> packagesRaw =
        (await packagesString?.commonToJSON<List<dynamic>>()) ?? [];
    return packagesRaw.map((e) => Package.fromJson(e)).toSet().toList();
  }

  Future<List<String>> getChinaPackageNames() async {
    final packageNamesString = await methodChannel.invokeMethod<String>(
      'getChinaPackageNames',
    );
    final List<dynamic> packageNamesRaw =
        await packageNamesString?.commonToJSON<List<dynamic>>() ?? [];
    return packageNamesRaw.map((e) => e.toString()).toList();
  }

  Future<bool?> requestNotificationsPermission() async {
    return methodChannel.invokeMethod<bool>('requestNotificationsPermission');
  }

  Future<bool> openFile(String path) async {
    return await methodChannel.invokeMethod<bool>('openFile', {'path': path}) ??
        false;
  }

  Future<ImageProvider?> getPackageIcon(String packageName) async {
    final path = await methodChannel.invokeMethod<String>('getPackageIcon', {
      'packageName': packageName,
    });
    if (path == null) {
      return null;
    }
    return FileImage(File(path));
  }

  Future<bool?> tip(String? message) async {
    return methodChannel.invokeMethod<bool>('tip', {'message': '$message'});
  }

  Future<bool?> initShortcuts() async {
    return methodChannel.invokeMethod<bool>(
      'initShortcuts',
      currentAppLocalizations.toggle,
    );
  }

  Future<bool?> updateExcludeFromRecents(bool value) async {
    return methodChannel.invokeMethod<bool>('updateExcludeFromRecents', {
      'value': value,
    });
  }

  Future<bool?> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    return methodChannel.invokeMethod<bool>('isBatteryOptimizationDisabled');
  }

  Future<bool?> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    return methodChannel.invokeMethod<bool>('openBatteryOptimizationSettings');
  }

  Future<bool?> openAppSettings() async {
    if (!Platform.isAndroid) return false;
    return methodChannel.invokeMethod<bool>('openAppSettings');
  }
}

final app = (system.isAndroid || system.isOhos) ? App() : null;
