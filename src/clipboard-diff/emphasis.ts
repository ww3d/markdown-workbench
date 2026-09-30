// Emphasis marker alignment for the clipboard diff style pass (docs/DECISIONS.md
// #1, #48 F2): swaps _x_ / __x__ (or *x* / **x**) delimiters to the baseline's
// markers, with code spans and inline HTML masked first so nothing inside them
// moves. Pure, no vscode.

/** The emphasis part of a style profile: the markers to align to, null for "leave as is". */
export interface EmphasisProfile {
  /** `*` or `_`. */
  readonly emphasis: string | null;
  /** `**` or `__`. */
  readonly strong: string | null;
}

/**
 * Rewrites _x_ / __x__ (or *x* / **x**) delimiters to the profile's markers.
 * Code spans and inline HTML are masked first, so nothing inside them moves.
 */
function swapEmphasis(line: string, profile: Partial<EmphasisProfile>): string {
  const masked = maskInline(line);
  let out = line;
  for (const [from, to] of emphasisSwaps(profile)) {
    out = replaceDelimiters(out, masked, from, to);
  }
  return out;
}

function emphasisSwaps(profile: Partial<EmphasisProfile>): [string, string][] {
  const swaps: [string, string][] = [];
  if (profile.strong === '**') swaps.push(['__', '**']);
  if (profile.strong === '__') swaps.push(['**', '__']);
  if (profile.emphasis === '*') swaps.push(['_', '*']);
  if (profile.emphasis === '_') swaps.push(['*', '_']);
  return swaps;
}

// Blanks code spans and inline HTML tags, index-preserving, in one linear
// pass (a regex would backtrack quadratically on runs of "`" or "<").
function maskInline(line: string): string {
  const out = line.split('');
  const runs: [number, number][] = []; // [index, length] of backtick runs
  for (let i = 0; i < line.length; ) {
    if (line[i] !== '`') {
      i++;
      continue;
    }
    let j = i;
    while (line[j] === '`') j++;
    runs.push([i, j - i]);
    i = j;
  }
  const nextOfLength = new Map<number, number[]>(); // run length -> indexes into runs, ascending
  for (const [k, [, len]] of runs.entries()) {
    const list = nextOfLength.get(len);
    if (list) list.push(k);
    else nextOfLength.set(len, [k]);
  }
  const cursor = new Map<number, number>();
  let maskedTo = 0;
  for (const [k, [at, len]] of runs.entries()) {
    if (at < maskedTo) continue;
    const list = nextOfLength.get(len) ?? [];
    let c = cursor.get(len) ?? 0;
    while (c < list.length && (list[c] ?? Infinity) <= k) c++;
    cursor.set(len, c);
    const closeIndex = list[c];
    const closeRun = closeIndex === undefined ? undefined : runs[closeIndex];
    if (!closeRun) continue;
    const closeAt = closeRun[0];
    for (let x = at; x < closeAt + len; x++) out[x] = ' ';
    maskedTo = closeAt + len;
  }
  const masked = out.join('');
  let result = '';
  let last = 0;
  for (let i = masked.indexOf('<'); i !== -1; i = masked.indexOf('<', last)) {
    const close = masked.indexOf('>', i);
    if (close === -1) break;
    result += masked.slice(last, i) + ' '.repeat(close - i + 1);
    last = close + 1;
  }
  return result + masked.slice(last);
}

// Replaces delimiter runs of exactly `from` (a run of one repeated character)
// that open or close emphasis per the flanking rules, at positions where the
// masked line still shows them.
function replaceDelimiters(
  line: string,
  masked: string,
  from: string,
  to: string,
): string {
  const ch = from[0] === '*' ? '\\*' : '_';
  const re = new RegExp(`(?<![${ch}\\\\])${ch}{${from.length}}(?!${ch})`, 'g');
  let out = '';
  let last = 0;
  for (const m of masked.matchAll(re)) {
    const i = m.index;
    const prev = line[i - 1] || ' ';
    const next = line[i + from.length] || ' ';
    const opens =
      /\S/.test(next) && !(from[0] === '_' && /[\p{L}\p{N}]/u.test(prev));
    const closes =
      /\S/.test(prev) && !(from[0] === '_' && /[\p{L}\p{N}]/u.test(next));
    if (!opens && !closes) continue;
    out += line.slice(last, i) + to;
    last = i + from.length;
  }
  return out + line.slice(last);
}

export { swapEmphasis };
/** Exported for tests only. */
export const _internal = { maskInline, replaceDelimiters, emphasisSwaps };
