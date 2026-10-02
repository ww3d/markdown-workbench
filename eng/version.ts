// The version of a package build, after the ww3d/atlas scheme (docs/versioning.md there): a SemVer2 prerelease
// label that says what kind of build made the file, so a local or CI package never passes for a release.
//
//   build                          package version        example
//   local                          <prefix>-dev           0.37.0-dev
//   CI (--ci)                      <prefix>-ci            0.37.0-ci
//   official (--official-build-id) <prefix>-preview.1.<short date>.<revision>   0.37.0-preview.1.26275.1
//   release (--release)            <prefix>               0.37.0
//
// `package.json` keeps the release version: it is the prefix, and what the Marketplace takes (it rejects
// SemVer prereleases). Only the file name and the version inside the .vsix carry the label.

/** What kind of build a package comes from. */
export type BuildKind = 'dev' | 'ci' | 'official' | 'release';

/** What the command line says about the kind of build. */
export interface KindOptions {
  readonly ci: boolean;
  readonly release: boolean;
  readonly officialBuildId?: string | undefined;
}

/** The prerelease label and iteration of official builds (Atlas: `PreReleaseVersionLabel`/`...Iteration`). */
const officialLabel = 'preview.1';

/**
 * The kind of build the options ask for: `--release` wins (it needs an official build id's date no more than
 * Atlas's `DotNetFinalVersionKind=release` does), then an official build id, then `--ci`, else a local build.
 */
export function buildKind(options: KindOptions): BuildKind {
  if (options.release) return 'release';
  if (options.officialBuildId) return 'official';
  return options.ci ? 'ci' : 'dev';
}

/** The two numbers an official build id (`yyyymmdd.r`) stands for in a package version. */
export interface OfficialBuildNumber {
  /** `yy * 1000 + mm * 50 + dd`: unique per day, ordered, and short. */
  readonly shortDate: number;
  /** The build of that day, 0 to 99. */
  readonly revision: number;
}

/**
 * Reads an official build id the way Atlas does: `20yymmdd.r`, the daily counter at most 99 (a larger one would
 * reach into the digits of the next day).
 *
 * @throws On any other shape, an impossible date or a counter above 99.
 */
export function parseOfficialBuildId(id: string): OfficialBuildNumber {
  const m = /^20(\d{2})(\d{2})(\d{2})\.(\d+)$/.exec(id);
  if (!m) {
    throw new Error(
      `The official build id '${id}' is not 'yyyymmdd.r' (e.g. 20260930.1).`,
    );
  }
  const [yy, mm, dd, revision] = [m[1], m[2], m[3], m[4]].map(Number);
  if (
    yy === undefined ||
    mm === undefined ||
    dd === undefined ||
    revision === undefined
  ) {
    throw new Error(
      `The official build id '${id}' is not 'yyyymmdd.r' (e.g. 20260930.1).`,
    );
  }
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
    throw new Error(`The official build id '${id}' names no date.`);
  }
  if (revision > 99) {
    throw new Error(
      `The daily counter of the official build id '${id}' must be between 0 and 99: a larger one would reach into the next day.`,
    );
  }
  return { shortDate: yy * 1000 + mm * 50 + dd, revision };
}

/**
 * The package version of a build.
 *
 * @param prefix - The release version, `MAJOR.MINOR.PATCH` (`package.json` `version`).
 * @param kind - The kind of build.
 * @param officialBuildId - The build id, required for `official`.
 * @throws On a prefix that is no `MAJOR.MINOR.PATCH`, or an official build without a valid id.
 */
export function packageVersion(
  prefix: string,
  kind: BuildKind,
  officialBuildId?: string,
): string {
  if (!/^\d+\.\d+\.\d+$/.test(prefix)) {
    throw new Error(
      `package.json version '${prefix}' is not MAJOR.MINOR.PATCH.`,
    );
  }
  switch (kind) {
    case 'release':
      return prefix;
    case 'official': {
      if (!officialBuildId)
        throw new Error('An official build needs an official build id.');
      const { shortDate, revision } = parseOfficialBuildId(officialBuildId);
      return `${prefix}-${officialLabel}.${shortDate}.${revision}`;
    }
    case 'ci':
      return `${prefix}-ci`;
    case 'dev':
      return `${prefix}-dev`;
  }
}
