// Fence language completion: suggests language identifiers after ``` / ~~~.

import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh, MockDocument } from '../helpers/vscode-mock.js';

const vscode = install();
const editing = await loadFresh('src/editing/index.js');

test('fence completion triggers after ``` and replaces a partial language', () => {
  const ctx = { subscriptions: [] };
  editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
  const provider = vscode._completionProvider;
  const doc = new MockDocument('```pow');
  const items = provider.provideCompletionItems(doc, { line: 0, character: 6 });
  assert.ok(items.some((i) => i.label === 'powershell'));
  assert.ok(
    items.some((i) => i.label === 'ps1'),
    'verified aliases offered',
  );
  assert.strictEqual(items[0].range.start.character, 3);
});

test('fence completion stays silent on normal text', () => {
  const provider = vscode._completionProvider;
  const doc = new MockDocument('regular text');
  assert.strictEqual(
    provider.provideCompletionItems(doc, { line: 0, character: 5 }),
    undefined,
  );
});
