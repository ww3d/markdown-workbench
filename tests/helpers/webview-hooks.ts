// Module hooks for the webview sources under Node (registered by tests/setup.ts):
//
// - A stylesheet import (`import './x.css'`) loads as an empty module: Node cannot load
//   CSS, and the modules import theirs for the bundler only.
// - `morphdom` resolves to a stand-in that calls `globalThis.morphdom` at call time, so a
//   test can swap the implementation (a spy) per test. The npm package needs a real DOM,
//   which the DOM mock is not.

import { registerHooks } from 'node:module';

const MORPHDOM_URL = 'mock:morphdom';

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === 'morphdom') {
      return { url: MORPHDOM_URL, format: 'module', shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === MORPHDOM_URL) {
      return {
        format: 'module',
        source: 'export default (...args) => globalThis.morphdom(...args);',
        shortCircuit: true,
      };
    }
    if (url.startsWith('file:') && new URL(url).pathname.endsWith('.css')) {
      return { format: 'module', source: '', shortCircuit: true };
    }
    return nextLoad(url, context);
  },
});
