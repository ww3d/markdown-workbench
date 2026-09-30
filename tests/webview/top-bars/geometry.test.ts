// The top bars' fixed geometry (docs/DECISIONS.md #36).
import { test } from 'node:test';
import assert from 'node:assert';
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
