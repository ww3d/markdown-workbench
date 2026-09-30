// Pure parts of the guard mutation run (tests/integration/guard-mutation.js):
// the mutation hits the immediate save exactly once, and a run counts as
// caught only when its guard cases failed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { mutate, caught, run, SAVE_CALL } = require('./guard-mutation.js');

const session = fs.readFileSync(
  path.join(__dirname, '..', '..', 'src', 'clipboard-diff', 'session.js'),
  'utf8',
);

test('the mutation removes the one immediate save from session.js', () => {
  const mutated = mutate(session);
  assert.equal(mutated.includes(SAVE_CALL), false);
  assert.equal(mutated.length > 0, true);
});

test('the mutation refuses a source without the save call or with two', () => {
  assert.throws(() => mutate('nothing here'), /found 0/);
  assert.throws(() => mutate(`${SAVE_CALL}\n${SAVE_CALL}`), /found 2/);
});

test('caught: a failed run whose guard cases failed on a hit', () => {
  const out = [
    '== VS Code 1.100.0 - phase main',
    'FAIL guard: no dirty page',
    '     AssertionError [ERR_ASSERTION]: guard hit: dirty',
    '== VS Code 1.100.0 - phase window guard (main)',
    'FAIL guard in a normal window, main',
    '     [["backups",["/u/Backups/x"]]]',
  ].join('\n');
  assert.equal(caught(1, out), true);
});

test('not caught: a guard case red for another reason than a hit', () => {
  const timeout = [
    'FAIL guard: no dirty page',
    '     Error: timed out waiting for the diff',
    'FAIL guard in a normal window, main',
    '     ["the driver wrote no result"]',
  ].join('\n');
  assert.equal(caught(1, timeout), false);
  const hitBelongsToNext = [
    'FAIL guard: no dirty page',
    'FAIL guard after reload',
    '     guard hit: file',
  ].join('\n');
  assert.equal(caught(1, hitBelongsToNext), false);
});

test('not caught: a guard case passed, the run passed, or no guard case ran', () => {
  const passed =
    'FAIL guard: x\n  guard hit: dirty\nok   guard in a normal window, main\n';
  assert.equal(caught(1, passed), false);
  assert.equal(caught(0, 'FAIL guard: x\n  guard hit: dirty\n'), false);
  assert.equal(caught(1, 'FAIL tab title shows the roles\n'), false);
});

test('run starts node without a shell, so a node path with a space stays whole', () => {
  const calls = [];
  const spawn = (cmd, args, options) => {
    calls.push({ cmd, args, options });
    return { status: 0, stdout: '', stderr: '' };
  };
  const exe = 'C:\\Program Files\\nodejs\\node.exe';
  assert.equal(run(exe, ['run.js'], '.', {}, spawn).status, 0);
  assert.equal(calls[0].cmd, exe);
  assert.ok(!calls[0].options.shell, 'no shell');
});
