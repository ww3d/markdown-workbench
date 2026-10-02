// The cached line map: the scroll path reads cached tops, not layout.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { byId, scroll } from '../../helpers/webview-fixtures.ts';

test('sourceLineAtTop reads at most one rect per frame, not one per line entry (#44 perf)', async () => {
  // The scroll-sync freeze: the old scan called getBoundingClientRect on EVERY
  // [data-line] element each frame. The tops are cached (binary search), so a
  // scroll frame reads at most one rect (the resolved entry, for its height).
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { lineMetrics } = await r.load('scroll-sync/line-metrics.ts');
  let rectCalls = 0;
  const els: unknown[] = [];
  for (let i = 0; i < 50; i++)
    els.push({
      dataset: { line: String(i * 10) },
      getBoundingClientRect: () => {
        rectCalls++;
        return { top: i * 100 - r.window.scrollY, height: 90 };
      },
    });
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === '[data-line]' ? els : [];
  lineMetrics.collect(); // caches all 50 tops here, once
  rectCalls = 0; // count only the scroll-path reads
  r.window.scrollY = 2500;
  scroll(r);
  assert.ok(
    rectCalls <= 1,
    `at most one rect read per scroll frame, got ${rectCalls} for 50 entries`,
  );
});
