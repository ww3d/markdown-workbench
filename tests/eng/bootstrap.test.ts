// The bootstrap (eng/common/tools.ps1 under Windows PowerShell 5.1, tools.sh under bash) runs for
// real here, against a local stand-in for nodejs.org: the pin is read from package.json, a Node on the
// PATH is used only in the pinned version, a wrong one is never used (the pin is fetched instead),
// and a download whose checksum differs from SHASUMS256.txt aborts without installing anything.
// The pnpm fetch is checked with a recording `npm`; the real npm run is the consumer-topology probe.
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert';
import { spawn, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { repoRoot } from '../../eng/layout.ts';

const isWindows = process.platform === 'win32';
/** The pin every case uses: the running Node, so a fetched stand-in (a copy of it) reports it. */
const pin = process.versions.node;
const pnpmPin = '12.6.0';
/** A pin whose archive holds the running Node, so the fetched Node reports another version than the pin. */
const mislabeledPin = '99.0.0';
/** The platform part of the .tools folder names, as nodejs.org names it (e.g. win-x64). */
const platform = archiveName(pin)
  .replace(/^node-v[\d.]+-/, '')
  .replace(/\.(zip|tar\.gz)$/, '');

/** The archive name tools.* ask nodejs.org for on this machine. */
function archiveName(version: string): string {
  const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
  return isWindows
    ? `node-v${version}-win-${arch}.zip`
    : `node-v${version}-${process.platform === 'darwin' ? 'darwin' : 'linux'}-${arch}.tar.gz`;
}

/** Hard link, falling back to a copy where the link crosses a volume. */
function linkOrCopy(from: string, to: string): void {
  try {
    fs.linkSync(from, to);
  } catch {
    fs.copyFileSync(from, to);
  }
}

let work: string;
let archiveFile: string;
let archiveSha: string;
let server: http.Server;
let base: string;
const hits: string[] = [];
/** What the stand-in serves as the archive's checksum line; a case may break it. */
let shaOverride: string | undefined;

before(async () => {
  work = fs.mkdtempSync(path.join(os.tmpdir(), 'mw-bootstrap-'));
  // The stand-in distribution: one folder holding a copy of the running Node, packed like nodejs.org's.
  const inner = `node-v${pin}-standin`;
  const bin = path.join(work, inner, isWindows ? '' : 'bin');
  fs.mkdirSync(bin, { recursive: true });
  linkOrCopy(process.execPath, path.join(bin, isWindows ? 'node.exe' : 'node'));
  archiveFile = path.join(work, archiveName(pin));
  // Windows' own bsdtar writes zip (-a picks the format from the name); a GNU tar on the PATH would not.
  const packed = spawnSync(
    isWindows
      ? path.join(
          process.env.SystemRoot ?? 'C:\\Windows',
          'System32',
          'tar.exe',
        )
      : 'tar',
    [isWindows ? '-a' : '-z', '-cf', path.basename(archiveFile), inner],
    { cwd: work },
  );
  assert.strictEqual(packed.status, 0, String(packed.stderr));
  archiveSha = crypto
    .createHash('sha256')
    .update(fs.readFileSync(archiveFile))
    .digest('hex');
  server = http.createServer((req, res) => {
    hits.push(req.url ?? '');
    // Two releases are "published": the pin (a real stand-in) and mislabeledPin, whose archive holds the
    // same Node, so what runs after the install is not the version the pin names.
    const version = /^\/v(\d+\.\d+\.\d+)\//.exec(req.url ?? '')?.[1];
    const served = version === pin || version === mislabeledPin;
    if (served && req.url === `/v${version}/SHASUMS256.txt`) {
      res.setHeader('content-type', 'text/plain');
      res.end(
        `${shaOverride ?? archiveSha}  ${archiveName(String(version))}\n`,
      );
    } else if (
      served &&
      req.url === `/v${version}/${archiveName(String(version))}`
    ) {
      res.end(fs.readFileSync(archiveFile));
    } else {
      res.statusCode = 404;
      res.end();
    }
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(() => {
  server?.close();
  fs.rmSync(work, { recursive: true, force: true });
});

/** A throwaway repo root holding the bootstrap scripts and a package.json with the given pins. */
function makeRepo(manifest: Record<string, unknown>): string {
  const dir = fs.mkdtempSync(path.join(work, 'repo-'));
  fs.mkdirSync(path.join(dir, 'eng', 'common'), { recursive: true });
  for (const f of ['tools.ps1', 'tools.sh']) {
    fs.copyFileSync(
      path.join(repoRoot, 'eng', 'common', f),
      path.join(dir, 'eng', 'common', f),
    );
  }
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify(manifest));
  return dir;
}

const manifest = (over: Record<string, unknown> = {}) => ({
  devEngines: { runtime: { name: 'node', version: pin } },
  packageManager: `pnpm@${pnpmPin}`,
  ...over,
});

/** A directory on the PATH holding a command that prints `version` for --version. */
function fakeTool(name: string, version: string): string {
  const dir = fs.mkdtempSync(path.join(work, `fake-${name}-`));
  if (isWindows) {
    fs.writeFileSync(path.join(dir, `${name}.cmd`), `@echo ${version}\r\n`);
  } else {
    const file = path.join(dir, name);
    fs.writeFileSync(file, `#!/bin/sh\necho ${version}\n`);
    fs.chmodSync(file, 0o755);
  }
  return dir;
}

/**
 * A recording `npm` that "installs" a pnpm printing the requested version: its arguments go to `log`, and the
 * value of NODE_USE_SYSTEM_CA it was started with goes to `caLog`.
 */
function recordingNpm(): { npmDir: string; log: string; caLog: string } {
  const npmDir = fs.mkdtempSync(path.join(work, 'fake-npm-'));
  const log = path.join(npmDir, 'npm.log');
  const caLog = path.join(npmDir, 'ca.log');
  if (isWindows) {
    fs.writeFileSync(
      path.join(npmDir, 'npm.cmd'),
      [
        '@echo off',
        `echo %* > "${log}"`,
        // The space before > keeps a value ending in a digit from turning into a handle redirect (1>).
        `echo ca=%NODE_USE_SYSTEM_CA% > "${caLog}"`,
        // %3 is the prefix (npm install --prefix <dir> ...).
        'mkdir "%~3\\node_modules\\.bin" 2>nul',
        'echo @echo 12.6.0 > "%~3\\node_modules\\.bin\\pnpm.cmd"',
        '',
      ].join('\r\n'),
    );
  } else {
    const file = path.join(npmDir, 'npm');
    fs.writeFileSync(
      file,
      [
        '#!/bin/sh',
        `echo "$@" > "${log}"`,
        `echo "ca=\${NODE_USE_SYSTEM_CA-unset}" > "${caLog}"`,
        'mkdir -p "$3/node_modules/.bin"',
        `printf '#!/bin/sh\\necho 12.6.0\\n' > "$3/node_modules/.bin/pnpm"`,
        'chmod +x "$3/node_modules/.bin/pnpm"',
        '',
      ].join('\n'),
    );
    fs.chmodSync(file, 0o755);
  }
  return { npmDir, log, caLog };
}

/** A command on the PATH that runs `script` in place of the real one (the bash cases only). */
function shimTool(name: string, script: string): string {
  const dir = fs.mkdtempSync(path.join(work, `shim-${name}-`));
  const file = path.join(dir, name);
  fs.writeFileSync(file, `#!/bin/sh\n${script}\n`);
  fs.chmodSync(file, 0o755);
  return dir;
}

/** The download folders install_node left in the repo's .tools/node. */
function downloadFolders(repo: string): string[] {
  const dir = path.join(repo, '.tools', 'node');
  return fs.existsSync(dir)
    ? fs.readdirSync(dir).filter((n) => n.startsWith('.download-'))
    : [];
}

interface Result {
  readonly status: number | null;
  readonly out: string;
}

/**
 * Runs `body` after loading the bootstrap, in the shell the script is written for, with a PATH made
 * of `pathDirs` and the system's own tools - and no Node, so nothing but the bootstrap provides one.
 */
async function run(
  repo: string,
  body: string,
  pathDirs: string[] = [],
  extraEnv: NodeJS.ProcessEnv = {},
): Promise<Result> {
  const system = isWindows
    ? [
        path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32'),
        path.join(
          process.env.SystemRoot ?? 'C:\\Windows',
          'System32',
          'WindowsPowerShell',
          'v1.0',
        ),
      ]
    : ['/usr/bin', '/bin'];
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    PATH: [...pathDirs, ...system].join(path.delimiter),
    MARKDOWN_WORKBENCH_NODE_DIST_URL: base,
  };
  // The caller's own value must not decide what the bootstrap does by default.
  delete env.NODE_USE_SYSTEM_CA;
  Object.assign(env, extraEnv);
  // A Windows PowerShell started from pwsh 7 would load pwsh's modules; a normal shell does not.
  delete env.PSModulePath;
  const driver = path.join(repo, isWindows ? 'driver.ps1' : 'driver.sh');
  const tools = path.join(
    repo,
    'eng',
    'common',
    isWindows ? 'tools.ps1' : 'tools.sh',
  );
  fs.writeFileSync(
    driver,
    isWindows ? `. '${tools}'\n${body}\n` : `set -u\n. '${tools}'\n${body}\n`,
  );
  // Async: the stand-in server runs in this process and must keep answering while the script downloads.
  const child = isWindows
    ? spawn(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', driver],
        { env },
      )
    : spawn('bash', [driver], { env });
  let out = '';
  child.stdout.on('data', (d: Buffer) => {
    out += d;
  });
  child.stderr.on('data', (d: Buffer) => {
    out += d;
  });
  const status = await new Promise<number | null>((resolve, reject) => {
    child.on('error', reject);
    child.on('close', resolve);
  });
  // PowerShell wraps its error display at the terminal width; undo it so messages match whole.
  return { status, out: out.replace(/\r?\n\s*\|\s?/g, ' ') };
}

const sh = {
  nodePin: isWindows ? 'Get-NodePin' : 'get_node_pin',
  pnpmPin: isWindows ? 'Get-PnpmPin' : 'get_pnpm_pin',
  initNode: isWindows ? 'Initialize-Node' : 'initialize_node',
  initPnpm: isWindows ? 'Initialize-Pnpm' : 'initialize_pnpm',
  enableCa: isWindows ? 'Enable-SystemCa' : 'enable_system_ca',
  initToolchain: isWindows ? 'Initialize-Toolchain' : 'initialize_toolchain',
  /** Prints what NODE_USE_SYSTEM_CA is in the bootstrap's shell ("ca=" or "ca=unset": not set). */
  showCa: isWindows
    ? 'Write-Output "ca=$env:NODE_USE_SYSTEM_CA"'
    : `echo "ca=\${NODE_USE_SYSTEM_CA-unset}"`,
  /** Prints the version `node` resolves to once the bootstrap has set the PATH. */
  nodeVersion: isWindows ? '& node --version' : 'node --version',
};

describe(`bootstrap (${isWindows ? 'tools.ps1, Windows PowerShell 5.1' : 'tools.sh, bash'})`, () => {
  test('the Node pin is read from devEngines.runtime, the pnpm pin from packageManager', async () => {
    const repo = makeRepo(manifest());
    const r = await run(repo, `${sh.nodePin}\n${sh.pnpmPin}`);
    assert.strictEqual(r.status, 0, r.out);
    assert.deepStrictEqual(r.out.trim().split(/\s+/), [pin, pnpmPin]);
  });

  test('a hash suffix on the pnpm pin is dropped', async () => {
    const repo = makeRepo(
      manifest({ packageManager: `pnpm@${pnpmPin}+sha512.abc` }),
    );
    const r = await run(repo, sh.pnpmPin);
    assert.strictEqual(r.out.trim(), pnpmPin);
  });

  test('a Node pin that is no exact version stops the bootstrap', async () => {
    for (const bad of ['>=26', '^26.0.0', '26']) {
      const repo = makeRepo(
        manifest({ devEngines: { runtime: { name: 'node', version: bad } } }),
      );
      const r = await run(repo, sh.nodePin);
      assert.notStrictEqual(r.status, 0, bad);
      assert.match(
        r.out,
        /devEngines\.runtime must name node with an exact version/,
      );
    }
  });

  test('a missing Node pin stops the bootstrap', async () => {
    const repo = makeRepo({ packageManager: `pnpm@${pnpmPin}` });
    const r = await run(repo, sh.nodePin);
    assert.notStrictEqual(r.status, 0);
    assert.match(r.out, /devEngines\.runtime must name node/);
  });

  test('a packageManager that is not pnpm stops the bootstrap', async () => {
    const repo = makeRepo(manifest({ packageManager: 'yarn@4.0.0' }));
    const r = await run(repo, sh.pnpmPin);
    assert.notStrictEqual(r.status, 0);
    assert.match(r.out, /is not 'pnpm@<version>'/);
  });

  test('a Node in the pinned version on the PATH is used, nothing is fetched', async () => {
    const repo = makeRepo(manifest());
    hits.length = 0;
    const r = await run(repo, sh.initNode, [fakeTool('node', pin)]);
    assert.strictEqual(r.status, 0, r.out);
    assert.match(r.out, /using the one on the PATH/);
    assert.deepStrictEqual(hits, []);
    assert.ok(!fs.existsSync(path.join(repo, '.tools')));
  });

  test('a Node in another version on the PATH is never used: the pin is fetched', async () => {
    const repo = makeRepo(manifest());
    const r = await run(repo, `${sh.initNode}\n${sh.nodeVersion}`, [
      fakeTool('node', '1.0.0'),
    ]);
    assert.strictEqual(r.status, 0, r.out);
    assert.match(r.out, /the one on the PATH is 1\.0\.0/);
    assert.match(r.out, new RegExp(`Node ${pin} ready`));
    // After the bootstrap `node` is the fetched one, not the stand-in that said 1.0.0.
    assert.strictEqual(
      r.out.trim().split(/\s+/).at(-1)?.replace(/^v/, ''),
      pin,
    );
    assert.ok(
      fs.existsSync(path.join(repo, '.tools', 'node', `${pin}-${platform}`)),
    );
  });

  test('no Node at all: the pin is fetched into .tools and reused on the next run', async () => {
    const repo = makeRepo(manifest());
    hits.length = 0;
    const first = await run(repo, sh.initNode);
    assert.strictEqual(first.status, 0, first.out);
    assert.match(first.out, /none on the PATH/);
    const fetched = hits.length;
    assert.ok(fetched > 0);
    const second = await run(repo, sh.initNode);
    assert.strictEqual(second.status, 0, second.out);
    assert.strictEqual(
      hits.length,
      fetched,
      'the second run downloads nothing',
    );
  });

  test('a download whose checksum differs from SHASUMS256.txt aborts and installs nothing', async () => {
    const repo = makeRepo(manifest());
    shaOverride = '0'.repeat(64);
    try {
      const r = await run(repo, sh.initNode);
      assert.notStrictEqual(r.status, 0);
      assert.match(r.out, /[Cc]hecksum mismatch/);
      assert.match(r.out, /Nothing was installed/);
    } finally {
      shaOverride = undefined;
    }
    assert.ok(
      !fs.existsSync(path.join(repo, '.tools', 'node', `${pin}-${platform}`)),
    );
  });

  test('a fetched Node that is not the pinned version is an error, not a pass', async () => {
    const repo = makeRepo(
      manifest({
        devEngines: { runtime: { name: 'node', version: mislabeledPin } },
      }),
    );
    const r = await run(repo, sh.initNode);
    assert.notStrictEqual(r.status, 0);
    assert.match(r.out, /still not what runs after the install/);
  });

  test('a SHASUMS256.txt that does not list the archive aborts', async () => {
    const repo = makeRepo(
      manifest({ devEngines: { runtime: { name: 'node', version: '9.9.9' } } }),
    );
    const r = await run(repo, sh.initNode);
    assert.notStrictEqual(r.status, 0);
  });

  test('pnpm in the pinned version on the PATH is used, npm is not called', async () => {
    const repo = makeRepo(manifest());
    const r = await run(repo, sh.initPnpm, [fakeTool('pnpm', pnpmPin)]);
    assert.strictEqual(r.status, 0, r.out);
    assert.match(r.out, /using the one on the PATH/);
    assert.ok(!fs.existsSync(path.join(repo, '.tools')));
  });

  test('pnpm in another version is never used: the pin is installed with npm into .tools', async () => {
    const repo = makeRepo(manifest());
    const { npmDir, log } = recordingNpm();
    const r = await run(repo, sh.initPnpm, [
      fakeTool('pnpm', '10.0.0'),
      npmDir,
    ]);
    assert.strictEqual(r.status, 0, r.out);
    assert.match(r.out, /the one on the PATH is 10\.0\.0/);
    assert.match(r.out, /pnpm 12\.6\.0 ready/);
    const call = fs.readFileSync(log, 'utf8');
    assert.match(call, /install/);
    assert.match(call, /pnpm@12\.6\.0/);
    assert.ok(
      call.includes(
        path.join(repo, '.tools', 'pnpm', `${pnpmPin}-${platform}`),
      ),
    );
  });

  test('the .tools folders name the platform, so one checkout builds from Windows and from WSL', async () => {
    const repo = makeRepo(manifest());
    const r = await run(repo, sh.initNode);
    assert.strictEqual(r.status, 0, r.out);
    assert.ok(r.out.includes(`.tools/node/${pin}-${platform}`), r.out);
  });

  test('the toolchain trusts the system certificates (a proxy with its own CA); a value of the caller stays', async () => {
    const repo = makeRepo(manifest());
    const onPath = [fakeTool('node', pin), fakeTool('pnpm', pnpmPin)];
    const set = await run(repo, `${sh.initToolchain}\n${sh.showCa}`, onPath);
    assert.strictEqual(set.status, 0, set.out);
    assert.match(set.out, /ca=1\b/);
    const kept = await run(repo, `${sh.initToolchain}\n${sh.showCa}`, onPath, {
      NODE_USE_SYSTEM_CA: '0',
    });
    assert.match(kept.out, /ca=0\b/);
    const none = await run(repo, sh.showCa);
    assert.doesNotMatch(
      none.out,
      /ca=1\b/,
      'sourcing the script alone sets nothing',
    );
  });

  test('the npm that fetches pnpm is started with the system certificates enabled', async () => {
    const repo = makeRepo(manifest());
    const { npmDir, caLog } = recordingNpm();
    const r = await run(repo, `${sh.enableCa}\n${sh.initPnpm}`, [npmDir]);
    assert.strictEqual(r.status, 0, r.out);
    assert.match(fs.readFileSync(caLog, 'utf8'), /^ca=1\s*$/);
  });

  test('a pnpm install that does not yield the pin is an error, not a pass', async () => {
    const repo = makeRepo(manifest());
    const npmDir = fs.mkdtempSync(path.join(work, 'fake-npm-'));
    if (isWindows) {
      fs.writeFileSync(
        path.join(npmDir, 'npm.cmd'),
        '@echo off\r\nexit /b 0\r\n',
      );
    } else {
      fs.writeFileSync(path.join(npmDir, 'npm'), '#!/bin/sh\nexit 0\n');
      fs.chmodSync(path.join(npmDir, 'npm'), 0o755);
    }
    const r = await run(repo, sh.initPnpm, [npmDir]);
    assert.notStrictEqual(r.status, 0);
    assert.match(r.out, /still not what runs after the install/);
  });
});

// tools.sh only: the PowerShell version cleans up in a finally block. Shimmed system commands stand in for a
// full disk (mktemp, mv) and for Ctrl-C (a signal to the shell during the unpack).
describe('tools.sh keeps no half-installed Node behind', {
  skip: isWindows ? 'tools.sh is bash; the Linux run covers it' : false,
}, () => {
  test('a mktemp that fails stops with a message and downloads nothing', async () => {
    const repo = makeRepo(manifest());
    hits.length = 0;
    const r = await run(repo, sh.initNode, [shimTool('mktemp', 'exit 1')]);
    assert.notStrictEqual(r.status, 0);
    assert.match(r.out, /cannot create a download folder/);
    assert.deepStrictEqual(
      hits,
      [],
      'nothing was fetched into a missing folder',
    );
  });

  test('a mv that fails stops with a message and leaves no download folder', async () => {
    const repo = makeRepo(manifest());
    const r = await run(repo, sh.initNode, [shimTool('mv', 'exit 1')]);
    assert.notStrictEqual(r.status, 0);
    assert.match(r.out, /cannot move the unpacked Node/);
    assert.deepStrictEqual(downloadFolders(repo), []);
  });

  for (const [signal, code] of [
    ['HUP', 129],
    ['INT', 130],
    ['TERM', 143],
  ] as const) {
    test(`a ${signal} during the unpack removes the download folder and runs the caller's exit trap`, async () => {
      const repo = makeRepo(manifest());
      // The shell gets the signal while its child runs; its trap then ends it with 128 + the signal number.
      const r = await run(
        repo,
        `trap 'echo caller-trap-ran' EXIT\n${sh.initNode}`,
        [shimTool('tar', `kill -${signal} $PPID\nexit 1`)],
      );
      assert.strictEqual(r.status, code, r.out);
      assert.match(r.out, /caller-trap-ran/);
      assert.deepStrictEqual(downloadFolders(repo), []);
    });
  }

  test('an exit trap of the caller survives a fetch, a failed one included', async () => {
    const body = `trap 'echo caller-trap-ran' EXIT\n${sh.initNode}`;
    const fetched = await run(makeRepo(manifest()), body);
    assert.strictEqual(fetched.status, 0, fetched.out);
    assert.match(fetched.out, /caller-trap-ran/);
    shaOverride = '0'.repeat(64);
    try {
      const failed = await run(makeRepo(manifest()), body);
      assert.notStrictEqual(failed.status, 0);
      assert.match(failed.out, /caller-trap-ran/);
    } finally {
      shaOverride = undefined;
    }
  });

  test('a failed checksum leaves no download folder either', async () => {
    const repo = makeRepo(manifest());
    shaOverride = '0'.repeat(64);
    try {
      const r = await run(repo, sh.initNode);
      assert.notStrictEqual(r.status, 0);
    } finally {
      shaOverride = undefined;
    }
    assert.deepStrictEqual(downloadFolders(repo), []);
  });
});
