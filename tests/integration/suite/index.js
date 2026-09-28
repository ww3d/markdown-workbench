// Test entry VS Code loads in the extension host (extensionTestsPath). A small
// runner instead of Mocha (docs/DECISIONS.md #21, #48): it loads the *.int.js
// files of this folder for the current phase, runs their cases in order with
// node:assert, and writes the results plus the measurements to
// MDWB_RESULT_FILE for tests/integration/run.js to report.

const fs = require('node:fs');
const path = require('node:path');
const vscode = require('vscode');
const harness = require('./harness');

async function run() {
  const phase = process.env.MDWB_PHASE || 'main';
  const only = process.env.MDWB_ONLY;
  const files = fs
    .readdirSync(__dirname)
    .filter((f) => f.endsWith('.int.js'))
    .filter((f) => !only || f === `${only}.int.js`)
    .sort();
  for (const f of files) require(path.join(__dirname, f));
  const results = [];
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
        error: err?.stack || String(err),
      });
    }
    if (!t.keepEditors) await harness.resetEditors();
  }
  fs.writeFileSync(
    process.env.MDWB_RESULT_FILE,
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

module.exports = { run };
