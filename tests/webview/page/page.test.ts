// Page-level stylesheet contract (#15): the body is selectable.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';

const css = sheet('page/page.css');

test('body is selectable (user-select: text)', () => {
  assert.match(css.ruleBody('body'), /user-select:\s*text/);
});
