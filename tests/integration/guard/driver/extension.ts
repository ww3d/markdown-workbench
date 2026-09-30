// Test-only driver extension (never published): in a normal VS Code window -
// not an extension-development host, which keeps backups in memory - it runs
// the guard scenario (bundled in by tests/integration/run.ts) for
// MDWB_DRIVER_PHASE, writes the result to MDWB_RESULT_FILE and quits VS Code.
// Without those variables it does nothing.

import fs from 'node:fs';
import * as vscode from 'vscode';
import * as scenario from '../scenario.ts';
import { requireEnv } from '../../env.ts';

async function activate(): Promise<void> {
  const phase = process.env.MDWB_DRIVER_PHASE;
  if (!phase) return;
  let result: Partial<scenario.GuardResult> | { error: string };
  try {
    const run = phase === 'reload' ? scenario.runReload : scenario.runMain;
    result = await run(vscode, {
      userDataDir: requireEnv('MDWB_USER_DATA_DIR'),
      workspace: requireEnv('MDWB_WORKSPACE'),
    });
  } catch (err) {
    result = { error: (err instanceof Error && err.stack) || String(err) };
  }
  fs.writeFileSync(
    requireEnv('MDWB_RESULT_FILE'),
    JSON.stringify({ vscodeVersion: vscode.version, ...result }),
  );
  await vscode.commands.executeCommand('workbench.action.quit');
}

export { activate };
export const deactivate = () => {};
