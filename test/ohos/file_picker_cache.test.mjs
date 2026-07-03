import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const filePickerUtilsSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/FilePickerUtils.ets', import.meta.url),
  'utf8',
);

test('FilePickerUtils isolates picked files under a dedicated file_picker cache directory', () => {
  assert.match(
    filePickerUtilsSource,
    /private static resolveWritableCacheRoot\(context: common\.UIAbilityContext\): string \{[\s\S]*const cacheRoot = `\$\{candidate\}\/file_picker`;/m,
  );
  assert.match(
    filePickerUtilsSource,
    /ensureDir\(cacheRoot\);[\s\S]*return cacheRoot;/m,
  );
  assert.match(
    filePickerUtilsSource,
    /const tempTargetPath = `\$\{cacheRoot\}\/picked_file\.tmp`;/m,
  );
});

test('FilePickerUtils clearCache removes the same candidate directories used by openFileStream', () => {
  assert.match(
    filePickerUtilsSource,
    /static clearCache\(context: common\.UIAbilityContext\): boolean \{[\s\S]*const candidates: Array<string> = \[[\s\S]*context\.filesDir[\s\S]*context\.tempDir[\s\S]*context\.cacheDir[\s\S]*\];/m,
  );
  assert.match(
    filePickerUtilsSource,
    /for \(const candidate of candidates\) \{[\s\S]*const cacheRoot = `\$\{candidate\}\/file_picker`;/m,
  );
  assert.doesNotMatch(
    filePickerUtilsSource,
    /const cacheRoot = `\$\{context\.cacheDir\}\/file_picker`;/m,
  );
  assert.match(
    filePickerUtilsSource,
    /private static clearCacheFiles\(cacheRoot: string\): void \{[\s\S]*const fileNames = fs\.listFileSync\(cacheRoot\);/m,
  );
  assert.match(
    filePickerUtilsSource,
    /for \(const fileName of fileNames\) \{[\s\S]*fs\.unlinkSync\(`\$\{cacheRoot\}\/\$\{fileName\}`\);/m,
  );
  assert.match(
    filePickerUtilsSource,
    /static clearCache\(context: common\.UIAbilityContext\): boolean \{[\s\S]*FilePickerUtils\.clearCacheFiles\(cacheRoot\);[\s\S]*fs\.rmdirSync\(cacheRoot\);/m,
  );
  assert.match(
    filePickerUtilsSource,
    /let hadCleanupFailure = false;/m,
  );
  assert.match(
    filePickerUtilsSource,
    /try \{[\s\S]*fs\.accessSync\(cacheRoot\);[\s\S]*\} catch \(_\) \{[\s\S]*continue;[\s\S]*\}/m,
  );
  assert.match(
    filePickerUtilsSource,
    /return !hadCleanupFailure;/m,
  );
  assert.doesNotMatch(
    filePickerUtilsSource,
    /return cleared;/m,
  );
});
