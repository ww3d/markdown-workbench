#!/usr/bin/env node
// Mandatory package fields (modeled on Atlas ATLAS0118): the Marketplace listing needs a publisher, a
// description, a license and a repository, and the license text has to ship. Checked before `vsce package`
// (eng/build.ts) so a missing value stops the build once, with every missing name, instead of one at a time.

import fs from 'node:fs';
import path from 'node:path';

/** The fields of `package.json` the check reads; anything else in the manifest is ignored. */
export interface PackageManifest {
  readonly publisher?: unknown;
  readonly description?: unknown;
  readonly license?: unknown;
  readonly repository?: unknown;
}

/** Whether a manifest value is a string with content. */
function isFilled(value: unknown): boolean {
  return typeof value === 'string' && value.trim() !== '';
}

/** The value of `key` on `value` when `value` is an object, otherwise `undefined`. */
function member(value: unknown, key: string): unknown {
  return typeof value === 'object' && value !== null
    ? Reflect.get(value, key)
    : undefined;
}

/**
 * Names of the mandatory values that are missing or blank, in a fixed order: the manifest
 * fields `publisher`, `description`, `license`, `repository.url` and `repository.type`, then the
 * file `LICENSE`. An empty result means the package may be built.
 *
 * @param manifest - The parsed `package.json`.
 * @param hasLicenseFile - Whether the `LICENSE` file exists in the repository root.
 */
export function missingPackageFields(
  manifest: PackageManifest,
  hasLicenseFile: boolean,
): string[] {
  const checks: readonly (readonly [string, boolean])[] = [
    ['publisher', isFilled(manifest.publisher)],
    ['description', isFilled(manifest.description)],
    ['license', isFilled(manifest.license)],
    ['repository.url', isFilled(member(manifest.repository, 'url'))],
    ['repository.type', isFilled(member(manifest.repository, 'type'))],
    ['LICENSE', hasLicenseFile],
  ];
  return checks.filter(([, present]) => !present).map(([name]) => name);
}

// CLI: node scripts/package-fields.ts [root]
// Reads package.json and LICENSE in `root` (default: the repository root). Exits 1 with one message
// naming every missing value, 0 when all are present.
if (import.meta.main) {
  const root = process.argv[2] ?? path.resolve(import.meta.dirname, '..');
  const manifest: PackageManifest = JSON.parse(
    fs.readFileSync(path.join(root, 'package.json'), 'utf8'),
  );
  const missing = missingPackageFields(
    manifest,
    fs.existsSync(path.join(root, 'LICENSE')),
  );
  if (missing.length > 0) {
    console.error(`Mandatory package fields missing: ${missing.join(', ')}.`);
    process.exit(1);
  }
  console.log('Mandatory package fields are present.');
}
