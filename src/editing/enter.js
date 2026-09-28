// Enter / Shift+Enter: list continuation, code-fence auto-close, and hanging
// continuation lines.
const vscode = require('vscode');
const {
  COMPOUND_TASK_RE,
  execListItem,
  advanceMarker,
} = require('./list-markers');
const {
  contentColumn,
  enclosingListItem,
  resequenceSiblingsBelow,
} = require('./list-structure');
const { suppressedEdit } = require('./edit-guard');
const { tableEnter, tableShiftEnter } = require('../tables');

// Matches a code fence delimiter line: ``` or ~~~ (3+), optional language info.
const FENCE_RE = /^(\s*)(`{3,}|~{3,})\s*([\w-]*)\s*$/;

// True if the fence-delimiter line at lineNo opens a block that is never
// closed: an even number of delimiter lines below means all later fences
// pair among themselves, leaving this one open.
function fenceIsUnclosed(document, lineNo) {
  let later = 0;
  for (let l = lineNo + 1; l < document.lineCount; l++) {
    if (FENCE_RE.test(document.lineAt(l).text)) later++;
  }
  return later % 2 === 0;
}

/**
 * Enter-key handler: continues a list item or hanging continuation line, closes
 * an unclosed code fence, or falls back to the editor default.
 */
async function onEnterKey() {
  const fallback = () =>
    vscode.commands.executeCommand('default:type', { text: '\n' });
  const editor = vscode.window.activeTextEditor;
  if (editor && (await tableEnter(editor, suppressedEdit))) return;
  if (editor?.selections.length !== 1 || !editor.selection.isEmpty)
    return fallback();

  const pos = editor.selection.active;
  const lineText = editor.document.lineAt(pos.line).text;

  // Opening code fence + Enter at line end -> insert the closing fence and
  // place the cursor on the empty line in between. The snippet contains no
  // indentation: VS Code auto-indents snippet continuation lines to the
  // current line's indentation, so including fence[1] would double it.
  const fence = FENCE_RE.exec(lineText);
  if (
    fence &&
    pos.character === lineText.length &&
    fenceIsUnclosed(editor.document, pos.line)
  ) {
    await editor.insertSnippet(
      new vscode.SnippetString(`\n$0\n${fence[2]}`),
      pos,
    );
    return;
  }

  const m = execListItem(lineText);
  if (!m) {
    // Not a list line itself, but a continuation line of one (a wrapped or
    // Shift+Enter-hung line): Enter still continues the enclosing item with a
    // fresh sibling at its level, renumbering what follows.
    const encl = enclosingListItem(editor.document, pos.line);
    if (!encl) return fallback();
    return continueSibling(editor, pos, encl.m, encl.contentCol);
  }

  const indent = m[1],
    checkbox = m[4] || '';
  // Compound task item: the content is itself a one-line task list
  // ("1. - [ ] foo"). Only the leading marker follows its continuation
  // rule below; the rest of the compound prefix continues verbatim with a
  // fresh box (an inner number is content of the new line, never
  // incremented).
  const comp = checkbox ? null : COMPOUND_TASK_RE.exec(m[5]);
  const prefixLen = contentColumn(m);
  if (pos.character < prefixLen) return fallback(); // cursor inside indentation/marker

  if (m[5] === '' || (comp && comp[4] === '')) {
    // Empty item + Enter -> terminate the list by removing the marker.
    await suppressedEdit(editor, (b) =>
      b.delete(new vscode.Range(pos.line, indent.length, pos.line, prefixLen)),
    );
    return;
  }

  return continueSibling(editor, pos, m, prefixLen);
}

// Insert a fresh sibling below pos for the list item described by `m`, whose
// text hangs at `contentCol`. Numbered markers advance and the following
// siblings renumber; bullets and the compound prefix repeat with a fresh box.
// Text right of the cursor moves onto the new line, after the marker.
async function continueSibling(editor, pos, m, contentCol) {
  const indent = m[1],
    gap = m[3],
    checkbox = m[4] || '';
  const comp = checkbox ? null : COMPOUND_TASK_RE.exec(m[5]);
  // Numeric and letter markers count up, symbol/dash markers repeat.
  const nextBullet = advanceMarker(m[2]);

  await suppressedEdit(editor, (b) => {
    b.insert(
      pos,
      '\n' +
        indent +
        nextBullet +
        gap +
        (comp ? `${comp[1]}[ ] ` : checkbox ? '[ ] ' : ''),
    );
    // Mid-sequence Enter: the following siblings continue after the new item
    // (numbers and letters; symbols repeat and are not renumbered).
    resequenceSiblingsBelow(
      editor.document,
      b,
      pos.line + 1,
      indent.length,
      advanceMarker(nextBullet),
      contentCol,
    );
  });
}

// Shift+Enter: hanging continuation of a list item. Inside an item or one of
// its continuation lines, split at the cursor and indent the new line with
// whitespace to the item's content column - no marker, no number. Text right
// of the cursor moves down with it. Outside any list, the editor default.
async function onShiftEnterKey() {
  const fallback = () =>
    vscode.commands.executeCommand('default:type', { text: '\n' });
  const editor = vscode.window.activeTextEditor;
  if (editor && (await tableShiftEnter(editor, suppressedEdit))) return;
  if (editor?.selections.length !== 1 || !editor.selection.isEmpty)
    return fallback();

  const pos = editor.selection.active;
  const item = enclosingListItem(editor.document, pos.line);
  if (!item) return fallback();
  // Cursor still inside the marker/indentation (before the content column):
  // there is nothing to hang yet, so defer to the default newline - same
  // guard onEnterKey applies with prefixLen.
  if (pos.character < item.contentCol) return fallback();

  await suppressedEdit(editor, (b) =>
    b.insert(pos, `\n${' '.repeat(item.contentCol)}`),
  );
}

module.exports = {
  FENCE_RE,
  fenceIsUnclosed,
  onEnterKey,
  continueSibling,
  onShiftEnterKey,
};
