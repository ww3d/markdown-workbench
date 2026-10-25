// Tab- and comma-separated clipboard text to a table grid (X1). Pure.

/**
 * Parse CSV per RFC 4180: comma separated, `"` quotes a field, `""` inside a
 * quoted field is a literal quote, a quoted field may span lines.
 * @param {string} text
 * @returns {string[][]}
 */
function parseCsv(text) {
  const rows = [];
  let row = [],
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
 * @param {string} text
 * @returns {string[][] | null}
 */
function tabularRows(text) {
  const trimmed = text.replace(/(\r?\n)+$/, '');
  if (!trimmed) return null;
  const lines = trimmed.split(/\r?\n/);
  const tabs = lines.map((l) => l.split('\t').length);
  if (tabs[0] > 1 && tabs.every((n) => n === tabs[0]))
    return lines.map((l) => l.split('\t'));
  if (lines.length < 2) return null;
  const rows = parseCsv(trimmed);
  const n = rows[0].length;
  if (n < 2 || rows.length < 2 || rows.some((r) => r.length !== n)) return null;
  return rows;
}

// Cell text safe for a table: `|` escaped, line breaks as <br>, blanks trimmed.
function cellText(raw) {
  return raw.trim().replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
}

/**
 * A grid for pasted rows: the first row is the header, all rows share `prefix`.
 * @param {string[][]} rows
 * @param {string} prefix
 * @returns {import('./format.js').Grid}
 */
function gridFromRows(rows, prefix) {
  const n = Math.max(...rows.map((r) => r.length));
  const cells = (r) =>
    Array.from({ length: n }, (_, i) => cellText(r[i] ?? ''));
  return {
    start: 0,
    aligns: Array(n).fill(''),
    lead: true,
    trail: true,
    rows: [
      { prefix, cells: cells(rows[0]) },
      { prefix, cells: [], sep: true },
      ...rows.slice(1).map((r) => ({ prefix, cells: cells(r) })),
    ],
  };
}

module.exports = { parseCsv, tabularRows, gridFromRows };
