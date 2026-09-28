// Fence and frontmatter mask, indented code (REQ-024, REQ-003).

const { test } = require('node:test');
const assert = require('node:assert');
const { codeMask, isIndentedCode } = require('../../src/tables/code-mask.js');
const { linesDoc } = require('../../src/tables/detect.js');

const mask = (lines) => [...codeMask(linesDoc(lines))];

test('a backtick fence whose info string holds a backtick is no fence', () => {
  assert.deepStrictEqual(
    mask(['```js `x`', '| a |', '|---|', '| 1 |']),
    [0, 0, 0, 0],
  );
});

test('fences mask their lines, closing needs the same marker at least as long', () => {
  assert.deepStrictEqual(
    mask(['````', '```', 'x', '````', 'y']),
    [1, 1, 1, 1, 0],
  );
  assert.deepStrictEqual(mask(['~~~', '```', '~~~', 'y']), [1, 1, 1, 0]);
});

test('the frontmatter is masked up to its closing line', () => {
  assert.deepStrictEqual(mask(['---', 'a: 1', '...', 'x']), [1, 1, 1, 0]);
});

test('a fence opened in a quote ends with the quote', () => {
  assert.deepStrictEqual(mask(['> ```', '> x', 'y']), [1, 1, 0]);
});

test('an indented line is code outside a list, not inside one', () => {
  const doc = linesDoc(['text', '', '    ```', '- item', '', '    ```']);
  assert.strictEqual(isIndentedCode(doc, 2, '    '), true);
  assert.strictEqual(isIndentedCode(doc, 5, '    '), false);
  assert.deepStrictEqual(mask(['text', '', '    ```', 'y']), [0, 0, 0, 0]);
});
