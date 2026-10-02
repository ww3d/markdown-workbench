// `--clean` deletes the artifacts root and dist/. A moved root makes that a way to lose unrelated data, so
// the roots that must survive are refused (after the ww3d/atlas guard): the repository, its ancestors, the
// home folder and its ancestors, a .git, the repository's own .tools and node_modules, a filesystem root.
import { after, before, test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { cleanHazard, cleanOutputs, physicalPath } from '../../eng/clean.ts';

let base: string;
let repo: string;
let home: string;

before(() => {
  // realpath: the temp folder itself may be reached through a link (macOS /var, a Windows short name).
  base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'mw-clean-')));
  repo = path.join(base, 'work', 'repo');
  home = path.join(base, 'users', 'me');
  for (const dir of [
    path.join(repo, '.git'),
    path.join(repo, '.tools', 'node'),
    path.join(repo, 'node_modules', 'x'),
    path.join(repo, 'dist'),
    path.join(base, 'work', 'out', 'packages'),
    home,
  ]) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

after(() => {
  fs.rmSync(base, { recursive: true, force: true });
});

const hazard = (target: string) => cleanHazard(target, repo, [home]);

test('an ordinary output folder next to or inside the repository may be cleaned', () => {
  assert.strictEqual(hazard(path.join(base, 'work', 'out')), undefined);
  assert.strictEqual(hazard(path.join(repo, 'artifacts')), undefined);
  assert.strictEqual(
    hazard(path.join(base, 'does', 'not', 'exist')),
    undefined,
  );
});

test('a filesystem root, the repository and its ancestors are refused', () => {
  assert.match(hazard(path.parse(base).root) ?? '', /filesystem root/);
  assert.match(hazard(repo) ?? '', /repository root/);
  assert.match(
    hazard(path.join(base, 'work')) ?? '',
    /repository root or one of its ancestors/,
  );
  assert.match(hazard(base) ?? '', /repository root or one of its ancestors/);
});

test('the home folder and its ancestors are refused', () => {
  assert.match(hazard(home) ?? '', /home folder/);
  assert.match(
    hazard(path.join(base, 'users')) ?? '',
    /home folder or one of its ancestors/,
  );
});

test('a .git, and a folder that holds one, are refused (a worktree has a .git file)', () => {
  assert.match(hazard(path.join(repo, '.git')) ?? '', /\.git/);
  const worktree = path.join(base, 'work', 'worktree');
  fs.mkdirSync(worktree, { recursive: true });
  fs.writeFileSync(path.join(worktree, '.git'), 'gitdir: ../repo/.git\n');
  assert.match(hazard(worktree) ?? '', /holds, a \.git|or holds/);
});

test('the toolchain and the dependencies of the repository are refused, and so is anything inside them', () => {
  assert.match(hazard(path.join(repo, '.tools')) ?? '', /\.tools/);
  assert.match(hazard(path.join(repo, '.tools', 'node')) ?? '', /\.tools/);
  assert.match(hazard(path.join(repo, 'node_modules')) ?? '', /node_modules/);
  assert.match(
    hazard(path.join(repo, 'node_modules', 'x')) ?? '',
    /node_modules/,
  );
});

test('a link does not hide what it points to: a home reached through a junction is still the home', () => {
  const link = path.join(base, 'link-to-users');
  try {
    fs.symlinkSync(path.join(base, 'users'), link, 'junction');
  } catch (error) {
    // Creating links can be denied; say so instead of passing without having looked.
    assert.fail(`cannot create the link this case needs: ${String(error)}`);
  }
  assert.match(hazard(link) ?? '', /home folder or one of its ancestors/);
  assert.strictEqual(
    physicalPath(path.join(link, 'me', 'later')),
    path.join(home, 'later'),
  );
});

test('cleaning deletes the artifacts root and dist, reports both, and a second run finds nothing', () => {
  const out = path.join(base, 'work', 'out');
  fs.writeFileSync(path.join(out, 'packages', 'a.vsix'), 'x');
  const removed = cleanOutputs(out, path.join(repo, 'dist'), repo, [home]);
  assert.deepStrictEqual(removed, [out, path.join(repo, 'dist')]);
  assert.ok(!fs.existsSync(out));
  assert.ok(!fs.existsSync(path.join(repo, 'dist')));
  assert.deepStrictEqual(
    cleanOutputs(out, path.join(repo, 'dist'), repo, [home]),
    [],
  );
});

test('a refused root deletes nothing, dist included, and the error names the way out', () => {
  const marker = path.join(repo, 'dist', 'keep.txt');
  fs.mkdirSync(path.dirname(marker), { recursive: true });
  fs.writeFileSync(marker, 'x');
  assert.throws(
    () => cleanOutputs(repo, path.join(repo, 'dist'), repo, [home]),
    /Refusing to clean .*repository root.*--artifacts-dir/s,
  );
  assert.ok(fs.existsSync(marker), 'dist survived a refused clean');
});

test('square brackets in a root are literal, not a wildcard', () => {
  const odd = path.join(base, 'work', 'a[1]');
  const sibling = path.join(base, 'work', 'a1');
  fs.mkdirSync(odd, { recursive: true });
  fs.mkdirSync(sibling, { recursive: true });
  cleanOutputs(odd, path.join(base, 'no-dist'), repo, [home]);
  assert.ok(!fs.existsSync(odd));
  assert.ok(fs.existsSync(sibling), 'a[1] did not match a1');
});
