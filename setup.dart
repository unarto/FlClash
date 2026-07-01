import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb', // appimage + rpm added for amd64 only
  'macos': 'dmg',
  'ohos': 'hap',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'ohos': 'ohos',
  'windows': 'windows',
};

final _homeDir = Directory(
  Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.',
);

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host && platform != 'android' && platform != 'ohos') {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android, ohos',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final rootDir = Directory.current.path;
  final arch = _detectArch();
  final targets = _getTargets(platform, arch, results['targets']);
  final androidArch = results['arch'] as String?;
  final verbose = results['verbose'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    verbose: verbose,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'pre',
      allowed: ['pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,dmg,apk,...',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help: 'Target architecture (Android only)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    );
}

List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
  }
  return flutterBuildArgs;
}

String _getTargets(String platform, String arch, String? customTargets) {
  if (customTargets != null) return customTargets;
  if (platform == 'linux' && arch == 'amd64') return 'deb,appimage,rpm';
  return _allTargets[platform]!;
}

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln('Platform: current host platform (default), android, or ohos');
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  required bool verbose,
}) async {
  if (platform == 'ohos') {
    return _packageOhos(rootDir, env, arch, verbose: verbose);
  }

  final distributorDir = p.join(
    rootDir,
    'plugins',
    'flutter_distributor',
    'packages',
    'flutter_distributor',
  );
  final activateResult = await Process.run('dart', [
    'pub',
    'global',
    'activate',
    '-s',
    'path',
    distributorDir,
  ]);
  if (activateResult.exitCode != 0) {
    stderr.write(activateResult.stderr);
    return activateResult.exitCode;
  }

  final coreSha256 = platform == 'windows' ? await _buildGoCore(rootDir) : null;
  final appVersion = _readAppVersion(rootDir);

  final file = File(p.join(rootDir, 'env.json'));

  await file.writeAsString(
    jsonEncode({
      'APP_ENV': env,
      'APP_VERSION': appVersion.versionName,
      'APP_BUILD_NUMBER': appVersion.buildNumber,
      'CORE_SHA256': coreSha256,
      'TARGET_PLATFORM': platform,
    }),
  );

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
  );
  final descriptionArgs = <String>[];
  if (platform != 'android') {
    descriptionArgs.addAll(['--description', arch]);
  }

  final depExit = await _ensureDependencies(platform, arch);
  if (depExit != 0) return depExit;

  final process = await Process.start(
    'flutter_distributor',
    [
      'package',
      '--skip-clean',
      '--platform',
      platform,
      '--targets',
      targets,
      if (androidArch != null)
        '--build-target-platform=${_androidFlutterTarget[androidArch]!}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: true,
    environment: {if (androidArch != null) 'ANDROID_ARCH': androidArch},
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  return exitCode;
}

Future<int> _packageOhos(
  String rootDir,
  String env,
  String arch, {
  required bool verbose,
}) async {
  const flutterArch = 'ohos-arm64';
  final ohosContext = _prepareOhosBuildContext(rootDir);
  final appVersion = _readAppVersion(rootDir);
  final envFile = File(p.join(rootDir, 'env.json'));
  await envFile.writeAsString(
    jsonEncode({
      'APP_ENV': env,
      'APP_VERSION': appVersion.versionName,
      'APP_BUILD_NUMBER': appVersion.buildNumber,
      'CORE_SHA256': null,
      'TARGET_PLATFORM': 'ohos',
    }),
  );

  final buildArgs = <String>[
    'build',
    'hap',
    '--target-platform',
    flutterArch,
    '--release',
    '--no-pub',
    '--dart-define-from-file=env.json',
    if (verbose) '--verbose',
  ];

  _writeOhosLocalProperties(rootDir, ohosContext);
  _syncOhosAppScopeVersion(rootDir, appVersion);
  _repairOhosDartPackageResolution(rootDir, ohosContext);
  final ohosEnvironment = _buildOhosEnvironment(ohosContext);
  final ohosGoRoot = await _prepareOhosGoToolchain(rootDir, ohosEnvironment);
  final ohosBuildEnvironment = _withOhosGoToolchain(
    ohosEnvironment,
    ohosGoRoot,
  );
  final coreExitCode = await _buildOhosCore(rootDir, ohosBuildEnvironment);
  if (coreExitCode != 0) return coreExitCode;
  final executableExitCode = await _buildOhosCoreExecutable(
    rootDir,
    ohosBuildEnvironment,
  );
  if (executableExitCode != 0) return executableExitCode;
  _prepareOhosCoreLibrary(rootDir);
  _prepareOhosFlutterHarFiles(rootDir, ohosContext);
  _verifyOhosSqliteLibrary(rootDir);
  final restorePackages = _patchOhosPackageFiles(rootDir, ohosContext);
  final restoreFlutterEmbeddingHar = _patchFlutterOhosEmbeddingHarForBuild(
    rootDir,
    ohosContext,
  );

  try {
    final dependencyExitCode = await _installOhosDependencies(
      rootDir,
      ohosEnvironment,
    );
    if (dependencyExitCode != 0) return dependencyExitCode;

    final firstBuildExitCode = await _runOhosFlutterBuild(
      rootDir,
      buildArgs,
      ohosEnvironment,
    );
    if (firstBuildExitCode != 0) return firstBuildExitCode;

    final copiedEntryBridgeLibraries = _prepareOhosEntryBridgeLibraries(
      rootDir,
    );
    if (copiedEntryBridgeLibraries) {
      final repackExitCode = await _runOhosFlutterBuild(
        rootDir,
        buildArgs,
        ohosEnvironment,
      );
      if (repackExitCode != 0) return repackExitCode;
    }
  } finally {
    restoreFlutterEmbeddingHar();
    restorePackages();
  }

  return _renameOhosArtifact(rootDir, flutterArch);
}

Future<String> _prepareOhosGoToolchain(
  String rootDir,
  Map<String, String> environment,
) async {
  final explicitRoot = Platform.environment['FLCLASH_OHOS_GOROOT'];
  final toolchainRoot = explicitRoot != null && explicitRoot.isNotEmpty
      ? explicitRoot
      : p.join(rootDir, '.ohos_toolchain', 'go-nonglibc');
  final goBinary = File(p.join(toolchainRoot, 'bin', 'go'));
  if (goBinary.existsSync()) {
    return toolchainRoot;
  }

  final scriptPath = p.join(
    rootDir,
    'scripts',
    'ohos',
    'prepare_go_toolchain.sh',
  );
  final process = await Process.start(
    'bash',
    [scriptPath, toolchainRoot],
    includeParentEnvironment: true,
    environment: environment,
    runInShell: Platform.isWindows,
    workingDirectory: rootDir,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Failed to prepare OHOS Go toolchain.');
    exit(exitCode);
  }
  if (!goBinary.existsSync()) {
    stderr.writeln('Prepared OHOS Go toolchain is missing: ${goBinary.path}');
    exit(1);
  }
  return toolchainRoot;
}

Map<String, String> _withOhosGoToolchain(
  Map<String, String> environment,
  String toolchainRoot,
) {
  final goBin = p.join(toolchainRoot, 'bin');
  return {
    ...environment,
    'FLCLASH_OHOS_GOROOT': toolchainRoot,
    'GOROOT': toolchainRoot,
    'PATH':
        _prependPathEntries([goBin], basePath: environment['PATH']) ??
        environment['PATH'] ??
        goBin,
  };
}

void _prepareOhosCoreLibrary(String rootDir) {
  final sourceCandidates = <String>[
    p.join(rootDir, 'libclash', 'ohos', 'arm64-v8a', 'libclash.so'),
    p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64-v8a', 'libclash.so'),
  ];
  final sourcePath = sourceCandidates.firstWhere(
    (path) => File(path).existsSync(),
    orElse: () => '',
  );
  if (sourcePath.isEmpty) {
    stderr.writeln(
      'Missing OHOS core shared library. Expected one of: '
      '${sourceCandidates.join(', ')}',
    );
    exit(1);
  }

  final targets = <String>[
    p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64', 'libclash.so'),
    p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64-v8a', 'libclash.so'),
  ];
  for (final targetPath in targets) {
    final target = File(targetPath);
    target.parent.createSync(recursive: true);
    File(sourcePath).copySync(target.path);
  }
}

void _prepareOhosFlutterHarFiles(String rootDir, _OhosBuildContext context) {
  final harSources = <String, String>{
    p.join(
      context.flutterSdkRoot,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'ohos-arm64-release',
      'flutter_embedding_release.har',
    ): p.join(
      rootDir,
      'ohos',
      'har',
      'flutter.har',
    ),
    p.join(
      context.flutterSdkRoot,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'ohos-arm64-release',
      'arm64_v8a_release.har',
    ): p.join(
      rootDir,
      'ohos',
      'har',
      'flutter_native_arm64_v8a.har',
    ),
  };

  for (final entry in harSources.entries) {
    final source = File(entry.key);
    if (!source.existsSync()) {
      stderr.writeln('Missing Flutter OHOS HAR: ${source.path}');
      exit(1);
    }

    final target = File(entry.value);
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }
}

bool _prepareOhosEntryBridgeLibraries(String rootDir) {
  final libraries = <String, List<String>>{
    'libentry.so': [
      p.join(
        rootDir,
        'ohos',
        'entry',
        'build',
        'default',
        'intermediates',
        'libs',
        'default',
        'arm64-v8a',
        'libentry.so',
      ),
      p.join(
        rootDir,
        'ohos',
        'entry',
        'build',
        'default',
        'intermediates',
        'cmake',
        'default',
        'obj',
        'arm64-v8a',
        'libentry.so',
      ),
      p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64-v8a', 'libentry.so'),
    ],
    'libentry_child.so': [
      p.join(
        rootDir,
        'ohos',
        'entry',
        'build',
        'default',
        'intermediates',
        'libs',
        'default',
        'arm64-v8a',
        'libentry_child.so',
      ),
      p.join(
        rootDir,
        'ohos',
        'entry',
        'build',
        'default',
        'intermediates',
        'cmake',
        'default',
        'obj',
        'arm64-v8a',
        'libentry_child.so',
      ),
      p.join(
        rootDir,
        'ohos',
        'entry',
        'libs',
        'arm64-v8a',
        'libentry_child.so',
      ),
    ],
    'libc++_shared.so': [
      p.join(
        rootDir,
        'ohos',
        'entry',
        'build',
        'default',
        'intermediates',
        'libs',
        'default',
        'arm64-v8a',
        'libc++_shared.so',
      ),
      p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64-v8a', 'libc++_shared.so'),
    ],
  };

  var copied = false;
  for (final entry in libraries.entries) {
    final sourcePath = entry.value.firstWhere(
      (path) => File(path).existsSync(),
      orElse: () => '',
    );
    if (sourcePath.isEmpty) {
      continue;
    }

    final source = File(sourcePath);
    final target = File(
      p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64', entry.key),
    );
    target.parent.createSync(recursive: true);
    if (target.existsSync()) {
      final targetStat = target.statSync();
      final sourceStat = source.statSync();
      if (targetStat.size == sourceStat.size &&
          targetStat.modified.isAfter(sourceStat.modified)) {
        continue;
      }
    }
    source.copySync(target.path);
    copied = true;
  }

  return copied;
}

Future<int> _runOhosFlutterBuild(
  String rootDir,
  List<String> buildArgs,
  Map<String, String> ohosEnvironment,
) async {
  final process = await Process.start(
    _resolveFlutterExecutable(),
    buildArgs,
    includeParentEnvironment: true,
    environment: ohosEnvironment,
    runInShell: Platform.isWindows,
    workingDirectory: rootDir,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });

  return process.exitCode;
}

void _verifyOhosSqliteLibrary(String rootDir) {
  final sqliteLibrary = File(
    p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64', 'libsqlite3.so'),
  );
  final coreBinary = File(
    p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64-v8a', 'libclash.so'),
  );
  final coreArchive = File(
    p.join(rootDir, 'libclash', 'ohos', 'arm64-v8a', 'libclash.a'),
  );
  final executableCoreBinary = File(
    p.join(rootDir, 'ohos', 'entry', 'libs', 'arm64', 'libFlClashCore.so'),
  );
  if (!sqliteLibrary.existsSync()) {
    stderr.writeln(
      'Missing OHOS sqlite library: ${sqliteLibrary.path}. '
      'Build or copy libsqlite3.so before packaging.',
    );
    exit(1);
  }
  if (!coreBinary.existsSync()) {
    stderr.writeln(
      'Missing OHOS core shared library: ${coreBinary.path}. '
      'Build or copy libclash.so before packaging.',
    );
    exit(1);
  }
  if (!coreArchive.existsSync()) {
    stderr.writeln(
      'Missing OHOS core static archive: ${coreArchive.path}. '
      'Build libclash.a before packaging.',
    );
    exit(1);
  }
  final fileResult = Process.runSync('file', [coreBinary.path]);
  final fileOutput = '${fileResult.stdout}${fileResult.stderr}';
  if (!fileOutput.contains('shared object')) {
    stderr.writeln(
      'Invalid OHOS core library: ${coreBinary.path}. '
      'Expected a shared object, got: ${fileOutput.trim()}',
    );
    exit(1);
  }
  if (!executableCoreBinary.existsSync()) {
    stderr.writeln(
      'Missing OHOS core executable: ${executableCoreBinary.path}. '
      'Build or copy FlClashCore before packaging.',
    );
    exit(1);
  }
}

class _OhosBuildContext {
  const _OhosBuildContext({
    required this.originalSdkRoot,
    required this.compatibleSdkRoot,
    required this.devecoSdkRoot,
    required this.flutterSdkRoot,
    this.nodeHome,
  });

  final String originalSdkRoot;
  final String compatibleSdkRoot;
  final String devecoSdkRoot;
  final String flutterSdkRoot;
  final String? nodeHome;
}

int _renameOhosArtifact(String rootDir, String flutterArch) {
  final source = File(
    p.join(
      rootDir,
      'ohos',
      'entry',
      'build',
      'default',
      'outputs',
      'default',
      'entry-default-signed.hap',
    ),
  );
  if (!source.existsSync()) {
    stderr.writeln('Signed HAP not found: ${source.path}');
    return 1;
  }

  final version = _readAppVersion(rootDir).versionName;
  final releaseArch = flutterArch.replaceFirst('ohos-', '');
  final distDir = Directory(p.join(rootDir, 'dist'));
  if (!distDir.existsSync()) {
    distDir.createSync(recursive: true);
  }

  final target = File(
    p.join(distDir.path, 'FlClash-$version-ohos-$releaseArch.hap'),
  );
  source.copySync(target.path);
  stdout.writeln('Created release artifact: ${target.path}');
  return 0;
}

_OhosBuildContext _prepareOhosBuildContext(String rootDir) {
  final originalSdkRoot = _resolveOhosSdkRoot();
  if (originalSdkRoot == null) {
    stderr.writeln(
      'Unable to resolve an OpenHarmony SDK root. '
      'Install DevEco Studio/OpenHarmony SDK or set OHOS_SDK_HOME.',
    );
    exit(1);
  }

  final flutterSdkRoot = _resolveFlutterSdkRoot();
  if (flutterSdkRoot == null) {
    stderr.writeln(
      'Unable to resolve the Flutter SDK root. Set FLUTTER_ROOT first.',
    );
    exit(1);
  }
  _normalizeFlutterSdkVersionMetadata(flutterSdkRoot);

  final compatibleSdkRoot = _prepareCompatibleOhosSdkView(
    rootDir,
    originalSdkRoot,
  );

  return _OhosBuildContext(
    originalSdkRoot: originalSdkRoot,
    compatibleSdkRoot: compatibleSdkRoot,
    devecoSdkRoot: p.dirname(originalSdkRoot),
    flutterSdkRoot: flutterSdkRoot,
    nodeHome: _resolveOhosNodeHome(),
  );
}

void _normalizeFlutterSdkVersionMetadata(String flutterSdkRoot) {
  final versionFile = File(p.join(flutterSdkRoot, 'version'));
  final version = versionFile.existsSync()
      ? versionFile.readAsStringSync().trim()
      : '';
  if (version.isNotEmpty && version != '0.0.0-unknown') {
    return;
  }

  final branchResult = Process.runSync('git', [
    'branch',
    '--show-current',
  ], workingDirectory: flutterSdkRoot);
  if (branchResult.exitCode != 0) {
    return;
  }
  final branch = branchResult.stdout.toString().trim();
  final match = RegExp(
    r'^oh-(\d+\.\d+\.\d+)-(release|dev)$',
  ).firstMatch(branch);
  if (match == null) {
    return;
  }

  final semanticVersion = switch (match.group(2)) {
    'release' => match.group(1)!,
    'dev' => '${match.group(1)!}-0.0.pre',
    _ => null,
  };
  if (semanticVersion == null) {
    return;
  }

  versionFile.writeAsStringSync(semanticVersion);
  final versionJsonFile = File(
    p.join(flutterSdkRoot, 'bin', 'cache', 'flutter.version.json'),
  );
  if (versionJsonFile.existsSync()) {
    final raw = jsonDecode(versionJsonFile.readAsStringSync());
    if (raw is Map<String, dynamic>) {
      raw['frameworkVersion'] = semanticVersion;
      raw['flutterVersion'] = semanticVersion;
      versionJsonFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
      );
    }
  }
  stdout.writeln(
    'Normalized Flutter SDK version metadata: $branch -> $semanticVersion',
  );
}

String _prepareCompatibleOhosSdkView(String rootDir, String originalSdkRoot) {
  if (_isCompatibleOhosSdkRoot(originalSdkRoot)) {
    return originalSdkRoot;
  }

  final componentDirs =
      Directory(originalSdkRoot)
          .listSync()
          .whereType<Directory>()
          .where(
            (dir) => File(p.join(dir.path, 'oh-uni-package.json')).existsSync(),
          )
          .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  if (componentDirs.isEmpty) {
    stderr.writeln(
      'No OpenHarmony SDK components found under $originalSdkRoot.',
    );
    exit(1);
  }

  final compatRoot = Directory(p.join(rootDir, 'ohos', '.sdk', 'openharmony'));
  compatRoot.createSync(recursive: true);

  for (final entity in compatRoot.listSync()) {
    if (entity is Directory && int.tryParse(p.basename(entity.path)) != null) {
      entity.deleteSync(recursive: true);
    }
  }

  for (final componentDir in componentDirs) {
    final metadata =
        jsonDecode(
              File(
                p.join(componentDir.path, 'oh-uni-package.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final apiVersion = metadata['apiVersion']?.toString();
    if (apiVersion == null || apiVersion.isEmpty) {
      stderr.writeln(
        'Missing apiVersion in ${p.join(componentDir.path, 'oh-uni-package.json')}.',
      );
      exit(1);
    }

    final targetDir = Directory(
      p.join(compatRoot.path, apiVersion, p.basename(componentDir.path)),
    );
    targetDir.parent.createSync(recursive: true);
    final targetEntity = FileSystemEntity.typeSync(
      targetDir.path,
      followLinks: false,
    );
    if (targetEntity != FileSystemEntityType.notFound) {
      if (targetEntity == FileSystemEntityType.directory) {
        Directory(targetDir.path).deleteSync(recursive: true);
      } else {
        Link(targetDir.path).deleteSync();
      }
    }
    Link(targetDir.path).createSync(componentDir.path);
  }

  return compatRoot.path;
}

bool _isCompatibleOhosSdkRoot(String sdkRoot) {
  final root = Directory(sdkRoot);
  if (!root.existsSync()) {
    return false;
  }

  for (final entity in root.listSync()) {
    if (entity is! Directory) continue;
    final apiVersion = int.tryParse(p.basename(entity.path));
    if (apiVersion == null) continue;
    if (File(
      p.join(entity.path, 'toolchains', 'oh-uni-package.json'),
    ).existsSync()) {
      return true;
    }
  }

  return false;
}

void _writeOhosLocalProperties(String rootDir, _OhosBuildContext context) {
  final file = File(p.join(rootDir, 'ohos', 'local.properties'));
  final appVersion = _readAppVersion(rootDir);

  final lines = <String>[
    'hwsdk.dir=${context.devecoSdkRoot}',
    'sdk.dir=${context.compatibleSdkRoot}',
    if (context.nodeHome != null) 'nodejs.dir=${context.nodeHome!}',
    'flutter.sdk=${context.flutterSdkRoot}',
    'flutter.versionName=${appVersion.versionName}',
    'flutter.versionCode=${appVersion.buildNumber}',
  ];
  file.writeAsStringSync('${lines.join('\n')}\n');
}

_AppVersion _readAppVersion(String rootDir) {
  final versionLine = File(p.join(rootDir, 'pubspec.yaml'))
      .readAsLinesSync()
      .firstWhere((line) => line.startsWith('version: '))
      .substring('version: '.length)
      .trim();
  final versionParts = versionLine.split('+');
  return _AppVersion(
    versionName: versionParts.first,
    buildNumber: versionParts.length > 1 ? versionParts[1] : '1',
  );
}

class _AppVersion {
  const _AppVersion({required this.versionName, required this.buildNumber});

  final String versionName;
  final String buildNumber;
}

void _syncOhosAppScopeVersion(String rootDir, _AppVersion appVersion) {
  final appScopeFile = File(p.join(rootDir, 'ohos', 'AppScope', 'app.json5'));
  if (!appScopeFile.existsSync()) {
    return;
  }
  final versionNamePattern = RegExp(r'"versionName"\s*:\s*"[^"]*"');
  final versionCodePattern = RegExp(r'"versionCode"\s*:\s*\d+');
  final content = appScopeFile.readAsStringSync();
  final updated = content
      .replaceFirst(
        versionCodePattern,
        '"versionCode": ${appVersion.buildNumber}',
      )
      .replaceFirst(
        versionNamePattern,
        '"versionName": "${appVersion.versionName}"',
      );
  if (updated != content) {
    appScopeFile.writeAsStringSync(updated);
  }
}

void _repairOhosDartPackageResolution(
  String rootDir,
  _OhosBuildContext context,
) {
  final packageConfigFile = File(
    p.join(rootDir, '.dart_tool', 'package_config.json'),
  );
  if (!packageConfigFile.existsSync()) {
    return;
  }

  final raw = jsonDecode(packageConfigFile.readAsStringSync());
  if (raw is! Map<String, dynamic>) {
    return;
  }
  final packages = raw['packages'];
  if (packages is! List) {
    return;
  }

  _repairLegacyFlutterSdkMirror(context.flutterSdkRoot);
  _repairLegacyPubCacheLayout(packages);
}

void _repairLegacyFlutterSdkMirror(String flutterSdkRoot) {
  const legacyRootPath = '/private/tmp/flutter_ohos_3357';
  final legacyRoot = Directory(legacyRootPath);
  legacyRoot.createSync(recursive: true);

  final packageNames = <String>[
    'flutter',
    'flutter_localizations',
    'flutter_test',
    'flutter_web_plugins',
  ];
  for (final packageName in packageNames) {
    _ensureLinkedDirectory(
      p.join(legacyRootPath, 'packages', packageName),
      p.join(flutterSdkRoot, 'packages', packageName),
    );
  }
}

void _repairLegacyPubCacheLayout(List<dynamic> packages) {
  const legacyPubRoot = '/tmp/pub_ohos_3357';
  final hostedPubDev = Directory(p.join(legacyPubRoot, 'hosted', 'pub.dev'));
  hostedPubDev.createSync(recursive: true);
  final hostedFlutterIo = p.join(legacyPubRoot, 'hosted', 'pub.flutter-io.cn');
  _ensureLinkedDirectory(hostedFlutterIo, hostedPubDev.path);

  final fallbackHostedRoots = <String>[
    p.join(legacyPubRoot, 'hosted', 'pub.dev'),
    p.join(legacyPubRoot, 'hosted', 'pub.flutter-io.cn'),
    p.join(_homeDir.path, '.pub-cache-ohos', 'hosted', 'pub.dev'),
    p.join(_homeDir.path, '.pub-cache', 'hosted', 'pub.dev'),
  ];
  final fallbackGitRoots = <String>[
    p.join(legacyPubRoot, 'git'),
    p.join(_homeDir.path, '.pub-cache-ohos', 'git'),
    p.join(_homeDir.path, '.pub-cache', 'git'),
  ];

  for (final package in packages) {
    if (package is! Map) {
      continue;
    }
    final rootUri = package['rootUri'];
    if (rootUri is! String || rootUri.isEmpty) {
      continue;
    }
    final uri = Uri.tryParse(rootUri);
    if (uri == null || uri.scheme != 'file') {
      continue;
    }
    final targetPath = uri.toFilePath();
    if (Directory(targetPath).existsSync() || File(targetPath).existsSync()) {
      continue;
    }

    if (targetPath.startsWith('$legacyPubRoot/hosted/pub.flutter-io.cn/') ||
        targetPath.startsWith('$legacyPubRoot/hosted/pub.dev/')) {
      final packageDirName = p.basename(targetPath);
      final sourcePath = _firstExistingDirectoryPath(
        fallbackHostedRoots
            .map((root) => p.join(root, packageDirName))
            .toList(),
      );
      if (sourcePath != null) {
        _ensureLinkedDirectory(targetPath, sourcePath);
      }
      continue;
    }

    if (targetPath.startsWith('$legacyPubRoot/git/')) {
      final packageDirName = p.basename(targetPath);
      final sourcePath = _firstExistingDirectoryPath(
        fallbackGitRoots.map((root) => p.join(root, packageDirName)).toList(),
      );
      if (sourcePath != null) {
        _ensureLinkedDirectory(targetPath, sourcePath);
      }
    }
  }
}

void _ensureLinkedDirectory(String targetPath, String sourcePath) {
  final sourceType = FileSystemEntity.typeSync(sourcePath, followLinks: true);
  if (sourceType == FileSystemEntityType.notFound) {
    return;
  }

  final targetType = FileSystemEntity.typeSync(targetPath, followLinks: false);
  if (targetType == FileSystemEntityType.link) {
    final existingTarget = Link(targetPath).targetSync();
    if (existingTarget == sourcePath) {
      return;
    }
    Link(targetPath).deleteSync();
  } else if (targetType == FileSystemEntityType.directory) {
    if (Directory(targetPath).resolveSymbolicLinksSync() == sourcePath) {
      return;
    }
    Directory(targetPath).deleteSync(recursive: true);
  } else if (targetType == FileSystemEntityType.file) {
    File(targetPath).deleteSync();
  }

  Directory(p.dirname(targetPath)).createSync(recursive: true);
  Link(targetPath).createSync(sourcePath, recursive: true);
}

String? _firstExistingDirectoryPath(List<String> candidates) {
  for (final candidate in candidates) {
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

void Function() _patchOhosPackageFiles(
  String rootDir,
  _OhosBuildContext context,
) {
  final embeddingHar = File(
    p.join(
      context.flutterSdkRoot,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'ohos-arm64-release',
      'flutter_embedding_release.har',
    ),
  );
  final nativeHar = File(
    p.join(
      context.flutterSdkRoot,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'ohos-arm64-release',
      'arm64_v8a_release.har',
    ),
  );

  if (!embeddingHar.existsSync() || !nativeHar.existsSync()) {
    stderr.writeln(
      'Missing Flutter OHOS engine HARs under ${embeddingHar.parent.path}.',
    );
    exit(1);
  }

  final files = <String>[
    p.join(rootDir, 'ohos', 'oh-package.json5'),
    p.join(rootDir, 'ohos', 'entry', 'oh-package.json5'),
  ];
  final originals = <String, String>{};

  for (final path in files) {
    originals[path] = File(path).readAsStringSync();
  }

  final rootPackageFile = File(files.first);
  final rootPackage =
      jsonDecode(rootPackageFile.readAsStringSync()) as Map<String, dynamic>;
  rootPackage['overrides'] = {
    ...(rootPackage['overrides'] as Map<String, dynamic>? ?? {}),
    '@ohos/flutter_ohos': 'file:${embeddingHar.path}',
    'flutter_native_arm64_v8a': 'file:${nativeHar.path}',
  };
  rootPackageFile.writeAsStringSync('${jsonEncode(rootPackage)}\n');

  final entryPackageFile = File(files.last);
  final entryPackage =
      jsonDecode(entryPackageFile.readAsStringSync()) as Map<String, dynamic>;
  entryPackage['dependencies'] = {
    ...(entryPackage['dependencies'] as Map<String, dynamic>? ?? {}),
    '@ohos/flutter_ohos': '',
    'flutter_native_arm64_v8a': '',
  };
  entryPackageFile.writeAsStringSync('${jsonEncode(entryPackage)}\n');

  return () {
    for (final entry in originals.entries) {
      File(entry.key).writeAsStringSync(entry.value);
    }
  };
}

Future<int> _installOhosDependencies(
  String rootDir,
  Map<String, String> environment,
) async {
  final process = await Process.start(
    'ohpm',
    ['install'],
    includeParentEnvironment: true,
    environment: environment,
    runInShell: Platform.isWindows,
    workingDirectory: p.join(rootDir, 'ohos'),
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });

  return process.exitCode;
}

void Function() _patchFlutterOhosEmbeddingHarForBuild(
  String rootDir,
  _OhosBuildContext context,
) {
  final embeddingHar = File(
    p.join(
      context.flutterSdkRoot,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'ohos-arm64-release',
      'flutter_embedding_release.har',
    ),
  );
  if (!embeddingHar.existsSync()) {
    stderr.writeln('Missing Flutter OHOS embedding HAR: ${embeddingHar.path}.');
    exit(1);
  }

  final originalBytes = embeddingHar.readAsBytesSync();
  final sdkDir = Directory(p.join(rootDir, 'ohos', '.sdk'));
  sdkDir.createSync(recursive: true);
  final workDir = Directory(p.join(sdkDir.path, 'flutter_embedding_patch'));
  if (workDir.existsSync()) {
    workDir.deleteSync(recursive: true);
  }
  workDir.createSync(recursive: true);

  final extractResult = Process.runSync('tar', [
    '-xzf',
    embeddingHar.path,
    '-C',
    workDir.path,
  ]);
  if (extractResult.exitCode != 0) {
    stderr.write(extractResult.stderr);
    stderr.writeln('Failed to extract ${embeddingHar.path}.');
    exit(extractResult.exitCode);
  }

  final navigationChannel = File(
    p.join(
      workDir.path,
      'package',
      'src',
      'main',
      'ets',
      'embedding',
      'engine',
      'systemchannels',
      'NavigationChannel.ets',
    ),
  );
  if (!navigationChannel.existsSync()) {
    stderr.writeln('NavigationChannel.ets not found in ${embeddingHar.path}.');
    exit(1);
  }

  const buggySnippet = """
    const argsMap = call.args as Map<string, string>;
    const currentUri: string = argsMap.get('uri') ?? '';
""";
  const fixedSnippet = """
    const uriArg = call.argument('uri');
    const currentUri: string = typeof uriArg === 'string' ? uriArg : '';
""";
  final source = navigationChannel.readAsStringSync();
  if (source.contains(fixedSnippet)) {
    workDir.deleteSync(recursive: true);
    return () {};
  }
  if (!source.contains(buggySnippet)) {
    stderr.writeln(
      'Unexpected NavigationChannel.ets contents in ${embeddingHar.path}.',
    );
    exit(1);
  }

  navigationChannel.writeAsStringSync(
    source.replaceFirst(buggySnippet, fixedSnippet),
  );

  final patchedHar = File(p.join(sdkDir.path, 'flutter_embedding_release.har'));
  if (patchedHar.existsSync()) patchedHar.deleteSync();
  final archiveResult = Process.runSync('tar', [
    '-czf',
    patchedHar.path,
    '-C',
    workDir.path,
    'package',
  ]);
  workDir.deleteSync(recursive: true);
  if (archiveResult.exitCode != 0) {
    stderr.write(archiveResult.stderr);
    stderr.writeln('Failed to create patched ${embeddingHar.path}.');
    exit(archiveResult.exitCode);
  }

  embeddingHar.writeAsBytesSync(patchedHar.readAsBytesSync());
  patchedHar.deleteSync();

  return () {
    embeddingHar.writeAsBytesSync(originalBytes);
  };
}

Map<String, String> _buildOhosEnvironment(_OhosBuildContext context) {
  final environment = <String, String>{};
  environment['HOS_SDK_HOME'] = context.originalSdkRoot;
  environment['OHOS_SDK_HOME'] = context.compatibleSdkRoot;
  environment['OHOS_BASE_SDK_HOME'] = context.compatibleSdkRoot;
  environment['DEVECO_SDK_HOME'] = context.devecoSdkRoot;
  environment['FLCLASH_OHOS_SOURCE_SDK_HOME'] = context.originalSdkRoot;

  final nodeHome = context.nodeHome;
  if (nodeHome != null) environment['NODE_HOME'] = nodeHome;

  final pathEntries = <String>[
    p.join(context.flutterSdkRoot, 'bin'),
    if (nodeHome != null) p.join(nodeHome, 'bin'),
    if (Platform.isMacOS) '/opt/homebrew/bin',
    if (Platform.isMacOS) '/usr/local/bin',
    p.join(context.originalSdkRoot, 'toolchains'),
    if (Platform.isMacOS)
      '/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin',
    if (Platform.isMacOS)
      '/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin',
  ];
  final path = _prependPathEntries(pathEntries);
  if (path != null) {
    environment['PATH'] = path;
  }

  return environment;
}

String? _resolveOhosSdkRoot() {
  final candidates = <String>[
    if (Platform.environment['HOS_SDK_HOME'] case final value?
        when value.isNotEmpty)
      value,
    if (Platform.environment['OHOS_SDK_HOME'] case final value?
        when value.isNotEmpty)
      value,
    if (Platform.environment['OHOS_BASE_SDK_HOME'] case final value?
        when value.isNotEmpty)
      value,
    if (Platform.isMacOS)
      '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony',
  ];
  return _firstExistingDirectory(candidates);
}

String? _resolveOhosNodeHome() {
  final candidates = <String>[
    if (Platform.environment['NODE_HOME'] case final value?
        when value.isNotEmpty)
      value,
    if (Platform.isMacOS) '/Applications/DevEco-Studio.app/Contents/tools/node',
  ];
  return _firstExistingDirectory(candidates);
}

String? _firstExistingDirectory(List<String> candidates) {
  for (final candidate in candidates) {
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

String? _resolveFlutterSdkRoot() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    return flutterRoot;
  }

  final flutterExecutable = _resolveFlutterExecutable();
  if (p.isAbsolute(flutterExecutable)) {
    return p.dirname(p.dirname(flutterExecutable));
  }

  return null;
}

String? _prependPathEntries(List<String> entries, {String? basePath}) {
  final existing = basePath ?? Platform.environment['PATH'];
  final seen = <String>{};
  final values = <String>[];

  void add(String value) {
    if (value.isEmpty || !seen.add(value)) {
      return;
    }
    values.add(value);
  }

  for (final entry in entries) {
    add(entry);
  }
  if (existing != null && existing.isNotEmpty) {
    for (final entry in existing.split(Platform.isWindows ? ';' : ':')) {
      add(entry);
    }
  }

  if (values.isEmpty) {
    return null;
  }
  return values.join(Platform.isWindows ? ';' : ':');
}

String _resolveFlutterExecutable() {
  final flutterName = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final flutterFromEnv = File(p.join(flutterRoot, 'bin', flutterName));
    if (flutterFromEnv.existsSync()) {
      return flutterFromEnv.path;
    }
  }

  var current = File(Platform.resolvedExecutable).parent;
  while (true) {
    final directCandidate = File(p.join(current.path, flutterName));
    if (directCandidate.existsSync()) {
      return directCandidate.path;
    }

    final binCandidate = File(p.join(current.path, 'bin', flutterName));
    if (binCandidate.existsSync()) {
      return binCandidate.path;
    }

    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }

  return 'flutter';
}

Future<String?> _buildGoCore(String rootDir) async {
  final buildToolDir = p.join(
    rootDir,
    'plugins',
    'setup',
    'buildkit',
    'build_tool',
  );
  final result = await Process.run('dart', [
    'run',
    'build_tool',
    'windows',
    '--root-dir',
    rootDir,
  ], workingDirectory: buildToolDir);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    return null;
  }
  final shaFile = File(p.join(rootDir, 'core_sha256.json'));
  if (!shaFile.existsSync()) return null;
  final content =
      jsonDecode(shaFile.readAsStringSync()) as Map<String, dynamic>;
  return content['CORE_SHA256'] as String?;
}

Future<int> _buildOhosCore(
  String rootDir,
  Map<String, String> environment,
) async {
  final buildToolDir = p.join(
    rootDir,
    'plugins',
    'setup',
    'buildkit',
    'build_tool',
  );
  final process = await Process.start(
    'dart',
    ['run', 'build_tool', 'ohos', '--root-dir', rootDir],
    includeParentEnvironment: true,
    environment: environment,
    workingDirectory: buildToolDir,
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });

  return process.exitCode;
}

Future<int> _buildOhosCoreExecutable(
  String rootDir,
  Map<String, String> environment,
) async {
  final outputPath = p.join(
    rootDir,
    'ohos',
    'entry',
    'libs',
    'arm64',
    'libFlClashCore.so',
  );
  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);

  final process = await Process.start(
    'go',
    [
      'build',
      '-ldflags=-w -s -X github.com/metacubex/mihomo/component/http.forceConservativeTransport=true',
      '-tags=with_gvisor',
      '-o',
      outputPath,
    ],
    includeParentEnvironment: true,
    environment: {
      ...environment,
      'GOOS': 'linux',
      'GOARCH': 'arm64',
      'CGO_ENABLED': '0',
    },
    workingDirectory: p.join(rootDir, 'core'),
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    return exitCode;
  }

  final assetTarget = File(p.join(rootDir, 'assets', 'data', 'FlClashCore'));
  assetTarget.parent.createSync(recursive: true);
  outputFile.copySync(assetTarget.path);
  stdout.writeln(
    'Synced OHOS bundled executable core: ${outputFile.path} -> ${assetTarget.path}',
  );

  return exitCode;
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(which, args);
  return result.exitCode == 0;
}

Future<int> _ensureDependencies(String platform, String arch) async {
  switch (platform) {
    case 'macos':
      return _ensureMacosDependencies();
    case 'linux':
      return _ensureLinuxDependencies(arch);
    default:
      return 0;
  }
}

Future<int> _ensureMacosDependencies() async {
  if (await _hasCommand('appdmg')) {
    stdout.writeln('appdmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing appdmg (DMG creator)...');
  final result = await Process.run('npm', ['install', '-g', 'appdmg']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

Future<int> _ensureLinuxDependencies(String arch) async {
  final pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libkeybinder-3.0-dev'],
    ['locate'],
  ];
  if (arch == 'amd64') {
    pkgGroups.addAll([
      ['rpm', 'patchelf'],
      ['libfuse2'],
    ]);
  }

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) return installExit;
    }
  }

  if (arch == 'amd64') {
    const appimagetool = '/usr/local/bin/appimagetool';
    if (File(appimagetool).existsSync()) {
      stdout.writeln('appimagetool already installed, skipping.');
      return 0;
    }
    stdout.writeln('Downloading appimagetool...');
    final downloadName = arch == 'amd64' ? 'x86_64' : 'aarch64';
    final dlResult = await Process.run('wget', [
      '-O',
      appimagetool,
      'https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage',
    ]);
    if (dlResult.exitCode != 0) {
      stderr.write(dlResult.stderr);
      return dlResult.exitCode;
    }
    await Process.run('chmod', ['+x', appimagetool]);
  }

  return 0;
}

Future<bool> _isDebianPackageInstalled(String pkg) async {
  final result = await Process.run('dpkg', ['-s', pkg]);
  return result.exitCode == 0 &&
      (result.stdout as String).contains('Status: install ok installed');
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}
