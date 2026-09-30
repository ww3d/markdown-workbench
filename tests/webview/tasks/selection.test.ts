// Task toggle gating (#15): text stays selectable, the toggle is decided at click
// time instead of by a global user-select lock; the checkbox inputs opt out of
// text selection.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';

test('both checkbox inputs keep user-select: none', () => {
  const css = sheet('tasks/tasks.css', 'tables/tables.css');
  assert.match(
    css.ruleBody('.task-row input[type=checkbox]'),
    /user-select:\s*none/,
  );
  assert.match(css.ruleBody('input.cell-task'), /user-select:\s*none/);
});

test('canToggleFromBareClick: empty selection + single click toggles', async () => {
  const r = await startWebview();
  const { canToggleFromBareClick } = await r.load('tasks/selection.ts');
  assert.strictEqual(canToggleFromBareClick('', 1), true);
});

test('canToggleFromBareClick: a non-empty selection blocks the toggle', async () => {
  const r = await startWebview();
  const { canToggleFromBareClick } = await r.load('tasks/selection.ts');
  assert.strictEqual(canToggleFromBareClick('some text', 1), false);
});

test('canToggleFromBareClick: a multi-click (detail > 1) blocks the toggle', async () => {
  const r = await startWebview();
  const { canToggleFromBareClick } = await r.load('tasks/selection.ts');
  assert.strictEqual(canToggleFromBareClick('', 2), false);
});

test('bareClickToggles: selection off always toggles; on it delegates to the gate', async () => {
  const r = await startWebview();
  const { bareClickToggles } = await r.load('tasks/selection.ts');
  // textSelection off: no text interaction to protect -> always toggles.
  assert.strictEqual(bareClickToggles(false, 'some text', 2), true);
  // textSelection on: defers to canToggleFromBareClick.
  assert.strictEqual(bareClickToggles(true, '', 1), true);
  assert.strictEqual(bareClickToggles(true, 'sel', 1), false);
  assert.strictEqual(bareClickToggles(true, '', 2), false);
});
