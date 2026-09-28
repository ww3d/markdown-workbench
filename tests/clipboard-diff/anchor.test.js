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

test('(counter-check) a candidate matching nothing in the baseline returns no matches', () => {
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

test('(counter-check) a candidate covering only most of the file, not the whole share, still returns a match', () => {
  const lines = Array.from({ length: 20 }, (_, i) => `line${i}`);
  const baseline = lines.join('\n');
  const candidate = lines.slice(0, 10).join('\n'); // half the file, below WHOLE_FILE_SHARE
  const result = findAnchor(baseline, candidate);
  assert.ok(result.matches.length > 0);
});

// --- confidence ---

test('two equally good places are not confident (MIN_ANCHOR_LEAD)', () => {
  const baseline = [
    'start1',
    'mid1',
    'end1',
    'started',
    'filler',
    'start1',
    'mid2',
    'end1',
  ].join('\n');
  const r = findAnchor(baseline, 'start1\nend1');
  assert.strictEqual(r.confident, false);
  assert.strictEqual(
    r.matches[0].score,
    r.matches[1].score,
    'a tie, not a weak score',
  );
  assert.strictEqual(r.matches[0].score, 1);
});

test('a clearly better place leads a weaker one and is confident', () => {
  const baseline = [
    'a1',
    'x',
    'y',
    'z',
    'filler',
    'a1',
    'x',
    'q',
    'r',
    'filler2',
  ].join('\n');
  const r = findAnchor(baseline, 'a1\nx\ny\nz');
  assert.strictEqual(r.confident, true);
  assert.strictEqual(r.matches[0].start, 0);
});

test('a single weak match is offered but not confident (MIN_ANCHOR_CONFIDENCE)', () => {
  const baseline = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'].join(
    '\n',
  );
  const r = findAnchor(baseline, 'c\nNEW1\nNEW2\nNEW3');
  assert.strictEqual(r.confident, false);
  assert.ok(r.matches.length >= 1 && r.matches[0].score < 0.6);
});

test('placeholder lines never anchor; the real lines around them do', () => {
  const baseline = [
    'intro',
    'a',
    'b',
    'c',
    'd',
    'e',
    'real line',
    'tail',
    'more',
    'end',
  ].join('\n');
  const r = findAnchor(baseline, '… rest unchanged …\nreal line\ntail');
  assert.strictEqual(r.confident, true);
  assert.deepStrictEqual([r.matches[0].start, r.matches[0].end], [6, 8]);
});

test('a candidate spanning two sections replaces both', () => {
  const baseline =
    '# T\n\n## Install\n\ni\n\n## Usage\n\nu\n\n## License\n\nl\n';
  const r = findAnchor(baseline, '## Install\n\nI2\n\n## Usage\n\nU2\n');
  assert.strictEqual(r.confident, true);
  assert.deepStrictEqual([r.matches[0].start, r.matches[0].end], [2, 9]);
});

test('a candidate with a further section the baseline lacks there is not confident', () => {
  const baseline = '# T\n\n## Install\n\ni\n\n## Usage\n\nu\n';
  const r = findAnchor(baseline, '## Install\n\nI2\n\n## Other\n\nx\n');
  assert.strictEqual(r.confident, false);
});

test('MIN_ANCHOR_LEAD separates a runner-up just inside it from one at it', () => {
  const { MIN_ANCHOR_LEAD } = require('../../src/clipboard-diff/anchor');
  const cand = Array.from({ length: 20 }, (_, i) => `L${i}`);
  const withMisses = (n) => cand.map((l, i) => (i > 0 && i <= n ? `X${i}` : l));
  const place = (misses) => {
    const lead = MIN_ANCHOR_LEAD * cand.length;
    const baseline = [...cand, 'gap1', 'gap2', ...withMisses(misses)].join(
      '\n',
    );
    return { lead, r: findAnchor(baseline, cand.join('\n')) };
  };
  // Runner-up 2 of 20 lines worse (0.10 < 0.15): not confident.
  assert.strictEqual(place(2).r.confident, false);
  // Runner-up 3 of 20 lines worse (exactly MIN_ANCHOR_LEAD): confident.
  assert.strictEqual(place(3).r.confident, true);
});
