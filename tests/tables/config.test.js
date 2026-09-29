// The tables.* settings: defaults, fallbacks for missing or invalid values
// (REQ-055 to REQ-069).

import { test, beforeEach } from 'node:test';
import assert from 'node:assert';
import pkg from '../../package.json' with { type: 'json' };
import { install, loadFresh } from '../helpers/vscode-mock.ts';

const vscode = install();
const { tablesConfig, DEFAULTS } = await loadFresh('src/tables/config.js');

beforeEach(() => {
  vscode._config = {};
});

test('every setting falls back to its default when unset', () => {
  const cfg = tablesConfig();
  for (const [key, value] of Object.entries(DEFAULTS))
    assert.strictEqual(cfg[key], value, key);
  assert.strictEqual(cfg.ambiguousWide, false);
});

test('undefined, wrong types and unknown enum values fall back to the default', () => {
  for (const key of Object.keys(DEFAULTS)) {
    for (const bad of [undefined, null, {}, 'nonsense-value', 12345.5]) {
      if (
        typeof bad === typeof DEFAULTS[key] &&
        key !== 'maxAlignedWidth' &&
        !['enterBehavior', 'ambiguousWidth'].includes(key)
      )
        continue; // a string setting accepts any string
      vscode._config = { [`tables.${key}`]: bad };
      assert.strictEqual(
        tablesConfig()[key],
        DEFAULTS[key],
        `${key} = ${JSON.stringify(bad)}`,
      );
    }
  }
  vscode._config = { 'tables.maxAlignedWidth': -1 };
  assert.strictEqual(tablesConfig().maxAlignedWidth, 100);
});

test('valid values are taken over', () => {
  vscode._config = {
    'tables.enterBehavior': 'nextRowSameColumn',
    'tables.ambiguousWidth': 'wide',
    'tables.maxAlignedWidth': 0,
    'tables.cellLineBreak': '',
  };
  const cfg = tablesConfig();
  assert.strictEqual(cfg.enterBehavior, 'nextRowSameColumn');
  assert.strictEqual(cfg.ambiguousWide, true);
  assert.strictEqual(cfg.maxWidth, 0);
  assert.strictEqual(cfg.cellLineBreak, '');
});

test('package.json declares every tables.* setting with the same default and a description', () => {
  const props = pkg.contributes.configuration.properties;
  for (const [key, value] of Object.entries(DEFAULTS)) {
    const p = props[`markdownWorkbench.tables.${key}`];
    assert.ok(p, key);
    assert.deepStrictEqual(p.default, value, key);
    assert.ok(
      p.description || p.markdownDescription,
      `${key} has a description`,
    );
  }
});

test('get-east-asian-width is pinned exactly to 1.7.0 (REQ-008)', () => {
  assert.strictEqual(pkg.dependencies['get-east-asian-width'], '1.7.0');
});
