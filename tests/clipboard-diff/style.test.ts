// Markdown style alignment: derives the house style of a baseline and aligns
// a candidate to it surgically. Pure, no vscode.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  styleProfile,
  alignStyle,
  MAX_BLOCK_RETRIES,
  _internal,
} from '../../src/clipboard-diff/style.ts';

const { tableMode } = _internal;

// --- styleProfile ---

/** CPU milliseconds (user and system) this process spends in `fn`; load elsewhere does not count. */
function cpuMs(fn: () => void): number {
  const start = process.cpuUsage();
  fn();
  const used = process.cpuUsage(start);
  return (used.user + used.system) / 1000;
}

/** Median of three runs, so one run that met a garbage collection or a busy core does not decide. */
function medianCpuMs(fn: () => void): number {
  const runs = Array.from({ length: 3 }, () => cpuMs(fn)).sort((a, b) => a - b);
  return runs[1] ?? 0;
}

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

// --- tableMode: tables nested in a list item ---

const nested = (rows: string[]) =>
  ['- item', '', ...rows.map((r) => `    ${r}`)].join('\n');

test('a compact table in a list item with a 4-space indent reads as consolidate', () => {
  const text = nested(['| a | bb |', '| --- | --- |', '| c | d |']);
  assert.strictEqual(styleProfile(text).table, 'consolidate');
});

test('(counter-check) an unformatted table in a list item with a 4-space indent has no table style', () => {
  const text = nested(['| a | bb |', '|---|---|', '|c|d|']);
  assert.strictEqual(styleProfile(text).table, null);
});

test('a baseline of unformatted nested tables leaves a compact candidate table unpadded', () => {
  const baseline = [
    nested(['| a | bb |', '|---|---|', '|c|d|']),
    nested(['| x | yyyy |', '|-|-|', '|z|w|']),
  ].join('\n\n');
  const profile = styleProfile(baseline);
  const result = alignStyle('| a | bb |\n| --- | --- |\n| c | d |\n', profile);
  assert.strictEqual(result.changed, 0);
});

test('(counter-check) pipe rows without a delimiter row hold no table and get no mode', () => {
  assert.strictEqual(tableMode(['| a | b |', '| c | d |']), null);
});

test('a table that fits both modes reads as distribute (the mode order is pinned)', () => {
  const text = '| aaa | bbb |\n| --- | --- |\n| ccc | ddd |';
  assert.strictEqual(styleProfile(text).table, 'distribute');
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
  const text = `${parts.join('\n')}\n`;
  const profile = { bullet: '-', emphasis: '*', strong: null, table: null };
  // CPU time of this process, not the wall clock: other work on the machine does not count.
  // The one timed run is also the checked one; a cold run only counts against the bound.
  let r = { changed: 0, text };
  const cpu = cpuMs(() => {
    r = alignStyle(text, profile);
  });
  assert.ok(cpu < 3000, `took ${cpu.toFixed(0)} ms of CPU`);
  assert.ok(r.changed > 0 && !r.text.includes('_x_'));
});

test('a block tries at most MAX_BLOCK_RETRIES lines one by one', () => {
  const good = Array.from(
    { length: MAX_BLOCK_RETRIES + 10 },
    (_, i) => `line ${i} _x_`,
  );
  // The last line's swap changes the structure, so the block as a whole fails.
  const text = `${[...good, 'a *b _c* d_'].join('\n')}\n`;
  const r = alignStyle(text, {
    bullet: null,
    emphasis: '*',
    strong: null,
    table: null,
  });
  assert.strictEqual(r.changed, MAX_BLOCK_RETRIES);
  assert.ok(
    r.text.includes(`line ${MAX_BLOCK_RETRIES} _x_`),
    'lines past the cap stay as they were',
  );
});

test('the fallback stays linear on a long list of alternating bullets', () => {
  const build = (n: number) =>
    `${Array.from({ length: n }, (_, i) => `${i % 2 ? '*' : '-'} item ${i}`).join('\n')}\n`;
  const time = (n: number) => {
    const text = build(n);
    return medianCpuMs(() =>
      alignStyle(text, {
        bullet: '-',
        emphasis: null,
        strong: null,
        table: null,
      }),
    );
  };
  time(500); // warm-up
  const small = time(1000);
  const large = time(4000);
  // Four times the lines: about four times the work when linear, sixteen when quadratic.
  assert.ok(
    large < small * 8,
    `1000 lines ${small.toFixed(0)} ms, 4000 lines ${large.toFixed(0)} ms of CPU`,
  );
});
