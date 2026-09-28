// --- Sorting -------------------------------------------------------------------------
const vscode = require('vscode');

async function sortSelection(descending) {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selection.isEmpty) {
    vscode.window.showInformationMessage('Select the lines to sort first.');
    return;
  }
  const start = editor.selection.start.line;
  const end = editor.selection.end.line;
  const lines = [];
  for (let l = start; l <= end; l++) lines.push(editor.document.lineAt(l).text);
  lines.sort((a, b) =>
    a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }),
  );
  if (descending) lines.reverse();
  const range = new vscode.Range(
    start,
    0,
    end,
    editor.document.lineAt(end).text.length,
  );
  await editor.edit((b) => b.replace(range, lines.join('\n')));
}

module.exports = { sortSelection };
