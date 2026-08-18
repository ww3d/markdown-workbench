# Agent Rules — Shared Playbook

Read on every session. Imported by each consuming repo's `CLAUDE.md` via `@AGENTS.md`. Tech overlays
(e.g. `tech/common/dotnet.md`) are imported separately when the project adopts that stack.

Below the import block, the consuming `CLAUDE.md` adds project-specific material — Project
Context, Architecture Principles, Project-Specific Overrides.

## Product Name vs. Code Identifiers

The product name is user-visible. Technical identifiers (assembly names, namespaces, folders,
binaries) are decided per project — ask before introducing concrete code-level names.
Configuration sections and environment-variable prefixes typically follow the product name.

## Language

- **English**: code, comments, identifiers, commit titles (Conventional Commits), branch names,
  PR / issue titles.
- **German**: PR / issue / review descriptions and comments, `docs/*.md`, design discussions,
  changelogs — the changelog assignment is confirmed as it stands, not moved to English.
- Either: commit-message bodies.
- **Umlauts**: transliterate German umlauts in repository text (`ae` / `oe` / `ue` / `ss`).
  Exception: user-visible UI strings keep their native umlauts. **Changelogs have no exception** —
  strict ASCII, transliterated, because their top section is injected into built package manifests
  (see below).
- **UTF-8 punctuation and symbols** (em dash `—`, arrows `→`, ellipsis `…`, `≥`, typographic
  quotes) are fine in prose — docs, PR / issue / review bodies, comments, changelogs.
  Identifiers, file / branch / package names, and commit titles stay strict ASCII.
- **Reference identifiers** pointing at German documents (`Scheibe-N Decision M`, `Grundsatz N`,
  `Entscheidung N`) are quoted verbatim, never translated — a translated reference does not find
  its target. The exception covers the identifier only; the comment carrying it stays English.
- Never mix languages within a single comment.

**Release notes are not UI strings.** A build that injects the top changelog section into a package
manifest carries it into a format read by older, non-UTF-8-defaulting hosts (a `.psd1` without BOM
is read as the ANSI codepage by Windows PowerShell 5.1), where every non-ASCII byte becomes
mojibake. The BOM-less manifest pipeline is the reference; a per-repo BOM override is not the fix,
it only hides the convention breach. Repos that publish such a manifest carry a build check that
hard-rejects non-ASCII in the injected release-notes section — the check is mandatory, its concrete
form is the consuming repo's call.

## Scope

- Edit only files inside the repository. Never touch `bin/`, `obj/`, `dist/`, `_build/`,
  `_buildtools/`, `eng/`, `node_modules/`, `.git/`, or anything above the project root.
- Never run release, publish, or push commands without approval.
- Never force-push to any branch other than your own feature branch.

## Dependencies

Ask before adding any third-party package to a project manifest. Justify the need. Prefer
first-party and standard-library options. When a dependency is justified, pin the current stable
version — verify it from the registry rather than memory, since training-cutoff versions are
usually stale. If an existing dependency is outdated, say so and propose the update; never bump
it silently (updates can break) nor leave it unmentioned.

## Working Mode

- Work on feature branches, never directly on `main`.
- One commit = one sentence you can describe. PRs above ~150 changed lines are decomposed into
  ≥3 commits, even when squash-merged.
- Conventional Commits. English title, imperative, lowercase after the type colon, no period,
  max ~72 characters. Body explains **why**, in full sentences.
- Run the full local build and tests before every commit. Red builds do not get committed.
- Sketch the approach for large changes before writing code. Don't rewrite working code unprompted.
- State assumptions explicitly. If multiple interpretations exist, present them — don't pick
  silently. Surface tradeoffs and simpler alternatives. Push back when warranted.
- Never guess or invent. Research first via the forge CLI or the web; if it stays unclear,
  ask rather than assume. If nothing resolves it, say "unknown" plainly — don't paraphrase around it.
- Parallelize with sub-agents wherever it speeds the task up. When you dispatch one:
  - Hand work over as files, not pasted prose: write the task brief to a file, pass its path,
    have the sub-agent write its result to a file, take back only status + commits + a one-line
    test summary. Pasted context stays in your window every later turn.
  - For multi-step runs keep a git-ignored ledger (`.agent/progress.md`), one line per finished
    task (`Task N: done <base7>..<head7>, review clean`). After a context reset trust the ledger
    and `git log`, not memory — never re-run a task it marks done.
  - Pick the cheapest model that fits the sub-task and name it explicitly; an omitted model
    inherits the expensive session default. (Only where the harness exposes model choice.)
- Before acting, check whether a skill covers the task; if one does, follow it rather than
  improvising.
- Translate tasks into verifiable goals: write a failing test, then make it pass; ensure tests
  pass before and after a refactor. For multi-step work, state a brief plan with verify-checks
  per step.
- Ask only for design or otherwise consequential decisions (architecture choices, irreversible
  changes, scope expansion). Routine session work — toolchain install, `PATH`, dependency
  fetch, build, test — runs without asking.
- Subscribe silently (`subscribe_pr_activity` — deferred, load via
  `select:mcp__github__subscribe_pr_activity` first; see PR Lifecycle step 3) to every PR cc is
  actively involved in — as author (its own PR) or as reviewer (someone else's PR under review) —
  regardless of how it got there: PR lifecycle, reviewer role, or a skill / tooling PR. Never ask
  first.
- Routine actions are done, not offered. Drop the conversation-extending closing "shall I … ?"
  about a routine step — execute it instead of proposing it at the turn's end.

## Session Start: Read Before Anything Else

Truth is the repo at the head of the branch under work (`main` where there is none) — never the
prompt, never memory. With a working copy that head is the local `HEAD`; without one it is the
remote head, read via the GitHub MCP or `gh`. A session with no checkout still reads the head — it
does not fall back to the prompt.

1. **Mandatory** — read in full, receipt each file with its blob SHA (format:
   `role | path | blob SHA | read / not found`): `AGENTS.md`, `CLAUDE.md`, then search the repo
   for and read: the roadmap, the architecture document, the backlog, the latest state audit,
   the decision-log index. Only after an unsuccessful search may a role be reported as
   "not found" — never skip one silently.
2. **Index** — capture the remaining doc files — `docs/**` plus the Markdown files in the
   repository root — as a list (path + purpose). Exempt: `docs/overview/` — visualizations for
   humans, not agent reading.
3. **On demand** — when the task touches a document, a decision log, an issue, or a dependency /
   reference repo (e.g. the courier docs in `win-util`, Filer as the model template), read that
   source **in full before** deciding or asserting anything about it. Decision logs of the
   running phase: always.

**Every generated artifact carries only verified state the repo cannot provide** (decisions of the
round, cleared-up misconceptions, constellation) — never rules, conventions, or doc summaries: a
rule copy is how the original gets softened. This holds for all of them, by name: task prompt,
review prompt, decision log, handoff, task spec file. The rule stands here once; the skills and the
decision-log skeleton point at it instead of repeating it. Read first, then act.

## Session Receipt

At session start, acknowledge what you have read as three groups — `Konventionen`, `Profil`,
`Memory` — one line per file under each group header, an `OK` closing each group. The
`read-confirm.sh` SessionStart hook injects this receipt automatically (`/read-check` reproduces it
on demand); report the playbook version from `.playbook-version`. Mark what an environment cannot
see as `— (nicht verfuegbar in dieser Umgebung)`, never omit it. Keep it terse.

The hook receipt reports file presence only — it does not replace the blob-SHA read receipt from
§ "Session Start: Read Before Anything Else"; that one is given in addition.

**The receipt is gated, not merely expected.** The `require-receipt.sh` Stop hook refuses to let a
turn end until the receipt has been emitted. Both hooks are synced from the playbook, but the
registration that runs them lives in the repo's own `.claude/settings.json` — where that entry is
missing, neither fires and the rule rests on discipline alone.

## Session End: Carry What Is Still Open

Before the session ends, walk it backwards once: every point that is still open and stands nowhere
goes to a valid carrier first (§ "Carrier Requirement"). Decisions with no log entry, cleared-up
misconceptions, deferred points, running orders — a point that lives only in the transcript dies
with it. This is the counterpart to the read mandate above, and unlike the carrier gate in a review
it does not depend on a PR existing.

## Simplicity

- Minimum code that solves the problem. No features, abstractions, configurability, or error
  handling for hypotheticals beyond what was asked.
- Match existing style. Don't refactor adjacent code, fix neighboring formatting, or delete
  pre-existing dead code — mention it instead and let the user decide.
- Every changed line should trace directly to the user's request. If a 200-line change could be
  50, rewrite it.
- For new code and design choices, take the current, idiomatic, well-supported approach the
  toolchain offers (SOTA — state-of-the-art): a modern built-in over a heavier dependency,
  performant by sound algorithmic and structural choice rather than premature
  micro-optimization, in the simplest form that still does the job. Modern where you're
  choosing, existing style where you're touching — don't rewrite working code, re-optimize, or add
  a feature unprompted. Where you see the case for a more modern option, a better approach or an
  extra feature, **propose it**; building it is the user's call, not yours.

## Documentation

Every doc change keeps the docs short, clear, factual: cut redundancy, filler, and detours — never
lose knowledge or clarity. Prefer terse and unambiguous over exhaustive.

**A PR pulls only the doc places its own diff would otherwise make wrong** — a statement the cut
renders untrue. Everything else goes as a line to `backlog.md`; that file is a valid carrier
(§ "Carrier Requirement"), so nothing is lost. Where the repo has no `backlog.md` yet, the PR
contributing the first line creates it. The catch-up runs bundled, once per slice, at the state
audit that runs before every slice anyway (§ "State Audit") — without that, the lines are a dump
instead of a carrier. In doubt, pull it in the same PR.

**A doc-only PR gets no review gate.** Where a diff touches exclusively `docs/**` and `*.md` in the
repository root — no code, no workflow, **no skills**, no `VERSION` — green CI is enough and the PR
may be merged without waiting for a review; a review may follow afterwards. Everything else runs
the full lifecycle unchanged. The skills are named explicitly because they are the ruleset the
agents execute, not prose about it: a wrong sentence in `docs/` breaks nothing, a wrong sentence in
a skill changes what every agent does.

Markdown or prompt blocks that themselves contain triple-backtick code fences get a four-backtick
outer fence — everywhere: chat output, issue/PR bodies, docs. A triple outer fence is closed
prematurely by the first nested block.

## Target vs. Actual

- An architecture / baseline doc is the target state, not the actual state. Never assert actual
  state in prose.
- Every baseline statement carries a status marker: `[erfuellt]` / `[teilweise]` / `[geplant]`.
- The marker points at its evidence: the architecture test where one exists, otherwise the latest
  state audit. `[erfuellt]` without evidence is not allowed.
- **A marker is a display, not a carrier.** It says "this sentence is the target, not reality" at
  the place the sentence stands — which no issue can do. It does not say what exactly is missing or
  who is on it, which no marker can do. The state audit connects the two: it carries every
  `[geplant]` / `[teilweise]` point into the tracking issue (§ "Tracking Issue", § "State Audit").

## Evidence Requirement

- **Evidence is owed only for what the reader cannot see in the diff** — test runs, benchmarks,
  "not verified". What stands in the diff is proven by the diff and needs no anchor; a second prose
  description of the same change is only a place for the two to drift apart. Where evidence *is*
  owed, the rest of this section defines its form.
- No claim of "built / done / verified / green / fast" without a **stable anchor**. Repo-internal
  anchors come first: a test / `It` name, a function or symbol name, a variable name, a comment
  heading, a relative path. They are found at the head with `git grep` and survive squash, branch
  deletion, migration and a change of forge.
- A permalink pinned to a commit SHA only where nothing repo-internal exists — and then knowingly
  as a perishable anchor: it depends on the forge keeping the object. A migration does not carry
  the PR refs along, and the commits behind them stop resolving.
- **A link into a branch ref is never evidence.** It dies with the branch, and the branch is
  deleted on merge.
- A bare `file:line` relative to a moving branch head is **not** evidence: every push in the review
  cycle shifts the line, and the reviewer then checks the wrong code. `file:line` stays valid where
  the reference point is fixed — as part of a SHA permalink, or in a state audit that names
  its commit.
- **Anchor quick reference.** Valid: `TestName`, `MethodName`, `src/Foo.cs` as a path;
  `https://github.com/<owner>/<repo>/blob/<sha>/src/Foo.cs#L142` where nothing else exists.
  Invalid: `Foo.cs:142`, and any link into a branch
  (`.../blob/<branch>/...`, `.../tree/<branch>/...`).
- **Form is not existence — the anchor is resolved, not just read.** An anchor can be formally
  flawless and point at nothing. File names go against `git ls-files`, symbol and test names against
  `git grep`, both **at the commit state**, never in the working tree: a file that ran but was never
  committed carries no repeatable test, however correctly its name is spelled. The form check alone
  produces a feeling of thoroughness and catches none of this class.
- **No factual claim from a single source.** Hold every one against all three: target (the docs),
  actual (the code), and why (decision logs, issues, PRs). Two of them agreeing against the third
  is the finding, not a rounding error.
- Whatever did not really run (missing Docker / CLI / CI / hardware) is declared "not verified"
  explicitly, never glossed over.
- **A negative claim needs a contrasting case.** "X happens nowhere", "that no longer runs" — name
  a case where it does happen, or the check that would have shown it. Without one the claim is only
  the original observation in larger type.
- **The contrasting case is documented with its hit count.** A contrast that returns 0 as well
  relieves nothing — it shows a broken measurement, and "0 hits" out of one is a correct conclusion
  from an unusable search. Encoding, quoting and the pipeline the search ran through all break it
  silently; the second number is what makes the first one readable.
- **Check the place, not the count.** A search does not distinguish an occurrence from a quotation.
  In a document that answers its own findings, the answer list carries the old wording on purpose,
  as proof of the correction — so a hit counts as an occurrence only once it has been read at its
  place and does not stand in that answer list. Correcting a statement that was right is worse than
  leaving the search unrun.
- Performance claims need a benchmark reference.

## Tracking Issue

**One design = one decision log = one tracking issue** — independent of how many PRs the design
takes. It is created **always**, even when no point stays open, and closed after the merge.

- **All open points of the design stand in the tracking issue's body** — not in a PR body, not in
  comments, not spread over several carriers. Deferring a point means editing that body. A comment
  stream is not a work list: nobody reads one back as the list of what is left.
- **Both directions, or the body lies.** Deferring a point writes it in; **delivering one ticks it
  off, in the same PR that delivers it**. The body is not a plan, it is the live answer to "what is
  still open" — an unticked point that shipped is indistinguishable from one that did not, and the
  next design round reads the body and commissions it again. The spec file ticks the `REQ`; the
  issue body ticks the point. Both, never only one.
- **Who creates it, and when:** the design round does, before the first task prompt exists, in the
  same move as the decision log (`ccweb-prompt`, step 1). Created only at the first PR, there would
  be a window between design close and first PR with no carrier at all.
- **It carries the label `tracking`.** That is what makes it findable by machine — the state audit
  reads the open points out of every issue with that label. A title convention alone carries no
  filter, and a source that silently returns nothing is indistinguishable from "nothing open",
  which is the failure class this whole rule stands against.
- **The unconditionality is deliberate.** A rule with an exception ("only when more than one PR, or
  when a point stays open") introduces a judgement call, and judgement calls are where points get
  lost. An empty tracking issue costs thirty seconds.
- **`Closes #N` on a tracking issue only where that issue's body carries no open point left.**
  The keyword closes on merge and checks nothing on its way; a closed carrier is the worst carrier
  there is, because it looks like a finished one (§ "Carrier Requirement"). While a point stands
  open, the PR names the issue without a closing keyword, and it is closed by hand after the merge
  (see the next bullet for who). This holds for `Fixes #N` and `Resolves #N` alike, and it is the
  one place where the auto-close footer from § "PR / MR Description" is conditional.
- **Who closes it, and in which order: the `reviewer` first, the `maintainer` as fallback.** After
  the merge the `reviewer` closes the tracking issue, once **both** hold: its body carries no open
  point left, and the check from § "Carrier Requirement" has run ("before closing an issue, check
  what points to it"). If the body still carries points, the issue **stays open** — a point is
  moved only because it no longer belongs to this design, never to make the issue closable. Where
  the `reviewer` cannot, it falls to the `maintainer`. The rank is named on purpose: two
  responsible parties without an order is a judgement call, and this section exists because
  judgement calls are where points get lost. The `reviewer` goes first for a mechanical reason —
  the gate already had them read that body fresh at the head. The **merge** stays `maintainer`-only.
- **The review checks two things instead of N:** does the tracking issue exist and is it open, do
  the points this PR defers stand in it — and, where the PR carries a closing keyword for it, is
  its body free of open points (`pr-poll-review`, Phase 4).

## Carrier Requirement

A **carrier** is the place a deferred point is written down so it can be found again. Every point a
PR consciously leaves open needs one **before the PR gets a positive closing verdict** — an
approval, a "looks mergeable" comment or a sentence in chat all count, whatever the channel. See
also `pr-poll-review`, Phase 4, the carrier gate.

- **Valid carriers, and only these two:** the design's open **tracking issue** (§ "Tracking Issue");
  a line in `roadmap.md` or `backlog.md`. What both share is that someone goes through them again —
  the state audit walks them before every slice.
- **A missing `backlog.md` is never a reason to leave a point uncarried.** Where the repo has none
  yet, the PR contributing the first line creates it (§ "Documentation"). The clause is repeated
  here because this is the section someone reads while deferring a point, and the other one is the
  section they read while writing docs.
- **Not carriers:** the PR body, a review comment, an issue comment, a chat — **nor a decision
  log**, **nor the task spec file** (§ "Task Spec"). A merged PR body is an archive nobody reads
  back; a decision log is the record of one day, read for the why, never as a list of what is left;
  a spec file is opened again by nobody after the merge, and its finished items make the whole file
  look finished. An obligation held in a log gets a tracking-issue line or a backlog line in
  addition. Naming a point is not carrying it.
- **A `[geplant]` / `[teilweise]` marker is not a carrier either** — it is a target-vs-actual
  display at the place of the statement (§ "Target vs. Actual"). It used to be the third entry in
  the list above; the state audit now carries every marked point into the tracking issue, which is
  the one place a point can be counted. This revises decision N1 of the carrier round of 2026-08-06
  (`docs/decisions/2026-08-06T1930-playbook-traeger-pflicht-decisions.md`), which had put the
  markers into the list deliberately.
- **A carrier issue must be open.** A closed one is the worst carrier there is: it looks like a
  finished one. Roadmap / backlog lines hold no state — they count until the point is struck
  through.
- **Who writes it:** the dev, in the same PR. Only where the PR touches none of those files does
  the reviewer file it instead.
- **Handing a point to a future slice counts only once it stands at the destination** — that
  slice's tracking issue or its `roadmap.md` line. A sentence in the sender's PR body is a note to
  nobody: the receiver reads its own issue, not foreign PR bodies. If the destination does not
  exist yet, the point goes to `backlog.md`, never to a slice nobody has heard of.
- **Before closing an issue, check what points to it.** Any point naming it as its carrier is moved
  to another carrier first, or explicitly recorded as resolved with it. A `Closes #N` in a PR body
  closes without ever running that check, which is why the keyword is conditional on a tracking
  issue (§ "Tracking Issue").
- **No marker without a number.** A `TODO`, `HACK`, or `FIXME` — in code or in the prose of a
  source-of-truth document — carries a reference to an open carrier. Where the caveat qualifies a
  statement in a source-of-truth document, it belongs **on that statement**, not in a follow-up
  document.
- **A `nitpick:` is not an open point** (§ "Review Comments"). It blocks nothing and gets no
  carrier — it is fixed or dropped.

Known gap: nothing enforces the closing rule mechanically. The periodic sweep over all carrier
links is tracked in `ww3d/playbook#158` and still waits for `iris.ci`. Points deferred before this
rule existed are no longer part of that gap: the state audit walks the tracking issues and the
markers before every slice (§ "State Audit"), which is what the sweep was deferred for.

## Review Comments

Review points use **Conventional Comments** — the labels and the `(blocking)` / `(non-blocking)`
decorations, verbatim as the specification defines them. The labels stay English even in a German
review body (§ "Language": reference identifiers are quoted, not translated).

| Label | When |
|---|---|
| `issue: (blocking)` | a clear defect with an unambiguous correction |
| `nitpick: (non-blocking)` | polish, wording, style |
| `question: (blocking)` | the maintainer has to decide: scope, deviation from the source, breaking change, naming, posting something outward |
| `question: (non-blocking)` | the reviewer's comprehension question |
| `suggestion: (non-blocking)` | an alternative the author may take or leave |

The dividing line is not importance but **who has to answer**.

- **A `nitpick:` never blocks** — neither the closing verdict nor the merge — and needs no carrier.
- **Every `nitpick:` is posted as a suggested change**, not as prose. A nit that cannot be phrased
  as a suggestion is not one: then it is an `issue:` or a `suggestion:`.
- **Approval standard:** approve as soon as the PR clearly improves the state — not only once
  there is nothing left to find.
- **Out of scope does not block.** A concern about code outside the PR's scope becomes a separate
  task and does not hold up the running PR; it goes to the tracking issue or to `backlog.md`.
- **A finding whose fix moves what the architecture document governs is not decided on the way.** It
  goes to the maintainer as a `question: (blocking)` — also where it would be declared in the PR
  body, and also where the fix is obviously right. An entry in a PR body is a report, not a
  decision: nobody has to answer it, and the document it contradicts does not move because a PR
  mentioned it. This covers the case the rules were missing, the finding from your **own** review
  wave — "autonomous through to completion" (§ "Work Standard") ends at a statement someone else
  owns. **It applies only where the architecture document governs the affected statement.** A fix
  inside what the architecture leaves open runs through autonomously; the distinction is checkable
  at the document, not by feel.

## State Audit

- Before every new slice / phase, audit against the baseline doc: each statement checked against
  the code (`file:line`), the build, and the test actually run. `file:line` is the right form here:
  the audit names the commit it was taken at, which fixes the reference point the way a permalink
  does.
- **The audit also walks the tracking issues**, in both directions: a `[geplant]` / `[teilweise]`
  marker with no point in a tracking issue, and a point in a tracking issue with no marker or line
  behind it, are both findings.
- **The trigger is mechanically checkable:** a **new tracking issue** makes the audit due. Further
  PRs on the same tracking issue do not. Checked over the file stamp of
  `audit/ist-stand-<YYYY-MM-DDTHHMM>.md` against the close of the preceding design.
- Record the result as `audit/ist-stand-<YYYY-MM-DDTHHMM>.md` on its own branch
  (§ "Timestamps in File Names"). Mechanics: the `state-audit` skill.
- The audit is also where the deferred documentation catch-up in `backlog.md` is worked off
  (§ "Documentation").

## Code Conventions

Detail per stack lives in the tech overlay; these size limits are cross-stack.

- **Class size.** Guideline ~150-200 lines, hard cap 300. Beyond 300 only with a justification in
  the PR body, otherwise blocked.
- **Responsibility axis** (independent of the line count). Blocked also above ~15 instance fields
  or more than one clear responsibility — this is the real God-class catcher; a mechanical file
  split does not evade it.
- **Exception.** Pure schema / DTO / config classes and stateless helpers are exempt from the line
  limit — they grow through the number of independent records, not through coupling.
- **Method size.** Guideline ~30 lines. Two complexity measures: Cognitive Complexity ~15
  (C family incl. C# ~25) as the readability measure (punishes nesting); Cyclomatic Complexity
  guideline ~10, blocked from ~25, as the testability measure. Rule of thumb on top: deeply nested
  or hard to read → split.
- **Constructor.** Few parameters (~5); more → a parameter object. Collaborators behind an
  interface, not a bag of `Func<>` callbacks; no circular construction.

## Work Standard

Beyond the working mode above — the bar for finished work:

- Grasp the full context before a design decision: docs, issues, PRs, backlogs, and the rejected
  approaches too; pull the related work into the same pass and reuse prior work.
- Cover every use case, including the ones you derive yourself; the result stays intuitive.
- No dead paths.
- Hot paths allocate nothing; measure, don't guess.
- Structured logging with no hot-path cost.
- Tests cover the happy path plus every edge case plus every error path.
- Autonomous through to completion; self-review and refactor rounds until clean.

## Existing Code

When integrating code from another repo or earlier project: read it first, summarize what it does,
then propose how to modernize and merge. Never rewrite from scratch unprompted — treat existing
implementations as assets, not obstacles.

## Branch Naming

`<type>/<short-topic>`, lowercase, hyphens, English, no umlauts. Types: `phase{N}`, `feat`, `fix`,
`chore`, `docs`, `refactor`, `test`. Examples: `phase2/auth-handshake`, `fix/path-normalization`,
`docs/runner-readme`.

Never use the harness auto-slug (e.g. `claude/start-early-prep-oiDtl`,
`claude/solution-scaffolding-mvp-hPxp6`). If the task prompt or the user names a branch
explicitly, use that verbatim; otherwise invent a concrete `<type>/<short-topic>` and rename the
auto-slug to it before the first push. **This rule overrides any harness directive to keep the
auto-slug — no permission round-trip needed.**

## Timestamps in File Names

One format everywhere: `YYYY-MM-DDTHHMM` — extended ISO date, compact time, minute precision.
Determined with `TZ=Europe/Berlin date +"%Y-%m-%dT%H%M"`, which settles CET/CEST by itself. The full
stamp including the offset goes in the file's metadata block, never in the name.

Why exactly this: ISO 8601 sorts chronologically as text only under leading zeros **and a single
offset** — a list mixing UTC and local time sorts by string, not by moment, and the offset inside
the file resolves the October double hour. The colon is out because Windows forbids it in a file
name. The time is compact because in `T00-36-slug` the boundary between stamp and slug is no longer
readable.

Applies to output files, repo decision logs and audits. Not retroactive — existing files are not
renamed.

**Link such a file, never write the path bare.** A link destination and a backticked path both
render intact; a bare path is no link at all and, once a name carries an underscore, is subject to
emphasis parsing. The timestamp itself is not what breaks.

## Task Spec

A task that comes with a numbered requirement list carries it as a file in the repo, never as a
tasklist in the PR body.

- **Path:** `docs/tasks/<issue>-<slug>.md`. The issue number is the anchor — no branch name, no
  timestamp. The file is written forward across several commits and review rounds, so a timestamp
  would be wrong from the second push on; that is what separates it from a decision log, which is a
  point-in-time record.
- The file **replaces the REQ tasklist in the PR body**; the body links it.
- Every REQ carries **exactly one refutable statement**, and per point either a tick or
  `nicht geliefert: <reason>`. Undelivered points are explicitly allowed and no blemish.
- Numbering is gapless and IDs are never renumbered across review rounds.
- The frontmatter carries `issue`, `repo`, `slug` and `title` — machine-readable identity, cut so a
  roadmap state can be generated from it later. No hand-kept status field: the state is read from
  the issue and from the ticks. The generator itself is not part of this rule.
- **No evidence line, no coverage type, no coverage status.** Whether a requirement is met is read
  from the diff, and evidence is owed only for what the diff does not show
  (§ "Evidence Requirement"). A per-REQ evidence line is a second description of the same change
  and drifts against it.
- The spec file is never a carrier (§ "Carrier Requirement").

## PR / MR Description

Title is a Conventional-Commit title in English. Description in German with these five headings, in
order:

1. **Was**
2. **Was bewusst nicht geaendert wurde**
3. **Entscheidungen**
4. **Wie getestet**
5. **Offene Fragen**

The numbered REQ list is not part of the body — it lives in the task spec file (§ "Task Spec"),
which the body links.

Evidence is required only for what the reviewer cannot see in the diff: test runs, benchmarks,
"not verified". What stands in the diff is proven by the diff. Where evidence is required, it
carries a stable anchor as defined in § "Evidence Requirement".

**No diff quantities in the body** — no line, file, test, or function counts over the diff. GitHub
shows those itself and always current; a hand-kept copy is only a place to get it wrong.
Test-run results (`612 passed, 0 failed`) are not diff quantities and stay.

Under "Offene Fragen", "Observations" and "Bewusst nicht", each point is a link to its carrier
(§ "Carrier Requirement") and nothing else — the point is written out at the carrier, not a second
time here. A plain environment finding — a blocked CLI, a flaky sandbox, missing hardware — is not
an open question and needs no carrier: it goes under "Wie getestet" as "not verified".

A force-push on your own feature branch is announced and justified in the body. It changes every
SHA from the rewritten commit on, which makes the reviewer's delta diff since the last reviewed
state worthless — they have to know they must read the affected commits in full again.

To auto-close an issue on merge, add an English closing line to the German description — `Closes #N`
(also `Fixes #N` / `Resolves #N`), one keyword per issue. German verbs (`Behebt`, `Schliesst`) never
trigger GitHub's auto-close; the English keyword is the only way to combine it with the
German-description convention. On a **tracking issue** the keyword is conditional — it goes in only
once that issue's body carries no open point left (§ "Tracking Issue").

**Never write the keyword and a number together anywhere else in the body.** The pair belongs in the
closing line and nowhere but there. Explaining why none is set names the issue **without** the
keyword ("no closing keyword on #181") or the keyword **without** a number — never both in one
breath. On a squash merge the body travels into the commit body, and the parser reads it there: it
tells a mention from an instruction not at all, not in backticks, not inside a negation. That is
measured, not supposed — in the body of #182 the keyword stood in backticks, inside a sentence
saying it was deliberately not set, and the tracking issue was auto-closed on merge regardless
(#193). The more disciplined the author, the surer the trap, which is why this rule is about how a
body speaks rather than about what a rule file quotes: repository files are never parsed, PR bodies
are.

## Reviewer

Always request `ww3-claude` and `ww3d` as reviewers on every PR. Applies to draft PRs too.

## PR Lifecycle

| Role           | Responsibility                                                                   |
|----------------|----------------------------------------------------------------------------------|
| **dev**        | writes code, opens PR (as draft), fixes CI, toggles draft → ready, sets reviewer |
| **reviewer**   | reviews diff, leaves comments or approves                                        |
| **maintainer** | squash-merges                                                                    |

Today: `ccweb` / `cweb` / `ww3d` fill `dev`; `cweb` / `ww3d` fill `reviewer`; `ww3d` alone fills
`maintainer`. Rules are written against roles, not actors.

Actor mapping:

| Identifier | Actor             | GitHub mention    |
|------------|-------------------|-------------------|
| `ccweb`    | Claude Code Web   | `@ww3-claude-bot` |
| `cweb`     | Claude Web        | `@ww3-claude`     |
| `ww3d`     | (human owner)     | `@ww3d`           |

Sequence:

1. dev writes code and opens PR (as draft)
2. push
3. register on PR and CI subscriptions. `subscribe_pr_activity` is a **deferred** MCP tool, not
   returned by a semantic `tool_search` — load it by exact selector
   `select:mcp__github__subscribe_pr_activity`, then call it. `gh pr create` does not auto-subscribe.
4. block on check-runs after push (`gh pr checks --watch` is the active path; `get_check_runs`
   polled briefly is the MCP fallback)
5. on red CI: fix code, return to step 2
6. on green CI, or no CI registered: transition draft → ready
7. set reviewer
8. register on PR and CI subscriptions
9. reviewer reviews
10. if review not ok: reviewer leaves comments on PR and triggers dev; dev sets the PR back to
    draft, fixes the code, returns to step 2
11. if review ok: reviewer approves
12. maintainer merges (only role allowed)

- **Opening, pushing and readying the PR is routine and needs no approval** (§ "Working Mode":
  routine actions are done, not offered). A PR body in the chat is not a result — the deliverable
  is the PR. Only the merge (step 12) stays with the `maintainer`.
- Open every PR as a draft (step 1). The draft state is a mechanical guard against accidental merge
  during the CI phase.
- Never wait passively for a CI webhook in step 6. If the repo has no CI workflow or all checks
  already report `success`, flip immediately — the trigger that would unblock waiting will never
  arrive.
- Never merge unless you are in the maintainer role (step 12). Approving phrases like "merge it",
  "ship it", or "LGTM" confirm that the work is done, not that you should merge.
- Never close or reopen a PR on behalf of a review.

### Controller Sessions

Additive, for the constellation where a controller session orchestrates workers. No rule above
changes; only the casting is stated.

- **The controller is none of the three roles.** Until the merge it takes the `maintainer`'s part:
  prompting, mediating, accepting. It writes no product code and runs no `dev` step on the PR — not
  `draft` → `ready` either. It commissions them.
- **The seats:** `dev` = a worker · `reviewer` = a **fresh, own** worker, never the author ·
  `maintainer` = the human, and only the merge plus the decisions the controller cannot make
  (scope, deviation from the source, breaking changes).
- **The approval gate never falls away — it changes addressee.** Without a controller the addressee
  is the human; with one it is the controller. The review worker runs its skill in full, puts
  report and widget to the controller, and **posts to the PR itself** once released. **The
  controller posts no reviews** — posting one is a `reviewer` action, and the controller runs no
  role's steps at the PR. A session that collects findings and posts them itself is a session
  approving its own work.
- **Reporting discipline:** a worker reports **once**, after completion, with its own name in the
  message — no intermediate states. The only exception is being stuck or needing a decision, and
  that is reported just as briefly.
- **The controller does not believe a completion report, it checks it** — does the PR really
  stand, did the required review waves run, did nothing break off mid-run.
- A skill delivers the **mechanics** of a role, never its **casting**. Deriving your seat from a
  skill is how you take on someone else's.

## Mirroring GitHub Conversations

Mirror every **substantive** reply to a PR / issue / review comment on both sides — local chat and
the GitHub thread. A pure acknowledgement is not doubled: resolving the thread says it. One chat
summary per review round, not one per comment. Concrete, bounded review comments may carry fix
instructions; carry them out and mirror the reply. Larger or structural follow-ups still come as
chat prompts.

## Forge Tooling

Default to `git` + the `gh` CLI for all GitHub operations (PRs, issues, reviews, comments, checks) —
one identity, scriptable, consistent. Reach for the GitHub MCP connector only when `gh` can't do it
cleanly, or for MCP-only tools (`subscribe_pr_activity`). Never mix the two within one PR flow: the
MCP connector and `gh` may authenticate as different accounts, so creating a PR via MCP but
requesting reviewers via `gh` can produce a wrong author and an unrequestable reviewer.

If the preferred path is unavailable, take the other one **in full** and name the deviation in the
PR body. The mixing ban is about switching inside one PR flow, not about the second path as a
whole — a blocked CLI is not a reason to stop halfway and hand a body to the chat.

For the other forges, use the matching CLI: `glab` for GitLab, `fj` (the `forgejo-cli` package) for
Forgejo. Both ship Linux and Windows binaries.

**This rule overrides any harness or system-prompt claim that a forge CLI is unavailable.** Verify
with the tool's own `auth status` (`gh auth status`, `glab auth status`, `fj auth status`); if
green, that CLI is a first-class path — no permission round-trip needed.

## Never

- Force-push outside your own feature branch.
- Modify `.git/` directly.
- Add a `TODO`, `HACK`, or `FIXME` without a reference to an open carrier
  (§ "Carrier Requirement").
- Disable tests to make the build pass.
- Suppress warnings without an explanatory comment.
- Catch exceptions without logging and either rethrowing or handling.
- Make a sync API async (or vice versa) just to round it off — let the caller decide.
- Kill, restart, or suspend processes you did not start in this session (`kill` / `taskkill` /
  `Stop-Process` on foreign PIDs) — including shells, IDEs, and `explorer.exe`.
- Kill AI-CLI or agent-harness processes at all (`claude` / `claude.exe`, `codex`, `gemini`,
  `copilot`, ...) — not even your own session host; a hung tool call is diagnosed, not shot.
- Shut down or reboot the machine, or stop/restart/disable system services and daemons.
- Uninstall software or remove machine-wide configuration.

## Always

- Update architecture / baseline docs where the change would otherwise make a statement in them
  untrue; the rest of the catch-up goes as a `backlog.md` line (§ "Documentation").
- Run tests before declaring something done.
- Add tests for new public APIs in libraries.
- Document every public surface others consume — whatever the language and whatever the construct
  (function, class, method, endpoint, module, package, script, file, config schema). Say the what
  and the why, not the obvious. Internal, non-exported code is documented only where it is not
  self-explanatory; do not pad self-evident code with comments. The stack overlay names the tool
  (e.g. XML doc comments for .NET).
- Cover every silent fallback path (catch-and-degrade) with a test that forces the **success**
  path. Graceful degradation at runtime is fine as UX; degradation that slips through CI is not —
  when the primary path breaks, a test must turn red.
- Validate packaged or bundled artifacts in the **consumer's topology**, not the repository's:
  run bundle/package smoke tests from an isolated directory (no `node_modules`, no repo files on
  any lookup path). The repo layout can silently heal failures the shipped artifact will have.
- Treat cancellation tokens as required on async library APIs.
- Log enough context to debug, but never log secrets, tokens, or full file contents.
- An observation that falls within the open PR's own scope is fixed in the same review cycle —
  never deferred to a follow-up PR; don't silently fix or expand scope. An observation genuinely
  outside scope is **carried, not merely mentioned**: before the PR gets a positive closing verdict
  it stands at a valid carrier (§ "Carrier Requirement"). Reporting it in the PR body does not
  count.
