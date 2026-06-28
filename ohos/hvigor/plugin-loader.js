'use strict';

const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const Module = require('module');
const os = require('os');
const path = require('path');

function getWorkspaceNodeModules() {
  const configPath = path.join(__dirname, 'hvigor-config.json5');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const dependencies = config.dependencies || {};
  const bundledHvigorVersion = getBundledHvigorVersion();
  const dependencySpec = [
    `@ohos/hvigor@${bundledHvigorVersion}`,
    ...Object.keys(dependencies)
        .sort()
        .map((name) => `${name}@${dependencies[name]}`),
  ].join(',');

  const projectHash = crypto
      .createHash('md5')
      .update(dependencySpec)
      .digest('hex');
  const hvigorUserHome = process.env.HVIGOR_USER_HOME ||
      path.join(os.homedir(), '.hvigor');

  return path.join(
      hvigorUserHome,
      'project_caches',
      projectHash,
      'workspace',
      'node_modules',
  );
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

function removeDirectoryContentsSync(dirPath) {
  for (const entry of fs.readdirSync(dirPath)) {
    removePathSync(path.join(dirPath, entry));
  }
}

function getBundledHvigorVersion() {
  const hvigorBinDir = getHvigorToolRoot();
  const toolRoot = path.dirname(hvigorBinDir);
  const packageJsonPath = path.join(toolRoot, 'hvigor', 'package.json');
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  return packageJson.version;
}

function loadPlugin() {
  return withWorkspaceNodePath((bundledNodeModules, workspaceNodeModules) =>
    require(resolveHvigorPackage(
        '@ohos/hvigor-ohos-plugin',
        [bundledNodeModules, workspaceNodeModules],
    )));
}

function unescapePropertyValue(value) {
  return value
      .replace(/\\\\/g, '\\')
      .replace(/\\:/g, ':')
      .replace(/\\=/g, '=')
      .replace(/\\ /g, ' ');
}

function getFlutterSdkRoot() {
  const envFlutterSdk = process.env.FLUTTER_ROOT || process.env.FLUTTER_SDK || '';
  if (envFlutterSdk) {
    return envFlutterSdk;
  }
  const localPropertiesPath = path.join(__dirname, '..', 'local.properties');
  if (!fs.existsSync(localPropertiesPath)) {
    throw new Error(`Missing local.properties: ${localPropertiesPath}`);
  }

  const lines = fs.readFileSync(localPropertiesPath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    if (!line || line.trimStart().startsWith('#')) {
      continue;
    }
    const index = line.indexOf('=');
    if (index === -1) {
      continue;
    }
    const key = line.slice(0, index).trim();
    if (key === 'flutter.sdk') {
      return unescapePropertyValue(line.slice(index + 1).trim());
    }
  }

  throw new Error(`Missing flutter.sdk in ${localPropertiesPath}`);
}

function withWorkspaceNodePath(loader) {
  const bundledNodeModules = getBundledHvigorNodeModules();
  const workspaceNodeModules = getWorkspaceNodeModules();
  const previousNodePath = process.env.NODE_PATH;
  const previousPaths = Module.globalPaths.slice();
  const nodePaths = [bundledNodeModules, workspaceNodeModules];
  if (previousNodePath) {
    nodePaths.push(previousNodePath);
  }
  process.env.NODE_PATH = nodePaths.join(path.delimiter);
  Module._initPaths();
  try {
    return loader(bundledNodeModules, workspaceNodeModules);
  } finally {
    process.env.NODE_PATH = previousNodePath;
    Module.globalPaths.length = 0;
    Module.globalPaths.push(...previousPaths);
  }
}

function getHvigorToolRoot() {
  const hvigorwPath = resolveHvigorwPath();
  return path.dirname(fs.realpathSync(hvigorwPath));
}

function resolveHvigorwPath() {
  const candidates = [
    process.env.HVIGORW,
    process.env.HVIGOR_HOME && path.join(process.env.HVIGOR_HOME, 'bin', 'hvigorw'),
    process.env.DEVECO_HOME &&
        path.join(process.env.DEVECO_HOME, 'Contents', 'tools', 'hvigor', 'bin', 'hvigorw'),
    '/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw',
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  return childProcess.execFileSync('bash', ['-lc', 'command -v hvigorw'], {
    encoding: 'utf8',
  }).trim();
}

function removePathSync(targetPath) {
  if (!fs.existsSync(targetPath)) {
    return;
  }
  const stat = fs.lstatSync(targetPath);
  if (stat.isDirectory() && !stat.isSymbolicLink()) {
    removeDirectoryContentsSync(targetPath);
    fs.rmdirSync(targetPath);
    return;
  }
  fs.rmSync(targetPath, {force: true});
}

function ensureSymlink(targetPath, linkPath) {
  const parentDir = path.dirname(linkPath);
  ensureDirSync(parentDir);
  if (fs.existsSync(linkPath) || fs.lstatSync(parentDir).isDirectory()) {
    try {
      const currentTarget = fs.readlinkSync(linkPath);
      if (path.resolve(parentDir, currentTarget) === targetPath) {
        return;
      }
    } catch (_) {
      removePathSync(linkPath);
    }
  }
  removePathSync(linkPath);
  fs.symlinkSync(targetPath, linkPath, 'dir');
}

function getBundledHvigorNodeModules() {
  const hvigorBinDir = getHvigorToolRoot();
  const toolRoot = path.dirname(hvigorBinDir);
  const nodeModulesRoot = path.join(__dirname, '.runtime-node_modules');
  const ohosNodeModulesRoot = path.join(nodeModulesRoot, '@ohos');

  ensureSymlink(
      path.join(toolRoot, 'hvigor'),
      path.join(ohosNodeModulesRoot, 'hvigor'),
  );
  ensureSymlink(
      path.join(toolRoot, 'hvigor-ohos-plugin'),
      path.join(ohosNodeModulesRoot, 'hvigor-ohos-plugin'),
  );

  return nodeModulesRoot;
}

function resolveHvigorPackage(packageName, lookupPaths) {
  for (const lookupPath of lookupPaths) {
    try {
      return require.resolve(packageName, {
        paths: [lookupPath],
      });
    } catch (_) {
    }
  }

  throw new Error(`Unable to resolve ${packageName}`);
}

function loadFlutterHvigorPlugin() {
  return withWorkspaceNodePath(() => {
    const flutterHvigorPath = path.join(
        getFlutterSdkRoot(),
        'packages',
        'flutter_tools',
        'hvigor',
    );
    const flutterHvigorPlugin = require(require.resolve(flutterHvigorPath));
    return {
      ...flutterHvigorPlugin,
      flutterHvigorPlugin(flutterProjectPath, flutterProjectType = 0) {
        const plugin = flutterHvigorPlugin.flutterHvigorPlugin(
            flutterProjectPath,
            flutterProjectType,
        );
        return {
          ...plugin,
          apply(rootNode) {
            return plugin.apply(rootNode);
          },
        };
      },
    };
  });
}

function ensureProjectFlutterOverrides(appContext) {
  if (!appContext || typeof appContext.getOverrides !== 'function') {
    return;
  }

  const overrides = appContext.getOverrides();
  if (!overrides || typeof overrides !== 'object') {
    return;
  }

  const nextOverrides = {...overrides};
  if (nextOverrides['@ohos/flutter_ohos']) {
    appContext.setOverrides(nextOverrides);
  }
}

function ensureFlutterHar(moduleDir) {
  const sourceHarPath = path.join(__dirname, '..', 'har', 'flutter.har');
  const targetHarDir = path.join(moduleDir, 'har');
  const targetHarPath = path.join(targetHarDir, 'flutter.har');

  if (!fs.existsSync(sourceHarPath)) {
    throw new Error(`Missing Flutter HAR: ${sourceHarPath}`);
  }

  ensureDirSync(targetHarDir);

  const sourceStat = fs.statSync(sourceHarPath);
  const targetExists = fs.existsSync(targetHarPath);
  if (targetExists) {
    const targetStat = fs.statSync(targetHarPath);
    if (targetStat.size === sourceStat.size &&
        targetStat.mtimeMs >= sourceStat.mtimeMs) {
      return targetHarPath;
    }
  }

  fs.copyFileSync(sourceHarPath, targetHarPath);
  return targetHarPath;
}

function prepareNativePluginModule(moduleDir) {
  const moduleOhModulesDir = path.join(moduleDir, 'oh_modules');

  if (fs.existsSync(moduleOhModulesDir)) {
    const stat = fs.lstatSync(moduleOhModulesDir);
    if (stat.isSymbolicLink()) {
      removePathSync(moduleOhModulesDir);
    }
  }
  ensureDirSync(moduleOhModulesDir);

  const flutterHarPath = ensureFlutterHar(moduleDir);
  const ohPackagePath = path.join(moduleDir, 'oh-package.json5');
  if (!fs.existsSync(ohPackagePath)) {
    return;
  }

  const config = JSON.parse(fs.readFileSync(ohPackagePath, 'utf8'));
  const relativeFlutterHarPath = path.relative(moduleDir, flutterHarPath).replaceAll(path.sep, '/');
  config.dependencies = {
    ...(config.dependencies || {}),
    '@ohos/flutter_ohos': `file:${relativeFlutterHarPath}`,
  };
  if (config.overrides) {
    delete config.overrides;
  }
  fs.writeFileSync(ohPackagePath, `${JSON.stringify(config, null, 2)}\n`);
}

module.exports = {
  ...loadPlugin(),
  ensureFlutterHar,
  loadFlutterHvigorPlugin,
  prepareNativePluginModule,
};
