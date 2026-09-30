// Registration, context keys and the raw/aligned style switch of the clipboard
// diff on the vscode mock.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  setup,
  pageDoc,
  setText,
  SCHEME,
} = require('../helpers/clipboard-diff-setup');

const COMPARE = 'markdownWorkbench.compareWithClipboard';
const ALIGN = 'markdownWorkbench.alignCandidateStyle';
const RAW = 'markdownWorkbench.showRawCandidate';

test('registers the file system, the commands and the quick-fix provider', () => {
  const { vscode } = setup('a\n');
  assert.ok(vscode._fsProviders[SCHEME]);
  for (const id of [
    COMPARE,
    'markdownWorkbench.compareWithEarlierClipboard',
    'markdownWorkbench.swapDiffSides',
    'markdownWorkbench.applyCandidate',
    ALIGN,
    RAW,
  ]) {
    assert.strictEqual(typeof vscode._commands[id], 'function', id);
  }
  assert.deepStrictEqual(vscode._codeActionProviders[0].selector, {
    scheme: SCHEME,
  });
});

test('the own swap button stands only where VS Code shows none of its own', () => {
  // VS Code's button: textCompareEditorActive && activeCompareEditorCanSwap
  // (editor.contribution.ts); the key is false where the left side is
  // read-only, as in a Git diff (editorGroupView.ts), so one button shows.
  const manifest = require('../../package.json');
  const entry = manifest.contributes.menus['editor/title'].find(
    (m) => m.command === 'markdownWorkbench.swapDiffSides',
  );
  assert.strictEqual(
    entry.when,
    'isInDiffEditor && !activeCompareEditorCanSwap',
  );
});

test('the context keys follow the active clipboard diff and its style state', async () => {
  const { vscode, run, focusFile, tick } = setup('- a\n- b\n');
  vscode._clipboard = '* a\n* b\n* c\n';
  await run(COMPARE);
  assert.strictEqual(
    vscode._context['markdownWorkbench.clipboardDiffActive'],
    true,
  );
  assert.strictEqual(
    vscode._context['markdownWorkbench.candidateStyleAligned'],
    false,
  );
  await run(ALIGN);
  assert.strictEqual(
    vscode._context['markdownWorkbench.candidateStyleAligned'],
    true,
  );
  focusFile();
  await tick();
  assert.strictEqual(
    vscode._context['markdownWorkbench.clipboardDiffActive'],
    false,
  );
});

test('the style switch aligns the candidate to the baseline and back to raw', async () => {
  const { vscode, run } = setup('- a\n- b\n\n*x* and **y**\n');
  vscode._clipboard = '* a\n* b\n* c\n\n_x_ and __y__ and `_code_`\n';
  const session = await run(COMPARE);
  const doc = pageDoc(vscode, session.candidateUri);
  assert.strictEqual(await run(ALIGN), true);
  assert.strictEqual(
    doc.getText(),
    '- a\n- b\n- c\n\n*x* and **y** and `_code_`\n',
  );
  assert.strictEqual(await run(RAW), true);
  assert.strictEqual(
    doc.getText(),
    '* a\n* b\n* c\n\n_x_ and __y__ and `_code_`\n',
  );
});

test('the style switch asks before it discards the user edits of the candidate', async () => {
  const { vscode, run } = setup('- a\n');
  vscode._clipboard = '* a\n* b\n';
  const session = await run(COMPARE);
  const doc = pageDoc(vscode, session.candidateUri);
  await setText(vscode, doc, '* a\n* b edited\n');
  vscode._warningResult = undefined;
  assert.strictEqual(await run(ALIGN), false);
  assert.strictEqual(doc.getText(), '* a\n* b edited\n');
  assert.match(vscode._warnings.at(-1).message, /discards the edits/);
  vscode._warningResult = 'Discard Edits';
  assert.strictEqual(await run(ALIGN), true);
  assert.strictEqual(doc.getText(), '- a\n- b\n');
});

test('the style switch keeps the file around an anchored section', async () => {
  const { vscode, run } = setup('# T\n\n- x\n\n## S\n\n- s\n');
  vscode._clipboard = '## S\n\n* s\n* t\n';
  const session = await run(COMPARE);
  await run(ALIGN);
  assert.strictEqual(
    pageDoc(vscode, session.candidateUri).getText(),
    '# T\n\n- x\n\n## S\n\n- s\n- t\n',
  );
});

test('an already matching candidate says so and stays', async () => {
  const { vscode, run } = setup('- a\n');
  vscode._clipboard = '- b\n';
  await run(COMPARE);
  await run(ALIGN);
  assert.ok(vscode._statusMessages.some((m) => /already matches/.test(m)));
});

test('the style switch outside a clipboard diff says so', async () => {
  const { vscode, run } = setup('- a\n');
  assert.strictEqual(await run(ALIGN), false);
  assert.ok(
    vscode._infos.some((m) => /only be switched in a clipboard diff/.test(m)),
  );
});

test('a refused style switch keeps the state and says so', async () => {
  const { vscode, run } = setup('- a\n');
  vscode._clipboard = '* a\n* b\n';
  const session = await run(COMPARE);
  vscode._applyEditResult = false;
  assert.strictEqual(await run(ALIGN), false);
  assert.strictEqual(session.styled, false);
  assert.ok(
    vscode._warnings.some((w) =>
      /could not switch the candidate style/.test(w.message),
    ),
  );
});
