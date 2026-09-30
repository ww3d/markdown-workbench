// Editor -> webview: the fractional source line the host sends becomes a scroll
// position between, or inside, the rendered [data-line] elements.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import { seedLineEntries } from '../../helpers/webview-fixtures.ts';

// Where the webview scrolls for a host scrollTo of `line` over the seeded map.
async function scrolledFor(
  entries: Parameters<typeof seedLineEntries>[1],
  line: number,
): Promise<number | null> {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  await seedLineEntries(r, entries);
  r.send({ type: 'scrollTo', line });
  return r.state.scrolledTo;
}

test('a line between two [data-line] elements scrolls proportionally between them', async () => {
  assert.strictEqual(
    await scrolledFor(
      [
        { line: 10, top: 0 },
        { line: 20, top: 200 },
      ],
      15,
    ),
    100,
  );
});

test('a line inside a multi-line block scrolls proportionally through it (data-line-end)', async () => {
  assert.strictEqual(
    await scrolledFor([{ line: 10, endLine: 20, top: 0, height: 400 }], 15),
    200,
  );
});

test('a line past the last element scrolls at most one element height beyond it', async () => {
  assert.strictEqual(
    await scrolledFor([{ line: 20, top: 200, height: 50 }], 25),
    250,
  );
});

test('line 0 or above scrolls to the very top', async () => {
  assert.strictEqual(await scrolledFor([{ line: 10, top: 300 }], 0), 0);
});
