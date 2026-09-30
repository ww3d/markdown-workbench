#!/usr/bin/env node
// Editor-side table benchmark: the pure table model on one generated table.
//
// Reports what a keystroke in a large table costs in the extension host:
//
//   findTable    - building the table from the cached block parse
//   findTable new - the same on a new document version: one block parse of the
//                  whole document with the preview's markdown-it (Enter/Tab
//                  after an edit)
//   inTable hit  - the selection-change context key with the span cached
//   inTable miss - the same after an edit the cache cannot carry over
//   distribute   - aligning with padded columns (display width per grapheme)
//   consolidate  - aligning compactly (must not measure widths)
//   autoFormat   - what Enter/Tab run: distribute plus the maxAlignedWidth check
//
// Usage:
//   node bench/table-bench.js                 # 10000 rows, ASCII cells
//   node bench/table-bench.js --rows 5000     # other size
//   node bench/table-bench.js --cjk           # CJK and emoji cells
//
// Numbers are relative and machine-dependent; compare a change against its
// baseline on the same machine, not against an absolute target.

import { findTable, inTableAt, linesDoc } from '../src/tables/detect.ts';
import { toGrid, formatGrid, autoFormat } from '../src/tables/format.ts';

const arg = (name, dflt) => {
  const i = process.argv.indexOf(name);
  return i < 0 ? dflt : Number(process.argv[i + 1]);
};
const rows = arg('--rows', 10000);
const cjk = process.argv.includes('--cjk');

const cell = (r, c) => (cjk ? `漢字${r}😀${c}` : `cell ${r}.${c}`);
const lines = ['| a | b | c | d |', '|---|---|---|---|'];
for (let r = 0; r < rows; r++)
  lines.push(
    `| ${cell(r, 0)} | ${cell(r, 1)} | ${cell(r, 2)} | ${cell(r, 3)} |`,
  );

// Median of `runs` timed calls after one warm-up call.
function time(label, runs, fn) {
  fn();
  const ms = [];
  for (let i = 0; i < runs; i++) {
    const t0 = process.hrtime.bigint();
    fn();
    ms.push(Number(process.hrtime.bigint() - t0) / 1e6);
  }
  ms.sort((a, b) => a - b);
  const median = ms[runs >> 1];
  console.log(`${label.padEnd(14)} ${median.toFixed(3).padStart(10)} ms`);
}

const doc = { ...linesDoc(lines), version: 1 };
const last = lines.length - 1;
console.log(`${rows} rows${cjk ? ', CJK/emoji' : ''}`);
time('findTable', 21, () => findTable(doc, last));
time('findTable new', 21, () => {
  doc.version++;
  findTable(doc, last);
});
time('inTable hit', 1001, () => inTableAt(doc, last));
time('inTable miss', 21, () => {
  doc.version++;
  inTableAt(doc, last);
});
const grid = toGrid(findTable(doc, last));
time('distribute', 7, () => formatGrid(grid, { mode: 'distribute' }));
time('consolidate', 7, () => formatGrid(grid, { mode: 'consolidate' }));
time('autoFormat', 7, () => autoFormat(grid, { maxWidth: 100 }));
