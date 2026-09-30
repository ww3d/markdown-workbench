// The TOC tree: nesting, the initial state, the highlight delta, the reveal of the
// active entry, and the twistie/sublist stylesheet contract (#32, #44, #48).
import { test } from 'node:test';
import assert from 'node:assert';
import { nth } from '../../helpers/nth.ts';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import type { MockEl, Webview } from '../../helpers/webview-dom.ts';
import {
  byId,
  headingEl,
  MM,
  scroll,
  tocCfg,
  topConfig,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

// The mock element the TOC created for heading `idx` (its entry link).
function tocLinkMock(r: Webview, idx: number): MockEl {
  const link = r.state.created.find(
    (el) => el.className === 'toc-link' && el.dataset.idx === String(idx),
  );
  if (!link) throw new Error(`no TOC entry for heading ${idx}`);
  return link;
}

test('tocTree: nests by level and honors jumps', async () => {
  const r = await startWebview();
  const { tocTree } = await r.load('toc/tree.ts');
  const tree = tocTree([1, 2, 2]);
  assert.strictEqual(tree.length, 1);
  assert.strictEqual(nth(tree, 0).idx, 0);
  assert.deepStrictEqual(
    nth(tree, 0).children.map((n) => n.idx),
    [1, 2],
  );
  // h1 -> h4 jump: the h4 still nests under the h1.
  const jump = tocTree([1, 4]);
  assert.deepStrictEqual(
    nth(jump, 0).children.map((n) => n.idx),
    [1],
  );
  // Two top-level roots when the first level is deeper than the second.
  assert.strictEqual(tocTree([2, 1]).length, 2);
  assert.deepStrictEqual(tocTree([]), []); // document without headings
});

test('the initial TOC state is applied deterministically above the first heading', async () => {
  // active = -1 (reader above the first heading): the freshly rendered TOC must
  // collapse subsections up front, matching the state a scroll-back-to-top
  // produces (update() emits only on change, so the rebuild forces it).
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  const { tocBranches } = await r.load('toc/tree.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    toc: tocCfg({ mode: 'rail' }),
  });
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    true,
    'the h1 subsection is collapsed initially (active = -1)',
  );
});

test('the active TOC entry is scrolled into view only when it is outside the panel', async () => {
  // Performance (#44 review 4): the reveal must not force a reflow per active
  // change - it is coalesced into a rAF and skips the scroll when the entry is
  // already visible.
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  const { tocLinks } = await r.load('toc/tree.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h1', 'b', 'B', 1000),
  ]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  byId(r, 'toc').getBoundingClientRect = () => ({ top: 0, bottom: 400 });
  const linkB = tocLinkMock(r, 1);
  assert.ok(Object.is(linkB, tocLinks[1]), 'the entry of heading b');
  let scrolled = 0;
  linkB.scrollIntoView = () => {
    scrolled++;
  };
  linkB.getBoundingClientRect = () => ({ top: 100, bottom: 130 }); // inside [0,400]
  r.window.scrollY = 1500;
  scroll(r); // active = b, in view
  assert.strictEqual(scrolled, 0, 'an in-view active entry is not scrolled');
  linkB.getBoundingClientRect = () => ({ top: 500, bottom: 530 }); // below the panel bottom
  r.window.scrollY = 0;
  scroll(r); // active -1
  r.window.scrollY = 1500;
  scroll(r); // active = b again, out of view
  assert.strictEqual(
    scrolled,
    1,
    'an out-of-view active entry is scrolled into view',
  );
});

test('the TOC twistie is the native codicon chevron, centered in a gutter, rotated when expanded (#44)', () => {
  // The vendored codicon font renders at its native 16px metrics; chevron-right
  // is the \eab6 glyph; the gutter is a fixed 16px flex box that centers it
  // against the text; collapsed points right (0deg), expanded points down (90deg).
  const css = sheet('page/codicon.css', 'toc/tree.css');
  assert.match(
    css.text,
    /@font-face\s*\{[^}]*font-family:\s*"codicon"[^}]*codicon\.ttf[^}]*\}/,
    'the codicon font is declared and loaded from the vendored ttf',
  );
  assert.match(
    css.ruleBody('.codicon[class*="codicon-"]'),
    /16px\s*\/\s*1 codicon/,
    'native codicon metrics',
  );
  assert.match(
    css.ruleBody('.codicon-chevron-right::before'),
    /content:\s*"\\eab6"/,
    'the chevron-right glyph',
  );
  assert.match(
    css.ruleBody('.toc-gutter'),
    /flex:\s*0 0 16px/,
    'the gutter is a fixed 16px slot',
  );
  assert.match(
    css.ruleBody('.toc-gutter'),
    /align-items:\s*center/,
    'centers the chevron vertically',
  );
  assert.match(
    css.ruleBody('.toc-gutter'),
    /justify-content:\s*center/,
    'centers the chevron horizontally',
  );
  assert.match(
    css.ruleBody('.toc-link'),
    /align-items:\s*center/,
    'the row centers the gutter against the label',
  );
  assert.match(
    css.ruleBody('.toc-twistie'),
    /rotate\(0deg\)/,
    'collapsed: points right',
  );
  assert.match(
    css.ruleBody(
      '.toc-item:has(> .toc-sublist-wrap > .toc-sublist:not(.toc-collapsed)) > .toc-link .toc-twistie',
    ),
    /rotate\(90deg\)/,
    'expanded: points down',
  );
});

test('the TOC sublist expand/collapse is animated only on a manual toggle (#44 P5)', () => {
  // grid-template-rows 0fr<->1fr animates to the content height with no magic
  // number; the transition is armed only while body.toc-animating is set (a
  // manual toggle), so the scroll-driven auto expand/collapse stays instant.
  const css = sheet('toc/tree.css');
  assert.match(
    css.ruleBody('.toc-sublist-wrap'),
    /grid-template-rows:\s*1fr/,
    'expanded track',
  );
  assert.match(
    css.ruleBody('.toc-sublist-wrap:has(> .toc-sublist.toc-collapsed)'),
    /grid-template-rows:\s*0fr/,
    'collapsed track',
  );
  assert.match(
    css.ruleBody('body.toc-animating .toc-sublist-wrap'),
    /transition:\s*grid-template-rows/,
    'the transition is gated to a manual toggle',
  );
  assert.match(
    css.text,
    /prefers-reduced-motion:\s*reduce[\s\S]*?body\.toc-animating\s*\.toc-sublist-wrap\s*\{\s*transition:\s*none/,
    'reduced-motion disables the animation',
  );
  // The sublist clips during the collapse so the rows do not spill.
  assert.match(
    css.text,
    /\.toc-sublist\s*\{[^}]*overflow:\s*hidden/,
    'the sublist clips while collapsing',
  );
});

test('the TOC highlight delta marks the active path and re-collapses on the way out', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  const { tocLinks, tocBranches } = await r.load('toc/tree.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h2', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000),
  ]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 1500;
  scroll(r); // active = b (h2 under a)
  assert.strictEqual(
    tocLinks[1]?.classList.contains('toc-active'),
    true,
    'b active',
  );
  assert.strictEqual(
    tocLinks[0]?.classList.contains('toc-in-path'),
    true,
    'a on the path',
  );
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
    'a expanded',
  );
  r.window.scrollY = 2500;
  scroll(r); // active = c (sibling h1)
  assert.strictEqual(
    tocLinks[2]?.classList.contains('toc-active'),
    true,
    'c active',
  );
  assert.strictEqual(
    tocLinks[1]?.classList.contains('toc-active'),
    false,
    'b no longer active',
  );
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    true,
    'a re-collapsed',
  );
});

test('a parent TOC entry carries a real twistie node, a leaf none', async () => {
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
  const twisties = r.state.created.filter(
    (el) => el.className === 'codicon codicon-chevron-right toc-twistie',
  );
  assert.strictEqual(twisties.length, 1, 'one parent, one twistie');
  assert.strictEqual(nth(twisties, 0).tagName, 'I');
  assert.strictEqual(nth(twisties, 0)._attrs?.['aria-hidden'], 'true');
});

test('the TOC highlight touches only the links whose state changed', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h1', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000),
  ]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 1500;
  scroll(r); // active b
  const linkC = tocLinkMock(r, 2);
  let touched = 0;
  const toggle = linkC.classList.toggle;
  linkC.classList.toggle = (c, v) => {
    touched++;
    toggle(c, v);
  };
  r.window.scrollY = 500;
  scroll(r); // active a: a and b change, c does not
  assert.strictEqual(touched, 0, 'c was not rewritten');
});
