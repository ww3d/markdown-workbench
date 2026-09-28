// GFM row splitting for the editor's table model: the same cells markdown-it 15
// renders. Pure, no vscode import. Rules: docs/DECISIONS.md #48.

// The part of a line in front of the table: indentation and blockquote markers.
// Kept byte-identical by every edit.
const PREFIX_RE = /^(?:[ \t]*>)*[ \t]*/;
const SEPARATOR_CELL_RE = /^:?-+:?$/;
// Block starts that end a table even without a blank line (markdown-it's
// blockquote terminator rules): fence, ATX heading, thematic break, list item and
// the common HTML block tags. The HTML check is an approximation of html_block.
const TERMINATOR_RES = [
  /^(`{3,}|~{3,})/,
  /^#{1,6}(?:[ \t]|$)/,
  /^([-*_])(?:[ \t]*\1){2,}[ \t]*$/,
  /^(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)/,
  /^<(?:!--|\/?(?:div|p|table|pre|script|style|details|section|ul|ol|dl|h[1-6]|hr|blockquote)\b)/i,
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

/** Number of `>` markers in a prefix - rows of one table share it. */
function quoteDepth(prefix) {
  let n = 0;
  for (const ch of prefix) if (ch === '>') n++;
  return n;
}

/** Visual indentation after the last `>` of a prefix (tabs to the next 4-stop). */
function trailingIndent(prefix) {
  const ws = prefix.slice(prefix.lastIndexOf('>') + 1);
  let col = 0;
  for (const ch of ws) col = ch === '\t' ? col + 4 - (col % 4) : col + 1;
  return col;
}

// End of the line's content with trailing blanks trimmed.
function contentEnd(text) {
  let e = text.length;
  while (e > 0 && (text[e - 1] === ' ' || text[e - 1] === '\t')) e--;
  return e;
}

/**
 * Split a row into cells the way markdown-it 15 does (`escapedSplit`): a `|`
 * preceded by a backslash stays cell content, every other `|` - also one inside a
 * code span - separates. A leading and a trailing pipe are borders, not cells.
 * Offsets are absolute in `text`; `text` of a cell keeps its source form (`\|`).
 * @param {string} text the full line
 * @param {number} from where the row starts (after the prefix)
 * @returns {{ lead: boolean, trail: boolean, pipes: number[], cells: Array<{start: number, end: number, cStart: number, cEnd: number, text: string}> }}
 */
function splitRow(text, from) {
  const end = contentEnd(text);
  const pipes = [];
  for (let i = from; i < end; i++) {
    if (text[i] === '|' && text[i - 1] !== '\\') pipes.push(i);
  }
  // Segment bounds between the pipes, like escapedSplit's result array.
  const bounds = [];
  let s = from;
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
    while (cs < ce && (text[cs] === ' ' || text[cs] === '\t')) cs++;
    while (ce > cs && (text[ce - 1] === ' ' || text[ce - 1] === '\t')) ce--;
    return { start: a, end: b, cStart: cs, cEnd: ce, text: text.slice(cs, ce) };
  });
  return { lead, trail: trail && pipes.length > 0, pipes, cells };
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
  const body = text.slice(from, contentEnd(text));
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
 * Parse one line as a table row: its prefix plus the GFM cells.
 * @param {string} text
 * @returns {{ prefix: string, lead: boolean, trail: boolean, pipes: number[], cells: object[] }}
 */
function parseRow(text) {
  const p = prefixLength(text);
  return { prefix: text.slice(0, p), ...splitRow(text, p) };
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

module.exports = {
  prefixLength,
  quoteDepth,
  trailingIndent,
  contentEnd,
  splitRow,
  parseSeparator,
  parseRow,
  cellIndexAt,
  startsBlock,
};
