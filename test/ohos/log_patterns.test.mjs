import test from 'node:test';
import assert from 'node:assert/strict';
import {
  STARTUP_LOG_TERMS,
  BROWSER_FLOW_LOG_TERMS,
  CHROME_FLOW_LOG_TERMS,
  getOhosLogPattern,
  getOhosShellSafeLogPattern,
} from '../../scripts/ohos/log_patterns.mjs';
import fs from 'node:fs';

const harmonyosDoc = fs.readFileSync(
  new URL('../../docs/harmonyos.md', import.meta.url),
  'utf8',
);
const mate80Plan = fs.readFileSync(
  new URL('../../docs/testing/mate80-pro-acceptance-test-plan.md', import.meta.url),
  'utf8',
);
const ohosHandoff = fs.readFileSync(
  new URL('../../docs/ohos-handoff.md', import.meta.url),
  'utf8',
);
const verifyCompatVpnScript = fs.readFileSync(
  new URL('../../scripts/ohos/verify_compat_vpn.sh', import.meta.url),
  'utf8',
);
const verifyAllScript = fs.readFileSync(
  new URL('../../scripts/ohos/verify_all.sh', import.meta.url),
  'utf8',
);
const verifyCapabilitiesScript = fs.readFileSync(
  new URL('../../scripts/ohos/verify_capabilities.sh', import.meta.url),
  'utf8',
);
const verifyBrowserVpnScript = fs.readFileSync(
  new URL('../../scripts/ohos/verify_browser_vpn.sh', import.meta.url),
  'utf8',
);
const verifyChromeVpnScript = fs.readFileSync(
  new URL('../../scripts/ohos/verify_chrome_vpn.sh', import.meta.url),
  'utf8',
);

test('startup OHOS log pattern covers DNS hijack bind diagnostics', () => {
  const pattern = new RegExp(getOhosLogPattern('startup'));
  const requiredTerms = [
    'TUN start request',
    'TUN options',
    'dns hijack targets=',
    'applyConfig dns listen=',
    'dnsHijack=',
    'any:53',
    '0.0.0.0:53',
    'permission deny',
    'permission denied',
    'listen udp',
    'listen tcp',
    'bind',
  ];

  for (const term of requiredTerms) {
    assert.equal(
      STARTUP_LOG_TERMS.includes(term),
      true,
      `missing startup diagnostic term: ${term}`,
    );
    assert.match(term, pattern);
  }
});

test('browser and chrome flow patterns retain all startup diagnostics', () => {
  for (const term of STARTUP_LOG_TERMS) {
    assert.equal(
      BROWSER_FLOW_LOG_TERMS.includes(term),
      true,
      `browser flow pattern dropped startup term: ${term}`,
    );
    assert.equal(
      CHROME_FLOW_LOG_TERMS.includes(term),
      true,
      `chrome flow pattern dropped startup term: ${term}`,
    );
  }
});

test('unknown OHOS log pattern names fail fast', () => {
  assert.throws(() => getOhosLogPattern('unknown'), /unknown log pattern/i);
});

test('shell-safe OHOS log patterns contain no raw single quotes', () => {
  assert.equal(getOhosShellSafeLogPattern('startup').includes("'"), false);
  assert.equal(getOhosShellSafeLogPattern('browser').includes("'"), false);
  assert.equal(getOhosShellSafeLogPattern('chrome').includes("'"), false);
});

test('OHOS docs and acceptance plan do not rely on the old vpn extension not ready log string', () => {
  assert.doesNotMatch(
    harmonyosDoc,
    /\[AppPlugin\] startVpn failed error=vpn extension not ready/,
  );
  assert.doesNotMatch(
    mate80Plan,
    /\[AppPlugin\] startVpn failed error=vpn extension not ready/,
  );
  assert.doesNotMatch(
    ohosHandoff,
    /\[AppPlugin\] startVpn failed error=vpn extension not ready/,
  );
});

test('verify_compat_vpn usage defaults stay aligned with the actual script constants', () => {
  assert.match(verifyCompatVpnScript, /DEFAULT_VPN_START_WAIT=15/);
  assert.match(verifyCompatVpnScript, /DEFAULT_TARGET_LAUNCH_WAIT=20/);
  assert.match(verifyCompatVpnScript, /DEFAULT_TARGET_SETTLE_WAIT=15/);
  assert.match(
    verifyCompatVpnScript,
    /VPN_START_WAIT\s+Seconds to wait after tapping start VPN\. Default: 15/,
  );
  assert.match(
    verifyCompatVpnScript,
    /TARGET_LAUNCH_WAIT\s+Seconds to wait after launching target app\. Default: 20/,
  );
  assert.match(
    verifyCompatVpnScript,
    /TARGET_SETTLE_WAIT\s+Extra seconds before a delayed second counter sample\. Default: 15/,
  );
  assert.match(
    verifyCompatVpnScript,
    /SHELL_ASSISTANT_BUNDLE\s+Override compat host bundle\. Default: com\.huawei\.shell_assistant/,
  );
  assert.match(
    verifyCompatVpnScript,
    /What this verifies:\s+1\.\s+Force-stop FlClash, the target app, and the configured compat host bundle\./,
  );
});

test('verify_all does not silently pick the first HarmonyOS target when multiple devices are connected', () => {
  assert.doesNotMatch(
    verifyAllScript,
    /list targets 2>\/dev\/null \| grep -v '\\\[Empty\\\]' \| head -1/,
  );
  assert.match(verifyAllScript, /Multiple HarmonyOS targets detected/);
  assert.match(verifyAllScript, /HDC_TARGET explicitly/);
});

test('verify_capabilities help and live collector stay aligned with the current VPN start semantics', () => {
  assert.match(
    verifyCapabilitiesScript,
    /startVpnExtensionAbility timeout with no later started marker/,
  );
  assert.match(
    verifyCapabilitiesScript,
    /failed:\* final VPN status \/ explicit start failure marker/,
  );
  assert.doesNotMatch(
    verifyCapabilitiesScript,
    /\[FlClashVpnAbility\] started fd=.*\\\[AppPlugin\\\] startVpn stack=/,
  );
  assert.doesNotMatch(
    verifyCapabilitiesScript,
    /\[AppPlugin\] startVpn stack=/,
  );
});

test('browser and chrome VPN scripts keep filtered hilog capture non-fatal when no lines match', () => {
  assert.match(
    verifyBrowserVpnScript,
    /hilog -x \| grep -E '\$startup_log_pattern' \| tail -n 320 \|\| true/,
  );
  assert.match(
    verifyBrowserVpnScript,
    /hilog -x \| grep -E '\$browser_log_pattern' \| tail -n 520 \|\| true/,
  );
  assert.match(
    verifyChromeVpnScript,
    /hilog -x \| grep -E '\$startup_log_pattern' \| tail -n 320 \|\| true/,
  );
  assert.match(
    verifyChromeVpnScript,
    /hilog -x \| grep -E '\$chrome_log_pattern' \| tail -n 320 \|\| true/,
  );
  assert.match(
    verifyChromeVpnScript,
    /aa dump -a \| grep -n -A8 -B2 '\$chrome_bundle_pattern\|\$shell_assistant_bundle_pattern' \|\| true/,
  );
  assert.match(
    verifyCompatVpnScript,
    /aa dump -a \| grep -n -A8 -B2 '\$mission_grep_pattern\|\$shell_assistant_bundle_pattern' \|\| true/,
  );
  assert.match(
    verifyCompatVpnScript,
    /hilog -x \| grep -E '\$compat_log_pattern' \| tail -n 160 \|\| true/,
  );
});

test('browser VPN script uses the configurable browser host bundle instead of hard-coded shell assistant markers', () => {
  assert.match(verifyBrowserVpnScript, /DEFAULT_SHELL_ASSISTANT_BUNDLE="com\.huawei\.shell_assistant"/);
  assert.match(
    verifyBrowserVpnScript,
    /SHELL_ASSISTANT_BUNDLE Override browser host bundle\. Default: com\.huawei\.shell_assistant/,
  );
  assert.match(
    verifyBrowserVpnScript,
    /local shell_assistant_bundle="\$\{SHELL_ASSISTANT_BUNDLE:-\$DEFAULT_SHELL_ASSISTANT_BUNDLE\}"/,
  );
  assert.match(
    verifyBrowserVpnScript,
    /aa force-stop \$shell_assistant_bundle .* bm clean -n \$shell_assistant_bundle -c/,
  );
  assert.match(
    verifyBrowserVpnScript,
    /grep -E '\$browser_bundle_pattern\|com\\\.huawei\\\.hmos\\\.aidispatchservice\|\$shell_assistant_bundle_pattern' \|\| true/,
  );
});

test('browser and chrome VPN scripts derive fallback probes from the configured URI instead of only hard-coded YouTube markers', () => {
  assert.match(
    verifyBrowserVpnScript,
    /browser_uri_host=\$\(resolve_uri_host "\$browser_uri"\)/,
  );
  assert.match(
    verifyBrowserVpnScript,
    /try_tap_browser_target "\$target" "\$browser_uri_probe" contains/,
  );
  assert.match(
    verifyBrowserVpnScript,
    /find-text "\$browser_uri_host" contains \|\| true/,
  );
  assert.match(
    verifyChromeVpnScript,
    /chrome_uri_host=\$\(resolve_uri_host "\$chrome_uri"\)/,
  );
  assert.match(
    verifyChromeVpnScript,
    /try_tap_chrome_target "\$target" "\$chrome_uri_probe" contains/,
  );
  assert.match(
    verifyChromeVpnScript,
    /try_tap_chrome_target "\$target" "\$chrome_uri_host" contains/,
  );
  assert.match(
    verifyChromeVpnScript,
    /Trigger Chrome page traffic using the configured URI host, with YouTube-only fallbacks kept for the default target family\./,
  );
  assert.match(
    verifyChromeVpnScript,
    /6\.\s+Capture vpn-tun counters plus mission\/log evidence for the current Chrome host-bundle path\./,
  );
  assert.doesNotMatch(
    verifyChromeVpnScript,
    /5\.\s+Capture vpn-tun counters plus mission\/log evidence for the Chrome \+ shell-assistant compat path\./,
  );
});

test('browser and chrome VPN scripts escape configurable regex fragments before feeding them into grep-based evidence capture', () => {
  assert.equal(verifyBrowserVpnScript.includes('escape_ere() {'), true);
  assert.equal(
    verifyBrowserVpnScript.includes(`sed -e 's/[][(){}.^$+*?|\\\\]/\\\\&/g'`),
    true,
  );
  assert.match(verifyBrowserVpnScript, /browser_log_pattern="\$\{browser_log_pattern\}\|\$\{browser_bundle_pattern\}\|\$\{shell_assistant_bundle_pattern\}"/);
  assert.match(verifyBrowserVpnScript, /grep -E '\$browser_bundle_pattern\|com\\\.huawei\\\.hmos\\\.aidispatchservice\|\$shell_assistant_bundle_pattern' \|\| true/);
  assert.match(verifyChromeVpnScript, /chrome_log_pattern="\$\{chrome_log_pattern\}\|\$\{chrome_bundle_pattern\}\|\$\{shell_assistant_bundle_pattern\}"/);
  assert.match(verifyChromeVpnScript, /grep -n -A8 -B2 '\$chrome_bundle_pattern\|\$shell_assistant_bundle_pattern' \|\| true/);
  assert.equal(verifyCompatVpnScript.includes('escape_ere() {'), true);
  assert.equal(verifyCompatVpnScript.includes('escape_ere_union() {'), true);
  assert.match(
    verifyCompatVpnScript,
    /local shell_assistant_bundle="\$\{SHELL_ASSISTANT_BUNDLE:-\$DEFAULT_SHELL_ASSISTANT_BUNDLE\}"/,
  );
  assert.match(
    verifyCompatVpnScript,
    /mission_grep_pattern=\$\(escape_ere_union "\$mission_grep"\)/,
  );
  assert.match(
    verifyCompatVpnScript,
    /shell_assistant_bundle_pattern=\$\(escape_ere "\$shell_assistant_bundle"\)/,
  );
  assert.match(
    verifyCompatVpnScript,
    /compat_log_pattern="app: \$\{shell_assistant_bundle_pattern\} success\|responseCode=200\|statusCode: 200\|dnsFromNetsys\|dnsServerReturnNothing\|Couldn.t resolve host name\|StartTun result ok=1\|OHOSVPN\|ProcUpdateVpnRoutePolicy"/,
  );
  assert.match(
    verifyCompatVpnScript,
    /aa force-stop \$shell_assistant_bundle .* hilog -r/,
  );
  assert.match(
    verifyCompatVpnScript,
    /grep -n -A8 -B2 '\$mission_grep_pattern\|\$shell_assistant_bundle_pattern' \|\| true/,
  );
});
