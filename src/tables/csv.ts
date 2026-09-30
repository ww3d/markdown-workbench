// Tab- and comma-separated clipboard text to a table grid (X1). Pure.

import type { Grid } from './format.ts';
import type { Align } from './row.ts';

/**
 * Parse CSV per RFC 4180: comma separated, `"` quotes a field, `""` inside a
 * quoted field is a literal quote, a quoted field may span lines.
 */
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [],
    field = '',
    quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"' && field === '') quoted = true;
    else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else field += ch;
  }
  if (field !== '' || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

/**
 * The rows of pasted text when it is a table: TSV when every line has the same
 * number (>= 1) of tabs, else CSV when it has at least two rows of the same
 * field count (>= 2). Null for anything else (prose, a single CSV line).
 * @returns the rows, or null when the text is no table
 */
function tabularRows(text: string): string[][] | null {
  const trimmed = text.replace(/(\r?\n)+$/, '');
  if (!trimmed) return null;
  const lines = trimmed.split(/\r?\n/);
  const tabs = lines.map((l) => l.split('\t').length);
  const first = tabs[0] ?? 0;
  if (first > 1 && tabs.every((n) => n === first))
    return lines.map((l) => l.split('\t'));
  if (lines.length < 2) return null;
  const rows = parseCsv(trimmed);
  const n = rows[0]?.length ?? 0;
  if (n < 2 || rows.length < 2 || rows.some((r) => r.length !== n)) return null;
  return rows;
}

// Cell text safe for a table: `|` escaped, line breaks as <br>, blanks trimmed.
function cellText(raw: string): string {
  return raw.trim().replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
}

/**
 * A grid for pasted rows: the first row is the header, all rows share `prefix`.
 */
function gridFromRows(
  rows: readonly (readonly string[])[],
  prefix: string,
): Grid {
  const n = Math.max(...rows.map((r) => r.length));
  const cells = (r: readonly string[]) =>
    Array.from({ length: n }, (_, i) => cellText(r[i] ?? ''));
  const [header = [], ...body] = rows;
  return {
    start: 0,
    aligns: Array<Align>(n).fill(''),
    lead: true,
    trail: true,
    rows: [
      { prefix, cells: cells(header) },
      { prefix, cells: [], sep: true },
      ...body.map((r) => ({ prefix, cells: cells(r) })),
    ],
  };
}

export { parseCsv, tabularRows, gridFromRows };
