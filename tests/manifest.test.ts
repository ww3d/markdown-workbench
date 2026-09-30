// The extension manifest wiring the extension relies on: activation events and the `when`
// clauses of the keybindings. Read from package.json, no build needed.
import { test } from 'node:test';
import assert from 'node:assert';
import pkg from '../package.json' with { type: 'json' };

test('the preview panel viewType is an activation event, so a restored panel wakes the extension', () => {
  assert.ok(
    pkg.activationEvents.includes('onWebviewPanel:markdownWorkbench.preview'),
    'a restored preview panel is deserialized only after activation',
  );
});

// The `when` clauses of a command's keybinding, split at `&&`.
function whenClauses(command: string): string[] {
  const binding = pkg.contributes.keybindings.find(
    (k) => k.command === command,
  );
  assert.ok(binding, `${command} has a keybinding`);
  return binding.when.split('&&').map((c) => c.trim());
}

for (const command of [
  'markdownWorkbench.onUpKey',
  'markdownWorkbench.onDownKey',
]) {
  test(`${command} is bound only inside a table, with tables and arrow navigation enabled`, () => {
    const when = whenClauses(command);
    for (const clause of [
      'markdownWorkbench.inTable',
      'config.markdownWorkbench.tables.enabled',
      'config.markdownWorkbench.tables.arrowNavigation',
    ]) {
      assert.ok(when.includes(clause), `${command} lacks "${clause}"`);
    }
  });
}

for (const [command, setting] of [
  [
    'markdownWorkbench.joinForwardOrFallback',
    'config.markdownWorkbench.editing.forwardJoin.enabled',
  ],
  [
    'markdownWorkbench.joinBackwardOrFallback',
    'config.markdownWorkbench.editing.backwardJoin.enabled',
  ],
] as const) {
  test(`${command} is bound only while its join setting is on`, () => {
    assert.ok(
      whenClauses(command).includes(setting),
      `${command} lacks "${setting}"`,
    );
  });
}
