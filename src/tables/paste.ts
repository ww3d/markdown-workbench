// Paste tab- or comma-separated data as a Markdown table (X1). Offered as an
// alternative in the paste menu; the plain-text paste stays the default.

import * as vscode from 'vscode';
import { tabularRows, gridFromRows } from './csv.ts';
import { autoFormat } from './format.ts';
import { prefixLength } from './row.ts';
import { blocksOf } from './blocks.ts';
import { tablesConfig } from './config.ts';

/**
 * The table text for pasting `text` at `range`, or null when it is not tabular,
 * the paste is not at the start of a line (after an optional `>`/indent prefix),
 * text follows on the line, or the line is in code, HTML or the frontmatter. Lines after the first
 * repeat the prefix; a blank line is appended when content follows directly, so
 * the next line does not become a table row.
 */
function tableTextFor(
  doc: vscode.TextDocument,
  range: vscode.Range,
  text: string,
  cfg: { readonly maxWidth: number; readonly ambiguousWide: boolean },
): string | null {
  const rows = tabularRows(text);
  if (!rows) return null;
  const line = doc.lineAt(range.start.line).text;
  const before = line.slice(0, range.start.character);
  if (prefixLength(before) !== before.length) return null;
  if (range.end.line !== range.start.line) return null;
  if (line.slice(range.end.character).trim() !== '') return null;
  if (blocksOf(doc).code[range.start.line]) return null;
  const lines = autoFormat(gridFromRows(rows, before), cfg).lines;
  let out = lines.join('\n').slice(before.length);
  const next = range.start.line + 1;
  if (next < doc.lineCount && doc.lineAt(next).text.trim() !== '')
    out += `\n${before.trimEnd()}`;
  return out;
}

/** Register the paste provider for markdown documents. */
function registerPaste(context: vscode.ExtensionContext): void {
  const kind = vscode.DocumentDropOrPasteEditKind.Empty.append(
    'markdown',
    'table',
  );
  const provider: vscode.DocumentPasteEditProvider = {
    async provideDocumentPasteEdits(doc, ranges, dataTransfer) {
      const cfg = tablesConfig();
      const [range] = ranges;
      if (!cfg.pasteAsTable || ranges.length !== 1 || !range) return undefined;
      const text = await dataTransfer.get('text/plain')?.asString();
      if (!text) return undefined;
      const insert = tableTextFor(doc, range, text, cfg);
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

export { registerPaste, tableTextFor };
