// Local declaration shim for `./index.js` while the view machinery is still
// plain JavaScript (the host scope has no `allowJs`, so the import would fail
// with TS7016). It names only what `src/extension.ts` consumes. Remove it when
// `src/views/` moves to TypeScript; the real module then carries the types.
import type * as vscode from 'vscode';

/** Title prefix shared by every workbench tab. */
export const TAB_TITLE_PREFIX: string;

/** Remembers the extension root for icons and webview assets. */
export function setExtensionUri(uri: vscode.Uri): void;

/** The document of the focused workbench custom editor, if any. */
export function getActiveCustomDocUri(): vscode.Uri | null;

/** Light/dark tab icon paths for a workbench view. */
export function workbenchIconPath(): { light: vscode.Uri; dark: vscode.Uri };

/** Stores the top visible line of a document's editor before the view opens. */
export function captureScrollPosition(uri: vscode.Uri): void;

/** Scrolls an editor to the last line the workbench view reported. */
export function revealLastKnownLine(editor: vscode.TextEditor): void;

/** Custom editor provider behind `markdownWorkbench.editor`. */
export class WorkbenchEditorProvider
  implements vscode.CustomTextEditorProvider
{
  resolveCustomTextEditor(
    document: vscode.TextDocument,
    webviewPanel: vscode.WebviewPanel,
  ): void;
}

/** Wires a webview panel to a document: render, messages, scroll sync. */
export function wireWebview(
  document: vscode.TextDocument,
  webviewPanel: vscode.WebviewPanel,
  closeWithDocument: boolean,
): void;
