// List-item recognition: native CommonMark markers, the opt-in custom
// (non-CommonMark) markers, and the advance/family helpers that drive
// counting and re-lettering for both.
import * as vscode from 'vscode';

/**
 * A recognised list item, shaped like a `LIST_ITEM_RE` match: full text, indent,
 * marker token, gap after it, optional checkbox (`[ ] `, absent for custom
 * markers) and the rest of the line.
 */
export type ListItemMatch = readonly [
  full: string,
  indent: string,
  bullet: string,
  gap: string,
  checkbox: string | undefined,
  rest: string,
];

/**
 * Matches any native list item: `- text`, `* text`, `3. text`, optional `[ ] `
 * checkbox.
 */
const LIST_ITEM_RE = /^(\s*)([-*+]|\d+[.)])(\s+)(\[(?: |x|X)\]\s+)?(.*)$/;

/**
 * Matches the content of a compound task item, i.e. a second list marker plus
 * box (`- [ ] foo` as the content of `1. - [ ] foo`). Group 1 = marker + gap,
 * group 3 = gap after the box (empty at line end), group 4 = label. Mirrors the
 * compound branch of CHECKBOX_RE in markdown/syntax.ts.
 */
const COMPOUND_TASK_RE = /^((?:[-*+]|\d+[.)])\s+)\[( |x|X)\](\s+|$)(.*)$/;

// Ordered markers are digits + "." / ")" (CommonMark) or, for the opt-in custom
// markers, ":" too. The letter look of native outline levels comes from the
// preview stylesheet, never from the source (docs/DECISIONS.md #24).
/**
 * The number and delimiter of a numeric marker (`3.`, `12)`, `1:`), or null for
 * any other marker.
 */
function numericMarker(bullet: string): { n: number; delim: string } | null {
  const m = /^(\d+)([.):])$/.exec(bullet);
  const digits = m?.[1];
  const delim = m?.[2];
  return digits === undefined || delim === undefined
    ? null
    : { n: parseInt(digits, 10), delim };
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
/** Escape `s` for literal use inside a regular expression. */
function regexEscape(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** The custom bullets that repeat instead of counting. */
const SYMBOL_MARKERS: readonly string[] = ['->', '→', '❯'];

/**
 * The regular expression matching a line that starts with one of the configured
 * custom markers (groups: indent, marker, gap, rest), or null when the tokens
 * enable no family.
 */
function buildCustomMatcher(markers: readonly string[]): RegExp | null {
  if (!markers.length) return null;
  const symbols: string[] = [],
    lowerDelims = new Set<string>(),
    upperDelims = new Set<string>(),
    digitDelims = new Set<string>();
  for (const tok of markers) {
    const delim = tok[1] ?? '';
    if (SYMBOL_MARKERS.includes(tok)) symbols.push(tok);
    else if (/^[a-z][).:]$/.test(tok)) lowerDelims.add(delim);
    else if (/^[A-Z][).:]$/.test(tok)) upperDelims.add(delim);
    else if (/^1[).:]$/.test(tok)) digitDelims.add(delim);
  }
  const alts: string[] = [];
  if (symbols.length) alts.push(symbols.map(regexEscape).join('|'));
  const cls = (set: Set<string>) => `[${[...set].join('')}]`;
  if (lowerDelims.size) alts.push(`[a-z]{1,2}${cls(lowerDelims)}`);
  if (upperDelims.size) alts.push(`[A-Z]{1,2}${cls(upperDelims)}`);
  if (digitDelims.size) alts.push(`\\d+${cls(digitDelims)}`);
  if (!alts.length) return null;
  return new RegExp(`^(\\s*)((?:${alts.join('|')}))(\\s+)(.*)$`);
}

let _matcherCache: { key: string | null; matcher: RegExp | null } = {
  key: null,
  matcher: null,
};

/**
 * The configured `lists.extraMarkers` tokens; anything that is not a string is
 * dropped, the tokens themselves are not validated.
 */
function configuredExtraMarkers(): string[] {
  const value = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get<unknown>('lists.extraMarkers', []);
  return Array.isArray(value)
    ? value.filter((tok): tok is string => typeof tok === 'string')
    : [];
}

/**
 * Whether the opt-in custom markers are on: the setting is enabled and at
 * least one marker is configured.
 */
function extraMarkersEnabled(): boolean {
  return (
    Boolean(
      vscode.workspace
        .getConfiguration('markdownWorkbench')
        .get<unknown>('lists.extraMarkersEnabled', false),
    ) && configuredExtraMarkers().length > 0
  );
}

/**
 * The cached matcher for the currently configured extra markers, rebuilt when
 * the configured tokens change.
 */
function customMatcher(): RegExp | null {
  const markers = configuredExtraMarkers();
  const key = markers.join('\x00');
  if (_matcherCache.key !== key)
    _matcherCache = { key, matcher: buildCustomMatcher(markers) };
  return _matcherCache.matcher;
}

// A capture group that always takes part in the match; the fallback only
// satisfies noUncheckedIndexedAccess.
function group(m: RegExpExecArray, index: number): string {
  return m[index] ?? '';
}

/**
 * Match a line as a list item, native markers first, then (when enabled) the
 * custom ones. Custom markers carry no checkbox.
 * @returns the match, or null for a line that is no list item
 */
function execListItem(text: string): ListItemMatch | null {
  const native = LIST_ITEM_RE.exec(text);
  if (native)
    return [
      native[0],
      group(native, 1),
      group(native, 2),
      group(native, 3),
      native[4],
      group(native, 5),
    ];
  if (!extraMarkersEnabled()) return null;
  const matcher = customMatcher();
  if (matcher) {
    const m = matcher.exec(text);
    if (m)
      return [
        m[0],
        group(m, 1),
        group(m, 2),
        group(m, 3),
        undefined,
        group(m, 4),
      ];
  }
  return null;
}

/**
 * Whether `bullet` is one of the opt-in custom markers rather than a native
 * CommonMark one (numeric or `-`/`*`/`+`).
 */
function isCustomBullet(bullet: string): boolean {
  return !numericMarker(bullet) && !/^[-*+]$/.test(bullet);
}

/**
 * The next letter sequence: a->b ... y->z, then z->za, za->zb ... (a deliberate
 * prepend-z overflow, not base-26 carry), upper-case kept separate.
 */
function nextLetterSeq(seq: string): string {
  const upper = seq === seq.toUpperCase();
  const a = upper ? 'A' : 'a',
    z = upper ? 'Z' : 'z';
  const chars = seq.split('');
  const last = chars.length - 1;
  const lastChar = chars[last] ?? z;
  if (lastChar !== z) {
    chars[last] = String.fromCharCode(lastChar.charCodeAt(0) + 1);
    return chars.join('');
  }
  chars[last] = a;
  return z + chars.join('');
}

/**
 * The next marker in a marker's own sequence: numeric and letter markers count
 * up (delimiter preserved), symbol bullets repeat unchanged.
 */
function advanceMarker(bullet: string): string {
  const num = numericMarker(bullet);
  if (num) return String(num.n + 1) + num.delim;
  const letter = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  const seq = letter?.[1];
  const delim = letter?.[2];
  if (seq !== undefined && delim !== undefined)
    return nextLetterSeq(seq) + delim;
  return bullet; // symbols and dashes repeat
}

/**
 * The family key of a countable marker - kind (numeric / lower / upper letters)
 * plus delimiter; null for symbols and dashes, which never count. A run of
 * siblings is renumbered only while the family is unchanged.
 */
function markerFamily(bullet: string): string | null {
  const num = numericMarker(bullet);
  if (num) return `n${num.delim}`;
  const m = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  const seq = m?.[1];
  const delim = m?.[2];
  if (seq !== undefined && delim !== undefined)
    return (seq === seq.toUpperCase() ? 'U' : 'l') + delim;
  return null;
}

/**
 * Whether two markers count as the same family (same kind and delimiter);
 * always false when either is not a countable marker.
 */
function sameFamily(a: string, b: string): boolean {
  const fa = markerFamily(a);
  return fa !== null && fa === markerFamily(b);
}

/**
 * The first marker of a marker's family (1 / a / A with the same delimiter);
 * the bullet itself for symbols/dashes.
 */
function firstOfFamily(bullet: string): string {
  const num = numericMarker(bullet);
  if (num) return `1${num.delim}`;
  const m = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  const seq = m?.[1];
  const delim = m?.[2];
  if (seq !== undefined && delim !== undefined)
    return (seq === seq.toUpperCase() ? 'A' : 'a') + delim;
  return bullet;
}

export {
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
