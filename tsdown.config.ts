import { defineConfig } from 'tsdown';
import { layoutPath } from './eng/layout.ts';
import manifest from './package.json' with { type: 'json' };

// The build id both bundles carry: the webview persists it with its stand, and the host
// trusts a restored stand only from its own build (src/views/restore.ts).
const BUILD_ID = JSON.stringify(manifest.version);

export default defineConfig([
  // One self-contained CJS bundle for the VS Code extension host: all
  // dependencies are inlined (node_modules is excluded from the vsix);
  // only 'vscode' stays external - the host provides it.
  {
    entry: ['src/extension.ts'],
    format: 'cjs',
    platform: 'node',
    deps: {
      // Inline the runtime dependencies (and their transitive graph) so the
      // vsix ships without node_modules. Shiki as a regex, not a string: the
      // string only matches the bare package, leaving subpath imports like
      // 'shiki/engine/javascript' external - which then fail at runtime in the
      // installed vsix (no node_modules to resolve them).
      alwaysBundle: [
        'markdown-it',
        'markdown-it-front-matter',
        'get-east-asian-width',
        /^shiki/,
      ],
      neverBundle: ['vscode'],
    },
    define: { BUILD_ID },
    minify: true,
    outDir: layoutPath('dist'),
    clean: true,
  },
  // The webview: one browser IIFE (morphdom inlined) plus the stylesheet every
  // module imports, merged in import order into one file. getWebviewHtml loads
  // exactly these two (docs/DECISIONS.md, D1 of #92).
  {
    entry: { webview: 'src/webview/main.ts' },
    format: 'iife',
    platform: 'browser',
    minify: true,
    // Chromium 132 = Electron 34.5.1 = the Electron of the minimum VS Code (engines.vscode
    // 1.100): microsoft/vscode branch release/1.100, .npmrc `target="34.5.1"`;
    // releases.electronjs.org lists 34.5.1 with Chrome 132.0.6834.210. It applies to the
    // script and (css.target defaults to it) the stylesheet, so CSS is never lowered below it.
    target: 'chrome132',
    outDir: layoutPath('dist'),
    clean: true,
    // IIFE output is named webview.iife.js by default; the skeleton loads webview.js.
    outputOptions: { entryFileNames: '[name].js' },
    css: { fileName: 'webview.css', minify: true },
    // The fold bench's trace hook (src/webview/folding/refresh.ts) does not ship:
    // defined away here, the minifier drops its branch.
    define: { 'globalThis.__mwFoldTrace': 'undefined', BUILD_ID },
  },
]);
