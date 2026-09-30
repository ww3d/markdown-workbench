// Viewport/content-box changes: the resize observer's re-measure and the fold pass.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  globalListener,
  headingEl,
  renderFoldDom,
  settleFold,
  topConfig,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

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

test('a window resize and a content-box change re-read the heading tops', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  const { scrollSpy } = await r.load('scroll-spy/spy.ts');
  const hs = [headingEl('h1', 'a', 'A', 0), headingEl('h1', 'b', 'B', 1000)];
  withHeadings(r, hs);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  const topOfB = () => scrollSpy.headings[1]?.top;
  assert.strictEqual(topOfB(), 1000);
  const b = hs[1];
  assert.ok(b);
  b.getBoundingClientRect = () => ({ top: 1500 }); // a reflow moved it
  globalListener(r, 'window', 'resize')({});
  assert.strictEqual(topOfB(), 1500, 'the resize re-measured');
  b.getBoundingClientRect = () => ({ top: 1800 }); // an image load moved it again
  const observer = r.state.resizeObserver;
  assert.ok(observer, 'the webview observes the body');
  observer();
  assert.strictEqual(topOfB(), 1800, 'the content-box change re-measured');
});
