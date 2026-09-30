// Contract tests of build.ps1, the orchestrator CI and the local gate both run (DECISIONS.md #21).
// PowerShell is not executed headlessly here; the tests read the script and pin the wiring, so a
// removed step turns red instead of passing unnoticed. CI runs the real script.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import pkg from '../../package.json' with { type: 'json' };
import { repoRoot } from '../../eng/layout.ts';

test('build.ps1 runs format check and lint first in the All gate', () => {
  const script = fs.readFileSync(path.join(repoRoot, 'build.ps1'), 'utf8');
  assert.match(script, /ValidateSet\('Check',/, 'Check is a task of its own');
  assert.match(script, /pnpm run format\b/, 'Check runs the format check');
  assert.match(script, /pnpm run lint\b/, 'Check runs the linter');
  assert.match(
    script,
    /'All' \{\s*Invoke-Check\s*\n/,
    'All starts with the check, before the tests',
  );
});

test('build.ps1 dependency preflight: implicit restore locally, fail-fast in CI / -NoRestore', () => {
  // Contract only (PowerShell is not executed headlessly; CI exercises the CI
  // branch for real). The preflight detects a missing/stale node_modules, then:
  // locally restores with a frozen pnpm install (announced), but in CI or with
  // -NoRestore fails fast; a failed restore aborts with pnpm's exit code.
  const script = fs.readFileSync(path.join(repoRoot, 'build.ps1'), 'utf8');
  assert.match(
    script,
    /function Assert-Dependencies/,
    'the preflight function exists',
  );
  assert.match(
    script,
    /Assert-Dependencies\s*#/,
    'the preflight runs before the task switch',
  );
  assert.match(
    script,
    /\[switch\] \$NoRestore/,
    'the -NoRestore opt-out exists',
  );
  assert.match(
    script,
    /node_modules\/\.modules\.yaml/,
    'compares against the install marker',
  );
  assert.match(
    script,
    /Get-Item 'pnpm-lock\.yaml' -Force/,
    'the marker is compared with the pnpm lockfile',
  );
  // The install marker is a dotfile; Get-Item needs -Force on Linux or it throws
  // "Could not find item" on the hidden file (regression that broke CI).
  assert.match(
    script,
    /Get-Item \$installed -Force/,
    'reads the hidden install marker with -Force',
  );
  // CI / -NoRestore -> fail fast, never auto-install.
  assert.match(
    script,
    /if \(\$env:CI -or \$NoRestore\)/,
    'CI and -NoRestore take the fail-fast path',
  );
  assert.match(
    script,
    /run 'pnpm install --frozen-lockfile' first/,
    'fail-fast tells the user how to fix it',
  );
  // Local default -> announced implicit restore, error never swallowed.
  assert.match(
    script,
    /restoring \(pnpm install --frozen-lockfile\)\.\.\./,
    'announces the restore before running it',
  );
  assert.match(
    script,
    /^\s*pnpm install --frozen-lockfile$/m,
    'restores with a frozen pnpm install',
  );
  assert.match(
    script,
    /Dependency restore \(pnpm install\) failed with exit code \$LASTEXITCODE/,
    'a failed restore aborts with pnpm exit code',
  );
  assert.doesNotMatch(
    script,
    /\bnpm ci\b|\bnpx\b/,
    'no npm call is left in the build',
  );
});

/** The body of a top-level function of build.ps1: from its header to the closing brace at column 0. */
function functionBody(script: string, name: string): string {
  const match = new RegExp(
    `^function ${name} \\{\\n([\\s\\S]*?)\\n\\}`,
    'm',
  ).exec(script);
  assert.ok(match?.[1] !== undefined, `build.ps1 defines ${name}`);
  return match[1];
}

/** Offsets of `needles` in `haystack`, each searched after the previous one; -1 marks a miss. */
function inOrder(haystack: string, needles: readonly string[]): number[] {
  let from = 0;
  return needles.map((needle) => {
    const at = haystack.indexOf(needle, from);
    if (at >= 0) from = at + needle.length;
    return at;
  });
}

const script = fs.readFileSync(path.join(repoRoot, 'build.ps1'), 'utf8');

test('Check runs format, lint and typecheck, in this order', () => {
  const at = inOrder(functionBody(script, 'Invoke-Check'), [
    'pnpm run format',
    'pnpm run lint',
    'pnpm run typecheck',
  ]);
  assert.ok(
    at.every((i) => i >= 0),
    `a step is missing (${at})`,
  );
});

test('Test and Coverage run the command of pnpm test', () => {
  // build.ps1 writes the same node command as package.json, with single quotes.
  const command = pkg.scripts.test.replaceAll('"', "'");
  assert.ok(functionBody(script, 'Invoke-Tests').includes(command));
  assert.ok(functionBody(script, 'Invoke-Coverage').includes(command));
});

test('the unit run starts its test processes through the launcher, not with a fixed number', () => {
  assert.match(pkg.scripts.test, /scripts\/run-tests\.ts/);
  assert.doesNotMatch(pkg.scripts.test, /test-concurrency/);
  assert.doesNotMatch(script, /test-concurrency/);
});

test('the unit run leaves out the package layer, which needs a built dist', () => {
  assert.match(pkg.scripts.test, /!\(package\|probes\)/);
  assert.match(
    pkg.scripts['test:package'],
    /tests\/package\/\*\*\/\*\.test\.ts/,
  );
});

test('the unit run leaves out the type scope tests, which Check runs with the typecheck', () => {
  // Left out of both the unit run and Check, the scope tests would run nowhere in the gate.
  assert.match(pkg.scripts.test, /!\(package\|probes\)/);
  assert.strictEqual(
    pkg.scripts['test:probes'],
    'node --test "tests/probes/**/*.test.ts"',
  );
  const at = inOrder(functionBody(script, 'Invoke-Check'), [
    'pnpm run typecheck',
    pkg.scripts['test:probes'].replaceAll('"', "'"),
  ]);
  assert.ok(
    at.every((i) => i >= 0),
    `Check runs the command of test:probes after the typecheck (${at})`,
  );
});

test('Build bundles, smokes both bundles and ends with the size gate', () => {
  const body = functionBody(script, 'Invoke-Build');
  const at = inOrder(body, [
    'pnpm exec tsdown',
    'node scripts/bundle-smoke.ts',
    'node scripts/webview-smoke.ts',
    'node scripts/size-gate.ts',
  ]);
  assert.ok(
    at.every((i) => i >= 0),
    `a build step is missing (${at})`,
  );
  assert.strictEqual(
    body.match(/Invoke-Step /g)?.length,
    4,
    'nothing runs after the size gate',
  );
});

test('Package builds, runs the package tests on the built dist, then packs', () => {
  const body = functionBody(script, 'Invoke-Package');
  const at = inOrder(body, [
    'Invoke-Build',
    'Invoke-PackageTests',
    'pnpm exec vsce package',
  ]);
  assert.ok(
    at.every((i) => i >= 0),
    `a package step is missing (${at})`,
  );
  assert.match(
    functionBody(script, 'Invoke-PackageTests'),
    /node --test 'tests\/package\/\*\*\/\*\.test\.ts'/,
  );
});

test('Package checks the mandatory package fields before it builds and packs', () => {
  const at = inOrder(functionBody(script, 'Invoke-Package'), [
    'node scripts/package-fields.ts',
    'Invoke-Build',
    'pnpm exec vsce package',
  ]);
  assert.ok(
    at.every((i) => i >= 0),
    `a package step is missing (${at})`,
  );
});

test('Package fixes SOURCE_DATE_EPOCH before vsce, from the commit time unless one is set', () => {
  const body = functionBody(script, 'Invoke-Package');
  const at = inOrder(body, ['Set-SourceDateEpoch', 'pnpm exec vsce package']);
  assert.ok(
    at.every((i) => i >= 0),
    `the epoch is not set before vsce (${at})`,
  );
  const setter = functionBody(script, 'Set-SourceDateEpoch');
  assert.match(setter, /if \(\$env:SOURCE_DATE_EPOCH\) \{[\s\S]*?\n {8}return/);
  assert.match(setter, /git log -1 --format=%ct/);
  assert.match(setter, /\$env:SOURCE_DATE_EPOCH = "\$epoch"/);
  assert.match(setter, /throw /, 'no git history stops the run, no wall clock');
  assert.match(setter, /-notmatch '\^\\d\+\$'/, 'a set epoch must be digits');
  assert.match(
    setter,
    /Get-Command git\b/,
    'a missing git gets its own message',
  );
  assert.ok(
    setter.indexOf('Get-Command git') < setter.indexOf('git log -1'),
    'git is checked before it is called',
  );
});

test('Package hands SOURCE_DATE_EPOCH and TZ=UTC to vsce only and restores the session after', () => {
  const body = functionBody(script, 'Invoke-Package');
  assert.match(body, /\$oldEpoch = \$env:SOURCE_DATE_EPOCH/);
  assert.match(body, /\$oldTz = \$env:TZ/);
  assert.match(body, /\$env:TZ = 'UTC'/);
  const at = inOrder(body, [
    'try {',
    'Set-SourceDateEpoch',
    "$env:TZ = 'UTC'",
    'pnpm exec vsce package',
    '} finally {',
    '$env:SOURCE_DATE_EPOCH = $oldEpoch',
    '$env:TZ = $oldTz',
  ]);
  assert.ok(
    at.every((i) => i >= 0),
    `the session is not restored in finally (${at})`,
  );
});

test('Coverage counts every source file and holds the documented thresholds', () => {
  const body = functionBody(script, 'Invoke-Coverage');
  // --all: a source no test loads counts as uncovered instead of missing from the report.
  assert.match(body, /c8 --all --src src\b/);
  assert.match(
    body,
    /--check-coverage --lines 88 --branches 82 --functions 78\b/,
  );
});

// The quoted globs of a package.json script: the test files one run takes.
const globsOf = (script: string): string[] =>
  [...script.matchAll(/"([^"]+\.test\.ts)"/g)].map((m) => m[1] ?? '');

function testFiles(dir: string): string[] {
  return fs
    .readdirSync(path.join(repoRoot, dir), { withFileTypes: true })
    .flatMap((e) => {
      const rel = `${dir}/${e.name}`;
      if (e.isDirectory()) return testFiles(rel);
      return e.name.endsWith('.test.ts') ? [rel] : [];
    });
}

test('every *.test.ts under tests/ is taken by exactly one of the unit, package and probe runs', () => {
  // Striking a glob from package.json and build.ps1 alike (the command comparison stays green)
  // would leave its files running nowhere.
  const runs = [
    pkg.scripts.test,
    pkg.scripts['test:package'],
    pkg.scripts['test:probes'],
  ].map(globsOf);
  assert.ok(
    runs.every((globs) => globs.length > 0),
    'each run names a glob',
  );
  const files = testFiles('tests');
  assert.ok(files.length > 100, 'the walk finds the test files');
  for (const file of files) {
    const taken = runs.filter((globs) =>
      globs.some((glob) => path.matchesGlob(file, glob)),
    ).length;
    assert.strictEqual(taken, 1, `${file} is taken by ${taken} runs`);
  }
});
