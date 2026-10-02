// Aligning a table: the grid (a table as editable cell text), its formatting in
// distribute/consolidate mode, and the minimal line edits from old to new text.
// Pure, no vscode import. Rules: docs/DECISIONS.md #49.

import { findTable, linesDoc } from './detect.ts';
import type { Table } from './detect.ts';
import { startsBlock } from './row.ts';
import type { Align } from './row.ts';
import { displayWidth } from './width.ts';

/**
 * One row of a `Grid`. `line` is the document line the row replaces; rows
 * without one are inserted after the row above them. `dirty` forces a rewrite
 * when the table is not auto-aligned; `origin` lets the sort find the source row.
 */
export interface GridRow {
  prefix: string;
  cells: string[];
  line?: number;
  sep?: boolean;
  dirty?: boolean;
  origin?: number;
}

/** A table as plain cell text, the form every table edit works on; `rows[1]` is the delimiter row (`sep: true`). */
export interface Grid {
  start: number;
  aligns: Align[];
  lead: boolean;
  trail: boolean;
  rows: GridRow[];
}

/** A replace of `start..end` on document line `line` with `text`. */
export interface LineEdit {
  line: number;
  start: number;
  end: number;
  text: string;
}

/**
 * The grid of a detected table. The border style (leading/trailing pipe) is the
 * header's; a borderless table stays borderless.
 */
function toGrid(table: Table): Grid {
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

// Column widths over the header and body rows, at least 3 (the delimiter `---`),
// plus each row's measured cell widths, so no cell is measured twice.
function columnWidths(
  grid: Grid,
  ambiguousWide: boolean,
): { widths: number[]; cellWidths: number[][] } {
  const widths = grid.aligns.map(() => 3);
  const cellWidths = grid.rows.map((row) => {
    if (row.sep) return [];
    const ws = row.cells.map((c) => displayWidth(c, ambiguousWide));
    for (const [i, w] of ws.entries()) {
      const widest = widths[i];
      if (widest !== undefined && w > widest) widths[i] = w;
    }
    return ws;
  });
  return { widths, cellWidths };
}

function delimiterCell(align: Align, width: number): string {
  const left = align === 'left' || align === 'center';
  const right = align === 'right' || align === 'center';
  const dashes = Math.max(1, width - (left ? 1 : 0) - (right ? 1 : 0));
  return (left ? ':' : '') + '-'.repeat(dashes) + (right ? ':' : '');
}

// Does a borderless row body leave the table? A block start ends it, a `>`
// changes the quote depth.
const leavesTable = (body: string): boolean =>
  startsBlock(body) || body.startsWith('>');

// A borderless body row the padding would push out of the table, written so it
// stays a row: an empty first cell gets a leading pipe (GFM trims the row, so
// only a pipe can hold it), a first cell like `*` is glued to its pipe
// (`*| x`, not a list item), anything still starting a block or a quote (`>`,
// a fence, `<div>`) gets a leading pipe.
function safeBorderless(
  body: string,
  first: string,
  distribute: boolean,
): string {
  if (first === '') return distribute ? `|${body.slice(1)}` : `| ${body}`;
  if (!leavesTable(body)) return body;
  const rest = body.slice(first.length);
  const glued = first + rest.replace(/^ +/, '');
  if (!leavesTable(glued)) return glued;
  // The pipe and its space take two columns of the first cell's padding.
  return `| ${first}${distribute && rest.startsWith('   ') ? rest.slice(2) : rest}`;
}

/**
 * Format a grid. `distribute` pads every column to its widest cell (display
 * width), `consolidate` uses single spaces. Only spaces and the delimiter row's
 * dash count change; colons, prefixes, borders and cell text stay. Rows short of
 * the header are filled with empty cells; cells beyond it are kept unpadded,
 * trailing empty ones dropped when the table has no right border.
 * @returns the lines, and in `widths` each line's display width (distribute
 *   only; derived from the measured cells)
 */
function formatGrid(
  grid: Grid,
  opts: { mode: 'distribute' | 'consolidate'; ambiguousWide?: boolean },
): { lines: string[]; widths: number[] } {
  const n = grid.aligns.length;
  const distribute = opts.mode === 'distribute';
  const { widths, cellWidths } = distribute
    ? columnWidths(grid, !!opts.ambiguousWide)
    : { widths: [], cellWidths: [] };
  const lines: string[] = [];
  const lineWidths: number[] = [];
  grid.rows.forEach((row, r) => {
    const rowWidths = cellWidths[r] ?? [];
    const texts = row.sep
      ? grid.aligns.map((a, i) =>
          delimiterCell(a, distribute ? (widths[i] ?? 3) : 3),
        )
      : row.cells.concat(
          Array<string>(Math.max(0, n - row.cells.length)).fill(''),
        );
    // Without a right border, an empty cell past the header would leave a
    // trailing `|` that the next pass reads as the border.
    if (!grid.trail)
      while (texts.length > n && texts.at(-1) === '') texts.pop();
    let line = row.prefix + (grid.lead ? '| ' : '');
    texts.forEach((text, i) => {
      if (i > 0) line += ' | ';
      line += text;
      const last = i === texts.length - 1;
      if (distribute && i < n && !row.sep && (grid.trail || !last))
        line += ' '.repeat((widths[i] ?? 0) - (rowWidths[i] ?? 0));
    });
    if (grid.trail) line += ' |';
    else line = line.trimEnd(); // an empty last cell of a borderless row
    if (!grid.lead && r > 1)
      line =
        row.prefix +
        safeBorderless(
          line.slice(row.prefix.length),
          texts[0] ?? '',
          distribute,
        );
    lines.push(line);
    // Only the cell texts are not plain ASCII: swap their lengths for widths.
    if (distribute) {
      let w = displayWidth(row.prefix, !!opts.ambiguousWide);
      w += line.length - row.prefix.length;
      texts.forEach((text, i) => {
        w += (row.sep ? text.length : (rowWidths[i] ?? 0)) - text.length;
      });
      lineWidths.push(w);
    }
  });
  return { lines, widths: lineWidths };
}

/**
 * Format for the automatic alignment (Enter, Tab, commands): distribute, unless
 * its widest line - prefix included, in display width - exceeds `maxWidth`
 * (0 = no limit); then consolidate (K1).
 */
function autoFormat(
  grid: Grid,
  opts: { maxWidth: number; ambiguousWide?: boolean },
): { lines: string[]; widths: number[] } {
  const wide = formatGrid(grid, { ...opts, mode: 'distribute' });
  if (opts.maxWidth > 0) {
    for (const w of wide.widths)
      if (w > opts.maxWidth)
        return formatGrid(grid, { ...opts, mode: 'consolidate' });
  }
  return wide;
}

/**
 * Minimal edits turning the document lines under a grid into `lines`: per
 * original row one replace of only the differing middle (common prefix and
 * suffix kept), inserted rows riding on the row above them. Unchanged rows
 * produce no edit, so an already aligned table yields none.
 * @param oldText document line text
 * @param lines formatted lines, parallel to grid.rows
 */
function lineEdits(
  oldText: (line: number) => string,
  grid: Grid,
  lines: readonly string[],
): LineEdit[] {
  const ops: LineEdit[] = [];
  for (let i = 0; i < grid.rows.length; ) {
    const line = grid.rows[i]?.line;
    let text = lines[i] ?? '';
    let j = i + 1;
    for (; j < grid.rows.length && grid.rows[j]?.line === undefined; j++)
      text += `\n${lines[j]}`;
    const old = line === undefined ? text : oldText(line);
    if (line !== undefined && old !== text) {
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

/**
 * Reflow the table starting at the first of `lines` (distribute or
 * consolidate); lines after it come back unchanged, non-table input as is.
 * The line-based reflow: the clipboard diff's style alignment and the editor's
 * `reflowTable` wrapper call it; the editor commands work on `toGrid`/`formatGrid`.
 */
function reflowTable(
  lines: readonly string[],
  mode: 'distribute' | 'consolidate',
  ambiguousWide = false,
): string[] {
  const table = findTable(linesDoc(lines), 0);
  if (!table) return lines.slice();
  const out = formatGrid(toGrid(table), { mode, ambiguousWide }).lines;
  return out.concat(lines.slice(table.end + 1));
}

export { toGrid, formatGrid, autoFormat, lineEdits, reflowTable };
