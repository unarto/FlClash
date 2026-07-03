import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const appPluginSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/AppPlugin.ets', import.meta.url),
  'utf8',
);

const filePickerPluginSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/FilePickerPlugin.ets', import.meta.url),
  'utf8',
);

const filePickerDelegateSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/FilePickerDelegate.ets', import.meta.url),
  'utf8',
);

test('AppPlugin implements ability detach cleanup for flutter_ohos lifecycle', () => {
  assert.match(
    appPluginSource,
    /onDetachedFromAbility\(\): void \{[\s\S]*this\.channel\.setMethodCallHandler\(null\);[\s\S]*this\.abilityBinding = null;[\s\S]*this\.ability = null;[\s\S]*AppPlugin\.activeChannel === detachedChannel[\s\S]*AppPlugin\.activeChannel = null;[\s\S]*this\.applicationContext = this\.pluginBinding\?\.getApplicationContext\(\) \?\? null;[\s\S]*\}/m,
  );
  assert.match(
    appPluginSource,
    /onDetachedFromEngine\(binding: FlutterPluginBinding\): void \{[\s\S]*this\.onDetachedFromAbility\(\);[\s\S]*this\.pluginBinding = null;[\s\S]*this\.applicationContext = null;[\s\S]*\}/m,
  );
});

test('FilePickerPlugin implements ability detach cleanup for flutter_ohos lifecycle', () => {
  assert.match(
    filePickerPluginSource,
    /onDetachedFromAbility\(\): void \{[\s\S]*this\.delegate\?\.cancelPendingResult\([\s\S]*this\.channel\.setMethodCallHandler\(null\);[\s\S]*this\.channel = null;[\s\S]*this\.abilityBinding = null;[\s\S]*this\.ability = null;[\s\S]*this\.delegate = null;[\s\S]*\}/m,
  );
  assert.match(
    filePickerPluginSource,
    /onDetachedFromEngine\(binding: FlutterPluginBinding\): void \{[\s\S]*this\.onDetachedFromAbility\(\);[\s\S]*this\.pluginBinding = null;[\s\S]*\}/m,
  );
});

test('FilePickerDelegate can fail an in-flight picker result during lifecycle teardown', () => {
  assert.match(
    filePickerDelegateSource,
    /cancelPendingResult\(code: string, message: string\): void \{[\s\S]*this\.finishWithError\(code, message\);[\s\S]*\}/m,
  );
});

test('FilePickerDelegate ignores stale async picker callbacks after lifecycle cancellation', () => {
  assert.match(
    filePickerDelegateSource,
    /private isPendingResultActive\(result: MethodResult \| null\): boolean \{[\s\S]*return result !== null && this\.pendingResult === result;[\s\S]*\}/m,
  );
  assert.match(
    filePickerDelegateSource,
    /const pendingResult = result;[\s\S]*documentPicker\.save\(options\)[\s\S]*\.then\(\(saveResult: Array<string>\) => \{[\s\S]*if \(!this\.isPendingResultActive\(pendingResult\)\) \{[\s\S]*return;[\s\S]*\}/m,
  );
  assert.match(
    filePickerDelegateSource,
    /const pendingResult = result;[\s\S]*documentPicker\.save\(options\)[\s\S]*\.catch\(\(error: BusinessError\) => \{[\s\S]*if \(!this\.isPendingResultActive\(pendingResult\)\) \{[\s\S]*return;[\s\S]*\}/m,
  );
  assert.match(
    filePickerDelegateSource,
    /const pendingResult = result;[\s\S]*documentPicker\.select\(options\)[\s\S]*\.then\(\(uris: Array<string>\) => \{[\s\S]*setTimeout\(\(\) => \{[\s\S]*if \((?:pendingResult === null \|\| )?!this\.isPendingResultActive\(pendingResult\)\) \{[\s\S]*return;[\s\S]*\}[\s\S]*void this\.handlePickedUris\(pendingResult, uris\);/m,
  );
  assert.match(
    filePickerDelegateSource,
    /private async handlePickedUris\(result: MethodResult, uris: Array<string>\): Promise<void> \{[\s\S]*if \(!this\.isPendingResultActive\(result\)\) \{[\s\S]*return;[\s\S]*\}/m,
  );
  assert.match(
    filePickerDelegateSource,
    /openPickerUrisOnly\(initialDirectory: string\): void \{[\s\S]*const pendingResult = this\.pendingResult;[\s\S]*documentPicker\.select\(options\)[\s\S]*\.then\(async \(uris: Array<string>\) => \{[\s\S]*if \(!this\.isPendingResultActive\(pendingResult\)\) \{[\s\S]*return;[\s\S]*\}/m,
  );
});

test('FilePickerDelegate converts readPickedFile async failures into result.error instead of leaking uncaught throws', () => {
  assert.match(
    filePickerDelegateSource,
    /async readPickedFile\(uri: string, withData: boolean, result: MethodResult\): Promise<void> \{[\s\S]*try \{[\s\S]*const file = await FilePickerUtils\.openFileStream\(context, uri, withData\);/m,
  );
  assert.match(
    filePickerDelegateSource,
    /async readPickedFile\(uri: string, withData: boolean, result: MethodResult\): Promise<void> \{[\s\S]*catch \(error\) \{[\s\S]*Log\.e\(TAG, `readPickedFile failed: uri=\$\{uri\}, error=\$\{stringifyError\(error\)\}`\);[\s\S]*result\.error\('read_failed', stringifyError\(error\), null\);[\s\S]*\}/m,
  );
});

test('FilePickerDelegate converts handlePickedUris async failures into finishWithError instead of leaking uncaught throws', () => {
  assert.match(
    filePickerDelegateSource,
    /private async handlePickedUris\(result: MethodResult, uris: Array<string>\): Promise<void> \{[\s\S]*for \(const uri of uris\) \{[\s\S]*try \{[\s\S]*const file = await FilePickerUtils\.openFileStream\(context, uri, this\.withData\);/m,
  );
  assert.match(
    filePickerDelegateSource,
    /private async handlePickedUris\(result: MethodResult, uris: Array<string>\): Promise<void> \{[\s\S]*catch \(error\) \{[\s\S]*Log\.e\(TAG, `handlePickedUris failed: uri=\$\{uri\}, error=\$\{stringifyError\(error\)\}`\);[\s\S]*this\.finishWithError\('read_failed', stringifyError\(error\)\);[\s\S]*return;[\s\S]*\}/m,
  );
});
