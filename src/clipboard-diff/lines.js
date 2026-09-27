// Line-level text helpers for the clipboard diff: end-of-line handling and the
// line-hash index that the section anchor and the placeholder filler share
// (docs/DECISIONS.md #48). Pure, no vscode.

const LINE_BREAK_RE = /\r\n|\r|\n/;

/** Splits text into lines on any line break (CRLF, CR or LF). */
function splitLines(text) {
  return text.split(LINE_BREAK_RE);
}

/** The line break a text uses: CRLF when its first break is one, LF otherwise. */
function detectEol(text) {
  const m = LINE_BREAK_RE.exec(text);
  return m && m[0] === '\r\n' ? '\r\n' : '\n';
}

/** Rewrites every line break of `text` to `eol`. */
function normalizeEol(text, eol) {
  return text.replace(/\r\n|\r|\n/g, eol);
}

/**
 * The comparison key of a line: trimmed at both ends, so re-indented or
 * trailing-space variants of the same line still align. Empty for blank lines,
 * which never anchor anything.
 */
function lineKey(line) {
  return line.trim();
}

/**
 * Index of every non-blank line by its key: key -> ascending line numbers.
 * Built once in O(n); a lookup is O(1) plus the length of its position list.
 */
function buildLineIndex(lines) {
  const index = new Map();
  for (let i = 0; i < lines.length; i++) {
    const key = lineKey(lines[i]);
    if (!key) continue;
    const positions = index.get(key);
    if (positions) positions.push(i);
    else index.set(key, [i]);
  }
  return index;
}

/** Character offset at which each line of `text` starts (line 0 at 0). */
function lineStartOffsets(text) {
  const starts = [0];
  for (const m of text.matchAll(/\r\n|\r|\n/g))
    starts.push(m.index + m[0].length);
  return starts;
}

module.exports = {
  splitLines,
  detectEol,
  normalizeEol,
  lineKey,
  buildLineIndex,
  lineStartOffsets,
};
