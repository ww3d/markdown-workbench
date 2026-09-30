// Turns on Node's on-disk compile cache for the test processes: every test file starts its
// own process, and each one re-parses the same sources and the same helper modules. The cache
// directory comes from the output layout, so a clean removes it with the other build state.
// `NODE_DISABLE_COMPILE_CACHE=1` switches it off for a measurement or a suspected stale entry.
// The unit run turns it on earlier through compile-cache.env; this covers a file run on its own.
import { enableCompileCache } from 'node:module';
import { layoutPath } from '../../eng/layout.ts';

enableCompileCache(layoutPath('compileCache'));
