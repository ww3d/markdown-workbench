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
//   gbcr   - getBoundingClientRect calls per toggle (a forced-layout proxy)
//
// Usage:
//   node bench/fold-bench.js                        # 300 sections, 12 samples
//   node bench/fold-bench.js --sections 600         # bigger document
//   node bench/fold-bench.js --tables 200           # + tables (minimap clone cost)
//   node bench/fold-bench.js --no-minimap           # rail off: the clone's own share
//   node bench/fold-bench.js --profile              # + a CPU self-time table
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
const SAMPLES = ${SAMPLES}, SETTLE = ${SETTLE};
const config = {
  type: 'config', maxWidth: '980px',
  minimap: { enabled: ${MINIMAP}, side: 'right', size: 'proportional', showSlider: 'always' },
  toc: { enabled: true, mode: 'auto' }, breadcrumb: { enabled: true }, stickyScroll: { enabled: true }
};

// One toggle: click the section's fold chevron, force the layout it triggers, then
// watch the settle window for the debounced heavy refresh (the longest frame gap).
async function toggle(id) {
  const chevron = content.querySelector('#' + id + ' .mw-fold-toggle');
  window.__gbcr = 0;
  const t0 = performance.now();
  chevron.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  void document.documentElement.scrollHeight; // force the fold's layout into this measurement
  const click = performance.now() - t0;
  let last = performance.now(), gap = 0;
  const until = last + SETTLE;
  while (performance.now() < until) {
    await raf();
    const now = performance.now();
    if (now - last > gap) gap = now - last;
    last = now;
  }
  return { click, gap, gbcr: window.__gbcr };
}

async function run() {
  window.dispatchEvent(new MessageEvent('message', { data: config }));
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'render', html: DOC } }));
  await raf(); await raf(); await sleep(300);

  // Sample sections spread over the document (a fold near the top shifts more
  // content than one near the end, so a contiguous run would bias the numbers).
  const ids = [];
  const all = [...content.querySelectorAll('h2')].map((h) => h.id);
  const step = Math.max(1, Math.floor(all.length / SAMPLES));
  for (let i = 0; i < all.length && ids.length < SAMPLES; i += step) ids.push(all[i]);

  const fold = { click: [], gap: [], gbcr: [] }, unfold = { click: [], gap: [], gbcr: [] };
  for (const id of ids) {
    window.scrollTo(0, 0);
    window.dispatchEvent(new Event('scroll'));
    await raf();
    const f = await toggle(id);   // fold
    const u = await toggle(id);   // unfold again, so every sample starts equal
    for (const k of ['click', 'gap', 'gbcr']) { fold[k].push(f[k]); unfold[k].push(u[k]); }
  }
  report('samples=' + ids.length
    + ' fold: click=' + ms(median(fold.click)) + 'ms gap=' + ms(median(fold.gap)) + 'ms gbcr=' + median(fold.gbcr)
    + ' | unfold: click=' + ms(median(unfold.click)) + 'ms gap=' + ms(median(unfold.gap)) + 'ms gbcr=' + median(unfold.gbcr)
    + ' | blocks=' + document.getElementById('content').children.length
    + ' lines=' + content.querySelectorAll('[data-line]').length
    + ' headings=' + content.querySelectorAll('h1,h2,h3').length
    + ' scrollHeight=' + document.documentElement.scrollHeight);
}
run();
`;

runPage(buildPage(driver), { profile: flag('--profile'), name: 'fold-bench' });
