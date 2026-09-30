// The heading ancestor chain shared by the scroll-spy, the TOC and the top bars.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';

test('ancestorChain: root-first chain of strictly-smaller levels', async () => {
  const r = await startWebview();
  const { ancestorChain } = await r.load('scroll-spy/chain.ts');
  // h1 > h2 > h3 > h2(active): drops the h3, keeps h1 and the nearest h2 above.
  assert.deepStrictEqual(ancestorChain([1, 2, 3, 2], 3), [0, 3]);
  assert.deepStrictEqual(ancestorChain([1, 2, 3], 2), [0, 1, 2]);
  assert.deepStrictEqual(ancestorChain([1], 0), [0]);
});

test('ancestorChain: a level jump (h1 -> h4) takes the nearest shallower heading', async () => {
  const r = await startWebview();
  const { ancestorChain } = await r.load('scroll-spy/chain.ts');
  assert.deepStrictEqual(ancestorChain([1, 4], 1), [0, 1]);
  assert.deepStrictEqual(ancestorChain([1, 4, 2], 2), [0, 2]);
  assert.deepStrictEqual(ancestorChain([2, 4], -1), []); // nothing active
});
