// The webview HTML skeleton getWebviewHtml writes: CSP, nonce, asset URIs and the
// containers the webview script expects.
import { test } from 'node:test';
import assert from 'node:assert';
import { relativeLayout } from '../../eng/layout.ts';
import { install, loadFresh } from '../helpers/vscode-mock.ts';

/** The view identity module. */
type IdentityModule = typeof import('../../src/views/identity.ts');

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
  // Exactly one script and one stylesheet, both the bundles in dist/, linked
  // through asWebviewUri (the mock joins with "/"); morphdom is inside the script.
  assert.deepStrictEqual(
    [...html.matchAll(/<script\b[^>]*>/g)].map((m) => m[0]),
    [`<script nonce="${nonce}" src="https://webview/EXT/dist/webview.js">`],
  );
  assert.deepStrictEqual(
    [...html.matchAll(/<link\b[^>]*>/g)].map((m) => m[0]),
    ['<link rel="stylesheet" href="https://webview/EXT/dist/webview.css">'],
  );
  assert.doesNotMatch(html, /<style\b/, 'no inline stylesheet');
  assert.doesNotMatch(html, /morphdom|\/media\/webview/, 'no second script');
  // style-src must allow inline styles: Shiki emits token colors as inline
  // style="color:..." attributes; a strict style-src would blank them out
  // (the headless DOM tests don't parse innerHTML, so only this guards it).
  const styleSrc = html.match(/style-src ([^;]+);/)?.[1] ?? '';
  assert.match(styleSrc, /'unsafe-inline'/);
});

test('the CSP is exactly the documented policy, directive by directive (docs/DECISIONS.md #22)', async () => {
  install();
  const views = await loadFresh<HtmlApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  const src = 'vscode-webview://host';
  const html = views.getWebviewHtml({
    cspSource: src,
    asWebviewUri: (u) => `https://webview/${String(u)}`,
  });
  const csp = html.match(
    /<meta http-equiv="Content-Security-Policy" content="([^"]*)">/,
  )?.[1];
  const nonce = csp?.match(/'nonce-([A-Za-z0-9]+)'/)?.[1] ?? '';
  assert.strictEqual(
    csp,
    [
      "default-src 'none'",
      `img-src ${src} https: http: data:`,
      `style-src ${src} 'unsafe-inline'`,
      `font-src ${src}`,
      `script-src 'nonce-${nonce}'`,
    ].join('; '),
  );
});

test('the bundle folder the skeleton loads from is the layout dist folder', async () => {
  install();
  const { BUNDLE_DIR } = await loadFresh<IdentityModule>(
    'src/views/identity.ts',
  );
  assert.strictEqual(BUNDLE_DIR, relativeLayout.dist);
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
