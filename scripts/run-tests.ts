#!/usr/bin/env node
// Starts `node --test` with one test process per core. Node's own default is one less
// (os.availableParallelism() - 1) and takes no "all cores" value; the number has to be
// computed, and a package.json script cannot do that on every shell (DECISIONS.md #50).
//
//   node scripts/run-tests.ts <node arguments and test globs>   # what `pnpm test` runs

import { spawnSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';

/** The arguments of the child `node`: test mode, one test process per core, then the caller's. */
export function testArgs(
  cores: number,
  args: readonly string[],
): readonly string[] {
  return ['--test', `--test-concurrency=${cores}`, ...args];
}

/** The exit code to pass on: the child's own, or 1 when a signal ended it and left none. */
export function exitCode(
  status: number | null,
  signal: NodeJS.Signals | null,
): number {
  return signal === null ? (status ?? 1) : 1;
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(import.meta.filename)
) {
  const { status, signal } = spawnSync(
    process.execPath,
    testArgs(os.availableParallelism(), process.argv.slice(2)),
    { stdio: 'inherit' },
  );
  process.exit(exitCode(status, signal));
}
