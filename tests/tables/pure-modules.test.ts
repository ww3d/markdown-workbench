// The pure table modules must stay usable without the extension host - unlike
// the modules that register commands and providers, they deliberately import no
// `vscode`, and this file deliberately does not install the mock.
// tests/markdown/syntax.test.ts holds the same guarantee for the markdown primitives.
import { test } from 'node:test';
import assert from 'node:assert';

const PURE = [
  'row',
  'blocks',
  'detect',
  'width',
  'format',
  'grid-ops',
  'sort',
  'csv',
];

for (const name of PURE) {
  test(`src/tables/${name}.ts loads without vscode`, async () => {
    // A query of its own makes it a fresh load, before any mock is installed.
    const fresh = new URL(
      `../../src/tables/${name}.ts?nomock`,
      import.meta.url,
    );
    await assert.doesNotReject(import(fresh.href));
  });
}
