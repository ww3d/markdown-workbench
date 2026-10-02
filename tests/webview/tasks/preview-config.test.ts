// Preview readability settings (#25 follow-up): three opt-in/opt-out knobs,
// defaults reproduce #25 exactly.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import { sendCfg } from '../../helpers/webview-fixtures.ts';

test('config toggles mw-no-text-select only when textSelection is false', async () => {
  const r = await startWebview();
  sendCfg(r, { textSelection: true });
  assert.strictEqual(!!r.state.bodyClasses['mw-no-text-select'], false);
  sendCfg(r, { textSelection: false });
  assert.strictEqual(!!r.state.bodyClasses['mw-no-text-select'], true);
});

test('config sets mw-task-text-cursor only with textSelection on AND the cursor flag', async () => {
  const r = await startWebview();
  sendCfg(r, { textSelection: true, taskRowTextCursor: true });
  assert.strictEqual(!!r.state.bodyClasses['mw-task-text-cursor'], true);
  // cursor flag off -> absent
  sendCfg(r, { textSelection: true, taskRowTextCursor: false });
  assert.strictEqual(!!r.state.bodyClasses['mw-task-text-cursor'], false);
  // textSelection off wins even with the cursor flag on
  sendCfg(r, { textSelection: false, taskRowTextCursor: true });
  assert.strictEqual(!!r.state.bodyClasses['mw-task-text-cursor'], false);
});

test('mw-no-text-select locks selection; the text-cursor rules apply to the row', () => {
  const css = sheet('page/page.css', 'tasks/tasks.css');
  assert.match(css.ruleBody('body.mw-no-text-select'), /user-select:\s*none/);
  assert.match(
    css.ruleBody('body.mw-task-text-cursor .task-row'),
    /cursor:\s*text/,
  );
  assert.match(
    css.ruleBody('body.mw-task-text-cursor .task-row input[type=checkbox]'),
    /cursor:\s*pointer/,
  );
});
