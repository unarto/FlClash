import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'common.dart';

class Preferences {
  static Preferences? _instance;
  final bool _isOhos;
  final Future<void> Function() _ensureOhosPaths;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();
  Completer<File?> fileStoreCompleter = Completer();

  Future<bool> get isInit async {
    if (_isOhos) {
      await _ensureOhosPaths();
      return await fileStoreCompleter.future != null;
    }
    return await sharedPreferencesCompleter.future != null;
  }

  Preferences._internal({
    bool? isOhos,
    Future<void> Function()? ensureOhosPaths,
    File? ohosFileStore,
  }) : _isOhos = isOhos ?? system.isOhos,
       _ensureOhosPaths = ensureOhosPaths ?? appPath.initOhosPaths {
    if (_isOhos) {
      sharedPreferencesCompleter.complete(null);
      if (ohosFileStore != null) {
        fileStoreCompleter.complete(ohosFileStore);
        return;
      }
      appPath.sharedPreferencesPath
          .then((path) async {
            final file = File(path);
            await file.parent.create(recursive: true);
            if (!await file.exists()) {
              await file.writeAsString('{}');
            }
            fileStoreCompleter.complete(file);
          })
          .onError((_, _) {
            fileStoreCompleter.complete(null);
          });
      return;
    }
    SharedPreferences.getInstance()
        .then((value) => sharedPreferencesCompleter.complete(value))
        .onError((_, _) => sharedPreferencesCompleter.complete(null));
    fileStoreCompleter.complete(null);
  }

  @visibleForTesting
  Preferences.testOhos({
    required Future<void> Function() ensureOhosPaths,
    File? fileStore,
  }) : this._internal(
         isOhos: true,
         ensureOhosPaths: ensureOhosPaths,
         ohosFileStore: fileStore,
       );

  @visibleForTesting
  Preferences.testOhosWithFileStore({
    required Future<void> Function() ensureOhosPaths,
    required File fileStore,
  }) : _isOhos = true,
       _ensureOhosPaths = ensureOhosPaths {
    sharedPreferencesCompleter.complete(null);
    fileStoreCompleter.complete(fileStore);
  }

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<int> getVersion() async {
    if (_isOhos) {
      final configMap = await _readFileStore();
      return configMap['version'] as int? ?? 0;
    }
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    if (_isOhos) {
      final configMap = await _readFileStore();
      configMap['version'] = version;
      await _writeFileStore(configMap);
      return;
    }
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setInt('version', version);
  }

  Future<void> saveShareState(SharedState shareState) async {
    if (_isOhos) {
      final configMap = await _readFileStore();
      configMap['sharedState'] = json.encode(shareState);
      await _writeFileStore(configMap);
      return;
    }
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setString('sharedState', json.encode(shareState));
  }

  Future<Map<String, Object?>?> getConfigMap() async {
    try {
      if (_isOhos) {
        final configMap = await _readFileStore();
        final configString = configMap[configKey] as String?;
        if (configString == null) return null;
        return Map<String, Object?>.from(json.decode(configString));
      }
      final preferences = await sharedPreferencesCompleter.future;
      final configString = preferences?.getString(configKey);
      if (configString == null) return null;
      final Map<String, Object?>? configMap = json.decode(configString);
      return configMap;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> getClashConfigMap() async {
    try {
      if (_isOhos) {
        final configMap = await _readFileStore();
        final clashConfigString = configMap[clashConfigKey] as String?;
        if (clashConfigString == null) return null;
        return Map<String, Object?>.from(json.decode(clashConfigString));
      }
      final preferences = await sharedPreferencesCompleter.future;
      final clashConfigString = preferences?.getString(clashConfigKey);
      if (clashConfigString == null) return null;
      return json.decode(clashConfigString);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearClashConfig() async {
    try {
      if (_isOhos) {
        final configMap = await _readFileStore();
        configMap.remove(clashConfigKey);
        await _writeFileStore(configMap);
        return;
      }
      final preferences = await sharedPreferencesCompleter.future;
      await preferences?.remove(clashConfigKey);
      return;
    } catch (_) {
      return;
    }
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) {
      return null;
    }
    return Config.realFromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    if (_isOhos) {
      final configMap = await _readFileStore();
      configMap[configKey] = json.encode(config);
      await _writeFileStore(configMap);
      try {
        final file = await fileStoreCompleter.future;
        commonPrint.log(
          '[ohos-preferences] saveConfig path=${file?.path} '
          'profileId=${config.currentProfileId} '
          'routeMode=${config.networkProps.routeMode.name} '
          'ipv6=${config.patchClashConfig.ipv6}',
        );
      } catch (_) {}
      return true;
    }
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.setString(configKey, json.encode(config)) ?? false;
  }

  Future<void> clearPreferences() async {
    if (_isOhos) {
      await _writeFileStore({});
      return;
    }
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.clear();
  }

  Future<Map<String, Object?>> _readFileStore() async {
    await _ensureOhosFileStoreReady();
    final file = await fileStoreCompleter.future;
    if (file == null || !await file.exists()) {
      return {};
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return {};
    }
    return Map<String, Object?>.from(json.decode(content));
  }

  Future<void> _writeFileStore(Map<String, Object?> data) async {
    await _ensureOhosFileStoreReady();
    final file = await fileStoreCompleter.future;
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(data));
  }

  Future<void> _ensureOhosFileStoreReady() async {
    if (_isOhos) {
      await _ensureOhosPaths();
    }
  }
}

final preferences = Preferences();
