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

test('headings carry a scroll-margin-top so anchors clear the top edge', () => {
  assert.match(
    sheet('render/document.css').ruleBody('h1'),
    /scroll-margin-top/,
  );
});
