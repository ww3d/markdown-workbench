// Guard scenario (docs/DECISIONS.md #48): drives a clipboard diff the way a
// user would - typing fast in the candidate, with editor.formatOnSave on,
// across a swap, closing with and without a change, leaving one diff open for
// a restart - and records every way the clipboard text could reach the disk:
//
// - backups: a file under <user-data-dir>/Backups/**/<scheme>/
// - dirty: a page that stays unsaved for DIRTY_LIMIT_MS (the backup tracker
//   writes after ~1000 ms; the extension-development host keeps its backups in
//   memory only, so there this is the signal)
// - writes/logs: a node:fs write or console line in this process with the text
// - files: any file under the profile, the workspace or the temp directory
//   that contains the text afterwards
//
// It takes the vscode API as a parameter, so the same scenario runs in the
// test host (suite/guard.int.ts) and in a normal window through the driver
// extension (driver/extension.ts).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import type * as vscode from 'vscode';

/** The vscode API object the scenario is driven with. */
type Vscode = typeof vscode;

/** The profile and workspace directories of the run. */
interface ScenarioEnv {
  userDataDir: string;
  workspace: string;
}

/** What a phase reports: hit lists (all empty when the promise holds) and measurements. */
interface GuardResult {
  hits: Record<string, string[]>;
  measurements: Record<string, unknown>;
}

/** The bookkeeping `typeFast` shares with the save listener. */
interface SaveLog {
  pending: number[];
  latencies: number[];
}

/** A tab whose input is a text diff. */
type DiffTab = vscode.Tab & { readonly input: vscode.TabInputTextDiff };

const SCHEME = 'markdown-workbench-clipboard';
/** A page unsaved this long counts as exposed to VS Code's backup (~1000 ms). */
const DIRTY_LIMIT_MS = 800;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function markerFor(userDataDir: string): string {
  return `mdwb-guard-${path.basename(userDataDir)}`;
}

function clipFor(marker: string): string {
  return `## Usage\n\nRun the command ${marker} and read the output.\n`;
}

async function waitFor<T>(
  cond: () => T | PromiseLike<T>,
  label: string,
  timeout = 8000,
): Promise<NonNullable<Awaited<T>>> {
  const until = Date.now() + timeout;
  for (;;) {
    const v = await cond();
    if (v) return v;
    if (Date.now() > until) throw new Error(`timed out waiting for ${label}`);
    await sleep(25);
  }
}

function backupRoot(userDataDir: string): string {
  return path.join(userDataDir, 'Backups');
}

function schemeBackups(userDataDir: string): string[] {
  const root = backupRoot(userDataDir);
  if (!fs.existsSync(root)) return [];
  return fs
    .readdirSync(root, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.join(e.parentPath, e.name))
    .filter((f) => f.split(path.sep).includes(SCHEME));
}

// Files (< 5 MB, changed since `since`) under `dir` whose content has `marker`.
function filesWithMarker(
  dir: string,
  marker: string,
  since: number,
  skip: string[] = [],
): string[] {
  const out: string[] = [];
  if (!fs.existsSync(dir)) return out;
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { recursive: true, withFileTypes: true });
  } catch {
    return out; // an unreadable temp tree of another process: nothing of ours
  }
  for (const e of entries) {
    if (!e.isFile()) continue;
    const full = path.join(e.parentPath, e.name);
    if (skip.some((s) => full.startsWith(s))) continue;
    try {
      const st = fs.statSync(full);
      if (st.mtimeMs < since || st.size > 5 * 1024 * 1024) continue;
      if (fs.readFileSync(full).includes(marker)) out.push(full);
    } catch {
      // vanished or unreadable while scanning: not a file this run left behind
    }
  }
  return out;
}

// Watches the profile's backups and the pages' dirty state; spies on the
// writing node:fs functions and the console of this process.
function startWatch(
  vscode: Vscode,
  { userDataDir, marker }: { userDataDir: string; marker: string },
) {
  const backups = new Set<string>();
  const dirty: string[] = [];
  const writes: string[] = [];
  const logs: string[] = [];
  const hits = { backups, dirty, writes, logs };
  const dirtySince = new Map<string, number>();
  const poll = setInterval(() => {
    for (const f of schemeBackups(userDataDir)) hits.backups.add(f);
    const now = Date.now();
    for (const doc of vscode.workspace.textDocuments) {
      if (doc.uri.scheme !== SCHEME) continue;
      const key = doc.uri.toString();
      if (!doc.isDirty) {
        dirtySince.delete(key);
        continue;
      }
      const since = dirtySince.get(key) ?? now;
      dirtySince.set(key, since);
      if (now - since >= DIRTY_LIMIT_MS && !hits.dirty.includes(key))
        hits.dirty.push(key);
    }
  }, 50);
  const restore: (() => void)[] = [];
  const carries = (args: unknown[]) =>
    args.some((a) =>
      (Buffer.isBuffer(a) || a instanceof Uint8Array
        ? Buffer.from(a).toString()
        : String(a)
      ).includes(marker),
    );
  const wrap = (obj: object, name: string, label: string, list: string[]) => {
    const orig: unknown = Reflect.get(obj, name);
    if (typeof orig !== 'function') return;
    Reflect.set(obj, name, function (this: unknown, ...args: unknown[]) {
      if (carries(args)) list.push(`${label}(${String(args[0])})`);
      return Reflect.apply(orig, this, args);
    });
    restore.push(() => {
      Reflect.set(obj, name, orig);
    });
  };
  for (const n of [
    'writeFile',
    'writeFileSync',
    'appendFile',
    'appendFileSync',
    'write',
    'writeSync',
  ]) {
    wrap(fs, n, `fs.${n}`, hits.writes);
  }
  for (const n of ['writeFile', 'appendFile'])
    wrap(fs.promises, n, `fs.promises.${n}`, hits.writes);
  for (const n of ['log', 'info', 'warn', 'error', 'debug', 'trace'])
    wrap(console, n, `console.${n}`, hits.logs);
  return {
    hits,
    stop() {
      clearInterval(poll);
      for (const r of restore) r();
      for (const f of schemeBackups(userDataDir)) hits.backups.add(f);
    },
  };
}

function isDiffTab(tab: vscode.Tab, vscode: Vscode): tab is DiffTab {
  return tab.input instanceof vscode.TabInputTextDiff;
}

// Any tab input that carries a `uri` (text, custom, notebook ...).
function hasUri(input: unknown): input is { uri: vscode.Uri } {
  return (
    typeof input === 'object' &&
    input !== null &&
    'uri' in input &&
    Boolean(input.uri)
  );
}

function helpers(vscode: Vscode, workspace: string) {
  const editorOf = (uri: vscode.Uri) =>
    vscode.window.visibleTextEditors.find(
      (e) => e.document.uri.toString() === uri.toString(),
    );
  const clipboardDiffTab = () =>
    vscode.window.tabGroups.all
      .flatMap((g) => g.tabs)
      .filter((t) => isDiffTab(t, vscode))
      .find(
        (t) =>
          t.input.original.scheme === SCHEME ||
          t.input.modified.scheme === SCHEME,
      );
  return {
    editorOf,
    async openFixture(name: string) {
      const doc = await vscode.workspace.openTextDocument(
        vscode.Uri.file(path.join(workspace, name)),
      );
      return vscode.window.showTextDocument(doc, {
        preview: false,
        selection: new vscode.Range(0, 0, 0, 0),
      });
    },
    async compare(clip: string) {
      await vscode.env.clipboard.writeText(clip);
      const before = clipboardDiffTab();
      await vscode.commands.executeCommand(
        'markdownWorkbench.compareWithClipboard',
      );
      const tab = await waitFor(() => {
        const t = clipboardDiffTab();
        return t && t !== before ? t : undefined;
      }, 'the clipboard diff tab');
      return tab.input.modified;
    },
    async typeFast(
      uri: vscode.Uri,
      count: number,
      gapMs: number,
      saves: SaveLog,
    ) {
      for (let i = 0; i < count; i++) {
        const editor = await waitFor(
          () => editorOf(uri),
          'the candidate editor',
        );
        const at = editor.document.lineAt(2).range.end;
        saves.pending.push(Date.now());
        await editor.edit((b) => b.insert(at, 'x'));
        await sleep(gapMs);
      }
    },
  };
}

/**
 * Main phase. `env`: { userDataDir, workspace }. Returns { hits, measurements }
 * with every hit list empty when the promise holds.
 */
async function runMain(
  vscode: Vscode,
  { userDataDir, workspace }: ScenarioEnv,
): Promise<GuardResult> {
  const marker = markerFor(userDataDir);
  const clip = clipFor(marker);
  const since = Date.now() - 1000;
  const h = helpers(vscode, workspace);
  const watch = startWatch(vscode, { userDataDir, marker });
  const saves: SaveLog = { pending: [], latencies: [] };
  const saveSub = vscode.workspace.onDidSaveTextDocument((d) => {
    if (d.uri.scheme !== SCHEME) return;
    const t = saves.pending.shift();
    if (t) saves.latencies.push(Date.now() - t);
  });
  const config = vscode.workspace.getConfiguration('editor');
  try {
    await h.openFixture('notes.md');
    const candidate = await h.compare(clip);
    await h.typeFast(candidate, 30, 60, saves); // ~1.8 s of typing, longer than the backup delay
    await sleep(2500);
    await config.update(
      'formatOnSave',
      true,
      vscode.ConfigurationTarget.Global,
    );
    await h.typeFast(candidate, 15, 60, saves);
    await sleep(2500);
    await vscode.commands.executeCommand('markdownWorkbench.swapDiffSides');
    await sleep(300);
    await h.typeFast(candidate, 15, 60, saves);
    await sleep(2500);
    await h.typeFast(candidate, 3, 60, saves);
    await sleep(200);
    await vscode.commands.executeCommand('workbench.action.closeActiveEditor'); // with a change
    await h.openFixture('notes.md');
    await h.compare(clip);
    await vscode.commands.executeCommand('workbench.action.closeActiveEditor'); // without a change
    await sleep(2500);
    await h.openFixture('notes.md');
    const kept = await h.compare(clip); // stays open for the restart
    await h.typeFast(kept, 5, 60, saves);
    await sleep(2500);
  } finally {
    saveSub.dispose();
    watch.stop();
    await config.update(
      'formatOnSave',
      undefined,
      vscode.ConfigurationTarget.Global,
    );
  }
  const lat = saves.latencies.sort((a, b) => a - b);
  const skip = [path.join(userDataDir, 'CachedData')];
  return {
    hits: {
      backups: [...watch.hits.backups],
      dirty: watch.hits.dirty,
      writes: watch.hits.writes,
      logs: watch.hits.logs,
      files: [
        ...filesWithMarker(userDataDir, marker, since, skip),
        ...filesWithMarker(workspace, marker, since),
        ...filesWithMarker(os.tmpdir(), marker, since, [
          userDataDir,
          workspace,
        ]),
      ],
    },
    measurements: {
      saveLatencyMs: {
        saves: lat.length,
        median: lat[Math.floor(lat.length / 2)],
        max: lat.at(-1),
      },
      backupDir: fs.existsSync(backupRoot(userDataDir))
        ? fs.readdirSync(backupRoot(userDataDir), { recursive: true })
        : [],
    },
  };
}

/** Restart phase: the same profile opened again. Same result shape. */
async function runReload(
  vscode: Vscode,
  { userDataDir, workspace }: ScenarioEnv,
): Promise<GuardResult> {
  const marker = markerFor(userDataDir);
  const restoredTabs = () =>
    vscode.window.tabGroups.all
      .flatMap((g) => g.tabs)
      .filter((t) => {
        const i = t.input;
        const uris =
          i instanceof vscode.TabInputTextDiff
            ? [i.original, i.modified]
            : hasUri(i)
              ? [i.uri]
              : [];
        return uris.some((u) => u.scheme === SCHEME);
      });
  const atStart = restoredTabs().length;
  const backupsAtStart = schemeBackups(userDataDir);
  let closed = true;
  await waitFor(
    () => restoredTabs().length === 0,
    'restored clipboard pages to be closed',
  ).catch(() => {
    closed = false;
  });
  const skip = [path.join(userDataDir, 'CachedData')];
  return {
    hits: {
      backups: [...new Set([...backupsAtStart, ...schemeBackups(userDataDir)])],
      restoredPagesLeftOpen: closed ? [] : restoredTabs().map((t) => t.label),
      files: [
        ...filesWithMarker(userDataDir, marker, 0, skip),
        ...filesWithMarker(workspace, marker, 0),
      ],
    },
    measurements: {
      restoredClipboardTabsAtStart: atStart,
      backupDir: fs.existsSync(backupRoot(userDataDir))
        ? fs.readdirSync(backupRoot(userDataDir), { recursive: true })
        : [],
    },
  };
}

export { runMain, runReload, schemeBackups, DIRTY_LIMIT_MS, SCHEME };
export type { GuardResult, ScenarioEnv };
