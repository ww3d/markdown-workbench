// The webview HTML skeleton getWebviewHtml writes: CSP, nonce, asset URIs and the
// containers the webview script expects.
import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh } from '../helpers/vscode-mock.ts';

/** The skeleton builder, driven with a fake webview (URIs as strings). */
interface HtmlApi {
  setExtensionUri(uri: string): void;
  getWebviewHtml(webview: {
    cspSource: string;
    asWebviewUri(uri: unknown): string;
  }): string;
}

test('getWebviewHtml embeds CSP, a script nonce and both webview asset URIs', async () => {
  install();
  const views = await loadFresh<HtmlApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  const webview = {
    cspSource: 'vscode-webview://host',
    asWebviewUri: (uri: unknown) => `https://webview/${String(uri)}`,
  };
  const html = views.getWebviewHtml(webview);
  // Content-Security-Policy with a nonce'd script source.
  assert.match(html, /<meta http-equiv="Content-Security-Policy"/);
  const nonce = html.match(/script-src 'nonce-([A-Za-z0-9]+)'/)?.[1] ?? '';
  assert.ok(nonce.length >= 16, 'nonce is present and non-trivial');
  // The <script> tag carries the very same nonce.
  assert.match(html, new RegExp(`<script nonce="${nonce}" src=`));
  // Both media assets are linked through asWebviewUri (mock joins with "/").
  assert.match(html, /href="https:\/\/webview\/EXT\/media\/webview\.css"/);
  assert.match(html, /src="https:\/\/webview\/EXT\/media\/webview\.js"/);
  // The vendored morphdom global must load, and before webview.js so it is ready
  // at the first render (the render path calls morphdom, #44 P2).
  assert.match(html, /src="https:\/\/webview\/EXT\/media\/morphdom\.js"/);
  assert.ok(
    html.indexOf('/media/morphdom.js') < html.indexOf('/media/webview.js'),
    'morphdom loads before the webview script',
  );
  // style-src must allow inline styles: Shiki emits token colors as inline
  // style="color:..." attributes; a strict style-src would blank them out
  // (the headless DOM tests don't parse innerHTML, so only this guards it).
  const styleSrc = html.match(/style-src ([^;]+);/)?.[1] ?? '';
  assert.match(styleSrc, /'unsafe-inline'/);
});

test('the webview skeleton carries the breadcrumb, sticky-scroll and dropdown containers', async () => {
  install();
  const views = await loadFresh<HtmlApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  const html = views.getWebviewHtml({
    cspSource: 'vscode-webview://host',
    asWebviewUri: (u) => `https://webview/${String(u)}`,
  });
  assert.match(html, /id="breadcrumb"/);
  assert.match(html, /id="sticky-scroll"/);
  assert.match(html, /id="breadcrumb-dropdown"/);
  // tabindex -1 keeps the new controls out of the tab order (PR #45 decision).
  assert.match(html, /id="breadcrumb"[^>]*tabindex="-1"/);
});
