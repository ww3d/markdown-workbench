// Bundles the integration suite and the guard-driver extension before a run (tests/integration/run.ts):
// the minimum VS Code runs a Node without type stripping, and a bundle loads there no matter which
// module format its sources use. Only `vscode` stays external - the extension host provides it.
import path from 'node:path';
import { defineConfig, type UserConfig } from 'tsdown';
import { layoutPath } from '../../eng/layout.ts';

const out = layoutPath('integration');
const common: UserConfig = {
  format: 'cjs',
  platform: 'node',
  deps: { neverBundle: ['vscode'] },
  // The case files register their cases on load; package.json "sideEffects" would let the bundler drop that.
  treeshake: false,
  clean: true,
};

export default defineConfig([
  {
    ...common,
    entry: { index: path.join(import.meta.dirname, 'suite', 'index.ts') },
    outDir: path.join(out, 'suite'),
  },
  {
    ...common,
    entry: {
      extension: path.join(
        import.meta.dirname,
        'guard',
        'driver',
        'extension.ts',
      ),
    },
    outDir: path.join(out, 'driver'),
  },
]);
