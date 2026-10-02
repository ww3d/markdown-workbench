// --- Lists (insert / convert selection), tables (insert), language identifier ---
import * as vscode from 'vscode';
import { coveredLines } from './tab.ts';

/**
 * Insert a list marker at the cursor, or convert each selected line into one.
 */
async function insertList(
  kind: 'bulleted' | 'numbered' | 'task',
): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const prefix = (i: number) =>
    kind === 'numbered' ? `${i + 1}. ` : kind === 'task' ? '- [ ] ' : '- ';

  if (editor.selection.isEmpty) {
    await editor.edit((b) => b.insert(editor.selection.active, prefix(0)));
    return;
  }
  const lines = coveredLines(editor);
  await editor.edit((b) => {
    let i = 0;
    for (const l of lines) {
      if (editor.document.lineAt(l).text.trim() === '') continue;
      b.insert(new vscode.Position(l, 0), prefix(i++));
    }
  });
}

/**
 * Prompt for a columns x rows size and insert a GFM table snippet, tab stops on
 * the header cells and each data cell.
 */
async function insertTable(): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const input = await vscode.window.showInputBox({
    prompt: 'Table size: columns x rows (data rows)',
    value: '3x2',
    validateInput: (v) =>
      /^\s*\d+\s*[xX*]\s*\d+\s*$/.test(v) ? null : 'Format: 3x2',
  });
  if (!input) return;
  const m = /^\s*(\d+)\s*[xX*]\s*(\d+)\s*$/.exec(input);
  if (!m) return;
  const [, c = '', r = ''] = m;
  const cols = Math.min(20, parseInt(c, 10)),
    rows = Math.min(50, parseInt(r, 10));

  let tab = 1,
    out = '';
  const row = (cell: () => string) =>
    `| ${Array.from({ length: cols }, cell).join(' | ')} |\n`;
  out += row(() => `\${${tab++}:Header}`);
  out += row(() => '---');
  for (let i = 0; i < rows; i++) out += row(() => `$${tab++}`);
  await editor.insertSnippet(new vscode.SnippetString(out));
}

// --- Language identifier ----------------------------------------------------------------

/**
 * Prompt for one of the bundled language identifiers and replace the selection
 * with it (for a code-fence info string).
 */
async function insertLanguageIdentifier(
  shikiLangs: readonly string[],
): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const pick = await vscode.window.showQuickPick(shikiLangs.slice().sort(), {
    placeHolder: 'Language identifier for the code fence',
  });
  if (!pick) return;
  await editor.edit((b) => b.replace(editor.selection, pick));
}

export { insertList, insertTable, insertLanguageIdentifier };
