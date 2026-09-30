// The bars' segments and rows: the root label, the button-like nav controls and
// their stylesheet contract (#33, #44).
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { nth } from '../../helpers/nth.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import type { MockEl } from '../../helpers/webview-dom.ts';
import {
  byId,
  headingEl,
  scroll,
  tocCfg,
  topConfig,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

test('rootLabel: the leading H1 is the root label, else a neutral fallback', async () => {
  const r = await startWebview();
  const { rootLabel } = await r.load('top-bars/links.ts');
  assert.strictEqual(rootLabel([{ level: 1, text: 'My Title' }]), 'My Title');
  assert.strictEqual(rootLabel([{ level: 2, text: 'Sub' }]), 'Document'); // no leading H1
  assert.strictEqual(rootLabel([{ level: 1, text: '' }]), 'Document'); // empty H1
  assert.strictEqual(rootLabel([]), 'Document'); // no headings
});

test('the nav controls render as buttons (role=button + data-id, no href) so smooth scroll is not overridden (#44)', async () => {
  // The VS Code webview runs a native, instant #id jump on any real anchor click
  // (preventDefault does not stop it), which would win the final scroll position
  // and defeat the smooth navigateToHash. Rendering the controls as buttons with
  // the target in data-id (not an href) removes that native jump, so the smooth
  // scroll is the only motion. (In-file markdown [..](#id) links stay real anchors
  // and remain instant by design.)
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  scroll(r); // active chain [a, b] -> bars built
  const check = (el: MockEl, where: string) => {
    assert.strictEqual(
      el._attrs?.role,
      'button',
      `${where} is a button, not a link`,
    );
    assert.ok(el.dataset.id, `${where} carries its target id in data-id`);
    assert.strictEqual(
      el.href,
      undefined,
      `${where} has no href (no native #id jump to override the smooth scroll)`,
    );
  };
  check(nth(byId(r, 'breadcrumb')._links ?? [], 0), 'a breadcrumb segment');
  check(nth(byId(r, 'sticky-scroll')._links ?? [], 0), 'a sticky row');
  const tocEntry = r.state.created.find(
    (el) => el.className === 'toc-link' && el.dataset.idx === '0',
  );
  const { tocLinks } = await r.load('toc/tree.ts');
  assert.ok(
    tocEntry && Object.is(tocEntry, tocLinks[0]),
    'the first TOC entry',
  );
  check(tocEntry, 'a TOC entry');
});

test('every hrefless nav control declares cursor:pointer (buttons no longer inherit the anchor hand) (#44)', () => {
  // Dropping the href turned the controls into generic elements, which show the
  // text I-beam by default - each must declare the pointer cursor explicitly.
  const css = sheet('toc/tree.css', 'top-bars/top-bars.css');
  for (const sel of [
    '.toc-link',
    '.breadcrumb-seg',
    '.sticky-row',
    '.breadcrumb-option',
  ]) {
    assert.match(
      css.ruleBody(sel),
      /cursor:\s*pointer/,
      `${sel} shows the hand cursor`,
    );
  }
});

test('every breadcrumb segment is the same fixed-height box (#44 review 8)', () => {
  // The bar is a fixed height and each segment fills it as a flex box, so a
  // highlighted or long-label segment cannot render a different box height than a
  // plain one. (The rendered pixel height is a manual VS Code check; the fixed
  // geometry is the headless contract.)
  const css = sheet('top-bars/top-bars.css');
  assert.match(
    css.ruleBody('#breadcrumb'),
    /height:\s*28px/,
    'the bar is a fixed height',
  );
  assert.doesNotMatch(
    css.ruleBody('#breadcrumb'),
    /min-height/,
    'not a content-dependent min-height',
  );
  assert.match(
    css.ruleBody('.breadcrumb-seg'),
    /display:\s*inline-flex/,
    'segment is a flex box',
  );
  assert.match(css.ruleBody('.breadcrumb-seg'), /align-items:\s*center/);
  assert.match(
    css.ruleBody('.breadcrumb-seg'),
    /height:\s*100%/,
    'every segment fills the bar height',
  );
});

test('the breadcrumb highlight is a label pill, so the separator sits outside it (#44 review 8)', () => {
  // The hover background is on the inner .breadcrumb-label (the text), never on
  // the segment box; the separator is a ::before on the segment, outside that
  // label - so no highlight is ever drawn under it.
  const css = sheet('top-bars/top-bars.css');
  assert.match(
    css.ruleBody('.breadcrumb-seg:hover .breadcrumb-label'),
    /background:\s*var\(--vscode-list-hoverBackground\)/,
    'highlight is on the label pill',
  );
  assert.doesNotMatch(
    css.ruleBody('.breadcrumb-seg:hover'),
    /background/,
    'the segment box itself carries no highlight background',
  );
  assert.doesNotMatch(
    css.ruleBody('.breadcrumb-seg'),
    /background/,
    'nor does the base segment, so the separator never sits on a highlight',
  );
  assert.match(
    css.text,
    /\.breadcrumb-seg:not\(:first-child\)::before\s*\{[^}]*content:\s*"\\eab6"/,
    'the separator is the native codicon chevron ::before, outside the label',
  );
  assert.match(
    css.text,
    /\.breadcrumb-seg:not\(:first-child\)::before\s*\{[^}]*codicon/,
    'the separator uses the codicon font, not a thin angle-quote',
  );
});
