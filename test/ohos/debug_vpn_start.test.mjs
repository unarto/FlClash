import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const globalStateSource = fs.readFileSync(
  new URL('../../lib/state.dart', import.meta.url),
  'utf8',
);
const appPluginSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/AppPlugin.ets', import.meta.url),
  'utf8',
);
const appDartSource = fs.readFileSync(
  new URL('../../lib/plugins/app.dart', import.meta.url),
  'utf8',
);

test('OHOS pending debug VPN start handles PlatformException locally', () => {
  assert.match(
    globalStateSource,
    /on PlatformException catch \(error\) \{\s*final message = formatOhosVpnStartError\(error\);[\s\S]*showNotifier\(message\);/m,
  );
});

test('OHOS pending debug VPN start only reports handled after a successful local status sync', () => {
  assert.match(
    globalStateSource,
    /\.prepareProfileConfigOnly\(force: true\);[\s\S]*if \(!prepared\) \{[\s\S]*const message = 'VPN 启动失败';[\s\S]*showNotifier\(message\);[\s\S]*return false;\s*\}/m,
  );
  assert.match(
    globalStateSource,
    /if \(started != true\) \{[\s\S]*showNotifier\(message\);[\s\S]*return false;\s*\}/m,
  );
  assert.match(
    globalStateSource,
    /Future<PendingDebugVpnStartFinalizationResult> finalizePendingDebugVpnStart\([\s\S]*await container\.read\(setupActionProvider\.notifier\)\.updateStatus\(\s*true,\s*isInit: true,\s*\);[\s\S]*final started = container\.read\(isStartProvider\);[\s\S]*if \(started\) \{[\s\S]*return \(finalized: true, failureMessage: null\);[\s\S]*\}[\s\S]*try \{[\s\S]*final stopped = await stopPendingDebugVpnAfterFailedInitStart\?\.call\(\);[\s\S]*return \([\s\S]*finalized: false,[\s\S]*failureMessage: stopped == true[\s\S]*\? 'VPN 启动失败'[\s\S]*: formatOhosPendingDebugVpnRollbackFailure\('VPN 停止失败'\),[\s\S]*\);[\s\S]*\} on PlatformException catch \(error\) \{/m,
  );
  assert.match(
    globalStateSource,
    /on PlatformException catch \(error\) \{[\s\S]*showNotifier\(message\);[\s\S]*return false;\s*\}/m,
  );
});

test('OHOS pending debug VPN start surfaces init-status finalization failures to the user', () => {
  assert.match(
    globalStateSource,
    /final finalizationResult = await finalizePendingDebugVpnStart\(container\);[\s\S]*if \(!finalizationResult\.finalized\) \{[\s\S]*final message = finalizationResult\.failureMessage \?\? 'VPN 启动失败';[\s\S]*showNotifier\(message\);[\s\S]*\}[\s\S]*return finalizationResult\.finalized;/m,
  );
});

test('OHOS pending debug VPN start distinguishes native rollback failures after local init failure', () => {
  assert.match(
    globalStateSource,
    /typedef PendingDebugVpnStartFinalizationResult =[\s\S]*\(\{bool finalized, String\? failureMessage\}\);/m,
  );
  assert.match(
    globalStateSource,
    /on PlatformException catch \(error\) \{[\s\S]*final stopFailureMessage = formatOhosVpnStopError\(error\);[\s\S]*commonPrint\.log\([\s\S]*return \([\s\S]*finalized: false,[\s\S]*failureMessage: formatOhosPendingDebugVpnRollbackFailure\([\s\S]*stopFailureMessage,[\s\S]*\),[\s\S]*\);[\s\S]*\}/m,
  );
});

test('OHOS pending debug VPN start forces local VPN enable before follow-up startup sync', () => {
  assert.match(
    globalStateSource,
    /void applyPendingDebugVpnStartSettings\([\s\S]*container[\s\S]*\.read\(vpnSettingProvider\.notifier\)[\s\S]*copyWith\(enable: true, ipv6: ipv6\)/m,
  );
  assert.match(
    globalStateSource,
    /applyPendingDebugVpnStartSettings\(\s*container,\s*stack: stack,\s*ipv6: ipv6,\s*\);[\s\S]*final prepared = await container[\s\S]*prepareProfileConfigOnly\(force: true\);/m,
  );
});

test('OHOS pending debug VPN start raises a guard while it owns native start handling', () => {
  assert.match(
    globalStateSource,
    /bool _isHandlingOhosPendingDebugVpnStart = false;/m,
  );
  assert.match(
    globalStateSource,
    /bool get isHandlingOhosPendingDebugVpnStart =>[\s\S]*_isHandlingOhosPendingDebugVpnStart;/m,
  );
  assert.match(
    globalStateSource,
    /_isHandlingOhosPendingDebugVpnStart = true;[\s\S]*try \{[\s\S]*applyPendingDebugVpnStartSettings\([\s\S]*\} finally \{[\s\S]*_isHandlingOhosPendingDebugVpnStart = false;[\s\S]*\}/m,
  );
});

test('OHOS AppPlugin re-delivers pending debug VPN start after a hot onNewWant while Flutter is attached', () => {
  assert.match(
    appPluginSource,
    /private static pendingDebugVpnStartListenerReady = false;/,
  );
  assert.match(
    appPluginSource,
    /private static deliverPendingDebugVpnStartIfReady\(\): void \{[\s\S]*if \(\s*AppPlugin\.pendingDebugVpnStarts\.length === 0\s*\|\|\s*!AppPlugin\.pendingDebugVpnStartListenerReady\s*\|\|\s*AppPlugin\.activeChannel == null\s*\|\|\s*AppPlugin\.pendingDebugVpnStartDeliveryInFlight\s*\) \{[\s\S]*return;[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = true;[\s\S]*AppPlugin\.activeChannel\.invokeMethod\(\s*'pendingDebugVpnStart',\s*\{\s*stack:\s*pendingDebugVpnStart\.stack,\s*ipv6:\s*pendingDebugVpnStart\.ipv6,\s*\},/m,
  );
  assert.match(
    appPluginSource,
    /static setPendingLinkFromWant\(want: Want \| undefined\): void \{[\s\S]*AppPlugin\.pendingDebugVpnStarts\.push\(pendingDebugVpnStart\);[\s\S]*AppPlugin\.deliverPendingDebugVpnStartIfReady\(\);/m,
  );
  assert.match(
    appPluginSource,
    /onAttachedToAbility\(binding: AbilityPluginBinding\): void \{[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);[\s\S]*AppPlugin\.deliverPendingDebugVpnStartIfReady\(\);[\s\S]*this\.tryStartPendingDebugVpn\(\);/m,
  );
  assert.match(
    appPluginSource,
    /case 'updatePendingDebugVpnStartListenerReady': \{[\s\S]*AppPlugin\.pendingDebugVpnStartListenerReady = call\.args === true;[\s\S]*if \(AppPlugin\.pendingDebugVpnStartListenerReady\) \{[\s\S]*AppPlugin\.deliverPendingDebugVpnStartIfReady\(\);[\s\S]*\}[\s\S]*result\.success\(true\);/m,
  );
});

test('OHOS AppPlugin queues multiple pending debug VPN start requests instead of overwriting them', () => {
  assert.match(
    appPluginSource,
    /private static pendingDebugVpnStarts: PendingDebugVpnStart\[\] = \[\];/,
  );
  assert.match(
    appPluginSource,
    /private static pendingDebugVpnStartDeliveryInFlight = false;/,
  );
  assert.match(
    appPluginSource,
    /private static pendingDebugVpnStartDeliveryId = 0;/,
  );
  assert.match(
    appPluginSource,
    /private static pendingDebugVpnStartInFlightValue: PendingDebugVpnStart \| null = null;/,
  );
  assert.match(
    appPluginSource,
    /const pendingDebugVpnStart = AppPlugin\.pendingDebugVpnStarts\[0\];[\s\S]*if \(pendingDebugVpnStart == null\) \{[\s\S]*return;/m,
  );
  assert.match(
    appPluginSource,
    /const deliveryId = AppPlugin\.pendingDebugVpnStartDeliveryId \+ 1;[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryId = deliveryId;[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = true;[\s\S]*AppPlugin\.pendingDebugVpnStartInFlightValue = pendingDebugVpnStart;/m,
  );
  assert.match(
    appPluginSource,
    /private consumePendingDebugVpnStart\(\): PendingDebugVpnStart \| null \{[\s\S]*const pending = AppPlugin\.pendingDebugVpnStarts\.shift\(\) \?\? null;[\s\S]*if \(AppPlugin\.pendingDebugVpnStarts\.length > 0\) \{[\s\S]*AppPlugin\.deliverPendingDebugVpnStartIfReady\(\);[\s\S]*\}[\s\S]*return pending;\s*\}/m,
  );
  assert.match(
    appPluginSource,
    /success:\s*\(\)\s*=>\s*\{[\s\S]*if \(AppPlugin\.pendingDebugVpnStartDeliveryId !== deliveryId\) \{[\s\S]*return;[\s\S]*\}[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingDebugVpnStartInFlightValue = null;[\s\S]*if \(\s*AppPlugin\.pendingDebugVpnStarts\.length > 0\s*&&\s*AppPlugin\.pendingDebugVpnStarts\[0\] === pendingDebugVpnStart\s*\) \{[\s\S]*AppPlugin\.pendingDebugVpnStarts\.shift\(\);[\s\S]*\}[\s\S]*if \(\s*AppPlugin\.pendingDebugVpnStarts\.length > 0\s*\) \{[\s\S]*AppPlugin\.deliverPendingDebugVpnStartIfReady\(\);/m,
  );
  assert.ok(
    appPluginSource.includes(
      `error: (code: string, message: string, details: Any) => {
        if (AppPlugin.pendingDebugVpnStartDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingDebugVpnStartDeliveryInFlight = false;
        AppPlugin.pendingDebugVpnStartInFlightValue = null;
        if (
          AppPlugin.pendingDebugVpnStarts.length > 0 &&
          AppPlugin.pendingDebugVpnStarts[0] !== pendingDebugVpnStart
        ) {
          AppPlugin.deliverPendingDebugVpnStartIfReady();
        }
        console.warn(`,
    ),
  );
  assert.ok(
    appPluginSource.includes(
      `notImplemented: () => {
        if (AppPlugin.pendingDebugVpnStartDeliveryId !== deliveryId) {
          return;
        }
        AppPlugin.pendingDebugVpnStartDeliveryInFlight = false;
        AppPlugin.pendingDebugVpnStartInFlightValue = null;
        if (
          AppPlugin.pendingDebugVpnStarts.length > 0 &&
          AppPlugin.pendingDebugVpnStarts[0] !== pendingDebugVpnStart
        ) {
          AppPlugin.deliverPendingDebugVpnStartIfReady();
        }
        console.warn('[AppPlugin] pendingDebugVpnStart delivery not implemented by Flutter');`,
    ),
  );
  assert.match(
    appPluginSource,
    /onDetachedFromAbility\(\): void \{[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingDebugVpnStartInFlightValue = null;[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryId \+= 1;/m,
  );
});

test('OHOS AppPlugin does not consume the same pending debug VPN start while native delivery is still in flight', () => {
  assert.match(
    appPluginSource,
    /const pendingDebugVpnStart = AppPlugin\.pendingDebugVpnStarts\[0\];[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = true;[\s\S]*AppPlugin\.pendingDebugVpnStartInFlightValue = pendingDebugVpnStart;/m,
  );
  assert.match(
    appPluginSource,
    /error:\s*\([^)]*\)\s*=>\s*\{[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingDebugVpnStartInFlightValue = null;/m,
  );
  assert.match(
    appPluginSource,
    /notImplemented:\s*\(\)\s*=>\s*\{[\s\S]*AppPlugin\.pendingDebugVpnStartDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingDebugVpnStartInFlightValue = null;/m,
  );
  assert.match(
    appPluginSource,
    /private consumePendingDebugVpnStart\(\): PendingDebugVpnStart \| null \{[\s\S]*if \(\s*AppPlugin\.pendingDebugVpnStartDeliveryInFlight\s*&&\s*AppPlugin\.pendingDebugVpnStartInFlightValue != null\s*&&\s*AppPlugin\.pendingDebugVpnStarts\[0\] === AppPlugin\.pendingDebugVpnStartInFlightValue\s*\) \{[\s\S]*return null;\s*\}[\s\S]*const pending = AppPlugin\.pendingDebugVpnStarts\.shift\(\) \?\? null;/m,
  );
});

test('Flutter App bridge exposes pendingDebugVpnStart callbacks from OHOS method channel', () => {
  assert.match(
    appDartSource,
    /Future<void> Function\(Map<String, dynamic>\?\)\? onPendingDebugVpnStart;/,
  );
  assert.match(
    appDartSource,
    /Future<bool\?> updatePendingDebugVpnStartListenerReady\(bool value\) \{[\s\S]*return methodChannel\.invokeMethod<bool>\([\s\S]*'updatePendingDebugVpnStartListenerReady',[\s\S]*value,[\s\S]*\);/m,
  );
  assert.match(
    appDartSource,
    /case 'pendingDebugVpnStart':[\s\S]*final pending = call\.arguments == null[\s\S]*Map<String, dynamic>\.from\(call\.arguments as Map\);[\s\S]*if \(onPendingDebugVpnStart != null\) \{[\s\S]*await onPendingDebugVpnStart!\(pending\);[\s\S]*return;[\s\S]*\}/m,
  );
});

test('OHOS hot pending debug VPN callback does not race bootstrap consumption before init is complete', () => {
  assert.match(
    globalStateSource,
    /bool _ohosPendingDebugVpnStartReady = false;/,
  );
  assert.match(
    globalStateSource,
    /await app\?\.updatePendingDebugVpnStartListenerReady\(false\);[\s\S]*app\?\.onPendingDebugVpnStart = \(pending\) async \{[\s\S]*if \(!_ohosPendingDebugVpnStartReady\) \{[\s\S]*throw MissingPluginException\(\);/m,
  );
  assert.match(
    globalStateSource,
    /if \(!_ohosPendingDebugVpnStartReady\) \{[\s\S]*throw MissingPluginException\(\);/m,
  );
  assert.match(
    globalStateSource,
    /final handledPendingDebugVpn = await _handlePendingDebugVpnStart\(\);/m,
  );
  assert.match(
    globalStateSource,
    /await container\s*\.read\(setupActionProvider\.notifier\)\s*\.initStatus\(\);[\s\S]*_ohosPendingDebugVpnStartReady = true;/m,
  );
  assert.match(
    globalStateSource,
    /_ohosPendingDebugVpnStartReady = true;[\s\S]*await app\?\.updatePendingDebugVpnStartListenerReady\(true\);/m,
  );
  assert.match(
    globalStateSource,
    /final currentPendingDebugVpnStart = _pendingOhosDebugVpnStart\.then\(\(_\) async \{[\s\S]*await _handlePendingDebugVpnStart\(pending\);/m,
  );
});

test('OHOS startup keeps native pending debug VPN queue authoritative until listener-ready delivery begins', () => {
  assert.doesNotMatch(
    globalStateSource,
    /_deferredOhosPendingDebugVpnStarts/,
  );
  assert.match(
    globalStateSource,
    /if \(!_ohosPendingDebugVpnStartReady\) \{[\s\S]*throw MissingPluginException\(\);/m,
  );
  assert.match(
    globalStateSource,
    /await app\?\.updatePendingDebugVpnStartListenerReady\(true\);/m,
  );
  assert.doesNotMatch(
    globalStateSource,
    /while \(true\) \{[\s\S]*consumePendingDebugVpnStart\(\)/m,
  );
});

test('OHOS hot pending debug VPN callback does not swallow unexpected handler failures before native delivery resolves', () => {
  assert.match(
    globalStateSource,
    /final currentPendingDebugVpnStart = _pendingOhosDebugVpnStart\.then\(\(_\) async \{[\s\S]*await _handlePendingDebugVpnStart\(pending\);/m,
  );
  assert.match(
    globalStateSource,
    /_pendingOhosDebugVpnStart = currentPendingDebugVpnStart\.catchError\(\([\s\S]*Object error,[\s\S]*StackTrace stackTrace,[\s\S]*'\[OHOS-DEBUG-VPN\] hot pending start failed: \$error stack: \$stackTrace'/m,
  );
  assert.match(
    globalStateSource,
    /await currentPendingDebugVpnStart;/m,
  );
});

test('OHOS deferred pending debug VPN replay surfaces unexpected handler failures instead of silently swallowing them', () => {
  assert.doesNotMatch(
    globalStateSource,
    /replay deferred pending start handled=/,
  );
  assert.doesNotMatch(
    globalStateSource,
    /replay deferred pending start failed:/,
  );
  assert.doesNotMatch(
    globalStateSource,
    /await replayPendingDebugVpnStart/,
  );
});
