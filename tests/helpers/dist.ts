// Access to the built bundles for the package tests (tests/package/): they read dist/, they
// never build it. A missing bundle stops the run with the remedy instead of testing a stale
// or empty folder.
import fs from 'node:fs';
import path from 'node:path';
import { layoutPath } from '../../eng/layout.ts';

/** The bundles every package test may assume in `dist/` after a build. */
const BUNDLES = ['extension.cjs', 'webview.js', 'webview.css'] as const;

/**
 * The absolute path of the built `dist/` folder.
 *
 * @throws When a bundle is missing, with the command that builds it.
 */
export function builtDist(): string {
  const dist = layoutPath('dist');
  for (const file of BUNDLES)
    if (!fs.existsSync(path.join(dist, file)))
      throw new Error(
        `${file} is missing in ${dist}: the package tests read the built bundles, ` +
          'run `pnpm run build` (or `./build.ps1 -Task Build`) first',
      );
  return dist;
}
