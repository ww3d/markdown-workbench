// CSV/TSV paste, extra-cell diagnostics with quick fix, number right-align
// (REQ-042, REQ-048, REQ-053, REQ-054, REQ-066, REQ-068, REQ-069).

import { test, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  install,
  loadFresh,
  MockDocument,
  Range,
} from '../helpers/vscode-mock.js';

const vscode = install();
const tables = await loadFresh('src/tables/index.js');
tables.registerTableFeatures({ subscriptions: [] });

beforeEach(() => {
  vscode._config = {};
});

const transfer = (text) => ({
  get: (mime) =>
    mime === 'text/plain' ? { asString: async () => text } : undefined,
});
const paste = (doc, line, ch, text) =>
  vscode._pasteProvider.provideDocumentPasteEdits(
    doc,
    [new Range(line, ch, line, ch)],
    transfer(text),
    {},
    {},
  );

test('TSV paste is offered as an aligned table, pipes escaped (REQ-048)', async () => {
  const doc = new MockDocument('');
  const [edit] = await paste(doc, 0, 0, 'Name\tNote\nAda\ta|b\n');
  assert.strictEqual(
    edit.insertText,
    '| Name | Note |\n| ---- | ---- |\n| Ada  | a\\|b |',
  );
  assert.strictEqual(edit.title, 'Insert as Markdown table');
  assert.deepStrictEqual(
    edit.yieldTo,
    [vscode.DocumentDropOrPasteEditKind.Text],
    'plain paste stays default',
  );
  assert.deepStrictEqual(vscode._pasteMeta.pasteMimeTypes, ['text/plain']);
});

test('CSV paste handles quotes and repeats a blockquote prefix, ending the table before text', async () => {
  const doc = new MockDocument('> \nfollowing text');
  const [edit] = await paste(doc, 0, 2, 'a,b\n"x, y","say ""hi"""\n');
  assert.strictEqual(
    edit.insertText,
    '| a    | b        |\n> | ---- | -------- |\n> | x, y | say "hi" |\n>',
  );
});

test('prose, a single CSV line, mid-line pastes and code blocks get no offer', async () => {
  const doc = new MockDocument('text here\n```\n\n```');
  assert.strictEqual(await paste(doc, 0, 0, 'just, some prose'), undefined);
  assert.strictEqual(
    await paste(doc, 0, 4, 'a\tb\nc\td'),
    undefined,
    'mid-line',
  );
  assert.strictEqual(
    await paste(doc, 2, 0, 'a\tb\nc\td'),
    undefined,
    'code block',
  );
  vscode._config['tables.pasteAsTable'] = false;
  assert.strictEqual(
    await paste(new MockDocument(''), 0, 0, 'a\tb'),
    undefined,
    'setting off',
  );
});

const X = '| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |\n| 5 | 6 |';

test('cells beyond the header width are flagged (REQ-053, REQ-069)', () => {
  const doc = new MockDocument(X);
  vscode._docOpenListener(doc);
  const [d] = vscode._diagnostics.get(doc.uri.toString());
  assert.strictEqual(d.code, 'table-extra-cells');
  assert.deepStrictEqual(
    [d.range.start.line, d.range.start.character, d.range.end.character],
    [2, 9, 16],
  );
  assert.strictEqual(vscode._diagnostics.get(doc.uri.toString()).length, 1);
  vscode._config['tables.validate'] = false;
  vscode._docOpenListener(doc);
  assert.strictEqual(vscode._diagnostics.get(doc.uri.toString()), undefined);
});

test('the quick fix widens header and delimiter row (REQ-054)', () => {
  const doc = new MockDocument(X);
  vscode._docOpenListener(doc);
  const diags = vscode._diagnostics.get(doc.uri.toString());
  const actions = vscode._codeActionProvider.provideCodeActions(
    doc,
    diags[0].range,
    { diagnostics: diags },
  );
  const fix = actions.find((a) => a.title === 'Add column to header');
  assert.ok(fix?.isPreferred);
  assert.ok(fix.kind, 'a kind the mock defines');
  assert.strictEqual(fix.kind, vscode.CodeActionKind.QuickFix);
  const lines = X.split('\n');
  for (const op of fix.edit.ops)
    lines[op.range.start.line] =
      lines[op.range.start.line].slice(0, op.range.start.character) +
      op.text +
      lines[op.range.start.line].slice(op.range.end.character);
  assert.strictEqual(
    lines.join('\n').split('\n')[1].split('|').length - 2,
    4,
    'four delimiter cells',
  );
});

const N = '| n | amount |\n|---|---|\n| a | 1,200 |\n| b | 3.5 |\n| c |  |';

test('a number column without alignment gets the right-align action (REQ-042, REQ-066)', () => {
  const doc = new MockDocument(N);
  const actions = vscode._codeActionProvider.provideCodeActions(
    doc,
    new Range(2, 8, 2, 8),
    { diagnostics: [] },
  );
  const [a] = actions;
  assert.strictEqual(a.title, 'Right-align column');
  assert.ok(a.kind, 'a kind the mock defines');
  assert.strictEqual(a.kind, vscode.CodeActionKind.RefactorRewrite);
  assert.deepStrictEqual(
    a.edit.ops.map((o) => [
      o.range.start.line,
      o.range.start.character,
      o.range.end.character,
      o.text,
    ]),
    [[1, 7, 8, ':']],
  );
  assert.deepStrictEqual(
    vscode._codeActionProvider.provideCodeActions(doc, new Range(2, 2, 2, 2), {
      diagnostics: [],
    }),
    [],
    'text column',
  );
  vscode._config['tables.suggestNumericAlign'] = false;
  assert.deepStrictEqual(
    vscode._codeActionProvider.provideCodeActions(doc, new Range(2, 8, 2, 8), {
      diagnostics: [],
    }),
    [],
  );
});

test('an aligned column or a lone dash delimiter is handled', () => {
  const aligned = new MockDocument('| v |\n|--:|\n| 1 |');
  assert.deepStrictEqual(
    vscode._codeActionProvider.provideCodeActions(
      aligned,
      new Range(2, 2, 2, 2),
      { diagnostics: [] },
    ),
    [],
  );
  const lone = new MockDocument('| v |\n|-|\n| 1 |');
  const [a] = vscode._codeActionProvider.provideCodeActions(
    lone,
    new Range(2, 2, 2, 2),
    { diagnostics: [] },
  );
  assert.deepStrictEqual(
    a.edit.ops.map((o) => [
      o.range.start.character,
      o.range.end.character,
      o.text,
    ]),
    [[2, 2, ':']],
    '- becomes -:',
  );
});

test('no offer when text stands before the cursor on the line', async () => {
  assert.strictEqual(
    await paste(new MockDocument('existing text'), 0, 13, 'a\tb\nc\td'),
    undefined,
  );
});
