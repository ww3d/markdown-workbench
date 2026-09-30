// What the webview persists (src/webview/restore/state.ts): the stand of the last render
// with its key, scroll line and build id, merged with the document URI; the HTML only up
// to the bound; one setState per quiet phase, none in a render or scroll frame.
import { test } from 'node:test';
import assert from 'node:assert';
import { setTimeout as sleep } from 'node:timers/promises';
import { startWebview } from '../../helpers/webview-dom.ts';
import type { Webview } from '../../helpers/webview-dom.ts';
import { TEST_BUILD_ID } from '../../helpers/build-id.ts';
import { byId, scroll, sendCfg } from '../../helpers/webview-fixtures.ts';

// The bounds, read from a webview's own module generation (the module needs the DOM mock).
const { MAX_RESTORE_HTML_CHARS, STATE_SAVE_QUIET_MS } = await (
  await startWebview()
).load('restore/state.ts');
const quiet = () => sleep(STATE_SAVE_QUIET_MS + 60);

// A webview that has rendered `html` with `key` and gone quiet.
async function rendered(html: string, key = 'k1'): Promise<Webview> {
  const r = await startWebview();
  r.send({ type: 'render', html, key, version: 3 });
  await quiet();
  return r;
}

test('after a render the webview persists html, key and build id once quiet (REQ-041)', async () => {
  const r = await rendered('<h1 id="a">A</h1>');
  assert.deepStrictEqual(r.state.savedState, {
    documentUri: undefined,
    buildId: TEST_BUILD_ID,
    key: 'k1',
    html: '<h1 id="a">A</h1>',
    scrollLine: undefined,
  });
});

test('html just below the bound is persisted', async () => {
  const html = 'x'.repeat(MAX_RESTORE_HTML_CHARS - 1);
  const r = await rendered(html);
  assert.strictEqual(r.state.savedState?.html, html);
  assert.strictEqual(r.state.savedState?.key, 'k1');
});

test('html of exactly the bound is persisted: the bound is inclusive (REQ-041)', async () => {
  const html = 'x'.repeat(MAX_RESTORE_HTML_CHARS);
  const r = await rendered(html);
  assert.strictEqual(r.state.savedState?.html, html);
});

test('the bound is 512 KiB, as documented', () => {
  assert.strictEqual(MAX_RESTORE_HTML_CHARS, 524_288);
});

test('html just above the bound is not persisted: build id and document URI only (REQ-042)', async () => {
  const r = await rendered('x'.repeat(MAX_RESTORE_HTML_CHARS + 1));
  assert.deepStrictEqual(r.state.savedState, {
    documentUri: undefined,
    buildId: TEST_BUILD_ID,
  });
});

test('a render without a key persists no stand', async () => {
  const r = await startWebview();
  r.send({ type: 'render', html: '<p>a</p>' });
  await quiet();
  assert.strictEqual(r.state.savedState?.html, undefined);
});

test('the document URI from config and the render stand are merged, neither overwrites the other', async () => {
  const r = await startWebview();
  sendCfg(r, { documentUri: 'file:///ws/doc.md' });
  r.send({ type: 'render', html: '<p>a</p>', key: 'k1' });
  await quiet();
  assert.strictEqual(r.state.savedState?.documentUri, 'file:///ws/doc.md');
  assert.strictEqual(r.state.savedState?.html, '<p>a</p>');
  sendCfg(r, { documentUri: 'file:///ws/doc.md', maxWidth: '72ch' });
  assert.strictEqual(
    r.state.savedState?.html,
    '<p>a</p>',
    'config keeps the stand',
  );
});

test('a render and scroll burst writes the state once per quiet phase, never in the frame', async (t) => {
  const r = await startWebview();
  // Mocked after the start: the webview's timers and clock run on the test's ticks.
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: Date.now() });
  const writes = () => r.state.stateWrites;
  for (let i = 0; i < 20; i++)
    r.send({ type: 'render', html: `<p>${i}</p>`, key: `k${i}` });
  for (let i = 0; i < 200; i++) scroll(r);
  assert.strictEqual(
    writes(),
    0,
    'no setState inside a render or scroll frame',
  );
  t.mock.timers.tick(STATE_SAVE_QUIET_MS / 2);
  scroll(r); // still active: the quiet time starts over
  t.mock.timers.tick(STATE_SAVE_QUIET_MS / 2 + 20);
  assert.strictEqual(writes(), 0, 'no write while the view is not quiet');
  t.mock.timers.tick(STATE_SAVE_QUIET_MS);
  assert.strictEqual(writes(), 1, 'one write for the whole burst');
  assert.strictEqual(r.state.savedState?.key, 'k19', 'the last render wins');
  scroll(r);
  t.mock.timers.tick(STATE_SAVE_QUIET_MS);
  assert.strictEqual(writes(), 2, 'the next quiet phase writes again');
});

test('the persisted scroll line is the fractional source line at the top', async () => {
  const r = await startWebview({ scrollY: 100 });
  const { seedLineEntries } = await import('../../helpers/webview-fixtures.ts');
  r.send({ type: 'render', html: '<p>a</p>', key: 'k1' });
  await seedLineEntries(r, [
    { line: 10, top: 0 },
    { line: 20, top: 200 },
  ]);
  scroll(r);
  await quiet();
  assert.strictEqual(r.state.savedState?.scrollLine, 15);
});

test('an identical html with a new key persists the new key', async () => {
  const r = await rendered('<p>a</p>', 'k1');
  r.send({ type: 'render', html: '<p>a</p>', key: 'k2' });
  await quiet();
  assert.strictEqual(r.state.savedState?.key, 'k2');
});

test('after a fold the persisted scroll line comes from the re-measured tops', async (t) => {
  // An idle callback that never runs: the fold's re-measure stays pending until flushed.
  const r = await startWebview({
    scrollY: 100,
    prepare: () => Reflect.set(globalThis, 'requestIdleCallback', () => 0),
  });
  t.after(() => Reflect.deleteProperty(globalThis, 'requestIdleCallback'));
  const tops: Record<number, number> = { 10: 0, 20: 200 };
  const els = [10, 20].map((line) => ({
    dataset: { line: String(line) },
    getBoundingClientRect: () => ({
      top: (tops[line] ?? 0) - r.window.scrollY,
      height: 20,
    }),
  }));
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === '[data-line]' ? els : [];
  r.send({ type: 'render', html: '<p>a</p>', key: 'k1' });
  tops[20] = 100; // a fold above line 20 moved it up
  (await r.load('folding/refresh.ts')).scheduleFoldRefresh();
  r.send({ type: 'render', html: '<p>a</p>', key: 'k1' }); // schedules the write only
  await quiet();
  assert.strictEqual(r.state.savedState?.scrollLine, 20);
});

test('a fractional line just before a first block at line 0 is persisted as 0', async () => {
  const r = await startWebview({ scrollY: 100 });
  const { seedLineEntries } = await import('../../helpers/webview-fixtures.ts');
  r.send({ type: 'render', html: '<pre>a</pre>', key: 'k1' });
  // A fence at line 0 whose top sits a pixel below the viewport top reads as line -0.1.
  await seedLineEntries(r, [{ line: 0, endLine: 10, top: 101, height: 100 }]);
  await quiet();
  assert.strictEqual(r.state.savedState?.scrollLine, 0);
});
