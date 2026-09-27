// Page lifecycle on the vscode mock: immediate save of every page change, the
// selection page mirrored both ways, release once no tab shows a diff, and no
// clipboard text in logs, messages or persisted state.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  setup,
  pageDoc,
  lastDiff,
  setText,
  SCHEME,
} = require('../helpers/clipboard-diff-setup');
const { TabInputText, makeUri } = require('../helpers/vscode-mock');

const COMPARE = 'markdownWorkbench.compareWithClipboard';

test('every candidate change is saved at once into memory, with a growing mtime', async () => {
  const { vscode, run } = setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await run(COMPARE);
  const store = vscode._fsProviders[SCHEME];
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
  const { vscode, run } = setup('base\n');
  vscode._clipboard = 'SECRET-CONTENT';
  const session = await run(COMPARE);
  const doc = pageDoc(vscode, session.candidateUri);
  doc.onSave = async () => false;
  await setText(vscode, doc, 'SECRET-CONTENT 2');
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._warnings.length, 1);
  assert.ok(!vscode._warnings[0].message.includes('SECRET'));
  doc.onSave = () => Promise.reject(new Error('SECRET-CONTENT in an error'));
  await setText(vscode, doc, 'SECRET-CONTENT 3');
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(vscode._warnings.length, 2);
  assert.ok(!vscode._warnings[1].message.includes('SECRET'));
});

test('changes to files outside the scheme are never saved by the extension', async () => {
  const { vscode, file, run } = setup('base\n');
  vscode._clipboard = 'x';
  await run(COMPARE);
  await setText(vscode, file, 'edited\n');
  assert.strictEqual(file.saves, 0);
});

test('an edit of the selection page writes through into the file region', async () => {
  const { vscode, file, run } = setup('one\ntwo\nthree\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  const session = await run(COMPARE);
  await setText(vscode, pageDoc(vscode, session.baselineUri), 'Two!');
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(file.getText(), 'one\nTwo!\nthree\n');
  assert.strictEqual(
    session.region.touched,
    false,
    'our own write-through is not a foreign change',
  );
});

test('a user edit inside the region is mirrored into the selection page', async () => {
  const { vscode, file, run } = setup('one\ntwo\nthree\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  const session = await run(COMPARE);
  const edit = new vscode.WorkspaceEdit();
  edit.insert(file.uri, new vscode.Position(1, 1), 'w');
  await vscode.workspace.applyEdit(edit);
  await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(pageDoc(vscode, session.baselineUri).getText(), 'twwo');
  assert.strictEqual(session.region.touched, true);
});

test('the pages are released once no tab shows the diff, and on deactivate', async () => {
  const { vscode, cd, run, tick } = setup('one\n', {
    selections: [[0, 0, 0, 3]],
  });
  vscode._clipboard = 'ONE';
  const session = await run(COMPARE);
  const store = vscode._fsProviders[SCHEME];
  assert.ok(store.has(session.candidateUri) && store.has(session.baselineUri));
  // The mock swap closes the tab and opens the swapped one a microtask later,
  // like VS Code: the deferred lifecycle check must keep the pages.
  await run('markdownWorkbench.swapDiffSides');
  await tick();
  assert.ok(store.has(session.candidateUri));
  await vscode._closeTab(vscode.window.tabGroups.activeTabGroup.activeTab);
  await tick();
  assert.ok(
    !store.has(session.candidateUri) && !store.has(session.baselineUri),
  );
  vscode._clipboard = 'AGAIN';
  vscode._openTab(
    new TabInputText(vscode.window.activeTextEditor.document.uri),
  );
  const second = await run(COMPARE);
  cd.deactivateClipboardDiff();
  assert.ok(!store.has(second.candidateUri));
});

test('a page kept open alone (candidate tab) keeps its content; an orphan copy is freed', async () => {
  const { vscode, run, tick } = setup('one\n');
  vscode._clipboard = 'ONE';
  const session = await run(COMPARE);
  const store = vscode._fsProviders[SCHEME];
  const saveAsCopy = makeUri(SCHEME, '/99/copy.md');
  store.writeFile(saveAsCopy, Buffer.from('copy'), {
    create: true,
    overwrite: true,
  });
  await vscode._closeTab(vscode.window.tabGroups.activeTabGroup.activeTab);
  vscode._openTab(new TabInputText(session.candidateUri));
  await tick();
  assert.ok(store.has(session.candidateUri));
  assert.ok(!store.has(saveAsCopy));
});

test('restored pages of an earlier window are closed on activation', async () => {
  const {
    install,
    loadFresh,
    TabInputTextDiff,
  } = require('../helpers/vscode-mock');
  const vscode = install();
  vscode._openTab(
    new TabInputTextDiff(
      makeUri('file', '/ws/a.md'),
      makeUri(SCHEME, '/1/a (Candidate).md'),
    ),
  );
  vscode._openTab(new TabInputText(makeUri('file', '/ws/b.md')));
  loadFresh('src/clipboard-diff/index.js').registerClipboardDiff({
    subscriptions: [],
  });
  await new Promise((r) => setTimeout(r, 0));
  const left = vscode.window.tabGroups.all[0].tabs.map(
    (t) => t.input.uri?.path ?? 'diff',
  );
  assert.deepStrictEqual(left, ['/ws/b.md']);
});

test('no clipboard text reaches a log, a message or persisted state', async () => {
  const marker = 'CLIPBOARD-MARKER-7f3a';
  const logged = [];
  const saved = { console: {} };
  for (const k of ['log', 'info', 'warn', 'error', 'debug']) {
    saved.console[k] = console[k];
    console[k] = (...a) => logged.push(a.join(' '));
  }
  try {
    const { vscode, context, run } = setup('# A\n\n- [x] one\n', {
      selections: [[2, 0, 2, 9]],
    });
    const state = { update: () => assert.fail('no persisted state') };
    context.globalState = state;
    context.workspaceState = state;
    vscode._clipboard = `- [ ] one ${marker}\n… rest unchanged …`;
    await run(COMPARE);
    vscode._warningResult = 'Apply';
    await run('markdownWorkbench.applyCandidate');
    await run('markdownWorkbench.swapDiffSides');
    await run('markdownWorkbench.alignCandidateStyle');
    const texts = [
      ...logged,
      ...(vscode._infos || []),
      ...vscode._errors,
      ...vscode._statusMessages,
      ...vscode._warnings.map((w) => w.message),
    ];
    assert.ok(texts.length > 0, 'the flow did produce messages');
    for (const t of texts) assert.ok(!t.includes(marker), t);
  } finally {
    Object.assign(console, saved.console);
  }
});

test('swapping twice restores the original orientation', async () => {
  const { vscode, run } = setup('a\n');
  vscode._clipboard = 'b\n';
  await run(COMPARE);
  const diff = lastDiff(vscode);
  const active = () => vscode.window.tabGroups.activeTabGroup.activeTab;
  await run('markdownWorkbench.swapDiffSides');
  assert.strictEqual(active().input.original, diff.right);
  await run('markdownWorkbench.swapDiffSides');
  assert.strictEqual(active().input.original, diff.left);
  assert.strictEqual(active().input.modified, diff.right);
});

test('Swap Diff Sides uses the built-in command for any text diff and reports failures', async () => {
  const { vscode, run } = setup('a\n');
  const { TabInputTextDiff } = require('../helpers/vscode-mock');
  vscode._openTab(
    new TabInputTextDiff(makeUri('foreign', '/x'), makeUri('foreign', '/y')),
  );
  assert.strictEqual(await run('markdownWorkbench.swapDiffSides'), true);
  assert.ok(
    vscode._executed.some(
      (e) => e.id === 'workbench.action.compareEditor.swapSides',
    ),
  );
  vscode._commandHandlers['workbench.action.compareEditor.swapSides'] = () => {
    throw new Error('command not found');
  };
  assert.strictEqual(await run('markdownWorkbench.swapDiffSides'), false);
  assert.match(
    vscode._errors[0],
    /could not swap the diff sides: command not found/,
  );
});

test('a swap VS Code silently skips is reported, not claimed', async () => {
  const { vscode, run } = setup('a\n');
  const { TabInputTextDiff } = require('../helpers/vscode-mock');
  vscode._openTab(
    new TabInputTextDiff(makeUri('foreign', '/x'), makeUri('foreign', '/y')),
  );
  vscode._commandHandlers['workbench.action.compareEditor.swapSides'] =
    () => {}; // no-op
  assert.strictEqual(await run('markdownWorkbench.swapDiffSides'), false);
  assert.match(vscode._warnings.at(-1).message, /did not swap this diff/);
});

test('Swap Diff Sides outside a text diff says so', async () => {
  const { vscode, run } = setup('a\n');
  assert.strictEqual(await run('markdownWorkbench.swapDiffSides'), false);
  assert.ok(vscode._infos.some((m) => /needs an active text diff/.test(m)));
});

test('the lifecycle check waits for the two-step swap (the tab is gone for a moment)', async () => {
  const { vscode, run } = setup('one\n');
  vscode._clipboard = 'ONE';
  const session = await run(COMPARE);
  const store = vscode._fsProviders[SCHEME];
  await run('markdownWorkbench.swapDiffSides');
  await new Promise((r) => setTimeout(r, 10));
  assert.ok(store.has(session.candidateUri), 'kept across the swap');
});

test('a diff in a second editor group is kept and found there', async () => {
  const { vscode, run, tick } = setup('one\n');
  vscode._addGroup();
  vscode._openTab(
    new TabInputText(vscode.window.activeTextEditor.document.uri),
  );
  vscode._clipboard = 'ONE';
  const session = await run(COMPARE);
  vscode.window.tabGroups.activeTabGroup = vscode.window.tabGroups.all[0];
  await vscode._closeTab(vscode.window.tabGroups.all[0].tabs[0]);
  await tick();
  assert.ok(
    vscode._fsProviders[SCHEME].has(session.candidateUri),
    'group 2 still shows it',
  );
  assert.strictEqual(
    vscode.window.tabGroups.all[1].activeTab.input.modified,
    session.candidateUri,
  );
});

test('a diff that is still opening is never released by a tab change', async () => {
  const { vscode, run, tick } = setup('one\n');
  vscode._clipboard = 'ONE';
  vscode._commandHandlers['vscode.diff'] = async () => {
    vscode._openTab(new TabInputText(makeUri('file', '/ws/other.md'))); // an unrelated tab change
    await tick();
  };
  const session = await run(COMPARE);
  assert.ok(vscode._fsProviders[SCHEME].has(session.candidateUri));
  assert.strictEqual(session.opening, false);
});

test('the focused primary page is saved without the save participants', async () => {
  const { vscode, run } = setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await run(COMPARE);
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

test('save-action edits on the selection page never reach the file (not focused: document.save)', async () => {
  const { vscode, file, run } = setup('one \ntwo\n', {
    selections: [[0, 0, 1, 3]],
  });
  vscode._clipboard = 'x';
  const session = await run(COMPARE);
  const page = pageDoc(vscode, session.baselineUri);
  // A save participant like files.trimTrailingWhitespace.
  vscode._saveParticipant = async (d) => {
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
  const { vscode, run } = setup('base\n');
  vscode._clipboard = 'cand\n';
  const session = await run(COMPARE);
  const doc = pageDoc(vscode, session.candidateUri);
  let once = true;
  vscode._saveParticipant = async (d) => {
    if (!once) return;
    once = false;
    await setText(vscode, d, 'typed during the save\n');
  };
  await setText(vscode, doc, 'cand edited\n');
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(doc.isDirty, false);
  assert.strictEqual(
    vscode._fsProviders[SCHEME].textOf(session.candidateUri),
    'typed during the save\n',
  );
});

test('a refused write-through is reported', async () => {
  const { vscode, run } = setup('one\n', { selections: [[0, 0, 0, 3]] });
  vscode._clipboard = 'ONE';
  const session = await run(COMPARE);
  vscode._applyEditResult = false;
  const page = pageDoc(vscode, session.baselineUri);
  page.lines = ['one!'];
  vscode._fireDocChange({
    document: page,
    contentChanges: [{ rangeOffset: 3, rangeLength: 0, text: '!' }],
  });
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.ok(vscode._warnings.some((w) => /could not sync/.test(w.message)));
});

test('file edits outside an anchored section follow into the candidate', async () => {
  const { vscode, file, run } = setup('# A\n\na\n\n## B\n\nb\n');
  vscode._clipboard = '## B\n\nB2\n';
  const session = await run(COMPARE);
  const cand = pageDoc(vscode, session.candidateUri);
  const edit = new vscode.WorkspaceEdit();
  edit.insert(file.uri, new vscode.Position(2, 1), ' more');
  await vscode.workspace.applyEdit(edit);
  for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  assert.strictEqual(cand.getText(), '# A\n\na more\n\n## B\n\nB2\n');
  assert.strictEqual(session.prefix, '# A\n\na more\n\n');
  assert.strictEqual(session.region.touched, false);
});

test('an emptied selection page keeps writing into the same place', async () => {
  const { vscode, file, run } = setup('xxHELLOyy\n', {
    selections: [[0, 2, 0, 7]],
  });
  vscode._clipboard = 'x';
  const session = await run(COMPARE);
  const page = pageDoc(vscode, session.baselineUri);
  const tickAll = async () => {
    for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
  };
  await setText(vscode, page, '');
  await tickAll();
  const e1 = new vscode.WorkspaceEdit();
  e1.insert(page.uri, new vscode.Position(0, 0), 'a');
  await vscode.workspace.applyEdit(e1);
  await tickAll();
  const e2 = new vscode.WorkspaceEdit();
  e2.insert(page.uri, new vscode.Position(0, 1), 'b');
  await vscode.workspace.applyEdit(e2);
  await tickAll();
  assert.strictEqual(file.getText(), 'xxabyy\n');
  assert.deepStrictEqual([session.region.start, session.region.end], [2, 4]);
});
