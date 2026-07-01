import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const scriptPath = path.join(repoRoot, 'scripts/ohos/verify_capabilities.sh');

test('verify_capabilities waits for decisive VPN markers instead of stopping at launch-attempt logs', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-verify-capabilities-'));
  const fakeHdcPath = path.join(tempDir, 'hdc');
  const statePath = path.join(tempDir, 'hilog-count');

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
state_path="${statePath}"
if [[ "\${1:-}" == "-t" ]]; then
  shift 2
fi
if [[ "\${1:-}" == "shell" && "\${2:-}" == *"hilog -z"* ]]; then
  count=0
  if [[ -f "$state_path" ]]; then
    count=$(cat "$state_path")
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$state_path"
  if (( count == 1 )); then
    printf '%s\\n' '[AppPlugin] startVpn stack=mixed ipv6=false'
    exit 0
  fi
  printf '%s\\n' '[AppPlugin] startVpn stack=mixed ipv6=false'
  printf '%s\\n' '[FlClashVpnAbility] started fd=10 stack=mixed ipv6=false'
  exit 0
fi
exit 0
`,
    { mode: 0o755 },
  );

  const result = spawnSync(
    'bash',
    [scriptPath, 'vpn', '--skip-install'],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
        HDC_TARGET: 'fake-target',
        VERIFY_TIMEOUT: '5',
      },
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /\[FlClashVpnAbility\] started fd=10/);
  assert.match(result.stdout, /PASS VPN ability started successfully\./);
});

test('verify_capabilities does not stop on a timeout-style AppPlugin failure if a later started marker appears', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-verify-capabilities-late-start-'));
  const fakeHdcPath = path.join(tempDir, 'hdc');
  const statePath = path.join(tempDir, 'hilog-count');

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
state_path="${statePath}"
if [[ "\${1:-}" == "-t" ]]; then
  shift 2
fi
if [[ "\${1:-}" == "shell" && "\${2:-}" == *"hilog -z"* ]]; then
  count=0
  if [[ -f "$state_path" ]]; then
    count=$(cat "$state_path")
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$state_path"
  if (( count == 1 )); then
    printf '%s\\n' '[AppPlugin] startVpn stack=mixed ipv6=false'
    printf '%s\\n' '[AppPlugin] startVpn failed error=startVpnExtensionAbility timeout lastError='
    exit 0
  fi
  printf '%s\\n' '[AppPlugin] startVpn stack=mixed ipv6=false'
  printf '%s\\n' '[AppPlugin] startVpn failed error=startVpnExtensionAbility timeout lastError='
  printf '%s\\n' '[FlClashVpnAbility] started fd=10 stack=mixed ipv6=false'
  exit 0
fi
exit 0
`,
    { mode: 0o755 },
  );

  const result = spawnSync(
    'bash',
    [scriptPath, 'vpn', '--skip-install'],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
        HDC_TARGET: 'fake-target',
        VERIFY_TIMEOUT: '5',
      },
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /\[FlClashVpnAbility\] started fd=10/);
  assert.match(result.stdout, /PASS VPN ability started successfully\./);
});

test('verify_capabilities classifies mixed VPN logs by the latest decisive marker', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-verify-capabilities-mixed-'));
  const logPath = path.join(tempDir, 'vpn.log');

  fs.writeFileSync(
    logPath,
    [
      '[FlClashVpnAbility] started fd=10 stack=mixed ipv6=false',
      '[AppPlugin] startVpn stack=mixed ipv6=false',
      '[AppPlugin] startVpn failed error=startVpnExtensionAbility timeout lastError=',
    ].join('\n'),
  );

  const result = spawnSync(
    'bash',
    [scriptPath, 'vpn', '--log-file', logPath],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: process.env,
    },
  );

  assert.equal(result.status, 1, result.stderr || result.stdout);
  assert.match(result.stdout, /FAIL VPN startup is blocked on the current target\./);
});

test('verify_capabilities clears live VPN logs before skip-install polling so stale started logs do not short-circuit the current run', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-verify-capabilities-live-stale-'));
  const fakeHdcPath = path.join(tempDir, 'hdc');
  const statePath = path.join(tempDir, 'state');

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
state_path="${statePath}"
if [[ "\${1:-}" == "-t" ]]; then
  shift 2
fi
cmd="\${2:-}"
if [[ "\${1:-}" == "shell" && "$cmd" == "hilog -r" ]]; then
  printf '%s' 'cleared' > "$state_path"
  exit 0
fi
if [[ "\${1:-}" == "shell" && "$cmd" == *"hilog -z"* ]]; then
  state=""
  if [[ -f "$state_path" ]]; then
    state=$(cat "$state_path")
  fi
  if [[ "$state" == "cleared" ]]; then
    printf '%s\\n' '[AppPlugin] startVpn stack=mixed ipv6=false'
    printf '%s\\n' '[AppPlugin] startVpn failed error=startVpnExtensionAbility timeout lastError='
    exit 0
  fi
  printf '%s\\n' '[FlClashVpnAbility] started fd=10 stack=mixed ipv6=false'
  exit 0
fi
exit 0
`,
    { mode: 0o755 },
  );

  const result = spawnSync(
    'bash',
    [scriptPath, 'vpn', '--skip-install'],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
        HDC_TARGET: 'fake-target',
        VERIFY_TIMEOUT: '5',
      },
    },
  );

  assert.equal(result.status, 1, result.stderr || result.stdout);
  assert.match(result.stdout, /FAIL VPN startup is blocked on the current target\./);
});

test('verify_capabilities classifies mixed child-process logs by the latest decisive marker', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-verify-capabilities-child-mixed-'));
  const logPath = path.join(tempDir, 'child.log');

  fs.writeFileSync(
    logPath,
    [
      'Started OHOS core child process pid=1234',
      '[AppPlugin] startCoreChildProcess failed pid=-1, lastError=Capability not support',
    ].join('\n'),
  );

  const result = spawnSync(
    'bash',
    [scriptPath, 'child-process', '--log-file', logPath],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: process.env,
    },
  );

  assert.equal(result.status, 1, result.stderr || result.stdout);
  assert.match(result.stdout, /FAIL target blocked before native child-process verification completed\./);
});
