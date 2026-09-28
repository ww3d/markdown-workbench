// --- Tables: reflow (distribute / consolidate) ------------------------------------
const vscode = require('vscode');

// Pure helpers (exported for tests): reflow a block of table lines.
function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

function isSeparatorRow(cells) {
  return cells.length > 0 && cells.every((c) => /^:?-+:?$/.test(c));
}

function reflowTable(lines, mode) {
  const rows = lines.map(splitRow);
  const colCount = Math.max(...rows.map((r) => r.length));
  for (const r of rows) while (r.length < colCount) r.push('');

  const widths = Array.from({ length: colCount }, (_, i) =>
    Math.max(
      3,
      ...rows.filter((r) => !isSeparatorRow(r)).map((r) => r[i].length),
    ),
  );

  return rows.map((r) => {
    if (isSeparatorRow(r)) {
      return (
        '| ' +
        r
          .map((c, i) => {
            const left = c.startsWith(':'),
              right = c.endsWith(':');
            const w = mode === 'distribute' ? widths[i] : 3;
            const dashes = '-'.repeat(
              Math.max(1, w - (left ? 1 : 0) - (right ? 1 : 0)),
            );
            return (left ? ':' : '') + dashes + (right ? ':' : '');
          })
          .join(' | ') +
        ' |'
      );
    }
    const cells =
      mode === 'distribute' ? r.map((c, i) => c.padEnd(widths[i])) : r;
    return `| ${cells.join(' | ')} |`;
  });
}

function tableRangeAt(editor) {
  const doc = editor.document;
  let start, end;
  if (!editor.selection.isEmpty) {
    start = editor.selection.start.line;
    end = editor.selection.end.line;
  } else {
    start = end = editor.selection.active.line;
    while (start > 0 && /^\s*\|/.test(doc.lineAt(start - 1).text)) start--;
    while (end < doc.lineCount - 1 && /^\s*\|/.test(doc.lineAt(end + 1).text))
      end++;
  }
  const lines = [];
  for (let l = start; l <= end; l++) {
    const text = doc.lineAt(l).text;
    if (!/^\s*\|/.test(text)) return null;
    lines.push(text);
  }
  return { start, end, lines };
}

async function reflowTableCommand(mode) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const t = tableRangeAt(editor);
  if (!t) {
    vscode.window.showInformationMessage(
      'Place the cursor inside a markdown table (lines starting with |).',
    );
    return;
  }
  const out = reflowTable(t.lines, mode).join('\n');
  const range = new vscode.Range(
    t.start,
    0,
    t.end,
    editor.document.lineAt(t.end).text.length,
  );
  await editor.edit((b) => b.replace(range, out));
}

module.exports = {
  splitRow,
  isSeparatorRow,
  reflowTable,
  tableRangeAt,
  reflowTableCommand,
};
