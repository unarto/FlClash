import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const sourcePath = new URL(
  '../../ohos/entry/src/main/ets/plugins/error_utils.ts',
  import.meta.url,
);
const source = fs.readFileSync(sourcePath, 'utf8');

function loadStringifyError() {
  const compiled = `${source
    .replace(/export function stringifyError\s*\(/, 'function stringifyError(')
    .replace(/\(error: unknown\): string/, '(error)')
    .replace(/\(error as Record<string, unknown>\)\.message/, 'error.message')
  }\nmodule.exports = { stringifyError };`;
  const sandbox = {
    module: { exports: {} },
    exports: {},
  };
  vm.runInNewContext(compiled, sandbox, {
    filename: fileURLToPath(sourcePath),
  });
  return sandbox.module.exports.stringifyError;
}

const stringifyError = loadStringifyError();
const filePickerDelegate = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/FilePickerDelegate.ets', import.meta.url),
  'utf8',
);
const appPlugin = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/AppPlugin.ets', import.meta.url),
  'utf8',
);
const filePickerUtils = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/FilePickerUtils.ets', import.meta.url),
  'utf8',
);
const generatedPluginRegistrant = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/GeneratedPluginRegistrant.ets', import.meta.url),
  'utf8',
);
const customPluginRegistrant = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/CustomPluginRegistrant.ets', import.meta.url),
  'utf8',
);
const entryAbility = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/entryability/EntryAbility.ets', import.meta.url),
  'utf8',
);
const hvigorWrapper = fs.readFileSync(
  new URL('../../ohos/hvigor/hvigor-wrapper.js', import.meta.url),
  'utf8',
);
const proxyPubspec = fs.readFileSync(
  new URL('../../plugins/proxy/pubspec.yaml', import.meta.url),
  'utf8',
);
const wifiSsidPubspec = fs.readFileSync(
  new URL('../../plugins/wifi_ssid/pubspec.yaml', import.meta.url),
  'utf8',
);
const windowExtPubspec = fs.readFileSync(
  new URL('../../plugins/window_ext/pubspec.yaml', import.meta.url),
  'utf8',
);
const appDartBridge = fs.readFileSync(
  new URL('../../lib/plugins/app.dart', import.meta.url),
  'utf8',
);

test('stringifyError preserves Error.message instead of collapsing to braces', () => {
  const error = new Error('vpn extension not ready: failed:{}');

  assert.equal(
    stringifyError(error),
    'vpn extension not ready: failed:{}',
  );
});

test('stringifyError keeps structured JSON payloads when available', () => {
  assert.equal(
    stringifyError({ code: 1, message: 'boom' }),
    '{"code":1,"message":"boom"}',
  );
});

test('FilePickerDelegate uses shared stringifyError for picker failures', () => {
  assert.match(filePickerDelegate, /import \{ stringifyError \} from '\.\/error_utils';/);
  assert.match(filePickerDelegate, /DocumentViewPicker\.select failed: \$\{stringifyError\(error\)\}/);
  assert.match(filePickerDelegate, /DocumentViewPicker\.select uris-only failed: \$\{stringifyError\(error\)\}/);
  assert.doesNotMatch(filePickerDelegate, /DocumentViewPicker\.select failed: \$\{JSON\.stringify\(error\)\}/);
  assert.doesNotMatch(filePickerDelegate, /DocumentViewPicker\.select uris-only failed: \$\{JSON\.stringify\(error\)\}/);
});

test('AppPlugin uses stringifyError for async failure logs and result errors', () => {
  assert.match(appPlugin, /console\.error\(\s*`\[AppPlugin\] exitApp failed error=\$\{stringifyError\(error\)\}`,\s*\);/);
  assert.match(appPlugin, /console\.error\(\s*`\[AppPlugin\] moveTaskToBack failed error=\$\{stringifyError\(error\)\}`,\s*\);/);
  assert.match(appPlugin, /console\.error\(\s*`\[AppPlugin\] openExternalUrl failed url=\$\{url\} error=\$\{stringifyError\(error\)\}`,\s*\);/);
  assert.match(appPlugin, /console\.error\(\s*`\[AppPlugin\] setClipboardText failed error=\$\{stringifyError\(error\)\}`,\s*\);/);
  assert.match(appPlugin, /getClipboardText failed error=\$\{stringifyError\(error\)\} fallbackLength=/);
  assert.match(appPlugin, /gallery:imported:uri=\$\{AppPlugin\.lastImportedGalleryUri\}:identifier_error=\$\{stringifyError\(infoError\)\}/);
  assert.match(appPlugin, /result\.error\(\s*'START_CORE_CHILD_PROCESS_FAILED',\s*stringifyError\(error\),/);
  assert.match(appPlugin, /result\.error\(\s*'WRITE_SHARED_DOWNLOAD_FAILED',\s*stringifyError\(error\),/);
  assert.doesNotMatch(appPlugin, /error=\$\{error\}/);
  assert.doesNotMatch(appPlugin, /result\.error\([^)]*`\$\{error\}`/);
});

test('Flutter App bridge exposes OHOS gallery identifier diagnostics from AppPlugin', () => {
  assert.match(
    appPlugin,
    /case 'getLastImportedGalleryIdentifier': \{[\s\S]*result\.success\(AppPlugin\.lastImportedGalleryIdentifier\);/m,
  );
  assert.match(
    appDartBridge,
    /Future<String\?> getLastImportedGalleryIdentifier\(\) \{\s*return methodChannel\.invokeMethod<String>\('getLastImportedGalleryIdentifier'\);\s*\}/m,
  );
});

test('FilePickerUtils uses stringifyError instead of String(error) in diagnostics', () => {
  assert.match(filePickerUtils, /import \{ stringifyError \} from '\.\/error_utils';/);
  assert.match(filePickerUtils, /raw=\$\{stringifyError\(error\)\}/);
  assert.match(filePickerUtils, /translated-path-failed:path=\$\{translatedPath\}:error=\$\{stringifyError\(error\)\}/);
  assert.match(filePickerUtils, /errors\.push\(`translatedPath\(\$\{translatedPath\}\): \$\{stringifyError\(error\)\}`\);/);
  assert.match(filePickerUtils, /read:error:uri=\$\{uri\}:copiedFrom=\$\{copiedFrom\}:error=\$\{stringifyError\(error\)\}/);
  assert.match(filePickerUtils, /openFileStream failed: uri=\$\{uri\}[\s\S]*error=\$\{stringifyError\(error\)\}/);
  assert.doesNotMatch(filePickerUtils, /String\(error\)/);
  assert.doesNotMatch(filePickerUtils, /error=\$\{error\}/);
});

test('CustomPluginRegistrant uses stringifyError for custom registration failures', () => {
  assert.match(
    customPluginRegistrant,
    /import \{ stringifyError \} from '\.\/error_utils';/,
  );
  assert.match(
    customPluginRegistrant,
    /Received exception while registering: \$\{stringifyError\(e\)\}/,
  );
  assert.doesNotMatch(
    customPluginRegistrant,
    /Log\.e\(TAG,\s*"Received exception while registering",\s*e\);/,
  );
});

test('GeneratedPluginRegistrant stays Flutter-generated while hvigor wrapper supplies registration error patching', () => {
  assert.doesNotMatch(
    generatedPluginRegistrant,
    /import \{ stringifyError \} from '\.\/error_utils';/,
  );
  assert.match(
    generatedPluginRegistrant,
    /Log\.e\(TAG, "Received exception while registering", e\);/,
  );
  assert.match(hvigorWrapper, /function restoreCustomGeneratedPluginRegistrant\(appHome\)/);
  assert.match(hvigorWrapper, /Received exception while registering:/);
  assert.match(hvigorWrapper, /stringifyError\(e\)/);
  assert.doesNotMatch(
    hvigorWrapper,
    /import AppPlugin from '\.\/AppPlugin';/,
  );
  assert.doesNotMatch(
    hvigorWrapper,
    /import FilePickerPlugin from '\.\/FilePickerPlugin';/,
  );
});

test('OHOS generated registrant excludes local har-only plugins that break the hvigor build', () => {
  // proxy/wifi_ssid/window_ext have no buildable OHOS module (their source dirs lack a
  // src/main/module.json and are not declared in ohos/build-profile.json5). Registering them
  // here makes flutter wire them as local source modules and assembleHap fails with
  // "Failed to resolve OhmUrl". The hvigor wrapper deliberately keeps them out; AppPlugin and
  // FilePickerPlugin are registered via CustomPluginRegistrant instead.
  assert.doesNotMatch(generatedPluginRegistrant, /import ProxyPlugin from 'proxy';/);
  assert.doesNotMatch(generatedPluginRegistrant, /import WifiSsidPlugin from 'wifi_ssid';/);
  assert.doesNotMatch(generatedPluginRegistrant, /import WindowExtPlugin from 'window_ext';/);
  assert.doesNotMatch(generatedPluginRegistrant, /new ProxyPlugin\(\)/);
  assert.doesNotMatch(generatedPluginRegistrant, /new WifiSsidPlugin\(\)/);
  assert.doesNotMatch(generatedPluginRegistrant, /new WindowExtPlugin\(\)/);
  assert.doesNotMatch(generatedPluginRegistrant, /AppPlugin/);
  assert.doesNotMatch(generatedPluginRegistrant, /FilePickerPlugin/);
});

test('OHOS hvigor wrapper patches the generated registrant instead of replacing it wholesale', () => {
  assert.match(hvigorWrapper, /const originalRegistrant = fs\.readFileSync\(registrantPath, 'utf8'\);/);
  assert.doesNotMatch(
    hvigorWrapper,
    /const customRegistrant = `import \{ FlutterEngine, Log \} from '@ohos\/flutter_ohos';/,
  );
  assert.match(
    hvigorWrapper,
    /if \(!patchedRegistrant\.includes\("import \{ stringifyError \} from '\.\/error_utils';"\)\) \{/,
  );
  assert.match(
    hvigorWrapper,
    /patchedRegistrant = patchedRegistrant\.replace\([\s\S]*\/\(\?:import \.\*;\\n\)\+\/m,[\s\S]*\(match\) => `\$\{match\}import \{ stringifyError \} from '\.\/error_utils';\\n`,/,
  );
  assert.match(
    hvigorWrapper,
    /patchedRegistrant = patchedRegistrant\.replace\([\s\S]*Log\\\.e\\\(TAG, "Received exception while registering", e\\\);[\s\S]*stringifyError\(e\)/,
  );
});

test('EntryAbility registers generated and custom plugin registrants separately', () => {
  assert.match(
    entryAbility,
    /import \{ GeneratedPluginRegistrant \} from '\.\.\/plugins\/GeneratedPluginRegistrant';/,
  );
  assert.match(
    entryAbility,
    /import \{ CustomPluginRegistrant \} from '\.\.\/plugins\/CustomPluginRegistrant';/,
  );
  assert.match(
    entryAbility,
    /GeneratedPluginRegistrant\.registerWith\(flutterEngine\)\s*[\r\n]+\s*CustomPluginRegistrant\.registerWith\(flutterEngine\)/,
  );
});

test('OHOS plugin pubspecs do not declare ohos.pluginClass (keeps them har-only, avoids hvigor break)', () => {
  // Declaring an `ohos:` platform with pluginClass makes the flutter tool regenerate
  // GeneratedPluginRegistrant with source-dir imports for these plugins, which hvigor cannot
  // resolve/build. They must stay consumed as prebuilt HARs only.
  assert.doesNotMatch(proxyPubspec, /ohos:\n\s+pluginClass: ProxyPlugin/);
  assert.doesNotMatch(wifiSsidPubspec, /ohos:\n\s+pluginClass: WifiSsidPlugin/);
  assert.doesNotMatch(windowExtPubspec, /ohos:\n\s+pluginClass: WindowExtPlugin/);
});
