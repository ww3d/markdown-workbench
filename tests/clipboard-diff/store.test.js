// The in-memory file system behind the clipboard-diff pages: memory-only
// writes, growing mtimes, directory listing, the FileSystemProvider errors.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh, makeUri } = require('../helpers/vscode-mock');

function fresh() {
  const vscode = install();
  const { CandidateStore, SCHEME } = loadFresh('src/clipboard-diff/store.js');
  return {
    vscode,
    store: new CandidateStore(),
    uri: (p) => makeUri(SCHEME, p),
  };
}

test('writeFile keeps content in memory only and the mtime always grows', () => {
  const { vscode, store, uri } = fresh();
  const u = uri('/1/a (Candidate).md');
  const events = [];
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

test('writeFile honours create/overwrite like a file system', () => {
  const { store, uri } = fresh();
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

test('stat, readDirectory and readFile see the implicit directories', () => {
  const { vscode, store, uri } = fresh();
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

test('delete and rename move content within memory', () => {
  const { store, uri } = fresh();
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
  const { install, loadFresh } = require('../helpers/vscode-mock');
  const vscode = install();
  loadFresh('src/clipboard-diff/index.js').registerClipboardDiff({
    subscriptions: [],
  });
  const uri = makeUri('markdown-workbench-clipboard', '/1/a (Candidate).md');
  await vscode.workspace.fs.writeFile(uri, Buffer.from('via fs'));
  assert.strictEqual(
    vscode._fsProviders['markdown-workbench-clipboard'].textOf(uri),
    'via fs',
  );
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
