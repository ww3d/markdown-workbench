// Restore after a restart (src/webview/restore/restore.ts): a persisted stand of this
// build is on screen before the host's first render and named in `ready`; one of another
// build is discarded; the first host render then decides the content.
import { test } from 'node:test';
import assert from 'node:assert';
import { setTimeout as sleep } from 'node:timers/promises';
import { type createDom, startWebview } from '../../helpers/webview-dom.ts';
import { TEST_BUILD_ID } from '../../helpers/build-id.ts';
import {
  byId,
  lineEls,
  scroll,
  sendCfg,
} from '../../helpers/webview-fixtures.ts';

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

// Lines 10 and 20 whose tops follow the content width like a real layout: the default width
// puts them at 100 and 300, a config with 72ch at 150 and 450.
function widthDependentLines(dom: ReturnType<typeof createDom>): void {
  const scale = () =>
    dom.state.cssVars?.['--mc-max-width'] === '72ch' ? 1.5 : 1;
  const els = [10, 20].map((line, i) => ({
    dataset: { line: String(line) },
    getBoundingClientRect: () => ({
      top: (100 + 200 * i) * scale() - dom.window.scrollY,
      height: 20,
    }),
  }));
  dom.document.getElementById('content').querySelectorAll = (sel) =>
    sel === '[data-line]' ? els : [];
}

const restoredAt15 = () =>
  startWebview({
    savedState: { ...STAND, scrollLine: 15 },
    prepare: widthDependentLines,
  });

test('the first config moves the layout: the restored line is scrolled to again and persisted as such', async () => {
  const r = await restoredAt15();
  assert.strictEqual(r.state.scrolledTo, 200, 'line 15 in the default layout');
  sendCfg(r, { maxWidth: '72ch' });
  assert.strictEqual(r.state.scrolledTo, 300, 'line 15 in the 72ch layout');
  r.state.listeners.window.scroll?.({});
  assert.ok(
    !r.state.posted.some((m) => m.type === 'scrolled'),
    'the re-scroll is not reported',
  );
  const { STATE_SAVE_QUIET_MS } = await r.load('restore/state.ts');
  await sleep(STATE_SAVE_QUIET_MS + 60);
  assert.strictEqual(r.state.savedState?.scrollLine, 15);
  sendCfg(r, { maxWidth: '980px' });
  assert.strictEqual(r.state.scrolledTo, 300, 'only the first config');
});

test('a reader scroll before the first config keeps the reader position', async (t) => {
  const r = await restoredAt15();
  // Past the echo suppression of the restore: the next scroll is the reader's.
  t.mock.timers.enable({ apis: ['Date'], now: Date.now() + 1000 });
  scroll(r);
  sendCfg(r, { maxWidth: '72ch' });
  assert.strictEqual(r.state.scrolledTo, 200);
});

test('a host scrollTo before the first config takes over from the restored line', async () => {
  const r = await restoredAt15();
  r.send({ type: 'scrollTo', line: 10 });
  assert.strictEqual(r.state.scrolledTo, 100);
  sendCfg(r, { maxWidth: '72ch' });
  assert.strictEqual(r.state.scrolledTo, 100);
});
