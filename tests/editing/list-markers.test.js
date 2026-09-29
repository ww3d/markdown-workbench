// List-item recognition: native markers, custom (non-CommonMark) markers,
// and the advance/family helpers.

import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh } from '../helpers/vscode-mock.js';

const vscode = install();
const editing = await loadFresh('src/editing/index.js');
const { LIST_ITEM_RE } = editing;
const { numericMarker, execListItem, advanceMarker, nextLetterSeq } =
  editing._internal;

test('LIST_ITEM_RE captures indent, bullet, gap and checkbox', () => {
  const m = LIST_ITEM_RE.exec('  - [x] text');
  assert.strictEqual(m[1], '  ');
  assert.strictEqual(m[2], '-');
  assert.strictEqual(m[4], '[x] ');
  assert.strictEqual(m[5], 'text');
});

test('numericMarker accepts only digit markers with . or )', () => {
  assert.deepStrictEqual(numericMarker('3.'), { n: 3, delim: '.' });
  assert.deepStrictEqual(numericMarker('12)'), { n: 12, delim: ')' });
  assert.strictEqual(numericMarker('-'), null);
  assert.strictEqual(numericMarker('a.'), null);
});

const ALL_EXTRA = [
  '->',
  '→',
  '❯',
  'a)',
  'A)',
  'a.',
  'A.',
  '1)',
  'a:',
  'A:',
  '1:',
];

function withExtraMarkers(markers, fn) {
  return async () => {
    vscode._config['lists.extraMarkers'] = markers;
    vscode._config['lists.extraMarkersEnabled'] = true;
    try {
      await fn();
    } finally {
      delete vscode._config['lists.extraMarkers'];
      delete vscode._config['lists.extraMarkersEnabled'];
    }
  };
}

test(
  'execListItem recognizes each enabled custom marker family',
  withExtraMarkers(ALL_EXTRA, () => {
    for (const line of [
      '-> x',
      '→ x',
      '❯ x',
      'a) x',
      'A) x',
      'a. x',
      'A. x',
      '1: x',
      'A: x',
      'za) x',
    ]) {
      const m = execListItem(line);
      assert.ok(m, line);
    }
  }),
);

test('execListItem ignores custom markers when none are enabled', () => {
  assert.strictEqual(execListItem('a) x'), null);
  assert.strictEqual(execListItem('-> x'), null);
});

test(
  'execListItem ignores a marker family that is not enabled',
  withExtraMarkers(['a)'], () => {
    assert.ok(execListItem('a) x'));
    assert.strictEqual(execListItem('A) x'), null); // upper-case not enabled
    assert.strictEqual(execListItem('-> x'), null);
  }),
);

test(
  'execListItem still ignores ordinary prose',
  withExtraMarkers(ALL_EXTRA, () => {
    assert.strictEqual(execListItem('word) text'), null); // 4-letter run, not a marker
    assert.strictEqual(execListItem('a)no gap'), null);
  }),
);

test('advanceMarker counts letters, repeats symbols, keeps the delimiter', () => {
  assert.strictEqual(advanceMarker('a)'), 'b)');
  assert.strictEqual(advanceMarker('z)'), 'za)');
  assert.strictEqual(advanceMarker('za)'), 'zb)');
  assert.strictEqual(advanceMarker('A)'), 'B)');
  assert.strictEqual(advanceMarker('Z)'), 'ZA)');
  assert.strictEqual(advanceMarker('a:'), 'b:');
  assert.strictEqual(advanceMarker('a.'), 'b.');
  assert.strictEqual(advanceMarker('->'), '->');
  assert.strictEqual(advanceMarker('→'), '→');
  assert.strictEqual(advanceMarker('3)'), '4)');
  assert.strictEqual(nextLetterSeq('zz'), 'zza');
});

test('custom markers need the enable flag, not just a non-empty list', () => {
  vscode._config['lists.extraMarkers'] = ['a)']; // filled but flag off
  try {
    assert.strictEqual(execListItem('a) x'), null);
    vscode._config['lists.extraMarkersEnabled'] = true;
    assert.ok(execListItem('a) x'));
  } finally {
    delete vscode._config['lists.extraMarkers'];
    delete vscode._config['lists.extraMarkersEnabled'];
  }
});

test('numericMarker and advanceMarker handle the colon delimiter', () => {
  assert.deepStrictEqual(numericMarker('1:'), { n: 1, delim: ':' });
  assert.strictEqual(advanceMarker('1:'), '2:');
});
