// Extension-side configuration resolution and the config message flow.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh } = require('./helpers/vscode-mock');

test('configuredViewConfig maps narrow to 72ch and github to 980px', () => {
  const vscode = install();
  const { _internal } = loadFresh('extension.js');
  vscode._config['preview.maxWidth'] = 'narrow';
  assert.strictEqual(_internal.configuredViewConfig().maxWidth, '72ch');
  vscode._config['preview.maxWidth'] = 'github';
  assert.strictEqual(_internal.configuredViewConfig().maxWidth, '980px');
});

test('configuredViewConfig falls back to defaults when get() yields undefined (regression 0.21.1)', () => {
  install(); // empty config: every get(key, dflt) returns dflt
  const { _internal } = loadFresh('extension.js');
  const cfg = _internal.configuredViewConfig();
  assert.deepStrictEqual(cfg.minimap, {
    enabled: true, size: 'proportional', showSlider: 'mouseover', side: 'right'
  });
  assert.strictEqual(cfg.maxWidth, '980px');
});

test('shikiTheme follows the active color theme kind', () => {
  const vscode = install();
  const { _internal } = loadFresh('extension.js');
  vscode.window.activeColorTheme = { kind: 2 }; // dark
  assert.match(_internal.shikiTheme(), /dark/);
  vscode.window.activeColorTheme = { kind: 1 }; // light
  assert.match(_internal.shikiTheme(), /light/);
});
