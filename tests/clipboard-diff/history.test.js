// Session list of clipboard texts the extension itself read. Memory only,
// pure, no vscode.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  ClipboardHistory,
  previewOf,
  MAX_HISTORY_ENTRIES,
  MAX_ENTRY_BYTES,
  PREVIEW_LENGTH,
} = require('../../src/clipboard-diff/history');

// --- ring buffer ---

test('add() keeps at most MAX_HISTORY_ENTRIES, newest first, dropping the oldest', () => {
  const h = new ClipboardHistory();
  for (let i = 0; i < MAX_HISTORY_ENTRIES + 3; i++) h.add(`t${i}`);
  const texts = h.list().map((e) => e.text);
  assert.strictEqual(texts.length, MAX_HISTORY_ENTRIES);
  assert.strictEqual(texts[0], `t${MAX_HISTORY_ENTRIES + 2}`);
  assert.ok(!texts.includes('t0'));
  assert.ok(!texts.includes('t1'));
  assert.ok(!texts.includes('t2'));
});

test('add() (counter-check) exactly MAX_HISTORY_ENTRIES entries drops none', () => {
  const h = new ClipboardHistory();
  for (let i = 0; i < MAX_HISTORY_ENTRIES; i++) h.add(`t${i}`);
  assert.strictEqual(h.list().length, MAX_HISTORY_ENTRIES);
  assert.ok(
    h
      .list()
      .map((e) => e.text)
      .includes('t0'),
  );
});

// --- byte limit ---

test('add() rejects an entry over MAX_ENTRY_BYTES, counted in UTF-8 bytes, not truncated', () => {
  // Each euro sign is 3 UTF-8 bytes, so the char count alone would look fine.
  const big = '€'.repeat(Math.floor(MAX_ENTRY_BYTES / 3) + 10);
  assert.ok(Buffer.byteLength(big, 'utf8') > MAX_ENTRY_BYTES);
  const h = new ClipboardHistory();
  assert.strictEqual(h.add(big), false);
  assert.strictEqual(h.list().length, 0);
});

test('add() (counter-check) an entry of exactly MAX_ENTRY_BYTES bytes is accepted whole, not truncated', () => {
  const exact = 'a'.repeat(MAX_ENTRY_BYTES);
  const h = new ClipboardHistory();
  assert.strictEqual(h.add(exact), true);
  assert.strictEqual(h.list()[0].text.length, MAX_ENTRY_BYTES);
});

// --- empty ---

test('add() rejects an empty string', () => {
  const h = new ClipboardHistory();
  assert.strictEqual(h.add(''), false);
  assert.strictEqual(h.list().length, 0);
});

// --- duplicate ---

test('add() moves an identical earlier entry to the front instead of duplicating it', () => {
  const h = new ClipboardHistory();
  h.add('a');
  h.add('b');
  h.add('c');
  h.add('a');
  assert.deepStrictEqual(
    h.list().map((e) => e.text),
    ['a', 'c', 'b'],
  );
});

test('add() (counter-check) a merely similar text is not treated as a duplicate', () => {
  const h = new ClipboardHistory();
  h.add('a');
  h.add('a ');
  assert.deepStrictEqual(
    h.list().map((e) => e.text),
    ['a ', 'a'],
  );
});

// --- previewOf ---

test('previewOf takes the first non-blank line and collapses internal whitespace', () => {
  assert.strictEqual(
    previewOf('\n\n   \nfirst   real    line\nsecond'),
    'first real line',
  );
});

test('previewOf cuts a long line to PREVIEW_LENGTH with an ellipsis', () => {
  const preview = previewOf('x'.repeat(PREVIEW_LENGTH + 10));
  assert.strictEqual(preview.length, PREVIEW_LENGTH);
  assert.strictEqual(preview, `${'x'.repeat(PREVIEW_LENGTH - 1)}…`);
});

test('previewOf (counter-check) a line at exactly PREVIEW_LENGTH is not cut', () => {
  const line = 'x'.repeat(PREVIEW_LENGTH);
  assert.strictEqual(previewOf(line), line);
});
