// Folding a section: the fold chevron's stylesheet, the fold set, and a click path
// that only writes (#44 P2).
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import { renderFoldDom } from '../../helpers/webview-fixtures.ts';

test('the fold chevron is a fixed in-heading column that hides on a grace delay (#44 P2)', () => {
  // The chevron sits inside the heading padding (positive left), so it shares the
  // heading hover box (no flicker moving onto it) and every heading text starts on
  // the same column. It fades out on a grace delay, not instantly (hover-intent).
  const css = sheet('page/page.css', 'folding/folding.css');
  assert.match(
    css.text,
    /#content h1[^{]*\{[^}]*padding-left:\s*1\.5rem/,
    'headings reserve a fixed-rem fold gutter (same column for every level)',
  );
  // Inline + vertical-align:middle centres the glyph on the text optical middle
  // independent of the heading font size (a font-size-relative box drifted); a
  // fixed-rem width hung into the gutter keeps one shared column.
  assert.match(
    css.ruleBody('.mw-fold-toggle'),
    /vertical-align:\s*middle/,
    'centred on the text line, not a font-relative box',
  );
  assert.match(
    css.ruleBody('.mw-fold-toggle'),
    /width:\s*1\.5rem/,
    'chevron box is the fixed gutter column',
  );
  assert.match(
    css.ruleBody('.mw-fold-toggle'),
    /margin-left:\s*-1\.5rem/,
    'hung into the reserved gutter',
  );
  assert.match(
    css.ruleBody('.mw-fold-toggle'),
    /opacity\s*0\.15s\s*ease\s*0\.8s/,
    'hides after a long (~800ms) hover-out grace',
  );
  assert.match(
    css.text,
    /scrollbar-gutter:\s*stable/,
    'the scrollbar gutter is reserved so folding-to-fit never slides the content',
  );
});

test('toggleFold flips a heading id in the fold set (#44 P2)', async () => {
  const r = await startWebview();
  const { toggleFold } = await r.load('folding/fold.ts');
  const { foldedIds } = await r.load('folding/sections.ts');
  assert.strictEqual(foldedIds.has('sec'), false);
  toggleFold('sec');
  assert.strictEqual(foldedIds.has('sec'), true, 'first toggle folds');
  toggleFold('sec');
  assert.strictEqual(foldedIds.has('sec'), false, 'second toggle unfolds');
  toggleFold('');
  assert.strictEqual(foldedIds.has(''), false, 'an empty id is ignored');
});

test('a fold click reads no layout: no offsetParent, no rect (#44 P2 perf)', async () => {
  // Everything a click does must be a WRITE, so the browser lays the folded
  // document out once, asynchronously - not inside the click handler. The
  // visibility mask the scroll-spy consumes is derived from the fold set instead.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { blocks } = renderFoldDom(r);
  for (const b of blocks) {
    b.rects = 0;
    b.offsetParentReads = 0;
  }
  toggleFold('a');
  assert.deepStrictEqual(
    blocks.map((b) => b.offsetParentReads),
    blocks.map(() => 0),
    'no offsetParent read (a forced synchronous layout) on the click path',
  );
  assert.deepStrictEqual(
    blocks.map((b) => b.rects),
    blocks.map(() => 0),
    'no getBoundingClientRect on the click path either',
  );
});

test('a fold writes only the blocks whose visibility changed (#44 P2 perf)', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const { blocks } = renderFoldDom(r);
  for (const b of blocks) b.writes = 0;
  toggleFold('b'); // hides blocks 3 and 4 only
  assert.deepStrictEqual(
    blocks.map((b) => b.writes),
    [0, 0, 0, 1, 1, 0, 0],
    'only the folded section, not every block in the document',
  );
  for (const b of blocks) b.writes = 0;
  toggleFold('a'); // a hides its whole section: 1..4 (3, 4 already hidden)
  assert.deepStrictEqual(
    blocks.map((b) => b.writes),
    [0, 1, 1, 0, 0, 0, 0],
    'the blocks already hidden by the nested fold are not rewritten',
  );
});
