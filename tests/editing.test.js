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
        onTabKey, onShiftTabKey, smartDeleteWordRight, sortSelection, toggleWrap,
        execListItem, advanceMarker, nextLetterSeq, propagateMarkerType } = _internal;

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

test('Tab into a populated deeper level joins its sequence instead of duplicating', async () => {
  // zwei 1 already sits one level deeper; tabbing zwei 2 in must continue the
  // sequence (-> 2.), not restart at 1 and leave a `1.`/`1.` pair. The level
  // left behind closes its gap.
  const editor = editorOn('1. eins\n2. zwei\n      1. zwei 1\n   1. zwei 2\n   2. zwei 3', 3, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines,
    ['1. eins', '2. zwei', '      1. zwei 1', '      2. zwei 2', '   1. zwei 3']);
});

test('Tab joining a deeper sequence counts past nine into two digits', async () => {
  const nine = Array.from({ length: 9 }, (_, i) => '      ' + (i + 1) + '. d' + (i + 1));
  const editor = editorOn('1. p\n' + nine.join('\n') + '\n   1. x\n   2. y', 10, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines,
    ['1. p', ...nine, '      10. x', '   1. y']);
});

test('Tab on the first child nests it and closes the gap left behind (Fall B)', async () => {
  const editor = editorOn('1. eins\n2. zwei\n   1. zwei 1\n   2. zwei 2\n   3. zwei 3', 2, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines,
    ['1. eins', '2. zwei', '      1. zwei 1', '   1. zwei 2', '   2. zwei 3']);
});

test('Shift+Tab on the first child renumbers both levels (Fall A)', async () => {
  const editor = editorOn('1. eins\n2. zwei\n   1. zwei 1\n   2. zwei 2\n   3. zwei 3', 2, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines,
    ['1. eins', '2. zwei', '3. zwei 1', '   1. zwei 2', '   2. zwei 3']);
});

test('Shift+Tab out of a deeper level joins a populated parent across three levels', async () => {
  // Level 3 item moves up into the populated level 2 sequence; the level it
  // leaves closes its gap, the level it joins continues after it.
  const editor = editorOn(
    '1. a\n   1. b\n      1. p\n      2. q\n   2. c', 2, 6);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines,
    ['1. a', '   1. b', '   2. p', '      1. q', '   3. c']);
});

test('Tab joining a deeper level keeps the paren delimiter', async () => {
  const editor = editorOn('1) p\n      1) x\n   1) y', 2, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1) p', '      1) x', '      2) y']);
});

test('Enter on a dash item under a numbered parent continues the dash', async () => {
  const editor = editorOn('1. parent\n   - dash', 1, 9);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[2], '   - ');
});

// --- Tab / Shift+Tab: respect existing indentation stops (opt-in) ---

function withRespectStops(fn) {
  return async () => {
    vscode._config['indent.respectExistingStops'] = true;
    try { await fn(); } finally { delete vscode._config['indent.respectExistingStops']; }
  };
}

test('respectExistingStops Tab snaps onto the parent content column', withRespectStops(async () => {
  // "10. a" content column is 4; default Tab would indent by 3. With the mode
  // on the item aligns under the existing content column instead.
  const editor = editorOn('10. a\n2. b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['10. a', '    1. b']);
}));

test('respectExistingStops Shift+Tab snaps onto a shallower content column', withRespectStops(async () => {
  // The only shallower stop is "10. a" at content column 4; default Shift+Tab
  // would remove only one marker width (column 10 -> 7).
  const editor = editorOn('10. a\n          1. c', 1, 10);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['10. a', '    1. c']);
}));

test('respectExistingStops Tab with no deeper stop falls back to the marker step', withRespectStops(async () => {
  const editor = editorOn('1. a\n   1. b', 1, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '      1. b']);
}));

test('respectExistingStops off keeps the default marker-width step', async () => {
  // No config set: identical to the default Tab behavior (indent by 3).
  const editor = editorOn('10. a\n2. b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['10. a', '   1. b']);
});

// --- Ctrl+Delete: smart forward delete (opt-in) ---

function withSmartDelete(fn) {
  return async () => {
    vscode._config['editing.smartForwardDelete'] = true;
    try { await fn(); } finally { delete vscode._config['editing.smartForwardDelete']; }
  };
}

test('smartForwardDelete pulls an indented continuation up with one space', withSmartDelete(async () => {
  const editor = editorOn('- item one\n  zusaetzlich noch was', 0, 10);
  await smartDeleteWordRight();
  assert.deepStrictEqual(editor.document.lines, ['- item one zusaetzlich noch was']);
}));

test('smartForwardDelete collapses trailing whitespace to a single space', withSmartDelete(async () => {
  const editor = editorOn('- item   \n  cont', 0, 9);
  await smartDeleteWordRight();
  assert.deepStrictEqual(editor.document.lines, ['- item cont']);
}));

test('smartForwardDelete falls back when the next line is not indented', withSmartDelete(async () => {
  editorOn('word one\nnext line', 0, 8);
  await smartDeleteWordRight();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordRight');
}));

test('smartForwardDelete falls back mid-line', withSmartDelete(async () => {
  editorOn('- item one\n  cont', 0, 5);
  await smartDeleteWordRight();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordRight');
}));

test('smartForwardDelete off behaves as deleteWordRight', async () => {
  editorOn('- item one\n  cont', 0, 10);
  await smartDeleteWordRight();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordRight');
});

// --- Custom (non-CommonMark) list markers (opt-in) ---

const ALL_EXTRA = ['->', '→', '❯', 'a)', 'A)', 'a.', 'A.', '1)', 'a:', 'A:', '1:'];
function withExtraMarkers(markers, fn) {
  return async () => {
    vscode._config['lists.extraMarkers'] = markers;
    try { await fn(); } finally { delete vscode._config['lists.extraMarkers']; }
  };
}

test('execListItem recognizes each enabled custom marker family', withExtraMarkers(ALL_EXTRA, () => {
  for (const line of ['-> x', '→ x', '❯ x', 'a) x', 'A) x', 'a. x', 'A. x', '1: x', 'A: x', 'za) x']) {
    const m = execListItem(line);
    assert.ok(m, line);
  }
}));

test('execListItem ignores custom markers when none are enabled', () => {
  assert.strictEqual(execListItem('a) x'), null);
  assert.strictEqual(execListItem('-> x'), null);
});

test('execListItem ignores a marker family that is not enabled', withExtraMarkers(['a)'], () => {
  assert.ok(execListItem('a) x'));
  assert.strictEqual(execListItem('A) x'), null); // upper-case not enabled
  assert.strictEqual(execListItem('-> x'), null);
}));

test('execListItem still ignores ordinary prose', withExtraMarkers(ALL_EXTRA, () => {
  assert.strictEqual(execListItem('word) text'), null); // 4-letter run, not a marker
  assert.strictEqual(execListItem('a)no gap'), null);
}));

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

test('Enter counts up a lettered custom item', withExtraMarkers(ALL_EXTRA, async () => {
  const editor = editorOn('a) one', 0, 6);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], 'b) ');
}));

test('Enter rolls a lettered item past z into za', withExtraMarkers(ALL_EXTRA, async () => {
  const editor = editorOn('z) last', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], 'za) ');
}));

test('Enter keeps the delimiter on a colon-delimited custom item', withExtraMarkers(ALL_EXTRA, async () => {
  const editor = editorOn('a: one', 0, 6);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], 'b: ');
}));

test('Enter repeats a symbol bullet without a sequence', withExtraMarkers(ALL_EXTRA, async () => {
  const editor = editorOn('-> bullet', 0, 9);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '-> ');
}));

test('Tab nests a custom item with the markerCycle marker for the depth', withExtraMarkers(ALL_EXTRA, async () => {
  // Default markerCycle ["1.","a)","1)","a."]; depth 1 -> "a)".
  const editor = editorOn('a) parent\nb) child', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['a) parent', '   a) child']);
}));

test('Tab nests a numbered item by the cycle when custom markers are active', withExtraMarkers(ALL_EXTRA, async () => {
  const editor = editorOn('1. parent\n2. child', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. parent', '   a) child']);
}));

test('Tab follows markerCycle to the second depth', withExtraMarkers(ALL_EXTRA, async () => {
  // depth 2 -> "1)".
  const editor = editorOn('1. p\n   a) q\n   b) r', 2, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. p', '   a) q', '      1) r']);
}));

test('Tab joins an existing deeper custom sequence', withExtraMarkers(ALL_EXTRA, async () => {
  const editor = editorOn('x) p\n   a) first\nb) second', 2, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['x) p', '   a) first', '   b) second']);
}));

test('propagateMarkerType pulls siblings to the first item type', withExtraMarkers(ALL_EXTRA, () => {
  const doc = new MockDocument('1) x\nb) y\nc) z');
  const ops = [];
  propagateMarkerType(doc, { replace: (r, t) => ops.push({ kind: 'replace', range: r, text: t }) }, 0);
  doc._apply(ops);
  assert.deepStrictEqual(doc.lines, ['1) x', '2) y', '3) z']);
}));

test('propagateMarkerType never rewrites child levels', withExtraMarkers(ALL_EXTRA, () => {
  const doc = new MockDocument('1) x\n   a) child\n   b) child\nb) y');
  const ops = [];
  propagateMarkerType(doc, { replace: (r, t) => ops.push({ kind: 'replace', range: r, text: t }) }, 0);
  doc._apply(ops);
  assert.deepStrictEqual(doc.lines, ['1) x', '   a) child', '   b) child', '2) y']);
}));

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

test('enclosingListItem steps over deeper children to the owning item', () => {
  // The continuation line hangs at the parent content column (3); the deeper
  // `1.`/`2.` children (content column 6) sit in between and must be skipped.
  const doc = new MockDocument('3. parent\n   1. child a\n   2. child b\n   more text');
  const item = enclosingListItem(doc, 3);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 3);
});

test('enclosingListItem resolves a whitespace-only hanging line over children', () => {
  // The reproduced @ww3d case: cursor on the empty hanging line at column 6.
  const doc = new MockDocument(
    '   3. tenant test\n      1. kind eins\n      2. kind zwei\n      ich denke\n      noch eine\n      ');
  const item = enclosingListItem(doc, 5);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 6);
});

test('enclosingListItem stops at a blank line above the children', () => {
  const doc = new MockDocument('3. parent\n   1. child\n\n   orphan');
  assert.strictEqual(enclosingListItem(doc, 3), null);
});

test('enclosingListItem stops at a markerless line shallower than the start', () => {
  const doc = new MockDocument('3. parent\n   1. child\n shallow\n   here');
  assert.strictEqual(enclosingListItem(doc, 3), null);
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

test('Enter on a continuation line over children opens the next parent sibling', async () => {
  // Cursor on the markerless continuation line of `3.`, with deeper `1.`/`2.`
  // children in between. Enter must continue `3.` -> `4.`, not fall back.
  const editor = editorOn('3. parent\n   1. child a\n   2. child b\n   more text', 3, 12);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines,
    ['3. parent', '   1. child a', '   2. child b', '   more text', '4. ']);
});

test('Enter on an empty hanging line over children opens the next parent sibling', async () => {
  // The reproduced @ww3d case: empty hanging line at column 6 over the children
  // of `   3.`. Enter creates `   4.` at column 3.
  const editor = editorOn(
    '   3. tenant\n      1. kind eins\n      2. kind zwei\n      ich denke\n      noch eine\n      ', 5, 6);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[6], '   4. ');
});

test('Enter on a continuation line under a blank line falls back', async () => {
  editorOn('3. parent\n   1. child\n\n   orphan', 3, 9);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
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
