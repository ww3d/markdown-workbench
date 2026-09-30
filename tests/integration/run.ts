#!/usr/bin/env node
// Integration runner (docs/DECISIONS.md #48): runs tests/integration/suite in a
// real VS Code through @vscode/test-electron, once against the minimum version
// from engines.vscode and once against the current stable version. Every run
// gets a fresh --user-data-dir under the OS temp directory, --disable-extensions
// and a fresh copy of tests/integration/fixtures/workspace. A second launch on
// the same user-data-dir plays the reloaded window. No Mocha: the suite brings
// its own small runner (suite/index.ts). Before the launch the suite and the
// guard driver are bundled (tsdown.config.ts next to this file), so the
// minimum VS Code loads them whatever module format the sources use.
//
// The guard also runs in a normal window: an extension-development host keeps
// VS Code's backups in memory only (no backup path is registered for it), so
// only a normal window shows whether a backup file of the clipboard text is
// written. For that the runner packages the extension and the test-only guard
// driver (guard/driver) as vsix files, installs both into a fresh
// --extensions-dir of a fresh profile and starts VS Code twice on it (main and
// restart); the driver runs guard/scenario.ts and quits.
//
// The restart measurement P8 (restore/scenario.ts) runs the same way on its own
// profile: an extension-development host writes no workspace storage, so only a
// normal window restores its editors - and the preview - after a restart.
//
// Under Linux run it through `xvfb-run -a` (build.ps1 -Task Integration does).
// MDWB_VERSIONS=1.139.1,stable narrows the versions; MDWB_ONLY=guard runs one
// suite file (and skips the normal-window runs), MDWB_ONLY=window-guard runs
// only the window guard, MDWB_ONLY=window-restore only the restart measurement.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  runTests,
  downloadAndUnzipVSCode,
  resolveCliArgsFromVSCodeExecutablePath,
} from '@vscode/test-electron';
import { build } from 'tsdown';
import type { GuardResult } from './guard/scenario.ts';
import type { RestoreResult } from './restore/scenario.ts';
import { layoutPath } from '../../eng/layout.ts';
import manifest from '../../package.json' with { type: 'json' };

/** Where the downloaded VS Code builds are kept between runs (under the layout's toolset). */
const VSCODE_CACHE = path.join(layoutPath('toolset'), 'vscode-test');

/** One case as the suite reports it. */
interface CaseResult {
  name: string;
  ok: boolean;
  ms?: number;
  error?: string;
}

/** What one launch (a phase on a VS Code version) reports. */
interface PhaseResult {
  version: string;
  phase: string;
  failed: boolean;
  vscodeVersion?: string;
  tests: CaseResult[];
  measurements: Record<string, unknown>;
  error?: string;
}

/** What the result file of a suite launch holds. */
interface SuiteFile {
  vscodeVersion?: string;
  tests: CaseResult[];
  measurements: Record<string, unknown>;
  error?: string;
}

/** What the result file of a normal-window launch holds (guard or restart measurement). */
interface DriverFile extends Partial<GuardResult>, Partial<RestoreResult> {
  vscodeVersion?: string;
  error?: string;
}

const root = path.resolve(import.meta.dirname, '..', '..');
const bundles = layoutPath('integration');
const suiteDir = path.join(import.meta.dirname, 'suite');

// The suite lists its case files for the bundler (suite/index.ts); a case file
// missing there would silently never run, so the list is checked first.
function assertSuitesListed() {
  const index = fs.readFileSync(path.join(suiteDir, 'index.ts'), 'utf8');
  const missing = fs
    .readdirSync(suiteDir)
    .filter((f) => f.endsWith('.int.ts'))
    .filter((f) => !index.includes(`import('./${f}')`));
  if (missing.length)
    throw new Error(`suite/index.ts does not list ${missing.join(', ')}`);
}

// Bundles the suite and the guard driver; the driver's manifest goes next to
// its bundle, which is the folder its vsix is packed from.
async function buildBundles() {
  await build({ config: path.join(import.meta.dirname, 'tsdown.config.ts') });
  fs.copyFileSync(
    path.join(import.meta.dirname, 'guard', 'driver', 'package.json'),
    path.join(bundles, 'driver', 'package.json'),
  );
}

// Windows MAX_PATH: from 260 characters on, a path is too long for the file
// APIs VS Code's Electron uses. Its workbench.html is then not found
// (ERR_FILE_NOT_FOUND) and the test window hangs until the timeout
// (ww3d/markdown-workbench#94).
const WINDOWS_MAX_PATH = 260;
// Where the workbench page lies in an unpacked VS Code: 1.100.0 under
// resources/app/out/vs/code/electron-sandbox/workbench/, 1.139.1 under
// <commit>/resources/app/out/vs/code/electron-browser/workbench/.
const WORKBENCH_HTML =
  '**/resources/app/out/vs/code/*/workbench/workbench.html';

/**
 * Checks, before VS Code starts, that the unpacked workbench.html next to
 * `executable` stays below the Windows path limit; throws a message naming
 * the length and the remedy instead of letting the run hang. Only Windows has
 * the limit, so any other platform passes.
 *
 * @param executable - VS Code executable from downloadAndUnzipVSCode.
 * @param platform - process.platform; a parameter for the tests.
 * @param warn - Where a page it cannot find is reported.
 */
function assertPathFits(
  executable: string,
  platform: string = process.platform,
  warn: (message: string) => void = console.warn,
): void {
  if (platform !== 'win32') return;
  const install = path.dirname(executable);
  const [page] = fs.globSync(WORKBENCH_HTML, { cwd: install });
  if (!page) {
    // A new layout would switch the check off; say so instead of passing.
    warn(`warning: no workbench.html under ${install}, path length unchecked`);
    return;
  }
  const full = path.join(install, page);
  if (full.length < WINDOWS_MAX_PATH) return;
  throw new Error(
    `VS Code's workbench.html lies at a path of ${full.length} characters ` +
      `(Windows limit: ${WINDOWS_MAX_PATH}), where VS Code cannot load it and ` +
      `the run would hang until the timeout:\n  ${full}\n` +
      'Check the repository out under a shorter path and run again.',
  );
}

/** What `cleanup` removes with and warns through; injectable for tests. */
interface CleanupDeps {
  rmSync?: (
    target: string,
    options: { recursive: boolean; force: boolean },
  ) => void;
  warn?: (message: string) => void;
}

/**
 * Removes a temporary path without ever throwing: a failed cleanup (EPERM on
 * Windows, a file still held by a dying VS Code) must not hide the error of
 * the run that led to it. The failure is logged as a warning instead.
 *
 * @param target - File or directory to remove.
 * @param deps - Injectable for tests.
 */
function cleanup(
  target: string,
  { rmSync = fs.rmSync, warn = console.warn }: CleanupDeps = {},
): void {
  try {
    rmSync(target, { recursive: true, force: true });
  } catch (err) {
    warn(`warning: cannot remove ${target}: ${errorCode(err)}`);
  }
}

// The code of a failed file operation (EPERM, EBUSY), else its message.
function errorCode(err: unknown): string {
  if (err instanceof Error) {
    const code: unknown = Reflect.get(err, 'code');
    return code ? String(code) : err.message;
  }
  return String(err);
}

function minimumVersion(): string {
  const version = /(\d+\.\d+\.\d+)/.exec(manifest.engines.vscode)?.[1];
  if (version === undefined)
    throw new Error(
      `cannot read a version from engines.vscode "${manifest.engines.vscode}"`,
    );
  return version;
}

async function runVersion(version: string): Promise<PhaseResult[]> {
  const executable = await downloadAndUnzipVSCode({
    version,
    cachePath: VSCODE_CACHE,
  });
  assertPathFits(executable);
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-it-user-'));
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-it-ws-'));
  fs.cpSync(
    path.join(import.meta.dirname, 'fixtures', 'workspace'),
    workspace,
    {
      recursive: true,
    },
  );
  const resultFile = path.join(
    userDataDir,
    '..',
    `${path.basename(userDataDir)}-result.json`,
  );
  const results: PhaseResult[] = [];
  try {
    for (const phase of ['main', 'reload']) {
      const env = {
        MDWB_PHASE: phase,
        MDWB_USER_DATA_DIR: userDataDir,
        MDWB_WORKSPACE: workspace,
        MDWB_RESULT_FILE: resultFile,
        MDWB_ONLY: process.env.MDWB_ONLY || '',
      };
      let failed: unknown = null;
      try {
        await runTests({
          vscodeExecutablePath: executable,
          extensionDevelopmentPath: root,
          extensionTestsPath: path.join(bundles, 'suite', 'index.cjs'),
          extensionTestsEnv: env,
          launchArgs: [
            workspace,
            '--user-data-dir',
            userDataDir,
            '--disable-extensions',
            '--disable-workspace-trust',
            '--skip-welcome',
            '--skip-release-notes',
          ],
        });
      } catch (err) {
        failed = err;
      }
      const phaseResult: SuiteFile = fs.existsSync(resultFile)
        ? JSON.parse(fs.readFileSync(resultFile, 'utf8'))
        : { tests: [], measurements: {}, error: String(failed) };
      fs.rmSync(resultFile, { force: true });
      results.push({ version, phase, failed: !!failed, ...phaseResult });
      if (failed && phase === 'main') break;
    }
  } finally {
    cleanup(userDataDir);
    cleanup(workspace);
  }
  return results;
}

const WINDOW_TIMEOUT_MS = 180000;

function vsce(args: string[], cwd: string): void {
  const r = spawnSync(
    process.execPath,
    [fileURLToPath(import.meta.resolve('@vscode/vsce/vsce')), ...args],
    {
      cwd,
      encoding: 'utf8',
    },
  );
  if (r.status !== 0)
    throw new Error(`vsce ${args.join(' ')} failed:\n${r.stdout}\n${r.stderr}`);
}

// Packages the extension (dist/ must be built) and the guard driver once.
function packageVsix(dir: string): string[] {
  const ext = path.join(dir, 'markdown-workbench.vsix');
  const driver = path.join(dir, 'guard-driver.vsix');
  vsce(['package', '--no-dependencies', '--out', ext], root);
  vsce(
    [
      'package',
      '--no-dependencies',
      '--allow-missing-repository',
      '--skip-license',
      '--out',
      driver,
    ],
    path.join(bundles, 'driver'),
  );
  return [ext, driver];
}

function launchWindow(
  executable: string,
  args: string[],
  env: Record<string, string>,
): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const child = spawn(executable, args, {
      env: { ...process.env, ...env },
      stdio: 'ignore',
    });
    const timer = setTimeout(() => {
      child.kill();
      reject(
        new Error(`VS Code window did not quit within ${WINDOW_TIMEOUT_MS} ms`),
      );
    }, WINDOW_TIMEOUT_MS);
    child.on('exit', () => {
      clearTimeout(timer);
      resolve();
    });
    child.on('error', reject);
  });
}

/** A fresh profile with the vsix files installed, and a fresh copy of the workspace. */
interface WindowProfile {
  executable: string;
  userDataDir: string;
  extensionsDir: string;
  workspace: string;
  resultFile: string;
}

async function windowProfile(
  version: string,
  vsixes: string[],
  prefix: string,
): Promise<WindowProfile> {
  const executable = await downloadAndUnzipVSCode({
    version,
    cachePath: VSCODE_CACHE,
  });
  assertPathFits(executable);
  const [cli] = resolveCliArgsFromVSCodeExecutablePath(executable);
  if (cli === undefined)
    throw new Error(`no VS Code CLI found for ${executable}`);
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), `${prefix}-user-`));
  const profile: WindowProfile = {
    executable,
    userDataDir,
    extensionsDir: fs.mkdtempSync(path.join(os.tmpdir(), `${prefix}-ext-`)),
    workspace: fs.mkdtempSync(path.join(os.tmpdir(), `${prefix}-ws-`)),
    resultFile: path.join(
      os.tmpdir(),
      `${path.basename(userDataDir)}-result.json`,
    ),
  };
  try {
    fs.cpSync(
      path.join(import.meta.dirname, 'fixtures', 'workspace'),
      profile.workspace,
      { recursive: true },
    );
    for (const vsix of vsixes) {
      const r = spawnSync(
        cli,
        [
          '--install-extension',
          vsix,
          '--extensions-dir',
          profile.extensionsDir,
          '--user-data-dir',
          userDataDir,
        ],
        { encoding: 'utf8', shell: process.platform === 'win32' },
      );
      if (r.status !== 0)
        throw new Error(`installing ${vsix} failed:\n${r.stdout}\n${r.stderr}`);
    }
  } catch (err) {
    removeProfile(profile);
    throw err;
  }
  return profile;
}

function removeProfile(p: WindowProfile): void {
  for (const d of [p.userDataDir, p.extensionsDir, p.workspace]) cleanup(d);
}

// Starts VS Code on the profile with the driver's inputs and returns what the
// driver wrote before it quit.
async function launchDriver(
  p: WindowProfile,
  env: Record<string, string>,
): Promise<DriverFile> {
  await launchWindow(
    p.executable,
    [
      p.workspace,
      '--user-data-dir',
      p.userDataDir,
      '--extensions-dir',
      p.extensionsDir,
      '--skip-welcome',
      '--skip-release-notes',
      '--disable-workspace-trust',
      '--disable-updates',
      '--no-sandbox',
    ],
    {
      ...env,
      MDWB_USER_DATA_DIR: p.userDataDir,
      MDWB_WORKSPACE: p.workspace,
      MDWB_RESULT_FILE: p.resultFile,
      // Taken right before the spawn: the restart measurement counts from here.
      MDWB_LAUNCHED_AT: String(Date.now()),
    },
  );
  const out: DriverFile = fs.existsSync(p.resultFile)
    ? JSON.parse(fs.readFileSync(p.resultFile, 'utf8'))
    : { error: 'the driver wrote no result' };
  fs.rmSync(p.resultFile, { force: true });
  return out;
}

async function runWindowGuard(
  version: string,
  vsixes: string[],
): Promise<PhaseResult[]> {
  const p = await windowProfile(version, vsixes, 'mdwb-guard');
  const results: PhaseResult[] = [];
  try {
    for (const phase of ['main', 'reload']) {
      const out = await launchDriver(p, { MDWB_DRIVER_PHASE: phase });
      const bad = out.error
        ? [out.error]
        : Object.entries(out.hits ?? {}).filter(([, l]) => l.length);
      results.push({
        version,
        vscodeVersion: out.vscodeVersion,
        phase: `window guard (${phase})`,
        failed: false,
        tests: [
          {
            name: `guard in a normal window, ${phase}: no backup, dirty page, write, log or file with the clipboard text`,
            ok: bad.length === 0,
            error: JSON.stringify(bad),
          },
        ],
        measurements: out.measurements || {},
      });
    }
  } finally {
    removeProfile(p);
  }
  return results;
}

// The workspace storage databases of a profile. VS Code writes one per
// workspace when it quits; the editors and the webview states live there.
function workspaceStateDbs(userDataDir: string): string[] {
  const dir = path.join(userDataDir, 'User', 'workspaceStorage');
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .map((id) => path.join(dir, id, 'state.vscdb'))
    .filter((f) => fs.existsSync(f));
}

const RESTORE_CASES: Record<string, string> = {
  main: 'restart in a normal window, main: the side preview renders and the quit writes the workspace storage',
  restart:
    'restart in a normal window, restart: the restored preview shows its stand with 0 host renders (P8)',
};

// P8 (restore/scenario.ts): the side preview renders, VS Code quits, and the
// same profile starts again and restores the preview.
async function runWindowRestore(
  version: string,
  vsixes: string[],
): Promise<PhaseResult[]> {
  const p = await windowProfile(version, vsixes, 'mdwb-restore');
  const results: PhaseResult[] = [];
  try {
    for (const phase of ['main', 'restart']) {
      const out = await launchDriver(p, {
        MDWB_DRIVER_SCENARIO: 'restore',
        MDWB_DRIVER_PHASE: phase,
      });
      const failures = out.error ? [out.error] : [...(out.failures ?? [])];
      const measurements = { ...out.measurements };
      if (phase === 'main') {
        const dbs = workspaceStateDbs(p.userDataDir);
        measurements.stateDbBytes = dbs.map((f) => fs.statSync(f).size);
        if (!dbs.length)
          failures.push('no workspace state.vscdb after the quit');
      }
      results.push({
        version,
        vscodeVersion: out.vscodeVersion,
        phase: `window restore (${phase})`,
        failed: false,
        tests: [
          {
            name: RESTORE_CASES[phase] ?? phase,
            ok: failures.length === 0,
            error: JSON.stringify(failures),
          },
        ],
        measurements,
      });
      if (failures.length) break;
    }
  } finally {
    removeProfile(p);
  }
  return results;
}

async function main() {
  const versions = process.env.MDWB_VERSIONS
    ? process.env.MDWB_VERSIONS.split(',')
    : [minimumVersion(), 'stable'];
  const all: PhaseResult[] = [];
  const only = process.env.MDWB_ONLY;
  const onlyWindow = only === 'window-guard' || only === 'window-restore';
  const guard = !only || only === 'window-guard';
  const restore = !only || only === 'window-restore';
  assertSuitesListed();
  await buildBundles();
  fs.mkdirSync(layoutPath('tmp'), { recursive: true });
  const vsixDir = fs.mkdtempSync(path.join(layoutPath('tmp'), 'vsix-'));
  try {
    const vsixes = guard || restore ? packageVsix(vsixDir) : [];
    for (const v of versions) {
      if (!onlyWindow) all.push(...(await runVersion(v)));
      if (guard) all.push(...(await runWindowGuard(v, vsixes)));
      if (restore) all.push(...(await runWindowRestore(v, vsixes)));
    }
  } finally {
    cleanup(vsixDir);
  }
  let failed = false;
  for (const r of all) {
    console.log(
      `\n== VS Code ${r.vscodeVersion || r.version} - phase ${r.phase}`,
    );
    for (const t of r.tests) {
      console.log(
        `${t.ok ? 'ok  ' : 'FAIL'} ${t.name}${t.ok ? '' : `\n     ${t.error}`}`,
      );
      if (!t.ok) failed = true;
    }
    if (r.error) console.log(`run error: ${r.error}`);
    if (Object.keys(r.measurements || {}).length) {
      console.log(`measurements: ${JSON.stringify(r.measurements, null, 2)}`);
    }
    // A restart phase without cases is fine when MDWB_ONLY picked a suite
    // that has none; a main phase without cases never is.
    const empty =
      !r.tests.length && (r.phase === 'main' || !process.env.MDWB_ONLY);
    if (r.failed || empty) failed = true;
  }
  console.log(failed ? '\nINTEGRATION FAILED' : '\nINTEGRATION PASSED');
  process.exit(failed ? 1 : 0);
}

if (import.meta.main) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

export { assertPathFits, cleanup, WINDOWS_MAX_PATH };
