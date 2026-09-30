// Table detection for the editor: the tables the preview renders, read from the
// preview's own block parse (./blocks.ts); the cells with their positions come
// from our GFM split (./row.ts). No vscode import: a document is anything with
// `lineCount` + `lineAt(n).text`. Rules: docs/DECISIONS.md #49.

import { blocksOf, isParsed } from './blocks.ts';
import type { LineDoc } from './blocks.ts';
import { contentStart, parseSeparator, splitRow } from './row.ts';
import type { Align, ParsedRow } from './row.ts';

/** A table row: the parsed cells, the document line and that line's text. */
export interface TableRow extends ParsedRow {
  readonly line: number;
  readonly text: string;
}

/** A table as the preview renders it. */
export interface Table {
  /** Header line. */
  readonly start: number;
  /** Last body line. */
  readonly end: number;
  /** Alignment per column. */
  readonly aligns: readonly Align[];
  readonly columnCount: number;
  /** `rows[0]` is the header, `rows[1]` the delimiter row. */
  readonly rows: readonly [TableRow, TableRow, ...TableRow[]];
}

/** The part of a document change that `carrySpan` reads; a vscode content change fits. */
export interface Change {
  readonly range: {
    readonly start: { readonly line: number; readonly character: number };
    readonly end: { readonly line: number };
  };
  readonly text: string;
}

interface Span {
  readonly start: number;
  readonly end: number;
  readonly heads: readonly number[];
}

// The last span found per document, reused while the version stays - or is
// carried over an edit inside a body row (carrySpan) - so the selection-change
// context key does not rescan on every keystroke.
const spanCache = new WeakMap<
  LineDoc,
  Span & { pipes: readonly number[]; version: number }
>();

// Header line, last body line and the content start of every row of the table
// holding `line`, or null.
function tableSpan(doc: LineDoc, line: number): Span | null {
  if (line < 0 || line >= doc.lineCount) return null;
  const { lines } = blocksOf(doc);
  const hit = lines[line];
  if (hit?.kind !== 'table') return null;
  const start = hit.start;
  let end = line;
  for (
    let next = lines[end + 1];
    next?.kind === 'table' && next.start === start;
    next = lines[end + 1]
  )
    end++;
  const heads: number[] = [];
  for (let l = start; l <= end; l++) {
    const at = lines[l]?.at;
    if (at === undefined) return null;
    heads.push(at);
  }
  return { start, end, heads };
}

function remember(doc: LineDoc, span: Span | null): void {
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
function buildTable(doc: LineDoc, span: Span): Table | null {
  const rows: TableRow[] = [];
  for (const [i, head] of span.heads.entries()) {
    const l = span.start + i;
    const t = doc.lineAt(l).text;
    const row = splitRow(t, head);
    rows.push({ line: l, text: t, prefix: t.slice(0, row.rowStart), ...row });
  }
  const [header, delimiter, ...body] = rows;
  const delimiterHead = span.heads[1];
  if (!header || !delimiter || delimiterHead === undefined) return null;
  const aligns = parseSeparator(delimiter.text, delimiterHead) ?? [];
  return {
    start: span.start,
    end: span.end,
    aligns,
    columnCount: aligns.length,
    rows: [header, delimiter, ...body],
  };
}

/**
 * The table containing `line`, as the preview renders it: header, delimiter
 * row and body rows. Null outside a table, in code, HTML or the frontmatter.
 */
function findTable(doc: LineDoc, line: number): Table | null {
  const span = tableSpan(doc, line);
  if (!span) return null;
  remember(doc, span);
  return buildTable(doc, span);
}

// Whether the cached span of the current version holds `line`.
function spanHit(doc: LineDoc, line: number): boolean {
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
 */
function needsParse(doc: LineDoc, line: number): boolean {
  return !spanHit(doc, line) && !isParsed(doc);
}

/**
 * Whether `line` is a table row, without building the table: answered from the
 * cached span of the current document version where possible.
 */
function inTableAt(doc: LineDoc, line: number): boolean {
  if (spanHit(doc, line)) return true;
  const span = tableSpan(doc, line);
  remember(doc, span);
  return span !== null;
}

/**
 * Carry the cached span over a document change that only edits body rows of
 * that table behind their opening pipe, within the line (typing in a cell):
 * such an edit cannot end the row or the table. Any other change drops it.
 * @param doc the changed document (new version)
 */
function carrySpan(doc: LineDoc, changes: readonly Change[]): void {
  const hit = spanCache.get(doc);
  if (!hit || doc.version === undefined || hit.version !== doc.version - 1) {
    spanCache.delete(doc);
    return;
  }
  for (const c of changes) {
    const l = c.range.start.line;
    const pipe = hit.pipes[l - hit.start];
    const inBody = l > hit.start + 1 && l <= hit.end;
    const oneLine = c.range.end.line === l && !c.text.includes('\n');
    if (
      !inBody ||
      !oneLine ||
      pipe === undefined ||
      pipe < 0 ||
      c.range.start.character <= pipe
    ) {
      spanCache.delete(doc);
      return;
    }
  }
  hit.version = doc.version;
}

/**
 * A line typed as the start of a table (REQ-005): a paragraph line of the
 * preview whose content begins with `|`, with no delimiter row below it in the
 * same paragraph. Its
 * prefix is what precedes the content (quote markers, indent, a list marker on
 * the item's own line). Null otherwise - also in code, HTML and tables.
 */
function pipeHeaderAt(doc: LineDoc, line: number): TableRow | null {
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
 */
function scanTables(doc: LineDoc): Table[] {
  // Without `remember`: the cursor's cached span stays.
  return blocksOf(doc).tables.flatMap((l) => {
    const span = tableSpan(doc, l);
    const table = span && buildTable(doc, span);
    return table ? [table] : [];
  });
}

/**
 * Whether the preview would start a table at `line` of these lines - checked
 * before an edit writes a new table (E4), so it writes only what the preview
 * shows as one.
 */
function startsTableAt(lines: readonly string[], line: number): boolean {
  const hit = blocksOf(linesDoc(lines)).lines[line];
  return hit?.kind === 'table' && hit.start === line;
}

/** Adapt a string array to the document shape the model reads. */
function linesDoc(lines: readonly string[]): LineDoc {
  return { lineCount: lines.length, lineAt: (n) => ({ text: lines[n] ?? '' }) };
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
