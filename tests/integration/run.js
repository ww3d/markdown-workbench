#!/usr/bin/env node
// Integration runner (docs/DECISIONS.md #48): runs tests/integration/suite in a
// real VS Code through @vscode/test-electron, once against the minimum version
// from engines.vscode and once against the current stable version. Every run
// gets a fresh --user-data-dir under the OS temp directory, --disable-extensions
// and a fresh copy of tests/integration/fixtures/workspace. A second launch on
// the same user-data-dir plays the reloaded window. No Mocha: the suite brings
// its own small runner (suite/index.js). Before the launch the suite and the
// guard driver are bundled (tsdown.config.ts next to this file), so the
// minimum VS Code loads them whatever module format the sources use.
//
// The guard also runs in a normal window: an extension-development host keeps
// VS Code's backups in memory only (no backup path is registered for it), so
// only a normal window shows whether a backup file of the clipboard text is
// written. For that the runner packages the extension and the test-only guard
// driver (guard/driver) as vsix files, installs both into a fresh
// --extensions-dir of a fresh profile and starts VS Code twice on it (main and
// restart); the driver runs guard/scenario.js and quits.
//
// Under Linux run it through `xvfb-run -a` (build.ps1 -Task Integration does).
// MDWB_VERSIONS=1.139.1,stable narrows the versions; MDWB_ONLY=guard runs one
// suite file (and skips the window guard), MDWB_ONLY=window-guard runs only the
// window guard.

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
import { layoutPath } from '../../eng/layout.ts';
import manifest from '../../package.json' with { type: 'json' };

const root = path.resolve(import.meta.dirname, '..', '..');
const bundles = layoutPath('integration');
const suiteDir = path.join(import.meta.dirname, 'suite');

// The suite lists its case files for the bundler (suite/index.js); a case file
// missing there would silently never run, so the list is checked first.
function assertSuitesListed() {
  const index = fs.readFileSync(path.join(suiteDir, 'index.js'), 'utf8');
  const missing = fs
    .readdirSync(suiteDir)
    .filter((f) => f.endsWith('.int.js'))
    .filter((f) => !index.includes(`import('./${f}')`));
  if (missing.length)
    throw new Error(`suite/index.js does not list ${missing.join(', ')}`);
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

function minimumVersion() {
  const m = /(\d+\.\d+\.\d+)/.exec(manifest.engines.vscode);
  if (!m)
    throw new Error(
      `cannot read a version from engines.vscode "${manifest.engines.vscode}"`,
    );
  return m[1];
}

async function runVersion(version) {
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
  const results = [];
  try {
    for (const phase of ['main', 'reload']) {
      const env = {
        MDWB_PHASE: phase,
        MDWB_USER_DATA_DIR: userDataDir,
        MDWB_WORKSPACE: workspace,
        MDWB_RESULT_FILE: resultFile,
        MDWB_ONLY: process.env.MDWB_ONLY || '',
      };
      let failed = null;
      try {
        await runTests({
          version,
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
      const phaseResult = fs.existsSync(resultFile)
        ? JSON.parse(fs.readFileSync(resultFile, 'utf8'))
        : { tests: [], measurements: {}, error: String(failed) };
      fs.rmSync(resultFile, { force: true });
      results.push({ version, phase, failed: !!failed, ...phaseResult });
      if (failed && phase === 'main') break;
    }
  } finally {
    fs.rmSync(userDataDir, { recursive: true, force: true });
    fs.rmSync(workspace, { recursive: true, force: true });
  }
  return results;
}

const WINDOW_TIMEOUT_MS = 180000;

function vsce(args, cwd) {
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
function packageVsix(dir) {
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

function launchWindow(executable, args, env) {
  return new Promise((resolve, reject) => {
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

async function runWindowGuard(version, vsixes) {
  const executable = await downloadAndUnzipVSCode(version);
  const [cli] = resolveCliArgsFromVSCodeExecutablePath(executable);
  const userDataDir = fs.mkdtempSync(
    path.join(os.tmpdir(), 'mdwb-guard-user-'),
  );
  const extensionsDir = fs.mkdtempSync(
    path.join(os.tmpdir(), 'mdwb-guard-ext-'),
  );
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-guard-ws-'));
  fs.cpSync(
    path.join(import.meta.dirname, 'fixtures', 'workspace'),
    workspace,
    {
      recursive: true,
    },
  );
  const resultFile = path.join(
    os.tmpdir(),
    `${path.basename(userDataDir)}-result.json`,
  );
  const results = [];
  try {
    for (const vsix of vsixes) {
      const r = spawnSync(
        cli,
        [
          '--install-extension',
          vsix,
          '--extensions-dir',
          extensionsDir,
          '--user-data-dir',
          userDataDir,
        ],
        { encoding: 'utf8', shell: process.platform === 'win32' },
      );
      if (r.status !== 0)
        throw new Error(`installing ${vsix} failed:\n${r.stdout}\n${r.stderr}`);
    }
    for (const phase of ['main', 'reload']) {
      await launchWindow(
        executable,
        [
          workspace,
          '--user-data-dir',
          userDataDir,
          '--extensions-dir',
          extensionsDir,
          '--skip-welcome',
          '--skip-release-notes',
          '--disable-workspace-trust',
          '--disable-updates',
          '--no-sandbox',
        ],
        {
          MDWB_DRIVER_PHASE: phase,
          MDWB_USER_DATA_DIR: userDataDir,
          MDWB_WORKSPACE: workspace,
          MDWB_RESULT_FILE: resultFile,
        },
      );
      const out = fs.existsSync(resultFile)
        ? JSON.parse(fs.readFileSync(resultFile, 'utf8'))
        : { error: 'the driver wrote no result' };
      fs.rmSync(resultFile, { force: true });
      const bad = out.error
        ? [out.error]
        : Object.entries(out.hits).filter(([, l]) => l.length);
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
    for (const d of [userDataDir, extensionsDir, workspace])
      fs.rmSync(d, { recursive: true, force: true });
  }
  return results;
}

async function main() {
  const versions = process.env.MDWB_VERSIONS
    ? process.env.MDWB_VERSIONS.split(',')
    : [minimumVersion(), 'stable'];
  const all = [];
  const onlyWindow = process.env.MDWB_ONLY === 'window-guard';
  assertSuitesListed();
  await buildBundles();
  fs.mkdirSync(layoutPath('tmp'), { recursive: true });
  const vsixDir = fs.mkdtempSync(path.join(layoutPath('tmp'), 'vsix-'));
  try {
    const vsixes =
      !process.env.MDWB_ONLY || onlyWindow ? packageVsix(vsixDir) : null;
    for (const v of versions) {
      if (!onlyWindow) all.push(...(await runVersion(v)));
      if (vsixes) all.push(...(await runWindowGuard(v, vsixes)));
    }
  } finally {
    fs.rmSync(vsixDir, { recursive: true, force: true });
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

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
