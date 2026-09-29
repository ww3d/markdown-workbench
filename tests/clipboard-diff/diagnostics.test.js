// Candidate hints on the vscode mock: placeholder and Markdown-check
// diagnostics on the candidate page, and the one-click quick fixes.
import { test } from 'node:test';
import assert from 'node:assert';
import { setup, pageDoc, setText } from '../helpers/clipboard-diff-setup.ts';

const COMPARE = 'markdownWorkbench.compareWithClipboard';

function codeActions(vscode, doc) {
  const diagnostics = vscode._diagnostics.get(doc.uri.toString()) || [];
  const { provider } = vscode._codeActionProviders[0];
  return provider.provideCodeActions(doc, new vscode.Range(0, 0, 0, 0), {
    diagnostics,
  });
}

test('placeholders and check findings appear as diagnostics on the candidate', async () => {
  const { vscode, run } = await setup('- [x] done\n- [ ] open\n');
  vscode._clipboard = '- [ ] done\n...\n';
  const session = await run(COMPARE);
  const list = vscode._diagnostics.get(session.candidateUri.toString());
  const byCode = Object.fromEntries(list.map((d) => [d.code, d]));
  assert.strictEqual(byCode.placeholder.range.start.line, 1);
  assert.strictEqual(
    byCode.placeholder.severity,
    vscode.DiagnosticSeverity.Warning,
  );
  assert.strictEqual(byCode['checkbox-reset'].range.start.line, 0);
  assert.strictEqual(
    byCode['checkbox-reset'].severity,
    vscode.DiagnosticSeverity.Information,
  );
  assert.ok(list.every((d) => d.source === 'Markdown Workbench'));
});

test('diagnostic lines of an anchored section are offset by the text before it', async () => {
  const { vscode, run } = await setup('# A\n\nx\n\n## B\n\n- [x] b\n');
  vscode._clipboard = '## B\n\n- [ ] b\n';
  const session = await run(COMPARE);
  const list = vscode._diagnostics.get(session.candidateUri.toString());
  assert.strictEqual(list[0].range.start.line, 6);
});

test('the quick fixes keep checkbox states and fill placeholders', async () => {
  const { vscode, run } = await setup('- [x] done\nhead\nmid\ntail\n');
  vscode._clipboard = '- [ ] done\nhead\n...';
  vscode._quickPickResult = (items) => items.at(-1);
  const session = await run(COMPARE);
  const doc = pageDoc(vscode, session.candidateUri);
  const actions = await codeActions(vscode, doc);
  assert.deepStrictEqual(
    actions.map((a) => a.title),
    [
      'Keep checkbox states from the baseline',
      'Fill placeholders from the baseline',
    ],
  );
  assert.strictEqual(actions[0].kind, vscode.CodeActionKind.QuickFix);
  await vscode.workspace.applyEdit(actions[0].edit);
  assert.strictEqual(doc.getText(), '- [x] done\nhead\n...');
  // Actions are computed per request, like VS Code does after every edit.
  const fill = (await codeActions(vscode, doc)).find((a) =>
    a.title.startsWith('Fill'),
  );
  await vscode.workspace.applyEdit(fill.edit);
  assert.strictEqual(doc.getText(), '- [x] done\nhead\nmid\ntail\n');
});

test('diagnostics are refreshed after edits and cleared when the diff closes', async () => {
  const { vscode, run, tick } = await setup('- [x] done\n');
  vscode._clipboard = '- [ ] done\n';
  const session = await run(COMPARE);
  const key = session.candidateUri.toString();
  assert.strictEqual(vscode._diagnostics.get(key).length, 1);
  await setText(vscode, pageDoc(vscode, session.candidateUri), '- [x] done\n');
  await new Promise((r) => setTimeout(r, 260));
  assert.strictEqual(vscode._diagnostics.get(key).length, 0);
  await vscode._closeTab(vscode.window.tabGroups.activeTabGroup.activeTab);
  await tick();
  assert.strictEqual(vscode._diagnostics.has(key), false);
});

test('no quick fixes for documents without our diagnostics', async () => {
  const { vscode, run } = await setup('a\n');
  vscode._clipboard = 'b\n';
  const session = await run(COMPARE);
  const actions = await codeActions(
    vscode,
    pageDoc(vscode, session.candidateUri),
  );
  assert.deepStrictEqual(actions, []);
});

test('the cached anchor links follow a new file version', async () => {
  const { vscode, file, run } = await setup(
    '# Doc\n\n## Target\n\nt\n\nend\n',
    {
      selections: [[2, 0, 4, 1]],
    },
  );
  vscode._clipboard = '## Renamed\n\nt';
  const session = await run(COMPARE);
  const codes = () =>
    (vscode._diagnostics.get(session.candidateUri.toString()) || []).map(
      (d) => d.code,
    );
  assert.ok(!codes().includes('anchor-broken'), 'no link to #target yet');
  const e = new vscode.WorkspaceEdit();
  e.insert(file.uri, new vscode.Position(6, 3), ' [t](#target)'); // outside the region
  await vscode.workspace.applyEdit(e);
  await new Promise((r) => setTimeout(r, 260));
  assert.ok(
    codes().includes('anchor-broken'),
    'the new link of the new file version counts',
  );
});
