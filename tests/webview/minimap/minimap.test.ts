// The minimap rail: visibility, size modes, defensive config handling, the clone,
// and its stylesheet contract.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  headingEl,
  MM,
  px,
  renderFoldDom,
  scroll,
  topConfig,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

const css = sheet('minimap/minimap.css');

test('render shows the minimap for long documents', async () => {
  const { state, send } = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
  });
  send({ type: 'config', maxWidth: '980px', minimap: MM() });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], true);
});

test('the minimap clone strips ids so it never shadows the real anchor targets', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const removed: string[] = [];
  byId(r, 'content').cloneNode = () => ({
    querySelectorAll: (sel: string) =>
      sel === '[id]'
        ? [{ removeAttribute: (a: string) => removed.push(a) }]
        : [],
  });
  r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
  r.send({ type: 'render', html: '<h1 id="x">x</h1>' });
  assert.ok(
    removed.includes('id'),
    'heading id stripped from the minimap clone',
  );
});

test('short documents hide the minimap', async () => {
  const { state, send } = await startWebview({
    docHeight: 500,
    viewHeight: 800,
  });
  send({ type: 'config', maxWidth: '980px', minimap: MM() });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], false);
});

test('proportional mode pans: known slider geometry', async () => {
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
  // k=88/700; mapDocH=8000k=1005.71; overflow=205.71; offset=-(3600/7200)*205.71=-102.86
  // slider top = 3600k + offset = 452.57-102.86 = 349.71
  const top = px(byId(r, 'minimap-slider').style.top);
  assert.ok(Math.abs(top - 349.71) < 0.5, String(top));
  assert.match(
    String(byId(r, 'minimap-content').style.transform),
    /translateY\(-102\.8/,
  );
});

test('fill mode aligns the slider with the scrollbar and never pans', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
  });
  r.window.scrollY = 3600;
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  // sy = 800/8000 = 0.1 -> top = 360 = scrollbar thumb position; h = 80
  assert.strictEqual(px(byId(r, 'minimap-slider').style.top), 360);
  assert.strictEqual(px(byId(r, 'minimap-slider').style.height), 80);
  assert.match(
    String(byId(r, 'minimap-content').style.transform),
    /translateY\(0px\)/,
  );
});

test('fit mode caps the scale at the rail and never stretches', async () => {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
    contentWidth: 700,
    railWidth: 88,
  });
  r.window.scrollY = 3600;
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fit' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  // sy = min(88/700, 800/8000) = 0.1 -> identical mapping to fill here
  assert.strictEqual(px(byId(r, 'minimap-slider').style.top), 360);
});

test('fit equals proportional while the document still fits the rail', async () => {
  const opts = {
    docHeight: 3000,
    viewHeight: 800,
    railHeight: 800,
    contentWidth: 700,
    railWidth: 88,
  };
  // k=0.12571; docH*k=377 < 800 -> proportional: no pan; fit: sy=min(k, 0.2667)=k
  const a = await startWebview(opts);
  a.window.scrollY = 1000;
  a.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ size: 'proportional' }),
  });
  a.send({ type: 'render', html: '<p>x</p>' });
  const aTop = byId(a, 'minimap-slider').style.top;
  const b = await startWebview(opts);
  b.window.scrollY = 1000;
  b.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fit' }) });
  b.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(aTop, byId(b, 'minimap-slider').style.top);
});

test('undefined or missing minimap config falls back to defaults (regression 0.21.1)', async () => {
  const { state, send } = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
  });
  send({ type: 'config', maxWidth: '980px', minimap: { enabled: undefined } });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], true);
  send({ type: 'config', maxWidth: '980px', minimap: undefined });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], true);
});

test('enabled:false hides the rail even for long documents', async () => {
  const { state, send } = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
  });
  send({ type: 'config', maxWidth: '980px', minimap: MM({ enabled: false }) });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], false);
});

test('side and slider visibility map to classes', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ side: 'left', showSlider: 'mouseover' }),
  });
  r.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(r.state.bodyClasses['minimap-left'], true);
  assert.strictEqual(byId(r, 'minimap')._classes['slider-mouseover'], true);
});

test('a dragged minimap slider shows the active color, even while hovered', () => {
  // Hover and drag rules have equal specificity (2,1,0), so their order decides:
  // while dragging the pointer is also over the minimap, and the drag color has
  // to win - the drag rule must come after the hover rule.
  const hover = '#minimap:hover #minimap-slider';
  const drag = '#minimap.dragging #minimap-slider';
  assert.match(css.ruleBody(hover), /minimapSlider-hoverBackground/);
  assert.match(css.ruleBody(drag), /minimapSlider-activeBackground/);
  assert.ok(
    css.ruleIndex(hover) >= 0 && css.ruleIndex(hover) < css.ruleIndex(drag),
    'drag rule after hover rule',
  );
});

test('the minimap keeps user-select: none', () => {
  assert.match(css.ruleBody('#minimap'), /user-select:\s*none/);
});

test('the minimap stays shown while a section is folded, so it never slides the content (#44 P2)', async () => {
  // A short/heavily-folded page fits the viewport (scrollMax <= 0). Without a fold
  // the minimap auto-hides (its padding gone -> content slides); with a fold active
  // it must stay, keeping the reserved padding stable.
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 400,
    viewHeight: 800,
  });
  const { toggleFold } = await r.load('folding/fold.ts');
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  r.send(topConfig({ minimap: MM() }));
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(
    !!r.state.bodyClasses['has-minimap'],
    false,
    'a short page hides the minimap normally',
  );
  toggleFold('a'); // fold active
  scroll(r); // next updateMinimap (rAF is synchronous in the mock)
  assert.strictEqual(
    r.state.bodyClasses['has-minimap'],
    true,
    'a fold keeps the minimap (no content slide)',
  );
});

test('the minimap clone drops #content own id, not just the heading ids (#44 P2)', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { clone } = renderFoldDom(r);
  assert.ok(
    clone.removed.includes('id'),
    'the clone root would otherwise be a second element with id="content"',
  );
});
