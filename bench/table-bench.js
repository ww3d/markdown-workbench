#!/usr/bin/env node
// Editor-side table benchmark: the pure table model on one generated table.
//
// Reports what a keystroke in a large table costs in the extension host:
//
//   findTable    - detecting and parsing the whole table (Enter/Tab do this once)
//   inTable hit  - the selection-change context key with the span cached
//   inTable miss - the same after an edit the cache cannot carry over
//   distribute   - aligning with padded columns (display width per grapheme)
//   consolidate  - aligning compactly (must not measure widths)
//
// Usage:
//   node bench/table-bench.js                 # 10000 rows, ASCII cells
//   node bench/table-bench.js --rows 5000     # other size
//   node bench/table-bench.js --cjk           # CJK and emoji cells
//
// Numbers are relative and machine-dependent; compare a change against its
// baseline on the same machine, not against an absolute target.

const { findTable, inTableAt, linesDoc } = require('../src/tables/detect');
const { toGrid, formatGrid } = require('../src/tables/format');

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

function time(label, runs, fn) {
  fn();
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < runs; i++) fn();
  const ms = Number(process.hrtime.bigint() - t0) / 1e6 / runs;
  console.log(`${label.padEnd(14)} ${ms.toFixed(3).padStart(10)} ms`);
}

const doc = { ...linesDoc(lines), version: 1 };
const last = lines.length - 1;
console.log(`${rows} rows${cjk ? ', CJK/emoji' : ''}`);
time('findTable', 20, () => findTable(doc, last));
time('inTable hit', 1000, () => inTableAt(doc, last));
time('inTable miss', 20, () => {
  doc.version++;
  inTableAt(doc, last);
});
const grid = toGrid(findTable(doc, last));
time('distribute', 5, () => formatGrid(grid, { mode: 'distribute' }));
time('consolidate', 5, () => formatGrid(grid, { mode: 'consolidate' }));
