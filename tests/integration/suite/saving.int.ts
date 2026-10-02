// Save actions and the immediate save (docs/DECISIONS.md #48, decision on
// ww3d/markdown-workbench#88): typing in a focused page (the candidate or the
// selection page on the left) is saved without the user's save actions, so
// files.trimTrailingWhitespace, files.insertFinalNewline and
// editor.formatOnSave change neither the page nor the file; where a page is saved while not focused, the save
// actions may change the page, but never reach the real file.

import assert from 'node:assert';
import * as vscode from 'vscode';
import * as h from './harness.ts';

const SETTINGS: [string, string, boolean][] = [
  ['files', 'trimTrailingWhitespace', true],
  ['files', 'insertFinalNewline', true],
  ['editor', 'formatOnSave', true],
];

const appendFormatted = (doc: vscode.TextDocument) => [
  vscode.TextEdit.insert(doc.positionAt(doc.getText().length), '\nFORMATTED'),
];

// Runs `fn` with the save actions on; `format` is the pages' formatter, so
// formatOnSave has something to run.
async function withSaveActions(
  fn: () => Promise<void>,
  format: (
    doc: vscode.TextDocument,
  ) => vscode.TextEdit[] | Promise<vscode.TextEdit[]> = appendFormatted,
): Promise<void> {
  const formatter = vscode.languages.registerDocumentFormattingEditProvider(
    { scheme: h.SCHEME },
    { provideDocumentFormattingEdits: format },
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

// Types `text` one character at a time and waits until each change is saved,
// so every keystroke goes through one immediate save of its own (typing faster
// than a save takes would merge changes and make the result timing-dependent).
async function typeInto(
  editor: vscode.TextEditor,
  position: vscode.Position,
  text: string,
): Promise<void> {
  for (const ch of text) {
    await editor.edit((b) => b.insert(position, ch));
    position = position.translate(0, 1);
    await h.waitFor(
      () => !editor.document.isDirty,
      'the save of a keystroke',
      3000,
    );
    await h.sleep(150); // room for save actions that would follow the save
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
  'fast typing on the left with save actions: file region equals page',
  async () => {
    // A slow formatter: typing goes on while a save with save actions would run.
    const slow = () => h.sleep(300).then(() => []);
    await withSaveActions(async () => {
      const editor = await h.openFixture(
        'plain.md',
        new vscode.Range(0, 0, 1, 4),
      );
      const file = editor.document;
      const { baselineUri } = await h.compare('ALPHA\nBETA');
      const page = await h.waitFor(
        () => h.editorOf(baselineUri),
        'the selection page editor',
      );
      await vscode.commands.executeCommand(
        'workbench.action.compareEditor.focusSecondarySide',
      );
      page.selection = new vscode.Selection(0, 5, 0, 5);
      let willSave = 0;
      const listener = vscode.workspace.onWillSaveTextDocument((e) => {
        if (e.document.uri.toString() === baselineUri.toString()) willSave++;
      });
      try {
        for (const ch of ' x y z ') {
          await vscode.commands.executeCommand('type', { text: ch });
          await h.sleep(40);
        }
        await h.sleep(2000);
      } finally {
        listener.dispose();
      }
      const text = page.document.getText();
      h.measure(`leftPageAfterFastTyping(${vscode.version})`, text);
      h.measure(`fileAfterFastTypingLeft(${vscode.version})`, file.getText());
      h.measure(`willSaveFastTypingLeft(${vscode.version})`, willSave);
      assert.strictEqual(text, 'alpha x y z \nbeta', 'nothing trimmed');
      assert.strictEqual(
        file.getText(),
        `${text}\ngamma\ndelta\n`,
        'the file region equals the page',
      );
      assert.strictEqual(page.document.isDirty, false, 'the page is saved');
      assert.strictEqual(willSave, 0, 'no save with save actions');
    }, slow);
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
      const tab = h.found(h.clipboardDiffTab(), 'the clipboard diff tab');
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
