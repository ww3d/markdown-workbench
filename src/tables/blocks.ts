// The block structure of a document as the preview parses it: which lines are
// table rows or paragraph lines (and where their content starts), which lines
// are code, HTML or frontmatter. One block parse with the preview's own
// markdown-it instance per document version (docs/DECISIONS.md #49, D1).

import type { Token } from 'markdown-it';
import { md } from '../render/parser.ts';

// Tokens whose lines no table branch may touch (E10, and HTML blocks the
// preview shows as they are).
const CODE_TYPES = new Set([
  'fence',
  'code_block',
  'html_block',
  'front_matter',
]);

/**
 * Anything with `lineCount` and `lineAt(n).text`: a vscode `TextDocument`, or
 * `linesDoc` over a string array. `version` enables the per-version caches.
 */
export interface LineDoc {
  readonly lineCount: number;
  lineAt(n: number): { readonly text: string };
  readonly version?: number;
}

/**
 * Where a line stands in the block structure: `start` is the first line of the
 * table or paragraph, `at` the offset in the line where its content starts.
 */
export interface LineStart {
  readonly kind: 'table' | 'paragraph';
  readonly start: number;
  at: number;
}

/** The block structure of a document, one entry per line. */
export interface Blocks {
  /** Per line, for table rows and paragraph lines. */
  readonly lines: ReadonlyArray<LineStart | undefined>;
  /** Per line 1 inside a fence, code block, HTML block or the frontmatter. */
  readonly code: Uint8Array;
  /** First line of every table, in document order. */
  readonly tables: readonly number[];
}

const cache = new WeakMap<
  LineDoc,
  { version: number | undefined; blocks: Blocks }
>();

/**
 * The block structure of `doc`, cached per document version (a document
 * without a version is parsed on every call).
 */
function blocksOf(doc: LineDoc): Blocks {
  const hit = cache.get(doc);
  if (hit && doc.version !== undefined && hit.version === doc.version)
    return hit.blocks;
  const texts: string[] = [];
  for (let l = 0; l < doc.lineCount; l++) texts.push(doc.lineAt(l).text);
  const lineStarts = new Array<LineStart | undefined>(texts.length);
  const env = { lineStarts };
  const tokens: Token[] = [];
  md.block.parse(texts.join('\n'), md, env, tokens);
  // Offsets from the parse are absolute; make them relative to each line.
  let offset = 0;
  const tables: number[] = [];
  for (const [l, text] of texts.entries()) {
    const s = lineStarts[l];
    if (s) {
      s.at -= offset;
      if (s.kind === 'table' && s.start === l) tables.push(l);
    }
    offset += text.length + 1;
  }
  const code = new Uint8Array(texts.length);
  for (const t of tokens)
    if (t.map && CODE_TYPES.has(t.type)) code.fill(1, t.map[0], t.map[1]);
  const blocks = { lines: lineStarts, code, tables };
  cache.set(doc, { version: doc.version, blocks });
  return blocks;
}

/**
 * Whether the block structure of the current version of `doc` is already
 * parsed (then `blocksOf` costs nothing).
 */
function isParsed(doc: LineDoc): boolean {
  const hit = cache.get(doc);
  return !!hit && doc.version !== undefined && hit.version === doc.version;
}

export { blocksOf, isParsed };
