// In-page navigation: internal anchor links ([Text](#slug)) resolve the target
// heading via a lookup scoped to #content and scroll to it; a missing target is a
// no-op (no toggle fallthrough). seedHeading seeds content.querySelector with the
// expected heading.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  anchorTarget,
  byId,
  fireClick,
  seedHeading,
} from '../../helpers/webview-fixtures.ts';

test('clicking an internal anchor link scrolls to the target heading', async () => {
  const r = await startWebview({ scrollY: 100 });
  seedHeading(r, '#sec-two', 250); // absTop = 250 + scrollY 100
  fireClick(r, anchorTarget('#sec-two'));
  assert.strictEqual(r.state.scrolledTo, 350, 'scrolls to the target position');
  assert.ok(!r.state.posted.some((m) => m.type === 'toggle'), 'no task toggle');
});

test('an encoded anchor href is decoded before the lookup', async () => {
  const r = await startWebview();
  seedHeading(r, '#grüße', 40); // ASCII source, unicode id
  fireClick(r, anchorTarget('#gr%C3%BC%C3%9Fe'));
  assert.strictEqual(r.state.scrolledTo, 40);
});

test('a malformed percent-escape in the href falls back to the literal hash', async () => {
  // A raw HTML anchor (html: true) can carry a malformed escape like "#100%";
  // decodeURIComponent would throw. The handler must degrade to the literal
  // hash and still resolve it, not die with an URIError.
  const r = await startWebview();
  const el = { getBoundingClientRect: () => ({ top: 60 }) };
  byId(r, 'content').querySelector = () => el; // literal-hash lookup resolves
  assert.doesNotThrow(() => fireClick(r, anchorTarget('#100%')));
  assert.strictEqual(r.state.scrolledTo, 60, 'resolves the literal hash');
});

test('a heading whose slug collides with a skeleton id is still navigable', async () => {
  // "# Content" slugs to "content", which also names the #content container.
  // A document-wide getElementById would hit the container; the scoped lookup
  // (content.querySelector) must find the heading descendant instead.
  const r = await startWebview();
  seedHeading(r, '#content', 500);
  fireClick(r, anchorTarget('#content'));
  assert.strictEqual(
    r.state.scrolledTo,
    500,
    'scoped to the heading, not the container',
  );
});

test('an empty hash (href="#") is a no-op without an exception', async () => {
  const r = await startWebview();
  // The empty-hash guard must short-circuit before querySelector: '#' alone is
  // an invalid selector and CSS.escape('') would build one.
  byId(r, 'content').querySelector = () => {
    throw new Error('querySelector must not run for an empty hash');
  };
  const before = r.state.posted.length;
  assert.doesNotThrow(() => fireClick(r, anchorTarget('#')));
  assert.strictEqual(r.state.scrolledTo, null, 'no scroll');
  assert.strictEqual(r.state.posted.length, before, 'no message posted');
});

test('an internal anchor with no matching target does nothing', async () => {
  const r = await startWebview();
  byId(r, 'content').querySelector = () => null;
  const before = r.state.posted.length;
  fireClick(r, anchorTarget('#missing'));
  assert.strictEqual(r.state.scrolledTo, null, 'no scroll');
  assert.strictEqual(r.state.posted.length, before, 'no message posted');
});

test('the anchor lookup CSS.escapes the hash (a raw dotted fragment is escaped)', async () => {
  // Records the exact selector: proves CSS.escape is load-bearing. Dropping it
  // would query '#foo.bar' (a compound selector) instead of the escaped '#foo\\.bar'.
  const r = await startWebview();
  let seen: string | null = null;
  byId(r, 'content').querySelector = (sel) => {
    seen = sel;
    return null;
  };
  fireClick(r, anchorTarget('#foo.bar'));
  assert.strictEqual(seen, '#foo\\.bar', 'the "." must be CSS.escape-d');
});

test('a non-hash link (external or cross-file) is left to the browser, no scroll/toggle', async () => {
  for (const href of ['https://example.com', './other.md#y']) {
    const r = await startWebview();
    // Would throw if the code queried it: proves the non-hash href never reaches the lookup.
    byId(r, 'content').querySelector = () => {
      throw new Error(`must not query for ${href}`);
    };
    const before = r.state.posted.length;
    assert.doesNotThrow(() => fireClick(r, anchorTarget(href)), href);
    assert.strictEqual(r.state.scrolledTo, null, href);
    assert.strictEqual(r.state.posted.length, before, href);
  }
});

test('internal anchors are converted to buttons (no href, id in data-id) so no native #id jump fires (#44)', async () => {
  const r = await startWebview();
  const { convertInternalAnchors } = await r.load('anchors/anchors.ts');
  const mk = (href: string) => {
    const attrs: Record<string, string | undefined> = { href };
    const added: string[] = [];
    const dataset: Record<string, string> = {};
    return {
      getAttribute: (n: string) => attrs[n],
      removeAttribute: (n: string) => {
        delete attrs[n];
      },
      setAttribute: (n: string, v: string) => {
        attrs[n] = v;
      },
      dataset,
      classList: {
        add(c: string) {
          added.push(c);
        },
        contains(c: string) {
          return added.includes(c);
        },
      },
      _attrs: attrs,
    };
  };
  const internal = mk('#sec'),
    bare = mk('#');
  // The browser scopes a[href^="#"] to internal + the bare '#'; external never reaches it.
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === 'a[href^="#"]' ? [internal, bare] : [];
  convertInternalAnchors();
  assert.strictEqual(internal.dataset.id, 'sec', 'id moved to data-id');
  assert.strictEqual(
    internal._attrs.href,
    undefined,
    'href removed so no native jump fights navigateToHash',
  );
  assert.strictEqual(internal._attrs.role, 'button');
  assert.ok(internal.classList.contains('mw-anchor'));
  assert.strictEqual(
    bare._attrs.href,
    '#',
    'a bare "#" is left a plain anchor',
  );
  assert.ok(!bare.classList.contains('mw-anchor'));
});

test('navigation lands a heading at its own per-heading bars margin, not the transient global offset (#44)', async () => {
  // Each heading carries its own published scroll-margin-top (its bars height incl.
  // its sticky depth). Using it - not the global topBarsOffset of the current
  // position - is what makes the first jump from the top land correctly instead of
  // shifting a few px once the sticky stack appears.
  const r = await startWebview({ scrollY: 0 });
  const { navigateToHash } = await r.load('anchors/anchors.ts');
  const heading = {
    style: { scrollMarginTop: '72px' },
    getBoundingClientRect: () => ({ top: 4000 }),
  };
  byId(r, 'content').querySelector = (s) => (s === '#deep' ? heading : null);
  navigateToHash('deep', true);
  assert.strictEqual(
    r.state.scrolledTo,
    4000 - 72,
    'landed at absTop minus the heading own margin',
  );
  assert.strictEqual(r.state.scrolledSmooth, true, 'and smoothly');
});

// A heading's own scroll-margin-top of 0 (no bars above it) is a real margin
// and must win; only a missing one falls back to the global offset.
async function navigateWithMargin(margin: string): Promise<number | null> {
  const r = await startWebview({ scrollY: 0 });
  const { navigateToHash } = await r.load('anchors/anchors.ts');
  (await r.load('top-bars/geometry.ts')).setTopBarsOffset(50);
  const heading = {
    style: { scrollMarginTop: margin },
    getBoundingClientRect: () => ({ top: 4000 }),
  };
  byId(r, 'content').querySelector = (s) => (s === '#h' ? heading : null);
  navigateToHash('h', false);
  return r.state.scrolledTo;
}

test('navigation honors a per-heading scroll-margin-top of 0 (#44)', async () => {
  assert.strictEqual(
    await navigateWithMargin('0px'),
    4000,
    'margin 0, not the global 50',
  );
});

test('navigation falls back to the global offset without a per-heading margin (#44)', async () => {
  assert.strictEqual(await navigateWithMargin(''), 4000 - 50);
});
