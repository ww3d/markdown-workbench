// Shared pieces of the integration cases: the case registry, measurements and
// helpers that drive the real VS Code (open a fixture, compare with a given
// clipboard text, find the diff tab, wait for a condition, reset editors).

import path from 'node:path';
import * as vscode from 'vscode';
import { requireEnv } from '../env.ts';

/** A registered case. */
interface Case {
  name: string;
  fn: () => unknown;
  phases: string[];
  keepEditors: boolean;
}

/** A tab whose input is a text diff. */
type DiffTab = vscode.Tab & { readonly input: vscode.TabInputTextDiff };

const SCHEME = 'markdown-workbench-clipboard';
const cases: Case[] = [];
const measurements: Record<string, unknown> = {};

/**
 * Registers a case; `phases` defaults to the main launch only. `keepEditors`
 * leaves the editors open after the case (for the reload phase).
 */
function test(
  name: string,
  fn: () => unknown,
  {
    phases = ['main'],
    keepEditors = false,
  }: { phases?: string[]; keepEditors?: boolean } = {},
): void {
  cases.push({ name, fn, phases, keepEditors });
}

/** Adds a measurement under `key` (reported per VS Code version). */
function measure(key: string, value: unknown): void {
  measurements[key] = value;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Polls `cond` every 25 ms until it is truthy; throws after `timeout` ms. */
async function waitFor<T>(
  cond: () => T | PromiseLike<T>,
  label: string,
  timeout = 5000,
): Promise<NonNullable<Awaited<T>>> {
  const until = Date.now() + timeout;
  for (;;) {
    const v = await cond();
    if (v) return v;
    if (Date.now() > until) throw new Error(`timed out waiting for ${label}`);
    await sleep(25);
  }
}

/** `value`, or a thrown error naming what the case expected to find. */
function found<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`${what} not found`);
  return value;
}

function workspaceFile(name: string): vscode.Uri {
  return vscode.Uri.file(path.join(requireEnv('MDWB_WORKSPACE'), name));
}

/**
 * Opens a fixture file of the workspace copy as the active editor, with
 * `selection` or an empty cursor at the start (VS Code would otherwise restore
 * the selection an earlier case left, which changes the baseline choice).
 */
async function openFixture(
  name: string,
  selection: vscode.Range = new vscode.Range(0, 0, 0, 0),
): Promise<vscode.TextEditor> {
  const doc = await vscode.workspace.openTextDocument(workspaceFile(name));
  return vscode.window.showTextDocument(doc, { preview: false, selection });
}

function isDiffTab(tab: vscode.Tab): tab is DiffTab {
  return tab.input instanceof vscode.TabInputTextDiff;
}

/** Every tab whose input is a text diff. */
function diffTabs(): DiffTab[] {
  return vscode.window.tabGroups.all.flatMap((g) => g.tabs).filter(isDiffTab);
}

/** The diff tab showing a clipboard-diff candidate, if any. */
function clipboardDiffTab(): DiffTab | undefined {
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
  clip: string,
  command = 'markdownWorkbench.compareWithClipboard',
): Promise<{
  tab: DiffTab;
  candidateUri: vscode.Uri;
  baselineUri: vscode.Uri;
}> {
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
function editorOf(uri: vscode.Uri): vscode.TextEditor | undefined {
  return vscode.window.visibleTextEditors.find(
    (e) => e.document.uri.toString() === uri.toString(),
  );
}

// The uris a tab input shows: a diff has two, a text tab (or any input with a
// `uri`) one.
function inputUris(input: unknown): vscode.Uri[] {
  if (typeof input !== 'object' || input === null) return [];
  return [
    Reflect.get(input, 'original'),
    Reflect.get(input, 'modified'),
    Reflect.get(input, 'uri'),
  ].filter((u) => u instanceof vscode.Uri);
}

/**
 * Reverts every dirty document and closes all editors, so no save prompt can
 * block the run (a dirty page only occurs when the immediate save is off, as
 * in the mutation probe). The clipboard-diff tabs close before the files are
 * reverted: while a diff lives, a reverted file is mirrored into its page, and
 * reverting that page again would write the old text back into the file.
 */
async function resetEditors(): Promise<void> {
  await revertDirty(SCHEME);
  const pageTabs = vscode.window.tabGroups.all
    .flatMap((g) => g.tabs)
    .filter((t) => inputUris(t.input).some((u) => u.scheme === SCHEME));
  const pages = pageTabs.flatMap((t) =>
    inputUris(t.input).filter((u) => u.scheme === SCHEME),
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

async function revertDirty(scheme: string): Promise<void> {
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
  found,
  workspaceFile,
  openFixture,
  diffTabs,
  clipboardDiffTab,
  compare,
  editorOf,
  resetEditors,
};
export type { Case, DiffTab };
