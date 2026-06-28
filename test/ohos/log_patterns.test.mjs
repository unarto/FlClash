import test from 'node:test';
import assert from 'node:assert/strict';
import {
  STARTUP_LOG_TERMS,
  BROWSER_FLOW_LOG_TERMS,
  CHROME_FLOW_LOG_TERMS,
  getOhosLogPattern,
  getOhosShellSafeLogPattern,
} from '../../scripts/ohos/log_patterns.mjs';

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
