import { defineConfig } from 'tsdown';

// One self-contained CJS bundle for the VS Code extension host: all
// dependencies are inlined (node_modules is excluded from the vsix);
// only 'vscode' stays external - the host provides it.
export default defineConfig({
  entry: ['extension.js'],
  format: 'cjs',
  platform: 'node',
  deps: {
    // Inline the runtime dependencies (and their transitive graph) so the
    // vsix ships without node_modules.
    alwaysBundle: ['markdown-it', 'markdown-it-front-matter', 'shiki'],
    neverBundle: ['vscode'],
  },
  minify: true,
  outDir: 'dist',
  clean: true,
});
