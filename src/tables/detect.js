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
  listMarkerWidth,
  prefixAt,
} = require('./row');
const { codeMask, isIndentedCode, listContext } = require('./code-mask');

// Can `line` continue a table with header shape `info` (quote level `depth`,
// block indent `min`)? Like markdown-it: the row needs exactly the table's
// quote markers (fewer is a lazy line, more a nested quote); 4+ columns past
// the block are code; a block start ends the table.
function isBodyRow(doc, line, info, mask) {
  if (line >= doc.lineCount || mask[line]) return false;
  const text = doc.lineAt(line).text;
  const p = prefixAt(text, info.depth);
  if (p < 0 || p >= contentEnd(text) || text[p] === '>') return false;
  const rowIndent = trailingIndent(text.slice(0, p));
  if (rowIndent < info.min || rowIndent - info.min >= 4) return false;
  return !startsBlock(text.slice(p));
}

// A table whose header content starts at `p` and delimiter row at `sp`, in a
// block indented `min`: its alignments, or null.
function tableAt(text, p, sepText, sp, indent, min) {
  if (!text.slice(p).includes('|') || indent - min >= 4) return null;
  const sepIndent = trailingIndent(sepText.slice(0, sp));
  if (sepIndent < min || sepIndent - min >= 4) return null;
  const aligns = parseSeparator(sepText, sp);
  if (!aligns || splitRow(text, p).cells.length !== aligns.length) return null;
  return aligns;
}

// Is line `h` a lazy continuation of a deeper quote at level `k`? In
// markdown-it a line without the quote's `>` continues the quote only while
// the quote's last block is a paragraph, and only if it starts no block.
function inLazyQuote(doc, h, k, mask) {
  const own = doc.lineAt(h).text;
  if (startsBlock(own.slice(prefixAt(own, k)))) return false;
  for (let l = h - 1; l >= 0; l--) {
    const t = doc.lineAt(l).text;
    const at = prefixAt(t, k);
    if (at >= 0 && at >= contentEnd(t)) return false;
    const p = prefixLength(t);
    if (quoteDepth(t.slice(0, p)) > k) {
      const inner = t.slice(p);
      if (p >= contentEnd(t) || startsBlock(inner)) return false;
      return tableSpan(doc, l, mask) === null;
    }
    if (at < 0 || startsBlock(t.slice(at))) return false;
  }
  return false;
}

// Does a quote deeper than level `k` run on into line `h`? Then a `>` there
// continues that quote instead of starting a table at level `k`.
function quoteOpenAbove(doc, h, k, mask) {
  if (h === 0 || mask[h - 1]) return false;
  const t = doc.lineAt(h - 1).text;
  if (prefixAt(t, k) < 0) return false;
  return (
    quoteDepth(t.slice(0, prefixLength(t))) > k ||
    inLazyQuote(doc, h - 1, k, mask)
  );
}

// The header at `h` read at quote level `k`, like markdown-it's rule order in
// that block: the table rule first (a list marker is content then), else a
// list item on the header's own line (`- | a | b |`). A lazy line of a list
// item's paragraph starts a table only where its delimiter row would pass in
// the item; that ends the item, and the table stands outside it. A line
// starting a quote ends the item too.
function headerAtLevel(doc, h, text, sepText, k, mask) {
  const p = prefixAt(text, k);
  const sp = prefixAt(sepText, k);
  if (p < 0 || sp < 0 || inLazyQuote(doc, h, k, mask)) return null;
  if (text[p] === '>' && quoteOpenAbove(doc, h, k, mask)) return null;
  const prefix = text.slice(0, p);
  const indent = trailingIndent(prefix);
  const marker = listMarkerWidth(text.slice(p));
  let ctx = listContext(doc, h, prefix);
  if (ctx?.lazy) {
    const sepIndent = trailingIndent(sepText.slice(0, sp));
    const ends =
      text[p] === '>' || (sepIndent >= ctx.c && sepIndent - ctx.c < 4);
    if (!ends) return null;
    ctx = null;
  }
  const min = ctx ? ctx.c : 0;
  if (!ctx || !marker) {
    const aligns = tableAt(text, p, sepText, sp, indent, min);
    if (aligns) return { aligns, depth: k, indent, min, head: p };
  }
  if (!marker) return null;
  const c = indent + marker;
  const aligns = tableAt(text, p + marker, sepText, sp, c, c);
  return aligns && { aligns, depth: k, indent: c, min: c, head: p + marker };
}

// The header at `h` with its delimiter row below, outermost quote level
// first (markdown-it tries the table rule before descending into a quote).
function headerAt(doc, h, mask) {
  if (h < 0 || h + 1 >= doc.lineCount || mask[h] || mask[h + 1]) return null;
  const text = doc.lineAt(h).text;
  if (!text.includes('|')) return null;
  const sepText = doc.lineAt(h + 1).text;
  const depth = quoteDepth(text.slice(0, prefixLength(text)));
  for (let k = 0; k <= depth; k++) {
    const info = headerAtLevel(doc, h, text, sepText, k, mask);
    if (info) return info;
  }
  return null;
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
  let top = line;
  while (top > 0 && !mask[top - 1]) {
    const t = doc.lineAt(top - 1).text;
    if (prefixLength(t) >= contentEnd(t)) break;
    top--;
  }
  for (let l = top; l <= line; ) {
    const info = headerAt(doc, l, mask);
    if (!info) {
      l++;
      continue;
    }
    let end = l + 1;
    while (isBodyRow(doc, end + 1, info, mask)) end++;
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
    const p = l === span.start ? span.head : prefixAt(t, span.depth);
    rows.push({ line: l, text: t, prefix: t.slice(0, p), ...splitRow(t, p) });
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
    if (!inBody || !oneLine || !isBodyRow(doc, l, hit, NO_MASK))
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
