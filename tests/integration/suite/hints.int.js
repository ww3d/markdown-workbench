// Candidate hints and the section anchor in the real VS Code: placeholder and
// checkbox diagnostics with their quick fixes on the candidate page, the jump
// to the anchored span, and the picker for an ambiguous anchor
// (docs/DECISIONS.md #48).

const assert = require('node:assert');
const vscode = require('vscode');
const h = require('./harness');

// The test runner shares the extension's vscode API object, so wrapping
// showQuickPick sees the extension's picker. `onDidSelectItem` fires once the
// shown picker makes an item active: the signal that accepting now picks it.
function watchQuickPick() {
  const orig = vscode.window.showQuickPick;
  const state = {
    active: false,
    restore: () => {
      vscode.window.showQuickPick = orig;
    },
  };
  vscode.window.showQuickPick = function (items, options, token) {
    const onDidSelectItem = (item) => {
      state.active = true;
      return options?.onDidSelectItem?.(item);
    };
    return orig.call(this, items, { ...options, onDidSelectItem }, token);
  };
  return state;
}

h.test(
  'placeholder and checkbox diagnostics and their quick fixes appear on the candidate',
  async () => {
    await h.openFixture('notes.md');
    const { candidateUri } = await h.compare(
      '## Setup\n\n- [ ] install the tools\n… rest unchanged …\n',
    );
    const diagnostics = await h.waitFor(() => {
      const d = vscode.languages.getDiagnostics(candidateUri);
      return d.length >= 2 ? d : undefined;
    }, 'the candidate diagnostics');
    const codes = diagnostics.map((d) => String(d.code)).sort();
    h.measure('candidateDiagnostics', codes);
    assert.deepStrictEqual(codes, ['checkbox-reset', 'placeholder']);
    const line = diagnostics.find((d) => d.code === 'checkbox-reset').range
      .start.line;
    const actions = await vscode.commands.executeCommand(
      'vscode.executeCodeActionProvider',
      candidateUri,
      new vscode.Range(line, 0, line, 0),
    );
    const titles = actions.map((a) => a.title);
    h.measure('candidateQuickFixes', titles);
    assert.ok(
      titles.includes('Keep checkbox states from the baseline'),
      titles.join(', '),
    );
  },
);

h.test(
  'an anchored section opens with the span selected in the candidate',
  async () => {
    await h.openFixture('notes.md');
    const { candidateUri } = await h.compare(
      '## Usage\n\nRun it twice and read the output.\n',
    );
    const candidate = await h.waitFor(
      () => h.editorOf(candidateUri),
      'the candidate editor',
    );
    await h.sleep(300);
    const sel = candidate.selection;
    h.measure('anchorSelection', [sel.start.line, sel.end.line]);
    assert.deepStrictEqual([sel.start.line, sel.end.line], [9, 11]);
  },
);

h.test(
  'an ambiguous anchor shows a picker; accepting its first entry anchors there',
  async () => {
    await h.openFixture('duplicate.md');
    await vscode.env.clipboard.writeText('## Part\n\nnew text\n');
    const shown = watchQuickPick();
    let pending;
    try {
      pending = vscode.commands.executeCommand(
        'markdownWorkbench.compareWithClipboard',
      );
      await h.waitFor(() => shown.active, 'the anchor picker');
    } finally {
      shown.restore();
    }
    await vscode.commands.executeCommand(
      'workbench.action.acceptSelectedQuickOpenItem',
    );
    await pending;
    const tab = await h.waitFor(
      () => h.clipboardDiffTab(),
      'the diff after the pick',
    );
    const candidate = await vscode.workspace.openTextDocument(
      tab.input.modified,
    );
    h.measure('ambiguousAnchorCandidate', candidate.getText());
    assert.strictEqual(
      candidate.getText(),
      '## Part\n\nnew text\n\n## Part\n\nsame text\n',
    );
  },
);
