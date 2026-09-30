// Minimap navigation: centering clicks and the slider grab (like the editor minimap).
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  listenerOf,
  MM,
  sliderSetup,
} from '../../helpers/webview-fixtures.ts';

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

test('a slider hidden until hover (showSlider mouseover) is still grabbed, not jumped over', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
  });
  r.window.scrollY = 3600;
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ size: 'fill', showSlider: 'mouseover' }),
  });
  r.send({ type: 'render', html: '<p>x</p>' });
  listenerOf(
    byId(r, 'minimap'),
    'pointerdown',
  )({
    clientY: 400, // inside the slider [360, 440]
    pointerId: 1,
    preventDefault() {},
  });
  assert.strictEqual(r.state.scrolledTo, null, 'grabbed, no centering jump');
});

test('the slider hit test follows the pan offset of the proportional mode', async () => {
  // k = 88/700; at scrollY 3600 the clone is panned by -102.86px, so the slider
  // spans [349.71, 450.28] - a hit test without the pan would put it at 452.57.
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
    contentWidth: 700,
    railWidth: 88,
  });
  r.window.scrollY = 3600;
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ size: 'proportional' }),
  });
  r.send({ type: 'render', html: '<p>x</p>' });
  listenerOf(
    byId(r, 'minimap'),
    'pointerdown',
  )({
    clientY: 400,
    pointerId: 1,
    preventDefault() {},
  });
  assert.strictEqual(
    r.state.scrolledTo,
    null,
    'inside the panned slider: a grab',
  );
});

test('moving the pointer while a rail (centering) drag is held keeps centering', async () => {
  const { r, fire } = await sliderSetup();
  fire('pointerdown', 200); // outside the slider: centers docY 2000 -> 1600
  assert.strictEqual(r.state.scrolledTo, 1600);
  fire('pointermove', 300); // still held: centers docY 3000 -> 2600
  assert.strictEqual(r.state.scrolledTo, 2600);
  fire('pointerup', 300);
  fire('pointermove', 100); // released: no more moves
  assert.strictEqual(r.state.scrolledTo, 2600);
});
