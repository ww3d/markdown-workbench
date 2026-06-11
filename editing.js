// Markdown editing helpers for the text editor (not the checklist view):
// Enter list continuation, Tab/Shift+Tab nesting, formatting shortcuts,
// link/table insertion, table reflow, selection sorting. Modeled on the
// generic authoring features of Learn Markdown / Markdown All in One.

const vscode = require('vscode');
const path = require('path');

// Matches any list item: "- text", "* text", "3. text", optional "[ ] " checkbox.
const LIST_ITEM_RE = /^(\s*)([-*+]|\d+[.)])(\s+)(\[(?: |x|X)\]\s+)?(.*)$/;

// --- Enter: continue list ------------------------------------------------------

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

async function onEnterKey() {
  const fallback = () => vscode.commands.executeCommand('default:type', { text: '\n' });
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selections.length !== 1 || !editor.selection.isEmpty) return fallback();

  const pos = editor.selection.active;
  const lineText = editor.document.lineAt(pos.line).text;

  // Opening code fence + Enter at line end -> insert the closing fence and
  // place the cursor on the empty line in between. The snippet contains no
  // indentation: VS Code auto-indents snippet continuation lines to the
  // current line's indentation, so including fence[1] would double it.
  const fence = FENCE_RE.exec(lineText);
  if (fence && pos.character === lineText.length && fenceIsUnclosed(editor.document, pos.line)) {
    await editor.insertSnippet(new vscode.SnippetString('\n$0\n' + fence[2]), pos);
    return;
  }

  const m = LIST_ITEM_RE.exec(lineText);
  if (!m) return fallback();

  const indent = m[1], bullet = m[2], gap = m[3], checkbox = m[4] || '';
  const prefixLen = indent.length + bullet.length + gap.length + checkbox.length;
  if (pos.character < prefixLen) return fallback(); // cursor inside indentation/marker

  if (m[5] === '') {
    // Empty item + Enter -> terminate the list by removing the marker.
    await editor.edit((b) => b.delete(new vscode.Range(pos.line, indent.length, pos.line, prefixLen)));
    return;
  }

  let nextBullet = bullet;
  const num = /^(\d+)([.)])$/.exec(bullet);
  if (num) nextBullet = String(parseInt(num[1], 10) + 1) + num[2];

  await editor.edit((b) => b.insert(pos, '\n' + indent + nextBullet + gap + (checkbox ? '[ ] ' : '')));
}

// --- Tab / Shift+Tab: nest and un-nest list items -------------------------------

// Lines covered by the current selection (or just the cursor line).
function coveredLines(editor) {
  const lines = [];
  for (const sel of editor.selections) {
    for (let l = sel.start.line; l <= sel.end.line; l++) {
      if (!lines.includes(l)) lines.push(l);
    }
  }
  return lines;
}

// Adaptive indent unit per CommonMark: child content aligns under the parent
// content, i.e. indent by marker + gap width ("- " -> 2, "10. " -> 4).
function indentUnitFor(match) {
  return ' '.repeat(match[2].length + match[3].length);
}

async function onTabKey() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('tab');
  if (!editor) return fallback();

  const targets = coveredLines(editor)
    .map((l) => ({ line: l, m: LIST_ITEM_RE.exec(editor.document.lineAt(l).text) }))
    .filter((t) => t.m);
  if (!targets.length) return fallback();

  await editor.edit((b) => {
    for (const t of targets) {
      b.insert(new vscode.Position(t.line, 0), indentUnitFor(t.m));
    }
  });
}

async function onShiftTabKey() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('outdent');
  if (!editor) return fallback();

  const targets = coveredLines(editor)
    .map((l) => ({ line: l, m: LIST_ITEM_RE.exec(editor.document.lineAt(l).text) }))
    .filter((t) => t.m && t.m[1].length > 0);
  if (!targets.length) return fallback();

  await editor.edit((b) => {
    for (const t of targets) {
      const indent = t.m[1];
      const remove = indent.startsWith('\t') ? 1 : Math.min(indent.length, indentUnitFor(t.m).length);
      b.delete(new vscode.Range(t.line, 0, t.line, remove));
    }
  });
}

// --- Formatting: bold, italic, code ---------------------------------------------

function escapeSnippet(s) {
  return s.replace(/[\\$}]/g, '\\$&');
}

async function toggleWrap(marker) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;

  // Empty single cursor on no word: drop markers and put the cursor inside.
  if (editor.selections.length === 1 && editor.selection.isEmpty
      && !doc.getWordRangeAtPosition(editor.selection.active)) {
    await editor.insertSnippet(new vscode.SnippetString(escapeSnippet(marker) + '$0' + escapeSnippet(marker)));
    return;
  }

  await editor.edit((b) => {
    for (const sel of editor.selections) {
      let range = sel;
      if (sel.isEmpty) {
        const word = doc.getWordRangeAtPosition(sel.active);
        if (!word) continue;
        range = word;
      }
      const text = doc.getText(range);
      if (text.length >= marker.length * 2 && text.startsWith(marker) && text.endsWith(marker)) {
        b.replace(range, text.slice(marker.length, text.length - marker.length));
        continue;
      }
      // Selection sits inside existing markers -> unwrap them.
      const ext = new vscode.Range(
        range.start.translate(0, -Math.min(marker.length, range.start.character)),
        range.end.translate(0, marker.length)
      );
      const extText = doc.getText(ext);
      if (extText === marker + text + marker) {
        b.replace(ext, text);
        continue;
      }
      b.replace(range, marker + text + marker);
    }
  });
}

// --- Links -----------------------------------------------------------------------

async function insertWebLink() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const text = editor.document.getText(editor.selection);
  const snippet = '[${1:' + escapeSnippet(text || 'text') + '}](${2:https://})';
  await editor.insertSnippet(new vscode.SnippetString(snippet), editor.selection);
}

async function insertFileLink() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const files = await vscode.workspace.findFiles('**/*', '{**/node_modules/**,**/.git/**}', 2000);
  if (!files.length) {
    vscode.window.showInformationMessage('No workspace files found.');
    return;
  }
  const items = files
    .map((uri) => ({ label: vscode.workspace.asRelativePath(uri), uri }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Link to file in workspace' });
  if (!pick) return;

  let target;
  if (editor.document.uri.scheme === 'file') {
    target = path.relative(path.dirname(editor.document.uri.fsPath), pick.uri.fsPath).split(path.sep).join('/');
  } else {
    target = pick.label.split(path.sep).join('/');
  }
  const selText = editor.document.getText(editor.selection);
  const label = selText || path.basename(pick.uri.fsPath);
  await editor.edit((b) => b.replace(editor.selection, '[' + label + '](' + target + ')'));
}

// --- Lists (insert / convert selection) -------------------------------------------

async function insertList(kind) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const prefix = (i) => kind === 'numbered' ? (i + 1) + '. ' : kind === 'task' ? '- [ ] ' : '- ';

  if (editor.selection.isEmpty) {
    await editor.edit((b) => b.insert(editor.selection.active, prefix(0)));
    return;
  }
  const lines = coveredLines(editor);
  await editor.edit((b) => {
    let i = 0;
    for (const l of lines) {
      if (editor.document.lineAt(l).text.trim() === '') continue;
      b.insert(new vscode.Position(l, 0), prefix(i++));
    }
  });
}

// --- Tables ------------------------------------------------------------------------

async function insertTable() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const input = await vscode.window.showInputBox({
    prompt: 'Table size: columns x rows (data rows)',
    value: '3x2',
    validateInput: (v) => /^\s*\d+\s*[xX*]\s*\d+\s*$/.test(v) ? null : 'Format: 3x2'
  });
  if (!input) return;
  const [, c, r] = /^\s*(\d+)\s*[xX*]\s*(\d+)\s*$/.exec(input);
  const cols = Math.min(20, parseInt(c, 10)), rows = Math.min(50, parseInt(r, 10));

  let tab = 1, out = '';
  const row = (cell) => '| ' + Array.from({ length: cols }, cell).join(' | ') + ' |\n';
  out += row(() => '${' + (tab++) + ':Header}');
  out += row(() => '---');
  for (let i = 0; i < rows; i++) out += row(() => '$' + (tab++));
  await editor.insertSnippet(new vscode.SnippetString(out));
}

// Pure helpers (exported for tests): reflow a block of table lines.
function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

function isSeparatorRow(cells) {
  return cells.length > 0 && cells.every((c) => /^:?-+:?$/.test(c));
}

function reflowTable(lines, mode) {
  const rows = lines.map(splitRow);
  const colCount = Math.max(...rows.map((r) => r.length));
  for (const r of rows) while (r.length < colCount) r.push('');

  const widths = Array.from({ length: colCount }, (_, i) =>
    Math.max(3, ...rows.filter((r) => !isSeparatorRow(r)).map((r) => r[i].length))
  );

  return rows.map((r) => {
    if (isSeparatorRow(r)) {
      return '| ' + r.map((c, i) => {
        const left = c.startsWith(':'), right = c.endsWith(':');
        const w = mode === 'distribute' ? widths[i] : 3;
        let dashes = '-'.repeat(Math.max(1, w - (left ? 1 : 0) - (right ? 1 : 0)));
        return (left ? ':' : '') + dashes + (right ? ':' : '');
      }).join(' | ') + ' |';
    }
    const cells = mode === 'distribute' ? r.map((c, i) => c.padEnd(widths[i])) : r;
    return '| ' + cells.join(' | ') + ' |';
  });
}

function tableRangeAt(editor) {
  const doc = editor.document;
  let start, end;
  if (!editor.selection.isEmpty) {
    start = editor.selection.start.line;
    end = editor.selection.end.line;
  } else {
    start = end = editor.selection.active.line;
    while (start > 0 && /^\s*\|/.test(doc.lineAt(start - 1).text)) start--;
    while (end < doc.lineCount - 1 && /^\s*\|/.test(doc.lineAt(end + 1).text)) end++;
  }
  const lines = [];
  for (let l = start; l <= end; l++) {
    const text = doc.lineAt(l).text;
    if (!/^\s*\|/.test(text)) return null;
    lines.push(text);
  }
  return { start, end, lines };
}

async function reflowTableCommand(mode) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const t = tableRangeAt(editor);
  if (!t) {
    vscode.window.showInformationMessage('Place the cursor inside a markdown table (lines starting with |).');
    return;
  }
  const out = reflowTable(t.lines, mode).join('\n');
  const range = new vscode.Range(t.start, 0, t.end, editor.document.lineAt(t.end).text.length);
  await editor.edit((b) => b.replace(range, out));
}

// --- Sorting -------------------------------------------------------------------------

async function sortSelection(descending) {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selection.isEmpty) {
    vscode.window.showInformationMessage('Select the lines to sort first.');
    return;
  }
  const start = editor.selection.start.line;
  const end = editor.selection.end.line;
  const lines = [];
  for (let l = start; l <= end; l++) lines.push(editor.document.lineAt(l).text);
  lines.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));
  if (descending) lines.reverse();
  const range = new vscode.Range(start, 0, end, editor.document.lineAt(end).text.length);
  await editor.edit((b) => b.replace(range, lines.join('\n')));
}

// --- Language identifier ----------------------------------------------------------------

async function insertLanguageIdentifier(shikiLangs) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const pick = await vscode.window.showQuickPick(shikiLangs.slice().sort(), {
    placeHolder: 'Language identifier for the code fence'
  });
  if (!pick) return;
  await editor.edit((b) => b.replace(editor.selection, pick));
}

// --- Authoring menu (Alt+M) ----------------------------------------------------------------

async function authoringMenu() {
  const items = [
    { label: '$(bold) Bold', cmd: 'markdownWorkbench.formatBold' },
    { label: '$(italic) Italic', cmd: 'markdownWorkbench.formatItalic' },
    { label: '$(symbol-string) Code', cmd: 'markdownWorkbench.formatCode' },
    { label: '$(link) Link to web', cmd: 'markdownWorkbench.insertWebLink' },
    { label: '$(file) Link to file in workspace', cmd: 'markdownWorkbench.insertFileLink' },
    { label: '$(list-unordered) Bulleted list', cmd: 'markdownWorkbench.insertBulletedList' },
    { label: '$(list-ordered) Numbered list', cmd: 'markdownWorkbench.insertNumberedList' },
    { label: '$(checklist) Task list', cmd: 'markdownWorkbench.insertTaskList' },
    { label: '$(table) Insert table', cmd: 'markdownWorkbench.insertTable' },
    { label: '$(arrow-both) Distribute table', cmd: 'markdownWorkbench.distributeTable' },
    { label: '$(fold) Consolidate table', cmd: 'markdownWorkbench.consolidateTable' },
    { label: '$(sort-precedence) Sort selection ascending', cmd: 'markdownWorkbench.sortAscending' },
    { label: '$(sort-precedence) Sort selection descending', cmd: 'markdownWorkbench.sortDescending' },
    { label: '$(code) Insert language identifier', cmd: 'markdownWorkbench.insertLanguageIdentifier' }
  ];
  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Markdown authoring' });
  if (pick) vscode.commands.executeCommand(pick.cmd);
}

// --- Fence language completion -------------------------------------------------------------

// Suggests language identifiers while typing after ``` (or ~~~).
function registerFenceLanguageCompletion(context, shikiLangs) {
  // Bundled language ids plus the aliases shiki resolves for them.
  const langs = [...new Set([
    ...shikiLangs,
    'bash', 'sh', 'shell', 'zsh', 'ps', 'ps1', 'batch', 'js', 'ts', 'yml'
  ])].sort();

  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider('markdown', {
      provideCompletionItems(document, position) {
        const before = document.lineAt(position.line).text.slice(0, position.character);
        const m = /^(\s*)(`{3,}|~{3,})([\w-]*)$/.exec(before);
        if (!m) return undefined;
        const replaceRange = new vscode.Range(
          position.line, position.character - m[3].length,
          position.line, position.character
        );
        return langs.map((lang) => {
          const item = new vscode.CompletionItem(lang, vscode.CompletionItemKind.Value);
          item.range = replaceRange;
          return item;
        });
      }
    }, '`', '~')
  );
}

// --- Registration ------------------------------------------------------------------------------

function registerEditingCommands(context, shikiLangs) {
  registerFenceLanguageCompletion(context, shikiLangs);
  const reg = (id, fn) => context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  reg('markdownWorkbench.onEnterKey', onEnterKey);
  reg('markdownWorkbench.onTabKey', onTabKey);
  reg('markdownWorkbench.onShiftTabKey', onShiftTabKey);
  reg('markdownWorkbench.formatBold', () => toggleWrap('**'));
  reg('markdownWorkbench.formatItalic', () => toggleWrap('*'));
  reg('markdownWorkbench.formatCode', () => toggleWrap('`'));
  reg('markdownWorkbench.insertWebLink', insertWebLink);
  reg('markdownWorkbench.insertFileLink', insertFileLink);
  reg('markdownWorkbench.insertBulletedList', () => insertList('bulleted'));
  reg('markdownWorkbench.insertNumberedList', () => insertList('numbered'));
  reg('markdownWorkbench.insertTaskList', () => insertList('task'));
  reg('markdownWorkbench.insertTable', insertTable);
  reg('markdownWorkbench.distributeTable', () => reflowTableCommand('distribute'));
  reg('markdownWorkbench.consolidateTable', () => reflowTableCommand('consolidate'));
  reg('markdownWorkbench.sortAscending', () => sortSelection(false));
  reg('markdownWorkbench.sortDescending', () => sortSelection(true));
  reg('markdownWorkbench.insertLanguageIdentifier', () => insertLanguageIdentifier(shikiLangs));
  reg('markdownWorkbench.authoringMenu', authoringMenu);
}

module.exports = {
  registerEditingCommands, reflowTable, splitRow, LIST_ITEM_RE,
  // Exported for tests only.
  _internal: { FENCE_RE, fenceIsUnclosed, isSeparatorRow, indentUnitFor, escapeSnippet, onEnterKey, onTabKey, onShiftTabKey, sortSelection, toggleWrap }
};
