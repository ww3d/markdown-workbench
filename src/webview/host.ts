// The webview's one access point to the extension host. VS Code injects
// acquireVsCodeApi into the webview and allows a single call per webview, so the
// handle is acquired lazily on first use and kept.

import type { WebviewState, WebviewToHost } from './protocol.ts';

/** The part of the VS Code webview API the preview uses. */
export interface VsCodeApi {
  postMessage(message: WebviewToHost): void;
  setState(state: WebviewState): void;
  getState(): WebviewState | undefined;
}

declare function acquireVsCodeApi(): VsCodeApi;

let api: VsCodeApi | undefined;

/** The VS Code webview API, acquired on the first call (one call per webview allowed). */
export function vscodeApi(): VsCodeApi {
  api ??= acquireVsCodeApi();
  return api;
}
