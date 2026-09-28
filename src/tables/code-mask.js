// Which lines lie in a fenced code block or the frontmatter, and whether a line
// is an indented code block - places where no table branch may act. Pure.

const { prefixLength, quoteDepth, trailingIndent } = require('./row');

const FENCE_OPEN_RE = /^[ \t]{0,3}(`{3,}|~{3,})(.*)$/;

// Fence / frontmatter state per line, cached per document version so the key
// handlers pay one pass per edit at most, not one per keystroke and line.
const maskCache = new WeakMap();

/**
 * Per line 1 when it lies inside a fenced code block or the YAML frontmatter
 * (fence lines included), else 0.
 * @param {{ lineCount: number, lineAt(n: number): { text: string }, version?: number }} doc
 * @returns {Uint8Array}
 */
function codeMask(doc) {
  const hit = maskCache.get(doc);
  if (hit && doc.version !== undefined && hit.version === doc.version)
    return hit.mask;
  const mask = new Uint8Array(doc.lineCount);
  let l = 0;
  if (doc.lineCount > 0 && doc.lineAt(0).text.trimEnd() === '---') {
    mask[0] = 1;
    for (l = 1; l < doc.lineCount; l++) {
      mask[l] = 1;
      const t = doc.lineAt(l).text.trimEnd();
      if (t === '---' || t === '...') {
        l++;
        break;
      }
    }
  }
  let fence = null;
  for (; l < doc.lineCount; l++) {
    const body = doc.lineAt(l).text.slice(prefixLength(doc.lineAt(l).text));
    const m = FENCE_OPEN_RE.exec(body);
    if (fence) {
      mask[l] = 1;
      if (
        m &&
        m[1][0] === fence[0] &&
        m[1].length >= fence.length &&
        m[2].trim() === ''
      )
        fence = null;
    } else if (m && !(m[1][0] === '`' && m[2].includes('`'))) {
      mask[l] = 1;
      fence = m[1];
    }
  }
  maskCache.set(doc, { version: doc.version, mask });
  return mask;
}

// A header-indented 4+ line outside a list is an indented code block, no table.
function isIndentedCode(doc, line, prefix) {
  if (quoteDepth(prefix) > 0 || trailingIndent(prefix) < 4) return false;
  const indent = trailingIndent(prefix);
  for (let l = line - 1; l >= 0; l--) {
    const t = doc.lineAt(l).text;
    if (t.trim() === '') continue;
    const p = t.slice(0, prefixLength(t));
    if (trailingIndent(p) < indent)
      return !/^(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)/.test(t.slice(p.length));
  }
  return true;
}

module.exports = { codeMask, isIndentedCode };
