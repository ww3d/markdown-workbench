// Table detection for the editor: the tables the preview renders, read from the
// preview's own block parse (./blocks.js); the cells with their positions come
// from our GFM split (./row.js). No vscode import: a document is anything with
// `lineCount` + `lineAt(n).text`. Rules: docs/DECISIONS.md #49.

import { contentStart, splitRow, parseSeparator } from './row.js';
import { blocksOf, isParsed } from './blocks.js';

/**
 * @typedef {{ lineCount: number, lineAt(n: number): { text: string }, version?: number }} LineDoc
 * @typedef {import('./row').ParsedRow & { line: number, text: string }} TableRow
 * @typedef {object} Table
 * @property {number} start header line
 * @property {number} end last body line
 * @property {string[]} aligns per column '', 'left', 'right' or 'center'
 * @property {number} columnCount
 * @property {TableRow[]} rows `rows[0]` is the header, `rows[1]` the delimiter row
 * @typedef {{ start: { line: number, character: number }, end: { line: number } }} ChangeRange
 * @typedef {{ range: ChangeRange, text: string }} Change
 */

// The last span found per document, reused while the version stays - or is
// carried over an edit inside a body row (carrySpan) - so the selection-change
// context key does not rescan on every keystroke.
const spanCache = new WeakMap();

// Header line, last body line and the content start of every row of the table
// holding `line`, or null.
function tableSpan(doc, line) {
  if (line < 0 || line >= doc.lineCount) return null;
  const { lines } = blocksOf(doc);
  const hit = lines[line];
  if (hit?.kind !== 'table') return null;
  const start = hit.start;
  let end = line;
  while (lines[end + 1]?.kind === 'table' && lines[end + 1].start === start)
    end++;
  const heads = [];
  for (let l = start; l <= end; l++) heads.push(lines[l].at);
  return { start, end, heads };
}

function remember(doc, span) {
  if (!span || doc.version === undefined) return;
  // Where each row's opening pipe stands (-1 without one): no edit behind it
  // can end the row.
  const pipes = span.heads.map((h, i) => {
    const text = doc.lineAt(span.start + i).text;
    const at = contentStart(text, h);
    return text[at] === '|' ? at : -1;
  });
  spanCache.set(doc, { ...span, pipes, version: doc.version });
}

// The table of a span: its rows split into cells.
function buildTable(doc, span) {
  const rows = [];
  for (let l = span.start; l <= span.end; l++) {
    const t = doc.lineAt(l).text;
    const row = splitRow(t, span.heads[l - span.start]);
    rows.push({ line: l, text: t, prefix: t.slice(0, row.rowStart), ...row });
  }
  const aligns = parseSeparator(rows[1].text, span.heads[1]) ?? [];
  return {
    start: span.start,
    end: span.end,
    aligns,
    columnCount: aligns.length,
    rows,
  };
}

/**
 * The table containing `line`, as the preview renders it: header, delimiter
 * row and body rows. Null outside a table, in code, HTML or the frontmatter.
 * @param {LineDoc} doc
 * @param {number} line
 * @returns {Table | null}
 */
function findTable(doc, line) {
  const span = tableSpan(doc, line);
  if (!span) return null;
  remember(doc, span);
  return buildTable(doc, span);
}

// Whether the cached span of the current version holds `line`.
function spanHit(doc, line) {
  const hit = spanCache.get(doc);
  return (
    hit !== undefined &&
    hit.version === doc.version &&
    line >= hit.start &&
    line <= hit.end
  );
}

/**
 * Whether answering `inTableAt` for `line` costs a block parse: no cached span
 * holds it and the document changed since the last parse.
 * @param {LineDoc} doc
 * @param {number} line
 */
function needsParse(doc, line) {
  return !spanHit(doc, line) && !isParsed(doc);
}

/**
 * Whether `line` is a table row, without building the table: answered from the
 * cached span of the current document version where possible.
 * @param {LineDoc} doc
 * @param {number} line
 */
function inTableAt(doc, line) {
  if (spanHit(doc, line)) return true;
  const span = tableSpan(doc, line);
  remember(doc, span);
  return span !== null;
}

/**
 * Carry the cached span over a document change that only edits body rows of
 * that table behind their opening pipe, within the line (typing in a cell):
 * such an edit cannot end the row or the table. Any other change drops it.
 * @param {LineDoc} doc the changed document (new version)
 * @param {ReadonlyArray<Change>} changes
 */
function carrySpan(doc, changes) {
  const hit = spanCache.get(doc);
  if (!hit || doc.version === undefined || hit.version !== doc.version - 1)
    return spanCache.delete(doc);
  for (const c of changes) {
    const l = c.range.start.line;
    const i = l - hit.start;
    const inBody = l > hit.start + 1 && l <= hit.end;
    const oneLine = c.range.end.line === l && !c.text.includes('\n');
    if (
      !inBody ||
      !oneLine ||
      hit.pipes[i] < 0 ||
      c.range.start.character <= hit.pipes[i]
    )
      return spanCache.delete(doc);
  }
  hit.version = doc.version;
}

/**
 * A line typed as the start of a table (REQ-005): a paragraph line of the
 * preview whose content begins with `|`, with no delimiter row below it in the
 * same paragraph. Its
 * prefix is what precedes the content (quote markers, indent, a list marker on
 * the item's own line). Null otherwise - also in code, HTML and tables.
 * @param {LineDoc} doc
 * @param {number} line
 */
function pipeHeaderAt(doc, line) {
  if (line < 0 || line >= doc.lineCount) return null;
  const { lines } = blocksOf(doc);
  const hit = lines[line];
  if (hit?.kind !== 'paragraph') return null;
  const text = doc.lineAt(line).text;
  if (text[contentStart(text, hit.at)] !== '|') return null;
  // A delimiter-like next line of the same paragraph: the preview declined the
  // table (cell counts differ), so Enter must not add a second delimiter row.
  const below = lines[line + 1];
  if (below?.kind === 'paragraph' && below.start === hit.start) {
    if (parseSeparator(doc.lineAt(line + 1).text, below.at)) return null;
  }
  const row = splitRow(text, hit.at);
  return { line, text, prefix: text.slice(0, row.rowStart), ...row };
}

/**
 * All tables of a document, in order (for the diagnostics).
 * @param {LineDoc} doc
 */
function scanTables(doc) {
  // Without `remember`: the cursor's cached span stays.
  return blocksOf(doc).tables.map((l) => buildTable(doc, tableSpan(doc, l)));
}

/**
 * Whether the preview would start a table at `line` of these lines - checked
 * before an edit writes a new table (E4), so it writes only what the preview
 * shows as one.
 * @param {string[]} lines
 * @param {number} line
 */
function startsTableAt(lines, line) {
  const hit = blocksOf(linesDoc(lines)).lines[line];
  return hit?.kind === 'table' && hit.start === line;
}

/** Adapt a string array to the document shape the model reads. */
function linesDoc(lines) {
  return { lineCount: lines.length, lineAt: (n) => ({ text: lines[n] }) };
}

export {
  findTable,
  inTableAt,
  needsParse,
  carrySpan,
  pipeHeaderAt,
  startsTableAt,
  scanTables,
  linesDoc,
};
