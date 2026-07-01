import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppPath {
  static AppPath? _instance;
  Completer<Directory> dataDir = Completer();
  Completer<Directory> downloadDir = Completer();
  Completer<Directory> tempDir = Completer();
  Completer<Directory> cacheDir = Completer();
  Completer<String> bundleCodeDir = Completer();
  Future<void>? _initOhosPathsFuture;
  late String appDirPath;
  String ohosBundleCodeDirPath = '';
  String ohosCodeDirPath = '';
  String ohosNativeLibraryDirPath = '';

  AppPath._internal() {
    if (system.isOhos) {
      appDirPath = '';
      return;
    }
    appDirPath = join(dirname(Platform.resolvedExecutable));
    bundleCodeDir.complete(executableDirPath);
    getApplicationSupportDirectory().then((value) {
      dataDir.complete(value);
    });
    getTemporaryDirectory().then((value) {
      tempDir.complete(value);
    });
    getDownloadsDirectory().then((value) {
      downloadDir.complete(value);
    });
    getApplicationCacheDirectory().then((value) {
      cacheDir.complete(value);
    });
  }

  factory AppPath() {
    _instance ??= AppPath._internal();
    return _instance!;
  }

  @visibleForTesting
  AppPath.testOhos() {
    appDirPath = '';
  }

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  String get executableExtension {
    return system.isWindows ? '.exe' : '';
  }

  String get executableDirPath {
    final currentExecutablePath = Platform.resolvedExecutable;
    return dirname(currentExecutablePath);
  }

  String get corePath {
    if (system.isOhos) {
      if (ohosCodeDirPath.isEmpty || ohosNativeLibraryDirPath.isEmpty) {
        throw StateError('OHOS code path not initialized');
      }
      return join(ohosCodeDirPath, ohosNativeLibraryDirPath, 'FlClashCore');
    }
    return join(executableDirPath, 'FlClashCore$executableExtension');
  }

  List<String> get ohosCorePathCandidates {
    if (!system.isOhos) {
      return const [];
    }
    final candidates = <String>[];
    if (ohosNativeLibraryDirPath.isNotEmpty) {
      candidates.addAll([
        join(ohosNativeLibraryDirPath, 'FlClashCore'),
        join(ohosNativeLibraryDirPath, 'libFlClashCore.so'),
      ]);
    }
    if (ohosCodeDirPath.isNotEmpty) {
      candidates.addAll([
        join(ohosCodeDirPath, 'libs', 'arm64', 'FlClashCore'),
        join(ohosCodeDirPath, 'libs', 'arm64', 'libFlClashCore.so'),
        join(ohosCodeDirPath, 'libs', 'arm64-v8a', 'FlClashCore'),
        join(ohosCodeDirPath, 'libs', 'arm64-v8a', 'libFlClashCore.so'),
      ]);
    }
    if (ohosCodeDirPath.isNotEmpty && ohosNativeLibraryDirPath.isNotEmpty) {
      candidates.addAll([
        join(ohosCodeDirPath, ohosNativeLibraryDirPath, 'FlClashCore'),
        join(ohosCodeDirPath, ohosNativeLibraryDirPath, 'libFlClashCore.so'),
        join(ohosCodeDirPath, 'entry', ohosNativeLibraryDirPath, 'FlClashCore'),
        join(
          ohosCodeDirPath,
          'entry',
          ohosNativeLibraryDirPath,
          'libFlClashCore.so',
        ),
      ]);
    }
    if (ohosBundleCodeDirPath.isNotEmpty) {
      candidates.addAll([
        join(ohosBundleCodeDirPath, 'libs', 'arm64', 'FlClashCore'),
        join(ohosBundleCodeDirPath, 'libs', 'arm64', 'libFlClashCore.so'),
        join(ohosBundleCodeDirPath, 'libs', 'arm64-v8a', 'FlClashCore'),
        join(ohosBundleCodeDirPath, 'libs', 'arm64-v8a', 'libFlClashCore.so'),
        join(ohosBundleCodeDirPath, 'entry', 'libs', 'arm64', 'FlClashCore'),
        join(
          ohosBundleCodeDirPath,
          'entry',
          'libs',
          'arm64',
          'libFlClashCore.so',
        ),
      ]);
    }
    return candidates.toSet().toList();
  }

  String get helperPath {
    return join(executableDirPath, '$appHelperService$executableExtension');
  }

  Future<String> get downloadDirPath async {
    if (system.isOhos) {
      return 'file://docs/storage/Users/currentUser/Download';
    }
    final directory = await downloadDir.future;
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<String> get homeDirPath async {
    final directory = await dataDir.future;
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<String> get databasePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'database.sqlite');
  }

  Future<String> get backupFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'backup.zip');
  }

  Future<String> get restoreDirPath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'restore');
  }

  Future<String> get tempFilePath async {
    final mTempDir = await tempDir.future;
    return join(mTempDir.path, 'temp${utils.id}');
  }

  Future<String> get coreSafeTempFilePath async {
    if (!system.isOhos) {
      return tempFilePath;
    }
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, '.tmp', 'temp${utils.id}');
  }

  Future<String> get lockFilePath async {
    final homeDirPath = await appPath.homeDirPath;
    return join(homeDirPath, 'FlClash.lock');
  }

  Future<String> get configFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'config.yaml');
  }

  Future<String> get sharedFilePath async {
    final mHomeDirPath = await homeDirPath;
    return join(mHomeDirPath, 'shared.json');
  }

  Future<String> get sharedPreferencesPath async {
    final directory = await dataDir.future;
    return join(directory.path, 'shared_preferences.json');
  }

  Future<String> get profilesPath async {
    final directory = await dataDir.future;
    return join(directory.path, profilesDirectoryName);
  }

  Future<String> getProfilePath(String fileName) async {
    return join(await profilesPath, '$fileName.yaml');
  }

  Future<String> get scriptsDirPath async {
    final path = await homeDirPath;
    return join(path, 'scripts');
  }

  Future<String> getScriptPath(String fileName) async {
    final path = await scriptsDirPath;
    return join(path, '$fileName.js');
  }

  Future<String> getIconsCacheDir() async {
    final directory = await cacheDir.future;
    await directory.create(recursive: true);
    return join(directory.path, 'icons');
  }

  Future<String> getProvidersRootPath() async {
    final directory = await profilesPath;
    return join(directory, 'providers');
  }

  Future<String> getProvidersDirPath(String id) async {
    final directory = await profilesPath;
    return join(directory, 'providers', id);
  }

  Future<String> getProvidersFilePath(
    String id,
    String type,
    String url,
  ) async {
    final directory = await profilesPath;
    return join(directory, 'providers', id, type, url.toMd5());
  }

  Future<String> get tempPath async {
    final directory = await tempDir.future;
    await directory.create(recursive: true);
    return directory.path;
  }

  Future<String> get ohosBundledCorePath async {
    final directory = await dataDir.future;
    return join(directory.path, 'FlClashCore');
  }

  Future<void> initOhosPaths() async {
    if (!system.isOhos || dataDir.isCompleted) {
      return;
    }
    final pending = _initOhosPathsFuture;
    if (pending != null) {
      return pending;
    }
    final future = _loadOhosPaths();
    _initOhosPathsFuture = future;
    try {
      await future;
    } catch (_) {
      if (!dataDir.isCompleted) {
        _initOhosPathsFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _loadOhosPaths() async {
    final paths = await app?.getAppPaths();
    if (paths == null) {
      throw StateError('Failed to fetch OHOS app paths');
    }
    applyOhosAppPaths(paths);
  }

  @visibleForTesting
  Future<void> applyOhosAppPaths(Map<String, String> paths) async {
    final filesDirPath = paths['filesDir'];
    final tempDirPath = paths['tempDir'];
    final cacheDirPath = paths['cacheDir'];
    final bundleCodeDirPath = paths['bundleCodeDir'];
    final codeDirPath = paths['codePath'];
    final nativeLibraryDirPath = paths['nativeLibraryPath'];
    if (filesDirPath == null ||
        tempDirPath == null ||
        cacheDirPath == null ||
        bundleCodeDirPath == null ||
        codeDirPath == null ||
        nativeLibraryDirPath == null) {
      throw StateError('Incomplete OHOS app paths: $paths');
    }
    final filesDir = Directory(filesDirPath);
    final tempDirectory = Directory(tempDirPath);
    final cacheDirectory = Directory(cacheDirPath);
    final downloadsDir = Directory(join(filesDirPath, 'Downloads'));
    await filesDir.create(recursive: true);
    await tempDirectory.create(recursive: true);
    await cacheDirectory.create(recursive: true);
    await downloadsDir.create(recursive: true);
    appDirPath = filesDirPath;
    ohosBundleCodeDirPath = bundleCodeDirPath;
    ohosCodeDirPath = codeDirPath;
    ohosNativeLibraryDirPath = nativeLibraryDirPath;
    _completeDirectoryIfPending(dataDir, filesDir);
    _completeDirectoryIfPending(tempDir, tempDirectory);
    _completeDirectoryIfPending(downloadDir, downloadsDir);
    _completeDirectoryIfPending(cacheDir, cacheDirectory);
    _completeStringIfPending(bundleCodeDir, bundleCodeDirPath);
  }

  void _completeDirectoryIfPending(
    Completer<Directory> completer,
    Directory value,
  ) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void _completeStringIfPending(Completer<String> completer, String value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }
}

final appPath = AppPath();
