#!/usr/bin/env node
// Webview smoke test (REQ-035 of docs/tasks/92-typescript-webview.md): starts the
// BUILT dist/webview.js + dist/webview.css in a DOM (happy-dom) the way the preview
// panel does, and asserts a visible render. The unit tests import the webview modules
// from src/ into a DOM mock; only this run sees what the bundler made of them - a
// dropped module, a broken IIFE, a missing morphdom, a stylesheet the browser cannot
// parse.
//
// The bundle is copied to a fresh directory under os.tmpdir() and read from there,
// like the bundle smoke: nothing of the repository is on its lookup path (the IIFE
// must not need one). The page skeleton comes from getWebviewHtml itself, so the
// element ids the script expects are the ones the host writes; its <script>/<link>
// tags are not fetched, the bundle is evaluated in the window instead (no new
// Function) and the stylesheet goes in as a <style>.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Window } from 'happy-dom';
import { layoutPath } from '../eng/layout.ts';
import { install, loadFresh } from '../tests/helpers/vscode-mock.ts';
import type { WebviewToHost } from '../src/webview/protocol.ts';

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-webview-smoke-'));
for (const file of ['webview.js', 'webview.css'])
  fs.copyFileSync(path.join(layoutPath('dist'), file), path.join(tmpDir, file));

function done(code: number, msg: string): never {
  if (code !== 0) console.error(`WEBVIEW SMOKE TEST FAILED: ${msg}`);
  else console.log(msg);
  fs.rmSync(tmpDir, { recursive: true, force: true });
  process.exit(code);
}

/** The skeleton builder, driven with a fake webview (URIs as strings), as in the tests. */
interface HtmlApi {
  setExtensionUri(uri: string): void;
  getWebviewHtml(webview: {
    cspSource: string;
    asWebviewUri(uri: unknown): string;
  }): string;
}

async function skeleton(): Promise<string> {
  install();
  const views = await loadFresh<HtmlApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  return views.getWebviewHtml({
    cspSource: 'vscode-webview://smoke',
    asWebviewUri: (uri) => `https://webview.local/${String(uri)}`,
  });
}

async function main(): Promise<void> {
  const window = new Window({
    url: 'https://webview.local/',
    width: 1400,
    height: 900,
    settings: {
      disableJavaScriptFileLoading: true,
      disableCSSFileLoading: true,
      handleDisabledFileLoadingAsSuccess: true,
    },
  });
  const errors: string[] = [];
  window.addEventListener('error', (e) => errors.push(String(e)));
  const document = window.document;
  document.write(await skeleton());
  const style = document.createElement('style');
  style.textContent = fs.readFileSync(path.join(tmpDir, 'webview.css'), 'utf8');
  document.head.appendChild(style);

  const posted: WebviewToHost[] = [];
  Object.assign(window, {
    acquireVsCodeApi: () => ({
      postMessage: (m: WebviewToHost) => posted.push(m),
      setState() {},
      getState: () => undefined,
    }),
  });
  window.eval(fs.readFileSync(path.join(tmpDir, 'webview.js'), 'utf8'));
  if (!posted.some((m) => m.type === 'ready'))
    done(1, `the bundle posted no ready (posted: ${JSON.stringify(posted)})`);

  const send = (data: unknown) =>
    window.dispatchEvent(new window.MessageEvent('message', { data }));
  send({ type: 'config', maxWidth: '980px' });
  send({
    type: 'render',
    html: '<h1 id="title" data-line="0">Title</h1><p data-line="2">hello <strong>world</strong></p>',
    version: 1,
  });
  await window.happyDOM.waitUntilComplete();

  const content = document.getElementById('content');
  const text = content?.textContent ?? '';
  if (!/Title/.test(text) || !/hello world/.test(text))
    done(1, `#content shows no rendered document: ${JSON.stringify(text)}`);
  if (!content?.querySelector('h1 .mw-fold-toggle'))
    done(
      1,
      'the heading carries no fold control (render post-processing missing)',
    );
  const tocEntries = document.querySelectorAll('#toc-list .toc-link').length;
  if (tocEntries !== 1) done(1, `expected 1 TOC entry, found ${tocEntries}`);
  // The stylesheet reached the page: the minimap rail is a fixed overlay only by it.
  const minimap = document.getElementById('minimap');
  const position = minimap ? window.getComputedStyle(minimap).position : '';
  if (position !== 'fixed')
    done(
      1,
      `dist/webview.css is not applied (#minimap position "${position}")`,
    );
  if (errors.length) done(1, `page errors: ${errors.join('; ')}`);
  await window.happyDOM.close();
  done(
    0,
    'Webview smoke test passed: the built dist/webview.js rendered the document into #content ' +
      'from an isolated directory, built the TOC, posted ready; dist/webview.css applied.',
  );
}

main().catch((err) => done(1, `unexpected error: ${err?.stack || err}`));
