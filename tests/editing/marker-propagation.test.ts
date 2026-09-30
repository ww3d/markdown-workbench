// Marker type propagation (document change listener): custom-marker type
// follow, native number resequencing, and the re-entrancy guard.

import { test } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
} from '../helpers/vscode-mock.ts';
import type { MockContext } from '../helpers/vscode-mock.ts';

const vscode = install();
// The editing entry point as this suite uses it; typed here until it moves to TypeScript.
interface Editing {
  registerEditingCommands(context: MockContext, shikiLangs: string[]): void;
  _internal: { setPropagatingForTest(v: boolean): void };
}
const editing = await loadFresh<Editing>('src/editing/index.js');
const ctx: MockContext = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);

function change(line: number, character: number) {
  return {
    contentChanges: [
      { range: { start: { line, character }, end: { line, character } } },
    ],
  };
}

// Deliver a change at line/character to the registered document listener.
function fire(doc: MockDocument, line: number, character: number) {
  defined(
    vscode._docChangeListener,
    'document change listener',
  )({
    document: doc,
    ...change(line, character),
  });
}

// The replacement texts of the workspace edits applied so far.
const appliedTexts = () =>
  vscode._applied.map((o) => (o.kind === 'delete' ? undefined : o.text));

test('marker type propagation listener follows a first-item change', () => {
  vscode._config['lists.extraMarkers'] = ['1)', 'a)'];
  vscode._config['lists.extraMarkersEnabled'] = true;
  vscode._applied.length = 0;
  const doc = new MockDocument('1) x\nb) y\nc) z');
  fire(doc, 0, 0);
  delete vscode._config['lists.extraMarkers'];
  delete vscode._config['lists.extraMarkersEnabled'];
  assert.deepStrictEqual(appliedTexts(), ['2)', '3)']);
});

test('marker type propagation listener stays quiet when no markers are enabled', () => {
  vscode._applied.length = 0;
  const doc = new MockDocument('a) x\nb) y'); // custom markers, not recognized when off
  fire(doc, 0, 0);
  assert.strictEqual(vscode._applied.length, 0);
});

test('manual native number change renumbers the following siblings (no reset)', () => {
  vscode._applied.length = 0;
  const doc = new MockDocument('1. a\n5. b\n3. c\n4. d'); // user typed 2.->5.
  fire(doc, 1, 0);
  // 5. stays; the following continue from it -> 6, 7 (line0 1. untouched).
  assert.deepStrictEqual(appliedTexts(), ['6.', '7.']);
});

test('editing a line body does not reflow an intentionally non-sequential list', () => {
  vscode._applied.length = 0;
  const doc = new MockDocument('1. a\n5. b\n6. c');
  // change in the text (character past the marker), marker untouched
  fire(doc, 0, 3);
  assert.strictEqual(vscode._applied.length, 0);
});

test('the re-entrancy guard suppresses the listener during our own edits', () => {
  vscode._applied.length = 0;
  editing._internal.setPropagatingForTest(true);
  const doc = new MockDocument('1. a\n5. b\n6. c');
  fire(doc, 1, 0);
  editing._internal.setPropagatingForTest(false);
  assert.strictEqual(vscode._applied.length, 0);
});
