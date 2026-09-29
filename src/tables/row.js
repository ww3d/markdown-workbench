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

/**
 * Whether a row body (after the prefix) starts a block that ends a table.
 * @param {string} body
 */
function startsBlock(body) {
  return TERMINATOR_RES.some((re) => re.test(body));
}

/**
 * Length of the table prefix (indentation, `>` markers) of a line.
 * @param {string} text
 * @returns {number}
 */
function prefixLength(text) {
  return PREFIX_RE.exec(text)[0].length;
}

/**
 * A cell of a parsed row. `start`/`end` bound its segment between the pipes,
 * `cStart`/`cEnd` its content without the padding (absolute line offsets).
 * @typedef {{ start: number, end: number, cStart: number, cEnd: number, text: string }} Cell
 * @typedef {{ rowStart: number, lead: boolean, trail: boolean, pipes: number[], cells: Cell[] }} SplitRow
 *   `rowStart`: where the row starts after leading whitespace - the prefix ends there
 * @typedef {SplitRow & { prefix: string }} ParsedRow
 */

// Whitespace as `String.prototype.trim` sees it (NBSP, U+3000 ...): markdown-it
// trims rows and cells with it.
const WS_RE = /\s/;
const isWs = (ch) => ch !== undefined && WS_RE.test(ch);

/** End of the line's content with trailing whitespace trimmed (like `trim`). */
function contentEnd(text) {
  let e = text.length;
  while (e > 0 && isWs(text[e - 1])) e--;
  return e;
}

/** First offset at or after `from` that is not whitespace (like `trim`). */
function contentStart(text, from) {
  let s = from;
  while (s < text.length && isWs(text[s])) s++;
  return s;
}

/**
 * Split a row into cells the way markdown-it 15 does (`escapedSplit`): a `|`
 * preceded by a backslash stays cell content, every other `|` - also one inside a
 * code span - separates. A leading and a trailing pipe are borders, not cells.
 * Offsets are absolute in `text`; `text` of a cell keeps its source form (`\|`).
 * @param {string} text the full line
 * @param {number} from where the row starts (after the prefix)
 * @returns {SplitRow}
 */
function splitRow(text, from) {
  const end = contentEnd(text);
  const rowStart = Math.min(contentStart(text, from), end);
  const pipes = [];
  for (let i = rowStart; i < end; i++) {
    if (text[i] === '|' && text[i - 1] !== '\\') pipes.push(i);
  }
  // Segment bounds between the pipes, like escapedSplit's result array.
  const bounds = [];
  let s = rowStart;
  for (const p of pipes) {
    bounds.push([s, p]);
    s = p + 1;
  }
  bounds.push([s, end]);
  const lead = bounds.length > 1 && bounds[0][0] === bounds[0][1];
  if (lead) bounds.shift();
  const trail = bounds.length > 0 && bounds.at(-1)[0] === bounds.at(-1)[1];
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
 * @param {string} text
 * @param {number} from
 * @returns {string[] | null} per column '', 'left', 'right' or 'center'
 */
function parseSeparator(text, from) {
  const body = text.slice(contentStart(text, from), contentEnd(text));
  if (body.length < 2) return null;
  const c0 = body[0],
    c1 = body[1];
  if (c0 !== '|' && c0 !== '-' && c0 !== ':') return null;
  if (c1 !== '|' && c1 !== '-' && c1 !== ':' && c1 !== ' ' && c1 !== '\t')
    return null;
  if (c0 === '-' && (c1 === ' ' || c1 === '\t')) return null;
  if (!/^[|\-: \t]*$/.test(body)) return null;
  const columns = body.split('|');
  const aligns = [];
  for (let i = 0; i < columns.length; i++) {
    const t = columns[i].trim();
    if (!t) {
      if (i === 0 || i === columns.length - 1) continue;
      return null;
    }
    if (!SEPARATOR_CELL_RE.test(t)) return null;
    const left = t[0] === ':',
      right = t.at(-1) === ':';
    aligns.push(
      left && right ? 'center' : right ? 'right' : left ? 'left' : '',
    );
  }
  return aligns.length ? aligns : null;
}

/**
 * A row prefix with every list marker blanked (tabs kept, so columns stay):
 * the prefix of the rows below a header on a list item's line.
 * @param {string} prefix
 */
function continuationPrefix(prefix) {
  return prefix.replace(/(?:[-*+]|\d{1,9}[.)])(?=[ \t]|$)/g, (m) =>
    ' '.repeat(m.length),
  );
}

/**
 * Parse one line as a table row: its prefix plus the GFM cells.
 * @param {string} text
 * @returns {ParsedRow}
 */
function parseRow(text) {
  const row = splitRow(text, prefixLength(text));
  return { prefix: text.slice(0, row.rowStart), ...row };
}

/**
 * Index of the cell holding character `ch` of a parsed row: -1 before the
 * leading pipe (or before the row), otherwise the cell whose segment contains
 * it (a pipe belongs to the cell left of it); past the last cell the last one.
 * @param {{ prefix: string, lead: boolean, cells: Array<{start: number, end: number}> }} row
 * @param {number} ch
 */
function cellIndexAt(row, ch) {
  if (!row.cells.length) return -1;
  if (row.lead ? ch <= row.cells[0].start - 1 : ch < row.prefix.length)
    return -1;
  for (let i = 0; i < row.cells.length; i++)
    if (ch <= row.cells[i].end) return i;
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
