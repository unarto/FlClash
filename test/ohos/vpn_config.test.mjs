import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const vpnConfig = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/vpn/vpn_config.ts', import.meta.url),
  'utf8',
);
const vpnAbility = fs.readFileSync(
  new URL(
    '../../ohos/entry/src/main/ets/vpn/FlClashVpnAbility.ets',
    import.meta.url,
  ),
  'utf8',
);

test('OHOS VPN uses a full-system route and only blocks the FlClash app itself', () => {
  assert.doesNotMatch(vpnConfig, /trustedApplications:/);
  assert.match(vpnConfig, /blockedApplications:\s*\[bundleName\]/);
});

test('OHOS VPN still blocks the FlClash app itself from the VPN network', () => {
  assert.match(vpnConfig, /blockedApplications:\s*\[bundleName\]/);
});

test('OHOS VPN keeps the verified Huawei bootstrap and HTTPDNS exclusions', () => {
  assert.match(vpnConfig, /'139\.9\.98\.98'/);
  assert.match(vpnConfig, /'139\.9\.99\.99'/);
  assert.match(vpnConfig, /address:\s*'139\.9\.0\.0'.*prefixLength:\s*16/s);
  assert.match(vpnConfig, /address:\s*'49\.4\.0\.0'.*prefixLength:\s*16/s);
  assert.match(vpnConfig, /address:\s*'121\.36\.0\.0'.*prefixLength:\s*16/s);
  assert.match(vpnConfig, /address:\s*'125\.88\.0\.0'.*prefixLength:\s*16/s);
  assert.match(vpnConfig, /address:\s*'119\.147\.0\.0'.*prefixLength:\s*16/s);
  assert.match(vpnConfig, /address:\s*'183\.61\.0\.0'.*prefixLength:\s*16/s);
});

test('OHOS VPN does not regress to the old hard-coded Huawei HTTPDNS IP list', () => {
  assert.doesNotMatch(vpnConfig, /'125\.88\.252\.215'/);
  assert.doesNotMatch(vpnConfig, /'125\.88\.252\.217'/);
  assert.doesNotMatch(vpnConfig, /'125\.88\.252\.219'/);
  assert.doesNotMatch(vpnConfig, /'125\.88\.252\.221'/);
  assert.doesNotMatch(vpnConfig, /'125\.88\.252\.223'/);
  assert.doesNotMatch(vpnConfig, /'121\.36\.118\.233'/);
  assert.doesNotMatch(vpnConfig, /'49\.4\.33\.161'/);
  assert.doesNotMatch(vpnConfig, /'119\.147\.50\.77'/);
  assert.doesNotMatch(vpnConfig, /'119\.147\.50\.80'/);
  assert.doesNotMatch(vpnConfig, /'183\.61\.178\.94'/);
  assert.doesNotMatch(vpnConfig, /'183\.61\.178\.95'/);
  assert.doesNotMatch(vpnConfig, /'183\.61\.178\.96'/);
});

test('OHOS VPN ability uses the verified public VPN connection mode', () => {
  assert.match(vpnAbility, /isInternal:\s*false/);
});

test('OHOS VPN ability drains detached core events inside the extension process', () => {
  assert.match(vpnAbility, /consumeCoreEvents\(\):\s*string;/);
  assert.match(vpnAbility, /nativeBridge\.consumeCoreEvents\(\);/);
});

test('OHOS VPN ability preserves concrete error messages in status file and logs', () => {
  assert.match(vpnAbility, /import \{ stringifyError \} from '\.\.\/plugins\/error_utils';/);
  assert.match(vpnAbility, /const errorMessage = stringifyError\(error\);/);
  assert.match(
    vpnAbility,
    /`failed:\$\{errorMessage\}\$\{cleanupErrors\.length > 0 \? ` \| \$\{cleanupErrors\.join\(' \| '\)\}` : ''\}`/,
  );
  assert.doesNotMatch(vpnAbility, /failed:\$\{JSON\.stringify\(error\)/);
});

test('OHOS VPN ability cleans up native tun/core state when startup fails after partial initialization', () => {
  assert.match(
    vpnAbility,
    /let tunStarted = false;/,
  );
  assert.match(
    vpnAbility,
    /const started = nativeBridge\.startTun\([\s\S]*if \(!started\) \{[\s\S]*throw new Error\(`startTun failed: \$\{nativeBridge\.lastError\(\)\}`\);[\s\S]*\}[\s\S]*tunStarted = true;/m,
  );
  assert.match(
    vpnAbility,
    /catch \(error\) \{[\s\S]*if \(tunStarted\) \{[\s\S]*nativeBridge\.stopTun\(\);[\s\S]*nativeBridge\.stopTrackedCore\(\);[\s\S]*\}[\s\S]*try \{[\s\S]*await this\.vpnConnection\?\.destroy\(\);/m,
  );
});

test('OHOS VPN ability treats UI core link failure as startup failure instead of soft-warning success', () => {
  assert.match(
    vpnAbility,
    /if \(coreSocketPath\.length > 0\) \{[\s\S]*const linked = nativeBridge\.startEmbeddedCore\([\s\S]*if \(linked <= 0\) \{[\s\S]*throw new Error\(\s*`startEmbeddedCore failed: \$\{nativeBridge\.lastError\(\)\}`,\s*\);[\s\S]*\}[\s\S]*console\.info\(/m,
  );
  assert.match(
    vpnAbility,
    /if \(coreSocketPath\.length > 0\) \{[\s\S]*catch \(error\) \{[\s\S]*throw new Error\(\s*`core UI link failed: \$\{stringifyError\(error\)\}`,\s*\);[\s\S]*\}[\s\S]*\}/m,
  );
  assert.doesNotMatch(
    vpnAbility,
    /if \(coreSocketPath\.length > 0\) \{[\s\S]*catch \(error\) \{[\s\S]*console\.warn\(\s*`\[FlClashVpnAbility\] core UI link failed: \$\{stringifyError\(error\)\}`,\s*\);[\s\S]*\}[\s\S]*writeVpnStatus\(this\.context\.filesDir, 'started'\);/m,
  );
});
