import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const scriptsWithResolveTarget = [
  'scripts/ohos/install_and_launch.sh',
  'scripts/ohos/keep_awake.sh',
  'scripts/ohos/ui.sh',
  'scripts/ohos/verify_browser_vpn.sh',
  'scripts/ohos/verify_capabilities.sh',
  'scripts/ohos/verify_chrome_vpn.sh',
  'scripts/ohos/verify_compat_vpn.sh',
  'scripts/ohos/verify_runtime.sh',
];

test('OHOS scripts ignore the hdc [Empty] placeholder when resolving targets', () => {
  for (const relativePath of scriptsWithResolveTarget) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.match(
      source,
      /\[\[ "\$target" == "\[Empty\]" \]\] && continue/,
      `${relativePath} still treats [Empty] as a real target`,
    );
  }
});

test('keep_awake fails fast when hdc only reports the [Empty] placeholder', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-ohos-target-empty-'));
  const fakeHdcPath = path.join(tempDir, 'hdc');

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "list" && "\${2:-}" == "targets" ]]; then
  printf '%s\\n' '[Empty]'
  exit 0
fi
printf '%s\\n' "unexpected invocation: $*" >&2
exit 99
`,
    { mode: 0o755 },
  );

  const result = spawnSync(
    'bash',
    ['scripts/ohos/keep_awake.sh'],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
      },
    },
  );

  assert.notEqual(result.status, 0, result.stdout);
  assert.match(
    result.stderr,
    /No HarmonyOS emulator\/device detected|No HarmonyOS target detected/,
  );
});

test('keep_awake skips the [Empty] placeholder when a real device target is also present', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-ohos-target-real-'));
  const fakeHdcPath = path.join(tempDir, 'hdc');
  const invokedTargetPath = path.join(tempDir, 'invoked-target');

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "list" && "\${2:-}" == "targets" ]]; then
  printf '%s\\n' '[Empty]'
  printf '%s\\n' 'real-target'
  exit 0
fi
if [[ "\${1:-}" == "-t" ]]; then
  printf '%s' "\${2:-}" > "${invokedTargetPath}"
  exit 0
fi
printf '%s\\n' "unexpected invocation: $*" >&2
exit 99
`,
    { mode: 0o755 },
  );

  const result = spawnSync(
    'bash',
    ['scripts/ohos/keep_awake.sh'],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
      },
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(fs.readFileSync(invokedTargetPath, 'utf8'), 'real-target');
});
