// Aligning a table: the grid (a table as editable cell text), its formatting in
// distribute/consolidate mode, and the minimal line edits from old to new text.
// Pure, no vscode import. Rules: docs/DECISIONS.md #48.

const { displayWidth } = require('./width');
const { startsBlock } = require('./row');

/**
 * A table as plain cell text, the form every table edit works on. `line` is the
 * document line a row replaces; rows without one are inserted after the row
 * above them. `rows[1]` is the delimiter row (`sep: true`).
 * @typedef {{ prefix: string, cells: string[], line?: number, sep?: boolean }} GridRow
 * @typedef {{ start: number, aligns: string[], lead: boolean, trail: boolean, rows: GridRow[] }} Grid
 */

/**
 * The grid of a detected table. The border style (leading/trailing pipe) is the
 * header's; a borderless table stays borderless.
 * @param {import('./detect').Table} table
 * @returns {Grid}
 */
function toGrid(table) {
  const head = table.rows[0];
  return {
    start: table.start,
    aligns: [...table.aligns],
    lead: head.lead,
    trail: head.trail,
    rows: table.rows.map((r, i) => ({
      prefix: r.prefix,
      cells: r.cells.map((c) => c.text),
      line: r.line,
      sep: i === 1,
    })),
  };
}

// Column widths over the header and body rows, at least 3 (the delimiter `---`).
function columnWidths(grid, ambiguousWide) {
  const widths = grid.aligns.map(() => 3);
  for (const row of grid.rows) {
    if (row.sep) continue;
    for (let i = 0; i < widths.length && i < row.cells.length; i++) {
      const w = displayWidth(row.cells[i], ambiguousWide);
      if (w > widths[i]) widths[i] = w;
    }
  }
  return widths;
}

function delimiterCell(align, width) {
  const left = align === 'left' || align === 'center';
  const right = align === 'right' || align === 'center';
  const dashes = Math.max(1, width - (left ? 1 : 0) - (right ? 1 : 0));
  return (left ? ':' : '') + '-'.repeat(dashes) + (right ? ':' : '');
}

// Does a borderless row body leave the table? A block start ends it, a `>`
// changes the quote depth.
const leavesTable = (body) => startsBlock(body) || body.startsWith('>');

// A borderless body row the padding would push out of the table, written so it
// stays a row: an empty first cell gets a leading pipe (GFM trims the row, so
// only a pipe can hold it), a first cell like `*` is glued to its pipe
// (`*| x`, not a list item), anything still starting a block or a quote (`>`,
// a fence, `<div>`) gets a leading pipe.
function safeBorderless(body, first, distribute) {
  if (first === '') return distribute ? `|${body.slice(1)}` : `| ${body}`;
  if (!leavesTable(body)) return body;
  const glued = first + body.slice(first.length).replace(/^ +/, '');
  return leavesTable(glued) ? `| ${body}` : glued;
}

/**
 * Format a grid. `distribute` pads every column to its widest cell (display
 * width), `consolidate` uses single spaces. Only spaces and the delimiter row's
 * dash count change; colons, prefixes, borders and cell text stay. Rows short of
 * the header are filled with empty cells; cells beyond it are kept unpadded.
 * @param {Grid} grid
 * @param {{ mode: 'distribute' | 'consolidate', ambiguousWide?: boolean }} opts
 * @returns {{ lines: string[] }}
 */
function formatGrid(grid, opts) {
  const n = grid.aligns.length;
  const distribute = opts.mode === 'distribute';
  const widths = distribute ? columnWidths(grid, !!opts.ambiguousWide) : [];
  const lines = [];
  grid.rows.forEach((row, r) => {
    const texts = row.sep
      ? grid.aligns.map((a, i) => delimiterCell(a, distribute ? widths[i] : 3))
      : row.cells.concat(Array(Math.max(0, n - row.cells.length)).fill(''));
    let line = row.prefix + (grid.lead ? '| ' : '');
    texts.forEach((text, i) => {
      if (i > 0) line += ' | ';
      line += text;
      const last = i === texts.length - 1;
      if (distribute && i < n && !row.sep && (grid.trail || !last))
        line += ' '.repeat(
          widths[i] - displayWidth(text, !!opts.ambiguousWide),
        );
    });
    if (grid.trail) line += ' |';
    else line = line.trimEnd(); // an empty last cell of a borderless row
    if (!grid.lead && r > 1)
      line =
        row.prefix +
        safeBorderless(line.slice(row.prefix.length), texts[0], distribute);
    lines.push(line);
  });
  return { lines };
}

/**
 * Format for the automatic alignment (Enter, Tab, commands): distribute, unless
 * its widest line - prefix included, in display width - exceeds `maxWidth`
 * (0 = no limit); then consolidate (K1).
 * @param {Grid} grid
 * @param {{ maxWidth: number, ambiguousWide?: boolean }} opts
 */
function autoFormat(grid, opts) {
  const wide = formatGrid(grid, { ...opts, mode: 'distribute' });
  if (opts.maxWidth > 0) {
    for (const line of wide.lines) {
      if (displayWidth(line, !!opts.ambiguousWide) > opts.maxWidth)
        return formatGrid(grid, { ...opts, mode: 'consolidate' });
    }
  }
  return wide;
}

/**
 * Minimal edits turning the document lines under a grid into `lines`: per
 * original row one replace of only the differing middle (common prefix and
 * suffix kept), inserted rows riding on the row above them. Unchanged rows
 * produce no edit, so an already aligned table yields none.
 * @param {(line: number) => string} oldText document line text
 * @param {Grid} grid
 * @param {string[]} lines formatted lines, parallel to grid.rows
 * @returns {Array<{ line: number, start: number, end: number, text: string }>}
 */
function lineEdits(oldText, grid, lines) {
  const ops = [];
  for (let i = 0; i < grid.rows.length; ) {
    const line = grid.rows[i].line;
    let text = lines[i];
    let j = i + 1;
    for (; j < grid.rows.length && grid.rows[j].line === undefined; j++)
      text += `\n${lines[j]}`;
    const old = oldText(line);
    if (old !== text) {
      let p = 0;
      const max = Math.min(old.length, text.length);
      while (p < max && old[p] === text[p]) p++;
      let s = 0;
      while (
        s < max - p &&
        old[old.length - 1 - s] === text[text.length - 1 - s]
      )
        s++;
      ops.push({
        line,
        start: p,
        end: old.length - s,
        text: text.slice(p, text.length - s),
      });
    }
    i = j;
  }
  return ops;
}

module.exports = { toGrid, formatGrid, autoFormat, lineEdits };
