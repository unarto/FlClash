import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const appPluginSource = fs.readFileSync(
  new URL('../../ohos/entry/src/main/ets/plugins/AppPlugin.ets', import.meta.url),
  'utf8',
);

test('OHOS AppPlugin only clears pending deep links after channel delivery succeeds', () => {
  assert.match(
    appPluginSource,
    /private static pendingLinks: string\[\] = \[\];/,
  );
  assert.match(
    appPluginSource,
    /private static appLinkListenerReady = false;/,
  );
  assert.match(
    appPluginSource,
    /private static pendingLinkDeliveryInFlight = false;/,
  );
  assert.match(
    appPluginSource,
    /private static pendingLinkInFlightValue: string = '';/,
  );
  assert.match(
    appPluginSource,
    /private static pendingLinkDeliveryId = 0;/,
  );
  assert.match(
    appPluginSource,
    /private static deliverPendingLinkIfReady\(\): void \{[\s\S]*if \(\s*AppPlugin\.pendingLinks\.length === 0\s*\|\|\s*!AppPlugin\.appLinkListenerReady\s*\|\|\s*AppPlugin\.activeChannel == null\s*\|\|\s*AppPlugin\.pendingLinkDeliveryInFlight\s*\) \{[\s\S]*return;[\s\S]*const link = AppPlugin\.pendingLinks\[0\];[\s\S]*if \(link == null\) \{[\s\S]*return;[\s\S]*\}[\s\S]*const deliveryId = AppPlugin\.pendingLinkDeliveryId \+ 1;[\s\S]*AppPlugin\.pendingLinkDeliveryId = deliveryId;[\s\S]*AppPlugin\.pendingLinkDeliveryInFlight = true;[\s\S]*AppPlugin\.pendingLinkInFlightValue = link;[\s\S]*AppPlugin\.activeChannel\.invokeMethod\(\s*'appLink',\s*link,\s*\{[\s\S]*success:\s*\(\)\s*=>\s*\{[\s\S]*if \(AppPlugin\.pendingLinkDeliveryId !== deliveryId\) \{[\s\S]*return;[\s\S]*\}[\s\S]*AppPlugin\.pendingLinkDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingLinkInFlightValue = '';[\s\S]*if \(AppPlugin\.pendingLinks.length > 0 && AppPlugin\.pendingLinks\[0\] === link\) \{[\s\S]*AppPlugin\.pendingLinks\.shift\(\);[\s\S]*\}[\s\S]*if \(AppPlugin\.pendingLinks.length > 0\) \{[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);/m,
  );
  assert.match(
    appPluginSource,
    /error:\s*\([^)]*\)\s*=>\s*\{[\s\S]*if \(AppPlugin\.pendingLinkDeliveryId !== deliveryId\) \{[\s\S]*return;[\s\S]*\}[\s\S]*AppPlugin\.pendingLinkDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingLinkInFlightValue = '';[\s\S]*if \(\s*AppPlugin\.pendingLinks\.length > 0\s*&&\s*AppPlugin\.pendingLinks\[0\] !== link\s*\) \{[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);[\s\S]*\}[\s\S]*console\.(warn|error)\(/m,
  );
  assert.match(
    appPluginSource,
    /notImplemented:\s*\(\)\s*=>\s*\{[\s\S]*if \(AppPlugin\.pendingLinkDeliveryId !== deliveryId\) \{[\s\S]*return;[\s\S]*\}[\s\S]*AppPlugin\.pendingLinkDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingLinkInFlightValue = '';[\s\S]*if \(\s*AppPlugin\.pendingLinks\.length > 0\s*&&\s*AppPlugin\.pendingLinks\[0\] !== link\s*\) \{[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);[\s\S]*\}[\s\S]*console\.warn\(/m,
  );
});

test('OHOS AppPlugin re-delivers a pending deep link when the ability channel reattaches', () => {
  assert.match(
    appPluginSource,
    /private static deliverPendingLinkIfReady\(\): void \{[\s\S]*if \(\s*AppPlugin\.pendingLinks\.length === 0\s*\|\|\s*!AppPlugin\.appLinkListenerReady\s*\|\|\s*AppPlugin\.activeChannel == null\s*\|\|\s*AppPlugin\.pendingLinkDeliveryInFlight\s*\) \{[\s\S]*return;[\s\S]*const link = AppPlugin\.pendingLinks\[0\];[\s\S]*AppPlugin\.activeChannel\.invokeMethod\(\s*'appLink',\s*link,/m,
  );
  assert.match(
    appPluginSource,
    /static setPendingLink\(link: string\): void \{[\s\S]*AppPlugin\.pendingLinks\.push\(link\);[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);[\s\S]*\}/m,
  );
  assert.match(
    appPluginSource,
    /onAttachedToAbility\(binding: AbilityPluginBinding\): void \{[\s\S]*AppPlugin\.activeChannel = this\.channel;[\s\S]*this\.channel\.setMethodCallHandler\(this\);[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);/m,
  );
  assert.match(
    appPluginSource,
    /onDetachedFromAbility\(\): void \{[\s\S]*AppPlugin\.pendingLinkDeliveryInFlight = false;[\s\S]*AppPlugin\.pendingLinkInFlightValue = '';[\s\S]*AppPlugin\.pendingLinkDeliveryId \+= 1;/m,
  );
});

test('OHOS AppPlugin only auto-delivers app links after Flutter marks the listener ready', () => {
  assert.match(
    appPluginSource,
    /case 'updateAppLinkListenerReady': \{[\s\S]*AppPlugin\.appLinkListenerReady = call\.args === true;[\s\S]*if \(AppPlugin\.appLinkListenerReady\) \{[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);[\s\S]*\}[\s\S]*result\.success\(true\);/m,
  );
});

test('OHOS AppPlugin queues multiple pending deep links instead of overwriting them', () => {
  assert.match(
    appPluginSource,
    /private static pendingLinks: string\[\] = \[\];/,
  );
  assert.match(
    appPluginSource,
    /private static pendingLinkDeliveryInFlight = false;/,
  );
  assert.match(
    appPluginSource,
    /static setPendingLink\(link: string\): void \{[\s\S]*AppPlugin\.pendingLinks\.push\(link\);/m,
  );
  assert.match(
    appPluginSource,
    /private consumePendingLink\(\): string \{[\s\S]*const link = AppPlugin\.pendingLinks\.shift\(\) \?\? '';/m,
  );
  assert.match(
    appPluginSource,
    /private consumePendingLink\(\): string \{[\s\S]*if \(\s*AppPlugin\.pendingLinkDeliveryInFlight\s*&&\s*AppPlugin\.pendingLinkInFlightValue\.length > 0\s*&&\s*AppPlugin\.pendingLinks\[0\] === AppPlugin\.pendingLinkInFlightValue\s*\) \{[\s\S]*return '';\s*\}[\s\S]*const link = AppPlugin\.pendingLinks\.shift\(\) \?\? ''[\s\S]*return link;\s*\}/m,
  );
  assert.doesNotMatch(
    appPluginSource,
    /private consumePendingLink\(\): string \{[\s\S]*AppPlugin\.deliverPendingLinkIfReady\(\);[\s\S]*return link;\s*\}/m,
  );
  assert.match(
    appPluginSource,
    /case 'consumePendingLink': \{[\s\S]*const link = this\.consumePendingLink\(\);[\s\S]*result\.success\(link\);/m,
  );
});
