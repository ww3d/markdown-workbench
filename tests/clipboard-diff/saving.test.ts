// The immediate save of a clipboard-diff page and its save window
// (src/clipboard-diff/saving.ts): saveWithoutFormatting vs document.save,
// save actions never reaching the file, re-save after a save, failed save
// warnings, and reconciling edits that arrived after the write on did-save.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  opened,
  pageDoc,
  pageStore,
  setText,
  setup,
  SCHEME,
} from '../helpers/clipboard-diff-setup.ts';
import { nth } from '../helpers/nth.ts';
import { install, loadFresh, makeUri } from '../helpers/vscode-mock.ts';
import type { MockDocument, MockUri } from '../helpers/vscode-mock.ts';

// The saver as the mock drives it (the real signatures take vscode types).
interface Saver {
  readonly saving: Map<string, { since: number; own: boolean }>;
  isSaving(doc: { uri: MockUri }): boolean;
}
interface SavingModule {
  PageSaver: new () => Saver;
  SAVE_WINDOW_MS: number;
}

const COMPARE = 'markdownWorkbench.compareWithClipboard';

test('every candidate change is saved at once into memory, with a growing mtime', async () => {
  const { vscode, run } = await setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await opened(run(COMPARE));
  const store = pageStore(vscode);
  const before = store.stat(session.candidateUri).mtime;
  const doc = pageDoc(vscode, session.candidateUri);
  await setText(vscode, doc, 'cand edited\n');
  await setText(vscode, doc, 'cand edited twice\n');
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  // The second change lands inside the first save, which writes it too.
  assert.ok(doc.saves >= 1);
  assert.strictEqual(doc.isDirty, false);
  assert.strictEqual(store.textOf(session.candidateUri), 'cand edited twice\n');
  assert.ok(store.stat(session.candidateUri).mtime >= before + 2);
  assert.strictEqual(
    vscode._fsWrites.length,
    0,
    'nothing through workspace.fs',
  );
});

test('a failed save is reported without the page content', async () => {
  const { vscode, run } = await setup('base\n');
  vscode._clipboard = 'SECRET-CONTENT';
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  doc.onSave = async () => false;
  await setText(vscode, doc, 'SECRET-CONTENT 2');
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._warnings.length, 1);
  assert.ok(!String(nth(vscode._warnings, 0).message).includes('SECRET'));
  doc.onSave = () => Promise.reject(new Error('SECRET-CONTENT in an error'));
  await setText(vscode, doc, 'SECRET-CONTENT 3');
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._warnings.length, 2);
  assert.ok(!String(nth(vscode._warnings, 1).message).includes('SECRET'));
});

test('the focused primary page is saved without the save participants', async () => {
  const { vscode, run } = await setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  vscode.window.activeTextEditor = new vscode.MockEditor(doc); // typing in the candidate
  let participants = 0;
  vscode._saveParticipant = () => {
    participants++;
  };
  await setText(vscode, doc, 'cand edited\n');
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._savedWithoutFormatting, 1);
  assert.strictEqual(participants, 0);
  assert.strictEqual(doc.isDirty, false);
});

test('typing on the focused selection page (left side of the diff) is saved without the save participants', async () => {
  const { vscode, file, run } = await setup('one \ntwo\n', {
    selections: [[0, 0, 1, 3]],
  });
  vscode._clipboard = 'x';
  const session = await opened(run(COMPARE));
  const page = pageDoc(vscode, session.baselineUri);
  vscode.window.activeTextEditor = new vscode.MockEditor(page);
  let participants = 0;
  vscode._saveParticipant = () => {
    participants++;
  };
  const edit = new vscode.WorkspaceEdit();
  edit.insert(page.uri, new vscode.Position(1, 3), '!');
  await vscode.workspace.applyEdit(edit);
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._savedWithoutFormatting, 1);
  assert.strictEqual(participants, 0);
  assert.strictEqual(page.isDirty, false);
  assert.strictEqual(file.getText(), 'one \ntwo!\n');
});

test('a document.save resolving false because typing went on is no failure: saved again, no warning', async () => {
  const { vscode, run } = await setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  const write = doc.onSave;
  if (!write) throw new TypeError('the page has no save handler');
  let once = true;
  doc.onSave = async (d) => {
    if (!once) return write(d);
    once = false;
    await setText(vscode, d, 'typed on\n'); // a newer version during the save
    return false;
  };
  await setText(vscode, doc, 'cand edited\n');
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._warnings.length, 0);
  assert.strictEqual(doc.saves, 2);
  assert.strictEqual(doc.isDirty, false);
  assert.strictEqual(
    pageStore(vscode).textOf(session.candidateUri),
    'typed on\n',
  );
});

test('save-action edits on the selection page never reach the file (not focused: document.save)', async () => {
  const { vscode, file, run } = await setup('one \ntwo\n', {
    selections: [[0, 0, 1, 3]],
  });
  vscode._clipboard = 'x';
  const session = await opened(run(COMPARE));
  const page = pageDoc(vscode, session.baselineUri);
  // A save participant like files.trimTrailingWhitespace.
  vscode._saveParticipant = async (d: MockDocument) => {
    if (d !== page || !/ \n/.test(d.getText())) return;
    await setText(vscode, d, d.getText().replace(/ +\n/g, '\n'));
  };
  const edit = new vscode.WorkspaceEdit();
  edit.insert(page.uri, new vscode.Position(1, 3), '!');
  await vscode.workspace.applyEdit(edit);
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(
    page.getText(),
    'one\ntwo!',
    'the participant trimmed the page',
  );
  assert.strictEqual(
    file.getText(),
    'one \ntwo!\n',
    'the user edit arrived, the trim did not',
  );
  assert.strictEqual(page.isDirty, false);
});

test('an edit arriving during a document.save is saved right after it', async () => {
  const { vscode, run } = await setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  let once = true;
  // After the write, before did-save: the running save does not carry it.
  vscode._afterWrite = async (d) => {
    if (!once) return;
    once = false;
    await setText(vscode, d, 'typed during the save\n');
  };
  await setText(vscode, doc, 'cand edited\n');
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(doc.isDirty, false);
  assert.strictEqual(
    pageStore(vscode).textOf(session.candidateUri),
    'typed during the save\n',
  );
});

test('typing during the save on the selection page reaches the file, the save action does not', async () => {
  const { vscode, file, run } = await setup('one \ntwo\n', {
    selections: [[0, 0, 1, 3]],
  });
  vscode._clipboard = 'x';
  const session = await opened(run(COMPARE));
  const page = pageDoc(vscode, session.baselineUri);
  vscode._saveParticipant = async (d: MockDocument) => {
    if (/ \n/.test(d.getText()))
      await setText(vscode, d, d.getText().replace(/ +\n/g, '\n'));
  };
  let once = true;
  vscode._afterWrite = async (d) => {
    if (!once) return;
    once = false;
    const typed = new vscode.WorkspaceEdit();
    typed.insert(d.uri, d.positionAt(d.getText().length), '?');
    await vscode.workspace.applyEdit(typed);
  };
  const edit = new vscode.WorkspaceEdit();
  edit.insert(page.uri, new vscode.Position(1, 3), '!');
  await vscode.workspace.applyEdit(edit);
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(page.getText(), 'one\ntwo!?');
  assert.strictEqual(file.getText(), 'one \ntwo!?\n', 'typed, not trimmed');
  assert.strictEqual(page.isDirty, false);
});

test('a failed save of the focused page warns once and does not retry', async () => {
  const { vscode, run } = await setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  vscode.window.activeTextEditor = new vscode.MockEditor(doc);
  doc.onSave = () => Promise.resolve(false);
  await setText(vscode, doc, 'cand edited\n');
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._savedWithoutFormatting, 1, 'one attempt');
  assert.strictEqual(
    vscode._warnings.filter((w) => /could not keep/.test(String(w.message)))
      .length,
    1,
  );
});

test('a save window VS Code opened expires when no did-save follows', async () => {
  install();
  const { PageSaver, SAVE_WINDOW_MS } = await loadFresh<SavingModule>(
    'src/clipboard-diff/saving.ts',
  );
  const saver = new PageSaver();
  const doc = { uri: makeUri(SCHEME, '/1/a.md') };
  const opened = (since: number) => ({ since, own: false });
  saver.saving.set(doc.uri.toString(), opened(Date.now()));
  assert.strictEqual(saver.isSaving(doc), true);
  saver.saving.set(doc.uri.toString(), opened(Date.now() - SAVE_WINDOW_MS - 1));
  assert.strictEqual(saver.isSaving(doc), false);
});

test('an own document.save outlasting SAVE_WINDOW_MS keeps its save actions out of the file', async (t) => {
  const { vscode, file, run } = await setup('one \ntwo\n', {
    selections: [[0, 0, 1, 3]],
  });
  const { SAVE_WINDOW_MS } = await loadFresh<SavingModule>(
    'src/clipboard-diff/saving.ts',
  );
  vscode._clipboard = 'x';
  const session = await opened(run(COMPARE));
  const page = pageDoc(vscode, session.baselineUri);
  const now = Date.now();
  // A slow save participant (a formatter): it trims only after the window.
  vscode._saveParticipant = async (d: MockDocument) => {
    if (d !== page || !/ \n/.test(d.getText())) return;
    t.mock.method(Date, 'now', () => now + SAVE_WINDOW_MS + 1);
    await setText(vscode, d, d.getText().replace(/ +\n/g, '\n'));
  };
  const edit = new vscode.WorkspaceEdit();
  edit.insert(page.uri, new vscode.Position(1, 3), '!');
  await vscode.workspace.applyEdit(edit);
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(page.getText(), 'one\ntwo!', 'the participant trimmed');
  assert.strictEqual(
    file.getText(),
    'one \ntwo!\n',
    'the late save action stayed on the page',
  );
});

test('will-save of an own document.save keeps its window open: a later will-save edit stays off the file', async (t) => {
  const { vscode, file, run } = await setup('one \ntwo\n', {
    selections: [[0, 0, 1, 3]],
  });
  const { SAVE_WINDOW_MS } = await loadFresh<SavingModule>(
    'src/clipboard-diff/saving.ts',
  );
  vscode._clipboard = 'x';
  const session = await opened(run(COMPARE));
  const page = pageDoc(vscode, session.baselineUri);
  const now = Date.now();
  // Another extension's will-save listener: it edits the page late, after
  // the saver's own will-save listener ran.
  vscode.workspace.onWillSaveTextDocument((e) => {
    if (e.document !== page || !/ \n/.test(page.getText())) return;
    e.waitUntil(
      (async () => {
        t.mock.method(Date, 'now', () => now + SAVE_WINDOW_MS + 1);
        await setText(vscode, page, page.getText().replace(/ +\n/g, '\n'));
      })(),
    );
  });
  const edit = new vscode.WorkspaceEdit();
  edit.insert(page.uri, new vscode.Position(1, 3), '!');
  await vscode.workspace.applyEdit(edit);
  for (let i = 0; i < 10; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(page.getText(), 'one\ntwo!', 'the listener trimmed');
  assert.strictEqual(
    file.getText(),
    'one \ntwo!\n',
    'the late will-save edit stayed on the page',
  );
});
