// Viewport/content-box changes: the resize observer's re-measure and the fold pass.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { renderFoldDom, settleFold } from '../../helpers/webview-fixtures.ts';

test('the resize observer skips its re-measure while a fold refresh is pending (#44 P2 perf)', async () => {
  // A fold changes the body height, so the observer fires on every toggle. Left
  // unguarded it measured every cached top a second time per toggle - and it did so
  // before the folded-away blocks were filtered out, which puts them at top 0 and
  // breaks the monotonic line->pixel map.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { blocks } = renderFoldDom(r);
  const observer = r.state.resizeObserver;
  assert.ok(observer, 'the webview observes the body');
  toggleFold('b');
  for (const b of blocks) b.rects = 0;
  observer();
  assert.strictEqual(
    blocks.reduce((n, b) => n + b.rects, 0),
    0,
    'no re-measure while the batched fold pass is still pending',
  );
  await settleFold();
  assert.ok(
    blocks.reduce((n, b) => n + b.rects, 0) > 0,
    'the batched pass does re-measure',
  );
  for (const b of blocks) b.rects = 0;
  observer();
  assert.ok(
    blocks.reduce((n, b) => n + b.rects, 0) > 0,
    'with nothing pending the observer measures as before (image loads / reflow)',
  );
});
