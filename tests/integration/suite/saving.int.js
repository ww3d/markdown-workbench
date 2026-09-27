// Save actions and the immediate save (docs/DECISIONS.md #48, decision on
// ww3d/markdown-workbench#88): typing in the focused candidate is saved
// without the user's save actions, so files.trimTrailingWhitespace,
// files.insertFinalNewline and editor.formatOnSave change neither the
// candidate nor the file; where a page is saved while not focused, the save
// actions may change the page, but never reach the real file.

const assert = require('node:assert');
const vscode = require('vscode');
const h = require('./harness');

const SETTINGS = [
  ['files', 'trimTrailingWhitespace', true],
  ['files', 'insertFinalNewline', true],
  ['editor', 'formatOnSave', true],
];

async function withSaveActions(fn) {
  // A formatter for the pages, so formatOnSave has something to run.
  const formatter = vscode.languages.registerDocumentFormattingEditProvider(
    { scheme: h.SCHEME },
    {
      provideDocumentFormattingEdits: (doc) => [
        vscode.TextEdit.insert(
          doc.positionAt(doc.getText().length),
          '\nFORMATTED',
        ),
      ],
    },
  );
  for (const [section, key, value] of SETTINGS) {
    await vscode.workspace
      .getConfiguration(section)
      .update(key, value, vscode.ConfigurationTarget.Global);
  }
  try {
    await fn();
  } finally {
    formatter.dispose();
    for (const [section, key] of SETTINGS) {
      await vscode.workspace
        .getConfiguration(section)
        .update(key, undefined, vscode.ConfigurationTarget.Global);
    }
  }
}

async function typeInto(editor, position, text) {
  for (const ch of text) {
    await editor.edit((b) => b.insert(position, ch));
    position = position.translate(0, 1);
    await h.sleep(40);
  }
}

h.test(
  'typing in the focused candidate: a trailing space stays, no final newline, no format',
  async () => {
    await withSaveActions(async () => {
      const editor = await h.openFixture('plain.md');
      const fileBefore = editor.document.getText();
      const { candidateUri } = await h.compare('zeta one\nzeta two'); // no anchor hit: whole file
      const candidate = await h.waitFor(
        () => h.editorOf(candidateUri),
        'the candidate editor',
      );
      await vscode.commands.executeCommand(
        'workbench.action.compareEditor.focusPrimarySide',
      );
      await typeInto(candidate, new vscode.Position(0, 8), ' more ');
      await h.sleep(800);
      const text = candidate.document.getText();
      h.measure(`focusedCandidateAfterTyping(${vscode.version})`, text);
      assert.strictEqual(
        text,
        'zeta one more \nzeta two',
        'no trim, no final newline, no format',
      );
      assert.strictEqual(candidate.document.isDirty, false, 'saved');
      assert.strictEqual(
        editor.document.getText(),
        fileBefore,
        'the file is untouched',
      );
    });
  },
);

h.test(
  'a page saved while not focused: save actions stay on the page, the file only gets the edit',
  async () => {
    await withSaveActions(async () => {
      const editor = await h.openFixture(
        'plain.md',
        new vscode.Range(0, 0, 1, 4),
      );
      const file = editor.document;
      await h.compare('ALPHA\nBETA');
      const tab = h.clipboardDiffTab();
      const page = await vscode.workspace.openTextDocument(tab.input.original);
      await vscode.commands.executeCommand(
        'workbench.action.compareEditor.focusPrimarySide',
      ); // the candidate
      // An edit of the selection page from outside its editor (like a diff
      // arrow after a swap): it is saved with document.save().
      const edit = new vscode.WorkspaceEdit();
      edit.insert(page.uri, new vscode.Position(0, 5), ' ');
      await vscode.workspace.applyEdit(edit);
      await h.sleep(1500);
      h.measure(`unfocusedPageAfterEdit(${vscode.version})`, page.getText());
      h.measure(
        `fileAfterUnfocusedPageEdit(${vscode.version})`,
        file.getText(),
      );
      assert.strictEqual(
        file.getText(),
        'alpha \nbeta\ngamma\ndelta\n',
        'only the typed space reached the file',
      );
      assert.strictEqual(page.isDirty, false, 'the page is saved');
    });
  },
);
