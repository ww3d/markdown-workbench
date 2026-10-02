// Behavior tests of eng/build.ts, the flow CI and the local gate both run (DECISIONS.md #21). The plan
// of each task is data (`Step`), so the order, the commands and the environment each step gets are
// asserted on the plan itself; a removed or reordered step turns red here instead of passing unnoticed.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import pkg from '../../package.json' with { type: 'json' };
import {
  applyArtifactsDir,
  cleanRun,
  assertVersionsMatch,
  buildSteps,
  checkSteps,
  coverageSteps,
  dependencySteps,
  integrationSteps,
  type Options,
  packageSteps,
  parseOptions,
  plan,
  runStep,
  type Step,
  sourceDateEpoch,
  staleReason,
  taskSteps,
  testSteps,
  topChangelogVersion,
  typecheckSteps,
  unitTestArgs,
  usage,
} from '../../eng/build.ts';
import {
  artifactsDirVariable,
  relativeLayout,
  repoRoot,
  resolvedLayout,
} from '../../eng/layout.ts';

const layout = resolvedLayout({});
const opts = (over: Partial<Options> = {}): Options => ({
  tasks: ['All'],
  noRestore: false,
  ci: false,
  clean: false,
  help: false,
  ...over,
});
const line = (step: Step): string => (step.command ?? []).join(' ');
const lines = (steps: readonly Step[]): string[] => steps.map(line);
const git = () => '1700000000';

/** Offsets of `needles` in `haystack`, each searched after the previous one; -1 marks a miss. */
function inOrder(
  haystack: readonly string[],
  needles: readonly string[],
): number[] {
  let from = 0;
  return needles.map((needle) => {
    const at = haystack.findIndex((l, i) => i >= from && l.includes(needle));
    if (at >= 0) from = at + 1;
    return at;
  });
}

test('with no task the run is All; task names are matched without regard to case', () => {
  assert.deepStrictEqual(parseOptions([], {}).tasks, ['All']);
  assert.deepStrictEqual(
    parseOptions(['--task', 'check', '--task', 'PACKAGE'], {}).tasks,
    ['Check', 'Package'],
  );
});

test('an unknown task or option is an error that names what is known', () => {
  assert.throws(
    () => parseOptions(['--task', 'Deploy'], {}),
    /Unknown task 'Deploy'.*Restore, Check/,
  );
  assert.throws(() => parseOptions(['--nope'], {}));
});

test('--ci and a CI environment variable both mean a CI run; --no-restore is its own switch', () => {
  assert.strictEqual(parseOptions([], {}).ci, false);
  assert.strictEqual(parseOptions(['--ci'], {}).ci, true);
  assert.strictEqual(parseOptions([], { CI: 'true' }).ci, true);
  assert.strictEqual(parseOptions(['--no-restore'], {}).noRestore, true);
  assert.strictEqual(parseOptions(['--help'], {}).help, true);
});

test('the usage text names every task', () => {
  for (const t of [
    'Restore',
    'Check',
    'Test',
    'Coverage',
    'Build',
    'Package',
    'Integration',
    'All',
  ])
    assert.ok(usage().includes(t), t);
});

test('Check runs format, lint, typecheck and the type scope tests, in this order', () => {
  const at = inOrder(lines(checkSteps(layout)), [
    'pnpm run format',
    'pnpm run lint',
    'pnpm run typecheck',
    'node --test tests/probes/**/*.test.ts',
  ]);
  assert.deepStrictEqual(at, [0, 1, 2, 3]);
});

test('Test and Coverage run the command of pnpm test', () => {
  // package.json writes the globs in double quotes; the plan passes them as plain arguments.
  const command = pkg.scripts.test.replaceAll('"', '');
  assert.strictEqual(`node ${unitTestArgs.join(' ')}`, command);
  assert.deepStrictEqual(testSteps(layout).map(line), [command]);
  assert.ok(line(coverageSteps(layout)[0] as Step).endsWith(command));
});

test('the unit run starts its test processes through the launcher, not with a fixed number', () => {
  assert.match(pkg.scripts.test, /scripts\/run-tests\.ts/);
  assert.doesNotMatch(pkg.scripts.test, /test-concurrency/);
  assert.ok(!unitTestArgs.some((a) => a.includes('test-concurrency')));
});

test('the unit run leaves out the package layer and the type scope tests', () => {
  assert.ok(unitTestArgs.includes('tests/!(package|probes)/**/*.test.ts'));
  assert.match(
    pkg.scripts['test:package'],
    /tests\/package\/\*\*\/\*\.test\.ts/,
  );
  assert.strictEqual(
    pkg.scripts['test:probes'],
    'node --test "tests/probes/**/*.test.ts"',
  );
  // Left out of both the unit run and Check, the scope tests would run nowhere in the gate.
  assert.ok(
    lines(checkSteps(layout)).includes(
      pkg.scripts['test:probes'].replaceAll('"', ''),
    ),
  );
});

test('Coverage counts every source file, holds the documented thresholds and writes below the layout', () => {
  const command = line(coverageSteps(layout)[0] as Step);
  assert.match(command, /c8 --all --src src\b/);
  assert.match(
    command,
    /--check-coverage --lines 88 --branches 82 --functions 78\b/,
  );
  assert.ok(command.includes(`--reports-dir ${layout.coverage}`));
  assert.ok(command.includes(`--temp-directory ${layout.coverageTemp}`));
});

test('Build bundles, smokes both bundles and ends with the size gate', () => {
  assert.deepStrictEqual(lines(buildSteps()), [
    'pnpm exec tsdown',
    'node scripts/bundle-smoke.ts',
    'node scripts/webview-smoke.ts',
    'node scripts/size-gate.ts',
  ]);
});

test('Package checks the fields, builds, runs the package tests on the built dist, then packs', () => {
  const steps = lines(packageSteps(layout, {}, git));
  assert.deepStrictEqual(
    inOrder(steps, [
      'node scripts/package-fields.ts',
      'pnpm exec tsdown',
      'node scripts/size-gate.ts',
      'node --test tests/package/**/*.test.ts',
      'pnpm exec vsce package',
    ]),
    [0, 1, 4, 5, 6],
  );
  assert.ok(steps.at(-1)?.endsWith(`--out ${layout.packages}`));
});

test('Package fixes SOURCE_DATE_EPOCH and TZ=UTC for vsce only', () => {
  const steps = packageSteps(layout, {}, git);
  for (const step of steps.slice(0, -1))
    assert.strictEqual(step.env, undefined, step.name);
  assert.deepStrictEqual(steps.at(-1)?.env, {
    SOURCE_DATE_EPOCH: '1700000000',
    TZ: 'UTC',
  });
});

test('the epoch is the commit time of HEAD unless the environment sets one', () => {
  assert.strictEqual(sourceDateEpoch({}, git), '1700000000');
  assert.strictEqual(
    sourceDateEpoch({ SOURCE_DATE_EPOCH: '42' }, () =>
      assert.fail('git was asked'),
    ),
    '42',
  );
});

test('an epoch that is not digits, or no git history, stops the run - no wall clock', () => {
  assert.throws(
    () => sourceDateEpoch({ SOURCE_DATE_EPOCH: '1e9' }, git),
    /digits only\), got '1e9'/,
  );
  assert.throws(
    () => sourceDateEpoch({}, () => undefined),
    /git log failed.*SOURCE_DATE_EPOCH/,
  );
  assert.throws(() => sourceDateEpoch({}, () => ''), /git log failed/);
});

test('Integration builds first, and goes through xvfb-run under Linux only', () => {
  assert.deepStrictEqual(lines(integrationSteps('win32')), [
    'node tests/integration/run.ts',
  ]);
  assert.deepStrictEqual(lines(integrationSteps('darwin')), [
    'node tests/integration/run.ts',
  ]);
  assert.deepStrictEqual(lines(integrationSteps('linux')), [
    'xvfb-run -a node tests/integration/run.ts',
  ]);
  const steps = lines(taskSteps('Integration', layout, {}, 'linux'));
  assert.deepStrictEqual(
    inOrder(steps, ['pnpm exec tsdown', 'xvfb-run']),
    [0, 4],
  );
});

test('All runs the check first, then the version check, coverage, package and integration', () => {
  const steps = taskSteps('All', layout, { SOURCE_DATE_EPOCH: '1' }, 'linux');
  const names = steps.map((s) => s.name);
  const at = [
    'Format check',
    'Version consistency',
    'Tests with coverage',
    'Mandatory package',
    'Package (vsce)',
    'Integration',
  ].map((n) => names.findIndex((x) => x.startsWith(n)));
  assert.ok(
    at.every((i) => i >= 0),
    `a step is missing (${at})`,
  );
  assert.deepStrictEqual(
    at,
    [...at].sort((a, b) => a - b),
  );
  assert.strictEqual(at[0], 0, 'the format check is the first step');
});

test('Package and All check the version before anything is built', () => {
  assert.strictEqual(
    taskSteps('Package', layout, { SOURCE_DATE_EPOCH: '1' }, 'linux')[0]?.name,
    'Version consistency',
  );
});

test('the topmost CHANGELOG heading is the version the manifest must match', () => {
  assert.strictEqual(
    topChangelogVersion('# Changelog\n\n## 1.2.3\n\n## 1.2.2\n'),
    '1.2.3',
  );
  assert.strictEqual(topChangelogVersion('# nothing'), undefined);
  assert.strictEqual(
    topChangelogVersion(
      fs.readFileSync(path.join(repoRoot, 'CHANGELOG.md'), 'utf8'),
    ),
    pkg.version,
    'the repository itself is consistent',
  );
});

test('a manifest and a changelog that disagree stop the run; this repository passes', () => {
  assert.throws(
    () => assertVersionsMatch('1.2.3', '1.2.2'),
    /package.json is 1.2.3, topmost CHANGELOG entry is 1.2.2/,
  );
  assert.throws(
    () => assertVersionsMatch('1.2.3', undefined),
    /Version mismatch/,
  );
  const step = taskSteps(
    'Package',
    layout,
    { SOURCE_DATE_EPOCH: '1' },
    'linux',
  )[0] as Step;
  step.action?.();
});

test('dependencies: present and current needs no restore', () => {
  assert.strictEqual(
    staleReason({ exists: true, markerMtimeMs: 100 }, 50),
    undefined,
  );
  assert.deepStrictEqual(
    dependencySteps(opts(), undefined).map((s) => s.command),
    [undefined],
  );
});

test('dependencies: missing, unmarked and outdated trees are named', () => {
  assert.match(
    staleReason({ exists: false }, 1) ?? '',
    /node_modules is missing/,
  );
  assert.match(staleReason({ exists: true }, 1) ?? '', /no install marker/);
  assert.match(
    staleReason({ exists: true, markerMtimeMs: 1 }, 2) ?? '',
    /pnpm-lock\.yaml is newer/,
  );
});

test('dependencies: locally a stale tree is restored with a frozen install, announced', () => {
  const steps = dependencySteps(opts(), 'node_modules is missing');
  assert.strictEqual(
    steps[1] && line(steps[1]),
    'pnpm install --frozen-lockfile',
  );
  assert.doesNotThrow(() => steps[0]?.action?.());
});

test('dependencies: in CI and with --no-restore a stale tree fails fast and restores nothing', () => {
  for (const o of [opts({ ci: true }), opts({ noRestore: true })]) {
    const steps = dependencySteps(o, 'node_modules is missing');
    assert.strictEqual(steps.length, 1);
    assert.throws(
      () => steps[0]?.action?.(),
      /node_modules is missing - run 'pnpm install --frozen-lockfile' first/,
    );
  }
});

test('the preflight runs once, before every task but a plain Restore', () => {
  const all = plan(
    opts({ tasks: ['Check', 'Test'] }),
    layout,
    {},
    'linux',
    () => undefined,
  );
  assert.strictEqual(all.filter((s) => s.name === 'Dependencies').length, 1);
  assert.strictEqual(all[0]?.name, 'Dependencies');
  const restore = plan(
    opts({ tasks: ['Restore'] }),
    layout,
    {},
    'linux',
    () => 'node_modules is missing',
  );
  assert.deepStrictEqual(lines(restore), ['pnpm install --frozen-lockfile']);
});

test('tasks run in the order given', () => {
  const steps = lines(
    plan(
      opts({ tasks: ['Test', 'Check'] }),
      layout,
      {},
      'linux',
      () => undefined,
    ),
  );
  assert.deepStrictEqual(
    inOrder(steps, ['run-tests.ts', 'pnpm run format']),
    [1, 2],
  );
});

test('no step of any task calls npm or npx', () => {
  for (const task of [
    'Restore',
    'Check',
    'Test',
    'Coverage',
    'Build',
    'Package',
    'Integration',
    'All',
  ] as const) {
    for (const step of taskSteps(
      task,
      layout,
      { SOURCE_DATE_EPOCH: '1' },
      'linux',
    )) {
      assert.doesNotMatch(line(step), /^(npm|npx)\b|\bnpm ci\b/, step.name);
    }
  }
});

test('a step that exits non-zero stops the run with its exit code; one that exits 0 passes', () => {
  runStep({ name: 'ok', command: ['node', '-e', 'process.exit(0)'] });
  assert.throws(
    () => runStep({ name: 'bad', command: ['node', '-e', 'process.exit(3)'] }),
    /Step 'bad' failed with exit code 3/,
  );
  assert.throws(() => runStep({ name: 'empty' }), /neither command nor action/);
});

test('a step gets its own environment and the caller keeps theirs', () => {
  runStep({
    name: 'env',
    command: [
      'node',
      '-e',
      "process.exit(process.env.MW_PROBE === 'x' && process.env.PATH ? 0 : 9)",
    ],
    env: { MW_PROBE: 'x' },
  });
  assert.strictEqual(process.env.MW_PROBE, undefined);
});

test('every *.test.ts under tests/ is taken by exactly one of the unit, package and probe runs', () => {
  // Striking a glob from package.json (the plan reads the same command) would leave its files running nowhere.
  const globsOf = (script: string): string[] =>
    [...script.matchAll(/"([^"]+\.test\.ts)"/g)].map((m) => m[1] ?? '');
  const runs = [
    pkg.scripts.test,
    pkg.scripts['test:package'],
    pkg.scripts['test:probes'],
  ].map(globsOf);
  assert.ok(
    runs.every((globs) => globs.length > 0),
    'each run names a glob',
  );
  const testFiles = (dir: string): string[] =>
    fs
      .readdirSync(path.join(repoRoot, dir), { withFileTypes: true })
      .flatMap((e) => {
        const rel = `${dir}/${e.name}`;
        if (e.isDirectory()) return testFiles(rel);
        return e.name.endsWith('.test.ts') ? [rel] : [];
      });
  const files = testFiles('tests');
  assert.ok(files.length > 100, 'the walk finds the test files');
  for (const file of files) {
    const taken = runs.filter((globs) =>
      globs.some((glob) => path.matchesGlob(file, glob)),
    ).length;
    assert.strictEqual(taken, 1, `${file} is taken by ${taken} runs`);
  }
});

test('--artifacts-dir moves the root for the layout and every process a step starts; it beats the variable', () => {
  assert.strictEqual(
    parseOptions(['--artifacts-dir', 'out'], {}).artifactsDir,
    'out',
  );
  assert.strictEqual(parseOptions([], {}).artifactsDir, undefined);
  const env: NodeJS.ProcessEnv = {
    [artifactsDirVariable]: '/from/the/variable',
  };
  applyArtifactsDir(opts(), env);
  assert.strictEqual(
    env[artifactsDirVariable],
    '/from/the/variable',
    'without the parameter the variable stays',
  );
  applyArtifactsDir(opts({ artifactsDir: 'out/build' }), env);
  assert.strictEqual(
    env[artifactsDirVariable],
    path.join(repoRoot, 'out', 'build'),
  );
  const moved = resolvedLayout(env);
  assert.strictEqual(
    moved.packages,
    path.join(repoRoot, 'out', 'build', 'packages'),
  );
  assert.ok(
    line(packageSteps(moved, {}, git).at(-1) as Step).endsWith(
      `--out ${moved.packages}`,
    ),
  );
});

test('the typecheck is tsc -b in the default root and runs the check scopes one by one in a moved one', () => {
  assert.deepStrictEqual(lines(typecheckSteps(layout)), ['pnpm run typecheck']);
  const moved = resolvedLayout({
    [artifactsDirVariable]: path.join(repoRoot, 'elsewhere'),
  });
  const steps = lines(typecheckSteps(moved));
  const references = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'tsconfig.json'), 'utf8'),
  ).references;
  assert.strictEqual(
    steps.length,
    references.length,
    'one run per referenced project',
  );
  assert.ok(steps.length >= 4);
  for (const step of steps) {
    assert.match(
      step,
      /^pnpm exec tsc -p tsconfig\.\w+\.json --incremental --tsBuildInfoFile /,
    );
    assert.ok(step.includes(path.join(moved.obj, 'tsconfig.')), step);
    assert.ok(
      !step.includes(relativeLayout.obj),
      'nothing is written to the default root',
    );
  }
});

test('the unit run gets the compile cache of the layout as a variable, which wins over the env file', () => {
  const moved = resolvedLayout({
    [artifactsDirVariable]: path.join(repoRoot, 'elsewhere'),
  });
  for (const step of [...testSteps(moved), ...coverageSteps(moved)]) {
    assert.deepStrictEqual(
      step.env,
      { NODE_COMPILE_CACHE: moved.compileCache },
      step.name,
    );
  }
});

test('--clean is a switch of its own and runs no task; cleanRun says what it deleted', () => {
  assert.strictEqual(parseOptions(['--clean'], {}).clean, true);
  assert.strictEqual(parseOptions([], {}).clean, false);
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'mw-cleanrun-'));
  try {
    const root = path.join(base, 'repo');
    const out = path.join(base, 'out');
    fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
    fs.mkdirSync(out, { recursive: true });
    const fake = { ...layout, artifacts: out, dist: path.join(root, 'dist') };
    assert.strictEqual(
      cleanRun(fake, root),
      `Deleted ${out}, ${path.join(root, 'dist')}.`,
    );
    assert.strictEqual(cleanRun(fake, root), 'Nothing to delete.');
    assert.throws(
      () => cleanRun({ ...fake, artifacts: root }, root),
      /Refusing to clean/,
    );
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});
