// List-item recognition: native CommonMark markers, the opt-in custom
// (non-CommonMark) markers, and the advance/family helpers that drive
// counting and re-lettering for both.
const vscode = require('vscode');

// Matches any list item: "- text", "* text", "3. text", optional "[ ] " checkbox.
const LIST_ITEM_RE = /^(\s*)([-*+]|\d+[.)])(\s+)(\[(?: |x|X)\]\s+)?(.*)$/;

// Matches the content of a compound task item, i.e. a second list marker
// plus box ("- [ ] foo" as the content of "1. - [ ] foo"). Group 1 =
// marker + gap, group 3 = gap after the box (empty at line end), group 4 =
// label. Mirrors the compound branch of CHECKBOX_RE in views.js.
const COMPOUND_TASK_RE = /^((?:[-*+]|\d+[.)])\s+)\[( |x|X)\](\s+|$)(.*)$/;

// Ordered markers are digits + "." / ")" (CommonMark) or, for the opt-in custom
// markers, ":" too. The letter look of native outline levels comes from the
// preview stylesheet, never from the source (docs/DECISIONS.md #24).
function numericMarker(bullet) {
  const m = /^(\d+)([.):])$/.exec(bullet);
  return m ? { n: parseInt(m[1], 10), delim: m[2] } : null;
}

// --- Custom (non-CommonMark) list markers, opt-in via lists.extraMarkers ------
//
// LIST_ITEM_RE (native markers) is never touched. Instead a matcher is built
// from the configured markers and cached, rebuilt when the setting changes.
// Each configured token enables a family: a symbol bullet that repeats
// ("->", "→", "❯"), a letter sequence that counts (a) b) ... z) za); upper-case
// kept separate), or a digit sequence with a delimiter (1: ; 1) is already
// CommonMark). Letter sequences are bounded to two characters to limit false
// positives on ordinary prose. These markers are a deliberate non-CommonMark
// deviation for working notes (docs/DECISIONS.md).
function regexEscape(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const SYMBOL_MARKERS = ['->', '→', '❯'];

function buildCustomMatcher(markers) {
  if (!markers?.length) return null;
  const symbols = [],
    lowerDelims = new Set(),
    upperDelims = new Set(),
    digitDelims = new Set();
  for (const tok of markers) {
    if (SYMBOL_MARKERS.includes(tok)) symbols.push(tok);
    else if (/^[a-z][).:]$/.test(tok)) lowerDelims.add(tok[1]);
    else if (/^[A-Z][).:]$/.test(tok)) upperDelims.add(tok[1]);
    else if (/^1[).:]$/.test(tok)) digitDelims.add(tok[1]);
  }
  const alts = [];
  if (symbols.length) alts.push(symbols.map(regexEscape).join('|'));
  const cls = (set) => `[${[...set].join('')}]`;
  if (lowerDelims.size) alts.push(`[a-z]{1,2}${cls(lowerDelims)}`);
  if (upperDelims.size) alts.push(`[A-Z]{1,2}${cls(upperDelims)}`);
  if (digitDelims.size) alts.push(`\\d+${cls(digitDelims)}`);
  if (!alts.length) return null;
  return new RegExp(`^(\\s*)((?:${alts.join('|')}))(\\s+)(.*)$`);
}

let _matcherCache = { key: null, matcher: null };
function configuredExtraMarkers() {
  return vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get('lists.extraMarkers', []);
}
function extraMarkersEnabled() {
  return (
    vscode.workspace
      .getConfiguration('markdownWorkbench')
      .get('lists.extraMarkersEnabled', false) &&
    configuredExtraMarkers().length > 0
  );
}
function customMatcher() {
  const markers = configuredExtraMarkers();
  const key = markers.join('\x00');
  if (_matcherCache.key !== key)
    _matcherCache = { key, matcher: buildCustomMatcher(markers) };
  return _matcherCache.matcher;
}

// Match a line as a list item, native first then (when enabled) custom markers.
// Returns a LIST_ITEM_RE-shaped array: [full, indent, bullet, gap, checkbox,
// rest]. Custom markers carry no checkbox (group 4 is undefined).
function execListItem(text) {
  const native = LIST_ITEM_RE.exec(text);
  if (native) return native;
  if (!extraMarkersEnabled()) return null;
  const matcher = customMatcher();
  if (matcher) {
    const m = matcher.exec(text);
    if (m) return [m[0], m[1], m[2], m[3], undefined, m[4]];
  }
  return null;
}

function isCustomBullet(bullet) {
  return !numericMarker(bullet) && !/^[-*+]$/.test(bullet);
}

// The next letter sequence: a->b ... y->z, then z->za, za->zb ... (a deliberate
// prepend-z overflow, not base-26 carry), upper-case kept separate.
function nextLetterSeq(seq) {
  const upper = seq === seq.toUpperCase();
  const a = upper ? 'A' : 'a',
    z = upper ? 'Z' : 'z';
  const chars = seq.split('');
  const last = chars.length - 1;
  if (chars[last] !== z) {
    chars[last] = String.fromCharCode(chars[last].charCodeAt(0) + 1);
    return chars.join('');
  }
  chars[last] = a;
  return z + chars.join('');
}

// The next marker in a marker's own sequence: numeric and letter markers count
// up (delimiter preserved), symbol bullets repeat unchanged.
function advanceMarker(bullet) {
  const num = numericMarker(bullet);
  if (num) return String(num.n + 1) + num.delim;
  const letter = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  if (letter) return nextLetterSeq(letter[1]) + letter[2];
  return bullet; // symbols and dashes repeat
}

// The family key of a countable marker - kind (numeric / lower / upper letters)
// plus delimiter; null for symbols and dashes, which never count. A run of
// siblings is renumbered only while the family is unchanged.
function markerFamily(bullet) {
  const num = numericMarker(bullet);
  if (num) return `n${num.delim}`;
  const m = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  if (m) return (m[1] === m[1].toUpperCase() ? 'U' : 'l') + m[2];
  return null;
}
function sameFamily(a, b) {
  const fa = markerFamily(a);
  return fa !== null && fa === markerFamily(b);
}

// The first marker of a marker's family (1 / a / A with the same delimiter);
// the bullet itself for symbols/dashes.
function firstOfFamily(bullet) {
  const num = numericMarker(bullet);
  if (num) return `1${num.delim}`;
  const m = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  if (m) return (m[1] === m[1].toUpperCase() ? 'A' : 'a') + m[2];
  return bullet;
}

module.exports = {
  LIST_ITEM_RE,
  COMPOUND_TASK_RE,
  numericMarker,
  regexEscape,
  SYMBOL_MARKERS,
  buildCustomMatcher,
  configuredExtraMarkers,
  extraMarkersEnabled,
  customMatcher,
  execListItem,
  isCustomBullet,
  nextLetterSeq,
  advanceMarker,
  markerFamily,
  sameFamily,
  firstOfFamily,
};
