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

test('empty task items render as task rows in ul, ol and compound form', () => {
  for (const src of ['- [ ]\n', '8. [ ]\n', '1. - [ ]\n']) {
    const html = md.render(src);
    assert.match(html, /task-row/, src);
    assert.match(html, /<span class="task-label"><\/span>/, src);
  }
});

test('a compound task item renders as a task row inside the ordered item', () => {
  const html = md.render('1. - [ ] foo\n');
  assert.match(html, /<ol[^>]*>[\s\S]*<ul[^>]*>[\s\S]*class="task"[\s\S]*task-row/);
});

test('markup of a labeled numbered task is unchanged (number visibility is CSS-only)', () => {
  assert.strictEqual(md.render('1. [x] done\n'),
    '<ol data-line="0">\n'
    + '<li class="task done" data-checked="true" data-line="0">'
    + '<span class="task-row"><input type="checkbox" checked tabindex="-1">'
    + '<span class="task-label">done</span></span></li>\n'
    + '</ol>\n');
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

const EXTRA_ENV = { markdownWorkbench: { renderExtraMarkers: true, extraMarkers: ['a)', 'A)', '->', 'a.'] } };

test('renderExtraMarkers turns a custom lettered run into an ordered list', () => {
  const html = md.render('a) one\nb) two\nc) three\n', EXTRA_ENV);
  assert.match(html, /<ol[^>]*data-line="0"/);
  assert.match(html, /<li[^>]*>one<\/li>/);
  assert.match(html, /<li[^>]*>three<\/li>/);
  assert.ok(!/a\)/.test(html), 'the source marker is dropped, the visual marker is CSS');
});

test('renderExtraMarkers renders a symbol run as a bullet list', () => {
  const html = md.render('-> alpha\n-> beta\n', EXTRA_ENV);
  assert.match(html, /<ul[^>]*>[\s\S]*<li[^>]*>alpha<\/li>/);
});

test('renderExtraMarkers nests deeper custom markers as a child list', () => {
  const html = md.render('a) one\n   a. sub a\n   a. sub b\nb) two\n', EXTRA_ENV);
  assert.match(html, /<ol[^>]*>[\s\S]*<li[^>]*>one[\s\S]*<ol[^>]*>[\s\S]*<li[^>]*>sub a<\/li>/);
});

test('custom markers stay plain text when renderExtraMarkers is off', () => {
  const html = md.render('a) one\nb) two\n');
  assert.match(html, /<p[^>]*>a\) one\nb\) two<\/p>/);
  assert.ok(!html.includes('<ol'));
});

test('custom markers stay plain text when extraMarkers is empty', () => {
  const html = md.render('a) one\nb) two\n', { markdownWorkbench: { renderExtraMarkers: true, extraMarkers: [] } });
  assert.ok(!html.includes('<ol'));
  assert.match(html, /a\) one/);
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

test('CHECKBOX_RE matches compound markers, nested and with empty labels', () => {
  for (const line of ['1. - [ ] a', '1) - [x] b', '- 1. [ ] c', '- - [X] d',
                      '   2. - [ ] nested', '1. - [ ]', '8. [ ]', '- [ ]']) {
    assert.ok(CHECKBOX_RE.test(line), line);
  }
});

test('CHECKBOX_RE rejects malformed compound lines', () => {
  for (const line of ['1. -[ ] no gap', '1. - [y] bad state', 'a. - [ ] letter marker']) {
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

test('tables render inside a breakout wrapper, data-line stays on the table', () => {
  const html = md.render('| a |\n|---|\n| 1 |\n');
  assert.strictEqual(html,
    '<div class="table-wrap"><table data-line="0">\n'
    + '<thead data-line="0">\n<tr data-line="0">\n<th>a</th>\n</tr>\n</thead>\n'
    + '<tbody data-line="2">\n<tr data-line="2">\n<td>1</td>\n</tr>\n</tbody>\n'
    + '</table>\n</div>\n');
});

test('the table wrapper itself carries no data-line', () => {
  const html = md.render('| a |\n|---|\n| 1 |\n');
  assert.ok(!/<div class="table-wrap"[^>]*data-line/.test(html));
});

test('cell checkboxes keep line and index inside the wrapped table', () => {
  const html = md.render('| a |\n|---|\n| [x] |\n');
  assert.strictEqual(html,
    '<div class="table-wrap"><table data-line="0">\n'
    + '<thead data-line="0">\n<tr data-line="0">\n<th>a</th>\n</tr>\n</thead>\n'
    + '<tbody data-line="2">\n<tr data-line="2">\n'
    + '<td><input type="checkbox" class="cell-task" checked data-line="2" data-idx="0" tabindex="-1"></td>\n'
    + '</tr>\n</tbody>\n</table>\n</div>\n');
});

test('tables nested in list items are wrapped too', () => {
  const html = md.render('- item\n\n  | a |\n  |---|\n  | 1 |\n');
  assert.match(html, /<li[^>]*data-line="0"[^>]*>\n<p[^>]*>item<\/p>\n<div class="table-wrap"><table data-line="2">/);
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

test('frontmatter renders as property card for flat key/value', () => {
  const html = md.render('---\ntitle: X\ncount: 3\n---\n\nbody\n');
  assert.match(html, /frontmatter/);
  assert.match(html, /title/);
  assert.ok(!html.includes('<hr'), 'frontmatter must not leak as thematic break');
});
