#!/usr/bin/env node
// Mutation run of the guard (docs/DECISIONS.md #48, ww3d/markdown-workbench#94):
// proves the guard catches a clipboard page left unsaved. It copies the
// repository to a temporary folder, removes the immediate save from the copy's
// src/clipboard-diff/session.js, builds the copy and runs both guards there -
// the one in the test host (MDWB_ONLY=guard) and the one in a normal window
// (MDWB_ONLY=window-guard). Every run has to fail on its guard case; the
// working tree is never touched. MDWB_VERSIONS narrows the versions as for
// run.js. Under Linux run it through `xvfb-run -a`.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..', '..');
const SESSION = path.join('src', 'clipboard-diff', 'session.js');
// The immediate save in handlePageChange; without it a page stays unsaved.
const SAVE_CALL = 'this.saver.save(doc, () => this.warnSaveFailed());';
// Linked, not copied: large and not changed by the mutation. The VS Code
// cache (.vscode-test) stays out: vsce would package it; run.js finds it in
// its working directory, which stays the repository.
const LINKED = ['node_modules'];
const SKIPPED = new Set(['.git', 'dist', '.vscode-test', ...LINKED]);

/**
 * The source of session.js without its immediate save; throws unless the save
 * call occurs exactly once, so the mutation cannot silently miss.
 *
 * @param {string} source Text of src/clipboard-diff/session.js.
 * @returns {string}
 */
function mutate(source) {
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
 * Whether a run.js output shows the guard caught the mutation: the run failed
 * and every guard case in it failed on a hit, not on something else.
 *
 * @param {number | null} status Exit code of run.js.
 * @param {string} output Its stdout.
 * @returns {boolean}
 */
function caught(status, output) {
  const lines = output.split('\n');
  const guards = [];
  lines.forEach((l, i) => {
    if (/^(ok +|FAIL )guard/.test(l)) guards.push(i);
  });
  // The failure text of a case runs until the next result or phase line.
  const hitAfter = (i) => {
    for (let j = i + 1; j < lines.length; j++) {
      if (/^(ok +|FAIL |== )/.test(lines[j])) return false;
      if (HIT.test(lines[j])) return true;
    }
    return false;
  };
  return (
    status !== 0 &&
    guards.length > 0 &&
    guards.every((i) => lines[i].startsWith('FAIL') && hitAfter(i))
  );
}

function copyRepository(copy) {
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
function run(cmd, args, cwd, env = {}, spawn = spawnSync) {
  const r = spawn(cmd, args, {
    cwd,
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });
  return { status: r.status, output: `${r.stdout}\n${r.stderr}` };
}

function main() {
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
        [path.join(copy, 'tests', 'integration', 'run.js')],
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

if (require.main === module) main();

module.exports = { mutate, caught, run, SAVE_CALL };
