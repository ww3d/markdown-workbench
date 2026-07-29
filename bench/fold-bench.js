#!/usr/bin/env node
// Headless-Chromium fold benchmark for the preview webview.
//
// Folds and unfolds one section at a time on a generated document and reports
// what the user actually waits for:
//
//   click  - the SYNCHRONOUS work a fold click does before the browser can paint
//            (the delegated handler, applyFolds, plus the layout the fold forces)
//   gap    - the longest frame gap in the settle window after the click, i.e. the
//            debounced heavy refresh (re-measure + minimap) as felt blocking time
//   janky  - how many frames in that window ran over budget, and their total
//            over-budget time: one 30ms hitch and three of them feel different,
//            and `gap` alone cannot tell them apart
//   sync   - 'scrolled' messages the toggle posted to the host. Each one makes the
//            host revealRange the source editor, which posts a scrollTo back - a
//            round trip the headless stub cannot show but the real editor feels
//   gbcr   - getBoundingClientRect calls per toggle (a forced-layout proxy)
//
// Usage:
//   node bench/fold-bench.js                        # 300 sections, 12 samples
//   node bench/fold-bench.js --sections 600         # bigger document
//   node bench/fold-bench.js --tables 200           # + tables (minimap clone cost)
//   node bench/fold-bench.js --no-minimap           # rail off: the clone's own share
//   node bench/fold-bench.js --from-top             # fold from scroll 0 instead of
//                                                   # from the heading you are looking at
//   node bench/fold-bench.js --profile              # + a CPU self-time table
//   node bench/fold-bench.js --trace                # who re-measures, frame by frame
//
// Numbers are relative and machine-dependent; compare a change against its
// baseline on the same machine, not against an absolute target.

const { buildPage, runPage, cli } = require('./harness');

const { flag, opt } = cli(process.argv.slice(2));
const SECTIONS = Number(opt('--sections', '300'));
const TABLES = Number(opt('--tables', '0'));
const SAMPLES = Number(opt('--samples', '12'));
const SETTLE = Number(opt('--settle', '400'));
const MINIMAP = !flag('--no-minimap');
const FROM_TOP = flag('--from-top');
const TRACE = flag('--trace');

// A document of h2 sections, each with an h3 subsection, paragraphs, a list and
// (optionally) a table - the block mix a real document folds.
function doc() {
  let h = '', line = 1;
  for (let s = 0; s < SECTIONS; s++) {
    h += `<h2 id="s${s}" data-line="${line++}">Section ${s}</h2>`;
    for (let p = 0; p < 2; p++) h += `<p data-line="${line++}">Paragraph ${s}.${p} lorem ipsum dolor sit amet consectetur adipiscing elit.</p>`;
    h += `<h3 id="s${s}a" data-line="${line++}">Subsection ${s}.a</h3>`;
    h += `<ul data-line="${line++}"><li>alpha</li><li>beta</li><li>gamma</li></ul>`;
    h += `<p data-line="${line++}">Paragraph ${s}.tail lorem ipsum dolor sit amet.</p>`;
    if (TABLES && s < TABLES) {
      let rows = '';
      for (let r = 0; r < 6; r++) rows += `<tr><td>${r}a</td><td>${r}b</td><td>${r}c</td></tr>`;
      h += `<div class="table-wrap" data-line="${line++}"><table><thead><tr><th>A</th><th>B</th><th>C</th></tr></thead><tbody>${rows}</tbody></table></div>`;
    }
  }
  return h;
}

const driver = `
const DOC = ${JSON.stringify(doc())};
const SAMPLES = ${SAMPLES}, SETTLE = ${SETTLE}, FROM_TOP = ${FROM_TOP}, TRACE = ${TRACE};
const trace = [];
const config = {
  type: 'config', maxWidth: '980px',
  minimap: { enabled: ${MINIMAP}, side: 'right', size: 'proportional', showSlider: 'always' },
  toc: { enabled: true, mode: 'auto' }, breadcrumb: { enabled: true }, stickyScroll: { enabled: true }
};

// One toggle: click the section's fold chevron, force the layout it triggers, then
// watch the settle window for the debounced heavy refresh (the longest frame gap).
const FRAME_BUDGET = 20; // ms; a frame longer than this is a visible hitch at 60Hz

// Diagnostic mode (--trace): count who re-measures per toggle and print the frame
// timeline of one sample, so a multi-hitch toggle can be attributed instead of
// guessed at. Wraps the webview's own entry points (same global lexical scope).
const calls = { collect: 0, refresh: 0, spyMetrics: 0, rebuild: 0, resizeObserver: 0 };
function instrument() {
  const wrap = (obj, name, key) => { const f = obj[name]; obj[name] = function () { calls[key]++; return f.apply(this, arguments); }; };
  wrap(lineMetrics, 'collect', 'collect');
  // Time the batched pass itself, so its cost is attributable independently of which
  // frame it happens to land in.
  const pass = refreshAfterFold;
  window.__passMs = 0;
  refreshAfterFold = function () { const t = performance.now(); pass.apply(this, arguments); window.__passMs = performance.now() - t; };
  wrap(lineMetrics, 'refresh', 'refresh');
  wrap(scrollSpy, 'refreshMetrics', 'spyMetrics');
  const ro = window.ResizeObserver;
  window.ResizeObserver = class extends ro {
    constructor(cb) { super(() => { calls.resizeObserver++; cb(); }); }
  };
}
const resetCalls = () => { for (const k in calls) calls[k] = 0; };
const callsLine = () => Object.keys(calls).map((k) => k + '=' + calls[k]).join(' ');

async function toggle(id) {
  const chevron = content.querySelector('#' + id + ' .mw-fold-toggle');
  window.__gbcr = 0;
  window.__posted.length = 0;
  const t0 = performance.now();
  chevron.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  void document.documentElement.scrollHeight; // force the fold's layout into this measurement
  const click = performance.now() - t0;
  let last = performance.now(), gap = 0, janky = 0, blocked = 0;
  const until = last + SETTLE;
  const frames = [];
  while (performance.now() < until) {
    await raf();
    const now = performance.now();
    const frame = now - last;
    if (frame > gap) gap = frame;
    if (frame > FRAME_BUDGET) { janky++; blocked += frame - FRAME_BUDGET; }
    if (TRACE) frames.push(Math.round(frame));
    last = now;
  }
  if (TRACE) trace.push('click=' + ms(click) + ' pass=' + ms(window.__passMs || 0)
    + 'ms frames=[' + frames.join(',') + '] ' + callsLine());
  const sync = window.__posted.filter((m) => m && m.type === 'scrolled').length;
  return { click, gap, janky, blocked, sync, gbcr: window.__gbcr };
}

async function run() {
  if (TRACE) instrument();
  window.dispatchEvent(new MessageEvent('message', { data: config }));
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'render', html: DOC } }));
  await raf(); await raf(); await sleep(300);

  // Sample sections spread over the document (a fold near the top shifts more
  // content than one near the end, so a contiguous run would bias the numbers).
  const ids = [];
  const all = [...content.querySelectorAll('h2')].map((h) => h.id);
  const step = Math.max(1, Math.floor(all.length / SAMPLES));
  for (let i = 0; i < all.length && ids.length < SAMPLES; i += step) ids.push(all[i]);

  const keys = ['click', 'gap', 'janky', 'blocked', 'sync', 'gbcr'];
  const bucket = () => ({ click: [], gap: [], janky: [], blocked: [], sync: [], gbcr: [] });
  const fold = bucket(), unfold = bucket();
  for (const id of ids) {
    // Real gesture: you scroll to the section, then click its chevron. Folding then
    // changes the document height under a non-zero scroll position, which is what
    // makes the browser clamp the scroll and the preview post a source line back to
    // the host. --from-top keeps the artificial scroll-0 case for comparison.
    const heading = content.querySelector('#' + id);
    window.scrollTo(0, FROM_TOP ? 0 : Math.max(0, heading.getBoundingClientRect().top + window.scrollY - 40));
    window.dispatchEvent(new Event('scroll'));
    await raf(); await sleep(250); // let the scroll settle (and its posts drain) first
    resetCalls();
    const f = await toggle(id);   // fold
    resetCalls();
    const u = await toggle(id);   // unfold again, so every sample starts equal
    for (const k of keys) { fold[k].push(f[k]); unfold[k].push(u[k]); }
  }
  const line = (name, b) => name + ': click=' + ms(median(b.click)) + 'ms gap=' + ms(median(b.gap))
    + 'ms janky=' + median(b.janky) + '/' + ms(median(b.blocked)) + 'ms sync=' + median(b.sync)
    + ' gbcr=' + median(b.gbcr);
  report('samples=' + ids.length
    + ' ' + line('fold', fold) + ' | ' + line('unfold', unfold)
    + ' | blocks=' + document.getElementById('content').children.length
    + ' lines=' + content.querySelectorAll('[data-line]').length
    + ' headings=' + content.querySelectorAll('h1,h2,h3').length
    + ' scrollHeight=' + document.documentElement.scrollHeight
    + (TRACE ? '\\n' + trace.slice(0, 4).join('\\n') : ''));
}
run();
`;

runPage(buildPage(driver), { profile: flag('--profile'), name: 'fold-bench' });
