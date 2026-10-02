// The root scripts are the one command a clone needs (Atlas pattern): thin wrappers that hand a task to
// eng/common/build.{ps1,sh}, which fetch the pinned toolchain and start eng/build.ts. These tests pin
// the wiring - which wrapper starts which task, and that the bash ones can be executed after a checkout.
import { test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { repoRoot } from '../../eng/layout.ts';

const read = (file: string): string =>
  fs.readFileSync(path.join(repoRoot, file), 'utf8');

const cases = [
  ['Build.cmd', 'build.sh', '-restore -build', '--restore --build'],
  ['Restore.cmd', 'restore.sh', '-restore', '--restore'],
  ['Test.cmd', 'test.sh', '-test', '--test'],
] as const;

for (const [cmd, sh, psSwitch, shSwitch] of cases) {
  test(`${cmd} and ${sh} both start the task of ${psSwitch}`, () => {
    assert.match(
      read(cmd),
      new RegExp(`eng\\\\common\\\\build\\.ps1" ${psSwitch} %\\*`),
    );
    assert.match(
      read(cmd),
      /-ExecutionPolicy ByPass/,
      'runs under a restrictive policy too',
    );
    assert.match(read(cmd), /exit \/b %ErrorLevel%/, 'passes the exit code on');
    assert.match(
      read(sh),
      new RegExp(`eng/common/build\\.sh" ${shSwitch} "\\$@"`),
    );
  });
}

test('the full gate of CI is CIBuild.cmd / cibuild.sh: a restore first, then every task, with --ci', () => {
  assert.match(
    read('eng/common/CIBuild.cmd'),
    /build\.ps1" -restore -task All -ci %\*/,
  );
  assert.match(
    read('eng/common/cibuild.sh'),
    /build\.sh" --restore --task All --ci "\$@"/,
  );
});

test('the Windows entry runs under Windows PowerShell 5.1: no pwsh-only syntax in the bootstrap', () => {
  for (const file of ['eng/common/build.ps1', 'eng/common/tools.ps1']) {
    const code = read(file)
      .split(/\r?\n/)
      .filter((l) => !l.trim().startsWith('#'))
      .join('\n');
    assert.doesNotMatch(
      code,
      /\?\?|\?\.|&&|\|\||\$IsWindows|\$IsLinux/,
      `${file} uses a pwsh 7 feature`,
    );
    assert.doesNotMatch(
      code,
      /-AsHashtable|Get-FileHash|ConvertFrom-Json -Depth/,
      `${file}: not in 5.1`,
    );
  }
});

test('the bash scripts are executable in the repository', () => {
  const listed = spawnSync('git', ['ls-files', '-s', '--', '*.sh'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  assert.strictEqual(listed.status, 0, `${listed.stderr}${listed.error ?? ''}`);
  const modes = new Map(
    listed.stdout
      .trim()
      .split('\n')
      .map((l) => [l.split('\t')[1], l.split(' ')[0]] as const),
  );
  for (const sh of [
    'build.sh',
    'restore.sh',
    'test.sh',
    'eng/common/build.sh',
    'eng/common/cibuild.sh',
  ]) {
    assert.strictEqual(
      modes.get(sh),
      '100755',
      `${sh} is not executable in the index`,
    );
  }
});

test('the bootstrap folder .tools is neither tracked, formatted nor packaged', () => {
  assert.match(read('.gitignore'), /^\.tools\/$/m);
  assert.match(read('.prettierignore'), /^\.tools\/$/m);
  assert.match(read('.vscodeignore'), /^\.tools\/\*\*$/m);
});
