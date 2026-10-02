// Markdown block structure read with the preview's own markdown-it instance.
// Pure, no vscode - the instance comes from src/render/parser.js, which
// imports no vscode (the Shiki fence renderer is added in src/render/index.js).
const { test } = require('node:test');
const assert = require('node:assert');
const {
  parse,
  verbatimLineMask,
  headings,
} = require('../../src/clipboard-diff/blocks');

const SAMPLE = [
  '---',
  'title: x',
  '---',
  '',
  '# My  Title',
  '',
  '## Sub',
  '',
  '```js',
  'code here',
  '```',
  '',
  '    indented code',
  '',
  '<div>',
  'html block',
  '</div>',
].join('\n');

// --- verbatimLineMask ---

test('verbatimLineMask covers fence, indented code_block, html_block and front_matter', () => {
  const lines = SAMPLE.split('\n');
  const { tokens } = parse(SAMPLE);
  const mask = verbatimLineMask(tokens, lines.length);
  assert.deepStrictEqual(
    [...mask],
    [1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1],
  );
});

test('verbatimLineMask (counter-check) a heading and a blank line stay unmasked', () => {
  const lines = SAMPLE.split('\n');
  const { tokens } = parse(SAMPLE);
  const mask = verbatimLineMask(tokens, lines.length);
  assert.strictEqual(mask[4], 0); // '# My  Title'
  assert.strictEqual(mask[3], 0); // blank line
});

test('verbatimLineMask stays within a shorter lineCount', () => {
  const { tokens } = parse('```\ncode\n```\n');
  const mask = verbatimLineMask(tokens, 2);
  assert.strictEqual(mask.length, 2);
  assert.deepStrictEqual([...mask], [1, 1]);
});

// --- headings ---

test('headings capture level, normalized title, id and line', () => {
  const { tokens } = parse(SAMPLE);
  assert.deepStrictEqual(headings(tokens), [
    { level: 1, title: 'my title', id: 'my--title', line: 4 },
    { level: 2, title: 'sub', id: 'sub', line: 6 },
  ]);
});

test('headings normalizes whitespace and case in the title', () => {
  const { tokens } = parse('##   Weird   Spacing   HERE\n');
  assert.strictEqual(headings(tokens)[0].title, 'weird spacing here');
});

test('headings (counter-check) a heading-like line inside a fence is not collected', () => {
  const { tokens } = parse('```\n# not a heading\n```\n\n# real heading\n');
  const found = headings(tokens);
  assert.strictEqual(found.length, 1);
  assert.strictEqual(found[0].title, 'real heading');
});
