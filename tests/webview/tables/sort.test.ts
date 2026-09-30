// Sort button in table headers (REQ-045, REQ-067 of docs/tasks/90-table-editing.md).
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { fireClick, MM, sortButton } from '../../helpers/webview-fixtures.ts';

test('a header sort button posts sortTable with line, column, direction and version', async () => {
  const r = await startWebview();
  r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
  r.send({ type: 'render', html: '<p>x</p>', version: 7 });
  fireClick(r, sortButton(4, 1));
  assert.deepStrictEqual(r.state.posted.at(-1), {
    type: 'sortTable',
    line: 4,
    col: 1,
    dir: 'asc',
    version: 7,
  });
  fireClick(r, sortButton(4, 1));
  const second = r.state.posted.at(-1);
  assert.strictEqual(
    second?.type === 'sortTable' && second.dir,
    'desc',
    'second click sorts the other way',
  );
  fireClick(r, sortButton(4, 0));
  const third = r.state.posted.at(-1);
  assert.strictEqual(
    third?.type === 'sortTable' && third.dir,
    'asc',
    'another column starts ascending',
  );
});

test('the version travels even when the render HTML is unchanged', async () => {
  const r = await startWebview();
  r.send({ type: 'render', html: '<p>x</p>', version: 1 });
  r.send({ type: 'render', html: '<p>x</p>', version: 2 });
  fireClick(r, sortButton(0, 0));
  const msg = r.state.posted.at(-1);
  assert.strictEqual(msg?.type === 'sortTable' && msg.version, 2);
});

test('tables.previewSort reaches the preview through the config message', async () => {
  const r = await startWebview();
  r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
  assert.strictEqual(
    r.state.bodyClasses['mw-preview-sort'],
    true,
    'default on',
  );
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    tables: { previewSort: false },
  });
  assert.strictEqual(r.state.bodyClasses['mw-preview-sort'], false);
  const before = r.state.posted.length;
  fireClick(r, sortButton(0, 0));
  assert.strictEqual(r.state.posted.length, before, 'no sort while off');
});
