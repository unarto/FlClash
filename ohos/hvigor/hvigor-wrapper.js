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
  const localPropertiesPath = path.join(appHome, 'local.properties');
  if (!fs.existsSync(localPropertiesPath)) {
    return process.env.FLUTTER_ROOT || process.env.FLUTTER_SDK || '';
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
    if (key !== 'flutter.sdk') {
      continue;
    }
    const value = trimmed.slice(separatorIndex + 1).trim();
    return unescapePropertyValue(value);
  }

  return process.env.FLUTTER_ROOT || process.env.FLUTTER_SDK || '';
}

const appHome = path.resolve(__dirname, '..');
const flutterSdk = readFlutterSdk(appHome);
if (!flutterSdk) {
  fail('Unable to resolve the Flutter SDK. Set FLUTTER_ROOT or add flutter.sdk to ohos/local.properties.');
}

function getBundledHvigorVersion() {
  const hvigorwPath = childProcess.execFileSync('bash', ['-lc', 'command -v hvigorw'], {
    encoding: 'utf8',
  }).trim();
  const hvigorBinDir = path.dirname(hvigorwPath);
  const toolRoot = path.dirname(hvigorBinDir);
  const packageJsonPath = path.join(toolRoot, 'hvigor', 'hvigor', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  return packageJson.version;
}

function getHvigorToolRoot() {
  const hvigorwPath = childProcess.execFileSync('bash', ['-lc', 'command -v hvigorw'], {
    encoding: 'utf8',
  }).trim();
  return path.dirname(path.dirname(hvigorwPath));
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

function ensureSymlink(targetPath, linkPath) {
  fs.mkdirSync(path.dirname(linkPath), {recursive: true});
  try {
    const currentTarget = fs.readlinkSync(linkPath);
    if (path.resolve(path.dirname(linkPath), currentTarget) === targetPath) {
      return;
    }
    fs.rmSync(linkPath, {recursive: true, force: true});
  } catch (_) {
    fs.rmSync(linkPath, {recursive: true, force: true});
  }
  fs.symlinkSync(targetPath, linkPath, 'dir');
}

function getBundledRuntimeNodeModules() {
  const toolRoot = getHvigorToolRoot();
  const nodeModulesRoot = path.join(appHome, 'hvigor', '.runtime-node_modules');
  ensureSymlink(
      path.join(toolRoot, 'hvigor', 'hvigor'),
      path.join(nodeModulesRoot, '@ohos', 'hvigor'),
  );
  ensureSymlink(
      path.join(toolRoot, 'hvigor', 'hvigor-ohos-plugin'),
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

  fs.mkdirSync(workspaceDir, {recursive: true});
  fs.writeFileSync(packageJsonPath, JSON.stringify(packageJson));

  ensureSymlink(
      path.join(toolRoot, 'hvigor', 'hvigor'),
      path.join(workspaceDir, 'node_modules', '@ohos', 'hvigor'),
  );
  ensureSymlink(
      path.join(toolRoot, 'hvigor', 'hvigor-ohos-plugin'),
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
    if (resolvedPath !== hvigorConfigPath) {
      return content;
    }

    const config = JSON.parse(Buffer.isBuffer(content) ? content.toString('utf8') : content);
    if (!config.hvigorVersion) {
      config.hvigorVersion = bundledHvigorVersion;
    }
    const patchedContent = `${JSON.stringify(config, null, 2)}\n`;

    if (options == null) {
      return Buffer.from(patchedContent);
    }
    if (typeof options === 'string') {
      return patchedContent;
    }
    if (typeof options === 'object' && options.encoding) {
      return patchedContent;
    }
    return Buffer.from(patchedContent);
  };

  return () => {
    fs.readFileSync = originalReadFileSync;
  };
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

function ensureFlutterNativeHar(appHome, flutterSdk) {
  const nativeHar = resolveFlutterNativeHar(flutterSdk);
  if (!nativeHar) {
    return;
  }

  const targetHarDir = path.join(appHome, 'har');
  const targetHarPath = path.join(targetHarDir, 'flutter_native_arm64_v8a.har');
  fs.mkdirSync(targetHarDir, {recursive: true});
  fs.copyFileSync(nativeHar, targetHarPath);
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

if (!fs.existsSync(upstreamWrapperPath)) {
  fail(`Unable to find the upstream Flutter OHOS hvigor wrapper at ${upstreamWrapperPath}`);
}

prepareOpenHarmonySigningAssets({
  appHome,
  ohosSdkHome: process.env.OHOS_SDK_HOME || process.env.OHOS_BASE_SDK_HOME || '',
  signToolPath: path.join(
      process.env.OHOS_SDK_HOME || process.env.OHOS_BASE_SDK_HOME || '',
      'toolchains',
      'lib',
      'hap-sign-tool.jar',
  ),
  bundleName: 'com.follow.clash',
});

ensureFlutterNativeHar(appHome, flutterSdk);
prepareBundledHvigorWorkspace();
prepareNodePath();
const restoreFs = patchHvigorConfigForUpstreamWrapper();
try {
  require(upstreamWrapperPath);
} finally {
  restoreFs();
}
