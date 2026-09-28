// Display width per grapheme (REQ-006, REQ-007).

const { test } = require('node:test');
const assert = require('node:assert');
const { displayWidth } = require('../../src/tables/width.js');

test('ASCII counts one column per character', () => {
  assert.strictEqual(displayWidth('abc |x'), 6);
  assert.strictEqual(displayWidth(''), 0);
});

test('East-Asian wide and fullwidth count two (REQ-006)', () => {
  assert.strictEqual(displayWidth('漢字'), 4);
  assert.strictEqual(displayWidth('ｱ'), 1, 'halfwidth katakana stays narrow');
  assert.strictEqual(displayWidth('ＡＢ'), 4, 'fullwidth latin');
});

test('emoji graphemes count two, whatever their code units (REQ-006)', () => {
  assert.strictEqual(displayWidth('😀'), 2);
  assert.strictEqual(displayWidth('👩‍👩‍👧'), 2, 'ZWJ family is one grapheme');
  assert.strictEqual(displayWidth('👍🏽'), 2, 'skin tone modifier');
  assert.strictEqual(displayWidth('🇩🇪'), 2, 'flag');
  assert.strictEqual(displayWidth('❤️'), 2, 'VS16 emoji presentation');
});

test('combining marks and zero-width characters take no column (REQ-006)', () => {
  assert.strictEqual(displayWidth('é'), 1, 'e + combining acute');
  assert.strictEqual(displayWidth('a​b'), 2, 'zero-width space');
  assert.strictEqual(displayWidth('́'), 0, 'lone combining mark');
});

test('ambiguous width is 1, or 2 with ambiguousWidth wide (REQ-007)', () => {
  assert.strictEqual(displayWidth('±§'), 2);
  assert.strictEqual(displayWidth('±§', true), 4);
  assert.strictEqual(displayWidth('abc', true), 3, 'ASCII never ambiguous');
});
