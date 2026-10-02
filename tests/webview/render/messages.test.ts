// The host's messages to the webview, dispatched by type (src/webview/render/messages.ts).
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { byId, fireClick, sortButton } from '../../helpers/webview-fixtures.ts';

test('a version message sets the version sortTable carries, without rendering (REQ-071)', async () => {
  const r = await startWebview();
  r.send({ type: 'version', version: 9 });
  assert.strictEqual(byId(r, 'content').innerHTML, '', 'no render');
  fireClick(r, sortButton(4, 1));
  assert.deepStrictEqual(r.state.posted.at(-1), {
    type: 'sortTable',
    line: 4,
    col: 1,
    dir: 'asc',
    version: 9,
  });
});
