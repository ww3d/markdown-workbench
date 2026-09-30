// Markdown style alignment: derives the house style of the baseline (bullet
// character, emphasis markers, table padding) and aligns a candidate to it
// surgically - only markers at their source positions change, the text is never
// re-serialized (docs/DECISIONS.md #1, #48 F2). Every rewrite is verified: the
// candidate must parse to the same structure as before, markers aside, or the
// rewrite is dropped. Pure, no vscode.

import type { Token } from 'markdown-it';
import { reflowTable } from '../tables/format.ts';
import { findTable, linesDoc } from '../tables/detect.ts';
import { parse, verbatimLineMask } from './blocks.ts';
import { swapEmphasis } from './emphasis.ts';
import type { EmphasisProfile } from './emphasis.ts';
import { splitLines } from './lines.ts';

/**
 * Most lines of one block tried one by one when the block's rewrite as a whole
 * changes the structure; the rest of that block stays as it is.
 */
const MAX_BLOCK_RETRIES = 50;

/** Table layout: padded columns or compact. */
export type TableMode = 'distribute' | 'consolidate';

/**
 * The house style of a text, each part null when the text has no instance of
 * it (or, when aligning to it, when that part is to be left alone).
 */
export interface StyleProfile extends EmphasisProfile {
  /** `-`, `*` or `+`. */
  readonly bullet: string | null;
  readonly table: TableMode | null;
}

/**
 * The dominant style of `text`, read with the table logic of the editor
 * commands.
 */
function styleProfile(text: string): StyleProfile {
  const { tokens } = parse(text);
  const lines = splitLines(text);
  const bullets = new Map<string, number>();
  const ems = new Map<string, number>();
  const strongs = new Map<string, number>();
  const tables = new Map<TableMode, number>();
  let bulletDepth = 0;
  for (const t of tokens) {
    if (t.type === 'bullet_list_open') bulletDepth++;
    else if (t.type === 'bullet_list_close') bulletDepth--;
    else if (
      t.type === 'list_item_open' &&
      bulletDepth > 0 &&
      /^[-*+]$/.test(t.markup)
    )
      count(bullets, t.markup);
    else if (t.type === 'table_open' && t.map) {
      const mode = tableMode(lines.slice(t.map[0], t.map[1]));
      if (mode) count(tables, mode);
    } else if (t.type === 'inline') {
      for (const c of t.children || []) {
        if (c.type === 'em_open') count(ems, c.markup);
        else if (c.type === 'strong_open') count(strongs, c.markup);
      }
    }
  }
  return {
    bullet: dominant(bullets),
    emphasis: dominant(ems),
    strong: dominant(strongs),
    table: dominant(tables),
  };
}

function count<K>(map: Map<K, number>, key: K): void {
  map.set(key, (map.get(key) || 0) + 1);
}

function dominant<K>(map: ReadonlyMap<K, number>): K | null {
  let best: K | null = null;
  let bestCount = 0;
  for (const [k, n] of map) {
    if (n > bestCount) {
      best = k;
      bestCount = n;
    }
  }
  return best;
}

function tableMode(lines: readonly string[]): TableMode | null {
  if (lines.length < 2 || !lines.every((l) => /^\s*\|/.test(l))) return null;
  // A table in a list item keeps the item indent; cut apart from its list, 4+ spaces read as indented code,
  // so the shared indent goes first and rows that still hold no table get no mode.
  const cut = Math.min(...lines.map((l) => l.length - l.trimStart().length));
  const actual = lines.map((l) => l.slice(cut).trimEnd());
  if (!findTable(linesDoc(actual), 0)) return null;
  // Order decides a table that fits both, i.e. every cell at least 3 wide.
  for (const mode of ['distribute', 'consolidate'] as const) {
    const want = reflowTable(actual, mode);
    if (want.every((w, i) => w === actual[i])) return mode;
  }
  return null;
}

/**
 * Aligns `text` to `profile`. `changed` counts the lines that were rewritten;
 * the text is returned unchanged when nothing applies or no rewrite survives
 * verification.
 */
function alignStyle(
  text: string,
  profile: Partial<StyleProfile>,
): { text: string; changed: number } {
  const before = parse(text);
  const lines = splitLines(text);
  const eol = /\r\n/.test(text) ? '\r\n' : '\n';
  const mask = verbatimLineMask(before.tokens, lines.length);
  const proposed = proposeLines(before.tokens, lines, mask, profile);
  if (!proposed.size) return { text, changed: 0 };
  const reference = structure(before.tokens);
  const all = lines.map((l, i) => proposed.get(i) ?? l);
  if (structure(parse(all.join(eol)).tokens) === reference) {
    return { text: all.join(eol), changed: proposed.size };
  }
  // Some rewrite changed the meaning: keep what is safe per block, checked
  // together with its neighbour blocks (a bullet swap can merge two lists).
  const kept = keepSafe(
    lines,
    proposed,
    topLevelBlocks(before.tokens, lines.length),
    eol,
  );
  if (!kept.changed) return { text, changed: 0 };
  const result = kept.lines.join(eol);
  return structure(parse(result).tokens) === reference
    ? { text: result, changed: kept.changed }
    : { text, changed: 0 };
}

// [start, end) line spans of the top-level blocks, in order.
function topLevelBlocks(
  tokens: readonly Token[],
  lineCount: number,
): [number, number][] {
  const spans: [number, number][] = [];
  for (const t of tokens) {
    if (t.level === 0 && t.nesting >= 0 && t.map)
      spans.push([t.map[0], Math.min(t.map[1], lineCount)]);
  }
  return spans;
}

// Linear in the text: proposals and blocks are both in line order, so one
// cursor walks them together, and each check copies only its window.
function keepSafe(
  lines: readonly string[],
  proposed: ReadonlyMap<number, string>,
  blocks: readonly [number, number][],
  eol: string,
): { lines: string[]; changed: number } {
  const kept = lines.slice();
  const entries = [...proposed].sort((a, b) => a[0] - b[0]);
  let cursor = 0;
  let changed = 0;
  blocks.forEach(([start, end], b) => {
    while ((entries[cursor]?.[0] ?? Infinity) < start) cursor++;
    const mine: [number, string][] = [];
    for (let e = entries[cursor]; e && e[0] < end; e = entries[++cursor])
      mine.push(e);
    if (!mine.length) return;
    const lo = blocks[b - 1]?.[0] ?? start;
    const hi = blocks[b + 1]?.[1] ?? end;
    const window = () => kept.slice(lo, hi);
    const same = (trial: readonly string[]) =>
      structure(parse(trial.join(eol)).tokens) === reference;
    const reference = structure(parse(window().join(eol)).tokens);
    const all = window();
    for (const [i, text] of mine) all[i - lo] = text;
    if (same(all)) {
      for (const [i, text] of mine) kept[i] = text;
      changed += mine.length;
      return;
    }
    for (const [i, text] of mine.slice(0, MAX_BLOCK_RETRIES)) {
      const trial = window();
      trial[i - lo] = text;
      if (same(trial)) {
        kept[i] = text;
        changed++;
      }
    }
  });
  return { lines: kept, changed };
}

// Proposed replacement per line number, before verification. Tables replace
// whole lines through reflowTable; bullets and emphasis swap marker characters.
function proposeLines(
  tokens: readonly Token[],
  lines: readonly string[],
  mask: Uint8Array,
  profile: Partial<StyleProfile>,
): Map<number, string> {
  const proposed = new Map<number, string>();
  if (profile.table) {
    for (const t of tokens) {
      if (t.type !== 'table_open' || !t.map) continue;
      const [first, last] = t.map;
      const block = lines.slice(first, last);
      if (!block.every((l) => /^\|/.test(l))) continue; // nested in a list or quote
      reflowTable(
        block.map((l) => l.trimEnd()),
        profile.table,
      ).forEach((l, k) => {
        if (l !== block[k]) proposed.set(first + k, l);
      });
    }
  }
  const { bullet } = profile;
  const bulletLines = bullet
    ? bulletItemLines(tokens, bullet)
    : new Set<number>();
  for (const [i, original] of lines.entries()) {
    if (mask[i]) continue;
    let line = proposed.get(i) ?? original;
    if (bullet && bulletLines.has(i)) line = swapBullet(line, bullet);
    line = swapEmphasis(line, profile);
    if (line !== original) proposed.set(i, line);
  }
  return proposed;
}

// Lines of bullet items whose marker differs from `bullet`; a line carrying two
// items ("- * a") is left alone.
function bulletItemLines(
  tokens: readonly Token[],
  bullet: string,
): Set<number> {
  const perLine = new Map<number, { count: number; differs: boolean }>();
  let depth = 0;
  for (const t of tokens) {
    if (t.type === 'bullet_list_open') depth++;
    else if (t.type === 'bullet_list_close') depth--;
    else if (t.type === 'list_item_open' && t.map) {
      const n = perLine.get(t.map[0]) || { count: 0, differs: false };
      n.count++;
      n.differs =
        n.differs ||
        (depth > 0 && /^[-*+]$/.test(t.markup) && t.markup !== bullet);
      perLine.set(t.map[0], n);
    }
  }
  const out = new Set<number>();
  for (const [line, n] of perLine)
    if (n.count === 1 && n.differs) out.add(line);
  return out;
}

function swapBullet(line: string, bullet: string): string {
  return line.replace(/^([\s>]*)[-*+](?=\s|$)/, `$1${bullet}`);
}

// Structure of a token stream with every marker and position dropped: two texts
// with the same structure render the same.
function structure(tokens: readonly Token[]): string {
  const parts: string[] = [];
  for (const t of tokens) {
    parts.push(t.type, t.tag, t.info, attrs(t));
    if (t.type === 'inline') parts.push(`[${structure(t.children || [])}]`);
    else if (t.type === 'front_matter')
      parts.push(typeof t.meta === 'string' ? t.meta : '');
    else parts.push(t.content);
  }
  return parts.join('\u0000');
}

function attrs(t: Token): string {
  return (t.attrs || [])
    .filter(([k]) => k !== 'data-line')
    .map(([k, v]) => `${k}=${v}`)
    .join(' ');
}

export { styleProfile, alignStyle, MAX_BLOCK_RETRIES };
/** Exported for tests only. */
export const _internal = { structure, tableMode };
