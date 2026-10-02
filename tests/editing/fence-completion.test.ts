// Fence language completion: suggests language identifiers after ``` / ~~~.

import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh, MockDocument } from '../helpers/vscode-mock.ts';

const vscode = install();
const { registerFenceLanguageCompletion } = await loadFresh<
  typeof import('../../src/editing/fence-completion.ts')
>('src/editing/fence-completion.ts');

// What the test reads of the completion provider the source registered.
interface FenceProvider {
  provideCompletionItems(
    document: MockDocument,
    position: { line: number; character: number },
  ): { label: string; range: { start: { character: number } } }[] | undefined;
}

function isFenceProvider(value: unknown): value is FenceProvider {
  return (
    typeof value === 'object' &&
    value !== null &&
    'provideCompletionItems' in value &&
    typeof value.provideCompletionItems === 'function'
  );
}

function registeredProvider(): FenceProvider {
  const provider = vscode._completionProvider;
  if (!isFenceProvider(provider))
    throw new TypeError('no completion provider was registered');
  return provider;
}

test('fence completion triggers after ``` and replaces a partial language', () => {
  registerFenceLanguageCompletion({ subscriptions: [] }, [
    'powershell',
    'javascript',
  ]);
  const provider = registeredProvider();
  const doc = new MockDocument('```pow');
  const items = provider.provideCompletionItems(doc, { line: 0, character: 6 });
  assert.ok(items);
  assert.ok(items.some((i) => i.label === 'powershell'));
  assert.ok(
    items.some((i) => i.label === 'ps1'),
    'verified aliases offered',
  );
  assert.strictEqual(items[0]?.range.start.character, 3);
});

test('fence completion stays silent on normal text', () => {
  const provider = registeredProvider();
  const doc = new MockDocument('regular text');
  assert.strictEqual(
    provider.provideCompletionItems(doc, { line: 0, character: 5 }),
    undefined,
  );
});
