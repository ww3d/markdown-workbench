// Workbench view machinery shared by both entry modes (WebviewPanel preview
// and CustomTextEditorProvider): the webview HTML skeleton (loading the
// webview script/style as real media assets), render + bidirectional
// scroll-sync wiring, configuration resolution, and the surgical toggle paths
// that mirror every checkbox change into the source file.

import {
  TAB_TITLE_PREFIX,
  setExtensionUri,
  workbenchIconPath,
} from './identity.js';
import { configuredViewConfig } from './config.js';
import {
  captureScrollPosition,
  revealLastKnownLine,
  scrollEditorToLine,
  getVisibleLine,
} from './scroll-sync.js';
import { CHECKBOX_RE, applyToggle, applyCellToggle } from './toggles.js';
import { getWebviewHtml } from './html.js';
import {
  WorkbenchEditorProvider,
  wireWebview,
  getActiveCustomDocUri,
} from './wire.js';

export {
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
};
// Exported for tests only.
export const _internal = {
  CHECKBOX_RE,
  configuredViewConfig,
  getVisibleLine,
  scrollEditorToLine,
  applyToggle,
  applyCellToggle,
  getWebviewHtml,
};
