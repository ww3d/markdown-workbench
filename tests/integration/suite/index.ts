// Test entry VS Code loads in the extension host (extensionTestsPath). A small
// runner instead of Mocha (docs/DECISIONS.md #21, #48): it loads the *.int.ts
// files of this folder for the current phase, runs their cases in order with
// node:assert, and writes the results plus the measurements to
// MDWB_RESULT_FILE for tests/integration/run.ts to report.
//
// run.ts bundles this entry before the launch (the minimum VS Code runs a Node
// without type stripping), so the case files are listed here for the bundler
// instead of being read from the folder at run time.

import fs from 'node:fs';
import * as vscode from 'vscode';
import * as harness from './harness.ts';
import { requireEnv } from '../env.ts';

// Case files by name (MDWB_ONLY picks one); each registers its cases on load.
const SUITES: Record<string, () => Promise<unknown>> = {
  diff: () => import('./diff.int.ts'),
  guard: () => import('./guard.int.ts'),
  hints: () => import('./hints.int.ts'),
  saveas: () => import('./saveas.int.ts'),
  saving: () => import('./saving.int.ts'),
};

async function run() {
  const phase = process.env.MDWB_PHASE || 'main';
  const only = process.env.MDWB_ONLY;
  const suites = Object.entries(SUITES)
    .filter(([name]) => !only || name === only)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  for (const [, load] of suites) await load();
  const results: {
    name: string;
    ok: boolean;
    ms: number;
    error?: string;
  }[] = [];
  // Cases that leave their editors open for the reload phase run last.
  const selected = harness.cases
    .filter((c) => c.phases.includes(phase))
    .sort((a, b) => Number(a.keepEditors) - Number(b.keepEditors));
  for (const t of selected) {
    const started = Date.now();
    try {
      await t.fn();
      results.push({ name: t.name, ok: true, ms: Date.now() - started });
    } catch (err) {
      results.push({
        name: t.name,
        ok: false,
        ms: Date.now() - started,
        error: (err instanceof Error && err.stack) || String(err),
      });
    }
    if (!t.keepEditors) await harness.resetEditors();
  }
  fs.writeFileSync(
    requireEnv('MDWB_RESULT_FILE'),
    JSON.stringify(
      {
        vscodeVersion: vscode.version,
        tests: results,
        measurements: harness.measurements,
      },
      null,
      2,
    ),
  );
  if (results.some((r) => !r.ok)) throw new Error('integration cases failed');
}

export { run };
