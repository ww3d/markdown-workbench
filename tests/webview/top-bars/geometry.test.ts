// The top bars' fixed geometry (docs/DECISIONS.md #36).
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';

test('topBarsHeight: computed from the fixed geometry (breadcrumb 28 + rows x 22)', async () => {
  const r = await startWebview();
  const { topBarsHeight } = await r.load('top-bars/geometry.ts');
  assert.strictEqual(topBarsHeight(false, 0), 0, 'both bars hidden -> 0');
  assert.strictEqual(topBarsHeight(true, 0), 28, 'breadcrumb only');
  assert.strictEqual(
    topBarsHeight(true, 3),
    28 + 66,
    'breadcrumb + 3 sticky rows',
  );
  assert.strictEqual(topBarsHeight(false, 2), 44, 'stack only');
});

test('the bar heights in the stylesheet are the constants the stack height is computed from (#36)', async () => {
  const r = await startWebview();
  const { BREADCRUMB_HEIGHT_PX, STICKY_ROW_HEIGHT_PX } = await r.load(
    'top-bars/geometry.ts',
  );
  const css = sheet('top-bars/top-bars.css');
  const px = (selector: string) =>
    Number(css.ruleBody(selector).match(/(?:^|;)\s*height:\s*(\d+)px/)?.[1]);
  assert.strictEqual(px('#breadcrumb'), BREADCRUMB_HEIGHT_PX);
  assert.strictEqual(px('.sticky-row'), STICKY_ROW_HEIGHT_PX);
  // The px are exact only when padding and border sit inside the height.
  assert.match(css.ruleBody('#breadcrumb'), /box-sizing:\s*border-box/);
  assert.match(css.ruleBody('.sticky-row'), /box-sizing:\s*border-box/);
});
