// --- Column stops for markerless continuation lines -----------------------------
//
// Tab/Shift+Tab on a line that is NOT a list item (execListItem null) does not
// shift by a fixed amount; it snaps the line's indentation onto a column stop.
// List-item lines are untouched by this path - their structural nesting and
// renumbering stay exactly as before.
const vscode = require('vscode');
const { execListItem } = require('./list-markers');
const { contentColumn, leadingWhitespace } = require('./list-structure');

/**
 * Configured continuation-stop search radius (lines above/below), falling back to 5
 * when unset or not a non-negative number.
 * @returns {number}
 */
function continuationStopRadius() {
  const n = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get('indent.continuationStopRadius', 5);
  return Number.isFinite(n) && n >= 0 ? n : 5;
}

// Visual column width of a leading-whitespace string, tabs expanding to the
// next multiple of tabSize.
function indentColumns(ws, tabSize) {
  let col = 0;
  for (const ch of ws)
    col = ch === '\t' ? (Math.floor(col / tabSize) + 1) * tabSize : col + 1;
  return col;
}

// Columns at which a word begins on a line (each whitespace -> non-whitespace
// transition), tab-expanded, in the same column space as the indentation.
function wordStartColumns(text, tabSize) {
  const cols = [];
  let col = 0,
    prevWs = true;
  for (const ch of text) {
    const ws = ch === ' ' || ch === '\t';
    if (!ws && prevWs) cols.push(col);
    prevWs = ws;
    col = ch === '\t' ? (Math.floor(col / tabSize) + 1) * tabSize : col + 1;
  }
  return cols;
}

// The sorted column stops for a markerless line: column 0, the indent and
// content columns of nearby list items, every word start of nearby lines (all
// within `radius` lines above and below), plus the multiples of tabSize so a
// forward step is always available.
function collectColumnStops(
  document,
  line,
  tabSize,
  radius,
  currentCol,
  exclude,
) {
  const skip = exclude || new Set([line]);
  const stops = new Set([0]);
  let maxDetected = 0;
  const lo = Math.max(0, line - radius),
    hi = Math.min(document.lineCount - 1, line + radius);
  for (let l = lo; l <= hi; l++) {
    if (skip.has(l)) continue;
    const text = document.lineAt(l).text;
    const m = execListItem(text);
    if (m) {
      const indent = indentColumns(m[1], tabSize);
      const content = indent + (contentColumn(m) - m[1].length);
      stops.add(indent);
      stops.add(content);
      maxDetected = Math.max(maxDetected, content);
    }
    for (const c of wordStartColumns(text, tabSize)) {
      stops.add(c);
      maxDetected = Math.max(maxDetected, c);
    }
  }
  const bound = Math.max(maxDetected, currentCol) + tabSize;
  for (let c = tabSize; c <= bound; c += tabSize) stops.add(c);
  return [...stops].sort((a, b) => a - b);
}

// Render `col` columns of indentation per the editor's insertSpaces/tabSize.
function makeIndent(col, tabSize, insertSpaces) {
  if (insertSpaces) return ' '.repeat(col);
  return '\t'.repeat(Math.floor(col / tabSize)) + ' '.repeat(col % tabSize);
}

// Visual indent column of a line's leading whitespace.
function lineIndentColumn(document, line, tabSize) {
  const text = document.lineAt(line).text;
  return indentColumns(text.slice(0, leadingWhitespace(text)), tabSize);
}

// The stop in `stops` a column `cur` snaps to in direction `dir` (+1 next stop
// right, -1 next stop left); `cur` itself when there is none.
function pickStop(stops, cur, dir) {
  if (dir > 0) {
    const t = stops.find((s) => s > cur);
    return t === undefined ? cur : t;
  }
  const lower = stops.filter((s) => s < cur);
  return lower.length ? lower[lower.length - 1] : cur;
}

// The column a line snaps to in direction `dir`, and its current column.
// `exclude` are lines not to read as stops (a moved block's own lines should not
// anchor each other).
function columnStopTarget(document, line, dir, tabSize, radius, exclude) {
  const cur = lineIndentColumn(document, line, tabSize);
  return {
    cur,
    target: pickStop(
      collectColumnStops(document, line, tabSize, radius, cur, exclude),
      cur,
      dir,
    ),
  };
}

// Re-indent one markerless line onto its own next column stop.
function applyColumnStop(
  document,
  b,
  line,
  dir,
  tabSize,
  insertSpaces,
  radius,
) {
  const { cur, target } = columnStopTarget(
    document,
    line,
    dir,
    tabSize,
    radius,
  );
  if (target === cur) return;
  b.replace(
    new vscode.Range(
      line,
      0,
      line,
      leadingWhitespace(document.lineAt(line).text),
    ),
    makeIndent(target, tabSize, insertSpaces),
  );
}

// Re-indent several markerless lines as a block by one common delta, preserving
// their relative indentation. The topmost line is the reference: it snaps to its
// next stop, and that delta applies to all. A left shift (Shift+Tab) is capped
// by the flattest line so nothing slides below column 0 and the shape holds. The
// block's own lines are excluded from each other's stop computation.
//
// Performance: each block line's indentation is read once into `entries`, and
// the stop set is built exactly once (for the reference line) - not implicitly
// per line on every keystroke (docs/DECISIONS.md #27).
function applyColumnStopBlock(
  document,
  b,
  lines,
  dir,
  tabSize,
  insertSpaces,
  radius,
) {
  const entries = [...lines]
    .sort((a, c) => a - c)
    .map((line) => {
      const text = document.lineAt(line).text;
      const wsLen = leadingWhitespace(text);
      return { line, wsLen, col: indentColumns(text.slice(0, wsLen), tabSize) };
    });
  const top = entries[0];
  const stops = collectColumnStops(
    document,
    top.line,
    tabSize,
    radius,
    top.col,
    new Set(entries.map((e) => e.line)),
  );
  let delta = pickStop(stops, top.col, dir) - top.col;
  if (delta < 0) {
    const flattest = Math.min(...entries.map((e) => e.col));
    delta = -Math.min(-delta, flattest);
  }
  if (delta === 0) return;
  for (const e of entries) {
    b.replace(
      new vscode.Range(e.line, 0, e.line, e.wsLen),
      makeIndent(e.col + delta, tabSize, insertSpaces),
    );
  }
}

module.exports = {
  continuationStopRadius,
  indentColumns,
  wordStartColumns,
  collectColumnStops,
  makeIndent,
  lineIndentColumn,
  pickStop,
  columnStopTarget,
  applyColumnStop,
  applyColumnStopBlock,
};
