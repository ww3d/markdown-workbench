#!/usr/bin/env node
// Load-time benchmark of the shipped webview script (REQ-076/077 of docs/tasks/92-typescript-webview.md).
//
// Measures how long dist/webview.js takes from the start of its script to the `ready`
// message: a marker script placed right before it records `performance.now()`, the
// stand-in of `acquireVsCodeApi` records it again when the webview posts `ready`, and
// the page reports the difference (`load`). That covers parse, compile, top-level run
// and the module setup, and nothing before the script. Each run is a fresh Chromium
// with a fresh page; the result is the median of --runs runs (21 by default).
//
// The same run reads the CDP metric `Performance.getMetrics` `ScriptDuration` (seconds
// the page spent in script, converted to ms) as a cross-check (`cdp`). `load` is the
// headline number: it is the span the requirement asks for and stays bounded by the two
// markers, whereas `ScriptDuration` also counts the marker scripts, the stand-in and the
// reporting call, and is only sampled after the fact. Both are printed so a
// disagreement shows.
//
// It runs dist/webview.js and dist/webview.css, so build first (`pnpm run build`).
//
// Usage:
//   node bench/load-bench.ts                # 21 runs
//   node bench/load-bench.ts --runs 5

import { distPage, formatStats, stats } from './dist-page.ts';
import { cli, runPage } from './harness.ts';

const { opt } = cli(process.argv.slice(2));
const RUNS = Number(opt('--runs', '21'));

const before = `
window.__t0 = performance.now();
window.__onPost = (m) => {
  if (m && m.type === 'ready' && !window.__ready) {
    window.__ready = true;
    report('load=' + (performance.now() - window.__t0).toFixed(3));
  }
};`;

const page = distPage({ before });
const loads: number[] = [];
const cdp: number[] = [];
for (let i = 0; i < RUNS; i++) {
  const { text, metrics } = await runPage(page, {
    name: 'load-bench',
    quiet: true,
    metrics: true,
  });
  const m = /load=([\d.]+)/.exec(text);
  if (!m) {
    console.error(`run ${i + 1} failed: ${text || '(no result)'}`);
    process.exit(1);
  }
  loads.push(Number(m[1]));
  cdp.push((metrics.ScriptDuration ?? Number.NaN) * 1000);
}
console.log(formatStats('P9 load (script start to ready)', stats(loads), 'ms'));
console.log(
  formatStats('   cdp ScriptDuration (cross-check)', stats(cdp), 'ms'),
);
