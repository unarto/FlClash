import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const repoRoot = path.resolve(import.meta.dirname, '../..');

function writeFakeHdcHarness(tempDir) {
  const fakeHdcPath = path.join(tempDir, 'hdc');
  const fakeUitestPath = path.join(tempDir, 'uitest');
  const capturedArgsPath = path.join(tempDir, 'captured-uitest-args.txt');

  fs.writeFileSync(
    fakeUitestPath,
    `#!/usr/bin/env bash
set -euo pipefail
: > "${capturedArgsPath}"
for arg in "$@"; do
  printf '%s\\n' "$arg" >> "${capturedArgsPath}"
done
`,
    { mode: 0o755 },
  );

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "list" && "\${2:-}" == "targets" ]]; then
  printf '%s\\n' 'real-target'
  exit 0
fi
if [[ "\${1:-}" == "-t" && "\${3:-}" == "shell" ]]; then
  PATH="${tempDir}:\${PATH}" bash -lc "\${4:-}"
  exit 0
fi
printf '%s\\n' "unexpected invocation: $*" >&2
exit 99
`,
    { mode: 0o755 },
  );

  return { capturedArgsPath };
}

test('ui text preserves a full URI with shell metacharacters as one uitest argument', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-ohos-ui-text-'));
  const { capturedArgsPath } = writeFakeHdcHarness(tempDir);
  const uri = 'https://example.com/watch?v=1&list=abc';

  const result = spawnSync(
    'bash',
    ['scripts/ohos/ui.sh', 'text', uri],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
        OHOS_TOOLCHAIN_DIR: '/nonexistent-ohos-toolchain',
      },
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const args = fs.readFileSync(capturedArgsPath, 'utf8').trim().split('\n');
  assert.deepEqual(args, ['uiInput', 'text', uri]);
});

test('ui text-at preserves a full URI with shell metacharacters as one uitest argument', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-ohos-ui-text-at-'));
  const { capturedArgsPath } = writeFakeHdcHarness(tempDir);
  const uri = 'https://example.com/watch?v=1&list=abc';

  const result = spawnSync(
    'bash',
    ['scripts/ohos/ui.sh', 'text-at', '11', '22', uri],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
        OHOS_TOOLCHAIN_DIR: '/nonexistent-ohos-toolchain',
      },
    },
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  const args = fs.readFileSync(capturedArgsPath, 'utf8').trim().split('\n');
  assert.deepEqual(args, ['uiInput', 'inputText', '11', '22', uri]);
});
