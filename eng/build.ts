#!/usr/bin/env node
// The build flow: every task the local gate and CI run, one TypeScript file for Windows and Linux. The root
// scripts (Build.cmd, build.sh, ...) only fetch the pinned Node and pnpm (eng/common/) and start this.
//
//   node eng/build.ts [--task <name>]... [--no-restore] [--ci] [--artifacts-dir <path>] [--clean] [--help]
//
// Tasks (several run in the order given; none means All):
//   Restore     - pnpm install --frozen-lockfile
//   Check       - format check (Biome + Prettier), lint (Biome), typecheck (tsc -b), the type scope tests
//   Test        - the unit tests (node:test; tests/package/ and tests/probes/ run in Package and Check)
//   Coverage    - the unit tests under c8 with the coverage gate
//   Build       - bundle the extension host and the webview (tsdown) into dist/, smoke both, size gate
//   Package     - mandatory package fields + Build + the package tests against the built dist/ + the .vsix
//   Integration - Build + the integration tests in a real VS Code (under Linux through xvfb-run -a)
//   All         - Check + version check + Coverage + Package + Integration
//
// The version in package.json is the source of truth (vsce requirement); the topmost CHANGELOG.md entry must
// match it. Every output path comes from eng/layout.ts, never from a literal here.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { cleanOutputs } from './clean.ts';
import {
  artifactsDirVariable,
  type Layout,
  relativeLayout,
  repoRoot,
  resolvedLayout,
} from './layout.ts';

/** The tasks, in the order `All` runs the ones it contains. */
export const taskNames = [
  'Restore',
  'Check',
  'Test',
  'Coverage',
  'Build',
  'Package',
  'Integration',
  'All',
] as const;

/** Name of a task. */
export type TaskName = (typeof taskNames)[number];

/** What a run was asked for. */
export interface Options {
  readonly tasks: readonly TaskName[];
  /** Fail fast on a missing or stale `node_modules` instead of restoring it. */
  readonly noRestore: boolean;
  /** Set when running on a CI server: never restores implicitly (a lockfile drift must be a red build). */
  readonly ci: boolean;
  /** Moves the artifacts root (see eng/layout.ts); a relative path counts from the repository root. */
  readonly artifactsDir?: string | undefined;
  /** Deletes the build outputs (the artifacts root and dist/) and ends the run; no task runs. */
  readonly clean: boolean;
  readonly help: boolean;
}

/** One unit of a run: an external command, or an in-process check. */
export interface Step {
  readonly name: string;
  /** The command and its arguments, when the step starts a process. */
  readonly command?: readonly string[];
  /** Environment for the process on top of the caller's; `undefined` removes a variable. */
  readonly env?: Readonly<Record<string, string | undefined>>;
  /** The in-process work, when the step starts no process. */
  readonly action?: () => void;
}

/** The `node` arguments of the unit run (the command of `pnpm test`; tests pin the two together). */
export const unitTestArgs: readonly string[] = [
  '--env-file=tests/helpers/compile-cache.env',
  'scripts/run-tests.ts',
  '--import',
  './tests/helpers/setup.ts',
  'tests/*.test.ts',
  'tests/!(package|probes)/**/*.test.ts',
];

const pnpm = (...args: string[]): readonly string[] => ['pnpm', ...args];
const node = (...args: string[]): readonly string[] => ['node', ...args];

/**
 * Parses the command line.
 *
 * @throws On an unknown option or task name.
 */
export function parseOptions(
  argv: readonly string[],
  env: NodeJS.ProcessEnv,
): Options {
  const { values } = parseArgs({
    args: [...argv],
    options: {
      task: { type: 'string', multiple: true },
      'no-restore': { type: 'boolean', default: false },
      ci: { type: 'boolean', default: false },
      'artifacts-dir': { type: 'string' },
      clean: { type: 'boolean', default: false },
      help: { type: 'boolean', default: false },
    },
    strict: true,
  });
  const tasks = (values.task ?? []).map((name) => {
    const task = taskNames.find((t) => t.toLowerCase() === name.toLowerCase());
    if (!task) {
      throw new Error(
        `Unknown task '${name}'; known: ${taskNames.join(', ')}.`,
      );
    }
    return task;
  });
  return {
    tasks: tasks.length > 0 ? tasks : ['All'],
    noRestore: values['no-restore'],
    ci: values.ci || Boolean(env.CI),
    artifactsDir: values['artifacts-dir'],
    clean: values.clean,
    help: values.help,
  };
}

/** The usage text printed by `--help`. */
export function usage(): string {
  return [
    'node eng/build.ts [--task <name>]... [--no-restore] [--ci] [--artifacts-dir <path>] [--clean] [--help]',
    '',
    `Tasks: ${taskNames.join(', ')} (default All; several run in the order given)`,
    '  --no-restore   fail fast on a missing or stale node_modules instead of restoring it',
    '  --ci           running on a CI server: never restore implicitly',
    '  --artifacts-dir <path>  root of the outputs (default: artifacts/ under the repository;',
    `                          else the variable ${artifactsDirVariable})`,
    '  --clean        delete the build outputs (the artifacts root and dist/) and stop; runs no task,',
    '                 refuses a root that is the repository, its ancestor, the home folder or a .git',
    '',
  ].join('\n');
}

/** The check scopes of the typecheck: the projects tsconfig.json references. */
function typecheckProjects(): readonly string[] {
  const config = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'tsconfig.json'), 'utf8'),
  ) as { references?: readonly { path: string }[] };
  return (config.references ?? []).map((r) => path.basename(r.path));
}

/**
 * The typecheck. In the default layout it is `tsc -b` (the `typecheck` script), whose build info lives where the
 * tsconfig files name it. `tsc -b` takes no `--tsBuildInfoFile`, so with the artifacts root moved each check scope
 * is run on its own, with its build info under the layout's `obj` - nothing lands in the default root.
 */
export function typecheckSteps(layout: Layout): readonly Step[] {
  if (layout.obj === path.join(repoRoot, relativeLayout.obj)) {
    return [{ name: 'Typecheck (tsc -b)', command: pnpm('run', 'typecheck') }];
  }
  return typecheckProjects().map((project) => ({
    name: `Typecheck (tsc -p ${project})`,
    command: pnpm(
      'exec',
      'tsc',
      '-p',
      project,
      '--incremental',
      '--tsBuildInfoFile',
      path.join(layout.obj, `${path.basename(project, '.json')}.tsbuildinfo`),
    ),
  }));
}

/** Steps of the format check, lint, typecheck and the type scope tests. */
export function checkSteps(layout: Layout): readonly Step[] {
  return [
    { name: 'Format check (Biome + Prettier)', command: pnpm('run', 'format') },
    { name: 'Lint (Biome)', command: pnpm('run', 'lint') },
    ...typecheckSteps(layout),
    // The type probes only prove something while each check scope includes them (tests/probes/).
    // Runs here with the typecheck, not in the unit run: three compiler runs are no unit test.
    {
      name: 'Type scope tests (tests/probes)',
      command: node('--test', 'tests/probes/**/*.test.ts'),
    },
  ];
}

/** The unit run: one test process per core through scripts/run-tests.ts (DECISIONS.md #50). */
export function testSteps(layout: Layout): readonly Step[] {
  return [
    {
      name: 'Tests (node:test)',
      command: node(...unitTestArgs),
      env: compileCacheEnv(layout),
    },
  ];
}

/**
 * The compile cache of the test processes at the layout's place: the variable wins over the `--env-file` the
 * unit run reads (tests/helpers/compile-cache.env), which names the default root.
 */
function compileCacheEnv(layout: Layout): Record<string, string> {
  return { NODE_COMPILE_CACHE: layout.compileCache };
}

/** The unit run under c8 with the coverage gate. */
export function coverageSteps(layout: Layout): readonly Step[] {
  return [
    {
      name: 'Tests with coverage gate (c8)',
      command: pnpm(
        'exec',
        'c8',
        '--all',
        '--src',
        'src',
        '--include=src/**/*.ts',
        '--reporter=text',
        '--reporter=lcov',
        '--reports-dir',
        layout.coverage,
        '--temp-directory',
        layout.coverageTemp,
        '--check-coverage',
        '--lines',
        '88',
        '--branches',
        '82',
        '--functions',
        '78',
        ...node(...unitTestArgs),
      ),
      env: compileCacheEnv(layout),
    },
  ];
}

/** The bundles, their smoke tests and the size gate - the last step of the build. */
export function buildSteps(): readonly Step[] {
  return [
    { name: 'Bundle (tsdown / Rolldown)', command: pnpm('exec', 'tsdown') },
    // Guards the bundle, not the sources: Shiki's languages/themes are lazy chunks, and a broken
    // cross-chunk runtime degrades silently to plain code blocks (initHighlighter catches the load
    // error). Unit tests run against src/ and cannot see this.
    { name: 'Bundle smoke test', command: node('scripts/bundle-smoke.ts') },
    // The same for the webview bundle: the unit tests import src/webview, so only a run of the
    // built dist/webview.js (in happy-dom) sees what the bundler made of it.
    { name: 'Webview smoke test', command: node('scripts/webview-smoke.ts') },
    // Last step of the build, before anything is packaged: the bundles stay inside the size limits.
    { name: 'Size gate', command: node('scripts/size-gate.ts') },
  ];
}

/**
 * The commit time of HEAD, or the epoch the caller already set (reproducible-builds convention):
 * what makes the .vsix byte-identical for one commit. No fallback to the wall clock - a package
 * that differs per run would defeat the point, so a missing git history stops the run.
 *
 * @param env - The environment; a `SOURCE_DATE_EPOCH` in it wins.
 * @param gitCommitTime - Runs `git log -1 --format=%ct`; `undefined` when git is missing or fails.
 */
export function sourceDateEpoch(
  env: NodeJS.ProcessEnv,
  gitCommitTime: () => string | undefined,
): string {
  const noGit =
    'Cannot read the commit time of HEAD. Set SOURCE_DATE_EPOCH or package inside the git checkout.';
  if (env.SOURCE_DATE_EPOCH) {
    if (!/^\d+$/.test(env.SOURCE_DATE_EPOCH)) {
      throw new Error(
        `SOURCE_DATE_EPOCH must be whole seconds since 1970 (digits only), got '${env.SOURCE_DATE_EPOCH}'.`,
      );
    }
    return env.SOURCE_DATE_EPOCH;
  }
  const epoch = gitCommitTime();
  if (!epoch) throw new Error(`git log failed. ${noGit}`);
  return epoch;
}

function gitCommitTime(): string | undefined {
  const r = spawnSync('git', ['log', '-1', '--format=%ct'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  return r.status === 0 ? r.stdout.trim() : undefined;
}

/** Steps of the package: mandatory fields, build, package tests on the built dist/, then the .vsix. */
export function packageSteps(
  layout: Layout,
  env: NodeJS.ProcessEnv,
  git: () => string | undefined = gitCommitTime,
): readonly Step[] {
  return [
    // Before the build: a missing publisher, description, license, repository or LICENSE file stops
    // the run at once, with every missing name in one error (scripts/package-fields.ts).
    {
      name: 'Mandatory package fields',
      command: node('scripts/package-fields.ts'),
    },
    ...buildSteps(),
    {
      name: 'Package tests (built dist/)',
      command: node('--test', 'tests/package/**/*.test.ts'),
    },
    {
      name: 'Package (vsce)',
      command: pnpm('exec', 'vsce', 'package', '--out', layout.packages),
      // Both variables reach vsce only: yazl writes zip times in local time, so TZ=UTC.
      env: { SOURCE_DATE_EPOCH: sourceDateEpoch(env, git), TZ: 'UTC' },
    },
  ];
}

/** Steps of the VS Code integration run (the minimum engines.vscode and the current stable). */
export function integrationSteps(platform: NodeJS.Platform): readonly Step[] {
  // Linux has no display in CI or containers, so the run goes through xvfb-run there.
  const run = node('tests/integration/run.ts');
  return [
    {
      name: 'Integration tests (VS Code, @vscode/test-electron)',
      command: platform === 'linux' ? ['xvfb-run', '-a', ...run] : run,
    },
  ];
}

/** Whether `node_modules` needs a restore, and why; `undefined` when it is present and current. */
export function staleReason(
  nodeModules: { readonly exists: boolean; readonly markerMtimeMs?: number },
  lockMtimeMs: number,
): string | undefined {
  if (!nodeModules.exists) return 'node_modules is missing';
  if (nodeModules.markerMtimeMs === undefined) {
    return 'node_modules is stale (no install marker)';
  }
  return lockMtimeMs > nodeModules.markerMtimeMs
    ? 'node_modules is stale (pnpm-lock.yaml is newer than the install)'
    : undefined;
}

const restoreStep: Step = {
  name: 'Restore (pnpm install --frozen-lockfile)',
  command: pnpm('install', '--frozen-lockfile'),
};

/** Why this checkout needs a restore right now, read from the file system; `undefined` when it does not. */
export function currentStaleReason(): string | undefined {
  const modules = `${repoRoot}/node_modules`;
  const marker = `${modules}/.modules.yaml`;
  return staleReason(
    {
      exists: fs.existsSync(modules),
      ...(fs.existsSync(marker)
        ? { markerMtimeMs: fs.statSync(marker).mtimeMs }
        : {}),
    },
    fs.statSync(`${repoRoot}/pnpm-lock.yaml`).mtimeMs,
  );
}

/** The dependency preflight: nothing to do, a fail-fast, or an announced restore. */
export function dependencySteps(
  options: Options,
  reason: string | undefined,
): readonly Step[] {
  if (!reason) {
    return [
      {
        name: 'Dependencies',
        action: () =>
          console.log(
            'Dependencies present and consistent with pnpm-lock.yaml.',
          ),
      },
    ];
  }
  // In CI, never auto-install: a lockfile drift must surface as a red build, not be silently repaired -
  // the pipeline runs its own frozen install. --no-restore forces the same fail-fast locally.
  if (options.ci || options.noRestore) {
    return [
      {
        name: 'Dependencies',
        action: () => {
          throw new Error(
            `${reason} - run 'pnpm install --frozen-lockfile' first.`,
          );
        },
      },
    ];
  }
  // Local default: implicit restore (like dotnet build), announced up front - never silent.
  return [
    {
      name: 'Dependencies',
      action: () => console.log(`${reason} - restoring...`),
    },
    restoreStep,
  ];
}

/** The topmost `## x.y.z` heading of a changelog. */
export function topChangelogVersion(changelog: string): string | undefined {
  return /^## (\d+\.\d+\.\d+)/m.exec(changelog)?.[1];
}

/**
 * Stops the run when the manifest version and the topmost changelog entry differ.
 *
 * @throws On a mismatch.
 */
export function assertVersionsMatch(
  manifestVersion: string,
  changelogTop: string | undefined,
): void {
  if (manifestVersion !== changelogTop) {
    throw new Error(
      `Version mismatch: package.json is ${manifestVersion}, topmost CHANGELOG entry is ${changelogTop}.`,
    );
  }
}

function versionStep(): Step {
  return {
    name: 'Version consistency',
    action: () => {
      const manifest = JSON.parse(
        fs.readFileSync(`${repoRoot}/package.json`, 'utf8'),
      ) as { version: string };
      const top = topChangelogVersion(
        fs.readFileSync(`${repoRoot}/CHANGELOG.md`, 'utf8'),
      );
      assertVersionsMatch(manifest.version, top);
      console.log(
        `Version ${manifest.version} is consistent across package.json and CHANGELOG.md.`,
      );
    },
  };
}

/** The steps of one task, without the dependency preflight. */
export function taskSteps(
  task: TaskName,
  layout: Layout,
  env: NodeJS.ProcessEnv,
  platform: NodeJS.Platform,
): readonly Step[] {
  switch (task) {
    case 'Restore':
      return [restoreStep];
    case 'Check':
      return checkSteps(layout);
    case 'Test':
      return testSteps(layout);
    case 'Coverage':
      return coverageSteps(layout);
    case 'Build':
      return buildSteps();
    case 'Package':
      return [versionStep(), ...packageSteps(layout, env)];
    case 'Integration':
      return [...buildSteps(), ...integrationSteps(platform)];
    case 'All':
      return [
        ...checkSteps(layout),
        versionStep(),
        ...coverageSteps(layout),
        ...packageSteps(layout, env),
        ...integrationSteps(platform),
      ];
  }
}

/** The whole plan of a run: the dependency preflight once, then each task in order. */
export function plan(
  options: Options,
  layout: Layout,
  env: NodeJS.ProcessEnv,
  platform: NodeJS.Platform,
  staleReasonOf: () => string | undefined = currentStaleReason,
): readonly Step[] {
  const needsDependencies = options.tasks.some((t) => t !== 'Restore');
  return [
    ...(needsDependencies ? dependencySteps(options, staleReasonOf()) : []),
    ...options.tasks.flatMap((t) => taskSteps(t, layout, env, platform)),
  ];
}

/** One line of the step journal: when, how it ended, how long, which step. */
export function journalLine(
  name: string,
  outcome: 'ok' | 'failed',
  ms: number,
  at: Date,
): string {
  return `${at.toISOString()} ${outcome.padEnd(6)} ${String(ms).padStart(7)} ms  ${name}`;
}

/** The file of the step journal, `build.log` in the layout's log branch - written by CI builds only (Atlas: the binlog). */
export function journalFile(
  options: Options,
  layout: Layout,
): string | undefined {
  return options.ci ? path.join(layout.log, 'build.log') : undefined;
}

/**
 * Runs the steps in order, journaling each (ok or failed, with its duration) when a journal is given, and
 * stops at the first one that fails.
 *
 * @param steps - The plan.
 * @param journal - Receives one line per step; `undefined` for a run that keeps no journal.
 * @param clock - Milliseconds since the epoch; replaceable for tests.
 * @throws What the failing step threw, after its line is journaled.
 */
export function runPlan(
  steps: readonly Step[],
  journal?: (line: string) => void,
  clock: () => number = Date.now,
): void {
  for (const step of steps) {
    const start = clock();
    try {
      runStep(step);
    } catch (error) {
      journal?.(
        journalLine(step.name, 'failed', clock() - start, new Date(clock())),
      );
      throw error;
    }
    journal?.(journalLine(step.name, 'ok', clock() - start, new Date(clock())));
  }
}

/**
 * Puts `--artifacts-dir` into the environment, where the layout and every process a step starts read it:
 * the parameter beats a variable that is already set (Atlas: parameter > environment).
 */
export function applyArtifactsDir(
  options: Options,
  env: NodeJS.ProcessEnv,
): void {
  if (options.artifactsDir) {
    env[artifactsDirVariable] = path.resolve(repoRoot, options.artifactsDir);
  }
}

/**
 * `--clean`: deletes the artifacts root and dist/ of the layout.
 *
 * @param layout - The resolved layout.
 * @param root - The repository root the hazard check measures against.
 * @returns What to tell the user.
 * @throws When the artifacts root is one that must not be deleted.
 */
export function cleanRun(layout: Layout, root: string = repoRoot): string {
  const removed = cleanOutputs(layout.artifacts, layout.dist, root);
  return removed.length > 0
    ? `Deleted ${removed.join(', ')}.`
    : 'Nothing to delete.';
}

/** Quotes one argument for cmd.exe, which runs `pnpm.cmd` (Node cannot start a .cmd without a shell). */
function cmdQuote(arg: string): string {
  return /^[\w./=:@\\-]+$/.test(arg) ? arg : `"${arg.replaceAll('"', '\\"')}"`;
}

/** Runs one step; throws when the step fails. */
export function runStep(step: Step): void {
  console.log(`==> ${step.name}`);
  if (step.action) {
    step.action();
    return;
  }
  const [file, ...args] = step.command ?? [];
  if (!file)
    throw new Error(`Step '${step.name}' has neither command nor action.`);
  const env = { ...process.env, ...step.env };
  for (const [k, v] of Object.entries(step.env ?? {})) {
    if (v === undefined) delete env[k];
  }
  const viaShell = process.platform === 'win32' && file === 'pnpm';
  const r = viaShell
    ? spawnSync([file, ...args].map(cmdQuote).join(' '), {
        cwd: repoRoot,
        env,
        stdio: 'inherit',
        shell: true,
      })
    : spawnSync(file === 'node' ? process.execPath : file, args, {
        cwd: repoRoot,
        env,
        stdio: 'inherit',
      });
  if (r.error)
    throw new Error(`Step '${step.name}' did not start: ${r.error.message}`);
  if (r.status !== 0) {
    throw new Error(
      `Step '${step.name}' failed with exit code ${r.status ?? r.signal}.`,
    );
  }
}

if (
  process.argv[1] &&
  fs.realpathSync(process.argv[1]) === fs.realpathSync(import.meta.filename)
) {
  try {
    const options = parseOptions(process.argv.slice(2), process.env);
    if (options.help) {
      console.log(usage());
    } else {
      applyArtifactsDir(options, process.env);
      const layout = resolvedLayout(process.env);
      if (options.clean) {
        // Like Atlas -clean: the outputs go, nothing else runs.
        console.log(cleanRun(layout));
        process.exit(0);
      }
      const file = journalFile(options, layout);
      if (file) {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(
          file,
          `# eng/build.ts ${process.argv.slice(2).join(' ')}\n`,
        );
      }
      runPlan(
        plan(options, layout, process.env, process.platform),
        file ? (line) => fs.appendFileSync(file, `${line}\n`) : undefined,
      );
      console.log('Done.');
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
