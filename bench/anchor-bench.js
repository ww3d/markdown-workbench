#!/usr/bin/env node
// Section-anchor benchmark (docs/DECISIONS.md #48): times findAnchor on a
// generated baseline for a heading-led candidate and for a lines candidate from
// the middle of the file with two changed lines. Reports medians over
// --iterations runs after one warm-up. Plain Node, no browser.
//
// Usage:
//   node bench/anchor-bench.js                      # 10 000 lines, 21 runs
//   node bench/anchor-bench.js --lines 50000 --iterations 11
//
// Target from the design round: < 100 ms at 10 000 lines. Numbers are
// machine-dependent; compare against a baseline on the same machine.

import { findAnchor } from '../src/clipboard-diff/anchor.js';

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const i = args.indexOf(name);
  return i === -1 ? dflt : Number(args[i + 1]);
};
const LINES = opt('--lines', 10000);
const ITERATIONS = opt('--iterations', 21);

const lines = [];
for (let i = 0; i < LINES; i++)
  lines.push(`Baseline content line number ${i} with some words.`);
for (let i = 0; i < LINES; i += 100) lines[i] = `## Section ${i / 100}`;
const baseline = lines.join('\n');

const mid = Math.floor(LINES / 2);
const snippet = lines.slice(mid + 1, mid + 21);
snippet[5] = 'CHANGED LINE FIVE';
snippet[15] = 'CHANGED LINE FIFTEEN';
const cases = {
  heading: `## Section ${Math.floor(mid / 100)}\n\nnew content\n`,
  lines: snippet.join('\n'),
};

function median(fn) {
  fn();
  const times = [];
  for (let i = 0; i < ITERATIONS; i++) {
    const start = process.hrtime.bigint();
    fn();
    times.push(Number(process.hrtime.bigint() - start) / 1e6);
  }
  times.sort((a, b) => a - b);
  return times[Math.floor(times.length / 2)];
}

console.log(
  `findAnchor, ${LINES} baseline lines, median of ${ITERATIONS} (Node ${process.version})`,
);
for (const [name, candidate] of Object.entries(cases)) {
  const result = findAnchor(baseline, candidate);
  const hit = result.matches[0];
  console.log(
    `  ${name.padEnd(8)} ${median(() => findAnchor(baseline, candidate))
      .toFixed(2)
      .padStart(8)} ms` +
      `  -> lines ${hit ? `${hit.start + 1}-${hit.end}` : 'none'}, confident: ${result.confident}`,
  );
}
