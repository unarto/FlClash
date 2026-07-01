'use strict';

const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const Module = require('module');
const os = require('os');
const path = require('path');
const {prepareOpenHarmonySigningAssets} = require('./signing');

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function unescapePropertyValue(value) {
  return value
      .replace(/\\\\/g, '\\')
      .replace(/\\:/g, ':')
      .replace(/\\=/g, '=')
      .replace(/\\ /g, ' ');
}

function readFlutterSdk(appHome) {
  const envFlutterSdk = process.env.FLUTTER_ROOT || process.env.FLUTTER_SDK || '';
  if (envFlutterSdk) {
    return envFlutterSdk;
  }
  const value = readLocalProperty(appHome, 'flutter.sdk');
  if (value) {
    return value;
  }
  return '';
}

function ensureDirSync(dirPath) {
  if (!dirPath || dirPath === '.' || fs.existsSync(dirPath)) {
    return;
  }
  ensureDirSync(path.dirname(dirPath));
  try {
    fs.mkdirSync(dirPath);
  } catch (error) {
    if (!fs.existsSync(dirPath)) {
      throw error;
    }
  }
}

function copyFileIfChanged(sourcePath, targetPath) {
  ensureDirSync(path.dirname(targetPath));
  if (fs.existsSync(targetPath)) {
    const sourceStat = fs.statSync(sourcePath);
    const targetStat = fs.statSync(targetPath);
    if (sourceStat.size === targetStat.size &&
        sourceStat.mtimeMs <= targetStat.mtimeMs) {
      return false;
    }
  }
  fs.copyFileSync(sourcePath, targetPath);
  return true;
}

function removeDirectoryContentsSync(dirPath) {
  for (const entry of fs.readdirSync(dirPath)) {
    removePathSync(path.join(dirPath, entry));
  }
}

function readLocalProperty(appHome, propertyName) {
  const localPropertiesPath = path.join(appHome, 'local.properties');
  if (!fs.existsSync(localPropertiesPath)) {
    return '';
  }

  const content = fs.readFileSync(localPropertiesPath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex === -1) {
      continue;
    }
    const key = trimmed.slice(0, separatorIndex).trim();
    if (key !== propertyName) {
      continue;
    }
    const value = trimmed.slice(separatorIndex + 1).trim();
    return unescapePropertyValue(value);
  }

  return '';
}

const appHome = path.resolve(__dirname, '..');
const flutterSdk = readFlutterSdk(appHome);
if (!flutterSdk) {
  fail('Unable to resolve the Flutter SDK. Set FLUTTER_ROOT or add flutter.sdk to ohos/local.properties.');
}

function resolveCommand(command) {
  try {
    return childProcess.execFileSync('bash', ['-lc', `command -v ${command}`], {
      encoding: 'utf8',
    }).trim();
  } catch (_) {
    return '';
  }
}

function resolveHvigorwPath() {
  const explicitPath = process.env.FLCLASH_HVIGORW || process.env.HVIGORW || '';
  if (explicitPath && fs.existsSync(explicitPath)) {
    return explicitPath;
  }

  const pathHvigorw = resolveCommand('hvigorw');
  if (pathHvigorw) {
    return pathHvigorw;
  }

  const nodejsDir = readLocalProperty(appHome, 'nodejs.dir');
  if (nodejsDir) {
    const devEcoToolsDir = path.dirname(nodejsDir);
    const devEcoHvigorw = path.join(devEcoToolsDir, 'hvigor', 'bin', 'hvigorw');
    if (fs.existsSync(devEcoHvigorw)) {
      return devEcoHvigorw;
    }
  }

  const defaultDevEcoHvigorw =
      '/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw';
  if (fs.existsSync(defaultDevEcoHvigorw)) {
    return defaultDevEcoHvigorw;
  }

  fail('Unable to locate hvigorw. Set FLCLASH_HVIGORW or add hvigorw to PATH.');
}

function getBundledHvigorVersion() {
  const hvigorwPath = resolveHvigorwPath();
  const hvigorBinDir = path.dirname(hvigorwPath);
  const toolRoot = path.dirname(hvigorBinDir);
  const packageJsonPath = path.join(toolRoot, 'hvigor', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  return packageJson.version;
}

function getHvigorToolRoot() {
  const hvigorwPath = resolveHvigorwPath();
  return path.dirname(path.dirname(hvigorwPath));
}

function getBundledNodePath() {
  const nodejsDir = readLocalProperty(appHome, 'nodejs.dir');
  if (nodejsDir) {
    const nodePath = path.join(nodejsDir, 'bin', 'node');
    if (fs.existsSync(nodePath)) {
      return nodePath;
    }
  }

  const pathNode = resolveCommand('node');
  if (pathNode) {
    return pathNode;
  }

  return process.execPath;
}

function relaunchWithBundledNodeIfNeeded() {
  if (process.env.FLCLASH_HVIGOR_NODE_RELAUNCHED === '1') {
    return;
  }

  const nodePath = getBundledNodePath();
  if (path.resolve(nodePath) === path.resolve(process.execPath)) {
    return;
  }

  const result = childProcess.spawnSync(nodePath, process.argv.slice(1), {
    env: {
      ...process.env,
      FLCLASH_HVIGOR_NODE_RELAUNCHED: '1',
    },
    stdio: 'inherit',
  });

  if (result.error) {
    fail(`Unable to launch bundled Node: ${result.error.message}`);
  }

  process.exit(result.status ?? 1);
}

function readHvigorConfig() {
  const hvigorConfigPath = path.join(appHome, 'hvigor', 'hvigor-config.json5');
  return JSON.parse(fs.readFileSync(hvigorConfigPath, 'utf8'));
}

function getHvigorWorkspaceDir() {
  const config = readHvigorConfig();
  const bundledHvigorVersion = getBundledHvigorVersion();
  const dependencySpec = [
    `@ohos/hvigor@${bundledHvigorVersion}`,
    ...Object.keys(config.dependencies || {})
        .sort()
        .map((name) => `${name}@${config.dependencies[name]}`),
  ].join(',');
  const projectHash = crypto
      .createHash('md5')
      .update(dependencySpec)
      .digest('hex');
  const hvigorUserHome = process.env.HVIGOR_USER_HOME ||
      path.join(os.homedir(), '.hvigor');
  return path.join(hvigorUserHome, 'project_caches', projectHash, 'workspace');
}

function removePathSync(target) {
  if (!fs.existsSync(target)) {
    return;
  }
  const stat = fs.lstatSync(target);
  if (stat.isDirectory() && !stat.isSymbolicLink()) {
    removeDirectoryContentsSync(target);
    fs.rmdirSync(target);
    return;
  }
  fs.rmSync(target, {force: true});
}

function installLegacyFsCompat() {
  require(path.join(__dirname, 'legacy-fs-compat.js'));
}

function configureLegacyFsCompatForChildNode() {
  const compatModulePath = path.join(__dirname, 'legacy-fs-compat.js');
  const requireFlag = `--require=${compatModulePath}`;
  const existingNodeOptions = process.env.NODE_OPTIONS || '';

  if (existingNodeOptions.split(/\s+/).includes(requireFlag)) {
    return;
  }

  process.env.NODE_OPTIONS = existingNodeOptions
      ? `${requireFlag} ${existingNodeOptions}`
      : requireFlag;
}

function ensureSymlink(targetPath, linkPath) {
  ensureDirSync(path.dirname(linkPath));
  try {
    const currentTarget = fs.readlinkSync(linkPath);
    if (path.resolve(path.dirname(linkPath), currentTarget) === targetPath) {
      return;
    }
    removePathSync(linkPath);
  } catch (_) {
    removePathSync(linkPath);
  }
  fs.symlinkSync(targetPath, linkPath, 'dir');
}

function getBundledRuntimeNodeModules() {
  const toolRoot = getHvigorToolRoot();
  const nodeModulesRoot = path.join(appHome, 'hvigor', '.runtime-node_modules');
  ensureSymlink(
      path.join(toolRoot, 'hvigor'),
      path.join(nodeModulesRoot, '@ohos', 'hvigor'),
  );
  ensureSymlink(
      path.join(toolRoot, 'hvigor-ohos-plugin'),
      path.join(nodeModulesRoot, '@ohos', 'hvigor-ohos-plugin'),
  );
  return nodeModulesRoot;
}

function prepareBundledHvigorWorkspace() {
  const workspaceDir = getHvigorWorkspaceDir();
  const config = readHvigorConfig();
  const bundledHvigorVersion = getBundledHvigorVersion();
  const toolRoot = getHvigorToolRoot();
  const packageJsonPath = path.join(workspaceDir, 'package.json');
  const packageJson = {
    dependencies: {
      ...(config.dependencies || {}),
      '@ohos/hvigor': bundledHvigorVersion,
    },
  };

  ensureDirSync(workspaceDir);
  fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson));

  ensureSymlink(
      path.join(toolRoot, 'hvigor'),
      path.join(workspaceDir, 'node_modules', '@ohos', 'hvigor'),
  );
  ensureSymlink(
      path.join(toolRoot, 'hvigor-ohos-plugin'),
      path.join(workspaceDir, 'node_modules', '@ohos', 'hvigor-ohos-plugin'),
  );
}

function prepareNodePath() {
  const nodePaths = [
    path.join(getHvigorWorkspaceDir(), 'node_modules'),
    getBundledRuntimeNodeModules(),
  ];
  if (process.env.NODE_PATH) {
    nodePaths.push(process.env.NODE_PATH);
  }
  process.env.NODE_PATH = nodePaths.join(path.delimiter);
  Module._initPaths();
}

function patchHvigorConfigForUpstreamWrapper() {
  const hvigorConfigPath = path.join(appHome, 'hvigor', 'hvigor-config.json5');
  const bundledHvigorVersion = getBundledHvigorVersion();
  const originalReadFileSync = fs.readFileSync;

  fs.readFileSync = function patchedReadFileSync(filePath, options) {
    const resolvedPath = typeof filePath === 'string' ? path.resolve(filePath) : null;
    const content = originalReadFileSync.apply(this, arguments);
    const stringContent = Buffer.isBuffer(content) ? content.toString('utf8') : content;

    if (resolvedPath === hvigorConfigPath) {
      const config = JSON.parse(stringContent);
      if (!config.hvigorVersion) {
        config.hvigorVersion = bundledHvigorVersion;
      }
      const patchedContent = `${JSON.stringify(config, null, 2)}\n`;
      return normalizePatchedReadContent(patchedContent, options);
    }

    return content;
  };

  return () => {
    fs.readFileSync = originalReadFileSync;
  };
}

function normalizePatchedReadContent(content, options) {
  if (options == null) {
    return Buffer.from(content);
  }
  if (typeof options === 'string') {
    return content;
  }
  if (typeof options === 'object' && options.encoding) {
    return content;
  }
  return Buffer.from(content);
}

function resolveFlutterNativeHar(flutterSdk) {
  const candidates = [
    path.join(
        flutterSdk,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ohos-arm64-release',
        'arm64_v8a_release.har',
    ),
    path.join(
        flutterSdk,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ohos-arm64-profile',
        'arm64_v8a_profile.har',
    ),
    path.join(
        flutterSdk,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ohos-arm64',
        'arm64_v8a_debug.har',
    ),
  ];

  return candidates.find((candidate) => fs.existsSync(candidate)) || '';
}

function patchOhosPackageForNativeHar(appHome, flutterSdk) {
  const packagePath = path.join(appHome, 'oh-package.json5');
  if (!fs.existsSync(packagePath)) {
    return () => {};
  }

  const nativeHar = resolveFlutterNativeHar(flutterSdk);
  if (!nativeHar) {
    return () => {};
  }

  const originalContent = fs.readFileSync(packagePath, 'utf8');
  const packageConfig = JSON.parse(originalContent);
  const overrides = {
    ...(packageConfig.overrides || {}),
    flutter_native_arm64_v8a: `file:${nativeHar}`,
  };
  packageConfig.overrides = overrides;
  fs.writeFileSync(packagePath, `${JSON.stringify(packageConfig, null, 2)}\n`);

  return () => {
    fs.writeFileSync(packagePath, originalContent);
  };
}

// Keep the entry module dependencies aligned with the custom registrant below.
// Pulling additional local OHOS plugins into entry causes ArkTS to compile their
// source trees as local modules, which breaks debug builds and is unrelated to
// the VPN validation path.
const entryHarDependencies = {};

function patchEntryHarDependencies(appHome) {
  const entryPackagePath = path.join(appHome, 'entry', 'oh-package.json5');
  if (!fs.existsSync(entryPackagePath)) {
    return () => {};
  }

  const originalContent = fs.readFileSync(entryPackagePath, 'utf8');
  const packageConfig = JSON.parse(originalContent);
  packageConfig.dependencies = {
    ...(packageConfig.dependencies || {}),
    ...entryHarDependencies,
  };
  fs.writeFileSync(entryPackagePath, `${JSON.stringify(packageConfig, null, 2)}\n`);

  removePathSync(path.join(appHome, 'entry', 'oh-package-lock.json5'));
  for (const packageName of Object.keys(entryHarDependencies)) {
    removePathSync(path.join(appHome, 'entry', 'oh_modules', packageName));
  }

  return () => {
    fs.writeFileSync(entryPackagePath, originalContent);
  };
}

function restoreCustomGeneratedPluginRegistrant(appHome) {
  const registrantPath = path.join(
      appHome,
      'entry',
      'src',
      'main',
      'ets',
      'plugins',
      'GeneratedPluginRegistrant.ets',
  );
  if (!fs.existsSync(registrantPath)) {
    return;
  }

  const originalRegistrant = fs.readFileSync(registrantPath, 'utf8');
  let patchedRegistrant = originalRegistrant;

  if (!patchedRegistrant.includes("import { stringifyError } from './error_utils';")) {
    patchedRegistrant = patchedRegistrant.replace(
        /(?:import .*;\n)+/m,
        (match) => `${match}import { stringifyError } from './error_utils';\n`,
    );
  }

  patchedRegistrant = patchedRegistrant.replace(
      /Log\.e\(TAG, "Received exception while registering", e\);/,
      `Log.e(
        TAG,
        \`Received exception while registering: \${stringifyError(e)}\`,
      );`,
  );

  if (patchedRegistrant !== originalRegistrant) {
    fs.writeFileSync(registrantPath, patchedRegistrant);
  }
}

function patchFlutterOhosNavigationChannel(appHome) {
  const ohpmRoots = [
    path.join(appHome, 'oh_modules', '.ohpm'),
    path.join(appHome, 'entry', 'oh_modules', '.ohpm'),
  ];
  const before = `    const argsMap = call.args as Map<string, string>;
    const currentUri: string = argsMap.get('uri') ?? '';
`;
  const after = `    const uriArg = call.argument('uri');
    const currentUri: string = typeof uriArg === 'string' ? uriArg : '';
`;

  for (const ohpmRoot of ohpmRoots) {
    if (!fs.existsSync(ohpmRoot)) {
      continue;
    }
    for (const packageName of fs.readdirSync(ohpmRoot)) {
      if (!packageName.startsWith('@ohos+flutter_ohos@')) {
        continue;
      }
      const channelPath = path.join(
          ohpmRoot,
          packageName,
          'oh_modules',
          '@ohos',
          'flutter_ohos',
          'src',
          'main',
          'ets',
          'embedding',
          'engine',
          'systemchannels',
          'NavigationChannel.ets',
      );
      if (!fs.existsSync(channelPath)) {
        continue;
      }
      const originalContent = fs.readFileSync(channelPath, 'utf8');
      if (!originalContent.includes(before)) {
        continue;
      }
      fs.writeFileSync(channelPath, originalContent.replace(before, after));
      console.log(`[flclash] patched NavigationChannel: ${channelPath}`);
    }
  }
}

function patchFlutterSdkNavigationChannel(flutterSdk) {
  const channelPath = path.join(
      path.resolve(flutterSdk),
      'engine',
      'src',
      'flutter',
      'shell',
      'platform',
      'ohos',
      'flutter_embedding',
      'flutter',
      'src',
      'main',
      'ets',
      'embedding',
      'engine',
      'systemchannels',
      'NavigationChannel.ets',
  );
  if (!fs.existsSync(channelPath)) {
    return () => {};
  }

  const before = `    const argsMap = call.args as Map<string, string>;
    const currentUri: string = argsMap.get('uri') ?? '';
`;
  const after = `    const uriArg = call.argument('uri');
    const currentUri: string = typeof uriArg === 'string' ? uriArg : '';
`;
  const originalContent = fs.readFileSync(channelPath, 'utf8');
  if (!originalContent.includes(before)) {
    return () => {};
  }

  fs.writeFileSync(channelPath, originalContent.replace(before, after));
  console.log(`[flclash] patched Flutter SDK NavigationChannel: ${channelPath}`);
  return () => {
    fs.writeFileSync(channelPath, originalContent);
  };
}

function patchFlutterEmbeddingHar(flutterSdk) {
  const scriptPath = path.join(
      appHome,
      '..',
      'scripts',
      'ohos',
      'patch_flutter_embedding_har.py',
  );
  if (!fs.existsSync(scriptPath)) {
    return;
  }
  const candidates = [
    path.join(
        flutterSdk,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ohos-arm64',
        'flutter_embedding_debug.har',
    ),
    path.join(
        flutterSdk,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ohos-arm64-profile',
        'flutter_embedding_profile.har',
    ),
    path.join(
        flutterSdk,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ohos-arm64-release',
        'flutter_embedding_release.har',
    ),
  ].filter((candidate) => fs.existsSync(candidate));
  if (candidates.length === 0) {
    return;
  }
  childProcess.execFileSync('python3', [scriptPath, ...candidates], {
    stdio: 'inherit',
  });
}

function syncLatestOhosCoreLibraries(appHome) {
  const rootDir = path.resolve(appHome, '..');
  const sourcePath = path.join(
      rootDir,
      'libclash',
      'ohos',
      'arm64-v8a',
      'libclash.so',
  );
  if (!fs.existsSync(sourcePath)) {
    return;
  }

  const targetPaths = [
    path.join(appHome, 'entry', 'libs', 'arm64-v8a', 'libclash.so'),
    path.join(appHome, 'entry', 'libs', 'arm64', 'libclash.so'),
  ];

  let copied = false;
  for (const targetPath of targetPaths) {
    copied = copyFileIfChanged(sourcePath, targetPath) || copied;
  }

  if (copied) {
    console.log(
        `[flclash] synced OHOS core library from ${sourcePath} to entry/libs`,
    );
  }
}

function buildLatestOhosBundledCoreExecutable(appHome) {
  const rootDir = path.resolve(appHome, '..');
  const outputPath = path.join(
      rootDir,
      'ohos',
      'entry',
      'libs',
      'arm64',
      'libFlClashCore.so',
  );
  ensureDirSync(path.dirname(outputPath));
  childProcess.execFileSync('go', [
    'build',
    '-ldflags=-w -s -X github.com/metacubex/mihomo/component/http.forceConservativeTransport=true',
    '-tags=with_gvisor',
    '-o',
    outputPath,
  ], {
    cwd: path.join(rootDir, 'core'),
    env: {
      ...process.env,
      GOOS: 'linux',
      GOARCH: 'arm64',
      CGO_ENABLED: '0',
    },
    stdio: 'inherit',
  });
  try {
    fs.chmodSync(outputPath, 0o755);
  } catch (_) {
  }
  console.log(
      `[flclash] built OHOS bundled executable core: ${outputPath}`,
  );
}

function syncLatestOhosBundledCoreExecutable(appHome) {
  const rootDir = path.resolve(appHome, '..');
  const sourcePath = path.join(
      rootDir,
      'ohos',
      'entry',
      'libs',
      'arm64',
      'libFlClashCore.so',
  );
  if (!fs.existsSync(sourcePath)) {
    return;
  }

  const targetPath = path.join(rootDir, 'assets', 'data', 'FlClashCore');
  if (!copyFileIfChanged(sourcePath, targetPath)) {
    return;
  }

  try {
    fs.chmodSync(targetPath, 0o755);
  } catch (_) {
  }
  console.log(
      `[flclash] synced OHOS bundled executable core from ${sourcePath} to ${targetPath}`,
  );
}

const upstreamWrapperPath = path.join(
    path.resolve(flutterSdk),
    'engine',
    'src',
    'flutter',
    'shell',
    'platform',
    'ohos',
    'flutter_embedding',
    'hvigor',
    'hvigor-wrapper.js',
);

relaunchWithBundledNodeIfNeeded();

if (!fs.existsSync(upstreamWrapperPath)) {
  fail(`Unable to find the upstream Flutter OHOS hvigor wrapper at ${upstreamWrapperPath}`);
}

prepareOpenHarmonySigningAssets({
  appHome,
  ohosSdkHome:
      process.env.FLCLASH_OHOS_SOURCE_SDK_HOME ||
      process.env.HOS_SDK_HOME ||
      process.env.OHOS_SDK_HOME ||
      process.env.OHOS_BASE_SDK_HOME ||
      '',
  signToolPath: path.join(
      process.env.FLCLASH_OHOS_SOURCE_SDK_HOME ||
      process.env.HOS_SDK_HOME ||
      process.env.OHOS_SDK_HOME ||
      process.env.OHOS_BASE_SDK_HOME ||
      '',
      'toolchains',
      'lib',
      'hap-sign-tool.jar',
  ),
  bundleName: 'com.follow.clash',
});

syncLatestOhosCoreLibraries(appHome);
buildLatestOhosBundledCoreExecutable(appHome);
syncLatestOhosBundledCoreExecutable(appHome);
patchFlutterEmbeddingHar(flutterSdk);
prepareBundledHvigorWorkspace();
prepareNodePath();
installLegacyFsCompat();
configureLegacyFsCompatForChildNode();
const restorePackage = patchOhosPackageForNativeHar(appHome, flutterSdk);
const restoreEntryPackage = patchEntryHarDependencies(appHome);
restoreCustomGeneratedPluginRegistrant(appHome);
const restoreFs = patchHvigorConfigForUpstreamWrapper();
patchFlutterOhosNavigationChannel(appHome);
const restoreFlutterSdkNavigationChannel = patchFlutterSdkNavigationChannel(flutterSdk);
process.on('exit', () => {
  restoreEntryPackage();
  restorePackage();
  restoreFs();
  restoreFlutterSdkNavigationChannel();
});

require(upstreamWrapperPath);
