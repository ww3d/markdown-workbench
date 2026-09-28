// Test-only driver extension (never published): in a normal VS Code window -
// not an extension-development host, which keeps backups in memory - it runs
// the guard scenario named by MDWB_GUARD_SCENARIO for MDWB_DRIVER_PHASE,
// writes the result to MDWB_RESULT_FILE and quits VS Code. Without those
// variables it does nothing.

const fs = require('node:fs');
const vscode = require('vscode');

async function activate() {
  const phase = process.env.MDWB_DRIVER_PHASE;
  if (!phase) return;
  let result;
  try {
    const scenario = require(process.env.MDWB_GUARD_SCENARIO);
    const run = phase === 'reload' ? scenario.runReload : scenario.runMain;
    result = await run(vscode, {
      userDataDir: process.env.MDWB_USER_DATA_DIR,
      workspace: process.env.MDWB_WORKSPACE,
    });
  } catch (err) {
    result = { error: err?.stack || String(err) };
  }
  fs.writeFileSync(
    process.env.MDWB_RESULT_FILE,
    JSON.stringify({ vscodeVersion: vscode.version, ...result }),
  );
  await vscode.commands.executeCommand('workbench.action.quit');
}

module.exports = { activate, deactivate: () => {} };
