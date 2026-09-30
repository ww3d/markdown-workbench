// The in-memory file system behind the clipboard-diff pages: memory-only
// writes, growing mtimes, directory listing, the FileSystemProvider errors.
import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh, makeUri } from '../helpers/vscode-mock.ts';
import type { MockUri } from '../helpers/vscode-mock.ts';
import { pageStore } from '../helpers/clipboard-diff-setup.ts';

// The store as the mock drives it (the real signatures take vscode types).
interface FileChange {
  type: number;
  uri: MockUri;
}
interface Store {
  readonly files: Map<string, unknown>;
  readonly onDidChangeFile: (listener: (events: FileChange[]) => void) => void;
  put(uri: MockUri, text: string): void;
  textOf(uri: MockUri): string | undefined;
  has(uri: MockUri): boolean;
  release(uri: MockUri): void;
  clear(): void;
  watch(): { dispose(): void };
  stat(uri: MockUri): { type: number; mtime: number; size: number };
  readDirectory(uri: MockUri): [string, number][];
  createDirectory(uri: MockUri): void;
  readFile(uri: MockUri): Uint8Array;
  writeFile(
    uri: MockUri,
    content: Uint8Array,
    options: { create: boolean; overwrite: boolean },
  ): void;
  delete(uri: MockUri): void;
  rename(
    oldUri: MockUri,
    newUri: MockUri,
    options: { overwrite: boolean },
  ): void;
}
interface StoreModule {
  CandidateStore: new () => Store;
  SCHEME: string;
}

async function fresh() {
  const vscode = install();
  const { CandidateStore, SCHEME } = await loadFresh<StoreModule>(
    'src/clipboard-diff/store.ts',
  );
  return {
    vscode,
    store: new CandidateStore(),
    uri: (p: string) => makeUri(SCHEME, p),
  };
}

test('writeFile keeps content in memory only and the mtime always grows', async () => {
  const { vscode, store, uri } = await fresh();
  const u = uri('/1/a (Candidate).md');
  const events: FileChange[] = [];
  store.onDidChangeFile((e) => events.push(...e));
  store.writeFile(u, Buffer.from('one'), { create: true, overwrite: true });
  const m1 = store.stat(u).mtime;
  store.writeFile(u, Buffer.from('two'), { create: false, overwrite: true });
  store.writeFile(u, Buffer.from('three'), { create: false, overwrite: true });
  assert.strictEqual(store.textOf(u), 'three');
  assert.ok(store.stat(u).mtime >= m1 + 2);
  assert.strictEqual(store.stat(u).size, 5);
  assert.deepStrictEqual(
    events.map((e) => e.type),
    [
      vscode.FileChangeType.Created,
      vscode.FileChangeType.Changed,
      vscode.FileChangeType.Changed,
    ],
  );
  assert.strictEqual(vscode._fsWrites.length, 0);
});

test('writeFile honours create/overwrite like a file system', async () => {
  const { store, uri } = await fresh();
  const u = uri('/1/a.md');
  assert.throws(
    () =>
      store.writeFile(u, Buffer.from('x'), { create: false, overwrite: true }),
    /FileNotFound/,
  );
  store.writeFile(u, Buffer.from('x'), { create: true, overwrite: false });
  assert.throws(
    () =>
      store.writeFile(u, Buffer.from('y'), { create: true, overwrite: false }),
    /FileExists/,
  );
});

test('stat, readDirectory and readFile see the implicit directories', async () => {
  const { vscode, store, uri } = await fresh();
  store.put(uri('/1/a (Candidate).md'), 'a');
  store.put(uri('/1/a (Selection).md'), 's');
  store.put(uri('/2/b (Candidate).md'), 'b');
  assert.strictEqual(store.stat(uri('/')).type, vscode.FileType.Directory);
  assert.strictEqual(store.stat(uri('/1')).type, vscode.FileType.Directory);
  assert.deepStrictEqual(store.readDirectory(uri('/')).sort(), [
    ['1', vscode.FileType.Directory],
    ['2', vscode.FileType.Directory],
  ]);
  assert.deepStrictEqual(
    store
      .readDirectory(uri('/1'))
      .map(([n]) => n)
      .sort(),
    ['a (Candidate).md', 'a (Selection).md'],
  );
  assert.strictEqual(
    Buffer.from(store.readFile(uri('/2/b (Candidate).md'))).toString(),
    'b',
  );
  assert.throws(() => store.readFile(uri('/3/x.md')), /FileNotFound/);
  assert.throws(() => store.stat(uri('/3/x.md')), /FileNotFound/);
  store.createDirectory(uri('/9')); // implicit, no-op
});

test('delete and rename move content within memory', async () => {
  const { store, uri } = await fresh();
  store.put(uri('/1/a.md'), 'a');
  store.rename(uri('/1/a.md'), uri('/1/b.md'), { overwrite: false });
  assert.strictEqual(store.textOf(uri('/1/b.md')), 'a');
  assert.strictEqual(store.has(uri('/1/a.md')), false);
  store.put(uri('/1/c.md'), 'c');
  assert.throws(
    () => store.rename(uri('/1/c.md'), uri('/1/b.md'), { overwrite: false }),
    /FileExists/,
  );
  assert.throws(
    () => store.rename(uri('/1/zz.md'), uri('/1/y.md'), { overwrite: true }),
    /FileNotFound/,
  );
  store.delete(uri('/1/b.md'));
  assert.throws(() => store.delete(uri('/1/b.md')), /FileNotFound/);
  store.watch().dispose();
  store.release(uri('/1/c.md'));
  assert.strictEqual(store.has(uri('/1/c.md')), false);
  store.put(uri('/1/d.md'), 'd');
  store.clear();
  assert.strictEqual(store.files.size, 0);
});

test('workspace.fs.writeFile on the page scheme lands in memory, not on disk', async () => {
  const vscode = install();
  (
    await loadFresh<{
      registerClipboardDiff(context: { subscriptions: unknown[] }): void;
    }>('src/clipboard-diff/index.js')
  ).registerClipboardDiff({
    subscriptions: [],
  });
  const uri = makeUri('markdown-workbench-clipboard', '/1/a (Candidate).md');
  await vscode.workspace.fs.writeFile(uri, Buffer.from('via fs'));
  assert.strictEqual(pageStore(vscode).textOf(uri), 'via fs');
  assert.strictEqual(vscode._fsWrites.length, 0);
  await vscode.workspace.fs.writeFile(
    makeUri('file', '/ws/real.md'),
    Buffer.from('x'),
  );
  assert.strictEqual(
    vscode._fsWrites.length,
    1,
    'a disk-backed scheme still counts as a write',
  );
});
