// Workbench view machinery shared by both entry modes (WebviewPanel preview
// and CustomTextEditorProvider): the webview HTML skeleton (loading the
// webview script/style as real media assets), render + bidirectional
// scroll-sync wiring, configuration resolution, and the surgical toggle paths
// that mirror every checkbox change into the source file.

import {
  TAB_TITLE_PREFIX,
  setExtensionUri,
  workbenchIconPath,
} from './identity.ts';
import { configuredViewConfig } from './config.ts';
import {
  captureScrollPosition,
  revealLastKnownLine,
  scrollEditorToLine,
  getVisibleLine,
} from './scroll-sync.ts';
import { CHECKBOX_RE, applyToggle, applyCellToggle } from './toggles.ts';
import { getWebviewHtml } from './html.ts';
import {
  WorkbenchEditorProvider,
  wireWebview,
  getActiveCustomDocUri,
} from './wire.ts';

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
/** Internals exposed for the unit tests only; not part of the view API. */
export const _internal = {
  CHECKBOX_RE,
  configuredViewConfig,
  getVisibleLine,
  scrollEditorToLine,
  applyToggle,
  applyCellToggle,
  getWebviewHtml,
};
