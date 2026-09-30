// Page-level stylesheet contract (#15): the body is selectable.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';

const css = sheet('page/page.css');

test('body is selectable (user-select: text)', () => {
  assert.match(css.ruleBody('body'), /user-select:\s*text/);
});

test('the custom scrollbar is in effect: scrollbar-color auto, no arrow buttons', () => {
  // VS Code injects a non-auto scrollbar-color into every webview, which disables
  // all ::-webkit-scrollbar styling; without the reset the arrow buttons return and
  // offset the thumb track against the full-height minimap rail.
  assert.match(css.text, /html\s*\{[^}]*scrollbar-color:\s*auto/);
  assert.match(css.ruleBody('::-webkit-scrollbar-button'), /display:\s*none/);
});
