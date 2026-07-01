import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const sourcePath = new URL(
  '../../ohos/entry/src/main/ets/plugins/vpn_stop_decision.ts',
  import.meta.url,
);
const source = fs.readFileSync(sourcePath, 'utf8');

function loadResolveVpnStopResult() {
  let compiled = source
    .replace(/export interface[\s\S]*?\n}\n/g, '')
    .replace(
      /export function resolveVpnStopResult\s*\(\s*input: VpnStopResolutionInput,\s*\): VpnStopResolution\s*\{/,
      'function resolveVpnStopResult(input) {',
    );
  compiled += '\nmodule.exports = { resolveVpnStopResult };';
  const sandbox = {
    module: { exports: {} },
    exports: {},
  };
  vm.runInNewContext(compiled, sandbox, {
    filename: fileURLToPath(sourcePath),
  });
  return sandbox.module.exports.resolveVpnStopResult;
}

const resolveVpnStopResult = loadResolveVpnStopResult();

function normalize(result) {
  return JSON.parse(JSON.stringify(result));
}

test('VPN stop treats a late stopped status as success even after launcher error', () => {
  assert.deepEqual(
    normalize(resolveVpnStopResult({
      stopErrorMessage: 'stopVpnExtensionAbility timeout',
      status: 'stopped',
    })),
    {
      stopped: true,
      errorMessage: '',
    },
  );
});

test('VPN stop surfaces explicit failed status over a generic launcher error', () => {
  assert.deepEqual(
    normalize(resolveVpnStopResult({
      stopErrorMessage: 'stopVpnExtensionAbility timeout',
      status: 'failed:stopTun failed',
    })),
    {
      stopped: false,
      errorMessage: 'vpn extension did not stop: failed:stopTun failed',
    },
  );
});

test('VPN stop preserves launcher error when status never becomes ready', () => {
  assert.deepEqual(
    normalize(resolveVpnStopResult({
      stopErrorMessage: 'stopVpnExtensionAbility timeout',
      status: '',
    })),
    {
      stopped: false,
      errorMessage: 'stopVpnExtensionAbility timeout',
    },
  );
});
