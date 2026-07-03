import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const sourcePath = new URL(
  '../../ohos/entry/src/main/ets/plugins/vpn_start_decision.ts',
  import.meta.url,
);
const source = fs.readFileSync(sourcePath, 'utf8');

function loadResolveVpnStartResult() {
  let compiled = source
    .replace(/export interface[\s\S]*?\n}\n/g, '')
    .replace(
      /export function resolveVpnStartResult\s*\(\s*input: VpnStartResolutionInput,\s*\): VpnStartResolution\s*\{/,
      'function resolveVpnStartResult(input) {',
    );
  compiled += '\nmodule.exports = { resolveVpnStartResult };';
  const sandbox = {
    module: { exports: {} },
    exports: {},
  };
  vm.runInNewContext(compiled, sandbox, {
    filename: fileURLToPath(sourcePath),
  });
  return sandbox.module.exports.resolveVpnStartResult;
}

const resolveVpnStartResult = loadResolveVpnStartResult();

function normalize(result) {
  return JSON.parse(JSON.stringify(result));
}

test('VPN start treats a late started status as success even after launcher timeout', () => {
  assert.deepEqual(
    normalize(resolveVpnStartResult({
      startErrorMessage: 'startVpnExtensionAbility timeout',
      status: 'started',
    })),
    {
      started: true,
      errorMessage: '',
    },
  );
});

test('VPN start surfaces explicit failed status over a generic timeout', () => {
  assert.deepEqual(
    normalize(resolveVpnStartResult({
      startErrorMessage: 'startVpnExtensionAbility timeout',
      status: 'failed:{}',
    })),
    {
      started: false,
      errorMessage: 'vpn extension not ready: failed:{}',
    },
  );
});

test('VPN start preserves launcher error when status never becomes ready', () => {
  assert.deepEqual(
    normalize(resolveVpnStartResult({
      startErrorMessage: 'startVpnExtensionAbility timeout',
      status: '',
    })),
    {
      started: false,
      errorMessage: 'startVpnExtensionAbility timeout',
    },
  );
});
