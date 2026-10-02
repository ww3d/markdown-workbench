// The config message: persisted document URI and the content width.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { MM, tocCfg } from '../../helpers/webview-fixtures.ts';

test('the webview persists the document URI from config for restore-after-restart', async () => {
  const r = await startWebview();
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    toc: tocCfg(),
    breadcrumb: { enabled: true },
    stickyScroll: { enabled: true },
    documentUri: 'file:///ws/doc.md',
  });
  assert.strictEqual(
    r.state.savedState?.documentUri,
    'file:///ws/doc.md',
    'setState persisted the document URI (read back by the panel serializer)',
  );
});

test('config sets the width variable', async () => {
  const { state, send } = await startWebview();
  send({ type: 'config', maxWidth: '72ch', minimap: MM() });
  assert.strictEqual(state.cssVars?.['--mc-max-width'], '72ch');
});
