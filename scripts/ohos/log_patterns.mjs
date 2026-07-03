const STARTUP_LOG_TERMS = [
  'FlClashVpnAbility',
  'FlClashEntry',
  'FlClashCore',
  '[OHOS-CORE]',
  '[OHOS-CORE-LOG]',
  'StartTun result ok=0',
  'StartTun result ok=1',
  'TUN start request',
  'TUN options',
  'dns hijack targets=',
  'protect fd=',
  'NetworkVpnManager',
  'UpdateOutputInterfaceRulesWithUid',
  'ProcUpdateVpnRoutePolicy',
  'uids.size',
  'Add uids size',
  'IsGlobalVpn',
  '[profile-config]',
  '[setup-profile]',
  '[BOOT] initOhosPaths',
  'handleGetConfig path=',
  'applyConfig input path=',
  'applyConfig rawInteresting',
  'applyConfig dns listen=',
  'dnsHijack=',
  'any:53',
  '0.0.0.0:53',
  '0.0.0.0:1053',
  'permission deny',
  'permission denied',
  'listen udp',
  'listen tcp',
  'bind',
  'address already in use',
];

const BROWSER_FLOW_LOG_TERMS = [
  ...STARTUP_LOG_TERMS,
  'RequestFromHttpDns',
  'AwcExtensionAbility',
  'AwcServiceExtAbility',
  'HWBR-0-arkweb_mainprocess',
  'NK_CPP',
  'dnsServerReturnNothing',
  'dnsFromNetsys',
  "Couldn't resolve host name",
  'browsercfg-drcn.cloud.dbankcloud.cn',
  'httpdns.platform.dbankcloud.com',
  'httpdns-browser.platform.dbankcloud.cn',
  'www.youtube.com',
  'youtube',
  'com.follow.clash:vpn',
  'app: com.huawei.hmos.browser success',
  'app: com.huawei.hmos.arkwebcore success',
  'app: com.huawei.hmos.arkwebcorelegacy success',
  'app: com.huawei.hmos.aidispatchservice success',
  'applyConfig rule[',
];

const CHROME_FLOW_LOG_TERMS = [
  ...STARTUP_LOG_TERMS,
  'OHOSVPN',
  'com.android.chrome',
  'com.huawei.shell_assistant',
  'RequestFromHttpDns',
  'Cronet',
  'youtube',
  'statusCode: 200',
  'responseCode=200',
  'dnsFromNetsys',
  'dnsServerReturnNothing',
  "Couldn't resolve host name",
  'OnRequestSceneSession',
  'startSceneFromIcon',
  'Start new application item',
];

const LOG_PATTERNS = {
  startup: STARTUP_LOG_TERMS,
  browser: BROWSER_FLOW_LOG_TERMS,
  chrome: CHROME_FLOW_LOG_TERMS,
};

function escapeRegex(term) {
  return term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function getOhosLogPattern(name) {
  const terms = LOG_PATTERNS[name];
  if (!terms) {
    throw new Error(`unknown log pattern: ${name}`);
  }
  return terms.map(escapeRegex).join('|');
}

function getOhosShellSafeLogPattern(name) {
  return getOhosLogPattern(name).replaceAll("'", '.');
}

export {
  STARTUP_LOG_TERMS,
  BROWSER_FLOW_LOG_TERMS,
  CHROME_FLOW_LOG_TERMS,
  getOhosLogPattern,
  getOhosShellSafeLogPattern,
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const name = process.argv[2];
  if (!name) {
    console.error('usage: node scripts/ohos/log_patterns.mjs <startup|browser|chrome>');
    process.exit(1);
  }
  console.log(getOhosShellSafeLogPattern(name));
}
