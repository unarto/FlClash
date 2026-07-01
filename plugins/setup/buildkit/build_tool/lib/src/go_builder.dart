import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'environment.dart';
import 'error.dart';
import 'logging.dart';
import 'options.dart';
import 'target.dart';
import 'util.dart';

final _log = Logger('go_builder');

String _resolveCc(Target target) {
  if (target.platformDir == 'ohos') {
    final clang = File(
      p.join(
        Environment.ohosSdkRoot,
        'native',
        'llvm',
        'bin',
        'aarch64-unknown-linux-ohos-clang',
      ),
    );
    if (!clang.existsSync()) {
      throw BuildException('OHOS clang not found: ${clang.path}');
    }
    return clang.path;
  }
  final ndk = Environment.androidNdk;
  final prebuiltDir = Directory(
    p.join(ndk, 'toolchains', 'llvm', 'prebuilt'),
  );
  final entries = prebuiltDir
      .listSync()
      .where((e) => !p.basename(e.path).startsWith('.'))
      .toList();
  if (entries.isEmpty) {
    throw BuildException('No NDK prebuilt toolchain found in $prebuiltDir');
  }
  return p.join(entries.first.path, 'bin', target.ndkCcName);
}

String _resolveOhosGoExecutable(String rootDir) {
  final absoluteRootDir = p.normalize(p.absolute(rootDir));
  final explicitRoot = Platform.environment['FLCLASH_OHOS_GOROOT'];
  final candidates = <String>[
    if (explicitRoot != null && explicitRoot.isNotEmpty)
      p.join(explicitRoot, 'bin', 'go'),
    p.join(absoluteRootDir, '.ohos_toolchain', 'go-nonglibc', 'bin', 'go'),
  ];

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }

  return 'go';
}

class GoBuilder {
  final String rootDir;
  final BuildConfig config;

  GoBuilder({required this.rootDir, required this.config});

  String get _corePath => p.join(rootDir, config.coreDir);
  String get _outputPath => p.join(rootDir, config.outputDir);

  String _ldflagsForTarget(Target target, String fileName) {
    final ldflags = <String>[
      config.goLdflags,
      if (target.isLib && target.platformDir == 'ohos')
        '-extldflags=-Wl,-soname,$fileName',
      if (target.platformDir == 'ohos')
        '-X github.com/metacubex/mihomo/component/http.forceConservativeTransport=true',
    ].where((item) => item.trim().isNotEmpty);
    return ldflags.join(' ');
  }

  String _tagsForTarget(Target target) {
    if (target.platformDir == 'ohos') {
      return '${config.tags},ohos';
    }
    return config.tags;
  }

  Future<String> build(Target target) async {
    // Desktop: output directly to libclash/{platform}/
    // Android: output to libclash/android/{abi}/
    final outDir = target.isLib
        ? p.join(_outputPath, target.platformDir, target.abi!)
        : p.join(_outputPath, target.platformDir);
    ensureDir(outDir);

    final fileName = target.isLib
        ? '${config.libName}${target.dynamicLibExtension}'
        : '${config.coreName}${target.executableExtension}';
    final outFile = p.join(outDir, fileName);
    final ldflags = _ldflagsForTarget(target, fileName);

    final env = <String, String>{
      'GOOS': target.goos,
      'GOARCH': target.goarch,
    };
    final goExecutable =
        target.platformDir == 'ohos' ? _resolveOhosGoExecutable(rootDir) : 'go';

    if (target.isLib) {
      env['CGO_ENABLED'] = '1';
      env['CC'] = _resolveCc(target);
      env['CFLAGS'] = '-O3 -Werror';
      if (target.platformDir == 'ohos' && goExecutable != 'go') {
        env['GOROOT'] = p.dirname(p.dirname(goExecutable));
      }
    } else {
      env['CGO_ENABLED'] = '0';
    }

    final args = [
      'build',
      '-ldflags=$ldflags',
      '-tags=${_tagsForTarget(target)}',
      if (target.isLib) '-buildmode=c-shared',
      '-o',
      outFile,
    ];

    if (target.platformDir == 'ohos' && target.isLib) {
      await _patchOhosGvisorTunFd(goExecutable);
    }

    _log.info(kDoubleSeparator);
    _log.info(
        'Building Go core: $target ${target.isLib ? "(CGO, c-shared)" : "(standalone)"}');
    _log.info(kSeparator);

    await runCommandStream(goExecutable, args,
        workingDirectory: _corePath, environment: env);

    if (target.isLib && target.platformDir == 'ohos') {
      await _buildOhosStaticArchive(
        target: target,
        env: env,
        outDir: outDir,
        goExecutable: goExecutable,
      );
    }

    if (target.isLib && target.abi != null) {
      await _adjustAndroidOutput(
          outDir: p.join(_outputPath, target.platformDir),
          abiDir: target.abi!,
          archName: target.abi!,
          libPath: outFile,
          libName: fileName);
    }

    _log.info('Built: $outFile');
    return outFile;
  }

  /// Patches the metacubex/gvisor fdbased endpoint in the module cache so the
  /// gVisor TUN stack can start inside the OHOS VpnExtension sandbox, where the
  /// VPN tun fd cannot be Fstat'd. Without this the gVisor stack fails to start
  /// and ALL TCP through the tunnel silently breaks. Idempotent.
  Future<void> _patchOhosGvisorTunFd(String goExecutable) async {
    final script =
        p.join(rootDir, 'scripts', 'ohos', 'patch_gvisor_tun_fd.sh');
    if (!File(script).existsSync()) {
      _log.warning('gvisor tun-fd patch script missing: $script');
      return;
    }
    _log.info('Patching gvisor fdbased endpoint for OHOS tun fd');
    await runCommandStream('bash', [script, goExecutable],
        workingDirectory: rootDir);
  }

  Future<void> _buildOhosStaticArchive({
    required Target target,
    required Map<String, String> env,
    required String outDir,
    required String goExecutable,
  }) async {
    final archivePath = p.join(outDir, '${config.libName}.a');
    final headerPath = p.join(outDir, '${config.libName}.h');
    final tempDir = Directory(p.join(outDir, '.carchive_tmp'));
    ensureDir(tempDir.path);
    final tempArchivePath = p.join(tempDir.path, '${config.libName}.a');
    final tempHeaderPath = p.join(tempDir.path, '${config.libName}.h');
    _deleteIfExists(tempArchivePath);
    _deleteIfExists(tempHeaderPath);

    final args = [
      'build',
      '-ldflags=${_ldflagsForTarget(target, config.libName)}',
      '-tags=${_tagsForTarget(target)}',
      '-buildmode=c-archive',
      '-o',
      tempArchivePath,
    ];

    _log.info('Building Go core static archive: $target (CGO, c-archive)');
    final result = Process.runSync(
      goExecutable,
      args,
      workingDirectory: _corePath,
      environment: env,
      includeParentEnvironment: true,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
    final stdout = result.stdout as String;
    final stderr = result.stderr as String;
    if (result.exitCode != 0) {
      throw CommandFailedException(
        executable: 'go',
        arguments: args,
        exitCode: result.exitCode,
        stdout: stdout,
        stderr: stderr,
      );
    }

    final archiveSourcePath = File(tempArchivePath).existsSync()
        ? tempArchivePath
        : _extractCArchiveSourcePath('$stdout\n$stderr');
    if (archiveSourcePath == null || !File(archiveSourcePath).existsSync()) {
      throw BuildException(
        'Failed to locate generated OHOS c-archive from go build output.',
      );
    }
    if (!File(tempHeaderPath).existsSync()) {
      throw BuildException(
        'Failed to locate generated OHOS c-archive header: $tempHeaderPath',
      );
    }

    copyFile(archiveSourcePath, archivePath);
    copyFile(tempHeaderPath, headerPath);
    _deleteIfExists(tempArchivePath);
    _deleteIfExists(tempHeaderPath);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    _log.info('Built: $archivePath');
  }

  String? _extractCArchiveSourcePath(String output) {
    final matches = RegExp(r'(/\S+-d)').allMatches(output).toList();
    if (matches.isEmpty) {
      return null;
    }
    return matches.last.group(1);
  }

  Future<List<String>> buildAll(List<Target> targets) async {
    final results = await Future.wait(targets.map(build));
    return results;
  }

  Future<void> _adjustAndroidOutput({
    required String outDir,
    required String abiDir,
    required String archName,
    required String libPath,
    required String libName,
  }) async {
    final includesPath = p.join(outDir, 'includes', archName);
    final androidCoreMainPath =
        p.join(rootDir, 'android', 'core', 'src', 'main');
    final jniLibsPath = p.join(androidCoreMainPath, 'jniLibs', abiDir);
    final cppIncludesPath =
        p.join(androidCoreMainPath, 'cpp', 'includes', archName);

    ensureDir(jniLibsPath);
    ensureDir(includesPath);
    _clearDirectory(includesPath);
    ensureDir(cppIncludesPath);
    _clearDirectory(cppIncludesPath);

    _deleteIfExists(p.join(jniLibsPath, libName));
    File(libPath).copySync(p.join(jniLibsPath, libName));

    final abiDirPath = p.join(outDir, abiDir);
    final headerFiles = [
      ...Directory(abiDirPath).listSync(),
      ...Directory(_corePath).listSync(),
    ];
    for (final file in headerFiles) {
      if (!file.path.endsWith('.h')) continue;
      final fileName = p.basename(file.path);
      final source = File(file.path);
      source.copySync(p.join(includesPath, fileName));
      source.copySync(p.join(cppIncludesPath, fileName));
      if (file.path.startsWith(abiDirPath)) {
        source.deleteSync();
      }
    }
  }

  void _clearDirectory(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync()) {
      if (entity is File || entity is Link) {
        entity.deleteSync();
      } else if (entity is Directory) {
        entity.deleteSync(recursive: true);
      }
    }
  }

  void _deleteIfExists(String filePath) {
    final file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
