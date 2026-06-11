#!/usr/bin/env node
// Bundle smoke test: drives dist/extension.cjs the way the extension host
// would and asserts that Shiki highlighting actually works through the
// bundled lazy chunks. Rolldown code-splits Shiki's languages/themes into
// chunks that load at highlighter init; if the entry breaks the cross-chunk
// runtime (e.g. by reassigning module.exports), initHighlighter swallows the
// load error and silently falls back to plain code blocks - unit tests never
// see it because they run against src/, not the bundle. This script checks
// the behavior (colors are there), not bundler internals.
'use strict';

const path = require('path');
const { install, MockDocument } = require(
  path.resolve(__dirname, '..', 'tests', 'helpers', 'vscode-mock'));

const DIST = path.resolve(__dirname, '..', 'dist', 'extension.cjs');
const POLL_MS = 250;
const TIMEOUT_MS = 10000;

function fail(msg, html) {
  console.error('BUNDLE SMOKE TEST FAILED: ' + msg);
  if (html) console.error('--- last rendered html ---\n' + html);
  process.exit(1);
}

async function main() {
  const vscode = install();
  vscode.window.activeColorTheme = { kind: 2 }; // dark -> dark-plus theme

  let ext;
  try {
    ext = require(DIST);
  } catch (err) {
    fail('dist/extension.cjs failed to load: ' + err.message);
  }
  if (typeof ext.activate !== 'function') fail('bundle does not export activate()');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });

  const doc = new MockDocument(
    '```powershell\nWrite-Host "hello"\n```\n\n```json\n{ "key": [1, 2] }\n```\n');
  const panel = {
    messages: [],
    webview: {
      cspSource: 'vscode-webview://smoke',
      asWebviewUri: (uri) => 'https://webview/' + String(uri),
      set options(v) {},
      set html(v) {},
      postMessage: (m) => panel.messages.push(m),
      onDidReceiveMessage: (f) => { panel._onMsg = f; return { dispose() {} }; }
    },
    onDidDispose: () => ({ dispose() {} }),
    onDidChangeViewState: () => ({ dispose() {} })
  };
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  panel._onMsg({ type: 'ready' });

  // The first render goes out before the async highlighter is ready (plain
  // fallback by design); once Shiki finishes loading, the extension re-posts
  // a render to every open view. Poll for that instead of sleeping blind.
  const deadline = Date.now() + TIMEOUT_MS;
  let html = '';
  for (;;) {
    const renders = panel.messages.filter((m) => m.type === 'render');
    html = renders.length ? renders[renders.length - 1].html : '';
    if ((html.match(/class="shiki/g) || []).length >= 2) break;
    if (Date.now() >= deadline) break;
    await new Promise((r) => setTimeout(r, POLL_MS));
  }

  const shikiBlocks = (html.match(/class="shiki/g) || []).length;
  if (shikiBlocks < 2) {
    fail('expected both fences (powershell, json) highlighted with class="shiki", '
      + 'found ' + shikiBlocks + ' after ' + TIMEOUT_MS + 'ms - the shiki lazy chunks '
      + 'did not load (highlighter fell back to plain code blocks)', html);
  }
  if (!/style="[^"]*color:/.test(html)) {
    fail('shiki blocks carry no inline color styles - tokens are unstyled', html);
  }
  if (/class="language-(powershell|json)"/.test(html)) {
    fail('plain language-* fallback rendered instead of shiki output', html);
  }
  console.log('Bundle smoke test passed: both fences highlighted by shiki, inline colors present.');
  process.exit(0);
}

main().catch((err) => fail('unexpected error: ' + ((err && err.stack) || err)));
