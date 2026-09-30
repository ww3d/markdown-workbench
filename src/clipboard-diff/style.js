// Markdown style alignment: derives the house style of the baseline (bullet
// character, emphasis markers, table padding) and aligns a candidate to it
// surgically - only markers at their source positions change, the text is never
// re-serialized (docs/DECISIONS.md #1, #48 F2). Every rewrite is verified: the
// candidate must parse to the same structure as before, markers aside, or the
// rewrite is dropped. Pure, no vscode.

import { parse, verbatimLineMask } from './blocks.js';
import { splitLines } from './lines.js';
import { reflowTable } from '../tables/format.ts';
import { findTable, linesDoc } from '../tables/detect.ts';
import { swapEmphasis } from './emphasis.js';

/**
 * Most lines of one block tried one by one when the block's rewrite as a whole
 * changes the structure; the rest of that block stays as it is.
 */
const MAX_BLOCK_RETRIES = 50;

/**
 * The dominant style of `text`: { bullet, emphasis, strong, table }, each null
 * when the text has no instance of it. bullet is '-', '*' or '+'; emphasis '*'
 * or '_'; strong '**' or '__'; table 'distribute' (padded columns) or
 * 'consolidate' (compact), read with the table logic of the editor commands.
 */
function styleProfile(text) {
  const { tokens } = parse(text);
  const lines = splitLines(text);
  const bullets = new Map();
  const ems = new Map();
  const strongs = new Map();
  const tables = new Map();
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

function count(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

function dominant(map) {
  let best = null;
  let bestCount = 0;
  for (const [k, n] of map) {
    if (n > bestCount) {
      best = k;
      bestCount = n;
    }
  }
  return best;
}

function tableMode(lines) {
  if (lines.length < 2 || !lines.every((l) => /^\s*\|/.test(l))) return null;
  // A table in a list item keeps the item indent; cut apart from its list, 4+ spaces read as indented code,
  // so the shared indent goes first and rows that still hold no table get no mode.
  const cut = Math.min(...lines.map((l) => l.length - l.trimStart().length));
  const actual = lines.map((l) => l.slice(cut).trimEnd());
  if (!findTable(linesDoc(actual), 0)) return null;
  // Order decides a table that fits both, i.e. every cell at least 3 wide.
  for (const mode of ['distribute', 'consolidate']) {
    const want = reflowTable(actual, mode);
    if (want.every((w, i) => w === actual[i])) return mode;
  }
  return null;
}

/**
 * Aligns `text` to `profile`. Returns { text, changed } where `changed` counts
 * the lines that were rewritten; the text is returned unchanged when nothing
 * applies or no rewrite survives verification.
 */
function alignStyle(text, profile) {
  const before = parse(text);
  const lines = splitLines(text);
  const eol = /\r\n/.test(text) ? '\r\n' : '\n';
  const mask = verbatimLineMask(before.tokens, lines.length);
  const proposed = proposeLines(before.tokens, lines, mask, profile);
  if (!proposed.size) return { text, changed: 0 };
  const reference = structure(before.tokens);
  const all = lines.map((l, i) => (proposed.has(i) ? proposed.get(i) : l));
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
function topLevelBlocks(tokens, lineCount) {
  const spans = [];
  for (const t of tokens) {
    if (t.level === 0 && t.nesting >= 0 && t.map)
      spans.push([t.map[0], Math.min(t.map[1], lineCount)]);
  }
  return spans;
}

// Linear in the text: proposals and blocks are both in line order, so one
// cursor walks them together, and each check copies only its window.
function keepSafe(lines, proposed, blocks, eol) {
  const kept = lines.slice();
  const keys = [...proposed.keys()].sort((a, b) => a - b);
  let cursor = 0;
  let changed = 0;
  blocks.forEach(([start, end], b) => {
    while (cursor < keys.length && keys[cursor] < start) cursor++;
    const mine = [];
    while (cursor < keys.length && keys[cursor] < end)
      mine.push(keys[cursor++]);
    if (!mine.length) return;
    const lo = b > 0 ? blocks[b - 1][0] : start;
    const hi = b + 1 < blocks.length ? blocks[b + 1][1] : end;
    const window = () => kept.slice(lo, hi);
    const same = (trial) =>
      structure(parse(trial.join(eol)).tokens) === reference;
    const reference = structure(parse(window().join(eol)).tokens);
    const all = window();
    for (const i of mine) all[i - lo] = proposed.get(i);
    if (same(all)) {
      for (const i of mine) kept[i] = proposed.get(i);
      changed += mine.length;
      return;
    }
    for (const i of mine.slice(0, MAX_BLOCK_RETRIES)) {
      const trial = window();
      trial[i - lo] = proposed.get(i);
      if (same(trial)) {
        kept[i] = proposed.get(i);
        changed++;
      }
    }
  });
  return { lines: kept, changed };
}

// Proposed replacement per line number, before verification. Tables replace
// whole lines through reflowTable; bullets and emphasis swap marker characters.
function proposeLines(tokens, lines, mask, profile) {
  const proposed = new Map();
  if (profile.table) {
    for (const t of tokens) {
      if (t.type !== 'table_open' || !t.map) continue;
      const block = lines.slice(t.map[0], t.map[1]);
      if (!block.every((l) => /^\|/.test(l))) continue; // nested in a list or quote
      reflowTable(
        block.map((l) => l.trimEnd()),
        profile.table,
      ).forEach((l, k) => {
        if (l !== block[k]) proposed.set(t.map[0] + k, l);
      });
    }
  }
  const bulletLines = profile.bullet
    ? bulletItemLines(tokens, profile.bullet)
    : new Set();
  for (let i = 0; i < lines.length; i++) {
    if (mask[i]) continue;
    let line = proposed.has(i) ? proposed.get(i) : lines[i];
    if (bulletLines.has(i)) line = swapBullet(line, profile.bullet);
    line = swapEmphasis(line, profile);
    if (line !== lines[i]) proposed.set(i, line);
  }
  return proposed;
}

// Lines of bullet items whose marker differs from `bullet`; a line carrying two
// items ("- * a") is left alone.
function bulletItemLines(tokens, bullet) {
  const perLine = new Map();
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
  const out = new Set();
  for (const [line, n] of perLine)
    if (n.count === 1 && n.differs) out.add(line);
  return out;
}

function swapBullet(line, bullet) {
  return line.replace(/^([\s>]*)[-*+](?=\s|$)/, `$1${bullet}`);
}

// Structure of a token stream with every marker and position dropped: two texts
// with the same structure render the same.
function structure(tokens) {
  const parts = [];
  for (const t of tokens) {
    parts.push(t.type, t.tag, t.info, attrs(t));
    if (t.type === 'inline') parts.push(`[${structure(t.children || [])}]`);
    else if (t.type === 'front_matter') parts.push(t.meta);
    else parts.push(t.content);
  }
  return parts.join('\u0000');
}

function attrs(t) {
  return (t.attrs || [])
    .filter(([k]) => k !== 'data-line')
    .map(([k, v]) => `${k}=${v}`)
    .join(' ');
}

export { styleProfile, alignStyle, MAX_BLOCK_RETRIES };
// Exported for tests only.
export const _internal = { structure, tableMode };
