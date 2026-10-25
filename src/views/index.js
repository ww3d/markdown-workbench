// Workbench view machinery shared by both entry modes (WebviewPanel preview
// and CustomTextEditorProvider): the webview HTML skeleton (loading the
// webview script/style as real media assets), render + bidirectional
// scroll-sync wiring, configuration resolution, and the surgical toggle paths
// that mirror every checkbox change into the source file.

const {
  TAB_TITLE_PREFIX,
  setExtensionUri,
  workbenchIconPath,
} = require('./identity');
const { configuredViewConfig } = require('./config');
const {
  captureScrollPosition,
  revealLastKnownLine,
  scrollEditorToLine,
  getVisibleLine,
} = require('./scroll-sync');
const { CHECKBOX_RE, applyToggle, applyCellToggle } = require('./toggles');
const { getWebviewHtml } = require('./html');
const {
  WorkbenchEditorProvider,
  wireWebview,
  getActiveCustomDocUri,
} = require('./wire');

module.exports = {
  CHECKBOX_RE,
  TAB_TITLE_PREFIX,
  setExtensionUri,
  getActiveCustomDocUri,
  workbenchIconPath,
  configuredViewConfig,
  captureScrollPosition,
  revealLastKnownLine,
  scrollEditorToLine,
  WorkbenchEditorProvider,
  wireWebview,
  applyToggle,
  applyCellToggle,
  getWebviewHtml,
  // Exported for tests only.
  _internal: {
    CHECKBOX_RE,
    configuredViewConfig,
    getVisibleLine,
    scrollEditorToLine,
    applyToggle,
    applyCellToggle,
    getWebviewHtml,
  },
};
