// The content's delegated click handler on tasks and cells, the batch gestures and
// Escape. Click-path helpers build minimal targets whose closest()/querySelectorAll()
// answer the exact selectors the handler probes, then fire the content click
// listener captured by the DOM mock.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  cellBodyTarget,
  cellCheckboxTarget,
  fireClick,
  keydown,
  labelTarget,
  listCheckboxTarget,
  sendCfg,
} from '../../helpers/webview-fixtures.ts';
import type { WebviewToHost } from '../../../src/webview/protocol.ts';

// The last message the webview posted; none fails the test by name.
function lastPosted(posted: readonly WebviewToHost[]): WebviewToHost {
  const msg = posted.at(-1);
  if (!msg) throw new Error('the webview posted nothing');
  return msg;
}

test('clicking a list checkbox toggles regardless of an active selection', async () => {
  const r = await startWebview();
  r.window.__selection = 'dragged out some text'; // would block a bare click
  fireClick(r, listCheckboxTarget(3, false));
  const msg = lastPosted(r.state.posted);
  assert.strictEqual(msg.type, 'toggle');
  assert.ok(msg.type === 'toggle');
  assert.deepStrictEqual(msg.lines, [3]);
  assert.strictEqual(msg.checked, true);
});

test('clicking a table checkbox toggles via toggleCell, ungated', async () => {
  const r = await startWebview();
  r.window.__selection = 'text';
  fireClick(r, cellCheckboxTarget(4, 1, false));
  const msg = lastPosted(r.state.posted);
  assert.strictEqual(msg.type, 'toggleCell');
  assert.ok(msg.type === 'toggleCell');
  assert.strictEqual(msg.line, 4);
  assert.strictEqual(msg.idx, 1);
  assert.strictEqual(msg.checked, true);
});

test('a bare label click toggles only without an active selection', async () => {
  const r = await startWebview();
  fireClick(r, labelTarget(2, false));
  assert.strictEqual(lastPosted(r.state.posted).type, 'toggle');
  const before = r.state.posted.length;
  r.window.__selection = 'highlighted';
  fireClick(r, labelTarget(2, false));
  assert.strictEqual(
    r.state.posted.length,
    before,
    'selection present: no toggle',
  );
});

test('a double click on the label selects a word instead of toggling', async () => {
  const r = await startWebview();
  const before = r.state.posted.length;
  fireClick(r, labelTarget(2, false), { detail: 2 });
  assert.strictEqual(r.state.posted.length, before);
});

test('a bare click in a single-checkbox cell is gated like the label', async () => {
  const r = await startWebview();
  fireClick(r, cellBodyTarget(cellCheckboxTarget(4, 0, false)));
  assert.strictEqual(lastPosted(r.state.posted).type, 'toggleCell');
  const before = r.state.posted.length;
  r.window.__selection = 'sel';
  fireClick(r, cellBodyTarget(cellCheckboxTarget(4, 0, false)));
  assert.strictEqual(
    r.state.posted.length,
    before,
    'selection present: no cell toggle',
  );
  r.window.__selection = '';
  fireClick(r, cellBodyTarget(cellCheckboxTarget(4, 0, false)), { detail: 2 });
  assert.strictEqual(
    r.state.posted.length,
    before,
    'double click: no cell toggle',
  );
});

test('batch select (Ctrl/Shift) fires from the checkbox, never from the label', async () => {
  const r = await startWebview();
  const { selection } = await r.load('tasks/selection.ts');
  // Ctrl on the label does NOT add to the batch selection (stays a plain toggle).
  fireClick(r, labelTarget(5, false), { ctrlKey: true });
  assert.strictEqual(selection.size, 0, 'label Ctrl+click is not batch');
  assert.strictEqual(lastPosted(r.state.posted).type, 'toggle');
  // Ctrl on the checkbox is membership batch: it adds and posts nothing.
  const before = r.state.posted.length;
  fireClick(r, listCheckboxTarget(5, false), { ctrlKey: true });
  assert.ok(selection.has(5), 'checkbox Ctrl+click adds to the selection');
  assert.strictEqual(
    r.state.posted.length,
    before,
    'membership batch posts no toggle',
  );
});

test('Escape clears the batch selection (regression)', async () => {
  const r = await startWebview();
  const { selection } = await r.load('tasks/selection.ts');
  fireClick(r, listCheckboxTarget(7, false), { ctrlKey: true });
  assert.ok(selection.has(7));
  keydown(r, 'Escape');
  assert.strictEqual(selection.size, 0, 'Escape empties the selection');
});

test('taskBatchSelect "row": Ctrl/Shift on the label drives the batch', async () => {
  const r = await startWebview();
  const { selection } = await r.load('tasks/selection.ts');
  // The range branch reads the task list off the DOM; supply line-tagged lis.
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === 'li.task'
      ? [2, 3, 4, 5].map((n) => ({
          dataset: { line: String(n) },
          classList: { toggle() {} },
        }))
      : [];
  sendCfg(r, { taskBatchSelect: 'row' });
  // Ctrl on the label is membership batch: grows the selection, posts nothing.
  const before = r.state.posted.length;
  fireClick(r, labelTarget(2, false), { ctrlKey: true });
  assert.ok(
    selection.has(2),
    'Ctrl on label adds to the selection in row mode',
  );
  assert.strictEqual(
    r.state.posted.length,
    before,
    'membership batch posts no toggle',
  );
  // Shift after the anchor range-selects 2..5 inclusive.
  fireClick(r, labelTarget(5, false), { shiftKey: true });
  assert.ok(selection.has(5), 'Shift on label range-selects in row mode');
  assert.ok(selection.has(3), 'range fills in between');
});

test('taskBatchSelect "checkbox" (default): Ctrl on the label plain-toggles', async () => {
  const r = await startWebview();
  const { selection } = await r.load('tasks/selection.ts');
  sendCfg(r, { taskBatchSelect: 'checkbox' });
  fireClick(r, labelTarget(2, false), { ctrlKey: true });
  assert.strictEqual(
    selection.size,
    0,
    'label Ctrl+click is not batch in checkbox mode',
  );
  assert.strictEqual(lastPosted(r.state.posted).type, 'toggle');
});

test('textSelection false: the label toggles despite a selection or a double click', async () => {
  const r = await startWebview();
  sendCfg(r, { textSelection: false });
  r.window.__selection = 'highlighted text'; // would block a gated bare click
  fireClick(r, labelTarget(2, false));
  assert.strictEqual(
    lastPosted(r.state.posted).type,
    'toggle',
    'selection present still toggles',
  );
  const before = r.state.posted.length;
  fireClick(r, labelTarget(2, false), { detail: 2 });
  assert.strictEqual(
    r.state.posted.length,
    before + 1,
    'double click still toggles',
  );
  assert.strictEqual(lastPosted(r.state.posted).type, 'toggle');
});

test('a cell toggle reads the rendered checked attribute, not the flipped live state', async () => {
  // At click time the browser has already flipped the input's live .checked; the
  // rendered attribute is the state the source has, so the toggle is its opposite.
  const r = await startWebview();
  const box = cellCheckboxTarget(4, 0, true); // rendered checked
  box.checked = false; // the live state the click just flipped
  fireClick(r, box);
  const msg = lastPosted(r.state.posted);
  assert.ok(msg.type === 'toggleCell');
  assert.strictEqual(
    msg.checked,
    false,
    'unchecks what the source has checked',
  );
});
