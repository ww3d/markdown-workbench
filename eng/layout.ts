// The one place every build output path comes from (bundles, packages, coverage, build
// state, tools, scratch files), modeled on the ww3d/atlas output layout: one root with fixed branch
// names underneath. Moving a branch is a change here, not a search through the scripts.
//
// Run directly (`node eng/layout.ts`) it prints the resolved layout as JSON for callers
// that cannot import TypeScript (eng/build.ts, the workflows); `node eng/layout.ts <key>`
// prints a single path.

import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** Absolute path of the repository root; every relative layout entry resolves against it. */
export const repoRoot: string = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);

/**
 * Output paths, relative to the repository root. `dist` stays at the root because the
 * extension manifest (`main`) and the vsix both name it; everything else lives under the
 * Atlas-style `artifacts/` root with Atlas's branch names.
 */
export const relativeLayout = {
  /** Bundled extension host and webview (tsdown `outDir`, `package.json` `main`). */
  dist: 'dist',
  /** Root of every other output. */
  artifacts: 'artifacts',
  /** Packaged `.vsix` files. */
  packages: 'artifacts/packages',
  /** Test reports: coverage (c8) and its raw V8 data. */
  testResults: 'artifacts/TestResults',
  coverage: 'artifacts/TestResults/coverage',
  coverageTemp: 'artifacts/TestResults/coverage-tmp',
  /** Intermediate build state (tsc build info). */
  obj: 'artifacts/obj',
  /** Node's compile cache for the test processes (tests/helpers/compile-cache.ts). */
  compileCache: 'artifacts/obj/compile-cache',
  /** Integration-test bundles: the suite and the staged guard-driver extension. */
  integration: 'artifacts/obj/integration',
  /** Downloaded tools the integration tests reuse between runs (the VS Code builds). */
  toolset: 'artifacts/toolset',
  /** Scratch files a run may leave behind (bench pages). */
  tmp: 'artifacts/tmp',
} as const;

/** Name of one layout entry. */
export type LayoutKey = keyof typeof relativeLayout;

/** Absolute path of a layout entry. */
export function layoutPath(key: LayoutKey): string {
  return path.join(repoRoot, relativeLayout[key]);
}

/** Whether a string names a layout entry. */
export function isLayoutKey(key: string): key is LayoutKey {
  return Object.hasOwn(relativeLayout, key);
}

/** Every layout entry as an absolute path, keyed by entry name. */
export type Layout = Readonly<Record<LayoutKey, string>>;

/** Every layout entry as an absolute path. */
export function resolvedLayout(): Layout {
  return {
    dist: layoutPath('dist'),
    artifacts: layoutPath('artifacts'),
    packages: layoutPath('packages'),
    testResults: layoutPath('testResults'),
    coverage: layoutPath('coverage'),
    coverageTemp: layoutPath('coverageTemp'),
    obj: layoutPath('obj'),
    compileCache: layoutPath('compileCache'),
    integration: layoutPath('integration'),
    toolset: layoutPath('toolset'),
    tmp: layoutPath('tmp'),
  };
}

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const key = process.argv[2];
  if (key === undefined) console.log(JSON.stringify(resolvedLayout()));
  else if (isLayoutKey(key)) console.log(layoutPath(key));
  else {
    console.error(
      `unknown layout key '${key}'; known: ${Object.keys(relativeLayout).join(', ')}`,
    );
    process.exit(2);
  }
}
