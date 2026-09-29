// Markdown block structure for the clipboard diff, read with the preview's own
// markdown-it instance (src/render/parser.js) so the diff classifies lines exactly as
// the preview does. Pure, no vscode.

import { md } from '../render/parser.ts';

// Block tokens whose lines are verbatim content: the style alignment and the
// Markdown check never read or rewrite anything inside them.
const VERBATIM_BLOCKS = new Set([
  'fence',
  'code_block',
  'html_block',
  'front_matter',
]);

/**
 * Block structure only (no inline rules, no core rules): enough for headings,
 * lists and verbatim blocks, several times faster on a long baseline. Inline
 * tokens keep their raw content; heading ids are not set.
 */
function parseBlocks(text) {
  const tokens = [];
  md.block.parse(text, md, {}, tokens);
  return tokens;
}

/** Parses `text` and returns markdown-it's token stream plus its env. */
function parse(text) {
  const env = {};
  return { tokens: md.parse(text, env), env };
}

/**
 * Marks every line that lies in a verbatim block (fence, indented code, HTML
 * block, front matter): mask[line] === 1.
 */
function verbatimLineMask(tokens, lineCount) {
  const mask = new Uint8Array(lineCount);
  for (const t of tokens) {
    if (!VERBATIM_BLOCKS.has(t.type) || !t.map) continue;
    for (let l = t.map[0]; l < Math.min(t.map[1], lineCount); l++) mask[l] = 1;
  }
  return mask;
}

/** Heading level (1-6) and normalized title of each heading, with its line. */
function headings(tokens) {
  const out = [];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t.type !== 'heading_open' || !t.map) continue;
    const inline = tokens[i + 1];
    out.push({
      level: Number(t.tag.slice(1)),
      title: normalizeTitle(inline?.content || ''),
      id: t.attrGet('id'),
      line: t.map[0],
    });
  }
  return out;
}

function normalizeTitle(title) {
  return title.trim().replace(/\s+/g, ' ').toLowerCase();
}

export { parse, parseBlocks, verbatimLineMask, headings, normalizeTitle };
