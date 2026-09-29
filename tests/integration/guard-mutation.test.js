// Pure parts of the guard mutation run (tests/integration/guard-mutation.js):
// the mutation hits the immediate save exactly once, and a run counts as
// caught only when its guard cases failed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { mutate, caught, SAVE_CALL } = require('./guard-mutation.js');

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

test('caught: a failed run whose guard cases failed', () => {
  const out = '== VS Code 1.100.0 - phase main\nFAIL guard: no dirty page\n';
  assert.equal(caught(1, out), true);
});

test('not caught: a guard case passed, the run passed, or no guard case ran', () => {
  const passed =
    'FAIL guard: no dirty page\nok   guard in a normal window, main\n';
  assert.equal(caught(1, passed), false);
  assert.equal(caught(0, 'FAIL guard: no dirty page\n'), false);
  assert.equal(caught(1, 'FAIL tab title shows the roles\n'), false);
});
