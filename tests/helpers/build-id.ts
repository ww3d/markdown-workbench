// The build id the bundles get from tsdown's `define` (tsdown.config.ts). The tests run the
// sources unbundled, so the free `BUILD_ID` they read resolves to this fixed global instead.

/** The fixed `BUILD_ID` of every test process. */
export const TEST_BUILD_ID = 'test-build';

Object.assign(globalThis, { BUILD_ID: TEST_BUILD_ID });
