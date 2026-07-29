// Extension-side configuration resolution and the config message flow.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh } = require('./helpers/vscode-mock');

test('configuredViewConfig maps narrow to 72ch and github to 980px', () => {
  const vscode = install();
  const { _internal } = loadFresh('src/views.js');
  vscode._config['preview.maxWidth'] = 'narrow';
  assert.strictEqual(_internal.configuredViewConfig().maxWidth, '72ch');
  vscode._config['preview.maxWidth'] = 'github';
  assert.strictEqual(_internal.configuredViewConfig().maxWidth, '980px');
});

test('configuredViewConfig falls back to defaults when get() yields undefined (regression 0.21.1)', () => {
  install(); // empty config: every get(key, dflt) returns dflt
  const { _internal } = loadFresh('src/views.js');
  const cfg = _internal.configuredViewConfig();
  assert.deepStrictEqual(cfg.minimap, {
    enabled: true, size: 'proportional', showSlider: 'mouseover', side: 'right'
  });
  assert.strictEqual(cfg.maxWidth, '980px');
});

test('configuredViewConfig defaults the preview readability flags to the #25 behavior', () => {
  install(); // empty config: every get(key, dflt) returns dflt
  const { _internal } = loadFresh('src/views.js');
  const cfg = _internal.configuredViewConfig();
  assert.strictEqual(cfg.textSelection, true);
  assert.strictEqual(cfg.taskBatchSelect, 'checkbox');
  assert.strictEqual(cfg.taskRowTextCursor, false);
});

test('configuredViewConfig passes the configured preview readability flags through', () => {
  const vscode = install();
  const { _internal } = loadFresh('src/views.js');
  vscode._config['preview.textSelection'] = false;
  vscode._config['preview.taskBatchSelect'] = 'row';
  vscode._config['preview.taskRowTextCursor'] = true;
  const cfg = _internal.configuredViewConfig();
  assert.strictEqual(cfg.textSelection, false);
  assert.strictEqual(cfg.taskBatchSelect, 'row');
  assert.strictEqual(cfg.taskRowTextCursor, true);
});

test('configuredViewConfig defaults the toc flags (enabled + auto mode)', () => {
  install(); // empty config: every get(key, dflt) returns dflt
  const { _internal } = loadFresh('src/views.js');
  const cfg = _internal.configuredViewConfig();
  assert.deepStrictEqual(cfg.toc, { enabled: true, mode: 'auto' });
});

test('configuredViewConfig passes the configured toc flags through', () => {
  const vscode = install();
  const { _internal } = loadFresh('src/views.js');
  vscode._config['toc.enabled'] = false;
  vscode._config['toc.mode'] = 'fab';
  const cfg = _internal.configuredViewConfig();
  assert.deepStrictEqual(cfg.toc, { enabled: false, mode: 'fab' });
});

test('configuredViewConfig defaults the top-bar flags (breadcrumb + sticky enabled)', () => {
  install(); // empty config: every get(key, dflt) returns dflt
  const { _internal } = loadFresh('src/views.js');
  const cfg = _internal.configuredViewConfig();
  assert.deepStrictEqual(cfg.breadcrumb, { enabled: true });
  assert.deepStrictEqual(cfg.stickyScroll, { enabled: true });
});

test('configuredViewConfig passes the configured top-bar flags through independently', () => {
  const vscode = install();
  const { _internal } = loadFresh('src/views.js');
  vscode._config['breadcrumb.enabled'] = false;
  vscode._config['stickyScroll.enabled'] = true;
  const cfg = _internal.configuredViewConfig();
  assert.deepStrictEqual(cfg.breadcrumb, { enabled: false });
  assert.deepStrictEqual(cfg.stickyScroll, { enabled: true });
});

test('shikiTheme follows the active color theme kind', () => {
  const vscode = install();
  const { _internal } = loadFresh('src/render.js');
  vscode.window.activeColorTheme = { kind: 2 }; // dark
  assert.match(_internal.shikiTheme(), /dark/);
  vscode.window.activeColorTheme = { kind: 1 }; // light
  assert.match(_internal.shikiTheme(), /light/);
});
