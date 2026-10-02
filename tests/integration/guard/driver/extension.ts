// Test-only driver extension (never published): in a normal VS Code window -
// not an extension-development host, which keeps backups in memory and writes
// no workspace storage - it runs a scenario (bundled in by
// tests/integration/run.ts) for MDWB_DRIVER_PHASE, writes the result to
// MDWB_RESULT_FILE and quits VS Code. MDWB_DRIVER_SCENARIO picks the guard
// scenario (default) or the restart measurement (`restore`). Without
// MDWB_DRIVER_PHASE it does nothing.

import fs from 'node:fs';
import * as vscode from 'vscode';
import * as scenario from '../scenario.ts';
import * as restore from '../../restore/scenario.ts';
import { requireEnv } from '../../env.ts';

type Result =
  | Partial<scenario.GuardResult>
  | restore.RestoreResult
  | { error: string };

function runPhase(phase: string): Promise<Result> {
  const env = {
    userDataDir: requireEnv('MDWB_USER_DATA_DIR'),
    workspace: requireEnv('MDWB_WORKSPACE'),
  };
  if (process.env.MDWB_DRIVER_SCENARIO === 'restore') {
    return phase === 'restart'
      ? restore.runRestart(vscode, {
          ...env,
          launchedAt: Number(requireEnv('MDWB_LAUNCHED_AT')),
        })
      : restore.runMain(vscode, env);
  }
  const run = phase === 'reload' ? scenario.runReload : scenario.runMain;
  return run(vscode, env);
}

async function activate(): Promise<void> {
  const phase = process.env.MDWB_DRIVER_PHASE;
  if (!phase) return;
  let result: Result;
  try {
    result = await runPhase(phase);
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
