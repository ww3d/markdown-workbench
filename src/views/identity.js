const vscode = require('vscode');

// Tab/panel title prefix for every workbench view (single constant: both the
// preview panel and the custom editor read it, so it is defined once).
const TAB_TITLE_PREFIX = 'Workbench: ';

// Extension root, set in activate; used for the tab icon and the webview
// media assets (script/style URIs, localResourceRoots).
let extensionUri = null;
function setExtensionUri(uri) {
  extensionUri = uri;
}
function getExtensionUri() {
  return extensionUri;
}

function workbenchIconPath() {
  return {
    light: vscode.Uri.joinPath(extensionUri, 'media', 'workbench-light.svg'),
    dark: vscode.Uri.joinPath(extensionUri, 'media', 'workbench-dark.svg'),
  };
}

module.exports = {
  TAB_TITLE_PREFIX,
  setExtensionUri,
  getExtensionUri,
  workbenchIconPath,
};
