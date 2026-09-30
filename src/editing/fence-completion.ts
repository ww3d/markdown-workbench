// --- Fence language completion -------------------------------------------------------------
import * as vscode from 'vscode';

/**
 * Suggest language identifiers while typing after ``` (or ~~~), from the bundled
 * `shikiLangs` plus common aliases; the provider lives as long as `context`.
 */
function registerFenceLanguageCompletion(
  context: Pick<vscode.ExtensionContext, 'subscriptions'>,
  shikiLangs: readonly string[],
): void {
  // Bundled language ids plus the aliases shiki resolves for them.
  const langs = [
    ...new Set([
      ...shikiLangs,
      'bash',
      'sh',
      'shell',
      'zsh',
      'ps',
      'ps1',
      'batch',
      'js',
      'ts',
      'yml',
    ]),
  ].sort();

  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider(
      'markdown',
      {
        provideCompletionItems(document, position) {
          const before = document
            .lineAt(position.line)
            .text.slice(0, position.character);
          const m = /^(\s*)(`{3,}|~{3,})([\w-]*)$/.exec(before);
          if (!m) return undefined;
          const replaceRange = new vscode.Range(
            position.line,
            position.character - (m[3] ?? '').length,
            position.line,
            position.character,
          );
          return langs.map((lang) => {
            const item = new vscode.CompletionItem(
              lang,
              vscode.CompletionItemKind.Value,
            );
            item.range = replaceRange;
            return item;
          });
        },
      },
      '`',
      '~',
    ),
  );
}

export { registerFenceLanguageCompletion };
