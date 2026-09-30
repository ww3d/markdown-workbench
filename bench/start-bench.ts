#!/usr/bin/env node
// Start benchmark of the shipped webview (P3, REQ-048/049 of docs/tasks/92-typescript-webview.md).
//
// Measures the time from the start of the page navigation until the first render is
// on screen: `performance.now()` two animation frames after the `config` and `render`
// messages of a 400-block document have been delivered. Each run is a fresh Chromium
// with a fresh page (no warm cache, no earlier document); the result is the median of
// --runs runs (21 by default), with minimum and maximum.
//
// It runs dist/webview.js and dist/webview.css, so build first (`pnpm run build`).
//
// Usage:
//   node bench/start-bench.ts               # 400 blocks, 21 runs
//   node bench/start-bench.ts --runs 5 --blocks 1200
//
// Numbers are relative and machine-dependent; compare a change against its baseline in
// the same session, not against an absolute target.

import { distPage, formatStats, stats } from './dist-page.ts';
import { cli, runPage } from './harness.ts';

const { opt } = cli(process.argv.slice(2));
const RUNS = Number(opt('--runs', '21'));
const BLOCKS = Number(opt('--blocks', '400'));

// The same document as the base measurement: a heading every sixth block, paragraphs between.
function doc(): string {
  let html = '';
  let line = 1;
  for (let i = 0; i < BLOCKS; i++) {
    if (i % 6 === 0)
      html += `<h2 id="s${i}" data-line="${line++}">Section ${i}</h2>`;
    else
      html += `<p data-line="${line++}">Paragraph ${i} lorem ipsum dolor sit amet consectetur adipiscing elit.</p>`;
  }
  return html;
}

const after = `
const HTML = ${JSON.stringify(doc())};
const raf = () => new Promise((r) => requestAnimationFrame(r));
(async () => {
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'config', maxWidth: '980px',
    minimap: { enabled: true, side: 'right', size: 'proportional', showSlider: 'always' },
    toc: { enabled: true, mode: 'auto' }, breadcrumb: { enabled: true }, stickyScroll: { enabled: true } } }));
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'render', html: HTML } }));
  await raf();
  await raf();
  report('start=' + performance.now().toFixed(2) + ' blocks=' + document.getElementById('content').children.length);
})();`;

const page = distPage({ after });
const starts: number[] = [];
for (let i = 0; i < RUNS; i++) {
  const { text } = await runPage(page, { name: 'start-bench', quiet: true });
  const m = /start=([\d.]+) blocks=(\d+)/.exec(text);
  if (!m || Number(m[2]) !== BLOCKS) {
    console.error(`run ${i + 1} failed: ${text || '(no result)'}`);
    process.exit(1);
  }
  starts.push(Number(m[1]));
}
console.log(
  `${formatStats('P3 start (navigation to first render)', stats(starts), 'ms')} blocks=${BLOCKS}`,
);
