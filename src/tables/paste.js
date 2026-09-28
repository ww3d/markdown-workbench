// Paste tab- or comma-separated data as a Markdown table (X1). Offered as an
// alternative in the paste menu; the plain-text paste stays the default.

const vscode = require('vscode');
const { tabularRows, gridFromRows } = require('./csv');
const { autoFormat } = require('./format');
const { prefixLength } = require('./row');
const { codeMask } = require('./code-mask');
const { tablesConfig } = require('./config');

/**
 * The table text for pasting `text` at `range`, or null when it is not tabular,
 * the paste is not at the start of a line (after an optional `>`/indent prefix),
 * text follows on the line, or the line is in a code block. Lines after the first
 * repeat the prefix; a blank line is appended when content follows directly, so
 * the next line does not become a table row.
 * @param {vscode.TextDocument} doc
 * @param {vscode.Range} range
 * @param {string} text
 * @param {{ maxWidth: number, ambiguousWide: boolean }} cfg
 * @returns {string | null}
 */
function tableTextFor(doc, range, text, cfg) {
  const rows = tabularRows(text);
  if (!rows) return null;
  const line = doc.lineAt(range.start.line).text;
  const before = line.slice(0, range.start.character);
  if (prefixLength(before) !== before.length) return null;
  if (range.end.line !== range.start.line) return null;
  if (line.slice(range.end.character).trim() !== '') return null;
  if (codeMask(doc)[range.start.line]) return null;
  const lines = autoFormat(gridFromRows(rows, before), cfg).lines;
  let out = lines.join('\n').slice(before.length);
  const next = range.start.line + 1;
  if (next < doc.lineCount && doc.lineAt(next).text.trim() !== '')
    out += `\n${before.trimEnd()}`;
  return out;
}

/** Register the paste provider for markdown documents. */
function registerPaste(context) {
  const kind = vscode.DocumentDropOrPasteEditKind.Empty.append(
    'markdown',
    'table',
  );
  const provider = {
    async provideDocumentPasteEdits(doc, ranges, dataTransfer) {
      const cfg = tablesConfig();
      if (!cfg.pasteAsTable || ranges.length !== 1) return undefined;
      const text = await dataTransfer.get('text/plain')?.asString();
      if (!text) return undefined;
      const insert = tableTextFor(doc, ranges[0], text, cfg);
      if (insert === null) return undefined;
      const edit = new vscode.DocumentPasteEdit(
        insert,
        'Insert as Markdown table',
        kind,
      );
      edit.yieldTo = [vscode.DocumentDropOrPasteEditKind.Text];
      return [edit];
    },
  };
  context.subscriptions.push(
    vscode.languages.registerDocumentPasteEditProvider(
      { language: 'markdown' },
      provider,
      { providedPasteEditKinds: [kind], pasteMimeTypes: ['text/plain'] },
    ),
  );
}

module.exports = { registerPaste, tableTextFor };
