// startWebview cancels the timers of the webview before it: its modules are bound to globals,
// so a leftover timer (trailing scroll post, TOC animation) would fire into the next test's mock.
import { test } from 'node:test';
import assert from 'node:assert';
import { setTimeout as sleep } from 'node:timers/promises';
import { startWebview } from './webview-dom.ts';

test('a timer of the previous webview does not fire into the next one', async () => {
  await startWebview();
  let fired = 0;
  globalThis.setTimeout(() => {
    fired++;
  }, 20);
  await startWebview();
  await sleep(60);
  assert.strictEqual(fired, 0, 'the old webview timer was cancelled');
});

test('a timer started after startWebview still fires', async () => {
  await startWebview();
  let fired = 0;
  globalThis.setTimeout(() => {
    fired++;
  }, 10);
  await sleep(60);
  assert.strictEqual(fired, 1);
});
