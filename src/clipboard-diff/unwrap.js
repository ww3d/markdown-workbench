// Unwrapping an AI answer and guarding against its omission placeholders
// (docs/DECISIONS.md #48, F3). The unwrap strips an outer fence and chat lines
// at the edges; the placeholder guard marks lines like "… rest unchanged …" and,
// on apply, fills in the baseline text they hide instead of deleting it. Every
// rule is a named entry of a fixed list. Pure, no vscode.

import { splitLines, lineKey, buildLineIndex } from './lines.js';

/** Leading chat lines ("Sure, here is the updated section:"); edge only. */
const LEADING_CHAT_PATTERNS = [
  {
    name: 'assent',
    re: /^(?:sure|certainly|of course|absolutely|okay|ok|got it|great)\b.*$/i,
  },
  {
    name: 'here-is',
    re: /^(?:here(?:'s| is| are)|below is|this is the)\b.*[:.]$/i,
  },
  {
    name: 'did-update',
    re: /^i(?:'ve| have)? (?:updated|rewritten|revised|changed|fixed|made)\b.*[:.]$/i,
  },
  {
    name: 'assent-de',
    re: /^(?:gerne|klar|natürlich|selbstverständlich|alles klar)\b.*$/i,
  },
  {
    name: 'here-is-de',
    re: /^(?:hier (?:ist|sind|kommt|die|der|das)|unten (?:steht|findest))\b.*[:.]$/i,
  },
];

/** Trailing chat lines ("Let me know if ..."); edge only. */
const TRAILING_CHAT_PATTERNS = [
  {
    name: 'offer',
    re: /^(?:let me know|hope this helps|i hope|feel free|if you (?:want|need|'d like)|would you like|want me to)\b.*$/i,
  },
  {
    name: 'offer-de',
    re: /^(?:lass mich wissen|sag bescheid|ich hoffe|möchtest du|soll ich|wenn du (?:willst|möchtest))\b.*$/i,
  },
];

/**
 * Placeholder lines an AI answer uses for text it left out. A pattern matches a
 * whole line only, so an ellipsis inside running text never counts.
 */
const PLACEHOLDER_PATTERNS = [
  {
    name: 'ellipsis-note',
    re: /^\s*(?:[[(]\s*)?(?:\.{3}|…)\s*(?:the )?(?:rest|remaining|unchanged|existing|same|omitted|no changes|rest unverändert|unverändert|wie bisher|gekürzt)\b[^\n]*$/i,
  },
  { name: 'bracketed-ellipsis', re: /^\s*[[(]\s*(?:\.{3}|…)\s*[\])]\s*$/ },
  {
    name: 'html-comment',
    re: /^\s*<!--\s*(?:(?:\.{3}|…)\s*)?(?:unchanged|rest unchanged|existing|rest of (?:the )?(?:file|document|section)|same as before|unverändert|rest unverändert)\b[^>]*-->\s*$/i,
  },
  {
    name: 'code-comment',
    re: /^\s*(?:\/\/|#|--|\/\*|;)\s*(?:\.{3}|…)\s*(?:existing|rest|unchanged|same|remaining|other)\b[^\n]*$/i,
  },
  { name: 'bare-ellipsis', re: /^\s*(?:\.{3}|…)\s*$/ },
];

const FENCE_OPEN_RE = /^ {0,3}(`{3,}|~{3,})(.*)$/;

/**
 * Strips chat lines at the edges and an outer fence around the whole answer.
 * Returns { text, removed } with the names of the rules that fired; `text` is
 * the input unchanged when none did.
 */
function unwrapAnswer(text) {
  let lines = splitLines(text);
  const removed = [];
  lines = stripEdges(lines, removed);
  const inner = outerFenceContent(lines);
  if (inner) {
    removed.push('outer-fence');
    lines = inner;
  }
  if (!removed.length) return { text, removed };
  return { text: lines.join('\n'), removed };
}

function stripEdges(lines, removed) {
  let a = 0;
  let b = lines.length;
  while (a < b && !lineKey(lines[a])) a++;
  while (b > a && !lineKey(lines[b - 1])) b--;
  // A chat line counts only where a blank line or a fence separates it from
  // more content, so a first sentence that merely starts with "Sure" stays,
  // and the last line of content is never taken for chat.
  while (a < b) {
    const rule = matchRule(LEADING_CHAT_PATTERNS, lines[a]);
    if (!rule || a + 1 >= b || !isSeparator(lines[a + 1])) break;
    removed.push(`leading-chat:${rule}`);
    a++;
    while (a < b && !lineKey(lines[a])) a++;
  }
  while (b > a) {
    const rule = matchRule(TRAILING_CHAT_PATTERNS, lines[b - 1]);
    if (!rule || b - 2 < a || !isSeparator(lines[b - 2])) break;
    removed.push(`trailing-chat:${rule}`);
    b--;
    while (b > a && !lineKey(lines[b - 1])) b--;
  }
  return removed.length ? lines.slice(a, b) : lines;
}

function isSeparator(line) {
  return line !== undefined && (!lineKey(line) || FENCE_OPEN_RE.test(line));
}

function matchRule(patterns, line) {
  const trimmed = lineKey(line);
  const hit = patterns.find((p) => p.re.test(trimmed));
  return hit ? hit.name : null;
}

// The lines inside a fence that wraps the whole text, or null. The wrapper is
// only recognized when no inner line could already close it.
function outerFenceContent(lines) {
  let a = 0;
  let b = lines.length;
  while (a < b && !lineKey(lines[a])) a++;
  while (b > a && !lineKey(lines[b - 1])) b--;
  if (b - a < 2) return null;
  const open = FENCE_OPEN_RE.exec(lines[a]);
  if (!open || (open[1][0] === '`' && open[2].includes('`'))) return null;
  const closes = (line) => {
    const m = /^ {0,3}(`{3,}|~{3,})\s*$/.exec(line);
    return m && m[1][0] === open[1][0] && m[1].length >= open[1].length;
  };
  if (!closes(lines[b - 1])) return null;
  for (let l = a + 1; l < b - 1; l++) if (closes(lines[l])) return null;
  const inner = lines.slice(a + 1, b - 1);
  return inner.some((l) => lineKey(l)) ? inner : null; // an empty fence is content
}

/**
 * Longest line checked against PLACEHOLDER_PATTERNS. Placeholders are short;
 * the limit also keeps every check linear on a pasted line of any length.
 */
const MAX_PLACEHOLDER_LENGTH = 200;

/** Name of the placeholder rule `line` matches, or null. */
function placeholderRule(line) {
  if (line.length > MAX_PLACEHOLDER_LENGTH) return null;
  const hit = PLACEHOLDER_PATTERNS.find((p) => p.re.test(line));
  return hit ? hit.name : null;
}

/** 0-based numbers of the placeholder lines in `text`. */
function findPlaceholders(text) {
  const out = [];
  splitLines(text).forEach((line, i) => {
    if (placeholderRule(line)) out.push(i);
  });
  return out;
}

/** How many lines above a placeholder are compared to pick among equal anchors. */
const PLACEHOLDER_CONTEXT = 3;

/**
 * Replaces each run of placeholder lines in `candidateText` with the baseline
 * lines it stands for, located by the nearest real lines above and below it
 * (the line index the anchor uses). Returns { text, filled, unresolved }:
 * `unresolved` lists the candidate lines whose position was unclear; those
 * stay in the text, for the caller to ask about.
 */
function fillPlaceholders(baselineText, candidateText) {
  const base = splitLines(baselineText);
  const cand = splitLines(candidateText);
  const index = buildLineIndex(base);
  const out = [];
  const filled = [];
  const unresolved = [];
  let cursor = 0; // baseline line after the last aligned position
  for (let i = 0; i < cand.length; i++) {
    if (!placeholderRule(cand[i])) {
      out.push(cand[i]);
      const p = firstAtOrAfter(index.get(lineKey(cand[i])), cursor);
      if (p !== -1 && lineKey(cand[i])) cursor = p + 1;
      continue;
    }
    let j = i;
    while (j + 1 < cand.length && placeholderRule(cand[j + 1])) j++;
    const span = alignGap(base, index, cand, i, j, cursor);
    if (span) {
      out.push(...base.slice(span.from, span.to));
      filled.push({ line: i, count: span.to - span.from });
      cursor = span.to;
    } else {
      for (let k = i; k <= j; k++) {
        out.push(cand[k]);
        unresolved.push(k);
      }
    }
    i = j;
  }
  return { text: out.join('\n'), filled, unresolved };
}

function firstAtOrAfter(positions, from) {
  if (!positions) return -1;
  for (const p of positions) if (p >= from) return p;
  return -1;
}

// The baseline lines [from, to) hidden by the placeholder run cand[i..j], or
// null when the neighbours do not pin them down to exactly one place.
function alignGap(base, index, cand, i, j, cursor) {
  const above = nearestContent(cand, i - 1, -1);
  const below = nearestContent(cand, j + 1, +1);
  if (above === -1 && below === -1) return null;
  let from;
  if (above === -1) {
    from = cursor;
  } else {
    const positions = (index.get(lineKey(cand[above])) || []).filter(
      (p) => p >= cursor - 1,
    );
    const pick = bestByContext(base, cand, above, positions);
    if (pick === -1) return null;
    from = pick + 1;
  }
  let to;
  if (below === -1) {
    to = base.length;
  } else {
    const positions = (index.get(lineKey(cand[below])) || []).filter(
      (p) => p >= from,
    );
    to = bestByFollowing(base, cand, below, positions);
    if (to === -1) return null;
  }
  return to >= from ? { from, to } : null;
}

function nearestContent(lines, start, step) {
  for (let l = start; l >= 0 && l < lines.length; l += step) {
    if (lineKey(lines[l]) && !placeholderRule(lines[l])) return l;
  }
  return -1;
}

// Among baseline positions of the line above a placeholder, the one whose
// preceding lines agree most with the candidate's; -1 when none or a tie.
function bestByContext(base, cand, above, positions) {
  if (!positions.length) return -1;
  if (positions.length === 1) return positions[0];
  const scored = positions.map((p) => {
    let score = 0;
    for (let k = 1; k <= PLACEHOLDER_CONTEXT; k++) {
      if (p - k < 0 || above - k < 0) break;
      if (lineKey(base[p - k]) !== lineKey(cand[above - k])) break;
      score++;
    }
    return { p, score };
  });
  scored.sort((x, y) => y.score - x.score);
  return scored[0].score > scored[1].score ? scored[0].p : -1;
}

// Among baseline positions of the line below a placeholder, the one whose
// following lines agree most with the candidate's; -1 when none or a tie. A
// line that repeats inside the hidden text ("---", "}") thus asks instead of
// cutting the gap short.
function bestByFollowing(base, cand, below, positions) {
  if (!positions.length) return -1;
  if (positions.length === 1) return positions[0];
  const scored = positions.map((p) => {
    let score = 0;
    for (let k = 1; k <= PLACEHOLDER_CONTEXT; k++) {
      if (p + k >= base.length || below + k >= cand.length) break;
      if (lineKey(base[p + k]) !== lineKey(cand[below + k])) break;
      score++;
    }
    return { p, score };
  });
  scored.sort((x, y) => y.score - x.score || x.p - y.p);
  return scored[0].score > scored[1].score ? scored[0].p : -1;
}

export {
  unwrapAnswer,
  placeholderRule,
  findPlaceholders,
  fillPlaceholders,
  LEADING_CHAT_PATTERNS,
  TRAILING_CHAT_PATTERNS,
  PLACEHOLDER_PATTERNS,
  PLACEHOLDER_CONTEXT,
  MAX_PLACEHOLDER_LENGTH,
};
