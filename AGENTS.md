# Agent Rules — Shared Playbook

Read on every session. Imported by each consuming repo's `CLAUDE.md` via `@AGENTS.md`. Tech overlays
(e.g. `tech/common/dotnet.md`) are imported separately when the project adopts that stack.

Below the import block, the consuming `CLAUDE.md` adds project-specific material — Project
Context, Architecture Principles, Project-Specific Overrides.

This file is the **core**: what holds in every session, before the first step. The rest of the
ruleset lives in the rule files below and is read at the point where it applies, not at the start.

## Rule Files

One file per point of use. Each is read **in full** and receipted before the first action of its
trigger type in a session (§ "Session Start: Read Before Anything Else", building block 3) — never
skimmed, never quoted from memory. A rule that is not in this table stands in this core.

<!-- rule-index:start -->
| Trigger | File | Read before |
|---|---|---|
| `audit` | [`.agents/rules/audit.md`](.agents/rules/audit.md) | starting a new slice, or running a state audit |
| `carrier` | [`.agents/rules/carrier.md`](.agents/rules/carrier.md) | deferring a point, or closing an issue |
| `code` | [`.agents/rules/code.md`](.agents/rules/code.md) | writing code |
| `docs` | [`.agents/rules/docs.md`](.agents/rules/docs.md) | touching a doc or a timestamped file |
| `evidence` | [`.agents/rules/evidence.md`](.agents/rules/evidence.md) | claiming something is done, green, or measured |
| `pr` | [`.agents/rules/pr.md`](.agents/rules/pr.md) | opening or maintaining a pull request |
| `review` | [`.agents/rules/review.md`](.agents/rules/review.md) | posting a review |
<!-- rule-index:end -->

The table is **generated** from the rule files' frontmatter by `./scripts/update-rule-index.ps1`,
never hand-kept, and CI fails when the checked-in table or `.agents/rules/index.json` differs from
the generated state. A consuming repo may add its own rules under `.agents/rules/local/`, same
frontmatter, picked up by the generator and never touched by the playbook sync.

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
  `select:mcp__github__subscribe_pr_activity` first; see `.agents/rules/pr.md` § "PR Lifecycle"
  step 3) to every PR cc is actively involved in — as author (its own PR) or as reviewer (someone
  else's PR under review) — regardless of how it got there: PR lifecycle, reviewer role, or a
  skill / tooling PR. Never ask first.
- Routine actions are done, not offered. Drop the conversation-extending closing "shall I … ?"
  about a routine step — execute it instead of proposing it at the turn's end.

## Session Start: Read Before Anything Else

Truth is the repo at the head of the branch under work (`main` where there is none) — never the
prompt, never memory. With a working copy that head is the local `HEAD`; without one it is the
remote head, read via the GitHub MCP or `gh`. A session with no checkout still reads the head — it
does not fall back to the prompt.

**Memory is a suspicion, not evidence.** Whatever you believe you know about a document, an issue,
a log or a rule is a lead to check at the head, never a source to act on. This sentence is what the
four building blocks below implement: they move the reading from "everything up front" to "the
relevant thing, in full, at the moment it decides something".

1. **Mandatory core** — read in full, always, receipt each file with its blob SHA: this `AGENTS.md`
   core, `CLAUDE.md`, and the **audit head** of the latest state audit — its metadata block plus
   the short-form section that leads it (`.agents/rules/audit.md` § "State Audit"). Only after an
   unsuccessful search may one of the three be reported as "not found" — never skip one silently.
2. **State, selectively** — roadmap, backlog and architecture document are **not** read in full.
   Mandatory instead: the **index** of building block 2's sources — the remaining doc files
   (`docs/**` plus the Markdown files in the repository root) as a list (path + purpose), exempt
   `docs/overview/`, visualizations for humans rather than agent reading — and the **running
   slice**: the body of the open tracking issue plus its `roadmap.md` lines. Everything else is
   **on demand, and sharpened**: before any statement or decision that touches a document, a
   decision log, an issue, or a dependency / reference repo (e.g. the courier docs in `win-util`,
   Filer as the model template), that source is read **in full first**. Decision logs of the
   running phase: always.
3. **Point-of-use receipt** — before the **first** action of a trigger type in a session, the
   matching rule file from § "Rule Files" is read in full and receipted, once per session per file.
   The format is the start receipt's, with `rule` in place of the role — that column is what marks
   the line as a rule-file receipt, and the trigger is the file's name:

   ```text
   role | path | blob SHA | read / not found
   rule | .agents/rules/pr.md | 4f2a1c9… | read
   ```

   The receipt is what the gate reads: in Claude Code a `PreToolUse` hook
   (`.claude/hooks/require-rule-read.sh`) blocks the trigger action while it is missing and, on the
   second attempt, injects the rule file itself; where a harness runs no hooks, the skills carry
   the receipt as their entry step. Neither replaces reading the file.
4. **Too large to read in one go** — where a mandatory source exceeds the environment's retrieval
   limit, read it section by section. Where even that fails, the receipt carries a declared
   exception line instead of a silent gap:

   ```text
   partial: docs/architecture.md - sections 1-4 of 11, MCP retrieval limit
   ```

**Every generated artifact carries only verified state the repo cannot provide** (decisions of the
round, cleared-up misconceptions, constellation) — never rules, conventions, or doc summaries: a
rule copy is how the original gets softened. This holds for all of them, by name: task prompt,
review prompt, decision log, handoff, task spec file. The rule stands here once; the skills and the
decision-log skeleton point at it instead of repeating it. Read first, then act.

## Session Receipt

At session start, acknowledge what you have read as three groups — `Konventionen`, `Profil`,
`Memory` — one line per file under each group header, an `OK` closing each group. The
`read-confirm.sh` SessionStart hook injects this receipt automatically (`/read-check` reproduces it
on demand); report the playbook version from `.playbook-version`, and the generated rule index from
`.agents/rules/index.json` under `Konventionen`, so the points of use are in context before the
first one is reached. Mark what an environment cannot see as
`— (nicht verfuegbar in dieser Umgebung)`, never omit it. Keep it terse.

The hook receipt reports file presence only — it does not replace the blob-SHA read receipt from
§ "Session Start: Read Before Anything Else"; that one is given in addition, and so is the
point-of-use receipt of every rule file the session actually reaches.

**The receipt is gated, not merely expected.** The `require-receipt.sh` Stop hook refuses to let a
turn end until the receipt has been emitted. Both hooks are synced from the playbook, but the
registration that runs them lives in the repo's own `.claude/settings.json` — where that entry is
missing, neither fires and the rule rests on discipline alone.

## Session End: Carry What Is Still Open

Before the session ends, walk it backwards once: every point that is still open and stands nowhere
goes to a valid carrier first (`.agents/rules/carrier.md` § "Carrier Requirement"). Decisions with
no log entry, cleared-up misconceptions, deferred points, running orders — a point that lives only
in the transcript dies with it. This is the counterpart to the read mandate above, and unlike the
carrier gate in a review it does not depend on a PR existing.

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

## Existing Code

When integrating code from another repo or earlier project: read it first, summarize what it does,
then propose how to modernize and merge. Never rewrite from scratch unprompted — treat existing
implementations as assets, not obstacles.

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
  (`.agents/rules/carrier.md` § "Carrier Requirement").
- Act on a rule from memory instead of from its rule file (§ "Rule Files").
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
  untrue; the rest of the catch-up goes as a `backlog.md` line (`.agents/rules/docs.md`
  § "Documentation").
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
  it stands at a valid carrier (`.agents/rules/carrier.md` § "Carrier Requirement"). Reporting it
  in the PR body does not count.
