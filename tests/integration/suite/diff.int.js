// Diff mechanics in the real VS Code: tab titles from the role names before
// and after a swap (twice), one undo step per Apply, the direction of the
// built-in revert arrows in both orientations, and the swap of a foreign
// virtual diff (docs/DECISIONS.md #48).

const assert = require('node:assert');
const vscode = require('vscode');
const h = require('./harness');

h.test(
  'tab title shows the roles in order before and after swapping, twice',
  async () => {
    await h.openFixture('notes.md');
    const { tab } = await h.compare('# Notes\n\nIntro paragraph, rewritten.\n');
    const labelOf = () => h.clipboardDiffTab().label;
    const before = labelOf();
    await vscode.commands.executeCommand('markdownWorkbench.swapDiffSides');
    await h.waitFor(() => labelOf() !== before, 'the swapped title');
    const swapped = labelOf();
    await vscode.commands.executeCommand('markdownWorkbench.swapDiffSides');
    await h.waitFor(() => labelOf() === before, 'the original title');
    h.measure('tabLabels', { before, swapped, again: labelOf() });
    assert.ok(
      before.indexOf('notes.md') < before.indexOf('notes (Candidate).md'),
      before,
    );
    assert.ok(
      swapped.indexOf('notes (Candidate).md') < swapped.indexOf('notes.md'),
      swapped,
    );
    assert.ok(tab);
  },
);

h.test('selection diff: the tab names the (Selection) page', async () => {
  const editor = await h.openFixture('plain.md', new vscode.Range(1, 0, 1, 4));
  assert.strictEqual(editor.document.getText(editor.selection), 'beta');
  const { tab } = await h.compare('BETA');
  h.measure('selectionTabLabel', tab.label);
  assert.ok(
    tab.label.includes('plain (Selection).md') &&
      tab.label.includes('plain (Candidate).md'),
    tab.label,
  );
});

h.test('Apply Candidate is undone by a single undo', async () => {
  const editor = await h.openFixture('plain.md', new vscode.Range(1, 0, 2, 5));
  const original = editor.document.getText();
  await h.compare('BETA\nGAMMA');
  await vscode.commands.executeCommand('markdownWorkbench.applyCandidate');
  const file = vscode.workspace.textDocuments.find(
    (d) => d.uri.toString() === editor.document.uri.toString(),
  );
  await h.waitFor(
    () => file.getText().includes('BETA\nGAMMA'),
    'the applied text',
  );
  await vscode.window.showTextDocument(file, { preview: false });
  await vscode.commands.executeCommand('undo');
  await h.waitFor(
    () => file.getText() === original,
    'the text after one undo',
    2000,
  );
  h.measure('undoRestoresOriginal', true);
});

// diffEditor.revert without arguments reverts the hunk at the cursor from 1.10x
// on; 1.100 only knows the gutter-arrow form with arguments. The test calls it
// only to press the arrow - the extension itself never does. The primary side
// of a diff editor is its right (modified) side.
async function pressRevertArrow(line) {
  await vscode.commands.executeCommand(
    'workbench.action.compareEditor.focusPrimarySide',
  );
  await h.sleep(100);
  const editor = vscode.window.activeTextEditor;
  editor.selection = new vscode.Selection(line, 0, line, 0);
  try {
    await vscode.commands.executeCommand('diffEditor.revert');
    return { target: editor.document.uri.toString(), form: 'cursor' };
  } catch {
    // 1.100: the arrow's own call - the hunk as a 1-based line range.
    const tab = h.diffTabs().find((t) => t.isActive);
    const width = editor.document.lineAt(line).text.length + 1;
    const range = {
      startLineNumber: line + 1,
      startColumn: 1,
      endLineNumber: line + 1,
      endColumn: width,
    };
    await vscode.commands.executeCommand('diffEditor.revert', {
      originalUri: tab.input.original,
      modifiedUri: tab.input.modified,
      mapping: {
        innerChanges: [{ originalRange: range, modifiedRange: range }],
      },
    });
    return { target: editor.document.uri.toString(), form: 'arrow arguments' };
  }
}

h.test(
  'the revert arrow drops a candidate hunk, and after the swap takes it into the file',
  async () => {
    const editor = await h.openFixture('plain.md');
    const file = editor.document;
    const { candidateUri } = await h.compare('alpha\nBETA\ngamma\ndelta\n');
    const candidate = await h.waitFor(
      () => h.editorOf(candidateUri),
      'the candidate editor',
    );
    await h.sleep(800); // let the diff compute
    h.measure(
      `arrowBeforeSwapTarget(${vscode.version})`,
      await pressRevertArrow(1),
    );
    const reverted = await h
      .waitFor(
        () => candidate.document.getText().startsWith('alpha\nbeta\n'),
        'the reverted candidate',
        2000,
      )
      .then(
        () => true,
        () => false,
      );
    h.measure(
      `arrowBeforeSwap(${vscode.version})`,
      reverted ? 'candidate hunk reverted to the file text' : 'no effect',
    );
    assert.strictEqual(
      file.getText(),
      'alpha\nbeta\ngamma\ndelta\n',
      'the file is untouched before the swap',
    );
    assert.ok(reverted, 'the arrow copies left (file) to right (candidate)');

    await h.resetEditors();
    const again = await h.openFixture('plain.md');
    await h.compare('alpha\nBETA\ngamma\ndelta\n');
    await vscode.commands.executeCommand('markdownWorkbench.swapDiffSides');
    const fileEditor = await h.waitFor(
      () =>
        vscode.window.visibleTextEditors.find(
          (e) => e.document.uri.toString() === again.document.uri.toString(),
        ),
      'the file editor on the right',
    );
    await h.sleep(800);
    assert.ok(fileEditor);
    h.measure(
      `arrowAfterSwapTarget(${vscode.version})`,
      await pressRevertArrow(1),
    );
    const taken = await h
      .waitFor(
        () => again.document.getText().startsWith('alpha\nBETA\n'),
        'the hunk in the file',
        2000,
      )
      .then(
        () => true,
        () => false,
      );
    h.measure(
      `arrowAfterSwap(${vscode.version})`,
      taken ? 'candidate hunk taken into the file' : 'no effect',
    );
    assert.ok(
      taken,
      'after the swap the arrow copies the candidate (left) into the file (right)',
    );
  },
);

h.test(
  'Swap Diff Sides on a foreign virtual diff swaps it or says it did not',
  async () => {
    const docs = new Map([
      ['/left.md', 'left side\n'],
      ['/right.md', 'right side\n'],
    ]);
    const reg = vscode.workspace.registerTextDocumentContentProvider(
      'mdwb-foreign',
      {
        provideTextDocumentContent: (uri) => docs.get(uri.path),
      },
    );
    try {
      const left = vscode.Uri.from({
        scheme: 'mdwb-foreign',
        path: '/left.md',
      });
      const right = vscode.Uri.from({
        scheme: 'mdwb-foreign',
        path: '/right.md',
      });
      await vscode.commands.executeCommand('vscode.diff', left, right);
      const tab = await h.waitFor(
        () =>
          h.diffTabs().find((t) => t.input.original.scheme === 'mdwb-foreign'),
        'the foreign diff',
      );
      const reported = await vscode.commands.executeCommand(
        'markdownWorkbench.swapDiffSides',
      );
      const swapped = await h
        .waitFor(
          () => h.diffTabs().find((t) => t.input.original.path === '/right.md'),
          'the swapped foreign diff',
          2000,
        )
        .then(
          () => true,
          () => false,
        );
      h.measure(`foreignSwap(${vscode.version})`, {
        swapped,
        commandResult: reported,
        tabs: h
          .diffTabs()
          .map((t) => `${t.input.original} | ${t.input.modified}`),
      });
      assert.ok(tab);
      // Either outcome is fine; a swap that did not happen must not be claimed.
      assert.strictEqual(
        reported,
        swapped,
        'the command result matches what happened',
      );
    } finally {
      reg.dispose();
    }
  },
);
