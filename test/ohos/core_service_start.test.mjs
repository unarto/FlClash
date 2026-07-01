import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const coreServiceSource = fs.readFileSync(
  new URL('../../lib/core/service.dart', import.meta.url),
  'utf8',
);

test('OHOS CoreService aborts restart when a previous tracked core still cannot be stopped', () => {
  assert.match(
    coreServiceSource,
    /if \(_process != null \|\| _ohosCoreLaunch\.hasTrackedCore\) \{[\s\S]*await shutdown\(false\);[\s\S]*if \(system\.isOhos && _ohosCoreLaunch\.hasTrackedCore\) \{[\s\S]*return false;[\s\S]*\}[\s\S]*\}/m,
  );
  assert.match(
    coreServiceSource,
    /Unable to start OHOS core because a previous tracked core is still active/,
  );
});

test('CoreService transport listener awaits handleResult so async parse failures stay inside the local try/catch', () => {
  assert.match(
    coreServiceSource,
    /listen\(\s*\(data\) async \{[\s\S]*try \{[\s\S]*final dataJson = await data\.trim\(\)\.commonToJSON<dynamic>\(\);[\s\S]*await handleResult\(ActionResult\.fromJson\(dataJson\)\);[\s\S]*\} catch \(e\) \{/m,
  );
  assert.ok(
    coreServiceSource.includes(
      '              await handleResult(ActionResult.fromJson(dataJson));',
    ),
  );
});

test('CoreService treats null or empty ids as core events before trying to parse invoke results', () => {
  assert.match(
    coreServiceSource,
    /Future<void> handleResult\(ActionResult result\) async \{[\s\S]*if \(result\.id\?\.isEmpty \?\? true\) \{[\s\S]*coreEventManager\.sendEvent\(CoreEvent\.fromJson\(result\.data\)\);[\s\S]*return;[\s\S]*\}[\s\S]*final completer = _callbackCompleterMap\[result\.id\];[\s\S]*final data = await parasResult\(result\);/m,
  );
});

test('CoreService only records OHOS child or bundled launches after native start returns a positive pid', () => {
  assert.match(
    coreServiceSource,
    /final childPid = await app\?\.startCoreChildProcess\(_transport\.address\);[\s\S]*if \(childPid != null && childPid > 0\) \{[\s\S]*_ohosCoreLaunch = OhosCoreLaunch\.child\(pid: childPid\);[\s\S]*\} else \{[\s\S]*fallback to embedded core/m,
  );
  assert.match(
    coreServiceSource,
    /final pid = await app\?\.startBundledCoreProcess\([\s\S]*if \(pid == null \|\| pid <= 0\) \{[\s\S]*throw StateError\([\s\S]*startBundledCoreProcess returned invalid pid: \$pid[\s\S]*\}[\s\S]*_ohosCoreLaunch = OhosCoreLaunch\.bundled\(pid: pid\);/m,
  );
});
