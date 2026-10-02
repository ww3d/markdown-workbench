// GFM row splitting for the editor's table model: the same cells markdown-it 15
// renders. Pure, no vscode import. Rules: docs/DECISIONS.md #49.

// The part of a line in front of the table: indentation and blockquote markers.
// Kept byte-identical by every edit.
const PREFIX_RE = /^(?:[ \t]*>)*[ \t]*/;
const SEPARATOR_CELL_RE = /^:?-+:?$/;
// HTML block starts of CommonMark types 1-6 (type 7 cannot interrupt a
// paragraph or a table): raw text tags, comment, processing instruction,
// declaration, CDATA, and the block tag names.
const BLOCK_TAGS =
  'address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul';
const HTML_START_RE = new RegExp(
  `^<(?:(?:script|pre|style|textarea)(?:[ \\t>]|$)|!--|\\?|![A-Za-z]|!\\[CDATA\\[|/?(?:${BLOCK_TAGS})(?:[ \\t>]|/>|$))`,
  'i',
);
// Block starts that end a borderless row when padding exposes them (the
// formatter keeps such rows inside the table): fence, ATX heading, thematic
// break, list item, HTML block.
const TERMINATOR_RES = [
  /^(`{3,}|~{3,})/,
  /^#{1,6}(?:[ \t]|$)/,
  /^([-*_])(?:[ \t]*\1){2,}[ \t]*$/,
  /^(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)/,
  HTML_START_RE,
];

/** Whether a row body (after the prefix) starts a block that ends a table. */
function startsBlock(body: string): boolean {
  return TERMINATOR_RES.some((re) => re.test(body));
}

/** Length of the table prefix (indentation, `>` markers) of a line. */
function prefixLength(text: string): number {
  return PREFIX_RE.exec(text)?.[0].length ?? 0;
}

/** Column alignment of a delimiter cell: none, or `left`, `right`, `center`. */
export type Align = '' | 'left' | 'right' | 'center';

/**
 * A cell of a parsed row. `start`/`end` bound its segment between the pipes,
 * `cStart`/`cEnd` its content without the padding (absolute line offsets).
 */
export interface Cell {
  readonly start: number;
  readonly end: number;
  readonly cStart: number;
  readonly cEnd: number;
  readonly text: string;
}

/** A row split into cells; `rowStart` is where it starts after leading whitespace, where the prefix ends. */
export interface SplitRow {
  readonly rowStart: number;
  readonly lead: boolean;
  readonly trail: boolean;
  readonly pipes: readonly number[];
  readonly cells: readonly Cell[];
}

/** A split row together with the prefix (indentation, quote markers) in front of it. */
export interface ParsedRow extends SplitRow {
  readonly prefix: string;
}

// Whitespace as `String.prototype.trim` sees it (NBSP, U+3000 ...): markdown-it
// trims rows and cells with it.
const WS_RE = /\s/;
const isWs = (ch: string | undefined): boolean =>
  ch !== undefined && WS_RE.test(ch);

/** End of the line's content with trailing whitespace trimmed (like `trim`). */
function contentEnd(text: string): number {
  let e = text.length;
  while (e > 0 && isWs(text[e - 1])) e--;
  return e;
}

/** First offset at or after `from` that is not whitespace (like `trim`). */
function contentStart(text: string, from: number): number {
  let s = from;
  while (s < text.length && isWs(text[s])) s++;
  return s;
}

// A segment between two pipes as [start, end); a leading or trailing empty one is a border.
type Bound = readonly [number, number];
const isEmptyBound = (b: Bound | undefined): boolean =>
  b !== undefined && b[0] === b[1];

/**
 * Split a row into cells the way markdown-it 15 does (`escapedSplit`): a `|`
 * preceded by a backslash stays cell content, every other `|` - also one inside a
 * code span - separates. A leading and a trailing pipe are borders, not cells.
 * Offsets are absolute in `text`; `text` of a cell keeps its source form (`\|`).
 * @param text the full line
 * @param from where the row starts (after the prefix)
 */
function splitRow(text: string, from: number): SplitRow {
  const end = contentEnd(text);
  const rowStart = Math.min(contentStart(text, from), end);
  const pipes: number[] = [];
  for (let i = rowStart; i < end; i++) {
    if (text[i] === '|' && text[i - 1] !== '\\') pipes.push(i);
  }
  // Segment bounds between the pipes, like escapedSplit's result array.
  const bounds: Bound[] = [];
  let s = rowStart;
  for (const p of pipes) {
    bounds.push([s, p]);
    s = p + 1;
  }
  bounds.push([s, end]);
  const lead = bounds.length > 1 && isEmptyBound(bounds[0]);
  if (lead) bounds.shift();
  const trail = bounds.length > 0 && isEmptyBound(bounds.at(-1));
  if (trail && pipes.length > 0) bounds.pop();
  const cells = bounds.map(([a, b]) => {
    let cs = a,
      ce = b;
    while (cs < ce && isWs(text[cs])) cs++;
    while (ce > cs && isWs(text[ce - 1])) ce--;
    return { start: a, end: b, cStart: cs, cEnd: ce, text: text.slice(cs, ce) };
  });
  return { rowStart, lead, trail: trail && pipes.length > 0, pipes, cells };
}

/**
 * Alignments of a delimiter row, or null when the line is none. Mirrors
 * markdown-it: only `|`, `-`, `:` and blanks, no `- ` start (a list item), and
 * every inner cell `:?-+:?`.
 * @returns the alignment per column, or null
 */
function parseSeparator(text: string, from: number): Align[] | null {
  const body = text.slice(contentStart(text, from), contentEnd(text));
  if (body.length < 2) return null;
  const c0 = body.charAt(0),
    c1 = body.charAt(1);
  if (c0 !== '|' && c0 !== '-' && c0 !== ':') return null;
  if (c1 !== '|' && c1 !== '-' && c1 !== ':' && c1 !== ' ' && c1 !== '\t')
    return null;
  if (c0 === '-' && (c1 === ' ' || c1 === '\t')) return null;
  if (!/^[|\-: \t]*$/.test(body)) return null;
  const columns = body.split('|');
  const aligns: Align[] = [];
  for (const [i, column] of columns.entries()) {
    const t = column.trim();
    if (!t) {
      if (i === 0 || i === columns.length - 1) continue;
      return null;
    }
    if (!SEPARATOR_CELL_RE.test(t)) return null;
    const left = t.startsWith(':'),
      right = t.endsWith(':');
    aligns.push(
      left && right ? 'center' : right ? 'right' : left ? 'left' : '',
    );
  }
  return aligns.length ? aligns : null;
}

/**
 * A row prefix with every list marker blanked (tabs kept, so columns stay):
 * the prefix of the rows below a header on a list item's line.
 */
function continuationPrefix(prefix: string): string {
  return prefix.replace(/(?:[-*+]|\d{1,9}[.)])(?=[ \t]|$)/g, (m) =>
    ' '.repeat(m.length),
  );
}

/**
 * Parse one line as a table row: its prefix plus the GFM cells.
 */
function parseRow(text: string): ParsedRow {
  const row = splitRow(text, prefixLength(text));
  return { prefix: text.slice(0, row.rowStart), ...row };
}

/**
 * Index of the cell holding character `ch` of a parsed row: -1 before the
 * leading pipe (or before the row), otherwise the cell whose segment contains
 * it (a pipe belongs to the cell left of it); past the last cell the last one.
 */
function cellIndexAt(
  row: {
    readonly prefix: string;
    readonly lead: boolean;
    readonly cells: readonly Pick<Cell, 'start' | 'end'>[];
  },
  ch: number,
): number {
  const first = row.cells[0];
  if (!first) return -1;
  if (row.lead ? ch <= first.start - 1 : ch < row.prefix.length) return -1;
  for (const [i, cell] of row.cells.entries()) if (ch <= cell.end) return i;
  return row.cells.length - 1;
}

export {
  prefixLength,
  contentEnd,
  contentStart,
  splitRow,
  parseSeparator,
  parseRow,
  cellIndexAt,
  startsBlock,
  continuationPrefix,
};
