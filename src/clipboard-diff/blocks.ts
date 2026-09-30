// Markdown block structure for the clipboard diff, read with the preview's own
// markdown-it instance (src/render/parser.ts) so the diff classifies lines exactly as
// the preview does. Pure, no vscode.

import type { Env, Token } from 'markdown-it';
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
function parseBlocks(text: string): Token[] {
  const tokens: Token[] = [];
  md.block.parse(text, md, {}, tokens);
  return tokens;
}

/** A full parse: the token stream and the environment it filled. */
export interface ParsedMarkdown {
  readonly tokens: Token[];
  readonly env: Env;
}

/** Parses `text` and returns markdown-it's token stream plus its env. */
function parse(text: string): ParsedMarkdown {
  const env: Env = {};
  return { tokens: md.parse(text, env), env };
}

/**
 * Marks every line that lies in a verbatim block (fence, indented code, HTML
 * block, front matter): mask[line] === 1.
 */
function verbatimLineMask(
  tokens: readonly Token[],
  lineCount: number,
): Uint8Array {
  const mask = new Uint8Array(lineCount);
  for (const t of tokens) {
    if (!VERBATIM_BLOCKS.has(t.type) || !t.map) continue;
    for (let l = t.map[0]; l < Math.min(t.map[1], lineCount); l++) mask[l] = 1;
  }
  return mask;
}

/** A heading of a token stream. */
export interface Heading {
  /** 1-6. */
  readonly level: number;
  /** Trimmed, whitespace-collapsed, lower-cased. */
  readonly title: string;
  /** The `id` attribute, null when none was set (block-only parses). */
  readonly id: string | null;
  /** 0-based source line. */
  readonly line: number;
}

/** Heading level (1-6) and normalized title of each heading, with its line. */
function headings(tokens: readonly Token[]): Heading[] {
  const out: Heading[] = [];
  for (const [i, t] of tokens.entries()) {
    if (t.type !== 'heading_open' || !t.map) continue;
    const inline = tokens[i + 1];
    const id = t.attrGet('id');
    out.push({
      level: Number(t.tag.slice(1)),
      title: normalizeTitle(inline?.content || ''),
      id: id === null ? null : String(id),
      line: t.map[0],
    });
  }
  return out;
}

/** A heading title as compared across texts: trimmed, whitespace collapsed, lower-cased. */
function normalizeTitle(title: string): string {
  return title.trim().replace(/\s+/g, ' ').toLowerCase();
}

export { parse, parseBlocks, verbatimLineMask, headings, normalizeTitle };
