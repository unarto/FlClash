import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const bridgeSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/cpp/bridge.cpp', import.meta.url),
  'utf8',
);

function extractFunction(name, nextName) {
  const start = bridgeSource.indexOf(`napi_value ${name}(napi_env env, napi_callback_info info) {`);
  const end = bridgeSource.indexOf(
    `napi_value ${nextName}(napi_env env, napi_callback_info info) {`,
  );
  assert.notEqual(start, -1, `${name} not found`);
  assert.notEqual(end, -1, `${nextName} not found`);
  return bridgeSource.slice(start, end);
}

const startCoreChildProcessSource = extractFunction(
  'StartCoreChildProcess',
  'StartBundledCoreProcess',
);
const startBundledCoreProcessSource = extractFunction(
  'StartBundledCoreProcess',
  'StartEmbeddedCore',
);
const startEmbeddedCoreSource = extractFunction(
  'StartEmbeddedCore',
  'StopTrackedCore',
);

test('bundled tracked core force-kill path waits for child exit before clearing tracked state', () => {
  assert.match(
    bridgeSource,
    /if \(kill\(tracked_core\.pid, SIGKILL\) != 0 && errno != ESRCH\) \{[\s\S]*return CreateBool\(env, false\);\s*\}[\s\S]*errno = 0;[\s\S]*if \(waitpid\(tracked_core\.pid, nullptr, 0\) != tracked_core\.pid &&[\s\S]*errno != ECHILD\) \{[\s\S]*waitpid bundled process failed:[\s\S]*return CreateBool\(env, false\);\s*\}[\s\S]*ClearTrackedCoreLaunchIfMatches\(/m,
  );
});

test('child tracked core path confirms exit before clearing tracked state', () => {
  assert.match(
    bridgeSource,
    /if \(tracked_core\.mode == CoreLaunchMode::kChild\) \{[\s\S]*?#endif[\s\S]*?errno = 0;[\s\S]*if \(waitpid\(tracked_core\.pid, nullptr, 0\) != tracked_core\.pid &&[\s\S]*errno != ECHILD\) \{[\s\S]*waitpid child process failed:[\s\S]*return CreateBool\(env, false\);\s*\}[\s\S]*ClearTrackedCoreLaunchIfMatches\([\s\S]*return CreateBool\(env, true\);\s*\}/m,
  );
});

test('child core start path rolls back tracked state when the process exits before tracking completes', () => {
  assert.match(
    startCoreChildProcessSource,
    /TrackCoreLaunch\(CoreLaunchMode::kChild, pid\);[\s\S]*errno = 0;[\s\S]*if \(waitpid\(pid, nullptr, WNOHANG\) == pid \|\| kill\(pid, 0\) != 0\) \{[\s\S]*ClearTrackedCoreLaunchIfMatches\(\s*CoreLaunchMode::kChild,\s*pid,\s*0\);[\s\S]*\}/m,
  );
});

test('bundled core start path rolls back tracked state when the process exits before startup completes', () => {
  assert.match(
    startBundledCoreProcessSource,
    /TrackCoreLaunch\(CoreLaunchMode::kBundled, pid\);[\s\S]*errno = 0;[\s\S]*if \(waitpid\(pid, nullptr, WNOHANG\) == pid \|\| kill\(pid, 0\) != 0\) \{[\s\S]*ClearTrackedCoreLaunchIfMatches\(\s*CoreLaunchMode::kBundled,\s*pid,\s*0\);[\s\S]*SetError\([\s\S]*return CreateInt32\(env, -1\);[\s\S]*\}/m,
  );
});

test('child core start path reports early exit as a start failure so Dart can fallback immediately', () => {
  assert.match(
    startCoreChildProcessSource,
    /TrackCoreLaunch\(CoreLaunchMode::kChild, pid\);[\s\S]*if \(waitpid\(pid, nullptr, WNOHANG\) == pid \|\| kill\(pid, 0\) != 0\) \{[\s\S]*ClearTrackedCoreLaunchIfMatches\(\s*CoreLaunchMode::kChild,\s*pid,\s*0\);[\s\S]*SetError\([\s\S]*return CreateInt32\(env, -1\);[\s\S]*\}/m,
  );
});

test('embedded core preflights dlopen and entrypoint resolution before reporting startup success', () => {
  assert.match(
    startEmbeddedCoreSource,
    /void \*core_handle = dlopen\("libclash\.so", RTLD_NOW \| RTLD_LOCAL\);[\s\S]*if \(core_handle == nullptr\) \{[\s\S]*ClearTrackedCoreLaunchIfMatches\(\s*CoreLaunchMode::kEmbedded,\s*-1,\s*embedded_launch_token\);[\s\S]*SetError\([\s\S]*return CreateInt32\(env, -1\);[\s\S]*\}[\s\S]*auto \*start_server_process = reinterpret_cast<StartServerProcessDetachedFn>\([\s\S]*dlsym\(core_handle, "startServerProcessDetached"\)[\s\S]*\);[\s\S]*if \(start_server_process == nullptr\) \{[\s\S]*ClearTrackedCoreLaunchIfMatches\(\s*CoreLaunchMode::kEmbedded,\s*-1,\s*embedded_launch_token\);[\s\S]*dlclose\(core_handle\);[\s\S]*SetError\([\s\S]*return CreateInt32\(env, -1\);[\s\S]*\}[\s\S]*g_embedded_core_thread = std::thread\(/m,
  );
});

test('embedded core thread does not dlclose or clear tracked state after the non-blocking detached launch', () => {
  // startServerProcessDetached returns immediately (it spawns its own detached
  // goroutine), so tearing down inside the thread would wipe embedded tracking
  // while the core is still live and make StopTrackedCore a silent no-op.
  const threadBody = startEmbeddedCoreSource.slice(
    startEmbeddedCoreSource.indexOf('g_embedded_core_thread = std::thread('),
  );
  assert.doesNotMatch(threadBody, /dlclose\(core_handle\)/);
  assert.doesNotMatch(threadBody, /ClearTrackedCoreLaunchIfMatches\(/);
});
