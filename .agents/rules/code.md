---
trigger: code
read-before: writing code
budgetTokens: 4100
---

Read before: writing code

## Code Conventions

Detail per stack lives in the tech overlay; these size limits are cross-stack.

- **Class size.** Guideline ~150-200 lines, hard cap 300; beyond 300 only with a justification in
  the PR body.
- **Responsibility axis**, independent of the line count: at most ~15 instance fields and one clear
  responsibility — the real God-class catcher, which a mechanical file split does not evade.
- **Exception.** Pure schema / DTO / config classes and stateless helpers are exempt from the line
  limit — they grow by independent records, not by coupling.
- **Method size.** Guideline ~30 lines. Cognitive Complexity ~15 (C family incl. C# ~25) as the
  readability measure; Cyclomatic Complexity guideline ~10, blocked from ~25, as the testability
  measure. Deeply nested or hard to read → split.
- **Constructor.** About five parameters at most, more → a parameter object. Collaborators behind an
  interface, not a bag of `Func<>` callbacks; no circular construction.
- A sync API stays sync and an async one async unless the caller needs the other — never switched
  just to round it off.
- **Cross-stack defaults:** nullability checks on wherever the language offers them; records or
  value types for data, classes for entities with identity; timestamps in UTC. The overlay names
  the construct.

## Code Comments

`AGENTS.md` § "Always" says what gets documented; this section bounds how a comment reads.

- **Short why**, guideline 1-3 lines. A longer rationale lives in the evidence document (decision
  log, architecture or upstream doc), and the comment points there.
- **Present state only.** Git history and the decision log carry how the code got here — no review
  rounds, finding numbers or "this used to be …". A pointer to a decision or a carrier (`TODO #N`) is
  fine. A review round that lengthens a comment is the wrong fix: shorten it, or move the reasoning.
- **Line limit: 120 characters** for every line carrying a comment, indentation included; the overlay
  names the tool, otherwise the review check in `pr-poll-review` carries it.
- **Exception: upstream comments taken over verbatim** from synced or vendored code, kept comparable
  with their source — rewriting them breaks that comparison on the next sync; a comment of our own beside them follows this section.
- A suppressed warning carries the comment that explains it.

## Folder Conventions

Detail per stack lives in the tech overlay; these five rules are cross-stack.

1. **Folders are named for the subject, never the technical role.** Default ban-list: `Services`,
   `Helpers`, `Utils`, `Models`, `Interfaces`, `Extensions`, `Common`, `Misc`, `Shared`;
   `Tenancy/`, `Dispatch/`, `Status/`, `Planning/` instead. An exception costs a line in the
   exception file (below).
2. **No sediment.** The top level of a project/module carries only what concerns the whole (entry
   point, DI/module root, manifest), hard cap **three**; everything else lives in a folder.
3. **Namespace equals path** wherever the language has namespaces.
4. **The test project mirrors in both directions:** every product folder has a same-named test
   folder, and every test folder a product counterpart — a test folder without one means the code
   moved and the tests stayed, the state where a test checks the wrong thing and still passes.
5. **Folder size guideline**, soft, ~15 files; beyond it split, or justify in the PR body.

**Exceptions live in one file per repo, never in comments:** ban-list, its exceptions and the
sediment cap together, so an exception costs a visible diff line — the same mechanic as a
dependency-direction allow-matrix. **Every exception carries a
resolution note** — a carrier reference or `permanent` — so the list stays tracked. Whether the rule
applies to the existing tree or only the diff is the repo's call: a permanently red gate teaches
everyone to ignore it.

## Work Standard

The bar for finished work, beyond `AGENTS.md` § "Working Mode":

- Grasp the full context before a design decision — docs, issues, PRs, backlogs, rejected approaches
  too — and reuse prior work. Code from another repo or an earlier project is read first and
  summarized, then modernized and merged; existing implementations are assets, never rewritten from
  scratch unprompted.
- Turn a task into verifiable goals: a failing test first, then make it pass; tests green before and
  after a refactor; a multi-step plan names a verify-check per step.
- **Related work joins the pass only with proximity — the same files or the same mechanism:** in
  scope means its own commits, listed in the PR body under "Carried along"; without proximity it is
  its own PR (`.agents/rules/carrier.md` § "Carrier Requirement"), since bycatch makes PRs large and
  review waves expensive.
- Cover every use case, the derived ones too; the result stays intuitive. No dead paths.
- Hot paths allocate nothing; measure, don't guess. Structured logging with no hot-path cost, and
  enough context to debug.
- Tests cover the happy path, every edge case and every error path; a test that cannot run on a
  platform is skipped there, never omitted or replaced by other behaviour. Async library APIs take a
  cancellation token as required.
- Validate packaged or bundled artifacts in the **consumer's topology**, not the repository's: the
  repo layout can silently heal failures the shipped artifact will have (§ "Test Isolation" for the
  smoke folder).
- Autonomous through to completion; self-review and refactor rounds until clean.

## Test Isolation

**A test changes nothing outside its own test folder** — a cleanup in `finally` included, since it
never runs when the process is killed. Off limits: a drive letter (`subst`, a mapped drive), the
registry, a persistent environment variable at user or machine scope, a scheduled task, any folder
outside the run's folder, system temp and `%LOCALAPPDATA%` included. A variable set in the run's own
process is fine. A test whose subject is such behavior runs against a stand-in (an interface, a fake),
never against the machine.

- **The test run sets the temp folder.** Before any test starts, the repository's test entry point
  (its test script or build target — no test depends on the caller's environment) points `TMP`,
  `TEMP` and `TMPDIR` at the run's folder inside the build's output folder, default
  `artifacts/tmp/<run>/` under the git-ignored `artifacts/`; whatever asks the platform for a temp
  path (`Path.GetTempPath()`, Pester's `TestDrive:`, a library's scratch file) lands there. Where the
  repo's versioning or build tool defines the output structure, its folder wins.
- **Package smoke tests get a named folder of their own** in the same output folder, and their
  isolation comes from the lookup paths, not the location: no repository file, package cache or
  parent `node_modules` on any lookup path of the smoke run.
- Locations a tool fixes inside the repository, and toolchain caches the restore writes, are the named
  exceptions per stack (`docs/common/ci.md` § "Testordner je Stack"). A tool that needs a short temp
  path outside the repository (Unix socket path length) is an open question to the maintainer,
  and until it is decided such a folder is named in the repo's `CLAUDE.md` as a divergence
  (`.agents/rules/audit.md` § "Divergences From a Source").
- **Cleanup happens at the next start, not only at the end:** the entry point removes earlier runs'
  folders that no running process holds any more (a lock on a marker file the OS releases with the
  process), so an aborted run's leftovers go and a parallel run keeps its files.

## Dependencies

Ask before adding a third-party package, with the need justified; first-party and standard-library
options first. A justified dependency is pinned at the current stable version, verified from the
registry, not from memory, and named with its version in the body of the `build:` commit that
introduces it. An outdated existing dependency is named with an update proposal — never
bumped silently, never left unmentioned.

1. **Latest stable is the default;** a deviation is named with a reason and a follow-up at the pin.
2. **Pre-release only on explicit request,** in every stack; once the stable ships, the pin is due.
3. **A major jump is its own decision** — own commit, own test run, never bycatch of a sweep: a major
   can change behavior without the compiler saying so.
4. **One platform line, one version** — differing patch levels of one product family in a repo are a
   finding.
5. **Audit downgrades are time-boxed:** `NuGetAuditMode`, `NoWarn` on security warnings and the like
   are re-checked at every sweep and fall once their reason is gone.

A sweep **shows** currency instead of claiming it: the overlay's currency command output goes into
the PR body before and after, empty except for the named exceptions. No update bot (Renovate,
Dependabot) before the org CI runs in production — PRs nobody can see green train everyone to ignore
them. The per-stack currency commands live in the tech overlays.

## Product Name vs. Code Identifiers

The product name is user-visible; technical identifiers (assembly names, namespaces, folders,
binaries) are decided per project — ask before introducing concrete ones. Configuration sections and
environment-variable prefixes typically follow the product name.

## Release Notes Are Not UI Strings

A build that injects the top changelog section into a package manifest carries it into a format older,
non-UTF-8-defaulting hosts read (a `.psd1` without BOM is read in the ANSI codepage by Windows
PowerShell 5.1), where every non-ASCII byte becomes mojibake. The BOM-less manifest pipeline is the
reference; a per-repo BOM override only hides the breach. A repo publishing such a manifest carries a
build check that hard-rejects non-ASCII in the injected section — mandatory, its form the repo's call.

## Simplicity in Detail

- Minimum code that solves the problem — no features, abstractions, configurability or error
  handling for hypotheticals. A 200-line change that could be 50 is rewritten.
- Code the change touches is made modern, and so is whatever turns up beside, before or after it;
  only a new feature or a change of direction is a proposal to the maintainer
  (`.agents/rules/pr.md` § "Controller Mode").
- Every changed line traces to the request or is listed under "Carried along".
- For new code take the current, idiomatic, well-supported approach the toolchain offers: a modern
  built-in over a heavier dependency, performance from sound algorithms and structure rather than
  micro-optimization, the simplest form that does the job.
