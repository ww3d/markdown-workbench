// Clipboard diff: wires the commands, the in-memory file system, the page
// lifecycle and the candidate hints into VS Code (docs/DECISIONS.md #48,
// docs/ARCHITECTURE.md "Clipboard diff").

import * as vscode from 'vscode';
import { CandidateStore, SCHEME } from './store.js';
import { ClipboardDiffSessions } from './session.js';
import { ClipboardHistory, previewOf } from './history.js';
import { compareWithText } from './compare.js';
import { applyCandidate } from './apply.js';
import { CandidateDiagnostics } from './diagnostics.js';
import { styleProfile, alignStyle } from './style.js';

const SWAP_COMMAND = 'workbench.action.compareEditor.swapSides';
/** How long a swap may take before it counts as not done. */
const SWAP_CHECK_MS = 1000;
const CONTEXT_ACTIVE = 'markdownWorkbench.clipboardDiffActive';
const CONTEXT_STYLED = 'markdownWorkbench.candidateStyleAligned';

let active = null; // { sessions, history, diagnostics } while activated

/** Registers the clipboard diff; its disposables go into `context.subscriptions`. */
function registerClipboardDiff(context) {
  const store = new CandidateStore();
  const sessions = new ClipboardDiffSessions(store);
  const history = new ClipboardHistory();
  const diagnostics = new CandidateDiagnostics(sessions);
  active = { sessions, history, diagnostics };
  sessions.onChanged = (s) => diagnostics.schedule(s);

  const reg = (id, fn) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  context.subscriptions.push(
    vscode.workspace.registerFileSystemProvider(SCHEME, store, {
      isCaseSensitive: true,
    }),
    vscode.workspace.onDidChangeTextDocument((e) => sessions.handleChange(e)),
    vscode.window.tabGroups.onDidChangeTabs(() =>
      onTabsChanged(sessions, diagnostics),
    ),
    vscode.window.onDidChangeActiveTextEditor(() => updateContext(sessions)),
    ...sessions.saver.register(),
    diagnostics.register(),
    diagnostics,
    sessions,
  );

  reg('markdownWorkbench.compareWithClipboard', async () => {
    const text = await vscode.env.clipboard.readText();
    history.add(text);
    return openDiff(sessions, diagnostics, text);
  });
  reg('markdownWorkbench.compareWithEarlierClipboard', () =>
    compareWithEarlier(sessions, diagnostics, history),
  );
  reg('markdownWorkbench.swapDiffSides', swapDiffSides);
  reg('markdownWorkbench.applyCandidate', () => applyCandidate(sessions));
  reg('markdownWorkbench.alignCandidateStyle', () =>
    setCandidateStyle(sessions, true),
  );
  reg('markdownWorkbench.showRawCandidate', () =>
    setCandidateStyle(sessions, false),
  );

  closeRestoredPages();
  return active;
}

async function openDiff(sessions, diagnostics, text) {
  const session = await compareWithText(sessions, text);
  if (session) {
    updateContext(sessions);
    await diagnostics.update(session);
  }
  return session;
}

async function compareWithEarlier(sessions, diagnostics, history) {
  const entries = history.list();
  if (!entries.length) {
    vscode.window.showInformationMessage(
      'No clipboard text was compared in this session yet.',
    );
    return undefined;
  }
  const pick = await vscode.window.showQuickPick(
    entries.map((e) => ({
      label: previewOf(e.text) || '(blank)',
      description: new Date(e.time).toLocaleTimeString(),
      detail: `${e.text.split(/\r\n|\r|\n/).length} lines`,
      entry: e,
    })),
    { placeHolder: 'Compare with an earlier clipboard text' },
  );
  return pick ? openDiff(sessions, diagnostics, pick.entry.text) : undefined;
}

/**
 * Swaps the sides of the active text diff through VS Code's own command, for
 * this extension's diffs and any other. VS Code's command returns silently
 * when it cannot reopen a side, so the tab is checked afterwards; every
 * failure is reported, none thrown.
 */
async function swapDiffSides() {
  const tab = vscode.window.tabGroups.activeTabGroup?.activeTab;
  const input = tab?.input;
  if (!(input instanceof vscode.TabInputTextDiff)) {
    vscode.window.showInformationMessage(
      'Swap Diff Sides needs an active text diff.',
    );
    return false;
  }
  try {
    await vscode.commands.executeCommand(SWAP_COMMAND);
  } catch (err) {
    vscode.window.showErrorMessage(
      `Markdown Workbench could not swap the diff sides: ${err?.message || err}`,
    );
    return false;
  }
  if (!(await swapped(input))) {
    vscode.window.showWarningMessage(
      'VS Code did not swap this diff: its sides cannot be reopened in swapped order.',
    );
    return false;
  }
  return true;
}

// True once a diff tab shows `before` with its sides swapped (VS Code
// replaces the tab asynchronously; checked for up to SWAP_CHECK_MS).
async function swapped(before) {
  const done = () =>
    vscode.window.tabGroups.all.some((g) =>
      g.tabs.some(
        (t) =>
          t.input instanceof vscode.TabInputTextDiff &&
          t.input.original.toString() === before.modified.toString() &&
          t.input.modified.toString() === before.original.toString(),
      ),
    );
  for (const until = Date.now() + SWAP_CHECK_MS; !done(); ) {
    if (Date.now() > until) return false;
    await new Promise((r) => setTimeout(r, 20));
  }
  return true;
}

// Switches the candidate between the raw clipboard text and the text aligned
// to the baseline's Markdown style; asks before discarding the user's edits.
async function setCandidateStyle(sessions, styled) {
  const session = sessions.forActiveTab();
  if (!session) {
    vscode.window.showInformationMessage(
      'The candidate style can only be switched in a clipboard diff.',
    );
    return false;
  }
  const candidate = await vscode.workspace.openTextDocument(
    session.candidateUri,
  );
  const clip = sessions.clipOf(session, candidate.getText());
  if (clip !== session.lastSetClip) {
    const discard = 'Discard Edits';
    const choice = await vscode.window.showWarningMessage(
      'The candidate was edited. Switching the style replaces it and discards the edits.',
      { modal: true },
      discard,
    );
    if (choice !== discard) return false;
  }
  const file = await sessions.fileOf(session);
  if (!file) {
    vscode.window.showInformationMessage(
      'The baseline document of this clipboard diff was closed.',
    );
    return false;
  }
  let next = session.rawClip;
  if (styled) {
    const aligned = alignStyle(session.rawClip, styleProfile(file.getText()));
    if (!aligned.changed)
      vscode.window.setStatusBarMessage(
        'Markdown Workbench: the candidate already matches the baseline style',
        3000,
      );
    next = aligned.text;
  }
  const edit = new vscode.WorkspaceEdit();
  const start = session.shape === 'page' ? 0 : session.prefix.length;
  const end =
    clip === undefined ? candidate.getText().length : start + clip.length;
  edit.replace(
    candidate.uri,
    new vscode.Range(
      candidate.positionAt(clip === undefined ? 0 : start),
      candidate.positionAt(end),
    ),
    clip === undefined ? session.prefix + next + session.suffix : next,
  );
  if (!(await sessions.applyOwn(session, 'page', edit))) {
    vscode.window.showWarningMessage(
      'Markdown Workbench could not switch the candidate style.',
    );
    return false;
  }
  session.lastSetClip = next;
  session.styled = styled;
  updateContext(sessions);
  return true;
}

function onTabsChanged(sessions, diagnostics) {
  // A swap replaces the tab in two steps; decide once the tab model settled.
  setTimeout(() => {
    for (const s of sessions.releaseClosed()) diagnostics.forget(s);
    updateContext(sessions);
  }, 0);
}

function updateContext(sessions) {
  const session = sessions.forActiveTab();
  vscode.commands.executeCommand('setContext', CONTEXT_ACTIVE, !!session);
  vscode.commands.executeCommand(
    'setContext',
    CONTEXT_STYLED,
    !!session?.styled,
  );
}

// Pages restored from an earlier window have no content any more (memory
// only): close their tabs instead of showing "file not found".
function closeRestoredPages() {
  const stale = [];
  for (const group of vscode.window.tabGroups.all) {
    for (const tab of group.tabs) {
      const input = tab.input;
      const uris =
        input instanceof vscode.TabInputTextDiff
          ? [input.original, input.modified]
          : input instanceof vscode.TabInputText
            ? [input.uri]
            : [];
      if (uris.some((u) => u.scheme === SCHEME)) stale.push(tab);
    }
  }
  if (stale.length) vscode.window.tabGroups.close(stale);
}

/** Frees every clipboard diff (extension deactivate). */
function deactivateClipboardDiff() {
  if (!active) return;
  active.sessions.dispose();
  active.history.clear();
  active = null;
}

export { registerClipboardDiff, deactivateClipboardDiff, SCHEME };
// Exported for tests only.
export const _internal = { swapDiffSides };
