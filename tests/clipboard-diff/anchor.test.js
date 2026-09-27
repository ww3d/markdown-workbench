// Section anchor: finds the part of the baseline a clipboard text most likely
// replaces. Pure, no vscode.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  findAnchor,
  MAX_ANCHOR_CANDIDATES,
} = require('../../src/clipboard-diff/anchor');

// --- heading-led candidate ---

test('a heading-led candidate picks the same-named section up to the next heading of same/higher level, not a deeper one', () => {
  const baseline = [
    '# Title',
    '',
    '## Section A',
    'para a1',
    '',
    '### Sub A1',
    'sub content',
    '',
    '## Section B',
    'para b1',
  ].join('\n');
  const candidate = ['## Section A', 'new para a1'].join('\n');
  const result = findAnchor(baseline, candidate);
  assert.strictEqual(result.confident, true);
  assert.deepStrictEqual(result.matches, [
    { start: 2, end: 7, score: 1, kind: 'heading' },
  ]);
  // end === 7 reaches past the deeper '### Sub A1' (line 5) into 'Section B'
  // territory, proving the deeper heading did not stop the section early.
});

test('a duplicate heading yields both matches and is not confident', () => {
  const baseline = ['## Dup', 'one', '', '## Dup', 'two'].join('\n');
  const candidate = ['## Dup', 'x'].join('\n');
  const result = findAnchor(baseline, candidate);
  assert.strictEqual(result.confident, false);
  assert.strictEqual(result.matches.length, 2);
  assert.deepStrictEqual(
    result.matches.map((m) => m.kind),
    ['heading', 'heading'],
  );
});

// --- line-hash candidate ---

test('a line-hash match tolerates changed middle lines', () => {
  const baseline = ['a', 'b', 'c', 'd', 'e', 'f', 'g'].join('\n');
  const candidate = ['b', 'CHANGED', 'd'].join('\n');
  const result = findAnchor(baseline, candidate);
  assert.strictEqual(result.confident, true);
  assert.deepStrictEqual(result.matches[0], {
    start: 1,
    end: 4,
    score: 2 / 3,
    kind: 'lines',
  });
});

test('(Gegenprobe) a candidate matching nothing in the baseline returns no matches', () => {
  const baseline = ['a', 'b', 'c', 'd', 'e', 'f', 'g'].join('\n');
  const candidate = ['zzz1', 'zzz2'].join('\n');
  assert.deepStrictEqual(findAnchor(baseline, candidate), {
    matches: [],
    confident: false,
  });
});

test('an ambiguous first line occurring more than MAX_ANCHOR_CANDIDATES times is not confident', () => {
  const lines = [];
  for (let i = 0; i < MAX_ANCHOR_CANDIDATES + 2; i++) {
    lines.push('dup');
    lines.push(`u${i}`);
  }
  const baseline = lines.join('\n');
  const candidate = ['dup', 'zzznomatch'].join('\n');
  const result = findAnchor(baseline, candidate);
  assert.strictEqual(result.confident, false);
  assert.ok(result.matches.length > 0);
});

test('a hit covering the whole file returns no matches, since the whole file is already the baseline', () => {
  const baseline = Array.from({ length: 20 }, (_, i) => `line${i}`).join('\n');
  assert.deepStrictEqual(findAnchor(baseline, baseline), {
    matches: [],
    confident: false,
  });
});

test('(Gegenprobe) a candidate covering only most of the file, not the whole share, still returns a match', () => {
  const lines = Array.from({ length: 20 }, (_, i) => `line${i}`);
  const baseline = lines.join('\n');
  const candidate = lines.slice(0, 10).join('\n'); // half the file, below WHOLE_FILE_SHARE
  const result = findAnchor(baseline, candidate);
  assert.ok(result.matches.length > 0);
});
