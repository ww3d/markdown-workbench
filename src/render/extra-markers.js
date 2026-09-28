// --- Custom (non-CommonMark) list markers in the preview ----------------------
//
// Opt-in via lists.renderExtraMarkers (with lists.extraMarkers non-empty),
// passed through render env from views.js. Lines that start with an enabled
// custom marker are plain text to CommonMark, so markdown-it leaves them in a
// paragraph; this core rule turns such paragraphs into real ol/ul lists so they
// get the same outline styling and depth as native lists (the source marker is
// dropped, the visual marker comes from the stylesheet, exactly as for native
// ordered lists). A deliberate, documented deviation from CommonMark for
// working notes (docs/DECISIONS.md): the same document renders as plain text
// anywhere else. Off by default. The marker matcher mirrors editing.js but is
// kept local so render.js stays decoupled from the editor module.
const SYMBOL_MARKERS = ['->', '→', '❯'];

function buildExtraMarkerMatcher(markers) {
  if (!markers?.length) return null;
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const symbols = [],
    lower = new Set(),
    upper = new Set(),
    digit = new Set();
  for (const tok of markers) {
    if (SYMBOL_MARKERS.includes(tok)) symbols.push(tok);
    else if (/^[a-z][).:]$/.test(tok)) lower.add(tok[1]);
    else if (/^[A-Z][).:]$/.test(tok)) upper.add(tok[1]);
    else if (/^1[).:]$/.test(tok)) digit.add(tok[1]);
  }
  const alts = [];
  if (symbols.length) alts.push(symbols.map(esc).join('|'));
  const cls = (set) => `[${[...set].join('')}]`;
  if (lower.size) alts.push(`[a-z]{1,2}${cls(lower)}`);
  if (upper.size) alts.push(`[A-Z]{1,2}${cls(upper)}`);
  if (digit.size) alts.push(`\\d+${cls(digit)}`);
  if (!alts.length) return null;
  return new RegExp(`^(\\s*)(?:${alts.join('|')})(\\s+)(.*)$`);
}

// Ordered (letters/digits count) vs. bullet (symbols repeat) - decides ol/ul.
function isOrderedExtra(marker) {
  return /^(?:\d+|[a-zA-Z]{1,2})[).:]$/.test(marker);
}

function parseExtraLine(line, matcher) {
  const m = matcher.exec(line);
  if (!m) return null;
  return {
    indent: m[1].length,
    marker: line.slice(m[1].length).match(/^\S+/)[0],
    text: m[3],
  };
}

// Build ol/ul list tokens for a run of parsed custom-marker lines, nesting by
// indentation. Items deeper than the run's base indent become a child list.
function buildExtraListTokens(state, items) {
  function build(lo, hi) {
    const out = [];
    const base = items[lo].indent;
    const ordered = isOrderedExtra(items[lo].marker);
    const tag = ordered ? 'ol' : 'ul';
    const type = ordered ? 'ordered_list' : 'bullet_list';
    const open = new state.Token(`${type}_open`, tag, 1);
    open.map = [items[lo].line, items[hi - 1].line + 1];
    open.block = true;
    out.push(open);
    let k = lo;
    while (k < hi) {
      const it = items[k];
      const li = new state.Token('list_item_open', 'li', 1);
      li.map = [it.line, it.line + 1];
      li.block = true;
      out.push(li);
      const inline = new state.Token('inline', '', 0);
      inline.content = it.text;
      inline.map = [it.line, it.line + 1];
      inline.children = [];
      out.push(inline);
      let c = k + 1;
      while (c < hi && items[c].indent > base) c++;
      if (c > k + 1) out.push(...build(k + 1, c));
      out.push(new state.Token('list_item_close', 'li', -1));
      k = c;
    }
    out.push(new state.Token(`${type}_close`, tag, -1));
    return out;
  }
  return build(0, items.length);
}

/**
 * markdown-it core rule: turn an all-custom-marker paragraph into a real
 * ol/ul list, when `renderExtraMarkers` is on and markers are configured.
 * @param {import('markdown-it')} md
 */
function extraMarkerListsPlugin(md) {
  md.core.ruler.before('inline', 'extra-marker-lists', (state) => {
    const cfg = state.env?.markdownWorkbench || {};
    if (!cfg.renderExtraMarkers) return false;
    const matcher = buildExtraMarkerMatcher(cfg.extraMarkers);
    if (!matcher) return false;

    // Read raw source lines (not inline.content, which has the indentation of
    // continuation lines stripped - nesting needs the real columns).
    const srcLines = state.src.split('\n');
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'paragraph_open') continue;
      const inline = tokens[i + 1];
      if (inline?.type !== 'inline' || !tokens[i].map) continue;
      const [start, end] = tokens[i].map;
      const parsed = srcLines
        .slice(start, end)
        .map((l) => parseExtraLine(l, matcher));
      if (!parsed.length || !parsed.every(Boolean)) continue; // not an all-marker paragraph
      parsed.forEach((p, k) => {
        p.line = start + k;
      });
      const newTokens = buildExtraListTokens(state, parsed);
      tokens.splice(i, 3, ...newTokens);
      i += newTokens.length - 1;
    }
    return true;
  });
}

module.exports = { extraMarkerListsPlugin };
