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

// The fractional source line the webview reports for a scroll position.
async function reportedLine(
  entries: Parameters<typeof seedLineEntries>[1],
  scrollY: number,
): Promise<unknown> {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  await seedLineEntries(r, entries);
  r.window.scrollY = scrollY;
  scroll(r);
  const msg = r.state.posted.at(-1);
  return msg?.type === 'scrolled' ? msg.line : undefined;
}

test('the reported line interpolates between two [data-line] elements', async () => {
  // line 10 at top 0, line 20 at top 200: 100px down is halfway -> line 15.
  assert.strictEqual(
    await reportedLine(
      [
        { line: 10, top: 0, height: 100 },
        { line: 20, top: 200 },
      ],
      100,
    ),
    15,
  );
});

test('inside a multi-line block the reported line runs through its data-line-end', async () => {
  // A fence from line 10 to 20, 400px tall: 200px into it is line 15.
  assert.strictEqual(
    await reportedLine([{ line: 10, endLine: 20, top: 0, height: 400 }], 200),
    15,
  );
});

test('scroll events within 200 ms of a host scrollTo are not reported back (echo)', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  await seedLineEntries(r, [
    { line: 0, top: 0 },
    { line: 100, top: 4000 },
  ]);
  const scrolled = () =>
    r.state.posted.filter((m) => m.type === 'scrolled').length;
  const realNow = Date.now;
  const t0 = realNow();
  try {
    Date.now = () => t0;
    r.send({ type: 'scrollTo', line: 50 }); // the host scrolled us
    r.window.scrollY = 2000;
    scroll(r); // our own echo
    assert.strictEqual(scrolled(), 0, 'the echo is suppressed');
    Date.now = () => t0 + 250;
    r.window.scrollY = 2400;
    scroll(r); // a real scroll after the window
    assert.strictEqual(scrolled(), 1, 'reported again after 200 ms');
  } finally {
    Date.now = realNow;
  }
});

test('a burst of scroll events schedules one animation frame', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    raf: 'manual',
  });
  r.flushFrames(); // whatever the load queued
  for (const y of [100, 200, 300]) {
    r.window.scrollY = y;
    scroll(r);
  }
  assert.strictEqual(r.flushFrames(), 1, 'one frame for the burst');
  scroll(r);
  assert.strictEqual(
    r.flushFrames(),
    1,
    'the next event after the frame gets its own',
  );
});

test('a deferred scroll post delivers the rest position once the window passes', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  await seedLineEntries(r, [
    { line: 0, top: 0 },
    { line: 100, top: 4000 },
  ]);
  const lines = () =>
    r.state.posted.flatMap((m) => (m.type === 'scrolled' ? [m.line] : []));
  r.window.scrollY = 400;
  scroll(r); // posts at once (line 10)
  r.window.scrollY = 800;
  scroll(r); // within ~33 ms: deferred
  r.window.scrollY = 1200;
  scroll(r); // still deferred: the trailing post takes the latest position
  assert.deepStrictEqual(lines(), [10]);
  await new Promise((resolve) => setTimeout(resolve, 80));
  assert.deepStrictEqual(
    lines(),
    [10, 30],
    'the rest position (line 30) arrives',
  );
});
