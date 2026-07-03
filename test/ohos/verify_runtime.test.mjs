import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const scriptPath = path.join(repoRoot, 'scripts/ohos/verify_runtime.sh');

test('verify_runtime clears live logs before polling so stale core init logs do not short-circuit the current run', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flclash-verify-runtime-live-stale-'));
  const fakeHdcPath = path.join(tempDir, 'hdc');
  const fakeInstallPath = path.join(tempDir, 'install_and_launch.sh');
  const statePath = path.join(tempDir, 'state');

  fs.writeFileSync(
    fakeInstallPath,
    '#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n',
    { mode: 0o755 },
  );

  fs.writeFileSync(
    fakeHdcPath,
    `#!/usr/bin/env bash
set -euo pipefail
state_path="${statePath}"
if [[ "\${1:-}" == "list" && "\${2:-}" == "targets" ]]; then
  printf '%s\\n' 'fake-target'
  exit 0
fi
if [[ "\${1:-}" == "-t" ]]; then
  shift 2
fi
cmd="\${2:-}"
if [[ "\${1:-}" == "shell" && "$cmd" == "hilog -r" ]]; then
  printf '%s' 'cleared' > "$state_path"
  exit 0
fi
if [[ "\${1:-}" == "shell" && "$cmd" == *"hilog -z 800"* ]]; then
  state=""
  if [[ -f "$state_path" ]]; then
    state=$(cat "$state_path")
  fi
  if [[ "$state" == "cleared" ]]; then
    printf '%s\\n' '[OHOS-CORE] invoke initClash#1 begin'
    exit 0
  fi
  printf '%s\\n' '[OHOS-CORE] invoke initClash#1 done'
  printf '%s\\n' '[OHOS-CORE] invoke setupConfig#2 done'
  printf '%s\\n' '[OHOS-CORE] invoke getProxies#3 done'
  printf '%s\\n' '[OHOS-CORE] invoke getExternalProviders#4 done'
  exit 0
fi
exit 0
`,
    { mode: 0o755 },
  );

  const result = spawnSync(
    'bash',
    [scriptPath],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: {
        ...process.env,
        PATH: `${tempDir}:${process.env.PATH ?? ''}`,
        HDC_TARGET: 'fake-target',
        VERIFY_TIMEOUT: '5',
        INSTALL_SCRIPT: fakeInstallPath,
      },
    },
  );

  assert.notEqual(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stderr || result.stdout, /Timed out after 5s waiting for OHOS core initialization logs\./);
});
