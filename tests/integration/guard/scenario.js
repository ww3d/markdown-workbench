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
// test host (suite/guard.int.js) and in a normal window through the driver
// extension (driver/extension.js).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SCHEME = 'markdown-workbench-clipboard';
/** A page unsaved this long counts as exposed to VS Code's backup (~1000 ms). */
const DIRTY_LIMIT_MS = 800;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function markerFor(userDataDir) {
  return `mdwb-guard-${path.basename(userDataDir)}`;
}

function clipFor(marker) {
  return `## Usage\n\nRun the command ${marker} and read the output.\n`;
}

async function waitFor(cond, label, timeout = 8000) {
  const until = Date.now() + timeout;
  for (;;) {
    const v = await cond();
    if (v) return v;
    if (Date.now() > until) throw new Error(`timed out waiting for ${label}`);
    await sleep(25);
  }
}

function backupRoot(userDataDir) {
  return path.join(userDataDir, 'Backups');
}

function schemeBackups(userDataDir) {
  const root = backupRoot(userDataDir);
  if (!fs.existsSync(root)) return [];
  return fs
    .readdirSync(root, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile())
    .map((e) => path.join(e.parentPath ?? e.path, e.name))
    .filter((f) => f.split(path.sep).includes(SCHEME));
}

// Files (< 5 MB, changed since `since`) under `dir` whose content has `marker`.
function filesWithMarker(dir, marker, since, skip = []) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { recursive: true, withFileTypes: true });
  } catch {
    return out; // an unreadable temp tree of another process: nothing of ours
  }
  for (const e of entries) {
    if (!e.isFile()) continue;
    const full = path.join(e.parentPath ?? e.path, e.name);
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
function startWatch(vscode, { userDataDir, marker }) {
  const hits = { backups: new Set(), dirty: [], writes: [], logs: [] };
  const dirtySince = new Map();
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
      if (!dirtySince.has(key)) dirtySince.set(key, now);
      if (
        now - dirtySince.get(key) >= DIRTY_LIMIT_MS &&
        !hits.dirty.includes(key)
      )
        hits.dirty.push(key);
    }
  }, 50);
  const restore = [];
  const carries = (args) =>
    args.some((a) =>
      (Buffer.isBuffer(a) || a instanceof Uint8Array
        ? Buffer.from(a).toString()
        : String(a)
      ).includes(marker),
    );
  const wrap = (obj, name, label, list) => {
    const orig = obj[name];
    if (typeof orig !== 'function') return;
    obj[name] = function (...args) {
      if (carries(args)) list.push(`${label}(${String(args[0])})`);
      return orig.apply(this, args);
    };
    restore.push(() => {
      obj[name] = orig;
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

function helpers(vscode, workspace) {
  const editorOf = (uri) =>
    vscode.window.visibleTextEditors.find(
      (e) => e.document.uri.toString() === uri.toString(),
    );
  const clipboardDiffTab = () =>
    vscode.window.tabGroups.all
      .flatMap((g) => g.tabs)
      .find(
        (t) =>
          t.input instanceof vscode.TabInputTextDiff &&
          (t.input.original.scheme === SCHEME ||
            t.input.modified.scheme === SCHEME),
      );
  return {
    editorOf,
    async openFixture(name) {
      const doc = await vscode.workspace.openTextDocument(
        vscode.Uri.file(path.join(workspace, name)),
      );
      return vscode.window.showTextDocument(doc, {
        preview: false,
        selection: new vscode.Range(0, 0, 0, 0),
      });
    },
    async compare(clip) {
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
    async typeFast(uri, count, gapMs, saves) {
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
async function runMain(vscode, { userDataDir, workspace }) {
  const marker = markerFor(userDataDir);
  const clip = clipFor(marker);
  const since = Date.now() - 1000;
  const h = helpers(vscode, workspace);
  const watch = startWatch(vscode, { userDataDir, marker });
  const saves = { pending: [], latencies: [] };
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
async function runReload(vscode, { userDataDir, workspace }) {
  const marker = markerFor(userDataDir);
  const restoredTabs = () =>
    vscode.window.tabGroups.all
      .flatMap((g) => g.tabs)
      .filter((t) => {
        const i = t.input;
        const uris =
          i instanceof vscode.TabInputTextDiff
            ? [i.original, i.modified]
            : i?.uri
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
