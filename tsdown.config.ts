import { defineConfig } from 'tsdown';

// One self-contained CJS bundle for the VS Code extension host: all
// dependencies are inlined (node_modules is excluded from the vsix);
// only 'vscode' stays external - the host provides it.
export default defineConfig({
  entry: ['src/extension.js'],
  format: 'cjs',
  platform: 'node',
  deps: {
    // Inline the runtime dependencies (and their transitive graph) so the
    // vsix ships without node_modules. Shiki as a regex, not a string: the
    // string only matches the bare package, leaving subpath imports like
    // 'shiki/engine/javascript' external - which then fail at runtime in the
    // installed vsix (no node_modules to resolve them).
    alwaysBundle: ['markdown-it', 'markdown-it-front-matter', /^shiki/],
    neverBundle: ['vscode'],
  },
  minify: true,
  outDir: 'dist',
  clean: true,
});
