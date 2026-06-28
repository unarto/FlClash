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

test('OHOS VPN trusts the browser host apps while still blocking the FlClash app itself', () => {
  assert.match(vpnConfig, /trustedApplications:\s*OHOS_VPN_TRUSTED_APPLICATIONS/);
  assert.match(vpnConfig, /blockedApplications:\s*\[bundleName\]/);
  assert.match(vpnConfig, /'com\.huawei\.shell_assistant'/);
  assert.match(vpnConfig, /'com\.huawei\.hmos\.browser'/);
  assert.match(vpnConfig, /'com\.huawei\.hmos\.arkwebcore'/);
  assert.match(vpnConfig, /'com\.huawei\.hmos\.arkwebcorelegacy'/);
  assert.match(vpnConfig, /'com\.huawei\.hmos\.aidispatchservice'/);
});

test('OHOS VPN still blocks the FlClash app itself from the VPN network', () => {
  assert.match(vpnConfig, /blockedApplications:\s*\[bundleName\]/);
});

test('OHOS VPN only excludes the minimal Huawei bootstrap anycast IPs', () => {
  assert.match(vpnConfig, /'139\.9\.98\.98'/);
  assert.match(vpnConfig, /'139\.9\.99\.99'/);
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

test('OHOS VPN ability keeps the built-in VPN mode enabled', () => {
  assert.match(vpnAbility, /isInternal:\s*true/);
});

test('OHOS VPN ability drains detached core events inside the extension process', () => {
  assert.match(vpnAbility, /consumeCoreEvents\(\):\s*string;/);
  assert.match(vpnAbility, /nativeBridge\.consumeCoreEvents\(\);/);
});
