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
import type { WebviewState, WebviewToHost } from '../src/webview/protocol.ts';
import manifest from '../package.json' with { type: 'json' };

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

/** One load of the built bundle in a page: the window, what it posted, and its page errors. */
interface Page {
  readonly window: Window;
  readonly posted: WebviewToHost[];
  readonly errors: string[];
}

/**
 * Opens the page skeleton with the stylesheet, hands the bundle a webview API whose
 * `getState` returns `state` (what `setState` saved before the restart), and evaluates
 * `dist/webview.js`.
 */
async function openPage(state: WebviewState | undefined): Promise<Page> {
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
  // An ErrorEvent stringifies to "[object ErrorEvent]"; the message is what names the fault.
  window.addEventListener('error', (e) =>
    errors.push(e instanceof window.ErrorEvent ? e.message : String(e)),
  );
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
      getState: () => state,
    }),
  });
  window.eval(fs.readFileSync(path.join(tmpDir, 'webview.js'), 'utf8'));
  return { window, posted, errors };
}

async function main(): Promise<void> {
  const { window, posted, errors } = await openPage(undefined);
  const document = window.document;
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
  await checkRestart();
  done(
    0,
    'Webview smoke test passed: the built dist/webview.js rendered the document into #content ' +
      'from an isolated directory, built the TOC, posted ready, showed a persisted stand before ' +
      'any render and reported its key; dist/webview.css applied.',
  );
}

/**
 * The restart path of the bundle: a persisted stand of this build (the version in package.json
 * is the `BUILD_ID` the bundle carries) must be in #content before the host has sent any
 * render, and `ready` must name it so the host can skip its render.
 */
async function checkRestart(): Promise<void> {
  const key = 'smoke-key';
  const { window, posted, errors } = await openPage({
    documentUri: 'file:///smoke.md',
    buildId: manifest.version,
    key,
    html: '<h1 id="stand" data-line="0">Persisted stand</h1>',
    scrollLine: 0,
  });
  await window.happyDOM.waitUntilComplete();
  const text = window.document.getElementById('content')?.textContent ?? '';
  if (!/Persisted stand/.test(text))
    done(
      1,
      `no persisted stand before the first render: ${JSON.stringify(text)}`,
    );
  const ready = posted.find((m) => m.type === 'ready');
  if (
    ready?.type !== 'ready' ||
    ready.buildId !== manifest.version ||
    ready.key !== key
  )
    done(1, `ready does not name the restored stand: ${JSON.stringify(ready)}`);
  if (errors.length) done(1, `page errors on restart: ${errors.join('; ')}`);
  await window.happyDOM.close();
}

main().catch((err) => done(1, `unexpected error: ${err?.stack || err}`));
