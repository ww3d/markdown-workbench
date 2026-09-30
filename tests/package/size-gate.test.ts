// The size gate against the REAL bundles in dist/ (REQ-045..047, REQ-078..080 of
// docs/tasks/92-typescript-webview.md). tests/scripts/size-gate.test.ts covers the gate's logic
// on small fixtures; only a built bundle shows that `hostFiles` still finds the chunks the
// bundler wires in, and that the shipped limits hold for what the build produces.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { hostFiles, LIMITS, measure } from '../../scripts/size-gate.ts';
import { builtDist } from '../helpers/dist.ts';

const dist = builtDist();

const gzipBytes = (file: string): number =>
  zlib.gzipSync(fs.readFileSync(file), { level: 9 }).length;

test('the built bundles are within the shipped limits', () => {
  const rows = measure(dist, LIMITS);
  assert.strictEqual(rows.length, 4, 'P1, P2 and the two raw byte limits');
  const over = rows.filter((r) => !r.ok);
  assert.deepStrictEqual(
    over.map((r) => `${r.check}: ${r.actual} > ${r.limit}`),
    [],
  );
});

test('the host code loaded on activation is more than extension.cjs alone', () => {
  // hostFiles reads the direct chunk loads from the bundle. If the bundler changes their
  // spelling the regex finds nothing, and P2 would quietly measure extension.cjs only.
  const files = hostFiles(dist);
  assert.ok(files.length >= 2, `only ${files.map((f) => path.basename(f))}`);
  assert.strictEqual(files[0], path.join(dist, 'extension.cjs'));
  for (const file of files) assert.ok(fs.existsSync(file), `${file} exists`);
  const p2 = measure(dist, LIMITS).find((r) => r.check.startsWith('P2'));
  assert.ok(p2);
  assert.ok(
    p2.actual > gzipBytes(path.join(dist, 'extension.cjs')),
    'P2 counts the chunks, not only extension.cjs',
  );
});
