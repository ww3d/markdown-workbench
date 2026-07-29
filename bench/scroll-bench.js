#!/usr/bin/env node
// Headless-Chromium scroll benchmark for the preview webview.
//
// Renders the REAL media/webview.{js,css} into a generated document, drives a
// scroll sweep in a headless Chromium, and reports wall time per frame plus the
// number of getBoundingClientRect calls per frame (a forced-layout proxy).
//
// Usage:
//   node bench/scroll-bench.js                 # 300 sections, all bars on
//   node bench/scroll-bench.js --tables 240    # add N tables (native sticky th)
//   node bench/scroll-bench.js --tables 240 --no-sticky   # stack disabled
//   node bench/scroll-bench.js --profile       # also print a CPU self-time table
//
// Numbers are relative and machine-dependent; use it to compare a change against
// its baseline on the same machine, not as an absolute target.

const { buildPage, runPage, cli } = require('./harness');

const { flag, opt } = cli(process.argv.slice(2));
const SECTIONS = Number(opt('--sections', '300'));
const TABLES = Number(opt('--tables', '0'));
const STICKY = !flag('--no-sticky');

function doc() {
  let h = '', line = 1;
  for (let s = 0; s < SECTIONS; s++) {
    h += `<h2 id="s${s}" data-line="${line++}">Section ${s}</h2>`;
    h += `<h3 id="s${s}a" data-line="${line++}">Subsection ${s}.a</h3>`;
    for (let p = 0; p < 3; p++) h += `<p data-line="${line++}">Paragraph ${s}.${p} lorem ipsum dolor sit amet consectetur.</p>`;
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
const config = {
  type: 'config', maxWidth: '980px',
  minimap: { enabled: true, side: 'right', size: 'proportional', showSlider: 'always' },
  toc: { enabled: true, mode: 'auto' }, breadcrumb: { enabled: true }, stickyScroll: { enabled: ${STICKY} }
};
async function run() {
  window.dispatchEvent(new MessageEvent('message', { data: config }));
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'render', html: DOC } }));
  await raf(); await raf();
  const maxY = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo(0, 0); window.dispatchEvent(new Event('scroll')); await raf();
  window.__gbcr = 0;
  const F = 120, t0 = performance.now();
  for (let i = 1; i <= F; i++) {
    window.scrollTo(0, Math.round(maxY * i / F));
    window.dispatchEvent(new Event('scroll'));
    await raf();
  }
  const dt = performance.now() - t0;
  report('frames=' + F + ' perFrame=' + ms(dt / F) + 'ms gbcrPerFrame=' + (window.__gbcr / F).toFixed(1)
    + ' lines=' + content.querySelectorAll('[data-line]').length
    + ' tables=' + content.querySelectorAll('table').length
    + ' scrollHeight=' + document.documentElement.scrollHeight);
}
run();
`;

runPage(buildPage(driver), { profile: flag('--profile'), name: 'scroll-bench' });
