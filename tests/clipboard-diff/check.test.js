// Markdown check before a candidate replaces its baseline: reset checkboxes,
// lost definitions, front matter changes, broken anchors. Pure, no vscode.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  checkCandidate,
  restoreCheckboxStates,
  collectAnchorRefs,
  FINDING,
} = require('../../src/clipboard-diff/check');

// --- checkbox reset ---

test('checkCandidate reports a checkbox-reset finding when a checked task becomes unchecked', () => {
  const base = '- [x] task one\n- [ ] task two\n';
  const cand = '- [ ] task one\n- [ ] task two\n';
  assert.deepStrictEqual(checkCandidate(base, cand), [
    {
      kind: FINDING.CHECKBOX_RESET,
      message: 'Checked task "task one" is unchecked in the candidate.',
      line: 0,
    },
  ]);
});

test('(Gegenprobe) checkCandidate reports nothing when the baseline task was already unchecked', () => {
  const base = '- [ ] task one\n';
  const cand = '- [ ] task one\n';
  assert.deepStrictEqual(checkCandidate(base, cand), []);
});

test('checkCandidate ignores task-looking lines inside a fence', () => {
  const base = '```\n- [x] fenced task\n```\n';
  const cand = '```\n- [ ] fenced task\n```\n';
  assert.deepStrictEqual(checkCandidate(base, cand), []);
});

// --- restoreCheckboxStates ---

test('restoreCheckboxStates sets each candidate box to its baseline pair, both directions, paired by occurrence', () => {
  const base = '- [x] dup\n- [ ] dup\n';
  const cand = '- [ ] dup\n- [x] dup\n';
  const result = restoreCheckboxStates(base, cand);
  assert.strictEqual(result.text, '- [x] dup\n- [ ] dup\n');
  assert.strictEqual(result.restored, 2);
});

test('(Gegenprobe) restoreCheckboxStates is a no-op when every pair already agrees', () => {
  const base = '- [x] a\n- [ ] b\n';
  const cand = '- [x] a\n- [ ] b\n';
  const result = restoreCheckboxStates(base, cand);
  assert.strictEqual(result.text, cand);
  assert.strictEqual(result.restored, 0);
});

// --- lost footnote / link reference definitions ---

test('checkCandidate reports a lost link reference definition', () => {
  const base = 'See [a][1].\n\n[1]: http://x\n';
  const cand = 'See [a][1] gone.\n';
  assert.deepStrictEqual(checkCandidate(base, cand), [
    {
      kind: FINDING.DEFINITION_LOST,
      message: 'Link reference definition [1] is missing in the candidate.',
      line: null,
    },
  ]);
});

test('checkCandidate reports a lost footnote definition', () => {
  const base = 'See [^1].\n\n[^1]: http://note\n';
  const cand = 'See it.\n';
  assert.deepStrictEqual(checkCandidate(base, cand), [
    {
      kind: FINDING.DEFINITION_LOST,
      message: 'Footnote definition [^1] is missing in the candidate.',
      line: null,
    },
  ]);
});

// --- front matter ---

test('checkCandidate reports front matter removed', () => {
  const base = '---\ntitle: A\n---\nbody\n';
  const cand = 'body\n';
  assert.deepStrictEqual(checkCandidate(base, cand), [
    {
      kind: FINDING.FRONT_MATTER,
      message: 'The front matter is missing in the candidate.',
      line: null,
    },
  ]);
});

test('checkCandidate reports front matter changed', () => {
  const base = '---\ntitle: A\n---\nbody\n';
  const cand = '---\ntitle: B\n---\nbody\n';
  assert.deepStrictEqual(checkCandidate(base, cand), [
    {
      kind: FINDING.FRONT_MATTER,
      message: 'The front matter differs in the candidate.',
      line: 0,
    },
  ]);
});

test('(Gegenprobe) checkCandidate reports nothing when there is no front matter at all', () => {
  const base = 'body\n';
  const cand = 'body changed\n';
  assert.deepStrictEqual(checkCandidate(base, cand), []);
});

// --- broken anchor ---

test('checkCandidate reports a broken anchor only when anchorRefs has the id', () => {
  const base = '## Kept Section\ntext\n## Removed Section\nmore\n';
  const cand = '## Kept Section\ntext\n## Renamed Section\nmore\n';
  const refs = new Map([['removed-section', ['this file']]]);
  assert.deepStrictEqual(checkCandidate(base, cand, refs), [
    {
      kind: FINDING.ANCHOR_BROKEN,
      message:
        'Heading #removed-section is renamed or removed, but this file links to it.',
      line: null,
    },
  ]);
});

test('(Gegenprobe) checkCandidate stays silent about the same renamed heading when nothing links to it', () => {
  const base = '## Kept Section\ntext\n## Removed Section\nmore\n';
  const cand = '## Kept Section\ntext\n## Renamed Section\nmore\n';
  assert.deepStrictEqual(checkCandidate(base, cand), []);
});

// --- collectAnchorRefs ---

test('collectAnchorRefs collects (#id), <a href="#id">, ignores other files and links inside code fences', () => {
  const text = [
    'See [x](#id1) and [y](file.md#id2) and <a href="#id3">z</a>.',
    '',
    '```',
    '[ignored](#idfence)',
    '```',
    '[other](other.md#id4)',
  ].join('\n');
  assert.deepStrictEqual([...collectAnchorRefs(text)].sort(), ['id1', 'id3']);
});

test('collectAnchorRefs with a fileName only picks up (file.md#id) links for that file', () => {
  const text = [
    'See [x](#id1) and [y](file.md#id2) and <a href="#id3">z</a>.',
    '[other](other.md#id4)',
  ].join('\n');
  assert.deepStrictEqual([...collectAnchorRefs(text, 'file.md')], ['id2']);
});

test('(Gegenprobe) collectAnchorRefs ignores a link with no #fragment at all', () => {
  const text = '[plain](http://example.com/no-fragment)';
  assert.deepStrictEqual([...collectAnchorRefs(text)], []);
});

// --- findings are plain data, never throw ---

test('checkCandidate never throws, even for empty or unrelated texts', () => {
  assert.doesNotThrow(() => checkCandidate('', ''));
  assert.doesNotThrow(() =>
    checkCandidate('# a\n', 'completely different text\n'),
  );
  const findings = checkCandidate('', '');
  assert.ok(Array.isArray(findings));
});
