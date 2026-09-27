// Markdown style alignment: derives the house style of a baseline and aligns
// a candidate to it surgically. Pure, no vscode.
const { test } = require('node:test');
const assert = require('node:assert');
const { styleProfile, alignStyle } = require('../../src/clipboard-diff/style');

// --- styleProfile ---

test('styleProfile picks the dominant bullet, emphasis, strong and table style', () => {
  const text = [
    '- a',
    '- b',
    '* c',
    '',
    'This is **bold** and _em_ and __also bold__ and *also em*.',
    '',
    '| a | b |',
    '| --- | --- |',
    '| 1 | 22 |',
  ].join('\n');
  assert.deepStrictEqual(styleProfile(text), {
    bullet: '-',
    emphasis: '_',
    strong: '**',
    table: 'consolidate',
  });
});

test('(counter-check) styleProfile reports null for a style the text never uses', () => {
  const profile = styleProfile(
    'Just a plain paragraph with no lists, emphasis or tables.',
  );
  assert.deepStrictEqual(profile, {
    bullet: null,
    emphasis: null,
    strong: null,
    table: null,
  });
});

// --- alignStyle: conversions ---

test('alignStyle converts * bullets to -', () => {
  const result = alignStyle('* item one\n* item two\n', { bullet: '-' });
  assert.strictEqual(result.text, '- item one\n- item two\n');
  assert.strictEqual(result.changed, 2);
});

test('alignStyle converts _x_ to *x* and __x__ to **x**', () => {
  const result = alignStyle('This is _em_ and __strong__ text.', {
    emphasis: '*',
    strong: '**',
  });
  assert.strictEqual(result.text, 'This is *em* and **strong** text.');
  assert.strictEqual(result.changed, 1);
});

// --- alignStyle: never touches ---

test('alignStyle never touches inline code, fenced code, indented code, an html block, front matter, snake_case words or URLs', () => {
  const text = [
    '---',
    'title: _kept_',
    '---',
    '',
    'Use `snake_case_var` and see http://example.com/a_b_c for _real_ text.',
    '',
    '```js',
    'let snake_case = _not_touched_;',
    '```',
    '',
    '    indented_code _stays_',
    '',
    '<div>_html_ stays</div>',
    '',
    'snake_case_word alone.',
  ].join('\n');
  const result = alignStyle(text, { emphasis: '*' });
  assert.strictEqual(
    result.text,
    [
      '---',
      'title: _kept_',
      '---',
      '',
      'Use `snake_case_var` and see http://example.com/a_b_c for *real* text.',
      '',
      '```js',
      'let snake_case = _not_touched_;',
      '```',
      '',
      '    indented_code _stays_',
      '',
      '<div>_html_ stays</div>',
      '',
      'snake_case_word alone.',
    ].join('\n'),
  );
  // Only the one real prose emphasis changed; every guarded occurrence of "_"
  // above (front matter, code span, URL, fence, indented code, html, snake_case) stayed.
  assert.strictEqual(result.changed, 1);
});

// --- alignStyle: structural preservation ---

test('alignStyle keeps blank lines and paragraph breaks', () => {
  const result = alignStyle('* a\n\n* b\n', { bullet: '-' });
  assert.strictEqual(result.text, '- a\n\n- b\n');
  assert.strictEqual(result.changed, 2);
});

test('alignStyle pads a table via reflowTable in distribute mode', () => {
  const result = alignStyle('| a | bb |\n| --- | --- |\n| c | d |\n', {
    table: 'distribute',
  });
  assert.strictEqual(
    result.text,
    '| a   | bb  |\n| --- | --- |\n| c   | d   |\n',
  );
  assert.strictEqual(result.changed, 2);
});

// --- alignStyle: verification drops unsafe rewrites ---

test('a rewrite that would change structure (a bullet swap that merges two separate lists) is dropped', () => {
  const text = '- a\n* b\n';
  const result = alignStyle(text, { bullet: '-' });
  assert.strictEqual(result.text, text);
  assert.strictEqual(result.changed, 0);
});

test('a rewrite touching a "*" that sits inside a link URL is dropped, since it would change the href', () => {
  const text = 'See [text](http://a.com/*mid*end) for details.';
  const result = alignStyle(text, { emphasis: '_' });
  assert.strictEqual(result.text, text);
  assert.strictEqual(result.changed, 0);
});

test('(counter-check) alignStyle returns changed 0 and the input unchanged when nothing applies', () => {
  const text = 'plain text, no markers here.';
  const result = alignStyle(text, { bullet: '-', emphasis: '*', strong: '**' });
  assert.strictEqual(result.text, text);
  assert.strictEqual(result.changed, 0);
});

// --- fallback per block ---

test('a bad block keeps its old text while the other blocks are aligned', () => {
  const text = '_a_ and _b_\n\n- one\n* two\n\n_c_\n';
  const r = alignStyle(text, {
    bullet: '-',
    emphasis: '*',
    strong: null,
    table: null,
  });
  // The bullet swap would merge two lists and is dropped; the emphasis swaps stay.
  assert.strictEqual(r.text, '*a* and *b*\n\n- one\n* two\n\n*c*\n');
});

test('the fallback stays linear: a large candidate with many bad blocks finishes fast', () => {
  const parts = [];
  for (let p = 0; p < 40; p++) {
    parts.push(`- pair ${p} first`, `* pair ${p} second`);
    for (let f = 0; f < 20; f++) parts.push(`Filler ${p}-${f} _x_ prose.`);
  }
  const t = Date.now();
  const r = alignStyle(`${parts.join('\n')}\n`, {
    bullet: '-',
    emphasis: '*',
    strong: null,
    table: null,
  });
  assert.ok(Date.now() - t < 3000, `took ${Date.now() - t} ms`);
  assert.ok(r.changed > 0 && !r.text.includes('_x_'));
});

test('code spans and inline HTML are masked in linear time', () => {
  const t = Date.now();
  alignStyle(`${'`'.repeat(20000)} _a_ ${'<'.repeat(20000)}\n`, {
    bullet: null,
    emphasis: '*',
    strong: null,
    table: null,
  });
  assert.ok(Date.now() - t < 1000, `took ${Date.now() - t} ms`);
});
