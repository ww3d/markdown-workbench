// "Apply Candidate" on the vscode mock: one edit into the tracked region,
// the stale-region question, placeholder filling and the Markdown check
// (hints, never a block).
const { test } = require('node:test');
const assert = require('node:assert');
const {
  setup,
  pageDoc,
  lastDiff,
  setText,
} = require('../helpers/clipboard-diff-setup');

const COMPARE = 'markdownWorkbench.compareWithClipboard';
const APPLY = 'markdownWorkbench.applyCandidate';

function applyEdits(vscode) {
  return vscode._applied.filter((op) => op.uri.scheme === 'file');
}

test('Apply writes the candidate into the selection range as one edit', async () => {
  const { vscode, file, run } = setup('one\ntwo\nthree\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  await run(COMPARE);
  vscode._applied.length = 0;
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(file.getText(), 'one\nTWO\nthree\n');
  assert.strictEqual(
    applyEdits(vscode).length,
    1,
    'a single WorkspaceEdit op = one undo step',
  );
});

test('Apply on a whole-file diff replaces the whole file', async () => {
  const { vscode, file, run } = setup('old\n');
  vscode._clipboard = 'new text\n';
  await run(COMPARE);
  await run(APPLY);
  assert.strictEqual(file.getText(), 'new text\n');
});

test('Apply on an anchored section replaces only the section', async () => {
  const { vscode, file, run } = setup('# A\n\na\n\n## B\n\nb\n\n## C\n\nc\n');
  vscode._clipboard = '## B\n\nB2\n';
  await run(COMPARE);
  await run(APPLY);
  assert.strictEqual(file.getText(), '# A\n\na\n\n## B\n\nB2\n\n## C\n\nc\n');
});

test('the region follows edits before it (contentChanges), so Apply hits the moved text', async () => {
  const { vscode, file, run } = setup('one\ntwo\nthree\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  await run(COMPARE);
  const edit = new vscode.WorkspaceEdit();
  edit.insert(file.uri, new vscode.Position(0, 0), 'zero\n');
  await vscode.workspace.applyEdit(edit);
  await run(APPLY);
  assert.strictEqual(file.getText(), 'zero\none\nTWO\nthree\n');
  assert.strictEqual(
    vscode._warnings.length,
    0,
    'an edit outside the region asks nothing',
  );
});

test('a changed region makes Apply ask; no answer writes nothing', async () => {
  const { vscode, file, run } = setup('one\ntwo\nthree\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  await run(COMPARE);
  const edit = new vscode.WorkspaceEdit();
  edit.replace(file.uri, new vscode.Range(1, 0, 1, 1), 'T');
  await vscode.workspace.applyEdit(edit);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  assert.strictEqual(file.getText(), 'one\nTwo\nthree\n');
  assert.match(vscode._warnings[0].message, /baseline range changed/);
  assert.strictEqual(vscode._warnings[0].rest[0].modal, true);
  vscode._warningResult = 'Replace';
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(file.getText(), 'one\nTWO\nthree\n');
});

test('placeholders are filled from the baseline on Apply', async () => {
  const { vscode, file, run } = setup('a\nb\nc\nd\ne\n');
  vscode._clipboard = 'a\n… rest unchanged …\ne\nnew\n';
  vscode._quickPickResult = (items) => items.at(-1); // "Whole file"
  await run(COMPARE);
  await run(APPLY);
  assert.strictEqual(file.getText(), 'a\nb\nc\nd\ne\nnew\n');
});

test('an unclear placeholder makes Apply ask instead of guessing', async () => {
  const { vscode, file, run } = setup('x\n1\nx\n2\n');
  vscode._clipboard = 'x\n...\nnowhere\n';
  vscode._quickPickResult = (items) => items.at(-1); // "Whole file"
  await run(COMPARE);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  assert.match(
    vscode._warnings.at(-1).message,
    /placeholder line could not be matched/,
  );
  assert.strictEqual(file.getText(), 'x\n1\nx\n2\n');
  vscode._warningResult = 'Apply as Text';
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(file.getText(), 'x\n...\nnowhere\n');
});

test('check findings are hints: keeping checkbox states restores them', async () => {
  const { vscode, file, run } = setup('- [x] ship it\n- [ ] later\n');
  vscode._clipboard = '- [ ] ship it\n- [ ] later\n- [ ] new\n';
  await run(COMPARE);
  vscode._warningResult = 'Keep Checkbox States and Apply';
  assert.strictEqual(await run(APPLY), true);
  const warning = vscode._warnings.at(-1);
  assert.match(warning.rest[0].detail, /Checked task "ship it" is unchecked/);
  assert.deepStrictEqual(warning.rest.slice(1), [
    'Keep Checkbox States and Apply',
    'Apply',
  ]);
  assert.strictEqual(file.getText(), '- [x] ship it\n- [ ] later\n- [ ] new\n');
});

test('check findings never block: plain Apply writes the candidate as is', async () => {
  const { vscode, file, run } = setup(
    '---\ntitle: x\n---\n\nintro [a]\n\n[a]: https://a.example\n',
  );
  vscode._clipboard = 'no front matter, no definitions\n';
  await run(COMPARE);
  vscode._warningResult = 'Apply';
  assert.strictEqual(await run(APPLY), true);
  const detail = vscode._warnings.at(-1).rest[0].detail;
  assert.match(detail, /front matter is missing/);
  assert.match(detail, /Link reference definition \[a\] is missing/);
  assert.strictEqual(file.getText(), 'no front matter, no definitions\n');
});

test('dismissing the check writes nothing', async () => {
  const { vscode, file, run } = setup('- [x] done\n');
  vscode._clipboard = '- [ ] done\n';
  await run(COMPARE);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  assert.strictEqual(file.getText(), '- [x] done\n');
});

test('workspace-wide anchor links are read only when the setting is on', async () => {
  const { vscode, file, run, focusFile } = setup('# Doc\n\n## Target\n\nt\n');
  const other = new vscode.MockDocument('see [t](notes.md#target)\n', {
    scheme: 'file',
    path: '/ws/other.md',
    toString: () => 'file:/ws/other.md',
  });
  vscode.workspace.textDocuments.push(other);
  vscode.workspace.findFiles = async () => [other.uri, file.uri];
  vscode._clipboard = '# Doc\n\n## Renamed\n\nt\n';
  await run(COMPARE);
  vscode._warningResult = undefined;
  await run(APPLY); // setting off: no finding, applies without asking
  assert.strictEqual(vscode._warnings.length, 0);
  await setText(vscode, file, '# Doc\n\n## Target\n\nt\n');
  vscode._config['clipboardDiff.checkWorkspaceAnchors'] = true;
  vscode._clipboard = '# Doc\n\n## Renamed again\n\nt\n';
  focusFile();
  await run(COMPARE);
  assert.strictEqual(await run(APPLY), false);
  assert.match(
    vscode._warnings.at(-1).rest[0].detail,
    /#target .* \/ws\/other\.md links to it/,
  );
  assert.strictEqual(vscode._fsWrites.length, 0, 'read only');
});

test('Apply without an active clipboard diff says so', async () => {
  const { vscode, run } = setup('a\n');
  assert.strictEqual(await run(APPLY), false);
  assert.ok(
    vscode._infos.some((m) => /needs an active clipboard diff/.test(m)),
  );
});

test('Apply works from the swapped orientation too', async () => {
  const { vscode, file, run } = setup('one\n', { selections: [[0, 0, 0, 3]] });
  vscode._clipboard = 'ONE';
  await run(COMPARE);
  await run('markdownWorkbench.swapDiffSides');
  const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
  assert.ok(
    tab.input.original.path.includes('(Candidate)'),
    'candidate is on the left now',
  );
  await run(APPLY);
  assert.strictEqual(file.getText(), 'ONE\n');
  assert.strictEqual(
    pageDoc(vscode, lastDiff(vscode).left).getText(),
    'ONE',
    'selection page mirrors the result',
  );
});
