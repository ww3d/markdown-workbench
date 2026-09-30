// Minimap navigation: centering clicks and the slider grab (like the editor minimap).
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { MM, sliderSetup } from '../../helpers/webview-fixtures.ts';

test('minimap navigation centers the clicked position (fill)', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
  });
  const { minimapNavigate } = await r.load('minimap/drag.ts');
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  minimapNavigate(400); // railY 400 -> docY 4000 -> centered: 4000-400
  assert.strictEqual(r.state.scrolledTo, 3600);
});

test('pointerdown on the slider grabs it without jumping', async () => {
  const { r, fire } = await sliderSetup();
  fire('pointerdown', 400); // inside [360, 440]
  assert.strictEqual(r.state.scrolledTo, null, 'grab must not scroll');
  assert.strictEqual(r.window.scrollY, 3600);
});

test('dragging the grabbed slider scrolls relative by px / mapSy', async () => {
  const { r, fire } = await sliderSetup();
  fire('pointerdown', 400); // grabOffset = 400 - 360 = 40
  fire('pointermove', 450); // sliderTop = 450 - 40 = 410 -> scrollY = 410 / 0.1
  assert.strictEqual(
    r.state.scrolledTo,
    4100,
    '50px drag = +500 scroll at mapSy 0.1',
  );
  fire('pointermove', 350); // sliderTop = 310 -> 3100
  assert.strictEqual(r.state.scrolledTo, 3100);
});

test('pointerdown outside the slider still centers, also after a grab', async () => {
  const { r, fire } = await sliderSetup();
  fire('pointerdown', 200); // outside [360, 440]: docY 2000 - 400 = 1600
  assert.strictEqual(r.state.scrolledTo, 1600);
  fire('pointerup', 200);
  // After the centering click scrollY is 1600 -> slider sits at [160, 240];
  // a fresh pointerdown at 396 is outside again and must center, proving a
  // previous interaction leaves no grab mode armed: docY 3960 - 400 = 3560.
  fire('pointerdown', 396);
  assert.strictEqual(r.state.scrolledTo, 3560);
});
