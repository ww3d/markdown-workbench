// Swap Diff Sides on a Git diff in the real VS Code with the built-in Git
// extension (ww3d/markdown-workbench#94): one swap button in the title bar,
// and the swap turns the one tab in place - also after the change was
// reopened from Source Control, which opens it in its first order.

const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const vscode = require('vscode');
const h = require('./harness');

const SWAP = 'markdownWorkbench.swapDiffSides';
const EXTENSION = 'ww3d.markdown-workbench';

// A throwaway repository with one changed file, in the workspace copy: Git in
// VS Code 1.100.0 opens no repository outside the workspace.
async function gitChange() {
  const dir = fs.mkdtempSync(path.join(process.env.MDWB_WORKSPACE, 'git-'));
  const git = (...args) =>
    execFileSync(
      'git',
      ['-c', 'user.email=it@example.com', '-c', 'user.name=it', ...args],
      { cwd: dir, encoding: 'utf8' },
    );
  const file = path.join(dir, 'notes.md');
  fs.writeFileSync(file, '# Notes\n\nfirst\n');
  git('init', '-q');
  git('add', '.');
  git('commit', '-qm', 'init');
  fs.writeFileSync(file, '# Notes\n\nfirst\nchanged\n');
  const api = (
    await vscode.extensions.getExtension('vscode.git').activate()
  ).getAPI(1);
  const repo = await api.openRepository(vscode.Uri.file(dir));
  assert.ok(repo, `Git opens the repository ${dir}`);
  await repo.status();
  return { dir, uri: vscode.Uri.file(file) };
}

// The text-diff tabs of the active group showing `uri` on one side.
function diffTabsOf(uri) {
  return vscode.window.tabGroups.activeTabGroup.tabs.filter(
    (t) =>
      t.input instanceof vscode.TabInputTextDiff &&
      [t.input.original, t.input.modified].some((u) => u.fsPath === uri.fsPath),
  );
}

// Index of the diff tab in its group, read afresh: VS Code 1.100.0 hands out
// new tab objects after a change.
function positionOf(tab) {
  return vscode.window.tabGroups.activeTabGroup.tabs.findIndex(
    (t) =>
      t.input instanceof vscode.TabInputTextDiff &&
      t.input.original.toString() === tab.input.original.toString() &&
      t.input.modified.toString() === tab.input.modified.toString(),
  );
}

function orientation(tab) {
  return tab.input.original.scheme === 'git' ? 'git|file' : 'file|git';
}

async function swapTo(uri, expected) {
  assert.strictEqual(await vscode.commands.executeCommand(SWAP), true);
  return h.waitFor(() => {
    const tabs = diffTabsOf(uri);
    return tabs.length === 1 && orientation(tabs[0]) === expected && tabs[0];
  }, `one ${expected} tab`);
}

async function withGitChange(fn) {
  const { dir, uri } = await gitChange();
  try {
    await fn(uri);
  } finally {
    await vscode.commands.executeCommand('workbench.action.closeAllEditors');
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

h.test(
  'the own swap button stands only where VS Code has none: its key exists, a Git side is read-only, a page is writable',
  async () => {
    await vscode.extensions.getExtension('vscode.git').activate();
    await vscode.extensions.getExtension(EXTENSION).activate();
    const keys = await vscode.commands.executeCommand('getContextKeyInfo');
    const writable = {
      git: vscode.workspace.fs.isWritableFileSystem('git'),
      page: vscode.workspace.fs.isWritableFileSystem(h.SCHEME),
      file: vscode.workspace.fs.isWritableFileSystem('file'),
    };
    h.measure(`swapButtonInputs(${vscode.version})`, writable);
    assert.ok(
      keys.some((k) => k.key === 'activeCompareEditorCanSwap'),
      'VS Code knows the key the button hides on',
    );
    // VS Code's own button needs a writable left side (editorGroupView.ts):
    // none in a Git diff as opened, one in a clipboard diff.
    assert.deepStrictEqual(writable, { git: false, page: true, file: true });
  },
);

h.test(
  'Swap Diff Sides turns a Git working-tree diff in place, three times: one tab, same position, pinned',
  async () => {
    await withGitChange(async (uri) => {
      await h.openFixture('plain.md');
      await vscode.commands.executeCommand('git.openChange', uri);
      const opened = await h.waitFor(
        () => diffTabsOf(uri)[0],
        'the Git diff',
        15000,
      );
      const at = positionOf(opened);
      assert.strictEqual(orientation(opened), 'git|file');
      const seen = [];
      for (const expected of ['file|git', 'git|file', 'file|git']) {
        const tab = await swapTo(uri, expected);
        seen.push({
          label: tab.label,
          at: positionOf(tab),
          pinned: !tab.isPreview,
        });
      }
      h.measure(`gitSwap(${vscode.version})`, { at, seen });
      for (const s of seen) {
        assert.strictEqual(s.at, at, 'same tab position');
        assert.strictEqual(s.pinned, true, 'kept open (not a preview)');
      }
    });
  },
);

h.test(
  'a Git change reopened from Source Control after a swap: the next swap leaves one tab',
  async () => {
    await withGitChange(async (uri) => {
      await vscode.commands.executeCommand('git.openChange', uri);
      await h.waitFor(() => diffTabsOf(uri)[0], 'the Git diff', 15000);
      await swapTo(uri, 'file|git');
      // VS Code opens the change in its first order, beside the swapped tab.
      await vscode.commands.executeCommand('git.openChange', uri);
      const reopened = await h.waitFor(
        () => diffTabsOf(uri).length === 2 && diffTabsOf(uri),
        'the reopened Git diff',
        15000,
      );
      h.measure(
        `gitReopened(${vscode.version})`,
        reopened.map((t) => `${orientation(t)} ${t.isActive ? 'active' : ''}`),
      );
      await swapTo(uri, 'file|git');
      await swapTo(uri, 'git|file');
    });
  },
);
