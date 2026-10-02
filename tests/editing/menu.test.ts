// Authoring quick-pick menu (Alt+M).

import { test } from 'node:test';
import assert from 'node:assert';
import {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
  defined,
} from '../helpers/vscode-mock.ts';
import type { MockContext } from '../helpers/vscode-mock.ts';

// The editing entry point with the mock context in place of a vscode.ExtensionContext.
interface Editing {
  registerEditingCommands(context: MockContext, shikiLangs: string[]): void;
}

const vscode = install();
const editing = await loadFresh<Editing>('src/editing/index.ts');
const ctx: MockContext = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id: string) => defined(vscode._commands?.[id], `command ${id}`)();

function editorOn(
  text: string,
  line: number,
  character: number,
  endLine?: number,
  endCharacter?: number,
) {
  const doc = new MockDocument(text);
  const sel =
    endLine === undefined || endCharacter === undefined
      ? new Selection(line, character, line, character)
      : new Selection(line, character, endLine, endCharacter);
  const editor = new MockEditor(doc, sel);
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}

// The command of a menu entry; anything else is no entry.
function commandOf(item: unknown): string[] {
  return typeof item === 'object' &&
    item !== null &&
    'cmd' in item &&
    typeof item.cmd === 'string'
    ? [item.cmd]
    : [];
}

test('authoringMenu executes the picked command', async () => {
  editorOn('', 0, 0);
  vscode._quickPickResult = { label: 'x', cmd: 'markdownWorkbench.formatBold' };
  await run('markdownWorkbench.authoringMenu');
  assert.ok(
    vscode._executed.some((e) => e.id === 'markdownWorkbench.formatBold'),
  );
});

test('the menu offers the table sort and column commands (REQ-052)', async () => {
  let offered: string[] = [];
  const orig = vscode.window.showQuickPick;
  vscode.window.showQuickPick = (items) => {
    offered = Array.isArray(items) ? items.flatMap(commandOf) : [];
    return Promise.resolve(undefined);
  };
  await run('markdownWorkbench.authoringMenu');
  vscode.window.showQuickPick = orig;
  for (const id of [
    'sortTableAscending',
    'sortTableDescending',
    'insertColumnLeft',
    'insertColumnRight',
    'deleteColumn',
    'moveColumnLeft',
    'moveColumnRight',
  ])
    assert.ok(offered.includes(`markdownWorkbench.${id}`), id);
});
