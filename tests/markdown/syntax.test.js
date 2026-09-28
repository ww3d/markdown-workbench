// Markdown source primitives shared by the editor commands, the preview and
// the clipboard diff: CHECKBOX_RE, splitRow, isSeparatorRow, reflowTable.
// This module must stay usable without the extension host - unlike the other
// test files it deliberately does not require tests/helpers/vscode-mock.js.
const { test } = require('node:test');
const assert = require('node:assert');

test('src/markdown/syntax.js loads without vscode', () => {
  delete require.cache[require.resolve('../../src/markdown/syntax')];
  assert.doesNotThrow(() => require('../../src/markdown/syntax'));
});

const {
  CHECKBOX_RE,
  checkboxBoxPos,
  splitRow,
  isSeparatorRow,
  reflowTable,
} = require('../../src/markdown/syntax');

// --- CHECKBOX_RE ---

test('CHECKBOX_RE matches plain and numbered task items', () => {
  let m = CHECKBOX_RE.exec('- [ ] text');
  assert.strictEqual(m[1], '- ');
  assert.strictEqual(m[2], ' ');
  assert.strictEqual(m[3], ' text');
  m = CHECKBOX_RE.exec('1. [X] text');
  assert.strictEqual(m[2], 'X');
});

test('CHECKBOX_RE matches compound markers and an empty label', () => {
  const m = CHECKBOX_RE.exec('1. - [ ] text');
  assert.strictEqual(m[1], '1. - ');
  const empty = CHECKBOX_RE.exec('- [ ]');
  assert.strictEqual(empty[3], undefined);
});

test('CHECKBOX_RE (counter-check) rejects a missing marker, bad box char and no gap after the box', () => {
  assert.strictEqual(CHECKBOX_RE.exec('[ ] text'), null);
  assert.strictEqual(CHECKBOX_RE.exec('- [z] text'), null);
  assert.strictEqual(CHECKBOX_RE.exec('- [ ]text'), null);
});

// --- checkboxBoxPos ---

test('checkboxBoxPos points at the char between the brackets, plain and compound markers', () => {
  assert.strictEqual(checkboxBoxPos(CHECKBOX_RE.exec('- [ ] text')), 3);
  assert.strictEqual(checkboxBoxPos(CHECKBOX_RE.exec('1. - [ ] text')), 6);
});

test('(counter-check) checkboxBoxPos ignores the box char and label, only the prefix', () => {
  const shortLabel = checkboxBoxPos(CHECKBOX_RE.exec('- [x] a'));
  const longLabel = checkboxBoxPos(
    CHECKBOX_RE.exec('- [ ] a much longer label'),
  );
  assert.strictEqual(shortLabel, longLabel);
});

// --- splitRow ---

test('splitRow trims cells and strips outer pipes', () => {
  assert.deepStrictEqual(splitRow('| a | b |'), ['a', 'b']);
});

test('splitRow tolerates a row without outer pipes', () => {
  assert.deepStrictEqual(splitRow('a | b'), ['a', 'b']);
});

test('splitRow (counter-check) does not merge cells of a row with no separators', () => {
  assert.deepStrictEqual(splitRow('| just one |'), ['just one']);
});

// --- isSeparatorRow ---

test('isSeparatorRow accepts alignment colons and bare dashes', () => {
  assert.ok(isSeparatorRow([':---', '---:', ':-:']));
  assert.ok(isSeparatorRow(['-']));
});

test('isSeparatorRow rejects an empty row', () => {
  assert.strictEqual(isSeparatorRow([]), false);
});

test('isSeparatorRow (counter-check) rejects a row with real content', () => {
  assert.ok(!isSeparatorRow(['a', '---']));
});

// --- reflowTable ---

test('reflowTable distribute pads every column to its widest cell', () => {
  const lines = ['| a | bb |', '|---|---|', '| c | d |'];
  assert.deepStrictEqual(reflowTable(lines, 'distribute'), [
    '| a   | bb  |',
    '| --- | --- |',
    '| c   | d   |',
  ]);
});

test('reflowTable consolidate compacts to single spaces and keeps alignment colons', () => {
  const lines = ['| left | right |', '|:---|---:|', '| x | y |'];
  assert.deepStrictEqual(reflowTable(lines, 'consolidate'), [
    '| left | right |',
    '| :-- | --: |',
    '| x | y |',
  ]);
});

test('reflowTable (counter-check) consolidate does not pad columns like distribute', () => {
  const lines = ['| a | bb |', '|---|---|', '| c | d |'];
  const distributed = reflowTable(lines, 'distribute');
  const consolidated = reflowTable(lines, 'consolidate');
  assert.notDeepStrictEqual(consolidated, distributed);
  assert.deepStrictEqual(consolidated, [
    '| a | bb |',
    '| --- | --- |',
    '| c | d |',
  ]);
});
