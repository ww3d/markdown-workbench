// The render message: the identical-HTML guard, the morph in place, and the
// document stylesheet's heading margin.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import { byId, MM } from '../../helpers/webview-fixtures.ts';

test('an identical render is a no-op: the built DOM (scroll + fold state) is kept (#44 P2)', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const content = byId(r, 'content');
  r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  content.innerHTML = 'SENTINEL'; // a following identical render must not overwrite the live DOM
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(
    content.innerHTML,
    'SENTINEL',
    'identical HTML skips the whole rebuild',
  );
  r.send({ type: 'render', html: '<h1 id="b">B</h1>' });
  assert.strictEqual(
    content.innerHTML,
    '<h1 id="b">B</h1>',
    'changed HTML re-renders as before',
  );
});

test('a changed render morphs #content in place (childrenOnly), guarded against an identical one (#44 P2)', async () => {
  // The render path patches the DOM via morphdom instead of replacing innerHTML,
  // so a content edit preserves scroll and selection (VS Code preview parity).
  const calls: { fromEl: unknown; opts: { childrenOnly?: boolean } }[] = [];
  const prev = Reflect.get(globalThis, 'morphdom');
  Reflect.set(
    globalThis,
    'morphdom',
    (
      fromEl: { innerHTML: unknown },
      toEl: { innerHTML: unknown } | undefined,
      opts: { childrenOnly?: boolean },
    ) => {
      // spy on the real orchestration
      calls.push({ fromEl, opts });
      if (toEl && typeof toEl.innerHTML === 'string')
        fromEl.innerHTML = toEl.innerHTML;
      return fromEl;
    },
  );
  try {
    const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
    const content = byId(r, 'content');
    r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
    r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
    assert.strictEqual(calls.length, 1, 'the first render morphs');
    assert.strictEqual(
      calls[0]?.fromEl,
      content,
      'morphs the live #content element',
    );
    assert.strictEqual(
      calls[0]?.opts.childrenOnly,
      true,
      'childrenOnly so #content itself is kept',
    );
    r.send({ type: 'render', html: '<h1 id="a">A</h1>' }); // identical -> guarded, no morph
    assert.strictEqual(
      calls.length,
      1,
      'an identical render does not morph again',
    );
    r.send({ type: 'render', html: '<h1 id="b">B</h1>' }); // changed -> morphs again
    assert.strictEqual(calls.length, 2, 'a changed render morphs again');
  } finally {
    Reflect.set(globalThis, 'morphdom', prev);
  }
});

// morphdom as the tests stand it in, which throws on its `failOn`-th call after morphing.
function throwingMorphdom(failOn: number): {
  calls: () => number;
  restore: () => void;
} {
  const prev = Reflect.get(globalThis, 'morphdom');
  let calls = 0;
  Reflect.set(
    globalThis,
    'morphdom',
    (fromEl: { innerHTML: unknown }, toEl: { innerHTML: unknown }) => {
      fromEl.innerHTML = toEl.innerHTML;
      if (++calls === failOn) throw new Error('morph failed (test)');
      return fromEl;
    },
  );
  return {
    calls: () => calls,
    restore: () => Reflect.set(globalThis, 'morphdom', prev),
  };
}

test('a render that throws half-way does not block the next render of the previous HTML', async () => {
  const morph = throwingMorphdom(2);
  try {
    const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
    r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
    r.send({ type: 'render', html: '<p>A</p>' });
    assert.throws(
      () => r.send({ type: 'render', html: '<p>B</p>' }),
      /morph failed/,
    );
    assert.strictEqual(
      byId(r, 'content').innerHTML,
      '<p>B</p>',
      'the morph reached #content',
    );
    r.send({ type: 'render', html: '<p>A</p>' }); // e.g. an undo: must not be taken as a repeat
    assert.strictEqual(byId(r, 'content').innerHTML, '<p>A</p>');
    assert.strictEqual(morph.calls(), 3);
  } finally {
    morph.restore();
  }
});

test('a render that throws leaves the saved stand at the previous render', async (t) => {
  const morph = throwingMorphdom(2);
  try {
    const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
    t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: Date.now() });
    const { STATE_SAVE_QUIET_MS } = await r.load('restore/state.ts');
    r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
    r.send({ type: 'render', html: '<p>A</p>', key: 'ka' });
    t.mock.timers.tick(STATE_SAVE_QUIET_MS + 60);
    assert.strictEqual(r.state.savedState?.html, '<p>A</p>');
    assert.throws(() =>
      r.send({ type: 'render', html: '<p>B</p>', key: 'kb' }),
    );
    t.mock.timers.tick(STATE_SAVE_QUIET_MS + 60);
    assert.strictEqual(
      r.state.savedState?.html,
      '<p>A</p>',
      'the broken render is not saved',
    );
    assert.strictEqual(r.state.savedState?.key, 'ka');
  } finally {
    morph.restore();
  }
});

test('headings carry a scroll-margin-top so anchors clear the top edge', () => {
  assert.match(
    sheet('render/document.css').ruleBody('h1'),
    /scroll-margin-top/,
  );
});
