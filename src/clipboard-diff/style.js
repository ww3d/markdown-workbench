// Markdown style alignment: derives the house style of the baseline (bullet
// character, emphasis markers, table padding) and aligns a candidate to it
// surgically - only markers at their source positions change, the text is never
// re-serialized (docs/DECISIONS.md #1, #48 F2). Every rewrite is verified: the
// candidate must parse to the same structure as before, markers aside, or the
// rewrite is dropped. Pure, no vscode.

const { parse, verbatimLineMask } = require('./blocks');
const { splitLines } = require('./lines');
const { reflowTable } = require('../markdown/syntax');

/** Most lines tried one by one when the rewrite of the whole text fails. */
const MAX_LINEWISE_RETRIES = 200;

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
  // Some rewrite changed the meaning: keep only the lines that are safe alone.
  if (proposed.size > MAX_LINEWISE_RETRIES) return { text, changed: 0 };
  const kept = lines.slice();
  let changed = 0;
  for (const [i, line] of proposed) {
    const trial = kept.slice();
    trial[i] = line;
    if (structure(parse(trial.join(eol)).tokens) === reference) {
      kept[i] = line;
      changed++;
    }
  }
  return { text: changed ? kept.join(eol) : text, changed };
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

function maskInline(line) {
  return line
    .replace(/(`+)[\s\S]*?\1/g, (m) => ' '.repeat(m.length))
    .replace(/<[^>\n]*>/g, (m) => ' '.repeat(m.length));
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
  MAX_LINEWISE_RETRIES,
  _internal: { structure, tableMode },
};
