// CSV/TSV paste, extra-cell diagnostics with quick fix, number right-align
// (REQ-042, REQ-048, REQ-053, REQ-054, REQ-066, REQ-068, REQ-069).

import { test, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
  Range,
} from '../helpers/vscode-mock.ts';
import type { MockContext } from '../helpers/vscode-mock.ts';
import { nth } from '../helpers/nth.ts';

// The module as the mock context drives it (the real signature takes a vscode.ExtensionContext).
interface Tables {
  registerTableFeatures(context: MockContext): void;
}

const vscode = install();
const tables = await loadFresh<Tables>('src/tables/index.ts');
tables.registerTableFeatures({ subscriptions: [] });

// The mock keeps the providers and results the sources hand it as `unknown`;
// these views name the members the tests read, and the guards check them.
interface PasteEdit {
  insertText: unknown;
  title: string;
  yieldTo: unknown;
}
interface EditOp {
  range: Range;
  text: string;
}
interface Action {
  title: string;
  kind: unknown;
  isPreferred?: boolean;
  edit: { ops: EditOp[] };
}
interface Diag {
  code: unknown;
  range: Range;
}

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null;
const isPasteEdit = (v: unknown): v is PasteEdit =>
  isRecord(v) && typeof v.title === 'string' && 'insertText' in v;
const isAction = (v: unknown): v is Action =>
  isRecord(v) &&
  typeof v.title === 'string' &&
  isRecord(v.edit) &&
  Array.isArray(v.edit.ops);
const isDiag = (v: unknown): v is Diag =>
  isRecord(v) && v.range instanceof Range && 'code' in v;

// Calls `method` of a provider the source registered.
function call(provider: unknown, method: string, ...args: unknown[]): unknown {
  assert.ok(isRecord(provider), `no provider with ${method}`);
  const fn = provider[method];
  if (typeof fn !== 'function') throw new TypeError(`no ${method}`);
  return Reflect.apply(fn, provider, args);
}

function actionsOf(result: unknown): Action[] {
  assert.ok(Array.isArray(result), 'an array of actions');
  const actions: Action[] = [];
  for (const a of result) {
    assert.ok(isAction(a), 'a code action with an edit');
    actions.push(a);
  }
  return actions;
}

const codeActions = (
  doc: MockDocument,
  range: Range,
  diagnostics: Diag[] = [],
): Action[] =>
  actionsOf(
    call(vscode._codeActionProvider, 'provideCodeActions', doc, range, {
      diagnostics,
    }),
  );

// The diagnostics published for `doc`, if any.
function diagnosticsOf(doc: MockDocument): Diag[] | undefined {
  const list = defined(vscode._diagnostics, 'diagnostic collection').get(
    doc.uri.toString(),
  );
  if (list === undefined) return undefined;
  assert.ok(Array.isArray(list) && list.every(isDiag), 'diagnostics');
  return list;
}

beforeEach(() => {
  vscode._config = {};
});

const transfer = (text: string) => ({
  get: (mime: string) =>
    mime === 'text/plain'
      ? { asString: () => Promise.resolve(text) }
      : undefined,
});
async function paste(
  doc: MockDocument,
  line: number,
  ch: number,
  text: string,
): Promise<PasteEdit[] | undefined> {
  const result = await call(
    vscode._pasteProvider,
    'provideDocumentPasteEdits',
    doc,
    [new Range(line, ch, line, ch)],
    transfer(text),
    {},
    {},
  );
  if (result === undefined) return undefined;
  assert.ok(Array.isArray(result) && result.every(isPasteEdit), 'paste edits');
  return result;
}
// The first paste edit offered, which the test expects to exist.
async function pasteEdit(
  doc: MockDocument,
  line: number,
  ch: number,
  text: string,
): Promise<PasteEdit> {
  const edits = await paste(doc, line, ch, text);
  assert.ok(edits, 'a paste offer');
  return nth(edits, 0);
}

test('TSV paste is offered as an aligned table, pipes escaped (REQ-048)', async () => {
  const doc = new MockDocument('');
  const edit = await pasteEdit(doc, 0, 0, 'Name\tNote\nAda\ta|b\n');
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
  const meta = vscode._pasteMeta;
  assert.ok(isRecord(meta));
  assert.deepStrictEqual(meta.pasteMimeTypes, ['text/plain']);
});

test('CSV paste handles quotes and repeats a blockquote prefix, ending the table before text', async () => {
  const doc = new MockDocument('> \nfollowing text');
  const edit = await pasteEdit(doc, 0, 2, 'a,b\n"x, y","say ""hi"""\n');
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

const openDoc = (doc: MockDocument) =>
  defined(vscode._docOpenListener, 'document open listener')(doc);

const X = '| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |\n| 5 | 6 |';

test('cells beyond the header width are flagged (REQ-053, REQ-069)', () => {
  const doc = new MockDocument(X);
  openDoc(doc);
  const d = nth(diagnosticsOf(doc) ?? [], 0);
  assert.strictEqual(d.code, 'table-extra-cells');
  assert.deepStrictEqual(
    [d.range.start.line, d.range.start.character, d.range.end.character],
    [2, 9, 16],
  );
  assert.strictEqual(diagnosticsOf(doc)?.length, 1);
  vscode._config['tables.validate'] = false;
  openDoc(doc);
  assert.strictEqual(diagnosticsOf(doc), undefined);
});

test('the quick fix widens header and delimiter row (REQ-054)', () => {
  const doc = new MockDocument(X);
  openDoc(doc);
  const diags = diagnosticsOf(doc);
  assert.ok(diags);
  const actions = codeActions(doc, nth(diags, 0).range, diags);
  const fix = actions.find((a) => a.title === 'Add column to header');
  assert.ok(fix?.isPreferred);
  assert.ok(fix.kind, 'a kind the mock defines');
  assert.strictEqual(fix.kind, vscode.CodeActionKind.QuickFix);
  const lines = X.split('\n');
  for (const op of fix.edit.ops)
    lines[op.range.start.line] =
      nth(lines, op.range.start.line).slice(0, op.range.start.character) +
      op.text +
      nth(lines, op.range.start.line).slice(op.range.end.character);
  assert.strictEqual(
    nth(lines.join('\n').split('\n'), 1).split('|').length - 2,
    4,
    'four delimiter cells',
  );
});

const N = '| n | amount |\n|---|---|\n| a | 1,200 |\n| b | 3.5 |\n| c |  |';

test('a number column without alignment gets the right-align action (REQ-042, REQ-066)', () => {
  const doc = new MockDocument(N);
  const a = nth(codeActions(doc, new Range(2, 8, 2, 8)), 0);
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
    codeActions(doc, new Range(2, 2, 2, 2)),
    [],
    'text column',
  );
  vscode._config['tables.suggestNumericAlign'] = false;
  assert.deepStrictEqual(codeActions(doc, new Range(2, 8, 2, 8)), []);
});

test('an aligned column or a lone dash delimiter is handled', () => {
  const aligned = new MockDocument('| v |\n|--:|\n| 1 |');
  assert.deepStrictEqual(codeActions(aligned, new Range(2, 2, 2, 2)), []);
  const lone = new MockDocument('| v |\n|-|\n| 1 |');
  const a = nth(codeActions(lone, new Range(2, 2, 2, 2)), 0);
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
