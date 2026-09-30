import * as vscode from 'vscode';

/**
 * Tab/panel title prefix for every workbench view (single constant: both the
 * preview panel and the custom editor read it, so it is defined once).
 */
const TAB_TITLE_PREFIX = 'Workbench: ';

// Extension root, set in activate; used for the tab icon and the webview
// media assets (script/style URIs, localResourceRoots).
let rootUri: vscode.Uri | null = null;

/** Records the extension root; `activate` calls it before any view opens. */
function setExtensionUri(uri: vscode.Uri): void {
  rootUri = uri;
}

/**
 * The extension root recorded by {@link setExtensionUri}. Every caller builds a
 * resource URI from it, which cannot work before activation, so an unset root
 * fails here by name.
 */
function getExtensionUri(): vscode.Uri {
  if (!rootUri)
    throw new Error('extension URI not set: activate() records it first');
  return rootUri;
}

/** Light/dark tab icon paths for a workbench view. */
function workbenchIconPath(): { light: vscode.Uri; dark: vscode.Uri } {
  const extensionUri = getExtensionUri();
  return {
    light: vscode.Uri.joinPath(extensionUri, 'media', 'workbench-light.svg'),
    dark: vscode.Uri.joinPath(extensionUri, 'media', 'workbench-dark.svg'),
  };
}

export {
  TAB_TITLE_PREFIX,
  setExtensionUri,
  getExtensionUri,
  workbenchIconPath,
};
