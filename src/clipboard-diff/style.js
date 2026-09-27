// Markdown style alignment: derives the house style of the baseline (bullet
// character, emphasis markers, table padding) and aligns a candidate to it
// surgically - only markers at their source positions change, the text is never
// re-serialized (docs/DECISIONS.md #1, #48 F2). Every rewrite is verified: the
// candidate must parse to the same structure as before, markers aside, or the
// rewrite is dropped. Pure, no vscode.

const { parse, verbatimLineMask } = require('./blocks');
const { splitLines } = require('./lines');
const { reflowTable } = require('../markdown/syntax');

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
  const actual = lines.map((l) => l.trimEnd());
  for (const mode of ['distribute', 'consolidate']) {
    const want = reflowTable(actual, mode);
    if (want.every((w, i) => w === actual[i].trim())) return mode;
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

// Rewrites _x_ / __x__ (or *x* / **x**) delimiters to the profile's markers.
// Code spans and inline HTML are masked first, so nothing inside them moves.
function swapEmphasis(line, profile) {
  const masked = maskInline(line);
  let out = line;
  for (const [from, to] of emphasisSwaps(profile)) {
    out = replaceDelimiters(out, masked, from, to);
  }
  return out;
}

function emphasisSwaps(profile) {
  const swaps = [];
  if (profile.strong === '**') swaps.push(['__', '**']);
  if (profile.strong === '__') swaps.push(['**', '__']);
  if (profile.emphasis === '*') swaps.push(['_', '*']);
  if (profile.emphasis === '_') swaps.push(['*', '_']);
  return swaps;
}

// Blanks code spans and inline HTML tags, index-preserving, in one linear
// pass (a regex would backtrack quadratically on runs of "`" or "<").
function maskInline(line) {
  const out = line.split('');
  const runs = []; // [index, length] of backtick runs
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
  const nextOfLength = new Map(); // run length -> indexes into runs, ascending
  runs.forEach(([, len], k) => {
    if (!nextOfLength.has(len)) nextOfLength.set(len, []);
    nextOfLength.get(len).push(k);
  });
  const cursor = new Map();
  let maskedTo = 0;
  for (let k = 0; k < runs.length; k++) {
    const [at, len] = runs[k];
    if (at < maskedTo) continue;
    const list = nextOfLength.get(len);
    let c = cursor.get(len) ?? 0;
    while (c < list.length && list[c] <= k) c++;
    cursor.set(len, c);
    if (c === list.length) continue;
    const [closeAt] = runs[list[c]];
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
function replaceDelimiters(line, masked, from, to) {
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

module.exports = {
  styleProfile,
  alignStyle,
  MAX_BLOCK_RETRIES,
  _internal: { structure, tableMode },
};
