// --- Formatting: bold, italic, code; web and file link insertion ---------------
const vscode = require('vscode');
const path = require('node:path');

function escapeSnippet(s) {
  return s.replace(/[\\$}]/g, '\\$&');
}

async function toggleWrap(marker) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;

  // Empty single cursor on no word: drop markers and put the cursor inside.
  if (
    editor.selections.length === 1 &&
    editor.selection.isEmpty &&
    !doc.getWordRangeAtPosition(editor.selection.active)
  ) {
    await editor.insertSnippet(
      new vscode.SnippetString(
        `${escapeSnippet(marker)}$0${escapeSnippet(marker)}`,
      ),
    );
    return;
  }

  await editor.edit((b) => {
    for (const sel of editor.selections) {
      let range = sel;
      if (sel.isEmpty) {
        const word = doc.getWordRangeAtPosition(sel.active);
        if (!word) continue;
        range = word;
      }
      const text = doc.getText(range);
      if (
        text.length >= marker.length * 2 &&
        text.startsWith(marker) &&
        text.endsWith(marker)
      ) {
        b.replace(
          range,
          text.slice(marker.length, text.length - marker.length),
        );
        continue;
      }
      // Selection sits inside existing markers -> unwrap them.
      const ext = new vscode.Range(
        range.start.translate(
          0,
          -Math.min(marker.length, range.start.character),
        ),
        range.end.translate(0, marker.length),
      );
      const extText = doc.getText(ext);
      if (extText === marker + text + marker) {
        b.replace(ext, text);
        continue;
      }
      b.replace(range, marker + text + marker);
    }
  });
}

// --- Links -----------------------------------------------------------------------

async function insertWebLink() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const text = editor.document.getText(editor.selection);
  const snippet = `[\${1:${escapeSnippet(text || 'text')}}](\${2:https://})`;
  await editor.insertSnippet(
    new vscode.SnippetString(snippet),
    editor.selection,
  );
}

async function insertFileLink() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const files = await vscode.workspace.findFiles(
    '**/*',
    '{**/node_modules/**,**/.git/**}',
    2000,
  );
  if (!files.length) {
    vscode.window.showInformationMessage('No workspace files found.');
    return;
  }
  const items = files
    .map((uri) => ({ label: vscode.workspace.asRelativePath(uri), uri }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const pick = await vscode.window.showQuickPick(items, {
    placeHolder: 'Link to file in workspace',
  });
  if (!pick) return;

  let target;
  if (editor.document.uri.scheme === 'file') {
    target = path
      .relative(path.dirname(editor.document.uri.fsPath), pick.uri.fsPath)
      .split(path.sep)
      .join('/');
  } else {
    target = pick.label.split(path.sep).join('/');
  }
  const selText = editor.document.getText(editor.selection);
  const label = selText || path.basename(pick.uri.fsPath);
  await editor.edit((b) =>
    b.replace(editor.selection, `[${label}](${target})`),
  );
}

module.exports = { escapeSnippet, toggleWrap, insertWebLink, insertFileLink };
