#!/usr/bin/env node
// Size gate (REQ-045..047, REQ-078..080 of docs/tasks/92-typescript-webview.md): measures
// the built bundles in dist/ and fails the run when one is over its limit. Run after the
// build and before the package step (eng/build.ts does both). Prints a table of measured
// value against limit for every check, so a pass shows how much room is left.
//
//   gzip:  P1 the webview delivery (webview.js + webview.css) and P2 the extension host
//          code loaded with extension.cjs (it plus every chunk it requires directly),
//          compressed at level 9 with node:zlib - what the vsix and the webview load pay for.
//   bytes: webview.js and webview.css uncompressed - what the webview parses and what
//          a reviewer can read in a diff. A raw limit never sits above the value measured
//          after the rebuild (REQ-079); raising one is a decision, not a fix.

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { layoutPath } from '../eng/layout.ts';

/** P1: gzip bytes of `webview.js` plus `webview.css`. Target of #92; never lowered to fit. */
export const P1_WEBVIEW_GZIP_MAX = 28_000;

/**
 * P2: gzip bytes of `extension.cjs` plus the chunks it requires directly, against the
 * base head 98f7590 (154 572 B, Shiki's core still inlined there) plus 2 %, rounded down.
 * The Shiki grammar and theme chunks stay out, as they did at the base (DECISIONS.md #50).
 */
export const P2_EXTENSION_GZIP_MAX = Math.floor(154_572 * 1.02);

/** Uncompressed bytes of `webview.js`; the value measured after the rebuild. */
export const WEBVIEW_JS_RAW_MAX = 29_859;

/** Uncompressed bytes of `webview.css`; the value measured after the rebuild. */
export const WEBVIEW_CSS_RAW_MAX = 15_244;

/** The limits one gate run checks; the exported constants are the shipped ones. */
export interface Limits {
  readonly webviewGzip: number;
  readonly extensionGzip: number;
  readonly webviewJsRaw: number;
  readonly webviewCssRaw: number;
}

/** The limits the build enforces. */
export const LIMITS: Limits = {
  webviewGzip: P1_WEBVIEW_GZIP_MAX,
  extensionGzip: P2_EXTENSION_GZIP_MAX,
  webviewJsRaw: WEBVIEW_JS_RAW_MAX,
  webviewCssRaw: WEBVIEW_CSS_RAW_MAX,
};

/** One row of the gate table: a measured value, its limit and the verdict. */
export interface GateRow {
  readonly check: string;
  readonly actual: number;
  readonly limit: number;
  readonly ok: boolean;
}

/**
 * The host code loaded with the bundle: `extension.cjs` and every chunk it names in a direct
 * `require("./…")`, read from the bundle itself so no chunk name list can go stale.
 */
export function hostFiles(distDir: string): readonly string[] {
  const ext = path.join(distDir, 'extension.cjs');
  const direct = fs
    .readFileSync(ext, 'utf8')
    .matchAll(/require\(\s*["']\.\/([^"']+)["']\s*\)/g);
  const chunks = new Set<string>();
  for (const [, name] of direct) if (name) chunks.add(path.join(distDir, name));
  return [ext, ...chunks];
}

/** Gzip size of a file at level 9. */
function gzipBytes(file: string): number {
  return zlib.gzipSync(fs.readFileSync(file), { level: 9 }).length;
}

/**
 * Measure the bundles in `distDir` against `limits`. A missing bundle throws: a gate that
 * skips what it cannot find would pass on an empty dist/.
 */
export function measure(
  distDir: string,
  limits: Limits = LIMITS,
): readonly GateRow[] {
  const js = path.join(distDir, 'webview.js');
  const css = path.join(distDir, 'webview.css');
  const row = (check: string, actual: number, limit: number): GateRow => ({
    check,
    actual,
    limit,
    ok: actual <= limit,
  });
  return [
    row(
      'P1 webview.js + webview.css (gzip)',
      gzipBytes(js) + gzipBytes(css),
      limits.webviewGzip,
    ),
    row(
      'P2 extension.cjs + direct requires (gzip)',
      hostFiles(distDir).reduce((sum, file) => sum + gzipBytes(file), 0),
      limits.extensionGzip,
    ),
    row('webview.js (bytes)', fs.statSync(js).size, limits.webviewJsRaw),
    row('webview.css (bytes)', fs.statSync(css).size, limits.webviewCssRaw),
  ];
}

/** The rows as a table: check, measured value, limit, verdict. */
export function formatTable(rows: readonly GateRow[]): string {
  const width = Math.max(...rows.map((r) => r.check.length));
  const lines = rows.map(
    (r) =>
      `${r.check.padEnd(width)}  ${String(r.actual).padStart(8)}  ${String(r.limit).padStart(8)}  ${r.ok ? 'ok' : 'OVER'}`,
  );
  const head = `${'check'.padEnd(width)}  ${'actual'.padStart(8)}  ${'limit'.padStart(8)}  verdict`;
  return [head, ...lines].join('\n');
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(import.meta.filename)
) {
  // An optional directory argument points the gate at another dist/ (the test fixtures).
  const rows = measure(process.argv[2] ?? layoutPath('dist'));
  console.log(formatTable(rows));
  const over = rows.filter((r) => !r.ok);
  if (over.length > 0) {
    console.error(
      `SIZE GATE FAILED: ${over.map((r) => r.check).join('; ')} over the limit`,
    );
    process.exit(1);
  }
  console.log('Size gate passed.');
}
