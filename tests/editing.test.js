// Editor authoring features: list continuation, fence auto-close, nesting,
// wrap toggles, table reflow, sorting, fence language completion.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh, MockDocument, MockEditor, Selection } = require('./helpers/vscode-mock');

const vscode = install();
const editing = loadFresh('src/editing.js');
const { reflowTable, splitRow, LIST_ITEM_RE, _internal } = editing;
const { FENCE_RE, fenceIsUnclosed, isSeparatorRow, indentUnitFor, escapeSnippet,
        numericMarker, contentColumn, enclosingListItem, onEnterKey, onShiftEnterKey,
        onTabKey, onShiftTabKey, sortSelection, toggleWrap } = _internal;

function editorOn(text, line, character, endLine, endCharacter) {
  const doc = new MockDocument(text);
  const sel = endLine === undefined
    ? new Selection(line, character, line, character)
    : new Selection(line, character, endLine, endCharacter);
  const editor = new MockEditor(doc, sel);
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}

// --- regexes and pure helpers ---

test('LIST_ITEM_RE captures indent, bullet, gap and checkbox', () => {
  const m = LIST_ITEM_RE.exec('  - [x] text');
  assert.strictEqual(m[1], '  ');
  assert.strictEqual(m[2], '-');
  assert.strictEqual(m[4], '[x] ');
  assert.strictEqual(m[5], 'text');
});

test('FENCE_RE matches backtick and tilde fences with language info', () => {
  assert.ok(FENCE_RE.test('```'));
  assert.ok(FENCE_RE.test('  ~~~~powershell'));
  assert.ok(!FENCE_RE.test('``inline``'));
});

test('fenceIsUnclosed pairs later delimiters', () => {
  const open = new MockDocument('```js\ncode');
  assert.strictEqual(fenceIsUnclosed(open, 0), true);
  const closed = new MockDocument('```js\ncode\n```');
  assert.strictEqual(fenceIsUnclosed(closed, 0), false);
});

test('isSeparatorRow accepts alignment colons', () => {
  assert.ok(isSeparatorRow([':---', '---:', ':-:']));
  assert.ok(!isSeparatorRow(['a', '---']));
});

test('indentUnitFor is marker plus gap width', () => {
  assert.strictEqual(indentUnitFor(LIST_ITEM_RE.exec('- x')).length, 2);
  assert.strictEqual(indentUnitFor(LIST_ITEM_RE.exec('10. x')).length, 4);
});

test('escapeSnippet escapes snippet metacharacters', () => {
  assert.strictEqual(escapeSnippet('a$b}c\\d'), 'a\\$b\\}c\\\\d');
});

// --- Enter ---

test('Enter continues a bullet task item with a fresh checkbox', async () => {
  const editor = editorOn('- [x] done', 0, 10);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '- [ ] ');
});

test('Enter increments numbered items', async () => {
  const editor = editorOn('3. item', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '4. ');
});

test('numericMarker accepts only digit markers with . or )', () => {
  assert.deepStrictEqual(numericMarker('3.'), { n: 3, delim: '.' });
  assert.deepStrictEqual(numericMarker('12)'), { n: 12, delim: ')' });
  assert.strictEqual(numericMarker('-'), null);
  assert.strictEqual(numericMarker('a.'), null);
});

test('Enter keeps the paren delimiter', async () => {
  const editor = editorOn('3) item', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '4) ');
});

test('Enter continues a numbered task item with a fresh checkbox', async () => {
  const editor = editorOn('1. [x] done', 0, 11);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '2. [ ] ');
});

test('Enter increments into two digits', async () => {
  const editor = editorOn('9. nine', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '10. ');
});

test('Enter on an empty numbered item removes the marker', async () => {
  const editor = editorOn('1. ', 0, 3);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[0], '');
});

test('Enter mid-sequence renumbers the following siblings', async () => {
  const editor = editorOn('1. a\n2. b\n3. c', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '2. ', '3. b', '4. c']);
});

test('Enter renumbering skips children and stops at a type change', async () => {
  const editor = editorOn('1. a\n   1. aa\n2. b\n- dash', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '2. ', '   1. aa', '3. b', '- dash']);
});

test('Enter continues a compound task item with a fresh box', async () => {
  const editor = editorOn('1. - [ ] asd', 0, 12);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '2. - [ ] ');
});

test('Enter keeps the paren delimiter on a compound task item', async () => {
  const editor = editorOn('1) - [x] asd', 0, 12);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '2) - [ ] ');
});

test('Enter on a dash-led compound never increments the inner number', async () => {
  const editor = editorOn('- 1. [ ] x', 0, 10);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '- 1. [ ] ');
});

test('Enter on an empty compound item removes the whole marker', async () => {
  const editor = editorOn('2. - [ ] ', 0, 9);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[0], '');
});

test('Enter mid-sequence renumbers across compound siblings', async () => {
  const editor = editorOn('1. - [ ] a\n2. - [ ] b', 0, 10);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. - [ ] a', '2. - [ ] ', '3. - [ ] b']);
});

test('Tab on a compound item touches only the leading marker', async () => {
  const editor = editorOn('1. - [ ] a\n2. - [ ] b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. - [ ] a', '   1. - [ ] b']);
});

test('Shift+Tab on a compound item touches only the leading marker', async () => {
  const editor = editorOn('1. - [ ] a\n   1. - [ ] b', 1, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. - [ ] a', '2. - [ ] b']);
});

test('Enter renumbering stops at a delimiter change', async () => {
  const editor = editorOn('1. a\n1) other', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '2. ', '1) other']);
});

test('Enter on an empty item removes the marker (list termination)', async () => {
  const editor = editorOn('- [ ] ', 0, 6);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[0], '');
});

test('Enter inside the marker falls back to default newline', async () => {
  editorOn('- [ ] text', 0, 2);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

test('Enter on a non-list line falls back', async () => {
  editorOn('plain', 0, 5);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

test('Enter at the end of an unclosed fence inserts the closing fence as an unindented snippet', async () => {
  const editor = editorOn('```js', 0, 5);
  await onEnterKey();
  assert.strictEqual(editor.insertedSnippets.length, 1);
  // No indentation in the snippet: VS Code auto-indents continuation lines.
  assert.strictEqual(editor.insertedSnippets[0].snippet.value, '\n$0\n```');
});

test('Enter on an already-paired fence falls back', async () => {
  editorOn('```js\nx\n```', 0, 5);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0] && vscode._executed[0].id, 'default:type');
});

// --- Tab / Shift+Tab ---

test('Tab nests by the adaptive marker width', async () => {
  const editor = editorOn('- item', 0, 3);
  await onTabKey();
  assert.strictEqual(editor.document.lines[0], '  - item');
});

test('Tab outside lists falls back to the tab command', async () => {
  editorOn('plain', 0, 0);
  await onTabKey();
  assert.strictEqual(vscode._executed[0].id, 'tab');
});

test('Shift+Tab un-nests and stops at column zero', async () => {
  const editor = editorOn('  - item', 0, 4);
  await onShiftTabKey();
  assert.strictEqual(editor.document.lines[0], '- item');
  await onShiftTabKey(); // already at zero indent -> outdent fallback
  assert.strictEqual(vscode._executed.at(-1).id, 'outdent');
});

test('Tab restarts a numbered item as a new sublist at 1', async () => {
  const editor = editorOn('1. a\n2. b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '   1. b']);
});

test('Tab keeps the paren delimiter on the restarted number', async () => {
  const editor = editorOn('1) a\n2) b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1) a', '   1) b']);
});

test('Tab closes the gap in the sequence left behind', async () => {
  const editor = editorOn('1. a\n2. b\n3. c', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '   1. b', '2. c']);
});

test('Tab gap-closing skips children of the tabbed item', async () => {
  const editor = editorOn('1. a\n2. b\n   1. bb\n3. c', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '   1. b', '   1. bb', '2. c']);
});

test('Tab on a multi-line selection only reindents, numbers untouched', async () => {
  const editor = editorOn('1. a\n2. b', 0, 0, 1, 4);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['   1. a', '   2. b']);
});

test('Shift+Tab joins the target sequence and renumbers both sequences', async () => {
  const editor = editorOn('1. a\n   1. x\n   2. y\n   3. z\n2. b', 1, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '2. x', '   1. y', '   2. z', '3. b']);
});

test('Shift+Tab without a preceding target-level sibling starts at 1', async () => {
  const editor = editorOn('   3. only', 0, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. only']);
});

test('Shift+Tab leaves dash markers and sibling numbers untouched', async () => {
  // Outdent by the dash's own unit (2), marker unrewritten, no renumbering.
  const editor = editorOn('1. parent\n   - dash\n2. next', 1, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. parent', ' - dash', '2. next']);
});

test('Enter on a dash item under a numbered parent continues the dash', async () => {
  const editor = editorOn('1. parent\n   - dash', 1, 9);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[2], '   - ');
});

// --- content column / enclosing item ---

test('contentColumn measures the text column of every item shape', () => {
  assert.strictEqual(contentColumn(LIST_ITEM_RE.exec('2. ')), 3);
  assert.strictEqual(contentColumn(LIST_ITEM_RE.exec('   - [ ] ')), 9);
  assert.strictEqual(contentColumn(LIST_ITEM_RE.exec('1. - [ ] foo')), 9);
});

test('enclosingListItem returns the item directly when the line is one', () => {
  const doc = new MockDocument('2. foo');
  const item = enclosingListItem(doc, 0);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 3);
});

test('enclosingListItem walks up one continuation line', () => {
  const doc = new MockDocument('2. foo\n   cont');
  const item = enclosingListItem(doc, 1);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 3);
});

test('enclosingListItem walks up several continuation lines', () => {
  const doc = new MockDocument('2. foo\n   cont one\n   cont two');
  const item = enclosingListItem(doc, 2);
  assert.strictEqual(item.line, 0);
});

test('enclosingListItem stops at a too-shallow markerless line', () => {
  const doc = new MockDocument('2. foo\n shallow');
  assert.strictEqual(enclosingListItem(doc, 1), null);
});

test('enclosingListItem stops at a blank line', () => {
  const doc = new MockDocument('2. foo\n\n   orphan');
  assert.strictEqual(enclosingListItem(doc, 2), null);
});

// --- Shift+Enter: hanging continuation lines ---

test('Shift+Enter on a numbered item hangs at the content column', async () => {
  const editor = editorOn('2. ', 0, 3);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. ', '   ']);
});

test('Shift+Enter on a nested task item hangs at column nine', async () => {
  const editor = editorOn('   - [ ] ', 0, 9);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['   - [ ] ', '         ']);
});

test('Shift+Enter on a compound item hangs at the compound content column', async () => {
  const editor = editorOn('1. - [ ] ', 0, 9);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. - [ ] ', '         ']);
});

test('Shift+Enter splits the line, rest text moves to the hanging line', async () => {
  const editor = editorOn('2. foobar', 0, 5);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. fo', '   obar']);
});

test('Shift+Enter on a continuation line hangs at the same column, no marker', async () => {
  const editor = editorOn('2. foo\n   cont', 1, 5);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. foo', '   co', '   nt']);
});

test('Shift+Enter outside a list falls back to the default newline', async () => {
  editorOn('plain', 0, 5);
  await onShiftEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

// --- Enter on a continuation line continues the item ---

test('Enter on a continuation line opens the next numbered sibling', async () => {
  const editor = editorOn('2. foo\n   buttons rechts\n3. bar', 1, 17);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. foo', '   buttons rechts', '3. ', '4. bar']);
});

test('Enter on a continuation line of a bullet repeats the bullet', async () => {
  const editor = editorOn('- foo\n  cont', 1, 6);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['- foo', '  cont', '- ']);
});

test('renumber skips a wrapped continuation line mid-sequence', async () => {
  const editor = editorOn('1. a\n2. b\n   wrapped\n3. c', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '2. ', '3. b', '   wrapped', '4. c']);
});

test('renumber steps over a continuation across a one-/two-digit transition', async () => {
  // The continuation under 10. still hangs at column 3 (it was written under a
  // single-digit marker); the seed - the trigger item's content column - is a
  // stable floor, so the run does not break at the wider 10. marker.
  const editor = editorOn('9. i\n10. j\n   cont\n11. k', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['9. i', '10. ', '11. j', '   cont', '12. k']);
});

test('Shift+Enter with the cursor inside the marker falls back to default', async () => {
  editorOn('2. foo', 0, 1);
  await onShiftEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

// --- wrap toggles ---

test('toggleWrap wraps a selection', async () => {
  const editor = editorOn('make bold here', 0, 5, 0, 9);
  await toggleWrap('**');
  assert.strictEqual(editor.document.lines[0], 'make **bold** here');
});

test('toggleWrap unwraps an exactly wrapped selection', async () => {
  const editor = editorOn('make **bold** here', 0, 5, 0, 13);
  await toggleWrap('**');
  assert.strictEqual(editor.document.lines[0], 'make bold here');
});

test('toggleWrap unwraps when the selection sits inside the markers', async () => {
  const editor = editorOn('make **bold** here', 0, 7, 0, 11);
  await toggleWrap('**');
  assert.strictEqual(editor.document.lines[0], 'make bold here');
});

test('toggleWrap on an empty cursor over a word wraps the word', async () => {
  const editor = editorOn('make bold here', 0, 7);
  await toggleWrap('*');
  assert.strictEqual(editor.document.lines[0], 'make *bold* here');
});

// --- tables ---

test('splitRow trims pipes and cells', () => {
  assert.deepStrictEqual(splitRow('| a | b c |'), ['a', 'b c']);
  assert.deepStrictEqual(splitRow('a|b'), ['a', 'b']);
});

test('reflowTable distribute pads to column widths and keeps alignment colons', () => {
  const out = reflowTable(['| App | On |', '|:---|---:|', '| git | yes |', '| q | n |'], 'distribute');
  assert.strictEqual(out[2], '| git | yes |');
  assert.strictEqual(out[3], '| q   | n   |');
  assert.match(out[1], /^\| :-+ \| -+: \|$/);
});

test('reflowTable consolidate shrinks separators to minimum width', () => {
  const out = reflowTable(['| Long header | x |', '|---|---|', '| a | b |'], 'consolidate');
  assert.strictEqual(out[1], '| --- | --- |');
  assert.strictEqual(out[2], '| a | b |');
});

test('reflowTable pads ragged rows to the widest row', () => {
  const out = reflowTable(['| a | b |', '|---|', '| only |'], 'distribute');
  for (const line of out) assert.strictEqual((line.match(/\|/g) || []).length, 3);
});

// --- sorting ---

test('sortSelection sorts numerically aware', async () => {
  const editor = editorOn('item10\nitem2\nitem1', 0, 0, 2, 5);
  await sortSelection(false);
  assert.deepStrictEqual(editor.document.lines, ['item1', 'item2', 'item10']);
});

test('sortSelection descending reverses', async () => {
  const editor = editorOn('a\nc\nb', 0, 0, 2, 1);
  await sortSelection(true);
  assert.deepStrictEqual(editor.document.lines, ['c', 'b', 'a']);
});

test('sortSelection without selection informs instead of editing', async () => {
  editorOn('a\nb', 0, 0);
  vscode._infos = [];
  await sortSelection(false);
  assert.strictEqual(vscode._infos.length, 1);
});

// --- fence language completion ---

test('fence completion triggers after ``` and replaces a partial language', () => {
  const ctx = { subscriptions: [] };
  editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
  const provider = vscode._completionProvider;
  const doc = new MockDocument('```pow');
  const items = provider.provideCompletionItems(doc, { line: 0, character: 6 });
  assert.ok(items.some((i) => i.label === 'powershell'));
  assert.ok(items.some((i) => i.label === 'ps1'), 'verified aliases offered');
  assert.strictEqual(items[0].range.start.character, 3);
});

test('fence completion stays silent on normal text', () => {
  const provider = vscode._completionProvider;
  const doc = new MockDocument('regular text');
  assert.strictEqual(provider.provideCompletionItems(doc, { line: 0, character: 5 }), undefined);
});
