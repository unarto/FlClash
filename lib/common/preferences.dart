import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

class Preferences {
  static Preferences? _instance;
  Completer<SharedPreferences?> sharedPreferencesCompleter = Completer();
  Completer<File?> fileStoreCompleter = Completer();

  Future<bool> get isInit async {
    if (system.isOhos) {
      return await fileStoreCompleter.future != null;
    }
    return await sharedPreferencesCompleter.future != null;
  }

  Preferences._internal() {
    if (system.isOhos) {
      sharedPreferencesCompleter.complete(null);
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

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<int> getVersion() async {
    if (system.isOhos) {
      final configMap = await _readFileStore();
      return configMap['version'] as int? ?? 0;
    }
    final preferences = await sharedPreferencesCompleter.future;
    return preferences?.getInt('version') ?? 0;
  }

  Future<void> setVersion(int version) async {
    if (system.isOhos) {
      final configMap = await _readFileStore();
      configMap['version'] = version;
      await _writeFileStore(configMap);
      return;
    }
    final preferences = await sharedPreferencesCompleter.future;
    await preferences?.setInt('version', version);
  }

  Future<void> saveShareState(SharedState shareState) async {
    if (system.isOhos) {
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
      if (system.isOhos) {
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
      if (system.isOhos) {
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
      if (system.isOhos) {
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
    return Config.fromJson(configMap);
  }

  Future<bool> saveConfig(Config config) async {
    if (system.isOhos) {
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
    if (system.isOhos) {
      await _writeFileStore({});
      return;
    }
    final sharedPreferencesIns = await sharedPreferencesCompleter.future;
    await sharedPreferencesIns?.clear();
  }

  Future<Map<String, Object?>> _readFileStore() async {
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
    final file = await fileStoreCompleter.future;
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(json.encode(data));
  }
}

final preferences = Preferences();
