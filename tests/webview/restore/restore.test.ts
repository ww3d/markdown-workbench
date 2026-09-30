// Restore after a restart (src/webview/restore/restore.ts): a persisted stand of this
// build is on screen before the host's first render and named in `ready`; one of another
// build is discarded; the first host render then decides the content.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { TEST_BUILD_ID } from '../../helpers/build-id.ts';
import { byId, lineEls } from '../../helpers/webview-fixtures.ts';

const STAND = {
  documentUri: 'file:///ws/doc.md',
  buildId: TEST_BUILD_ID,
  key: 'k1',
  html: '<h1 id="a">A</h1>',
};

test('a persisted stand of this build is shown before the first host render, and ready names it (REQ-043, REQ-070)', async () => {
  const r = await startWebview({ savedState: STAND });
  assert.strictEqual(byId(r, 'content').innerHTML, STAND.html, 'shown at load');
  const [ready, ...rest] = r.state.posted;
  assert.deepStrictEqual(rest, [], 'ready is the only message');
  assert.strictEqual(ready?.type, 'ready');
  assert.ok(ready?.type === 'ready');
  assert.strictEqual(ready.buildId, TEST_BUILD_ID);
  assert.strictEqual(ready.key, 'k1');
  assert.strictEqual(typeof ready.restoredInMs, 'number');
});

test('the restored stand goes through the render path: morphed into #content like a render', async () => {
  const calls: { opts: { childrenOnly?: boolean } }[] = [];
  const prev = Reflect.get(globalThis, 'morphdom');
  Reflect.set(
    globalThis,
    'morphdom',
    (
      fromEl: { innerHTML: unknown },
      toEl: { innerHTML: unknown },
      opts: { childrenOnly?: boolean },
    ) => {
      calls.push({ opts });
      fromEl.innerHTML = toEl.innerHTML;
      return fromEl;
    },
  );
  try {
    await startWebview({ savedState: STAND });
    assert.deepStrictEqual(
      calls.map((c) => c.opts.childrenOnly),
      [true],
    );
  } finally {
    Reflect.set(globalThis, 'morphdom', prev);
  }
});

test('the restored scroll position is re-established without a scrolled report', async () => {
  const r = await startWebview({
    savedState: { ...STAND, scrollLine: 15 },
    prepare: (dom) => {
      const els = lineEls(
        [
          { line: 10, top: 0 },
          { line: 20, top: 200 },
        ],
        () => dom.window.scrollY,
      );
      dom.document.getElementById('content').querySelectorAll = (sel) =>
        sel === '[data-line]' ? els : [];
    },
  });
  assert.strictEqual(r.state.scrolledTo, 100);
  r.state.listeners.window.scroll?.({});
  assert.ok(!r.state.posted.some((m) => m.type === 'scrolled'), 'not reported');
});

test('a stand of another build is discarded: nothing shown, ready without build id and key (REQ-073)', async () => {
  const r = await startWebview({ savedState: { ...STAND, buildId: 'older' } });
  assert.strictEqual(byId(r, 'content').innerHTML, '', 'nothing shown');
  assert.deepStrictEqual(r.state.posted, [{ type: 'ready' }]);
  assert.deepStrictEqual(
    r.state.savedState,
    { documentUri: STAND.documentUri, buildId: TEST_BUILD_ID },
    'the stand is dropped, the document URI kept',
  );
});

test('a state without a stand (URI only) restores nothing and keeps the state', async () => {
  const saved = { documentUri: STAND.documentUri };
  const r = await startWebview({ savedState: saved });
  assert.deepStrictEqual(r.state.posted, [{ type: 'ready' }]);
  assert.strictEqual(r.state.stateWrites, 0);
});

test('after the first host render the content equals the host render (REQ-044)', async () => {
  const r = await startWebview({ savedState: STAND });
  r.send({ type: 'render', html: '<h1 id="b">B</h1>', key: 'k2', version: 4 });
  assert.strictEqual(byId(r, 'content').innerHTML, '<h1 id="b">B</h1>');
});
