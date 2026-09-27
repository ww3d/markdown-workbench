// Tracks the baseline region of a clipboard diff through edits of its file.
// Pure, no vscode.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  createRegion,
  applyChange,
  applyChanges,
} = require('../../src/clipboard-diff/region');

test('createRegion starts untouched', () => {
  assert.deepStrictEqual(createRegion(10, 20), {
    start: 10,
    end: 20,
    touched: false,
  });
});

test('applyChange before the region shifts start and end by the size delta', () => {
  const r = createRegion(10, 20);
  const shifted = applyChange(
    r,
    { offset: 0, length: 2, text: 'abcde' },
    false,
  );
  assert.deepStrictEqual(shifted, { start: 13, end: 23, touched: false });
});

test('applyChange after the region leaves it untouched', () => {
  const r = createRegion(10, 20);
  const untouched = applyChange(
    r,
    { offset: 20, length: 0, text: 'xyz' },
    false,
  );
  assert.deepStrictEqual(untouched, { start: 10, end: 20, touched: false });
});

test('applyChange overlapping the region widens it and sets touched for a foreign edit', () => {
  const r = createRegion(10, 20);
  const widened = applyChange(
    r,
    { offset: 15, length: 10, text: 'ABCDEFGHIJKLMNOP' },
    false,
  );
  assert.deepStrictEqual(widened, { start: 10, end: 31, touched: true });
});

test('applyChange an insertion exactly at the start or end boundary counts as outside', () => {
  const r = createRegion(10, 20);
  const atStart = applyChange(r, { offset: 10, length: 0, text: 'Z' }, false);
  assert.deepStrictEqual(atStart, { start: 11, end: 21, touched: false });
  const atEnd = applyChange(r, { offset: 20, length: 0, text: 'Z' }, false);
  assert.deepStrictEqual(atEnd, { start: 10, end: 20, touched: false });
});

test('applyChange replacing the whole region collapses it to the replacement span', () => {
  const r = createRegion(10, 20);
  const replaced = applyChange(r, { offset: 5, length: 30, text: 'X' }, false);
  assert.deepStrictEqual(replaced, { start: 5, end: 6, touched: true });
});

test('applyChange (Gegenprobe) our own overlapping edit widens the region without setting touched', () => {
  const r = createRegion(10, 20);
  const own = applyChange(
    r,
    { offset: 15, length: 10, text: 'ABCDEFGHIJKLMNOP' },
    true,
  );
  assert.deepStrictEqual(own, { start: 10, end: 31, touched: false });
});

test('applyChanges applies a batch from the back, by offset descending', () => {
  const r = createRegion(10, 20);
  const changes = [
    { offset: 5, length: 0, text: 'aa' },
    { offset: 0, length: 0, text: 'b' },
  ];
  assert.deepStrictEqual(applyChanges(r, changes, false), {
    start: 13,
    end: 23,
    touched: false,
  });
});

test('applyChanges (Gegenprobe) the same changes in the opposite input order give the identical result', () => {
  const r = createRegion(10, 20);
  const changes = [
    { offset: 0, length: 0, text: 'b' },
    { offset: 5, length: 0, text: 'aa' },
  ];
  assert.deepStrictEqual(applyChanges(r, changes, false), {
    start: 13,
    end: 23,
    touched: false,
  });
});
