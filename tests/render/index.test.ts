// Rendering pipeline: task list plugin, table cell checkboxes, line number
// injection, frontmatter card, fence rendering fallback.
import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh } from '../helpers/vscode-mock.ts';

/** The render pipeline module. */
type RenderModule = typeof import('../../src/render/index.ts');
/** The view machinery module. */
type ViewsModule = typeof import('../../src/views/index.ts');

install();
const { md } = (await loadFresh<RenderModule>('src/render/index.ts'))._internal;
// The sort button every header cell carries (DECISIONS.md #49), first column.
const SORT_BUTTON =
  '<button type="button" class="mw-sort codicon codicon-sort-precedence" data-col="0"' +
  ' title="Sort by this column" aria-label="Sort by this column"></button>';
const { CHECKBOX_RE } = (await loadFresh<ViewsModule>('src/views/index.ts'))
  ._internal;

test('list task items become task rows with checkbox and data-line', () => {
  const html = md.render('- [ ] open\n- [x] done\n');
  assert.match(html, /task-row/);
  assert.match(html, /data-line="0"/);
  assert.match(html, /data-line="1"/);
  assert.match(html, /checked/);
});

test('empty task items render as task rows in ul, ol and compound form', () => {
  for (const src of ['- [ ]\n', '8. [ ]\n', '1. - [ ]\n']) {
    const html = md.render(src);
    assert.match(html, /task-row/, src);
    assert.match(html, /<span class="task-label"><\/span>/, src);
  }
});

test('a compound task item renders as a task row inside the ordered item', () => {
  const html = md.render('1. - [ ] foo\n');
  assert.match(
    html,
    /<ol[^>]*>[\s\S]*<ul[^>]*>[\s\S]*class="task"[\s\S]*task-row/,
  );
});

test('markup of a labeled numbered task is unchanged (number visibility is CSS-only)', () => {
  assert.strictEqual(
    md.render('1. [x] done\n'),
    '<ol data-line="0">\n' +
      '<li class="task done" data-checked="true" data-line="0">' +
      '<span class="task-row"><input type="checkbox" checked tabindex="-1">' +
      '<span class="task-label">done</span></span></li>\n' +
      '</ol>\n',
  );
});

test('task items in ordered lists become task rows too', () => {
  const html = md.render('1. [ ] open\n2. [x] done\n');
  assert.match(html, /<ol[^>]*>/);
  assert.match(html, /task-row/);
  assert.match(html, /data-checked="true"/);
});

test('nested ordered lists render as nested ol elements (outline look is CSS-only)', () => {
  // Each level restarts at 1 in the source; the letter/roman markers of
  // levels 2 and 3 come from webview.css, never from the markup.
  const html = md.render('1. a\n   1. b\n      1. c\n');
  assert.match(html, /<ol[^>]*>[\s\S]*<ol[^>]*>[\s\S]*<ol[^>]*>/);
  assert.ok(!html.includes(' type='), 'no marker type in the markup');
});

test('an ol inside a ul inside an ol nests as elements, not text', () => {
  const html = md.render('1. top\n   - bullet\n     1. inner\n');
  assert.match(html, /<ol[^>]*>[\s\S]*<ul[^>]*>[\s\S]*<ol[^>]*>/);
});

// --- custom marker preview rendering (opt-in) ---

const EXTRA_ENV = {
  markdownWorkbench: {
    renderExtraMarkers: true,
    extraMarkers: ['a)', 'A)', '->', 'a.'],
  },
};

test('renderExtraMarkers turns a custom lettered run into an ordered list', () => {
  const html = md.render('a) one\nb) two\nc) three\n', EXTRA_ENV);
  assert.match(html, /<ol[^>]*data-line="0"/);
  assert.match(html, /<li[^>]*>one<\/li>/);
  assert.match(html, /<li[^>]*>three<\/li>/);
  assert.ok(
    !/a\)/.test(html),
    'the source marker is dropped, the visual marker is CSS',
  );
});

test('renderExtraMarkers renders a symbol run as a bullet list', () => {
  const html = md.render('-> alpha\n-> beta\n', EXTRA_ENV);
  assert.match(html, /<ul[^>]*>[\s\S]*<li[^>]*>alpha<\/li>/);
});

test('renderExtraMarkers nests deeper custom markers as a child list', () => {
  const html = md.render(
    'a) one\n   a. sub a\n   a. sub b\nb) two\n',
    EXTRA_ENV,
  );
  assert.match(
    html,
    /<ol[^>]*>[\s\S]*<li[^>]*>one[\s\S]*<ol[^>]*>[\s\S]*<li[^>]*>sub a<\/li>/,
  );
});

test('custom markers stay plain text when renderExtraMarkers is off', () => {
  const html = md.render('a) one\nb) two\n');
  assert.match(html, /<p[^>]*>a\) one\nb\) two<\/p>/);
  assert.ok(!html.includes('<ol'));
});

test('custom markers stay plain text when extraMarkers is empty', () => {
  const html = md.render('a) one\nb) two\n', {
    markdownWorkbench: { renderExtraMarkers: true, extraMarkers: [] },
  });
  assert.ok(!html.includes('<ol'));
  assert.match(html, /a\) one/);
});

test('all CHECKBOX_RE marker variants match', () => {
  for (const line of [
    '- [ ] a',
    '* [x] b',
    '+ [X] c',
    '1. [ ] d',
    '2) [x] e',
    '  - [ ] nested',
  ]) {
    assert.ok(CHECKBOX_RE.test(line), line);
  }
});

test('CHECKBOX_RE rejects non-task lines', () => {
  for (const line of [
    '[ ] no marker',
    '- [y] bad state',
    '-[ ] no gap',
    'text - [ ] inline',
  ]) {
    assert.ok(!CHECKBOX_RE.test(line), line);
  }
});

test('CHECKBOX_RE matches compound markers, nested and with empty labels', () => {
  for (const line of [
    '1. - [ ] a',
    '1) - [x] b',
    '- 1. [ ] c',
    '- - [X] d',
    '   2. - [ ] nested',
    '1. - [ ]',
    '8. [ ]',
    '- [ ]',
  ]) {
    assert.ok(CHECKBOX_RE.test(line), line);
  }
});

test('CHECKBOX_RE rejects malformed compound lines', () => {
  for (const line of [
    '1. -[ ] no gap',
    '1. - [y] bad state',
    'a. - [ ] letter marker',
  ]) {
    assert.ok(!CHECKBOX_RE.test(line), line);
  }
});

test('table cells render checkboxes with row line and occurrence index', () => {
  const html = md.render(
    '| App | Win | Srv |\n|---|---|---|\n| git | [x] | [ ] |\n| zip | [ ] | [ ] |\n',
  );
  assert.match(html, /checked data-line="2" data-idx="0"/);
  assert.match(html, /data-line="2" data-idx="1"/);
  assert.match(html, /data-line="3" data-idx="0"/);
  assert.match(html, /data-line="3" data-idx="1"/);
});

test('tables render inside a breakout wrapper, data-line stays on the table', () => {
  const html = md.render('| a |\n|---|\n| 1 |\n');
  assert.strictEqual(
    html,
    '<div class="table-wrap"><table data-line="0">\n' +
      '<thead data-line="0">\n<tr data-line="0">\n' +
      `<th>${SORT_BUTTON}a</th>\n</tr>\n</thead>\n` +
      '<tbody data-line="2">\n<tr data-line="2">\n<td>1</td>\n</tr>\n</tbody>\n' +
      '</table>\n</div>\n',
  );
});

test('the table wrapper itself carries no data-line', () => {
  const html = md.render('| a |\n|---|\n| 1 |\n');
  assert.ok(!/<div class="table-wrap"[^>]*data-line/.test(html));
});

test('cell checkboxes keep line and index inside the wrapped table', () => {
  const html = md.render('| a |\n|---|\n| [x] |\n');
  assert.strictEqual(
    html,
    '<div class="table-wrap"><table data-line="0">\n' +
      '<thead data-line="0">\n<tr data-line="0">\n' +
      `<th>${SORT_BUTTON}a</th>\n</tr>\n</thead>\n` +
      '<tbody data-line="2">\n<tr data-line="2">\n' +
      '<td><input type="checkbox" class="cell-task" checked data-line="2" data-idx="0" tabindex="-1"></td>\n' +
      '</tr>\n</tbody>\n</table>\n</div>\n',
  );
});

test('tables nested in list items are wrapped too', () => {
  const html = md.render('- item\n\n  | a |\n  |---|\n  | 1 |\n');
  assert.match(
    html,
    /<li[^>]*data-line="0"[^>]*>\n<p[^>]*>item<\/p>\n<div class="table-wrap"><table data-line="2">/,
  );
  assert.match(html, /<\/table>\n<\/div>\n<\/li>/);
});

test('header row cells are not converted', () => {
  const html = md.render('| [ ] | b |\n|---|---|\n| x | y |\n');
  assert.ok(!/th[^>]*>[\s\S]*?cell-task[\s\S]*?<\/th>/.test(html));
});

test('code spans inside cells are not converted', () => {
  const html = md.render('| a |\n|---|\n| `[ ]` |\n');
  assert.match(html, /<code>\[ \]<\/code>/);
  assert.ok(!html.includes('cell-task'));
});

test('multiple checkboxes in one cell get sequential indices', () => {
  const html = md.render('| a |\n|---|\n| [ ] x [x] |\n');
  assert.match(html, /data-idx="0"/);
  assert.match(html, /data-idx="1"/);
});

test('block elements carry data-line from token maps', () => {
  const html = md.render('# H\n\npara\n\n- item\n');
  assert.match(html, /<h1[^>]*data-line="0"/);
  assert.match(html, /<p[^>]*data-line="2"/);
});

test('fences render with data-line and data-line-end', () => {
  const html = md.render('```js\na\nb\n```\n');
  assert.match(html, /data-line="0"/);
  assert.match(html, /data-line-end="3"/);
});

// --- heading anchors (GitHub-compatible slugs, docs/DECISIONS.md #31) ---

test('a simple heading gets a lowercase hyphenated id', () => {
  assert.match(md.render('# Hello World\n'), /<h1[^>]*id="hello-world"/);
});

test('uppercase is lowered and unicode letters are kept', () => {
  // "Cafe Resume" with accented letters (\u00e9 = e-acute); the test source
  // stays ASCII via escapes but exercises the Unicode-letter path.
  assert.match(
    md.render('# Caf\u00e9 R\u00e9sum\u00e9\n'),
    /<h1[^>]*id="caf\u00e9-r\u00e9sum\u00e9"/,
  );
});

test('punctuation is stripped, spaces become hyphens', () => {
  assert.match(md.render('## What: is 3.14?\n'), /<h2[^>]*id="what-is-314"/);
});

test('inline code in a heading contributes its text to the slug', () => {
  assert.match(
    md.render('## Use `npm run` now\n'),
    /<h2[^>]*id="use-npm-run-now"/,
  );
});

test('markup delimiters and link syntax do not contribute to the slug', () => {
  assert.match(
    md.render('## **Bold** and [link](https://x)\n'),
    /<h2[^>]*id="bold-and-link"/,
  );
});

test('linkify turns bare www links and scheme links into anchors', () => {
  const html = md.render('see www.example.com and https://example.org\n');
  assert.match(
    html,
    /<a href="http:\/\/www\.example\.com">www\.example\.com<\/a>/,
  );
  assert.match(
    html,
    /<a href="https:\/\/example\.org">https:\/\/example\.org<\/a>/,
  );
});

test('three identical headings get x, x-1, x-2', () => {
  const html = md.render('# x\n# x\n# x\n');
  const ids = [...html.matchAll(/<h1[^>]*id="([^"]*)"/g)].map((m) => m[1]);
  assert.deepStrictEqual(ids, ['x', 'x-1', 'x-2']);
});

test('the duplicate counter resets between renders (no state leak)', () => {
  assert.match(md.render('# x\n'), /id="x"/);
  const second = md.render('# x\n');
  assert.match(second, /id="x"/);
  assert.ok(
    !second.includes('id="x-1"'),
    'a fresh render must not carry the previous suffix',
  );
});

test('numeric symbols github-slugger strips (superscripts, fractions) are dropped', () => {
  // \p{No} is NOT kept (would be, with the broad \p{N}); matches github-slugger.
  assert.match(md.render('# Area in m\u00b2\n'), /<h1[^>]*id="area-in-m"/); // m^2 (U+00B2)
  assert.match(md.render('# Half \u00bd done\n'), /<h1[^>]*id="half--done"/); // 1/2 (U+00BD)
  // decimal digits (\p{Nd}) are kept
  assert.match(md.render('# Chapter 2\n'), /<h1[^>]*id="chapter-2"/);
});

test('empty and markup-only headings produce an empty id (github-slugger-faithful)', () => {
  assert.match(md.render('#\n'), /<h1[^>]*id=""/); // empty heading
  assert.match(md.render('# ![alt](x.png)\n'), /<h1[^>]*id=""/); // image alt does not contribute
  // duplicate empty headings dedupe like any slug: "" then "-1"
  const ids = [
    ...md.render('#\n##\n').matchAll(/<h[12][^>]*id="([^"]*)"/g),
  ].map((m) => m[1]);
  assert.deepStrictEqual(ids, ['', '-1']);
});

test('a literal heading equal to a would-be dedup suffix is not reused', () => {
  // The second "x" must skip the already-taken literal "x-1" and land on "x-2".
  const ids = [
    ...md.render('# x-1\n# x\n# x\n').matchAll(/<h1[^>]*id="([^"]*)"/g),
  ].map((m) => m[1]);
  assert.deepStrictEqual(ids, ['x-1', 'x', 'x-2']);
});

test('frontmatter renders as property card for flat key/value', () => {
  const html = md.render('---\ntitle: X\ncount: 3\n---\n\nbody\n');
  assert.match(html, /frontmatter/);
  assert.match(html, /title/);
  assert.ok(
    !html.includes('<hr'),
    'frontmatter must not leak as thematic break',
  );
});

test('flat frontmatter renders one key cell and one value cell per line, escaped', () => {
  assert.strictEqual(
    md.render('---\ntitle: X\ncount: 3\n---\n'),
    '<div class="frontmatter" data-line="0">' +
      '<div class="fm-key">title</div><div class="fm-val">X</div>' +
      '<div class="fm-key">count</div><div class="fm-val">3</div></div>\n',
  );
  assert.match(
    md.render('---\nname: <b>&\n---\n'),
    /<div class="fm-key">name<\/div><div class="fm-val">&lt;b&gt;&amp;<\/div>/,
  );
});

test('frontmatter that is not flat key/value falls back to an escaped monospace block', () => {
  assert.strictEqual(
    md.render('---\ntitle: X\ntags:\n  - <a>\n  - b\n---\n'),
    '<div class="frontmatter fm-raw" data-line="0">' +
      '<pre>title: X\ntags:\n  - &lt;a&gt;\n  - b</pre></div>\n',
  );
});

test('the render plugins sit in the core rule chain in their fixed order', () => {
  const chain = md.core.ruler.__rules__.map((r) => r.name);
  const ours = [
    'extra-marker-lists', // before inline: its lists are parsed inline like any other
    'inline',
    'table-checkboxes', // after inline: reads the inline children
    'task-lists',
    'heading-anchors',
    'inject_lines', // last: every token, generated ones included, gets its data-line
  ];
  assert.deepStrictEqual(
    chain.filter((name) => ours.includes(name)),
    ours,
  );
  assert.strictEqual(chain.at(-1), 'inject_lines');
  const blocks = md.block.ruler.__rules__.map((r) => r.name);
  assert.strictEqual(blocks[0], 'front_matter', 'ahead of hr and setext rules');
});

test('shiki code blocks keep token colors but not the theme background', async () => {
  // The preview's --code-bg (webview.css) paints the block; shiki's inline
  // background-color would override the stylesheet.
  const render = await loadFresh<RenderModule>('src/render/index.ts');
  await render.initHighlighter();
  const html = render.md.render('```js\nconst a = 1;\n```\n');
  const preTag = html.match(/<pre[^>]*>/);
  assert.ok(preTag, 'a pre element');
  const pre = preTag[0];
  assert.match(pre, /class="shiki/, 'highlighted by shiki');
  assert.doesNotMatch(pre, /background/, 'no inline theme background');
  assert.match(pre, /style="[^"]*color:/, 'the theme foreground stays');
  assert.match(html, /<span style="color:/, 'tokens keep their colors');
});

test('header cells carry a sort button with their column index; body cells none (REQ-045)', () => {
  const html = md.render('| a | b |\n|:-:|---|\n| 1 | 2 |');
  const cols = [
    ...html.matchAll(
      /<th[^>]*><button[^>]*class="mw-sort[^"]*" data-col="(\d)"/g,
    ),
  ].map((m) => m[1]);
  assert.deepStrictEqual(cols, ['0', '1']);
  assert.match(
    html,
    /<th style="text-align:center"><button/,
    'alignment attribute kept',
  );
  assert.doesNotMatch(html, /<td[^>]*><button/);
});

test('before shiki is ready a fence renders as escaped plain code with its language class', async () => {
  const render = await loadFresh<RenderModule>('src/render/index.ts');
  const html = render.md.render('```js\nif (a < b && c) {}\n```\n');
  assert.strictEqual(
    html,
    '<pre data-line="0" data-line-end="2"><code class="language-js">' +
      'if (a &lt; b &amp;&amp; c) {}\n</code></pre>\n',
  );
});

test('the highlighter start re-renders every open view once', async () => {
  const render = await loadFresh<RenderModule>('src/render/index.ts');
  let posts = 0;
  render.activePosts.add(() => {
    posts++;
  });
  await render.initHighlighter();
  assert.strictEqual(posts, 1);
});
