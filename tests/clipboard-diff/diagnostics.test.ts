// Candidate hints on the vscode mock: placeholder and Markdown-check
// diagnostics on the candidate page, and the one-click quick fixes.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  diagnosticsOf,
  opened,
  pageDoc,
  quickFixes,
  setText,
  setup,
} from '../helpers/clipboard-diff-setup.ts';
import type { PickItem } from '../helpers/clipboard-diff-setup.ts';
import { nth } from '../helpers/nth.ts';
import { defined } from '../helpers/vscode-mock.ts';
import type { MockUri, VscodeMock } from '../helpers/vscode-mock.ts';

const COMPARE = 'markdownWorkbench.compareWithClipboard';

// The diagnostics published for a page; none published fails the test by name.
const published = (vscode: VscodeMock, uri: MockUri) =>
  defined(diagnosticsOf(vscode, uri.toString()), 'published diagnostics');

test('placeholders and check findings appear as diagnostics on the candidate', async () => {
  const { vscode, run } = await setup('- [x] done\n- [ ] open\n');
  vscode._clipboard = '- [ ] done\n...\n';
  const session = await opened(run(COMPARE));
  const list = published(vscode, session.candidateUri);
  const byCode = new Map(list.map((d) => [d.code, d]));
  const placeholder = defined(byCode.get('placeholder'), 'placeholder hint');
  assert.strictEqual(placeholder.range.start.line, 1);
  assert.strictEqual(placeholder.severity, vscode.DiagnosticSeverity.Warning);
  const reset = defined(byCode.get('checkbox-reset'), 'checkbox-reset hint');
  assert.strictEqual(reset.range.start.line, 0);
  assert.strictEqual(reset.severity, vscode.DiagnosticSeverity.Information);
  assert.ok(list.every((d) => d.source === 'Markdown Workbench'));
});

test('diagnostic lines of an anchored section are offset by the text before it', async () => {
  const { vscode, run } = await setup('# A\n\nx\n\n## B\n\n- [x] b\n');
  vscode._clipboard = '## B\n\n- [ ] b\n';
  const session = await opened(run(COMPARE));
  const list = published(vscode, session.candidateUri);
  assert.strictEqual(nth(list, 0).range.start.line, 6);
});

test('the quick fixes keep checkbox states and fill placeholders', async () => {
  const { vscode, run } = await setup('- [x] done\nhead\nmid\ntail\n');
  vscode._clipboard = '- [ ] done\nhead\n...';
  vscode._quickPickResult = (items: PickItem[]) => items.at(-1);
  const session = await opened(run(COMPARE));
  const doc = pageDoc(vscode, session.candidateUri);
  const actions = await quickFixes(vscode, doc);
  assert.deepStrictEqual(
    actions.map((a) => a.title),
    [
      'Keep checkbox states from the baseline',
      'Fill placeholders from the baseline',
    ],
  );
  const keep = nth(actions, 0);
  assert.strictEqual(keep.kind, vscode.CodeActionKind.QuickFix);
  await vscode.workspace.applyEdit(defined(keep.edit, 'the edit of the fix'));
  assert.strictEqual(doc.getText(), '- [x] done\nhead\n...');
  // Actions are computed per request, like VS Code does after every edit.
  const fill = (await quickFixes(vscode, doc)).find((a) =>
    a.title.startsWith('Fill'),
  );
  await vscode.workspace.applyEdit(defined(fill?.edit, 'the fill fix'));
  assert.strictEqual(doc.getText(), '- [x] done\nhead\nmid\ntail\n');
});

test('diagnostics are refreshed after edits and cleared when the diff closes', async () => {
  const { vscode, run, tick } = await setup('- [x] done\n');
  vscode._clipboard = '- [ ] done\n';
  const session = await opened(run(COMPARE));
  const key = session.candidateUri.toString();
  assert.strictEqual(published(vscode, session.candidateUri).length, 1);
  await setText(vscode, pageDoc(vscode, session.candidateUri), '- [x] done\n');
  await new Promise((r) => setTimeout(r, 260));
  assert.strictEqual(published(vscode, session.candidateUri).length, 0);
  await vscode._closeTab(
    defined(vscode.window.tabGroups.activeTabGroup.activeTab, 'an active tab'),
  );
  await tick();
  assert.strictEqual(diagnosticsOf(vscode, key), undefined);
});

test('no quick fixes for documents without our diagnostics', async () => {
  const { vscode, run } = await setup('a\n');
  vscode._clipboard = 'b\n';
  const session = await opened(run(COMPARE));
  const actions = await quickFixes(
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
  const session = await opened(run(COMPARE));
  const codes = () =>
    (diagnosticsOf(vscode, session.candidateUri.toString()) ?? []).map(
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
