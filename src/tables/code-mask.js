// Which lines lie in a fenced code block or the frontmatter, and whether a line
// is an indented code block - places where no table branch may act. Pure.

const {
  prefixLength,
  quoteDepth,
  trailingIndent,
  listMarkerWidth,
  prefixAt,
  parseSeparator,
  splitRow,
} = require('./row');

// Blocks that interrupt a paragraph and so end a list item they are left of:
// heading, thematic break, fence, HTML block.
const BLOCK_START_RE =
  /^(?:#{1,6}(?:[ \t]|$)|([-*_])(?:[ \t]*\1){2,}[ \t]*$|`{3,}|~{3,}|<[a-zA-Z/!?])/;
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
  // The open fence (its marker and the quote depth it was opened at); a line
  // with fewer `>` ends the quote and with it the fence.
  let fence = null;
  for (; l < doc.lineCount; l++) {
    const text = doc.lineAt(l).text;
    const p = prefixLength(text);
    const prefix = text.slice(0, p);
    const depth = quoteDepth(prefix);
    if (fence && depth < fence.depth) fence = null;
    // A fence in a list item ends with the item: a line left of its content.
    const blank = p >= text.trimEnd().length;
    if (
      fence &&
      !blank &&
      depth === fence.depth &&
      trailingIndent(prefix) < fence.c
    )
      fence = null;
    const m = FENCE_OPEN_RE.exec(text.slice(p));
    if (fence) {
      mask[l] = 1;
      const marker = fence.marker;
      if (
        m &&
        m[1][0] === marker[0] &&
        m[1].length >= marker.length &&
        m[2].trim() === '' &&
        !isIndentedCode(doc, l, prefix)
      )
        fence = null;
    } else if (
      m &&
      !(m[1][0] === '`' && m[2].includes('`')) &&
      !isIndentedCode(doc, l, prefix)
    ) {
      mask[l] = 1;
      const ctx = listContext(doc, l, prefix);
      fence = { marker: m[1], depth, c: ctx && !ctx.lazy ? ctx.c : 0 };
    }
  }
  maskCache.set(doc, { version: doc.version, mask });
  return mask;
}

/** Whether a line indented 4+ columns outside a list is an indented code block. */
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

/**
 * The list item a line at `indent` (after `prefix`) belongs to, found upward
 * like markdown-it: `c` is the item's content column; `lazy` when the line
 * continues the item's paragraph from left of `c`. Within one paragraph the
 * indentation does not matter; after a blank line a line left of `c`, or a
 * block start (heading, rule, fence, HTML) left of it, ends the item. Null
 * outside any list item.
 * @param {{ lineAt(n: number): { text: string } }} doc
 * @param {number} line
 * @param {string} prefix
 * @returns {{ c: number, lazy: boolean } | null}
 */
function listContext(doc, line, prefix) {
  const depth = quoteDepth(prefix);
  const indent = trailingIndent(prefix);
  let need = Infinity; // lowest indent of a line right after a blank line
  let below = indent; // indent of the non-blank line visited last
  let closed = Infinity; // lowest indent of a block start on the way
  let blank = false; // a blank line between the item and `line`
  for (let l = line - 1; l >= 0; l--) {
    const t = doc.lineAt(l).text;
    const p = prefixLength(t);
    const d = quoteDepth(t.slice(0, p));
    if (d > depth) {
      // A nested quote is a block start at the indent of its first `>`.
      const own = trailingIndent(t.slice(0, prefixAt(t, depth)));
      closed = Math.min(closed, own);
      below = own;
      continue;
    }
    if (d < depth) return null;
    if (p >= t.trimEnd().length) {
      need = Math.min(need, below);
      blank = true;
      continue;
    }
    const own = trailingIndent(t.slice(0, p));
    const w = listMarkerWidth(t.slice(p));
    if (w) {
      const c = own + w;
      const state =
        need >= c && closed >= c ? itemState(doc, l, line, c, depth) : ENDED;
      if (state !== ENDED) {
        if (indent >= c) return { c, lazy: false };
        if (!blank && state === OPEN) return { c, lazy: true };
      }
      if (own === 0) return null;
    } else if (BLOCK_START_RE.test(t.slice(p))) closed = Math.min(closed, own);
    below = own;
  }
  return null;
}

// How the item at `item` (content column `c`) fares between it and `line`:
// ENDED when a line left of `c` is no paragraph continuation (the paragraph was
// broken by a block, or the line starts a table whose delimiter row passes in
// the item); BROKEN when a block or table in the item ended its paragraph, so
// `line` cannot continue it lazily; else OPEN. As in markdown-it.
const OPEN = 0;
const BROKEN = 1;
const ENDED = 2;
function itemState(doc, item, line, c, depth) {
  let state = OPEN;
  for (let m = item; m < line; m++) {
    const t = doc.lineAt(m).text;
    let p = prefixAt(t, depth);
    // The item's own line counts from its content column.
    if (m === item) p += listMarkerWidth(t.slice(p));
    if (p < 0 || p >= t.trimEnd().length) continue;
    const own = m === item ? c : trailingIndent(t.slice(0, p));
    if (own < c && state === BROKEN) return ENDED;
    if (own >= c && BLOCK_START_RE.test(t.slice(p))) state = BROKEN;
    if (!t.includes('|') || own - c >= 4) continue;
    const s = doc.lineAt(m + 1).text;
    const sp = prefixAt(s, depth);
    if (sp < 0) continue;
    const si = trailingIndent(s.slice(0, sp));
    const aligns = si >= c && si - c < 4 && parseSeparator(s, sp);
    if (!aligns || splitRow(t, p).cells.length !== aligns.length) continue;
    if (own < c) return ENDED;
    if (m + 1 < line) state = BROKEN;
  }
  return state;
}

module.exports = { codeMask, isIndentedCode, listContext };
