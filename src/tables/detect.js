// Table detection for the editor: header row, delimiter row with the same cell
// count, body rows up to a blank line or the next block - the table the preview
// (markdown-it 15) renders. Pure, no vscode import: a document is anything with
// `lineCount` + `lineAt(n).text`. Rules: docs/DECISIONS.md #48.

const {
  prefixLength,
  quoteDepth,
  trailingIndent,
  contentEnd,
  splitRow,
  parseSeparator,
  parseRow,
  startsBlock,
} = require('./row');
const { codeMask, isIndentedCode } = require('./code-mask');

// Can `line` continue a table whose header has `depth` and `indent`?
function isBodyRow(doc, line, depth, indent, mask) {
  if (line >= doc.lineCount || mask[line]) return false;
  const text = doc.lineAt(line).text;
  const p = prefixLength(text);
  if (p >= contentEnd(text)) return false;
  const prefix = text.slice(0, p);
  if (quoteDepth(prefix) !== depth) return false;
  const rowIndent = trailingIndent(prefix);
  if (rowIndent - indent >= 4) return false;
  if (rowIndent < indent && indent > 3) return false;
  const body = text.slice(p);
  return !startsBlock(body);
}

// The header at `h` with its delimiter row below, or null.
function headerAt(doc, h, mask) {
  if (h < 0 || h + 1 >= doc.lineCount || mask[h] || mask[h + 1]) return null;
  const text = doc.lineAt(h).text;
  const p = prefixLength(text);
  if (!text.slice(p).includes('|')) return null;
  const sepText = doc.lineAt(h + 1).text;
  const sp = prefixLength(sepText);
  const prefix = text.slice(0, p);
  const depth = quoteDepth(prefix);
  if (quoteDepth(sepText.slice(0, sp)) !== depth) return null;
  const indent = trailingIndent(prefix);
  if (trailingIndent(sepText.slice(0, sp)) - indent >= 4) return null;
  const aligns = parseSeparator(sepText, sp);
  if (!aligns) return null;
  const head = splitRow(text, p);
  if (head.cells.length !== aligns.length) return null;
  if (isIndentedCode(doc, h, prefix)) return null;
  return { aligns, depth, indent };
}

/**
 * The table containing `line`, detected like the preview does: a header row, a
 * delimiter row with the same cell count, then body rows up to a blank line or
 * the next block. Null outside a table, in a code block or the frontmatter.
 * `rows[0]` is the header, `rows[1]` the delimiter row.
 * @param {{ lineCount: number, lineAt(n: number): { text: string } }} doc
 * @param {number} line
 * @returns {{ start: number, end: number, aligns: string[], columnCount: number, rows: Array<{ line: number, text: string, prefix: string, lead: boolean, trail: boolean, pipes: number[], cells: object[] }> } | null}
 */
function findTable(doc, line) {
  if (line < 0 || line >= doc.lineCount) return null;
  const mask = codeMask(doc);
  if (mask[line]) return null;
  const text = doc.lineAt(line).text;
  const p = prefixLength(text);
  if (p >= contentEnd(text)) return null;
  const depth = quoteDepth(text.slice(0, p));
  let start = -1,
    info = null;
  for (let k = line; k >= 0; k--) {
    info = headerAt(doc, k, mask);
    if (info && info.depth === depth && k + 1 >= line) {
      start = k;
      break;
    }
    if (k < line && headerAt(doc, k - 1, mask)?.depth === depth) {
      start = k - 1;
      info = headerAt(doc, start, mask);
      break;
    }
    const t = doc.lineAt(k).text;
    const kp = prefixLength(t);
    if (kp >= contentEnd(t) || quoteDepth(t.slice(0, kp)) !== depth)
      return null;
  }
  if (start < 0) return null;
  let end = start + 1;
  while (isBodyRow(doc, end + 1, info.depth, info.indent, mask)) end++;
  if (line > end) return null;
  const rows = [];
  for (let l = start; l <= end; l++) {
    const t = doc.lineAt(l).text;
    rows.push({ line: l, text: t, ...parseRow(t) });
  }
  return {
    start,
    end,
    aligns: info.aligns,
    columnCount: info.aligns.length,
    rows,
  };
}

/**
 * A line typed as the start of a table (REQ-005): it begins with `|` after its
 * prefix, is no table row and has no delimiter row below. Null otherwise.
 * @param {{ lineCount: number, lineAt(n: number): { text: string } }} doc
 * @param {number} line
 */
function pipeHeaderAt(doc, line) {
  if (line < 0 || line >= doc.lineCount) return null;
  if (codeMask(doc)[line]) return null;
  const text = doc.lineAt(line).text;
  const row = parseRow(text);
  if (text[row.prefix.length] !== '|') return null;
  if (findTable(doc, line)) return null;
  if (line + 1 < doc.lineCount) {
    const next = doc.lineAt(line + 1).text;
    if (parseSeparator(next, prefixLength(next))) return null;
  }
  return { line, text, ...row };
}

/**
 * All tables of a document, in order (for the diagnostics).
 * @param {{ lineCount: number, lineAt(n: number): { text: string } }} doc
 */
function scanTables(doc) {
  const out = [];
  const mask = codeMask(doc);
  for (let l = 0; l + 1 < doc.lineCount; l++) {
    if (mask[l] || !doc.lineAt(l).text.includes('|')) continue;
    if (!headerAt(doc, l, mask)) continue;
    const t = findTable(doc, l);
    if (t && t.start === l) {
      out.push(t);
      l = t.end;
    }
  }
  return out;
}

/** Adapt a string array to the document shape the model reads. */
function linesDoc(lines) {
  return { lineCount: lines.length, lineAt: (n) => ({ text: lines[n] }) };
}

module.exports = { findTable, pipeHeaderAt, scanTables, linesDoc };
