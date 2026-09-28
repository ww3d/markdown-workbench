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
  // markdown-it measures against the enclosing block, not the header: 4+
  // columns outside a list are an indented code block.
  if (isIndentedCode(doc, line, prefix)) return false;
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
  if (isIndentedCode(doc, h + 1, sepText.slice(0, sp))) return null;
  const aligns = parseSeparator(sepText, sp);
  if (!aligns) return null;
  const head = splitRow(text, p);
  if (head.cells.length !== aligns.length) return null;
  if (isIndentedCode(doc, h, prefix)) return null;
  return { aligns, depth, indent };
}

/**
 * @typedef {{ lineCount: number, lineAt(n: number): { text: string }, version?: number }} LineDoc
 * @typedef {import('./row').ParsedRow & { line: number, text: string }} TableRow
 * @typedef {object} Table
 * @property {number} start header line
 * @property {number} end last body line
 * @property {string[]} aligns per column '', 'left', 'right' or 'center'
 * @property {number} columnCount
 * @property {TableRow[]} rows `rows[0]` is the header, `rows[1]` the delimiter row
 */

// The last span found per document, reused while the version stays - or is
// carried over an edit inside a body row (carrySpan) - so the selection-change
// context key does not rescan a large table on every keystroke.
const spanCache = new WeakMap();
const NO_MASK = {};

// Header line, last body line and header shape of the table holding `line`.
// Scans top-down from the start of the block, like markdown-it: a body row
// that looks like a delimiter row (`| - | - |`) stays a body row.
function tableSpan(doc, line, mask) {
  if (line < 0 || line >= doc.lineCount || mask[line]) return null;
  const text = doc.lineAt(line).text;
  const p = prefixLength(text);
  if (p >= contentEnd(text)) return null;
  const depth = quoteDepth(text.slice(0, p));
  let top = line;
  while (top > 0 && !mask[top - 1]) {
    const t = doc.lineAt(top - 1).text;
    const tp = prefixLength(t);
    if (tp >= contentEnd(t) || quoteDepth(t.slice(0, tp)) !== depth) break;
    top--;
  }
  for (let l = top; l <= line; ) {
    const info = headerAt(doc, l, mask);
    if (!info || info.depth !== depth) {
      l++;
      continue;
    }
    let end = l + 1;
    while (isBodyRow(doc, end + 1, info.depth, info.indent, mask)) end++;
    if (line <= end) return { start: l, end, ...info };
    l = end + 1;
  }
  return null;
}

function remember(doc, span) {
  if (span && doc.version !== undefined)
    spanCache.set(doc, { ...span, version: doc.version });
}

/**
 * The table containing `line`, detected like the preview does: a header row, a
 * delimiter row with the same cell count, then body rows up to a blank line or
 * the next block. Null outside a table, in a code block or the frontmatter.
 * @param {LineDoc} doc
 * @param {number} line
 * @returns {Table | null}
 */
function findTable(doc, line) {
  const span = tableSpan(doc, line, codeMask(doc));
  if (!span) return null;
  remember(doc, span);
  const rows = [];
  for (let l = span.start; l <= span.end; l++) {
    const t = doc.lineAt(l).text;
    rows.push({ line: l, text: t, ...parseRow(t) });
  }
  return {
    start: span.start,
    end: span.end,
    aligns: span.aligns,
    columnCount: span.aligns.length,
    rows,
  };
}

/**
 * Whether `line` is a table row, without building the table: answered from the
 * cached span of the current document version where possible.
 * @param {LineDoc} doc
 * @param {number} line
 */
function inTableAt(doc, line) {
  const hit = spanCache.get(doc);
  if (
    hit &&
    hit.version === doc.version &&
    line >= hit.start &&
    line <= hit.end
  )
    return true;
  const span = tableSpan(doc, line, codeMask(doc));
  remember(doc, span);
  return span !== null;
}

/**
 * Carry the cached span over a document change that only edits body rows of
 * that table within their line (typing in a cell); any other change drops it.
 * @param {LineDoc} doc the changed document (new version)
 * @param {ReadonlyArray<{ range: { start: { line: number }, end: { line: number } }, text: string }>} changes
 */
function carrySpan(doc, changes) {
  const hit = spanCache.get(doc);
  if (!hit || doc.version === undefined || hit.version !== doc.version - 1)
    return spanCache.delete(doc);
  for (const c of changes) {
    const l = c.range.start.line;
    const inBody = l > hit.start + 1 && l <= hit.end;
    const oneLine = c.range.end.line === l && !c.text.includes('\n');
    if (
      !inBody ||
      !oneLine ||
      !isBodyRow(doc, l, hit.depth, hit.indent, NO_MASK)
    )
      return spanCache.delete(doc);
  }
  hit.version = doc.version;
}

/**
 * A line typed as the start of a table (REQ-005): it begins with `|` after its
 * prefix, is no table row, no indented code and has no delimiter row below.
 * Null otherwise.
 * @param {LineDoc} doc
 * @param {number} line
 */
function pipeHeaderAt(doc, line) {
  if (line < 0 || line >= doc.lineCount) return null;
  if (codeMask(doc)[line]) return null;
  const text = doc.lineAt(line).text;
  const row = parseRow(text);
  if (text[row.prefix.length] !== '|') return null;
  if (isIndentedCode(doc, line, row.prefix)) return null;
  if (findTable(doc, line)) return null;
  if (line + 1 < doc.lineCount) {
    const next = doc.lineAt(line + 1).text;
    if (parseSeparator(next, prefixLength(next))) return null;
  }
  return { line, text, ...row };
}

/**
 * All tables of a document, in order (for the diagnostics).
 * @param {LineDoc} doc
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

module.exports = {
  findTable,
  inTableAt,
  carrySpan,
  pipeHeaderAt,
  scanTables,
  linesDoc,
};
