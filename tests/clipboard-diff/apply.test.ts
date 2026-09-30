// "Apply Candidate" on the vscode mock: one edit into the tracked region,
// the stale-region question, placeholder filling and the Markdown check
// (hints, never a block).
import { test } from 'node:test';
import assert from 'node:assert';
import {
  anyMessage,
  expectDiff,
  opened,
  pageDoc,
  setText,
  setup,
  warningOptions,
} from '../helpers/clipboard-diff-setup.ts';
import type { PickItem } from '../helpers/clipboard-diff-setup.ts';
import {
  defined,
  loadFresh,
  makeUri,
  TabInputTextDiff,
} from '../helpers/vscode-mock.ts';
import type { VscodeMock } from '../helpers/vscode-mock.ts';

const COMPARE = 'markdownWorkbench.compareWithClipboard';
const APPLY = 'markdownWorkbench.applyCandidate';

function applyEdits(vscode: VscodeMock) {
  return vscode._applied.filter((op) => op.uri.scheme === 'file');
}

test('Apply writes the candidate into the selection range as one edit', async () => {
  const { vscode, file, run } = await setup('one\ntwo\nthree\n', {
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
  const { vscode, file, run } = await setup('old\n');
  vscode._clipboard = 'new text\n';
  await run(COMPARE);
  await run(APPLY);
  assert.strictEqual(file.getText(), 'new text\n');
});

test('Apply on an anchored section replaces only the section', async () => {
  const { vscode, file, run } = await setup(
    '# A\n\na\n\n## B\n\nb\n\n## C\n\nc\n',
  );
  vscode._clipboard = '## B\n\nB2\n';
  await run(COMPARE);
  await run(APPLY);
  assert.strictEqual(file.getText(), '# A\n\na\n\n## B\n\nB2\n\n## C\n\nc\n');
});

test('the region follows edits before it (contentChanges), so Apply hits the moved text', async () => {
  const { vscode, file, run } = await setup('one\ntwo\nthree\n', {
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

test('an edit landing while Apply awaits the workspace anchor scan does not land at a stale offset', async () => {
  const { vscode, file, run } = await setup('keep1\nOLD\nkeep2\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'NEW';
  await run(COMPARE);
  vscode._config['clipboardDiff.checkWorkspaceAnchors'] = true;
  // Simulate a concurrent edit landing while `anchorRefs` awaits the scan.
  vscode.workspace.findFiles = async () => {
    const edit = new vscode.WorkspaceEdit();
    edit.insert(file.uri, new vscode.Position(0, 0), 'NEWp1\n');
    await vscode.workspace.applyEdit(edit);
    return [];
  };
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(file.getText(), 'NEWp1\nkeep1\nNEW\nkeep2\n');
  assert.strictEqual(
    vscode._warnings.length,
    0,
    'the edit is before the region, so nothing asks - the range is just refetched',
  );
});

test('an edit of the region while Apply awaits makes it ask; an edit during that question asks again', async () => {
  const { vscode, file, run } = await setup('keep1\nOLD\nkeep2\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'NEW';
  await run(COMPARE);
  vscode._config['clipboardDiff.checkWorkspaceAnchors'] = true;
  const editRegion = async (text: string) => {
    const edit = new vscode.WorkspaceEdit();
    edit.replace(file.uri, new vscode.Range(1, 0, 1, 1), text);
    await vscode.workspace.applyEdit(edit);
  };
  vscode.workspace.findFiles = async () => {
    await editRegion('X');
    return [];
  };
  const ask = vscode.window.showWarningMessage;
  let asked = 0;
  vscode.window.showWarningMessage = async (
    message: unknown,
    ...rest: unknown[]
  ) => {
    asked++;
    if (asked === 1) await editRegion('Y');
    return ask(message, ...rest);
  };
  vscode._warningResult = 'Replace';
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(asked, 2, 'asked once per change of the region');
  assert.strictEqual(file.getText(), 'keep1\nNEW\nkeep2\n');
});

test('a changed region makes Apply ask; no answer writes nothing', async () => {
  const { vscode, file, run } = await setup('one\ntwo\nthree\n', {
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
  const asked = defined(vscode._warnings[0], 'the question');
  assert.match(String(asked.message), /baseline range changed/);
  assert.strictEqual(warningOptions(asked).modal, true);
  vscode._warningResult = 'Replace';
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(file.getText(), 'one\nTWO\nthree\n');
});

test('placeholders are filled from the baseline on Apply', async () => {
  const { vscode, file, run } = await setup('a\nb\nc\nd\ne\n');
  vscode._clipboard = 'a\n… rest unchanged …\ne\nnew\n';
  vscode._quickPickResult = (items: PickItem[]) => items.at(-1); // "Whole file"
  await run(COMPARE);
  await run(APPLY);
  assert.strictEqual(file.getText(), 'a\nb\nc\nd\ne\nnew\n');
});

test('an unclear placeholder makes Apply ask instead of guessing', async () => {
  const { vscode, file, run } = await setup('x\n1\nx\n2\n');
  vscode._clipboard = 'x\n...\nnowhere\n';
  vscode._quickPickResult = (items: PickItem[]) => items.at(-1); // "Whole file"
  await run(COMPARE);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  assert.match(
    String(defined(vscode._warnings.at(-1), 'a warning').message),
    /placeholder line could not be matched/,
  );
  assert.strictEqual(file.getText(), 'x\n1\nx\n2\n');
  vscode._warningResult = 'Apply as Text';
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(file.getText(), 'x\n...\nnowhere\n');
});

test('check findings are hints: keeping checkbox states restores them', async () => {
  const { vscode, file, run } = await setup('- [x] ship it\n- [ ] later\n');
  vscode._clipboard = '- [ ] ship it\n- [ ] later\n- [ ] new\n';
  await run(COMPARE);
  vscode._warningResult = 'Keep Checkbox States and Apply';
  assert.strictEqual(await run(APPLY), true);
  const warning = defined(vscode._warnings.at(-1), 'a warning');
  assert.match(
    String(warningOptions(warning).detail),
    /Checked task "ship it" is unchecked/,
  );
  assert.deepStrictEqual(warning.rest.slice(1), [
    'Keep Checkbox States and Apply',
    'Apply',
  ]);
  assert.strictEqual(file.getText(), '- [x] ship it\n- [ ] later\n- [ ] new\n');
});

test('check findings never block: plain Apply writes the candidate as is', async () => {
  const { vscode, file, run } = await setup(
    '---\ntitle: x\n---\n\nintro [a]\n\n[a]: https://a.example\n',
  );
  vscode._clipboard = 'no front matter, no definitions\n';
  await run(COMPARE);
  vscode._warningResult = 'Apply';
  assert.strictEqual(await run(APPLY), true);
  const detail = String(
    warningOptions(defined(vscode._warnings.at(-1), 'a warning')).detail,
  );
  assert.match(detail, /front matter is missing/);
  assert.match(detail, /Link reference definition \[a\] is missing/);
  assert.strictEqual(file.getText(), 'no front matter, no definitions\n');
});

test('dismissing the check writes nothing', async () => {
  const { vscode, file, run } = await setup('- [x] done\n');
  vscode._clipboard = '- [ ] done\n';
  await run(COMPARE);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  assert.strictEqual(file.getText(), '- [x] done\n');
});

test('workspace-wide anchor links are read only when the setting is on', async () => {
  const { vscode, file, run, focusFile } = await setup(
    '# Doc\n\n## Target\n\nt\n',
  );
  const other = new vscode.MockDocument(
    'see [t](notes.md#target)\n',
    makeUri('file', '/ws/other.md'),
  );
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
    String(
      warningOptions(defined(vscode._warnings.at(-1), 'a warning')).detail,
    ),
    /#target .* \/ws\/other\.md links to it/,
  );
  assert.strictEqual(vscode._fsWrites.length, 0, 'read only');
});

test('Apply without an active clipboard diff says so', async () => {
  const { vscode, run } = await setup('a\n');
  assert.strictEqual(await run(APPLY), false);
  assert.ok(anyMessage(vscode._infos, /needs an active clipboard diff/));
});

test('Apply works from the swapped orientation too', async () => {
  const { vscode, file, run } = await setup('one\n', {
    selections: [[0, 0, 0, 3]],
  });
  vscode._clipboard = 'ONE';
  await run(COMPARE);
  await run('markdownWorkbench.swapDiffSides');
  const tab = defined(
    vscode.window.tabGroups.activeTabGroup.activeTab,
    'a tab',
  );
  assert.ok(tab.input instanceof TabInputTextDiff);
  assert.ok(
    tab.input.original.path.includes('(Candidate)'),
    'candidate is on the left now',
  );
  await run(APPLY);
  assert.strictEqual(file.getText(), 'ONE\n');
  assert.strictEqual(
    pageDoc(vscode, expectDiff(vscode).left).getText(),
    'ONE',
    'selection page mirrors the result',
  );
});

test('a refused edit is reported and changes nothing', async () => {
  const { vscode, file, run } = await setup('one\n', {
    selections: [[0, 0, 0, 3]],
  });
  vscode._clipboard = 'ONE';
  const session = await opened(run(COMPARE));
  vscode._applyEditResult = false;
  assert.strictEqual(await run(APPLY), false);
  assert.strictEqual(file.getText(), 'one\n');
  assert.ok(
    anyMessage(
      vscode._warnings.map((w) => w.message),
      /could not apply the candidate/,
    ),
  );
  assert.strictEqual(session.region.touched, false);
});

test('a region changed without a change event (closed file, changed on disk) makes Apply ask', async () => {
  const { vscode, file, run } = await setup('one\ntwo\n', {
    selections: [[1, 0, 1, 3]],
  });
  vscode._clipboard = 'TWO';
  await run(COMPARE);
  file.lines = ['one', 'tw0', '']; // reloaded from disk: no contentChanges reached the extension
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  assert.match(
    String(defined(vscode._warnings.at(-1), 'a warning').message),
    /baseline range changed/,
  );
});

test('the whole-candidate fallback changes the diff only after a successful Apply', async () => {
  const text = '# Doc\n\nintro\n\n## A\n\n- one\n- two\n\n## B\n\nbee\n';
  const { vscode, file, run } = await setup(text);
  vscode._clipboard = '## A\n\n* one\n* TWO\n';
  const session = await opened(run(COMPARE));
  const cand = pageDoc(vscode, session.candidateUri);
  await setText(vscode, cand, cand.getText().replace('intro', 'INTRO'));
  vscode._warningResult = undefined; // the style switch asks first
  const prefixBefore = session.prefix;
  vscode._applyEditResult = false;
  assert.strictEqual(await run(APPLY), false);
  assert.strictEqual(
    session.prefix,
    prefixBefore,
    'a failed Apply leaves the diff as it was',
  );
  vscode._applyEditResult = true;
  assert.strictEqual(await run(APPLY), true);
  assert.strictEqual(
    file.getText(),
    '# Doc\n\nINTRO\n\n## A\n\n* one\n* TWO\n\n## B\n\nbee\n',
  );
  vscode._warningResult = 'Discard Edits';
  await run('markdownWorkbench.showRawCandidate');
  await run(APPLY);
  assert.strictEqual(
    file.getText(),
    '# Doc\n\nINTRO\n\n## A\n\n* one\n* TWO\n\n## B\n\nbee\n',
    'the file is never cut to the section',
  );
});

test('Apply with a closed untitled baseline says so instead of writing into a new one', async () => {
  const { vscode, file, run } = await setup('draft\n', {
    scheme: 'untitled',
    path: 'Untitled-1',
  });
  vscode._clipboard = 'new draft\n';
  await run(COMPARE);
  vscode.workspace.textDocuments.splice(
    vscode.workspace.textDocuments.indexOf(file),
    1,
  );
  assert.strictEqual(await run(APPLY), false);
  assert.ok(
    anyMessage(
      vscode._infos,
      /baseline document of this clipboard diff was closed/,
    ),
  );
});

test('workspace anchors: links resolve relative to their file; unreadable files are skipped', async () => {
  const { vscode, file, run } = await setup('# Doc\n\n## Target\n\nt\n');
  const mk = (path: string, text: string) => {
    const d = new vscode.MockDocument(text, makeUri('file', path));
    vscode.workspace.textDocuments.push(d);
    return d;
  };
  const sameName = mk('/ws/sub/notes.md', 'a different notes.md\n');
  const linking = mk(
    '/ws/sub/guide.md',
    'see [t](../notes.md#target) and [u](notes.md#target)\n',
  );
  const gone = {
    scheme: 'file',
    path: '/ws/gone.md',
    toString: () => 'file:/ws/gone.md',
  };
  vscode.workspace.findFiles = async () => [
    sameName.uri,
    linking.uri,
    gone,
    file.uri,
  ];
  vscode._config['clipboardDiff.checkWorkspaceAnchors'] = true;
  vscode._clipboard = '# Doc\n\n## Renamed\n\nt\n';
  await run(COMPARE);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  const detail = defined(
    warningOptions(defined(vscode._warnings.at(-1), 'a warning')).detail,
    'the warning detail',
  );
  assert.match(detail, /#target .* \/ws\/sub\/guide\.md links to it/);
  assert.strictEqual(
    (detail.match(/guide\.md/g) || []).length,
    1,
    'only the ../notes.md link counts',
  );
});

test('workspace anchors: a file of MAX_SCAN_BYTES is read, a larger one is skipped', async () => {
  const { vscode, file, run } = await setup('# Doc\n\n## Target\n\nt\n');
  const { MAX_SCAN_BYTES } = await loadFresh<{ MAX_SCAN_BYTES: number }>(
    'src/clipboard-diff/apply.ts',
  );
  const mk = (path: string, bytes: number) => {
    const link = '[t](notes.md#target)\n';
    const text = link + 'x'.repeat(bytes - link.length);
    const d = new vscode.MockDocument(text, makeUri('file', path));
    vscode.workspace.textDocuments.push(d);
    return d;
  };
  const atLimit = mk('/ws/at-limit.md', MAX_SCAN_BYTES);
  const over = mk('/ws/over-limit.md', MAX_SCAN_BYTES + 1);
  vscode.workspace.findFiles = async () => [atLimit.uri, over.uri, file.uri];
  vscode._config['clipboardDiff.checkWorkspaceAnchors'] = true;
  vscode._clipboard = '# Doc\n\n## Renamed\n\nt\n';
  await run(COMPARE);
  vscode._warningResult = undefined;
  assert.strictEqual(await run(APPLY), false);
  const detail = defined(
    warningOptions(defined(vscode._warnings.at(-1), 'a warning')).detail,
    'the warning detail',
  );
  assert.match(detail, /at-limit\.md/, 'a file of exactly 1 MB is read');
  assert.doesNotMatch(detail, /over-limit\.md/, 'a larger file is skipped');
});
