import * as vscode from 'vscode';
import crypto from 'node:crypto';
import { getExtensionUri } from './identity.ts';

/**
 * A fresh CSP nonce (up to 24 alphanumerics). The webview runs untrusted-looking but
 * author-owned content: the script is gated by a per-load nonce; styles/images
 * come from the webview origin only.
 */
function makeNonce(): string {
  return crypto
    .randomBytes(16)
    .toString('base64')
    .replace(/[^a-zA-Z0-9]/g, '')
    .slice(0, 24);
}

/**
 * Slim skeleton that loads the real media/webview.css and media/webview.js via
 * webview.asWebviewUri. Both files ship in the vsix and run in the webview, so
 * they are not part of the extension-host bundle.
 */
function getWebviewHtml(webview: vscode.Webview): string {
  const nonce = makeNonce();
  const extensionUri = getExtensionUri();
  const scriptUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'media', 'webview.js'),
  );
  // Vendored morphdom (like codicon.ttf): the preview morphs the rendered DOM on
  // each update instead of replacing innerHTML, so a content edit preserves scroll
  // and selection. Loaded before webview.js so its global is ready at first render.
  const morphdomUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'media', 'morphdom.js'),
  );
  const styleUri = webview.asWebviewUri(
    vscode.Uri.joinPath(extensionUri, 'media', 'webview.css'),
  );
  const csp = [
    "default-src 'none'",
    // http: is kept alongside https:/data: so remote images in user markdown
    // keep loading as they did before (the inline view had no CSP at all).
    `img-src ${webview.cspSource} https: http: data:`,
    // 'unsafe-inline' is required for styles: Shiki emits per-token colors as
    // inline style="color:..." attributes in the rendered HTML (injected via
    // innerHTML), and the rendered markdown may carry inline styles too. The
    // script stays nonce-gated; only styles are relaxed.
    `style-src ${webview.cspSource} 'unsafe-inline'`,
    // The vendored codicon.ttf (the native VS Code twistie glyph) is loaded via
    // asWebviewUri, so only the webview origin needs to be allowed for fonts.
    `font-src ${webview.cspSource}`,
    `script-src 'nonce-${nonce}'`,
  ].join('; ');
  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<link rel="stylesheet" href="${styleUri}">
</head>
<body>
<nav id="breadcrumb" aria-label="Breadcrumb" tabindex="-1"></nav>
<div id="sticky-scroll" aria-hidden="true"></div>
<div id="breadcrumb-dropdown" role="menu" tabindex="-1"></div>
<div id="content"></div>
<div id="minimap"><div id="minimap-content"></div><div id="minimap-slider"></div></div>
<nav id="toc" aria-label="Table of contents"><div id="toc-title">On this page</div><ol id="toc-list"></ol></nav>
<button id="toc-fab" type="button" aria-label="Table of contents" aria-expanded="false" aria-controls="toc" title="Table of contents" tabindex="-1"><svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M2 3.5h3v1H2v-1zM7 3.5h7v1H7v-1zM2 7.5h3v1H2v-1zM7 7.5h7v1H7v-1zM2 11.5h3v1H2v-1zM7 11.5h7v1H7v-1z"/></svg></button>
<div id="toc-backdrop"></div>
<div class="hint">Click = toggle &middot; Ctrl+Click = select &middot; Shift+Click = select range &middot; toggle inside selection = toggle all &middot; Esc = clear selection</div>
<script nonce="${nonce}" src="${morphdomUri}"></script>
<script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
}

export { makeNonce, getWebviewHtml };
