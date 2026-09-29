// Markdown check before a candidate replaces its baseline (docs/DECISIONS.md
// #48, F4): reset checkboxes, lost footnote and reference-link definitions,
// removed or changed front matter, and removed headings that a #anchor still
// points at. Findings are hints, never a block. Task lines are recognized with
// the preview's own CHECKBOX_RE. Pure, no vscode.

import { CHECKBOX_RE, checkboxBoxPos } from '../markdown/syntax.js';
import { parse, verbatimLineMask, headings } from './blocks.js';
import { splitLines } from './lines.js';

/** Finding kinds, also the diagnostic codes the binding reports. */
const FINDING = Object.freeze({
  CHECKBOX_RESET: 'checkbox-reset',
  DEFINITION_LOST: 'definition-lost',
  FRONT_MATTER: 'front-matter',
  ANCHOR_BROKEN: 'anchor-broken',
});

/**
 * Compares `baselineText` with `candidateText`. `anchorRefs` maps a heading id
 * to the places that link to it (e.g. ['this file'] or file names), as
 * collected by collectAnchorRefs. Returns findings
 * [{ kind, message, line }] where `line` is a 0-based candidate line or null.
 */
function checkCandidate(baselineText, candidateText, anchorRefs = new Map()) {
  const base = parse(baselineText);
  const cand = parse(candidateText);
  return [
    ...checkboxResets(baselineText, base.tokens, candidateText, cand.tokens),
    ...lostDefinitions(base.env, cand.env),
    ...frontMatterChange(base.tokens, cand.tokens),
    ...brokenAnchors(base.tokens, cand.tokens, anchorRefs),
  ];
}

// Task lines outside verbatim blocks: [{ line, label, checked, boxAt }].
function taskLines(text, tokens) {
  const lines = splitLines(text);
  const mask = verbatimLineMask(tokens, lines.length);
  const out = [];
  lines.forEach((l, i) => {
    if (mask[i]) return;
    const m = CHECKBOX_RE.exec(l);
    if (!m) return;
    out.push({
      line: i,
      label: (m[3] || '').trim(),
      checked: m[2] !== ' ',
      boxAt: checkboxBoxPos(m),
    });
  });
  return out;
}

// Pairs the k-th task with a label in the candidate with the k-th task with the
// same label in the baseline.
function pairTasks(baseTasks, candTasks) {
  const byLabel = new Map();
  for (const t of baseTasks) {
    const list = byLabel.get(t.label) || [];
    list.push(t);
    byLabel.set(t.label, list);
  }
  const seen = new Map();
  const pairs = [];
  for (const c of candTasks) {
    const list = byLabel.get(c.label);
    if (!list) continue;
    const k = seen.get(c.label) || 0;
    seen.set(c.label, k + 1);
    if (list[k]) pairs.push({ base: list[k], cand: c });
  }
  return pairs;
}

function checkboxResets(baseText, baseTokens, candText, candTokens) {
  return pairTasks(
    taskLines(baseText, baseTokens),
    taskLines(candText, candTokens),
  )
    .filter((p) => p.base.checked && !p.cand.checked)
    .map((p) => ({
      kind: FINDING.CHECKBOX_RESET,
      message: p.cand.label
        ? `Checked task "${p.cand.label}" is unchecked in the candidate.`
        : `Checked task without text (line ${p.cand.line + 1}) is unchecked in the candidate.`,
      line: p.cand.line,
    }));
}

/**
 * Sets every candidate task to the checked state of its baseline counterpart
 * (paired by label). Returns { text, restored } with the number of boxes set.
 */
function restoreCheckboxStates(baselineText, candidateText) {
  const pairs = pairTasks(
    taskLines(baselineText, parse(baselineText).tokens),
    taskLines(candidateText, parse(candidateText).tokens),
  ).filter((p) => p.base.checked !== p.cand.checked);
  if (!pairs.length) return { text: candidateText, restored: 0 };
  const lines = splitLines(candidateText);
  const eol = /\r\n/.test(candidateText) ? '\r\n' : '\n';
  for (const { base, cand } of pairs) {
    const l = lines[cand.line];
    lines[cand.line] =
      l.slice(0, cand.boxAt) +
      (base.checked ? 'x' : ' ') +
      l.slice(cand.boxAt + 1);
  }
  return { text: lines.join(eol), restored: pairs.length };
}

// markdown-it records every link reference definition in env.references; a
// footnote definition "[^1]: text" parses as one too (label "^1").
function lostDefinitions(baseEnv, candEnv) {
  const have = new Set(Object.keys(candEnv.references || {}));
  return Object.keys(baseEnv.references || {})
    .filter((label) => !have.has(label))
    .map((label) => ({
      kind: FINDING.DEFINITION_LOST,
      message: label.startsWith('^')
        ? `Footnote definition [${label}] is missing in the candidate.`
        : `Link reference definition [${label.toLowerCase()}] is missing in the candidate.`,
      line: null,
    }));
}

function frontMatterChange(baseTokens, candTokens) {
  const before = baseTokens.find((t) => t.type === 'front_matter');
  if (!before) return [];
  const after = candTokens.find((t) => t.type === 'front_matter');
  if (!after) {
    return [
      {
        kind: FINDING.FRONT_MATTER,
        message: 'The front matter is missing in the candidate.',
        line: null,
      },
    ];
  }
  if (after.meta === before.meta) return [];
  return [
    {
      kind: FINDING.FRONT_MATTER,
      message: 'The front matter differs in the candidate.',
      line: 0,
    },
  ];
}

function brokenAnchors(baseTokens, candTokens, anchorRefs) {
  const kept = new Set(headings(candTokens).map((h) => h.id));
  return headings(baseTokens)
    .filter((h) => h.id && !kept.has(h.id) && anchorRefs.has(h.id))
    .map((h) => ({
      kind: FINDING.ANCHOR_BROKEN,
      message: `Heading #${h.id} is renamed or removed, but ${anchorRefs.get(h.id).join(', ')} links to it.`,
      line: null,
    }));
}

/**
 * Heading ids that `text` links to. Without `linksHere`: links into the same
 * text ([x](#id), <a href="#id">, a reference definition [x]: #id). With
 * `linksHere(path)`: links whose path part it accepts ([x](file.md#id)), for
 * the links of another file. Returns a Set of ids; links inside verbatim
 * blocks do not count.
 */
function collectAnchorRefs(text, linksHere = null) {
  const { tokens } = parse(text);
  const ids = new Set();
  const visit = (href) => {
    const hash = href.indexOf('#');
    if (hash === -1) return;
    const path = decodeSafe(href.slice(0, hash));
    const id = decodeSafe(href.slice(hash + 1));
    if (!id) return;
    if (path === '' ? linksHere === null : linksHere?.(path)) ids.add(id);
  };
  for (const t of tokens) {
    if (t.type !== 'inline') continue;
    for (const c of t.children || []) {
      if (c.type === 'link_open') visit(c.attrGet('href') || '');
      else if (c.type === 'html_inline')
        for (const m of c.content.matchAll(/href="([^"]*)"/g)) visit(m[1]);
    }
  }
  return ids;
}

function decodeSafe(s) {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

export { checkCandidate, restoreCheckboxStates, collectAnchorRefs, FINDING };
