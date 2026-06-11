// Rendering pipeline: task list plugin, table cell checkboxes, line number
// injection, frontmatter card, fence rendering fallback.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh } = require('./helpers/vscode-mock');

install();
const { md } = loadFresh('src/render.js')._internal;
const { CHECKBOX_RE } = loadFresh('src/views.js')._internal;

test('list task items become task rows with checkbox and data-line', () => {
  const html = md.render('- [ ] open\n- [x] done\n');
  assert.match(html, /task-row/);
  assert.match(html, /data-line="0"/);
  assert.match(html, /data-line="1"/);
  assert.match(html, /checked/);
});

test('all CHECKBOX_RE marker variants match', () => {
  for (const line of ['- [ ] a', '* [x] b', '+ [X] c', '1. [ ] d', '2) [x] e', '  - [ ] nested']) {
    assert.ok(CHECKBOX_RE.test(line), line);
  }
});

test('CHECKBOX_RE rejects non-task lines', () => {
  for (const line of ['[ ] no marker', '- [y] bad state', '-[ ] no gap', 'text - [ ] inline']) {
    assert.ok(!CHECKBOX_RE.test(line), line);
  }
});

test('table cells render checkboxes with row line and occurrence index', () => {
  const html = md.render('| App | Win | Srv |\n|---|---|---|\n| git | [x] | [ ] |\n| zip | [ ] | [ ] |\n');
  assert.match(html, /checked data-line="2" data-idx="0"/);
  assert.match(html, /data-line="2" data-idx="1"/);
  assert.match(html, /data-line="3" data-idx="0"/);
  assert.match(html, /data-line="3" data-idx="1"/);
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

test('frontmatter renders as property card for flat key/value', () => {
  const html = md.render('---\ntitle: X\ncount: 3\n---\n\nbody\n');
  assert.match(html, /frontmatter/);
  assert.match(html, /title/);
  assert.ok(!html.includes('<hr'), 'frontmatter must not leak as thematic break');
});
