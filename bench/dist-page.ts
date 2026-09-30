// Shared parts of the benches that run the SHIPPED webview (dist/webview.js and
// dist/webview.css, as the build and the size gate see them) instead of the bench-only
// bundle of bench/harness.ts: the page around the two files, and the run statistics.

import fs from 'node:fs';
import path from 'node:path';
import { layoutPath } from '../eng/layout.ts';
import { SKELETON, THEME } from './harness.ts';

/** Where the driver code goes, relative to the shipped script. */
export interface DistPageParts {
  /** Runs before `dist/webview.js` starts (a marker script for the load time). */
  readonly before?: string;
  /** Runs after `dist/webview.js` has run to its end; reports through `report()`. */
  readonly after?: string;
}

/**
 * The webview skeleton around the built `dist/webview.js` and `dist/webview.css`, both
 * inlined (a file:// page cannot load a nonce'd script the way the panel does, and one
 * script tag is one script tag). `acquireVsCodeApi` is the stand-in of every bench: it
 * collects posted messages in `window.__posted` and calls `window.__onPost` when set.
 * `report(text)` writes the `RESULT` line the harness polls for.
 */
export function distPage(parts: DistPageParts): string {
  const dist = layoutPath('dist');
  const js = path.join(dist, 'webview.js');
  const css = path.join(dist, 'webview.css');
  if (!fs.existsSync(js) || !fs.existsSync(css))
    throw new Error(`no ${js} or ${css}: run the build (pnpm run build) first`);
  return `<!doctype html><html><head><meta charset="utf-8"><style>:root{${THEME}}${fs.readFileSync(css, 'utf8')}</style></head><body>
${SKELETON}
<pre id="prof" style="position:fixed;bottom:0;left:0;z-index:99;background:#000;color:#0f0;font:12px monospace;padding:4px">pending</pre>
<script>
window.__posted = [];
window.__onPost = undefined;
const report = (text) => { document.getElementById('prof').textContent = 'RESULT ' + text; };
window.acquireVsCodeApi = () => ({
  postMessage(m) { window.__posted.push(m); if (window.__onPost) window.__onPost(m); },
  setState() {},
  getState() { return null; },
});
window.addEventListener('error', (e) => report('ERROR ' + (e.message || 'error')));
</script>
<script>${parts.before ?? ''}</script>
<script>${fs.readFileSync(js, 'utf8')}</script>
<script>${parts.after ?? ''}</script>
</body></html>`;
}

/** Median, minimum and maximum of a sample; the median is the element at index n >> 1. */
export interface Stats {
  readonly n: number;
  readonly median: number;
  readonly min: number;
  readonly max: number;
}

/** Statistics of a non-empty numeric sample. */
export function stats(sample: readonly number[]): Stats {
  const s = [...sample].sort((a, b) => a - b);
  return {
    n: s.length,
    median: s[s.length >> 1] ?? Number.NaN,
    min: s[0] ?? Number.NaN,
    max: s[s.length - 1] ?? Number.NaN,
  };
}

/** One line of a statistics result: `label n=21 median=1.23 min=1.00 max=2.00 unit`. */
export function formatStats(label: string, st: Stats, unit: string): string {
  const f = (x: number) => x.toFixed(2);
  return `${label} n=${st.n} median=${f(st.median)} min=${f(st.min)} max=${f(st.max)} ${unit}`;
}
