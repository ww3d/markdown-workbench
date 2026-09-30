// The batched re-measure after a fold: the minimap mirror, the flush before a
// position read, and the idle slots (#44 P2 perf).
import { test } from 'node:test';
import assert from 'node:assert';
import { nth } from '../../helpers/nth.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  renderFoldDom,
  scroll,
  settleFold,
} from '../../helpers/webview-fixtures.ts';

test('a fold mirrors itself onto the existing minimap clone instead of re-cloning (#44 P2 perf)', async () => {
  // Re-cloning #content per fold laid out and painted a second full copy of the
  // document (measured as the fold path's dominant cost, bench/fold-bench.ts). The
  // clone's blocks are index-parallel, so the fold is mirrored as a class write.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { clone, clones } = renderFoldDom(r);
  toggleFold('b');
  await settleFold();
  assert.strictEqual(clones.count, 0, 'the fold refresh reuses the clone');
  assert.strictEqual(
    nth(clone.children, 3).classList.contains('mw-fold-hidden'),
    true,
    "the folded section's block is hidden in the clone too",
  );
  assert.strictEqual(
    nth(clone.children, 5).classList.contains('mw-fold-hidden'),
    false,
    'a block outside the folded section stays shown in the clone',
  );
  toggleFold('b');
  await settleFold();
  assert.strictEqual(clones.count, 0, 'unfolding reuses it as well');
  assert.strictEqual(
    nth(clone.children, 3).classList.contains('mw-fold-hidden'),
    false,
    'unfolding un-hides the mirrored block',
  );
});

test('a scroll right after a fold reports from fresh tops, not stale ones (#44 P2 perf)', async () => {
  // The re-measure is deferred into idle time, so anything that READS a position has
  // to flush it first. Otherwise the scroll sync reports a line computed from the
  // pre-fold tops and the host reveals the wrong range in the source editor.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { blocks } = renderFoldDom(r);
  toggleFold('b');
  for (const b of blocks) b.rects = 0;
  scroll(r); // rAF is synchronous in the mock
  assert.ok(
    blocks.reduce((n, b) => n + b.rects, 0) > 0,
    'the pending re-measure is flushed before the scroll position is reported',
  );
  for (const b of blocks) b.rects = 0;
  scroll(r);
  assert.strictEqual(
    blocks.reduce((n, b) => n + b.rects, 0),
    0,
    'and only once - a second scroll finds the metrics fresh (hot path stays free)',
  );
});

test('flushing the fold metrics does not pay the minimap clone cost (#44 P2 perf)', async () => {
  // The clone is a second full document; its relayout is the most expensive thing a
  // fold triggers. It must stay in the idle slot, never on the path of whoever needed
  // the fresh metrics.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { clone } = renderFoldDom(r);
  toggleFold('b');
  scroll(r); // flushes the metrics synchronously
  assert.strictEqual(
    nth(clone.children, 3).classList.contains('mw-fold-hidden'),
    false,
    'the flush re-measures but leaves the clone alone',
  );
  await settleFold();
  assert.strictEqual(
    nth(clone.children, 3).classList.contains('mw-fold-hidden'),
    true,
    'the clone catches up in idle time',
  );
});

test('the fold pass waits for idle time with a 250 ms deadline where requestIdleCallback exists', async () => {
  const deadlines: unknown[] = [];
  Reflect.set(
    globalThis,
    'requestIdleCallback',
    (fn: () => void, options: unknown) => {
      deadlines.push(options);
      setTimeout(fn, 0);
      return deadlines.length;
    },
  );
  try {
    const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
    const { toggleFold } = await r.load('folding/fold.ts');
    const { blocks } = renderFoldDom(r);
    for (const b of blocks) b.rects = 0;
    toggleFold('b');
    assert.deepStrictEqual(deadlines, [{ timeout: 250 }], 're-measure queued');
    assert.strictEqual(
      blocks.reduce((n, b) => n + b.rects, 0),
      0,
      'nothing measured before the idle slot',
    );
    await settleFold();
    assert.ok(blocks.reduce((n, b) => n + b.rects, 0) > 0, 'measured in it');
    assert.deepStrictEqual(
      deadlines,
      [{ timeout: 250 }, { timeout: 250 }],
      'the minimap mirror takes a second idle slot',
    );
  } finally {
    Reflect.deleteProperty(globalThis, 'requestIdleCallback');
  }
});

test('the fold mirror rebuilds the minimap when the clone no longer matches the document', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { content, blocks, clones } = renderFoldDom(r);
  content.children = [...blocks, nth(blocks, 1)]; // one block more than the clone
  toggleFold('b');
  await settleFold();
  assert.strictEqual(clones.count, 1, 'rebuilt instead of mirrored');
});

test('the fold mirror rebuilds the minimap when the rail has to appear', async () => {
  const r = await startWebview({ docHeight: 400, viewHeight: 800 }); // fits: no rail
  const { toggleFold } = await r.load('folding/fold.ts');
  const { clones } = renderFoldDom(r);
  toggleFold('b'); // a fold keeps the rail shown (#44 P2)
  scroll(r); // flush the fold pass now; the mirror still waits for its idle slot
  r.document.body.classList.remove('has-minimap'); // the rail is not shown yet
  await settleFold();
  assert.strictEqual(clones.count, 1, 'rebuilt, with a fresh clone');
  assert.strictEqual(r.state.bodyClasses['has-minimap'], true);
});
