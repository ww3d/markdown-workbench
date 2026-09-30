// Webview -> host scroll reports: the scroll handler, the throttle decision and the
// delta gate (#44 review 5).
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  MM,
  px,
  scroll,
  seedLineEntries,
} from '../../helpers/webview-fixtures.ts';

test('scroll handler updates the minimap even while sync-suppressed (regression 0.18.0)', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
  });
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  r.send({ type: 'scrollTo', line: 0 }); // arms suppression
  r.window.scrollY = 4000;
  scroll(r);
  assert.strictEqual(px(byId(r, 'minimap-slider').style.top), 400);
});

test('scrollPostDecision: skip a sub-line change, post once the window elapsed, else defer', async () => {
  const r = await startWebview();
  const { scrollPostDecision } = await r.load('scroll-sync/report.ts');
  // Same line as last -> skip (delta gate).
  assert.strictEqual(scrollPostDecision(5.0, 5.0, 1000, 0, 33, 0.01), 'skip');
  // Meaningful change, window elapsed -> post.
  assert.strictEqual(scrollPostDecision(6.0, 5.0, 1000, 900, 33, 0.01), 'post');
  // Meaningful change, still within the window -> defer (trailing).
  assert.strictEqual(scrollPostDecision(6.0, 5.0, 910, 900, 33, 0.01), 'defer');
  // First post (lastLine -1) is never skipped.
  assert.strictEqual(scrollPostDecision(0, -1, 1000, 0, 33, 0.01), 'post');
});

test('the scrolled sync is delta-gated: repeated frames at the same line post once', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    scrollY: 300,
  });
  await seedLineEntries(r, [{ line: 5, top: 0, height: 1000 }]); // constant scrollY -> constant line
  const count = () =>
    r.state.posted.filter((m) => m.type === 'scrolled').length;
  for (let i = 0; i < 5; i++) scroll(r);
  assert.strictEqual(
    count(),
    1,
    'five frames at the same source line -> one message',
  );
});

test('a synchronous scroll burst coalesces to one immediate scrolled post', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  await seedLineEntries(r, [
    { line: 0, top: 0 },
    { line: 100, top: 4000 },
  ]);
  const count = () =>
    r.state.posted.filter((m) => m.type === 'scrolled').length;
  for (const y of [100, 200, 300, 400, 500, 600]) {
    r.window.scrollY = y;
    scroll(r);
  }
  assert.strictEqual(
    count(),
    1,
    'a same-window burst posts once (the rest are deferred/coalesced)',
  );
});
