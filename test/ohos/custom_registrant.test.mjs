import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const customPluginRegistrant = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/CustomPluginRegistrant.ets', import.meta.url),
  'utf8',
);

test('CustomPluginRegistrant guards against duplicate plugin registration', () => {
  assert.match(
    customPluginRegistrant,
    /const plugins = flutterEngine\.getPlugins\(\);/,
  );
  assert.match(
    customPluginRegistrant,
    /if \(!plugins\.has\('AppPlugin'\)\) \{/,
  );
  assert.match(
    customPluginRegistrant,
    /if \(!plugins\.has\('FilePickerPlugin'\)\) \{/,
  );
});
