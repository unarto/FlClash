import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const appPluginSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/AppPlugin.ets', import.meta.url),
  'utf8',
);

test('OHOS stopVpn reconciles a stale started status to stopped so restarts are not blocked', () => {
  // When the VPN extension is killed uncleanly (process death / force-stop) it
  // can no longer write 'stopped' to its status file, leaving a stale 'started'.
  // Without reconciliation that stale status permanently blocks every later
  // startVpn (isVpnStatusRunning short-circuits) and stopVpn
  // (waitForVpnStoppedStatus never observes 'stopped'). FlClashVpnAbility is a
  // system-managed singleton VPN, so stopVpn must reset the stale status and
  // report the VPN as stopped.
  assert.match(
    appPluginSource,
    /if \(!resolution\.stopped && status === 'started'\) \{[\s\S]*this\.resetVpnStatus\(statusPath\);[\s\S]*this\.isVpnRunning = false;[\s\S]*result\.success\(true\);[\s\S]*return;[\s\S]*\}/m,
  );
});
