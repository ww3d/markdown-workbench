// "Compare with Clipboard" through the registered command on the vscode mock:
// baseline choice (file, selection, hull, anchor), page names, line endings,
// the no-title diff call and the refusal paths.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  anyMessage,
  expectDiff,
  lastDiff,
  opened,
  pageDoc,
  pageStore,
  quickPickItems,
  setup,
  SCHEME,
} from '../helpers/clipboard-diff-setup.ts';
import type { PickItem } from '../helpers/clipboard-diff-setup.ts';
import {
  defined,
  makeUri,
  MockDocument,
  MockEditor,
  Range,
  TabInputTextDiff,
} from '../helpers/vscode-mock.ts';

const COMPARE = 'markdownWorkbench.compareWithClipboard';

test('without a selection or anchor hit the live file is the baseline, the diff has no title', async () => {
  const { vscode, file, run } = await setup('# Notes\n\nalpha\nbeta\n');
  vscode._clipboard = 'something else entirely\n';
  const session = await opened(run(COMPARE));
  const diff = expectDiff(vscode);
  assert.strictEqual(
    diff.left,
    file.uri,
    'baseline is the file URI itself, no snapshot',
  );
  assert.strictEqual(diff.right.scheme, SCHEME);
  assert.strictEqual(diff.title, undefined, 'no title argument');
  assert.strictEqual(diff.right.path.split('/').pop(), 'notes (Candidate).md');
  assert.strictEqual(session.shape, 'file');
  assert.strictEqual(
    pageDoc(vscode, diff.right).getText(),
    'something else entirely\n',
  );
});

test('a non-empty selection becomes a (Selection) page with the selected text', async () => {
  const { vscode, run } = await setup('one\ntwo\nthree\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  const session = await opened(run(COMPARE));
  const diff = expectDiff(vscode);
  assert.strictEqual(session.shape, 'page');
  assert.strictEqual(diff.left.path.split('/').pop(), 'notes (Selection).md');
  assert.strictEqual(pageDoc(vscode, diff.left).getText(), 'two');
  assert.strictEqual(pageDoc(vscode, diff.right).getText(), 'TWO');
});

test('several selections are combined into their hull, in document order, with a note', async () => {
  const { vscode, run } = await setup('a1\nb2\nc3\nd4\n', {
    selections: [
      [2, 0, 2, 2],
      [0, 0, 0, 2],
      [1, 1, 1, 1], // empty selections do not count
    ],
  });
  vscode._clipboard = 'x';
  await run(COMPARE);
  const diff = expectDiff(vscode);
  assert.strictEqual(pageDoc(vscode, diff.left).getText(), 'a1\nb2\nc3');
  assert.ok(
    defined(vscode._infos, 'info messages').includes(
      '2 selections combined into one range.',
    ),
  );
});

test('an empty clipboard opens no diff and says so', async () => {
  const { vscode, run } = await setup('text');
  vscode._clipboard = '';
  assert.strictEqual(await run(COMPARE), undefined);
  assert.strictEqual(lastDiff(vscode), undefined);
  assert.ok(anyMessage(vscode._infos, /clipboard is empty/));
});

test('a non-text active tab opens no diff and says so', async () => {
  const { vscode, run } = await setup('text');
  vscode._openTab({ viewType: 'someWebview' }); // e.g. a webview panel
  vscode._clipboard = 'x';
  assert.strictEqual(await run(COMPARE), undefined);
  assert.ok(anyMessage(vscode._infos, /needs an active text editor/));
  vscode.window.activeTextEditor = undefined;
  assert.strictEqual(await run(COMPARE), undefined);
  assert.strictEqual(lastDiff(vscode), undefined);
});

test('an untitled baseline works; the candidate takes its language', async () => {
  const { vscode, run } = await setup('draft line\n', {
    scheme: 'untitled',
    path: 'Untitled-1',
  });
  vscode._clipboard = 'new draft\n';
  const session = await opened(run(COMPARE));
  const diff = expectDiff(vscode);
  assert.strictEqual(
    diff.right.path.split('/').pop(),
    'Untitled-1 (Candidate)',
  );
  assert.strictEqual(
    pageDoc(vscode, diff.right).languageId,
    session.languageId,
  );
});

test('the candidate takes the baseline language even when it differs from the name', async () => {
  const { vscode, file, run } = await setup('x\n');
  file.languageId = 'plaintext';
  vscode._clipboard = 'y\n';
  await run(COMPARE);
  assert.strictEqual(
    pageDoc(vscode, expectDiff(vscode).right).languageId,
    'plaintext',
  );
});

test('clipboard line endings are aligned with the baseline (CRLF)', async () => {
  const { vscode, file, run } = await setup('a\nb\n');
  file.eol = vscode.EndOfLine.CRLF;
  vscode._clipboard = 'x\ny\n';
  const session = await opened(run(COMPARE));
  const store = pageStore(vscode);
  assert.strictEqual(store.textOf(session.candidateUri), 'x\r\ny\r\n');
});

test('clipboard CRLF is turned into LF for an LF baseline', async () => {
  const { vscode, run } = await setup('a\nb\n');
  vscode._clipboard = 'x\r\ny\r\n';
  const session = await opened(run(COMPARE));
  assert.strictEqual(pageStore(vscode).textOf(session.candidateUri), 'x\ny\n');
});

test('a heading-led clipboard anchors to its section: file shape, span selected, note', async () => {
  const text = '# Doc\n\nintro\n\n## Setup\n\nold step\n\n## Usage\n\nuse it\n';
  const { vscode, run } = await setup(text);
  vscode._clipboard = '## Setup\n\nnew step\n';
  const session = await opened(run(COMPARE));
  const diff = expectDiff(vscode);
  assert.strictEqual(session.shape, 'file');
  assert.strictEqual(
    pageDoc(vscode, diff.right).getText(),
    '# Doc\n\nintro\n\n## Setup\n\nnew step\n\n## Usage\n\nuse it\n',
  );
  assert.ok(
    typeof diff.options === 'object' &&
      diff.options !== null &&
      'selection' in diff.options &&
      diff.options.selection instanceof Range,
    'the options carry the selection',
  );
  assert.deepStrictEqual(
    [diff.options.selection.start.line, diff.options.selection.end.line],
    [4, 6],
    'the diff opens with the anchored span selected',
  );
  assert.ok(
    defined(vscode._infos, 'info messages').includes(
      'Compared with lines 5-7 (matching heading).',
    ),
  );
});

test('an ambiguous anchor asks with a QuickPick that offers the whole file', async () => {
  const text = '## Part\n\nsame\n\n## Part\n\nsame\n';
  const { vscode, run } = await setup(text);
  vscode._clipboard = '## Part\n\nother\n';
  vscode._quickPickResult = (items: PickItem[]) =>
    items.find((i) => i.label === 'Whole file');
  const session = await opened(run(COMPARE));
  const labels = quickPickItems(vscode, 0).map((i) => i.label);
  assert.deepStrictEqual(labels, ['Lines 1-3', 'Lines 5-7', 'Whole file']);
  assert.deepStrictEqual(
    [session.region.start, session.region.end],
    [0, text.length],
  );
});

test('dismissing the anchor QuickPick opens no diff', async () => {
  const { vscode, run } = await setup('## Part\n\nsame\n\n## Part\n\nsame\n');
  vscode._clipboard = '## Part\n\nother\n';
  vscode._quickPickResult = undefined;
  assert.strictEqual(await run(COMPARE), undefined);
  assert.strictEqual(lastDiff(vscode), undefined);
});

test('an AI answer is unwrapped before it becomes the candidate', async () => {
  const { vscode, run } = await setup('# A\n\ntext\n');
  vscode._clipboard =
    'Sure, here is the file:\n\n```markdown\n# A\n\nbetter text\n```\n';
  const session = await opened(run(COMPARE));
  assert.strictEqual(
    pageStore(vscode).textOf(session.candidateUri),
    '# A\n\nbetter text\n',
  );
  assert.ok(anyMessage(vscode._statusMessages, /unwrapped/));
});

test('the compared clipboard text lands in the session history', async () => {
  const { vscode, run, focusFile } = await setup('a\n');
  vscode._clipboard = 'first';
  await run(COMPARE);
  focusFile();
  vscode._clipboard = 'second';
  await run(COMPARE);
  focusFile();
  vscode._quickPickResult = (items: PickItem[]) => items[1];
  await run('markdownWorkbench.compareWithEarlierClipboard');
  const items = quickPickItems(vscode);
  assert.deepStrictEqual(
    items.map((i) => i.label),
    ['second', 'first'],
  );
  assert.ok(
    items.every((i) => i.description && /1 lines/.test(i.detail ?? '')),
  );
  assert.strictEqual(
    pageDoc(vscode, expectDiff(vscode).right).getText(),
    'first',
  );
});

test('Compare with Earlier Clipboard without history says so', async () => {
  const { vscode, run } = await setup('a\n');
  assert.strictEqual(
    await run('markdownWorkbench.compareWithEarlierClipboard'),
    undefined,
  );
  assert.ok(anyMessage(vscode._infos, /No clipboard text/));
});

test('Compare from inside a diff (not a plain text editor) is refused', async () => {
  const { vscode, run } = await setup('a\n');
  vscode._openTab(
    new TabInputTextDiff(makeUri('file', '/a'), makeUri('file', '/b')),
  );
  vscode.window.activeTextEditor = new MockEditor(new MockDocument('b'));
  vscode._clipboard = 'x';
  assert.strictEqual(await run(COMPARE), undefined);
});

test('a clipboard of whitespace only is empty too', async () => {
  const { vscode, run } = await setup('text');
  vscode._clipboard = '  \n\t\n';
  assert.strictEqual(await run(COMPARE), undefined);
  assert.ok(anyMessage(vscode._infos, /clipboard is empty/));
});

test('a single chat-like line is compared as content, not unwrapped to nothing', async () => {
  const { vscode, run } = await setup('text\n');
  vscode._clipboard = 'OK\n';
  const session = await opened(run(COMPARE));
  assert.strictEqual(pageStore(vscode).textOf(session.candidateUri), 'OK\n');
});

test('focus in an editor that is not the active tab (e.g. a panel) is refused', async () => {
  const { vscode, run } = await setup('a\n');
  vscode.window.activeTextEditor = new MockEditor(
    new MockDocument('panel output', makeUri('output', '/log')),
  );
  vscode._clipboard = 'x';
  assert.strictEqual(await run(COMPARE), undefined);
  assert.ok(anyMessage(vscode._infos, /needs an active text editor/));
});
