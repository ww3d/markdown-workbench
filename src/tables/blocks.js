// The block structure of a document as the preview parses it: which lines are
// table rows or paragraph lines (and where their content starts), which lines
// are code, HTML or frontmatter. One block parse with the preview's own
// markdown-it instance per document version (docs/DECISIONS.md #48, D1).

const { md } = require('../render/parser');

// Tokens whose lines no table branch may touch (E10, and HTML blocks the
// preview shows as they are).
const CODE_TYPES = new Set([
  'fence',
  'code_block',
  'html_block',
  'front_matter',
]);

const cache = new WeakMap();

/**
 * @typedef {{ kind: 'table' | 'paragraph', start: number, at: number }} LineStart
 *   `start` is the first line of the table or paragraph, `at` the offset in the
 *   line where its content starts.
 * @typedef {object} Blocks
 * @property {Array<LineStart | undefined>} lines per line, for table rows and paragraph lines
 * @property {Uint8Array} code per line 1 inside a fence, code block, HTML block or the frontmatter
 * @property {number[]} tables first line of every table, in document order
 */

/**
 * The block structure of `doc`, cached per document version (a document
 * without a version is parsed on every call).
 * @param {{ lineCount: number, lineAt(n: number): { text: string }, version?: number }} doc
 * @returns {Blocks}
 */
function blocksOf(doc) {
  const hit = cache.get(doc);
  if (hit && doc.version !== undefined && hit.version === doc.version)
    return hit.blocks;
  const texts = [];
  for (let l = 0; l < doc.lineCount; l++) texts.push(doc.lineAt(l).text);
  const lineStarts = new Array(texts.length);
  const env = { lineStarts };
  const tokens = [];
  md.block.parse(texts.join('\n'), md, env, tokens);
  // Offsets from the parse are absolute; make them relative to each line.
  let offset = 0;
  const tables = [];
  for (let l = 0; l < texts.length; l++) {
    const s = lineStarts[l];
    if (s) {
      s.at -= offset;
      if (s.kind === 'table' && s.start === l) tables.push(l);
    }
    offset += texts[l].length + 1;
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
 * @param {{ version?: number }} doc
 */
function isParsed(doc) {
  const hit = cache.get(doc);
  return !!hit && doc.version !== undefined && hit.version === doc.version;
}

module.exports = { blocksOf, isParsed };
