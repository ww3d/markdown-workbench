// --- Custom (non-CommonMark) list markers in the preview ----------------------
//
// Opt-in via lists.renderExtraMarkers (with lists.extraMarkers non-empty),
// passed through render env from views/config.js. Lines that start with an enabled
// custom marker are plain text to CommonMark, so markdown-it leaves them in a
// paragraph; this core rule turns such paragraphs into real ol/ul lists so they
// get the same outline styling and depth as native lists (the source marker is
// dropped, the visual marker comes from the stylesheet, exactly as for native
// ordered lists). A deliberate, documented deviation from CommonMark for
// working notes (docs/DECISIONS.md): the same document renders as plain text
// anywhere else. Off by default. The marker matcher mirrors editing/list-markers.ts but
// is kept local so render/ stays decoupled from the editor modules.
import type { Env, MarkdownIt, StateCore, Token } from 'markdown-it';

const SYMBOL_MARKERS = ['->', '→', '❯'];

/** One line of a custom-marker paragraph. */
interface ExtraLine {
  indent: number;
  marker: string;
  text: string;
}

/** A custom-marker line with its source line number. */
interface ExtraItem extends ExtraLine {
  line: number;
}

/** The render settings this rule reads from `env.markdownWorkbench`. */
interface ExtraMarkerSettings {
  renderExtraMarkers: boolean;
  extraMarkers: string[] | undefined;
}

// Reads the settings views/config.js passes in the render env; anything else
// there counts as "off".
function extraMarkerSettings(env: Env | undefined): ExtraMarkerSettings {
  const cfg = env?.markdownWorkbench;
  if (typeof cfg !== 'object' || cfg === null)
    return { renderExtraMarkers: false, extraMarkers: undefined };
  const on = 'renderExtraMarkers' in cfg && Boolean(cfg.renderExtraMarkers);
  const list = 'extraMarkers' in cfg ? cfg.extraMarkers : undefined;
  return {
    renderExtraMarkers: on,
    extraMarkers: Array.isArray(list)
      ? list.filter((t): t is string => typeof t === 'string')
      : undefined,
  };
}

function buildExtraMarkerMatcher(
  markers: readonly string[] | undefined,
): RegExp | null {
  if (!markers?.length) return null;
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const symbols: string[] = [],
    lower = new Set<string>(),
    upper = new Set<string>(),
    digit = new Set<string>();
  for (const tok of markers) {
    if (SYMBOL_MARKERS.includes(tok)) symbols.push(tok);
    else if (/^[a-z][).:]$/.test(tok)) lower.add(tok.charAt(1));
    else if (/^[A-Z][).:]$/.test(tok)) upper.add(tok.charAt(1));
    else if (/^1[).:]$/.test(tok)) digit.add(tok.charAt(1));
  }
  const alts = [];
  if (symbols.length) alts.push(symbols.map(esc).join('|'));
  const cls = (set: Set<string>) => `[${[...set].join('')}]`;
  if (lower.size) alts.push(`[a-z]{1,2}${cls(lower)}`);
  if (upper.size) alts.push(`[A-Z]{1,2}${cls(upper)}`);
  if (digit.size) alts.push(`\\d+${cls(digit)}`);
  if (!alts.length) return null;
  return new RegExp(`^(\\s*)(?:${alts.join('|')})(\\s+)(.*)$`);
}

// Ordered (letters/digits count) vs. bullet (symbols repeat) - decides ol/ul.
function isOrderedExtra(marker: string): boolean {
  return /^(?:\d+|[a-zA-Z]{1,2})[).:]$/.test(marker);
}

function parseExtraLine(line: string, matcher: RegExp): ExtraLine | null {
  const m = matcher.exec(line);
  if (!m) return null;
  // Groups 1 and 3 are not optional, and a matched line has a marker after
  // its indent.
  const indent = (m[1] ?? '').length;
  return {
    indent,
    marker: /^\S+/.exec(line.slice(indent))?.[0] ?? '',
    text: m[3] ?? '',
  };
}

// The item at `k` of a run; build() only asks for indexes inside the run.
function itemAt(items: readonly ExtraItem[], k: number): ExtraItem {
  const item = items[k];
  if (!item) throw new RangeError(`no custom-marker item ${k}`);
  return item;
}

// Build ol/ul list tokens for a run of parsed custom-marker lines, nesting by
// indentation. Items deeper than the run's base indent become a child list.
function buildExtraListTokens(
  state: StateCore,
  items: readonly ExtraItem[],
): Token[] {
  function build(lo: number, hi: number): Token[] {
    const out: Token[] = [];
    const first = itemAt(items, lo);
    const base = first.indent;
    const ordered = isOrderedExtra(first.marker);
    const tag = ordered ? 'ol' : 'ul';
    const type = ordered ? 'ordered_list' : 'bullet_list';
    const open = new state.Token(`${type}_open`, tag, 1);
    open.map = [first.line, itemAt(items, hi - 1).line + 1];
    open.block = true;
    out.push(open);
    let k = lo;
    while (k < hi) {
      const it = itemAt(items, k);
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
      while (c < hi && itemAt(items, c).indent > base) c++;
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
 */
function extraMarkerListsPlugin(md: MarkdownIt): void {
  md.core.ruler.before('inline', 'extra-marker-lists', (state) => {
    const cfg = extraMarkerSettings(state.env);
    if (!cfg.renderExtraMarkers) return false;
    const matcher = buildExtraMarkerMatcher(cfg.extraMarkers);
    if (!matcher) return false;

    // Read raw source lines (not inline.content, which has the indentation of
    // continuation lines stripped - nesting needs the real columns).
    const srcLines = state.src.split('\n');
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const para = tokens[i];
      if (para?.type !== 'paragraph_open') continue;
      const inline = tokens[i + 1];
      if (inline?.type !== 'inline' || !para.map) continue;
      const [start, end] = para.map;
      const parsed = srcLines
        .slice(start, end)
        .map((l) => parseExtraLine(l, matcher));
      if (!parsed.length || !parsed.every((p) => p !== null)) continue; // not an all-marker paragraph
      const items = parsed.map((p, k) => ({ ...p, line: start + k }));
      const newTokens = buildExtraListTokens(state, items);
      tokens.splice(i, 3, ...newTokens);
      i += newTokens.length - 1;
    }
    return true;
  });
}

export { extraMarkerListsPlugin };
