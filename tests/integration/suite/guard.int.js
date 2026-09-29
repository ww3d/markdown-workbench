// Guard test in the test host (docs/DECISIONS.md #48). Runs the shared guard
// scenario (../guard/scenario.js) and fails on any hit. The test host keeps
// VS Code's backups in memory, so here the "page stays dirty" signal and the
// write/log/file checks carry it; the backup directory itself is checked by
// the same scenario in a normal window (tests/integration/guard/driver).

import assert from 'node:assert';
import * as vscode from 'vscode';
import * as h from './harness.js';
import { runMain, runReload } from '../guard/scenario.js';

function env() {
  return {
    userDataDir: process.env.MDWB_USER_DATA_DIR,
    workspace: process.env.MDWB_WORKSPACE,
  };
}

function assertNoHits(result) {
  for (const [kind, list] of Object.entries(result.hits)) {
    assert.deepStrictEqual(list, [], `guard hit: ${kind}`);
  }
}

h.test(
  'guard: no dirty page, write, log or file with the clipboard text while editing, formatting, swapping, closing',
  async () => {
    const result = await runMain(vscode, env());
    h.measure('guardMain', result.measurements);
    assertNoHits(result);
  },
  { keepEditors: true },
);

h.test(
  'guard after reload: no restored clipboard page, no file with the text',
  async () => {
    const result = await runReload(vscode, env());
    h.measure('guardReload', result.measurements);
    assertNoHits(result);
  },
  { phases: ['reload'] },
);
