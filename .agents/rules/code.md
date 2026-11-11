---
trigger: code
read-before: writing code
budgetTokens: 2650
---

Read before: writing code

## Code Conventions

- **Class size.** Guideline ~150-200 lines, hard cap 300; beyond 300 only with a justification in
  the PR body.
- **Responsibility axis**, independent of the line count: at most ~15 instance fields and one clear
  responsibility.
- **Exception.** Pure schema / DTO / config classes and stateless helpers are exempt from the line
  limit.
- **Method size.** Guideline ~30 lines; deeply nested or hard to read → split.
- **Names** speak for themselves: a name says what the thing is or does.
- A sync API stays sync and an async one async unless the caller needs the other — never switched
  just to round it off.
- **Cross-stack defaults:** nullability checks on and I/O async wherever the language offers them;
  the overlay names the construct.

## Code Comments

- **Short why**, guideline 1-3 lines. A longer rationale lives in the evidence document (decision
  log, architecture or upstream doc), and the comment points there.
- **Present state only.** Git history and the decision log carry how the code got here — no review
  rounds, finding numbers or "this used to be …". A pointer to a decision or a carrier (`TODO #N`) is
  fine.
- **Exception: upstream comments taken over verbatim** from synced or vendored code stay as they are.
- **No REQ number in code, XML docs or tests**, in new and touched code: a reference points at an
  issue or a decision log (`#N`, in another repo `owner/repo#N`).

## Folder Conventions

1. **Folders are named for the subject, never the technical role.** Default ban-list: `Services`,
   `Helpers`, `Utils`, `Models`, `Interfaces`, `Extensions`, `Common`, `Misc`, `Shared`.
2. **No sediment.** The top level of a project/module carries only what concerns the whole (entry
   point, DI/module root, manifest), hard cap **three**; everything else lives in a folder.
3. **Namespace equals path** wherever the language has namespaces.
4. **The test project mirrors in both directions:** every product folder has a same-named test
   folder, and every test folder a product counterpart.
5. **Folder size guideline**, soft, ~15 files; beyond it split, or justify in the PR body.

`eng/` holds the build entry, the build properties and the tools that build, pack or generate build
input; `scripts/` holds upkeep — syncing with a source, convention checks, setup. Without the org
build tool, build scripts live in `scripts/`.

**Exceptions to rules 1-5 live in one file per repo, never in comments:** ban-list, its exceptions
and the sediment cap together. **Every exception carries a resolution note** — a carrier reference
or `permanent`.

## Work Standard

- Grasp the full context before a design decision — docs, issues, PRs, backlogs, rejected approaches
  too — and reuse prior work; existing implementations are never rewritten from scratch unprompted.
- Every finding or piece of work that belongs to the order is built in the same PR.
  `.agents/rules/carrier.md` § "Carrier Requirement" carries the same sentence and what else holds;
  related work goes into its own commits, and the PR body lists it (`.agents/rules/pr.md` § "PR / MR
  Description").
- Cover every use case, the derived ones too; the result stays intuitive. No dead paths.
- Hot paths allocate nothing; measure, don't guess. Structured logging with no hot-path cost, and
  enough context to debug.
- Tests cover the happy path, every edge case and every error path. Async library APIs take a
  cancellation token as required.
- A test checks our own code — never a third-party library's behaviour, only our wrapper around it
  —, and its name states the expectation, not the technical how; for a complex interface a double
  that reproduces the real interface comes before an auto-mock.
- Validate packaged or bundled artifacts in the **consumer's topology**, not the repository's
  (§ "Test Isolation" for the smoke folder).
- Autonomous through to completion; self-review and refactor rounds until clean.

## Test Isolation

**A test changes nothing outside its own test folder** — a cleanup in `finally` included. Off
limits: a drive letter (`subst`, a mapped drive), the registry, a persistent environment variable at
user or machine scope, a scheduled task, any folder outside the run's folder, system temp and
`%LOCALAPPDATA%` included. A variable set in the run's own process is fine. A test whose subject is
such behavior runs against a stand-in (an interface, a fake), never against the machine.

- **The test run sets the temp folder.** Before any test starts, the repository's test entry point
  (its test script or build target) points `TMP`, `TEMP` and `TMPDIR` at the run's folder inside the
  build's output folder, default `artifacts/tmp/<run>/` under the git-ignored `artifacts/`. Where the
  repo's versioning or build tool defines the output structure, its folder wins.
- **Package smoke tests get a named folder of their own** in the same output folder, and their
  isolation comes from the lookup paths: no repository file, package cache or parent `node_modules`
  on any lookup path of the smoke run.
- Locations a tool fixes inside the repository, and toolchain caches the restore writes, are the named
  exceptions per stack (`docs/common/ci.md` § "Testordner je Stack").
- **Cleanup happens at the next start, not only at the end:** the entry point removes earlier runs'
  folders that no running process holds any more (a lock on a marker file the OS releases with the
  process).

## Tests and Time

**A test never sleeps and never waits on the real clock** — no sleep or delay, no polling loop with a
wall-clock deadline. This holds for every existing test, not only new ones (the overlay names the
tool per stack).

- **Time-dependent code takes a replaceable clock**; the test hands in its own, and time jumps
  instantly instead of passing.
- **Waiting on another thread or process** is waiting on a signal (an event, the process exit),
  never "look again after X seconds".
- **A wall-clock deadline is only the run's hang guard** — it aborts a test that hangs — and never a
  condition a test has to meet.
- **A test that must measure real time** (a performance budget, a real process start) is its own
  group: marked as such in the repo's own way, run alone and outside the normal run, never in
  parallel with other tests. Only there real time is allowed.

## Dependencies

A package the code needs is a blocking question, asked the moment the need shows, with the need
justified; who answers: `.agents/rules/pr.md` § "Controller Mode". The work on that point waits: a
substitute built meanwhile is no answer. A good reason for a package is a reason to use it;
standard-library options first. A justified dependency is pinned at the current stable version,
verified from the registry. An outdated existing dependency is named with an update proposal — never
bumped silently, never left unmentioned.

1. **Latest stable is the default;** a deviation is named with a reason and a follow-up at the pin.
2. **Pre-release only on explicit request,** in every stack; once the stable ships, the pin is due.
3. **A major jump is its own decision** — own commit, own test run, never bycatch of a sweep.
4. **One platform line, one version** — differing patch levels of one product family in a repo are a
   finding.
5. **Audit downgrades are time-boxed:** `NuGetAuditMode`, `NoWarn` on security warnings and the like
   are re-checked at every sweep and fall once their reason is gone.

A sweep **shows** currency instead of claiming it: the overlay's currency command output goes into
the PR body before and after, empty except for the named exceptions. No update bot (Renovate,
Dependabot) before the org CI runs in production.

## Build Tools

The build installs the tools it needs in the exact version pinned in the repo — through the stack's
build SDK, else the repo's build script — each version in one place: the stack's manifest, else
`tools` in `global.json`.

- User- or repo-local only, never admin or machine-wide; a way that needs admin stops with the exact
  command.
- One check-only switch: check, stop with the exact command; the same without network.
- Platform toolchains (SDK, Visual Studio, compiler) are only checked; a missing one is reported
  with the exact command.
- One log line per tool: `<name> <version> (installed|kept)`.

## Simplicity

As little code as needed; every line traces back to the order. Where you see a more modern, better
or more performant solution or an additional feature, propose it; whether it is built is the
maintainer's call. No error handling for cases that cannot occur, and a 200-line change that could
be 50 is rewritten.

- New code matches the file it lands in in naming and formatting, but takes the newest language and
  platform feature the project's baseline offers — and so does every line a change touches.
  Neighbouring formatting and pre-existing dead code are mentioned, not changed; rebuilding a whole
  file, or whatever lies beside the touched lines, is a proposal to the maintainer
  (`.agents/rules/pr.md` § "Controller Mode").
- For new code take the current, idiomatic, well-supported approach the toolchain offers: a modern
  built-in over a heavier dependency, performance from sound algorithms and structure rather than
  micro-optimization, the simplest form that does the job; reference implementations are researched
  first rather than taking the first solution that works.

## Commits and Fixes

- Feature branches only, never `main`.
- State assumptions.
- What is configurable goes cleanly into the project's settings file; which settings exist is
  settled in the design with the maintainer, and a dev session only proposes switches.
- At most three fix attempts at the same error; then stop with a diagnosis — what was tried, what
  was observed, where the suspicion lies.

## Never in Code

- Modify `.git/` directly, or add a `TODO`, `HACK` or `FIXME` without an open carrier
  (`.agents/rules/carrier.md`).
- Suppress a warning without an explanatory comment; catch an exception without logging and either
  rethrowing or handling it.

## Always

- Add tests for new public library APIs.
- Document every public surface others consume — whatever the construct — with what and why, not
  the obvious; the stack overlay names the tool. Internal code is documented only where it is not
  self-explanatory.
- Cover every silent fallback path with a test that forces the success path: when the primary path
  breaks, a test turns red.
