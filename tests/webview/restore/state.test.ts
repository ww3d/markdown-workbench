// What the webview persists (src/webview/restore/state.ts): the stand of the last render
// with its key, scroll line and build id, merged with the document URI; the HTML only up
// to the bound; one setState per quiet phase, none in a render or scroll frame.
import { test } from 'node:test';
import assert from 'node:assert';
import { setTimeout as sleep } from 'node:timers/promises';
import { startWebview } from '../../helpers/webview-dom.ts';
import type { Webview } from '../../helpers/webview-dom.ts';
import { TEST_BUILD_ID } from '../../helpers/build-id.ts';
import { scroll, sendCfg } from '../../helpers/webview-fixtures.ts';

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

test('a render and scroll burst writes the state once per quiet phase, never in the frame', async () => {
  const r = await startWebview();
  const writes = () => r.state.stateWrites;
  for (let i = 0; i < 20; i++)
    r.send({ type: 'render', html: `<p>${i}</p>`, key: `k${i}` });
  for (let i = 0; i < 200; i++) scroll(r);
  assert.strictEqual(
    writes(),
    0,
    'no setState inside a render or scroll frame',
  );
  await sleep(STATE_SAVE_QUIET_MS / 2);
  scroll(r); // still active: the quiet time starts over
  await sleep(STATE_SAVE_QUIET_MS / 2 + 20);
  assert.strictEqual(writes(), 0, 'no write while the view is not quiet');
  await quiet();
  assert.strictEqual(writes(), 1, 'one write for the whole burst');
  assert.strictEqual(r.state.savedState?.key, 'k19', 'the last render wins');
  scroll(r);
  await quiet();
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
