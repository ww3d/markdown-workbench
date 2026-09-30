import { defineConfig } from 'tsdown';
import { layoutPath } from './eng/layout.ts';

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
    outDir: layoutPath('dist'),
    clean: true,
    // IIFE output is named webview.iife.js by default; the skeleton loads webview.js.
    outputOptions: { entryFileNames: '[name].js' },
    css: { fileName: 'webview.css', minify: true },
    // The fold bench's trace hook (src/webview/folding/refresh.ts) does not ship:
    // defined away here, the minifier drops its branch.
    define: { 'globalThis.__mwFoldTrace': 'undefined' },
  },
]);
