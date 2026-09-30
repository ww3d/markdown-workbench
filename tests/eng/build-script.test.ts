// Contract tests of build.ps1, the orchestrator CI and the local gate both run (DECISIONS.md #21).
// PowerShell is not executed headlessly here; the tests read the script and pin the wiring, so a
// removed step turns red instead of passing unnoticed. CI runs the real script.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
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
