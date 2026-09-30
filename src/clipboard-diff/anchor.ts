// Section anchor: finds the part of the baseline a clipboard text most likely
// replaces, so a snippet can be compared without selecting it first
// (docs/DECISIONS.md #48, F1+a). Text matching only, no diff algorithm: a
// heading-led candidate takes its same-named section; otherwise a line-hash
// index locates the candidate's first and last line and scores the overlap at
// no more than MAX_ANCHOR_CANDIDATES places - O(n + K*m). Pure, no vscode.

import { parseBlocks, headings } from './blocks.ts';
import { splitLines, lineKey, buildLineIndex } from './lines.ts';
import { placeholderRule } from './unwrap.ts';

/** K: most places whose overlap is scored; more hits count as ambiguous. */
const MAX_ANCHOR_CANDIDATES = 8;
/** Share of candidate lines a place must contain to count as a sure hit. */
const MIN_ANCHOR_CONFIDENCE = 0.6;
/** A best hit must lead the runner-up by this much score to be unambiguous. */
const MIN_ANCHOR_LEAD = 0.15;
/** A hit covering at least this share of the baseline is the whole file. */
const WHOLE_FILE_SHARE = 0.9;
/** A place ends within END_SEARCH_FACTOR * m + END_SEARCH_SLACK lines. */
const END_SEARCH_FACTOR = 4;
const END_SEARCH_SLACK = 32;

/** A place in the baseline that the candidate probably replaces. */
export interface AnchorMatch {
  /** First line, 0-based. */
  readonly start: number;
  /** Line after the last one (exclusive). */
  readonly end: number;
  /** Share of the candidate's lines found there, 0-1. */
  readonly score: number;
  /** How the place was found: by a same-named section or by line overlap. */
  readonly kind: 'heading' | 'lines';
}

/** The outcome of `findAnchor`. */
export interface Anchor {
  readonly matches: AnchorMatch[];
  readonly confident: boolean;
}

/**
 * Finds where in the baseline the candidate belongs. Lines are 0-based, end
 * exclusive. No matches means the whole file is the baseline. `confident` is
 * true for exactly one sure match.
 */
function findAnchor(baselineText: string, candidateText: string): Anchor {
  const baseLines = splitLines(baselineText);
  // Placeholder lines ("… rest unchanged …") stand for baseline text and never
  // occur in it, so they neither anchor nor count against the overlap.
  const candLines = trimBlankEdges(
    splitLines(candidateText).filter((l) => !placeholderRule(l)),
  );
  if (!candLines.length) return none();
  const byHeading = headingMatches(baselineText, baseLines, candidateText);
  if (byHeading) return byHeading;
  return lineMatches(baseLines, candLines);
}

function none(): Anchor {
  return { matches: [], confident: false };
}

function trimBlankEdges(lines: string[]): string[] {
  let a = 0;
  let b = lines.length;
  while (a < b && !lineKey(lines[a] ?? '')) a++;
  while (b > a && !lineKey(lines[b - 1] ?? '')) b--;
  return lines.slice(a, b);
}

// A candidate that starts with a heading takes the same-named section of the
// baseline, up to the next heading of the same or a higher level.
function headingMatches(
  baselineText: string,
  baseLines: readonly string[],
  candidateText: string,
): Anchor | null {
  const candHeadings = headings(parseBlocks(candidateText));
  const lead = candHeadings[0];
  if (!lead || !isFirstContentLine(candidateText, lead.line)) return null;
  // Further sections of the same level in the candidate, in order: a candidate
  // spanning "## Install" and "## Usage" replaces both sections.
  const followers = candHeadings
    .slice(1)
    .filter((h) => h.level === lead.level)
    .map((h) => h.title);
  const sections = headings(parseBlocks(baselineText));
  const matches: AnchorMatch[] = [];
  let partial = false;
  sections.forEach((h, i) => {
    if (h.level !== lead.level || h.title !== lead.title) return;
    let last = i;
    let covered = 0;
    for (
      let k = i + 1;
      k < sections.length && covered < followers.length;
      k++
    ) {
      const n = sections[k];
      if (!n || n.level < lead.level) break;
      if (n.level > lead.level) continue;
      if (n.title !== followers[covered]) break;
      last = k;
      covered++;
    }
    if (covered < followers.length) partial = true;
    const next = sections.slice(last + 1).find((n) => n.level <= lead.level);
    const end = next ? next.line : baseLines.length;
    matches.push({
      start: h.line,
      end: trimTrailingBlank(baseLines, h.line, end),
      score: 1,
      kind: 'heading',
    });
  });
  if (!matches.length) return null;
  return { matches, confident: matches.length === 1 && !partial };
}

function isFirstContentLine(text: string, line: number): boolean {
  const lines = splitLines(text);
  for (let l = 0; l < line; l++) if (lineKey(lines[l] ?? '')) return false;
  return true;
}

// Keeps the blank lines that separate a section from the next heading outside
// the anchored span, so replacing the section keeps the spacing.
function trimTrailingBlank(
  lines: readonly string[],
  start: number,
  end: number,
): number {
  let e = end;
  while (e > start + 1 && !lineKey(lines[e - 1] ?? '')) e--;
  return e;
}

function lineMatches(
  baseLines: readonly string[],
  candLines: readonly string[],
): Anchor {
  const index = buildLineIndex(baseLines);
  const m = candLines.length;
  const firstPositions = index.get(lineKey(candLines[0] ?? '')) || [];
  const lastPositions = index.get(lineKey(candLines[m - 1] ?? '')) || [];
  const places = new Map<number, number>(); // start line -> end line (exclusive)
  for (const s of firstPositions.slice(0, MAX_ANCHOR_CANDIDATES)) {
    places.set(s, endFor(s, lastPositions, m, baseLines.length));
  }
  for (const e of lastPositions.slice(0, MAX_ANCHOR_CANDIDATES)) {
    const s = Math.max(0, e - (m - 1));
    if (!places.has(s) && places.size < 2 * MAX_ANCHOR_CANDIDATES)
      places.set(s, e + 1);
  }
  const ambiguous =
    firstPositions.length > MAX_ANCHOR_CANDIDATES ||
    lastPositions.length > MAX_ANCHOR_CANDIDATES;
  const candKeys = candLines.map(lineKey).filter(Boolean);
  const matches = [...places]
    .map(
      ([start, end]): AnchorMatch => ({
        start,
        end,
        score: overlap(baseLines, start, end, candKeys),
        kind: 'lines',
      }),
    )
    .filter((p) => p.score > 0)
    .sort((a, b) => b.score - a.score || a.start - b.start);
  const best = matches[0];
  if (!best) return none();
  if (
    best.start === 0 &&
    best.end - best.start >= WHOLE_FILE_SHARE * baseLines.length
  )
    return none();
  const runnerUp = matches[1];
  const confident =
    !ambiguous &&
    best.score >= MIN_ANCHOR_CONFIDENCE &&
    (!runnerUp || leadOf(best, runnerUp) >= MIN_ANCHOR_LEAD);
  return { matches: matches.slice(0, MAX_ANCHOR_CANDIDATES), confident };
}

// Score lead of `a` over `b`, rounded so a lead of exactly MIN_ANCHOR_LEAD (e.g. 3
// of 20 lines) counts as reached instead of missing it by a float rounding error.
function leadOf(a: AnchorMatch, b: AnchorMatch): number {
  return Math.round((a.score - b.score) * 1e9) / 1e9;
}

// The end of the place that starts at `s`: the occurrence of the candidate's
// last line closest to where it would sit with an unchanged length, searched
// within END_SEARCH_FACTOR * m lines so one scored place stays O(m).
function endFor(
  s: number,
  lastPositions: readonly number[],
  m: number,
  lineCount: number,
): number {
  const expected = s + m - 1;
  const limit = s + END_SEARCH_FACTOR * m + END_SEARCH_SLACK;
  let best = -1;
  for (
    let k = firstIndexAtOrAfter(lastPositions, s);
    k < lastPositions.length;
    k++
  ) {
    const p = lastPositions[k];
    if (p === undefined || p > limit) break;
    if (best === -1 || Math.abs(p - expected) < Math.abs(best - expected))
      best = p;
  }
  return best === -1 ? Math.min(lineCount, s + m) : best + 1;
}

// Index of the first value >= `min` in the ascending `sorted`, by binary search.
function firstIndexAtOrAfter(sorted: readonly number[], min: number): number {
  let lo = 0;
  let hi = sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if ((sorted[mid] ?? Infinity) < min) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

// Share of the candidate's non-blank lines that occur in baseline[start, end).
function overlap(
  baseLines: readonly string[],
  start: number,
  end: number,
  candKeys: readonly string[],
): number {
  if (!candKeys.length) return 0;
  const present = new Set<string>();
  for (let l = start; l < end; l++) present.add(lineKey(baseLines[l] ?? ''));
  let hits = 0;
  for (const k of candKeys) if (present.has(k)) hits++;
  return hits / candKeys.length;
}

export {
  findAnchor,
  MAX_ANCHOR_CANDIDATES,
  MIN_ANCHOR_CONFIDENCE,
  MIN_ANCHOR_LEAD,
  WHOLE_FILE_SHARE,
};
