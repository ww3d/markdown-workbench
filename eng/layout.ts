// The one place every build output path comes from (bundles, packages, coverage, build
// state, logs, tools, scratch files), modeled on the ww3d/atlas output layout: one root with fixed branch
// names underneath. Moving a branch is a change here, not a search through the scripts.
//
// The root is `artifacts/` under the repository, or another folder: `--artifacts-dir` of eng/build.ts, which
// sets MARKDOWN_WORKBENCH_ARTIFACTS_DIR for itself and everything it starts, else that variable, else the
// default (Atlas: parameter > ATLAS_ARTIFACTS_DIR > Config.props > default; there is no Config.props here).
//
// Run directly (`node eng/layout.ts`) it prints the resolved layout as JSON for callers
// that cannot import TypeScript (the workflows); `node eng/layout.ts <key>`
// prints a single path.

import path from 'node:path';
import { fileURLToPath } from 'node:url';

/** Absolute path of the repository root; every relative layout entry resolves against it. */
export const repoRoot: string = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);

/** The environment variable that moves the artifacts root. */
export const artifactsDirVariable = 'MARKDOWN_WORKBENCH_ARTIFACTS_DIR';

/**
 * Output paths, relative to the repository root, for the default root. `dist` stays at the root because the
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
  /** Logs of a run: the step journal of a CI build (eng/build.ts). */
  log: 'artifacts/log',
  /** Downloaded tools the integration tests reuse between runs (the VS Code builds). */
  toolset: 'artifacts/toolset',
  /** Scratch files a run may leave behind (bench pages). */
  tmp: 'artifacts/tmp',
} as const;

/** Name of one layout entry. */
export type LayoutKey = keyof typeof relativeLayout;

/**
 * The artifacts root: the variable when set (a relative value counts from the repository root), else
 * `artifacts/` under the repository.
 *
 * @param env - The environment to read; defaults to the process's.
 */
export function artifactsRoot(env: NodeJS.ProcessEnv = process.env): string {
  const set = env[artifactsDirVariable];
  return set
    ? path.resolve(repoRoot, set)
    : path.join(repoRoot, relativeLayout.artifacts);
}

/** Absolute path of a layout entry under the given environment's root. */
export function layoutPath(
  key: LayoutKey,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const relative = relativeLayout[key];
  if (key === 'dist') return path.join(repoRoot, relative);
  // Every other entry is `artifacts/<rest>`: the first segment is the default root.
  return path.join(artifactsRoot(env), ...relative.split('/').slice(1));
}

/** Whether a string names a layout entry. */
export function isLayoutKey(key: string): key is LayoutKey {
  return Object.hasOwn(relativeLayout, key);
}

/** Every layout entry as an absolute path, keyed by entry name. */
export type Layout = Readonly<Record<LayoutKey, string>>;

/** Every layout entry as an absolute path. */
export function resolvedLayout(env: NodeJS.ProcessEnv = process.env): Layout {
  return {
    dist: layoutPath('dist', env),
    artifacts: layoutPath('artifacts', env),
    packages: layoutPath('packages', env),
    testResults: layoutPath('testResults', env),
    coverage: layoutPath('coverage', env),
    coverageTemp: layoutPath('coverageTemp', env),
    obj: layoutPath('obj', env),
    compileCache: layoutPath('compileCache', env),
    integration: layoutPath('integration', env),
    log: layoutPath('log', env),
    toolset: layoutPath('toolset', env),
    tmp: layoutPath('tmp', env),
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
