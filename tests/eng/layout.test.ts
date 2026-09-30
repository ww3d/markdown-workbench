// eng/layout.ts is the one place every build output path comes from. build.ps1 and the
// workflow read it through the CLI, and a few files cannot import it (a manifest field, an
// ignore file, a tsconfig) and name a path as a literal: these tests pin the layout itself,
// the CLI contract, every key the scripts read, and every such literal against the layout,
// so moving an output there turns them red here.
import { test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import pkg from '../../package.json' with { type: 'json' };
import {
  isLayoutKey,
  layoutPath,
  relativeLayout,
  repoRoot,
  resolvedLayout,
} from '../../eng/layout.ts';

const script = path.join(repoRoot, 'eng', 'layout.ts');

function read(file: string): string {
  return fs.readFileSync(path.join(repoRoot, file), 'utf8');
}

function cli(...args: string[]): {
  status: number | null;
  out: string;
  err: string;
} {
  const r = spawnSync(process.execPath, [script, ...args], {
    encoding: 'utf8',
  });
  return { status: r.status, out: r.stdout, err: r.stderr };
}

test('the layout is the documented set of outputs', () => {
  assert.deepStrictEqual(relativeLayout, {
    dist: 'dist',
    artifacts: 'artifacts',
    packages: 'artifacts/packages',
    testResults: 'artifacts/TestResults',
    coverage: 'artifacts/TestResults/coverage',
    coverageTemp: 'artifacts/TestResults/coverage-tmp',
    obj: 'artifacts/obj',
    compileCache: 'artifacts/obj/compile-cache',
    integration: 'artifacts/obj/integration',
    toolset: 'artifacts/toolset',
    tmp: 'artifacts/tmp',
  });
});

test('the repository root is the folder of package.json', () => {
  assert.ok(fs.existsSync(path.join(repoRoot, 'package.json')));
  assert.ok(path.isAbsolute(repoRoot));
});

test('every layout path resolves below the repository root', () => {
  const resolved = resolvedLayout();
  assert.deepStrictEqual(
    Object.keys(resolved).sort(),
    Object.keys(relativeLayout).sort(),
  );
  for (const [key, absolute] of Object.entries(resolved)) {
    assert.ok(isLayoutKey(key));
    assert.strictEqual(absolute, layoutPath(key));
    assert.strictEqual(
      absolute,
      path.join(repoRoot, ...relativeLayout[key].split('/')),
    );
  }
});

test('isLayoutKey knows the keys and nothing inherited or unknown', () => {
  for (const key of Object.keys(relativeLayout)) assert.ok(isLayoutKey(key));
  for (const key of ['nope', '', 'toString', '__proto__', 'Dist'])
    assert.ok(!isLayoutKey(key), key);
});

test('the CLI without a key prints the whole layout as JSON', () => {
  const r = cli();
  assert.strictEqual(r.status, 0, r.err);
  assert.deepStrictEqual(JSON.parse(r.out), resolvedLayout());
});

test('the CLI with a key prints that path only', () => {
  for (const key of Object.keys(relativeLayout).filter(isLayoutKey)) {
    const r = cli(key);
    assert.strictEqual(r.status, 0, r.err);
    assert.strictEqual(r.out.trim(), layoutPath(key));
  }
});

test('the CLI exits 2 on an unknown key and names the known ones', () => {
  const r = cli('nope');
  assert.strictEqual(r.status, 2);
  assert.strictEqual(r.out, '');
  assert.match(r.err, /unknown layout key 'nope'/);
  for (const key of Object.keys(relativeLayout))
    assert.ok(r.err.includes(key), `${key} is listed`);
});

test('every key build.ps1 and the workflow read exists in the layout', () => {
  // build.ps1 reads `$layout.<key>` and `(Get-Layout).<key>`; the workflow calls
  // `node eng/layout.ts <key>`.
  const build = read('build.ps1');
  const workflow = read('.github/workflows/test.yml');
  const read1 = [
    ...build.matchAll(/\$layout\.(\w+)|\(Get-Layout\)\.(\w+)/g),
  ].map((m) => m[1] ?? m[2]);
  const read2 = [...workflow.matchAll(/eng\/layout\.ts (\w+)/g)].map(
    (m) => m[1],
  );
  assert.ok(read1.length > 0, 'build.ps1 reads at least one key');
  assert.ok(read2.length > 0, 'the workflow reads at least one key');
  for (const key of [...read1, ...read2])
    assert.ok(
      key !== undefined && isLayoutKey(key),
      `${key} is not a layout key`,
    );
});

test('build.ps1 and the workflow name no layout path as a literal', () => {
  // A path such as `--out artifacts/packages` would keep working after the layout moves it; the
  // scripts read every output through `$layout.<key>` / `eng/layout.ts <key>`. Comments may name one.
  const branches = Object.values(relativeLayout).filter((p) =>
    p.startsWith('artifacts'),
  );
  assert.ok(branches.length > 0, 'the layout has branches under artifacts/');
  for (const file of ['build.ps1', '.github/workflows/test.yml']) {
    const code = read(file)
      .split(/\r?\n/)
      .filter((line) => !line.trim().startsWith('#'))
      .join('\n');
    for (const branch of branches)
      assert.ok(!code.includes(branch), `${file} names ${branch} as a literal`);
  }
});

// --- Literals that cannot import the layout ---

// Non-empty, non-comment lines of an ignore file in the repository root.
function ignoreLines(file: string): string[] {
  return read(file)
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
}

test('package.json main points into the layout dist folder', () => {
  assert.ok(
    pkg.main.startsWith(`./${relativeLayout.dist}/`),
    `main "${pkg.main}" is not under ${relativeLayout.dist}/`,
  );
});

test('.gitignore and .vscodeignore name the layout outputs', () => {
  const git = ignoreLines('.gitignore');
  for (const dir of [relativeLayout.dist, relativeLayout.artifacts]) {
    assert.ok(git.includes(`${dir}/`), `.gitignore lacks ${dir}/`);
  }
  const vsix = ignoreLines('.vscodeignore');
  assert.ok(
    vsix.includes(`${relativeLayout.artifacts}/**`),
    `.vscodeignore lacks ${relativeLayout.artifacts}/**`,
  );
  assert.ok(
    !vsix.some((l) => l.startsWith(`${relativeLayout.dist}/`)),
    `${relativeLayout.dist}/ is the extension and must ship in the vsix`,
  );
});

test('the downloaded VS Code lives under the layout, not in a path of its own', () => {
  // The runner takes the download folder from the toolset entry, and neither ignore file names a path of its own.
  for (const file of ['.gitignore', '.vscodeignore'])
    assert.ok(
      !read(file).includes('.vscode-test'),
      `${file} names .vscode-test`,
    );
  const sources = fs
    .readdirSync(path.join(repoRoot, 'tests', 'integration'))
    .filter((f) => f.endsWith('.ts'));
  assert.ok(sources.includes('run.ts'));
  for (const file of sources)
    assert.ok(
      !read(`tests/integration/${file}`).includes('.vscode-test'),
      `${file} names .vscode-test`,
    );
  assert.match(read('tests/integration/run.ts'), /layoutPath\('toolset'\)/);
});

test('both VS Code downloads in run.ts take their folder from vscodeCacheDir()', () => {
  const calls = [
    ...read('tests/integration/run.ts').matchAll(
      /downloadAndUnzipVSCode\(\{[^}]*\}\)/g,
    ),
  ];
  assert.equal(calls.length, 2);
  for (const [call] of calls)
    assert.match(call, /cachePath: vscodeCacheDir\(\)/);
});

test('every runTests call in run.ts names its own extensions dir, so none lands in .vscode-test/', () => {
  // runTests adds --extensions-dir=<repo>/.vscode-test/extensions when the launch args carry none.
  const calls = [
    ...read('tests/integration/run.ts').matchAll(
      /runTests\(\{[\s\S]*?launchArgs: \[([\s\S]*?)\]/g,
    ),
  ];
  assert.ok(calls.length > 0);
  for (const [, args] of calls) assert.match(args ?? '', /'--extensions-dir'/);
});

test('every tsconfig keeps its build info under the layout obj folder', () => {
  const configs = fs
    .readdirSync(repoRoot)
    .filter((f) => /^tsconfig.*\.json$/.test(f))
    .map((f) => [f, JSON.parse(read(f))]);
  // A config that checks files (not the solution, not the shared base) must
  // set it: tsc -b otherwise writes its build info next to the config.
  const checking = configs.filter(([, c]) => c.include || c.files?.length);
  assert.ok(checking.length > 0, 'expected at least one checking tsconfig');
  for (const [file, config] of checking) {
    const info = config.compilerOptions?.tsBuildInfoFile ?? '';
    assert.ok(
      info.startsWith(`./${relativeLayout.obj}/`),
      `${file}: tsBuildInfoFile "${info}" is not under ${relativeLayout.obj}/`,
    );
  }
});

test('Biome and Prettier skip the layout outputs through the ignore file', () => {
  // Neither names an output itself: Biome reads the VCS ignore file (vcs.useIgnoreFile),
  // Prettier 3 reads it by default, so that file is the one literal.
  const biome = JSON.parse(read('biome.json'));
  assert.strictEqual(biome.vcs?.useIgnoreFile, true);
  const outputs = [relativeLayout.dist, relativeLayout.artifacts];
  const named = [
    ...ignoreLines('.prettierignore'),
    ...(biome.files?.includes ?? []),
  ].filter((l) => outputs.some((o) => l.replace(/^!/, '').startsWith(o)));
  assert.deepStrictEqual(
    named,
    [],
    'an output path named outside the ignore file',
  );
});
