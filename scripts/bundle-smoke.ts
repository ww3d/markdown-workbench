#!/usr/bin/env node
// Bundle smoke test: drives dist/extension.cjs the way the extension host
// would and asserts that Shiki highlighting actually works through the
// bundled lazy chunks. Two silent-degradation traps are guarded here, both
// invisible to the unit tests (they run against src/, not the bundle):
//
// 1. The lazy chunks and every module with a load-time side effect (the
//    fence renderer, listed under package.json "sideEffects") must survive
//    bundling; a dropped one degrades to plain code blocks without an error.
// 2. Anything the bundler cannot resolve statically (Shiki's WASM engine
//    loaded `import('shiki/wasm')`) survives as a bare specifier - it works
//    in the repo/CI because node_modules sits next to dist/, and dies only
//    in the installed vsix, which ships none.
//
// Against trap 2 the test runs the bundle from a fresh directory under
// os.tmpdir(): Node's upward node_modules search finds nothing there, which
// is exactly the installed topology. All bundled languages are rendered and
// asserted, not a sample - the engine must carry every grammar we ship.
// The script checks the behavior (colors are there), not bundler internals.
// It also aligns a CJK/emoji table through the bundled command, so the table
// width data (get-east-asian-width) must be inside the bundle too.

import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { layoutPath } from '../eng/layout.ts';
// Importing the mock also registers its module hooks: the bundle's
// require('vscode') resolves to the installed mock, nothing else is redirected.
import {
  install,
  MockDocument,
  MockEditor,
  Selection,
  type VscodeMock,
} from '../tests/helpers/vscode-mock.js';

const POLL_MS = 250;
const TIMEOUT_MS = 10000;

// Expected values written out explicitly (not derived from src/render/fence-highlight.js):
// one fence per bundled language, every one must come back highlighted.
const LANG_SNIPPETS = [
  ['powershell', 'Write-Host "hello"'],
  ['bat', 'echo hello'],
  ['shellscript', 'echo "hello"'],
  ['json', '{ "key": [1, 2] }'],
  ['jsonc', '{ "key": 1 } // comment'],
  ['yaml', 'key: value'],
  ['ini', '[section]\nkey = value'],
  ['xml', '<node attr="v"/>'],
  ['javascript', 'const x = 1;'],
  ['typescript', 'const x: number = 1;'],
  ['html', '<p class="x">hi</p>'],
  ['css', 'a { color: red; }'],
  ['markdown', '# heading'],
  ['csharp', 'var x = 1;'],
  ['python', 'x = 1'],
  ['sql', 'SELECT 1;'],
  ['diff', '+added line'],
  ['docker', 'FROM node:22'],
];

// Isolate the bundle from the repo's node_modules: copy dist/ to a temp dir
// outside the project so Node's upward search resolves nothing - the
// installed-vsix topology. That is why this directory is not in eng/layout.ts.
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-bundle-smoke-'));
fs.cpSync(layoutPath('dist'), tmpDir, { recursive: true });

function done(code: number, msg: string, html?: string): never {
  if (code !== 0) {
    console.error(`BUNDLE SMOKE TEST FAILED: ${msg}`);
    if (html)
      console.error(
        `--- last rendered html (truncated) ---\n${html.slice(0, 2000)}`,
      );
  } else {
    console.log(msg);
  }
  fs.rmSync(tmpDir, { recursive: true, force: true });
  process.exit(code);
}

async function main() {
  const vscode = install();
  vscode.window.activeColorTheme = { kind: 2 }; // dark -> dark-plus theme

  let ext: { activate?: unknown };
  try {
    // The extension host loads the CJS bundle through require, so does this.
    ext = createRequire(import.meta.url)(path.join(tmpDir, 'extension.cjs'));
  } catch (err) {
    done(1, `isolated extension.cjs failed to load: ${String(err)}`);
  }
  if (typeof ext.activate !== 'function')
    done(1, 'bundle does not export activate()');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });

  const doc = new MockDocument(
    `${LANG_SNIPPETS.map(
      ([lang, code]) => `\`\`\`${lang}\n${code}\n\`\`\``,
    ).join('\n\n')}\n`,
  );
  const messages: { type: string; html?: string }[] = [];
  let onMessage: (message: { type: string }) => void = () => {};
  const panel = {
    webview: {
      cspSource: 'vscode-webview://smoke',
      asWebviewUri: (uri: unknown) => `https://webview/${String(uri)}`,
      set options(_v: unknown) {},
      set html(_v: string) {},
      postMessage: (m: { type: string; html?: string }) => messages.push(m),
      onDidReceiveMessage: (f: typeof onMessage) => {
        onMessage = f;
        return { dispose() {} };
      },
    },
    onDidDispose: () => ({ dispose() {} }),
    onDidChangeViewState: () => ({ dispose() {} }),
  };
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  onMessage({ type: 'ready' });

  // The first render goes out before the async highlighter is ready (plain
  // fallback by design); once Shiki finishes loading, the extension re-posts
  // a render to every open view. Poll for that instead of sleeping blind.
  const deadline = Date.now() + TIMEOUT_MS;
  let html = '';
  for (;;) {
    const renders = messages.filter((m) => m.type === 'render');
    html = renders.at(-1)?.html ?? '';
    if ((html.match(/class="shiki/g) || []).length >= LANG_SNIPPETS.length)
      break;
    if (Date.now() >= deadline) break;
    await new Promise((r) => setTimeout(r, POLL_MS));
  }

  const shikiBlocks = (html.match(/class="shiki/g) || []).length;
  const fallbacks = [...html.matchAll(/class="language-([\w-]+)"/g)].map(
    (m) => m[1],
  );
  if (shikiBlocks < LANG_SNIPPETS.length || fallbacks.length) {
    done(
      1,
      'expected all ' +
        LANG_SNIPPETS.length +
        ' fences highlighted with class="shiki", ' +
        'found ' +
        shikiBlocks +
        ' after ' +
        TIMEOUT_MS +
        'ms' +
        (fallbacks.length
          ? `; plain language-* fallback for: ${fallbacks.join(', ')}`
          : '') +
        ' - shiki did not load or dropped grammars in the installed (no node_modules) topology',
      html,
    );
  }
  if (!/style="[^"]*color:/.test(html)) {
    done(
      1,
      'shiki blocks carry no inline color styles - tokens are unstyled',
      html,
    );
  }
  if (/<pre[^>]*class="shiki[^>]*style="[^"]*background/.test(html)) {
    done(
      1,
      'shiki blocks carry an inline theme background - it overrides --code-bg',
      html,
    );
  }
  await checkTableWidths(vscode);
  done(
    0,
    'Bundle smoke test passed: all ' +
      LANG_SNIPPETS.length +
      ' languages highlighted by shiki without node_modules, inline colors present, ' +
      'CJK/emoji table aligned by display width.',
  );
}

// Distribute a table with wide characters through the bundled command: the
// padding is only right when the East Asian width data made it into the bundle.
async function checkTableWidths(vscode: VscodeMock) {
  const editor = new MockEditor(
    new MockDocument('| 漢字 | 😀 |\n|---|---|\n| abcde | x |'),
    new Selection(2, 2, 2, 2),
  );
  vscode.window.activeTextEditor = editor;
  const distribute = vscode._commands['markdownWorkbench.distributeTable'];
  if (!distribute) done(1, 'the bundle registers no distributeTable command');
  await distribute();
  const want = ['| 漢字  | 😀  |', '| ----- | --- |', '| abcde | x   |'];
  const got = editor.document.lines;
  if (JSON.stringify(got) !== JSON.stringify(want))
    done(1, `table widths wrong in the bundle: ${JSON.stringify(got)}`);
}

main().catch((err) => done(1, `unexpected error: ${err?.stack || err}`));
