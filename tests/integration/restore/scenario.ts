// Restart measurement P8 (docs/tasks/92-typescript-webview.md, REQ-054, REQ-075), run in a
// normal window by the driver extension (guard/driver): an extension-development host does
// not write its workspace storage, so it restores no editors after a restart. The main phase
// opens the side preview of a fixture and lets it render and persist its stand; the driver
// then quits VS Code, which writes the storage. The restart phase, on the same profile,
// waits for the restored preview's `ready` and counts the host renders, read from the
// extension's exports (src/extension.ts, `viewStats`).

import path from 'node:path';
import type * as vscode from 'vscode';
import type { ScenarioEnv } from '../guard/scenario.ts';

/** The vscode API object the scenario is driven with. */
type Vscode = typeof vscode;

/** What a phase reports: failed checks (empty when the phase holds) and measurements. */
interface RestoreResult {
  failures: string[];
  measurements: Record<string, unknown>;
}

/** The restart phase's inputs beyond the profile: when the runner started VS Code. */
interface RestartEnv extends ScenarioEnv {
  /** `Date.now()` of the runner right before it spawned VS Code. */
  launchedAt: number;
}

/** Render bookkeeping of one view, as the extension exports it (src/views/restore.ts). */
interface ViewStats {
  readonly documentUri: string;
  readonly renders: number;
  readonly restored: boolean;
  readonly restoredInMs: number | undefined;
}

const FIXTURE = 'restore.md';
const EXTENSION_ID = 'ww3d.markdown-workbench';
/** Past the host's highlighter wait (src/views/restore.ts, 5000 ms): a render would have gone out. */
const SETTLE_MS = 7000;
/** Shiki's start and the webview's quiet-time save (src/webview/restore/state.ts) before the quit. */
const PERSIST_MS = 5000;
const POLL_MS = 10;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function waitFor<T>(
  cond: () => T | undefined,
  label: string,
  timeout: number,
): Promise<T> {
  const until = Date.now() + timeout;
  for (;;) {
    const v = cond();
    if (v !== undefined) return v;
    if (Date.now() > until) throw new Error(`timed out waiting for ${label}`);
    await sleep(POLL_MS);
  }
}

function isViewStats(v: unknown): v is ViewStats {
  return (
    typeof v === 'object' &&
    v !== null &&
    typeof Reflect.get(v, 'documentUri') === 'string' &&
    typeof Reflect.get(v, 'renders') === 'number' &&
    typeof Reflect.get(v, 'restored') === 'boolean'
  );
}

// The fixture view's stats, once the extension is active and the view is wired.
function fixtureStats(
  vscode: Vscode,
  workspace: string,
): ViewStats | undefined {
  const ext = vscode.extensions.getExtension(EXTENSION_ID);
  if (!ext?.isActive) return undefined; // exports throws before the activation
  const exports: unknown = ext.exports;
  const all =
    typeof exports === 'object' && exports !== null
      ? Reflect.get(exports, 'viewStats')
      : undefined;
  if (!(all instanceof Set)) return undefined;
  const uri = vscode.Uri.file(path.join(workspace, FIXTURE)).toString();
  return [...all].filter(isViewStats).find((s) => s.documentUri === uri);
}

// What the window shows: every tab label per group, for a restart that restored nothing.
function tabLabels(vscode: Vscode): string[][] {
  return vscode.window.tabGroups.all.map((g) => g.tabs.map((t) => t.label));
}

/** Main phase: the side preview renders and persists its stand; the driver quits afterwards. */
async function runMain(
  vscode: Vscode,
  { workspace }: ScenarioEnv,
): Promise<RestoreResult> {
  const doc = await vscode.workspace.openTextDocument(
    vscode.Uri.file(path.join(workspace, FIXTURE)),
  );
  await vscode.window.showTextDocument(doc, { preview: false });
  await vscode.commands.executeCommand('markdownWorkbench.showPreviewToSide');
  const first = await waitFor(
    () => {
      const s = fixtureStats(vscode, workspace);
      return s && s.renders > 0 ? s : undefined;
    },
    'the first render',
    20000,
  );
  await sleep(PERSIST_MS);
  return {
    failures: [],
    measurements: {
      renders: fixtureStats(vscode, workspace)?.renders ?? first.renders,
      tabs: tabLabels(vscode),
    },
  };
}

/**
 * Restart phase: the restored preview reports `ready` with its stand, and the host renders
 * it 0 times - also past the highlighter start.
 */
async function runRestart(
  vscode: Vscode,
  { workspace, launchedAt }: RestartEnv,
): Promise<RestoreResult> {
  let stats: ViewStats;
  try {
    stats = await waitFor(
      () => {
        const s = fixtureStats(vscode, workspace);
        return s && (s.restored || s.renders > 0) ? s : undefined;
      },
      'the restored preview to report ready',
      60000,
    );
  } catch (err) {
    const ext = vscode.extensions.getExtension(EXTENSION_ID);
    return {
      failures: [err instanceof Error ? err.message : String(err)],
      measurements: { tabs: tabLabels(vscode), extensionActive: ext?.isActive },
    };
  }
  const launchToReadyMs = Date.now() - launchedAt;
  await sleep(SETTLE_MS);
  const failures: string[] = [];
  if (!stats.restored)
    failures.push('the host did not keep the restored stand');
  if (stats.restoredInMs === undefined)
    failures.push('the webview reported no restored stand');
  if (stats.renders !== 0)
    failures.push(`host renders while restoring: ${stats.renders}`);
  return {
    failures,
    measurements: {
      launchToReadyMs,
      restoredInMs: stats.restoredInMs,
      renders: stats.renders,
      restored: stats.restored,
      tabs: tabLabels(vscode),
    },
  };
}

export { runMain, runRestart };
export type { RestoreResult, RestartEnv };
