#!/usr/bin/env node
// Mutation run of the guard (docs/DECISIONS.md #48, ww3d/markdown-workbench#94):
// proves the guard catches a clipboard page left unsaved. It copies the
// repository to a temporary folder, removes the immediate save from the copy's
// src/clipboard-diff/session.ts, builds the copy and runs both guards there -
// the one in the test host (MDWB_ONLY=guard) and the one in a normal window
// (MDWB_ONLY=window-guard). Every run has to fail on its guard case; the
// working tree is never touched. MDWB_VERSIONS narrows the versions as for
// run.ts. Under Linux run it through `xvfb-run -a`.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import type { SpawnSyncOptionsWithStringEncoding } from 'node:child_process';
import { relativeLayout } from '../../eng/layout.ts';

const root = path.resolve(import.meta.dirname, '..', '..');
const SESSION = path.join('src', 'clipboard-diff', 'session.ts');
// The immediate save in handlePageChange; without it a page stays unsaved.
const SAVE_CALL = 'this.saver.save(doc, () => this.warnSaveFailed());';
// Linked, not copied: large and not changed by the mutation. The VS Code
// cache (.vscode-test) stays out: vsce would package it; run.ts finds it in
// its working directory, which stays the repository. Build outputs stay out too.
const LINKED = ['node_modules'];
const SKIPPED = new Set([
  '.git',
  relativeLayout.dist,
  relativeLayout.artifacts,
  '.vscode-test',
  ...LINKED,
]);

/**
 * The source of session.ts without its immediate save; throws unless the save
 * call occurs exactly once, so the mutation cannot silently miss.
 *
 * @param source - Text of src/clipboard-diff/session.ts.
 */
function mutate(source: string): string {
  const count = source.split(SAVE_CALL).length - 1;
  if (count !== 1)
    throw new Error(
      `expected the immediate save once in ${SESSION}, found ${count}`,
    );
  return source.replace(SAVE_CALL, 'void 0; // mutation: no immediate save');
}

// A failed guard case names what it found: the test host's assertion says
// "guard hit: <kind>", the window guard lists its hits as [[kind, [...]]].
// A guard red for another reason (timeout, no result) prints neither.
const HIT = /guard hit: |^\s+\[\["/;

/**
 * Whether a run.ts output shows the guard caught the mutation: the run failed
 * and every guard case in it failed on a hit, not on something else.
 *
 * @param status - Exit code of run.ts.
 * @param output - Its stdout.
 */
function caught(status: number | null, output: string): boolean {
  const lines = output.split('\n');
  const guards: number[] = [];
  lines.forEach((l, i) => {
    if (/^(ok +|FAIL )guard/.test(l)) guards.push(i);
  });
  // The failure text of a case runs until the next result or phase line.
  const hitAfter = (i: number): boolean => {
    for (const line of lines.slice(i + 1)) {
      if (/^(ok +|FAIL |== )/.test(line)) return false;
      if (HIT.test(line)) return true;
    }
    return false;
  };
  return (
    status !== 0 &&
    guards.length > 0 &&
    guards.every((i) => lines[i]?.startsWith('FAIL') && hitAfter(i))
  );
}

function copyRepository(copy: string): void {
  for (const entry of fs.readdirSync(root)) {
    if (SKIPPED.has(entry)) continue;
    fs.cpSync(path.join(root, entry), path.join(copy, entry), {
      recursive: true,
    });
  }
  for (const entry of LINKED) {
    const target = path.join(root, entry);
    if (fs.existsSync(target))
      fs.symlinkSync(target, path.join(copy, entry), 'junction');
  }
}

// Starts `node` only, so without a shell: under Windows cmd.exe would split
// a node path with a space (C:\Program Files\nodejs\node.exe).
/** The spawn `run` starts through; injectable for tests. */
type Spawn = (
  cmd: string,
  args: string[],
  options: SpawnSyncOptionsWithStringEncoding,
) => { status: number | null; stdout: string; stderr: string };

/** What one started process left: its exit code and its stdout plus stderr. */
interface RunResult {
  status: number | null;
  output: string;
}

function run(
  cmd: string,
  args: string[],
  cwd: string,
  env: Record<string, string> = {},
  spawn: Spawn = spawnSync,
): RunResult {
  const r = spawn(cmd, args, {
    cwd,
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
  return { status: r.status, output: `${r.stdout}\n${r.stderr}` };
}

function main(): void {
  const copy = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-mutation-'));
  let ok = true;
  try {
    copyRepository(copy);
    const file = path.join(copy, SESSION);
    fs.writeFileSync(file, mutate(fs.readFileSync(file, 'utf8')));
    // tsdown directly: `pnpm run` would first check the linked node_modules.
    const tsdown = path.join(copy, 'node_modules', 'tsdown', 'dist', 'run.mjs');
    const build = run(process.execPath, [tsdown], copy);
    if (build.status !== 0) throw new Error(`build failed:\n${build.output}`);
    for (const only of ['guard', 'window-guard']) {
      const r = run(
        process.execPath,
        [path.join(copy, 'tests', 'integration', 'run.ts')],
        root,
        { MDWB_ONLY: only },
      );
      const lines = r.output
        .split('\n')
        .filter((l) => /^(== VS Code|ok +|FAIL )/.test(l));
      console.log(`\n-- MDWB_ONLY=${only} (exit ${r.status})`);
      // No result lines: the run broke before its cases; show why.
      console.log(
        lines.length
          ? lines.join('\n')
          : r.output.trim().split('\n').slice(-15).join('\n'),
      );
      if (!caught(r.status, r.output)) ok = false;
    }
  } finally {
    fs.rmSync(copy, { recursive: true, force: true });
  }
  console.log(ok ? '\nMUTATION CAUGHT' : '\nMUTATION SURVIVED');
  process.exit(ok ? 0 : 1);
}

if (import.meta.main) main();

export { mutate, caught, run, SAVE_CALL };
export type { Spawn, RunResult };
