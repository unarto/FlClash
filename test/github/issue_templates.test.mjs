import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const bugReportTemplate = fs.readFileSync(
  path.join(repoRoot, '.github/ISSUE_TEMPLATE/bug_report.yml'),
  'utf8',
);
const featureRequestTemplate = fs.readFileSync(
  path.join(repoRoot, '.github/ISSUE_TEMPLATE/feature_request.yml'),
  'utf8',
);

test('bug report template includes HarmonyOS in OS options', () => {
  assert.match(
    bugReportTemplate,
    /label: 操作系统 \/ OS[\s\S]*?\n\s+- HarmonyOS\b/,
  );
});

test('feature request template includes HarmonyOS in target OS options', () => {
  assert.match(
    featureRequestTemplate,
    /label: 适用系统 \/ Target OS[\s\S]*?\n\s+- label: HarmonyOS\b/,
  );
});
