// Click-focus suppression (docs/DECISIONS.md #40) and the pointer-focus outline rule.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import { globalListener } from '../../helpers/webview-fixtures.ts';

test('one central mousedown handler suppresses the click focus on every control (#44)', async () => {
  // A mouse click that focuses a control makes a VS Code webview scroll it into
  // view - a first-click page jump, and for a TOC twistie a spurious active-heading
  // drift (the toggle appeared to select the entry above). One delegated mousedown
  // preventDefault over every click target fixes both; keyboard focus is untouched.
  const r = await startWebview();
  const sel = (await r.load('page/focus.ts')).CLICK_FOCUS_TARGETS;
  // Content links and checkboxes (a, input) as well as the nav controls: any
  // focusable target, so no click focuses (and scrolls) anything.
  for (const target of [
    'a',
    'input',
    'button',
    '.breadcrumb-seg',
    '.breadcrumb-option',
    '.toc-link',
    '.sticky-row',
    '.mw-fold-toggle',
  ]) {
    assert.ok(
      sel.split(/\s*,\s*/).includes(target),
      `the delegated selector covers ${target}`,
    );
  }
  assert.ok(
    r.state.listeners.document.mousedown,
    'a document mousedown listener is registered',
  );
  const md = globalListener(r, 'document', 'mousedown');
  let prevented = false;
  md({
    target: { closest: (s: string) => (s === sel ? {} : null) },
    preventDefault: () => {
      prevented = true;
    },
  });
  assert.strictEqual(
    prevented,
    true,
    'a mousedown on a control is prevented (no focus, no scroll-into-view)',
  );
  let plain = false;
  md({
    target: { closest: () => null },
    preventDefault: () => {
      plain = true;
    },
  });
  assert.strictEqual(
    plain,
    false,
    'a mousedown on plain content is untouched (text selection stays normal)',
  );
});

test('pointer focus shows no outline anywhere; keyboard focus-visible keeps the ring (#44)', () => {
  // VS Code injects an --vscode-focusBorder outline on every focusable element; on
  // a click (content link, tabindex=-1 checkbox/cell, nav control) that is just
  // visual noise. One global rule drops it for pointer/programmatic focus and
  // keeps it for :focus-visible (keyboard), so a11y is unaffected.
  assert.match(
    sheet('page/page.css').ruleBody(':focus:not(:focus-visible)'),
    /outline:\s*none/,
  );
});
