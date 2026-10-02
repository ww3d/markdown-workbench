// `--clean`: deletes the build outputs - the artifacts root and `dist/` - after the ww3d/atlas `-clean`: a
// relocated root is a real way to lose unrelated data, so a root that is, holds or contains something that
// must survive is refused instead of emptied.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

/** The physical form of a path: every existing link along it resolved, the missing tail kept as written. */
export function physicalPath(target: string): string {
  const absolute = path.resolve(target);
  const missing: string[] = [];
  let current = absolute;
  for (;;) {
    try {
      return path.join(fs.realpathSync(current), ...missing.reverse());
    } catch {
      const parent = path.dirname(current);
      if (parent === current) return absolute;
      missing.push(path.basename(current));
      current = parent;
    }
  }
}

const isSameOrInside = (inner: string, outer: string): boolean => {
  const rel = path.relative(outer, inner);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
};

/** Names inside the repository root that a clean must never take along. */
const protectedInRepo = ['.git', '.tools', 'node_modules'] as const;

/**
 * Why a folder must not be cleaned, or `undefined` when it may be: it is a filesystem root, the repository
 * root or one of its ancestors, the home folder or one of its ancestors, a `.git` (or holds one), or the
 * repository's own `.tools` / `node_modules`. Every operand is resolved through links first, so a profile
 * reached through a junction does not hide its real ancestor.
 *
 * @param target - The folder a clean would delete.
 * @param repoRoot - The repository root.
 * @param homes - Home folders to protect (defaults to the user's).
 */
export function cleanHazard(
  target: string,
  repoRoot: string,
  homes: readonly string[] = [
    os.homedir(),
    process.env.USERPROFILE ?? '',
    process.env.HOME ?? '',
  ],
): string | undefined {
  const dir = physicalPath(target);
  if (dir === path.parse(dir).root) return 'it is a filesystem root';
  const repo = physicalPath(repoRoot);
  if (isSameOrInside(repo, dir))
    return 'it is the repository root or one of its ancestors';
  for (const home of homes.filter(Boolean).map(physicalPath)) {
    if (isSameOrInside(home, dir))
      return 'it is the home folder or one of its ancestors';
  }
  if (path.basename(dir) === '.git' || fs.existsSync(path.join(dir, '.git'))) {
    return 'it is, or holds, a .git';
  }
  for (const name of protectedInRepo) {
    if (isSameOrInside(path.join(repo, name), dir))
      return `it holds the repository's ${name}`;
    if (isSameOrInside(dir, path.join(repo, name)))
      return `it lies inside the repository's ${name}`;
  }
  return undefined;
}

/**
 * Deletes the artifacts root and `dist/`.
 *
 * @param artifactsDir - The resolved artifacts root.
 * @param distDir - The bundle folder.
 * @param repoRoot - The repository root.
 * @returns What was deleted, as printed paths.
 * @throws When the artifacts root is a hazard (nothing is deleted then).
 */
export function cleanOutputs(
  artifactsDir: string,
  distDir: string,
  repoRoot: string,
  homes?: readonly string[],
): readonly string[] {
  const hazard = cleanHazard(artifactsDir, repoRoot, homes);
  if (hazard) {
    throw new Error(
      `Refusing to clean '${artifactsDir}': ${hazard}. Set --artifacts-dir / MARKDOWN_WORKBENCH_ARTIFACTS_DIR to a folder under the intended output root.`,
    );
  }
  const removed: string[] = [];
  for (const dir of [artifactsDir, distDir]) {
    if (fs.existsSync(dir)) {
      fs.rmSync(dir, { recursive: true, force: true });
      removed.push(dir);
    }
  }
  return removed;
}
