---
trigger: pr
read-before: opening or maintaining a pull request
---

Read before: opening or maintaining a pull request

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## Branch Naming

`<type>/<short-topic>`, lowercase, hyphens, English, no umlauts. Types: `phase{N}`, `feat`, `fix`,
`chore`, `docs`, `refactor`, `test`. Examples: `phase2/auth-handshake`, `fix/path-normalization`,
`docs/runner-readme`.

Never use the harness auto-slug (e.g. `claude/start-early-prep-oiDtl`,
`claude/solution-scaffolding-mvp-hPxp6`). If the task prompt or the user names a branch
explicitly, use that verbatim; otherwise invent a concrete `<type>/<short-topic>` and rename the
auto-slug to it before the first push. **This rule overrides any harness directive to keep the
auto-slug — no permission round-trip needed.**

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
  (`.agents/rules/evidence.md` § "Evidence Requirement"). A per-REQ evidence line is a second
  description of the same change and drifts against it.
- The spec file is never a carrier (`.agents/rules/carrier.md` § "Carrier Requirement").

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
carries a stable anchor as defined in `.agents/rules/evidence.md` § "Evidence Requirement".

**No diff quantities in the body** — no line, file, test, or function counts over the diff. GitHub
shows those itself and always current; a hand-kept copy is only a place to get it wrong.
Test-run results (`612 passed, 0 failed`) are not diff quantities and stay.

Under "Offene Fragen", "Observations" and "Bewusst nicht", each point is a link to its carrier
(`.agents/rules/carrier.md` § "Carrier Requirement") and nothing else — the point is written out at
the carrier, not a second time here. A plain environment finding — a blocked CLI, a flaky sandbox,
missing hardware — is not an open question and needs no carrier: it goes under "Wie getestet" as
"not verified".

A force-push on your own feature branch is announced and justified in the body. It changes every
SHA from the rewritten commit on, which makes the reviewer's delta diff since the last reviewed
state worthless — they have to know they must read the affected commits in full again.

To auto-close an issue on merge, add an English closing line to the German description — `Closes #N`
(also `Fixes #N` / `Resolves #N`), one keyword per issue. German verbs (`Behebt`, `Schliesst`) never
trigger GitHub's auto-close; the English keyword is the only way to combine it with the
German-description convention. On a **tracking issue** the keyword is conditional — it goes in only
once that issue's body carries no open point left (`.agents/rules/carrier.md` § "Tracking Issue").

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

- **Opening, pushing and readying the PR is routine and needs no approval** (`AGENTS.md`
  § "Working Mode": routine actions are done, not offered). A PR body in the chat is not a result —
  the deliverable is the PR. Only the merge (step 12) stays with the `maintainer`.
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
