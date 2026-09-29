// Shared pieces of the integration cases: the case registry, measurements and
// helpers that drive the real VS Code (open a fixture, compare with a given
// clipboard text, find the diff tab, wait for a condition, reset editors).

import path from 'node:path';
import * as vscode from 'vscode';

const SCHEME = 'markdown-workbench-clipboard';
const cases = [];
const measurements = {};

/**
 * Registers a case; `phases` defaults to the main launch only. `keepEditors`
 * leaves the editors open after the case (for the reload phase).
 */
function test(name, fn, { phases = ['main'], keepEditors = false } = {}) {
  cases.push({ name, fn, phases, keepEditors });
}

/** Adds a measurement under `key` (reported per VS Code version). */
function measure(key, value) {
  measurements[key] = value;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Polls `cond` every 25 ms until it is truthy; throws after `timeout` ms. */
async function waitFor(cond, label, timeout = 5000) {
  const until = Date.now() + timeout;
  for (;;) {
    const v = await cond();
    if (v) return v;
    if (Date.now() > until) throw new Error(`timed out waiting for ${label}`);
    await sleep(25);
  }
}

function workspaceFile(name) {
  return vscode.Uri.file(path.join(process.env.MDWB_WORKSPACE, name));
}

/**
 * Opens a fixture file of the workspace copy as the active editor, with
 * `selection` or an empty cursor at the start (VS Code would otherwise restore
 * the selection an earlier case left, which changes the baseline choice).
 */
async function openFixture(name, selection = new vscode.Range(0, 0, 0, 0)) {
  const doc = await vscode.workspace.openTextDocument(workspaceFile(name));
  return vscode.window.showTextDocument(doc, { preview: false, selection });
}

/** Every tab whose input is a text diff. */
function diffTabs() {
  return vscode.window.tabGroups.all
    .flatMap((g) => g.tabs)
    .filter((t) => t.input instanceof vscode.TabInputTextDiff);
}

/** The diff tab showing a clipboard-diff candidate, if any. */
function clipboardDiffTab() {
  return diffTabs().find(
    (t) =>
      t.input.original.scheme === SCHEME || t.input.modified.scheme === SCHEME,
  );
}

/**
 * Puts `clip` on the clipboard, runs Compare with Clipboard and waits for the
 * diff. Returns { tab, candidateUri, baselineUri }.
 */
async function compare(
  clip,
  command = 'markdownWorkbench.compareWithClipboard',
) {
  await vscode.env.clipboard.writeText(clip);
  const before = clipboardDiffTab();
  await vscode.commands.executeCommand(command);
  const tab = await waitFor(() => {
    const t = clipboardDiffTab();
    return t && t !== before ? t : undefined;
  }, 'the clipboard diff tab');
  return {
    tab,
    candidateUri: tab.input.modified,
    baselineUri: tab.input.original,
  };
}

/** The visible text editor of `uri`. */
function editorOf(uri) {
  return vscode.window.visibleTextEditors.find(
    (e) => e.document.uri.toString() === uri.toString(),
  );
}

/**
 * Reverts every dirty document and closes all editors, so no save prompt can
 * block the run (a dirty page only occurs when the immediate save is off, as
 * in the mutation probe). The clipboard-diff tabs close before the files are
 * reverted: while a diff lives, a reverted file is mirrored into its page, and
 * reverting that page again would write the old text back into the file.
 */
async function resetEditors() {
  await revertDirty(SCHEME);
  const pageTabs = vscode.window.tabGroups.all
    .flatMap((g) => g.tabs)
    .filter((t) =>
      [t.input?.original, t.input?.modified, t.input?.uri].some(
        (u) => u?.scheme === SCHEME,
      ),
    );
  const pages = pageTabs.flatMap((t) =>
    [t.input.original, t.input.modified, t.input.uri].filter(
      (u) => u?.scheme === SCHEME,
    ),
  );
  if (pageTabs.length) await vscode.window.tabGroups.close(pageTabs);
  // The extension releases a closed diff's pages from its store; then the
  // diff no longer mirrors (closed documents linger in textDocuments).
  await waitFor(async () => {
    const left = await Promise.all(
      pages.map((u) =>
        vscode.workspace.fs.stat(u).then(
          () => true,
          () => false,
        ),
      ),
    );
    return !left.includes(true);
  }, 'the clipboard pages to be released');
  await revertDirty('file');
  await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  await sleep(100);
}

async function revertDirty(scheme) {
  for (const doc of vscode.workspace.textDocuments) {
    if (doc.isDirty && doc.uri.scheme === scheme) {
      await vscode.window.showTextDocument(doc, { preview: false });
      await vscode.commands.executeCommand('workbench.action.files.revert');
    }
  }
}

export {
  SCHEME,
  cases,
  measurements,
  test,
  measure,
  sleep,
  waitFor,
  workspaceFile,
  openFixture,
  diffTabs,
  clipboardDiffTab,
  compare,
  editorOf,
  resetEditors,
};
