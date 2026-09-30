// Registration, context keys and the raw/aligned style switch of the clipboard
// diff on the vscode mock.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  anyMessage,
  opened,
  pageDoc,
  pageStore,
  setText,
  setup,
  SCHEME,
} from '../helpers/clipboard-diff-setup.ts';
import { nth } from '../helpers/nth.ts';
import { defined } from '../helpers/vscode-mock.ts';

const COMPARE = 'markdownWorkbench.compareWithClipboard';
const ALIGN = 'markdownWorkbench.alignCandidateStyle';
const RAW = 'markdownWorkbench.showRawCandidate';

test('registers the file system, the commands and the quick-fix provider', async () => {
  const { vscode } = await setup('a\n');
  assert.ok(pageStore(vscode));
  for (const id of [
    COMPARE,
    'markdownWorkbench.compareWithEarlierClipboard',
    'markdownWorkbench.swapDiffSides',
    'markdownWorkbench.applyCandidate',
    ALIGN,
    RAW,
  ]) {
    assert.strictEqual(
      typeof defined(vscode._commands, 'commands')[id],
      'function',
      id,
    );
  }
  assert.deepStrictEqual(nth(vscode._codeActionProviders, 0).selector, {
    scheme: SCHEME,
  });
});

test('the context keys follow the active clipboard diff and its style state', async () => {
  const { vscode, run, focusFile, tick } = await setup('- a\n- b\n');
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
  const { vscode, run } = await setup('- a\n- b\n\n*x* and **y**\n');
  vscode._clipboard = '* a\n* b\n* c\n\n_x_ and __y__ and `_code_`\n';
  const session = await opened(run(COMPARE));
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
  const { vscode, run } = await setup('- a\n');
  vscode._clipboard = '* a\n* b\n';
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  await setText(vscode, doc, '* a\n* b edited\n');
  vscode._warningResult = undefined;
  assert.strictEqual(await run(ALIGN), false);
  assert.strictEqual(doc.getText(), '* a\n* b edited\n');
  assert.match(
    String(defined(vscode._warnings.at(-1), 'a warning').message),
    /discards the edits/,
  );
  vscode._warningResult = 'Discard Edits';
  assert.strictEqual(await run(ALIGN), true);
  assert.strictEqual(doc.getText(), '- a\n- b\n');
});

test('the style switch keeps the file around an anchored section', async () => {
  const { vscode, run } = await setup('# T\n\n- x\n\n## S\n\n- s\n');
  vscode._clipboard = '## S\n\n* s\n* t\n';
  const session = await opened(run(COMPARE));
  await run(ALIGN);
  assert.strictEqual(
    pageDoc(vscode, session.candidateUri).getText(),
    '# T\n\n- x\n\n## S\n\n- s\n- t\n',
  );
});

test('an already matching candidate says so and stays', async () => {
  const { vscode, run } = await setup('- a\n');
  vscode._clipboard = '- b\n';
  await run(COMPARE);
  await run(ALIGN);
  assert.ok(anyMessage(vscode._statusMessages, /already matches/));
});

test('the style switch outside a clipboard diff says so', async () => {
  const { vscode, run } = await setup('- a\n');
  assert.strictEqual(await run(ALIGN), false);
  assert.ok(anyMessage(vscode._infos, /only be switched in a clipboard diff/));
});

test('a refused style switch keeps the state and says so', async () => {
  const { vscode, run } = await setup('- a\n');
  vscode._clipboard = '* a\n* b\n';
  const session = await opened(run(COMPARE));
  vscode._applyEditResult = false;
  assert.strictEqual(await run(ALIGN), false);
  assert.strictEqual(session.styled, false);
  assert.ok(
    anyMessage(
      vscode._warnings.map((w) => w.message),
      /could not switch the candidate style/,
    ),
  );
});
