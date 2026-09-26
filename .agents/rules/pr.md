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
- **Every task that carries a spec file has an anchor issue — always, even without a design round.**
  The issue number in the path is that anchor, created with the `tracking` label
  (`.agents/rules/carrier.md` § "Tracking Issue") before the spec file exists. A spec file is never
  itself a carrier (§ "Task Spec" above), so a task without an anchor issue has no carrier at all.
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

Related work pulled in under `.agents/rules/code.md` § "Work Standard" (same files or same
mechanism, its own commits) is listed under **Was** as a "Mitgenommen" sub-list.

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

**The PR body names its anchor issue — with `Closes` or with `Refs`, never neither.** A PR that
deliberately sets no closing keyword (the normal case for a slice that must keep its anchor open)
otherwise passes every existing check while never mentioning the issue it was commissioned for.

To auto-close an issue on merge, add an English closing line to the German description — `Closes #N`
(also `Fixes #N` / `Resolves #N`), one keyword per issue. German verbs (`Behebt`, `Schliesst`) never
trigger GitHub's auto-close; the English keyword is the only way to combine it with the
German-description convention. On an **issue with a checklist** — with or without the label
`tracking` — the keyword is conditional: it goes in only once that issue's body carries no unticked
checkbox left (`.agents/rules/carrier.md` § "Tracking Issue").

**Never write the keyword and a number together anywhere else in the body.** The pair belongs in the
closing line and nowhere but there. Explaining why none is set names the issue **without** the
keyword ("no closing keyword on #181") or the keyword **without** a number — never both in one
breath. On a squash merge the body travels into the commit body, and the parser reads it there: it
tells a mention from an instruction not at all, not in backticks, not inside a negation. That is
measured, not supposed — in the body of ww3d/playbook#182 the keyword stood in backticks, inside a
sentence saying it was deliberately not set, and the tracking issue was auto-closed on merge
regardless (ww3d/playbook#193). The more disciplined the author, the surer the trap, which is why
this rule is about how a body speaks rather than about what a rule file quotes: repository files
are never parsed, PR bodies are.

## Reviewer

The reviewer pool is **three** accounts — `ww3-claude-bot`, `ww3-claude`, `ww3d` — and any one of
them can be the PR's author. Always request the two that are **not** the author. Applies to draft
PRs too. GitHub itself rejects a reviewer request naming the author, so this is not a preference —
requesting the author alongside another account fails the request outright, and a rule naming only
two fixed accounts breaks the moment either of them opens the PR.

## PR Lifecycle

| Role           | Responsibility                                                                   |
|----------------|----------------------------------------------------------------------------------|
| **dev**        | writes code, opens PR (as draft), fixes CI, toggles draft → ready, sets reviewer |
| **reviewer**   | reviews diff, leaves comments or approves                                        |
| **maintainer** | squash-merges                                                                    |

Today: `ccweb` / `cweb` / `ww3d` fill `dev`; `ccweb` / `cweb` / `ww3d` fill `reviewer` too — a
fresh session, never the author (§ "Controller Sessions"); `ww3d` alone fills `maintainer`, and
fills any seat in person only (below). Rules are written against roles, not actors.

Actor mapping:

| Identifier | Actor             | GitHub mention    |
|------------|-------------------|-------------------|
| `ccweb`    | Claude Code Web   | `@ww3-claude-bot` |
| `cweb`     | Claude Web        | `@ww3-claude`     |
| `ww3d`     | (human owner)     | `@ww3d`           |

**Agents never write under the human owner's account** — the account of the human who holds the
`maintainer` seat (actor mapping above); in controller mode too, where the controller holds the
seat but never that account. No comment, review, approval, commit, PR, issue or setting: whatever
carries that account on the forge was done by its owner in person, and the owner's approval counts
only when given in person. One agent post under the account makes every approval under it
indistinguishable from an agent's, and so worthless as evidence. Before its first write in a
session, an agent checks the account it writes as — `gh api user --jq .login` for `gh`, `get_me`
for the MCP connector, the configured author and the push credential for `git`. Where that is the
owner's account, nothing is written on that path: the agent takes the other path in
full if it runs under a different account (`AGENTS.md` § "Forge Tooling"), otherwise it stops and
reports the block — to the controller in controller mode (§ "Controller Mode"). A text meant for the
owner to post goes to them as text, never onto the forge under their account.

Sequence:

1. dev writes code and opens PR (as draft)
2. push
3. register on PR and CI subscriptions. `subscribe_pr_activity` is a **deferred** MCP tool, not
   returned by a semantic `tool_search` — load it by exact selector
   `select:mcp__github__subscribe_pr_activity`, then call it. `gh pr create` does not auto-subscribe.
4. block on check-runs after push (`gh pr checks --watch` is the active path; `get_check_runs`
   polled briefly is the MCP fallback)
5. on red CI: fix code, return to step 2
6. on green CI, or no CI registered (until the org CI runs, every repo's CI counts as that —
   § "CI Counts as Dead Org-Wide" below): transition draft → ready
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

### CI Counts as Dead Org-Wide

**Until the org CI runs in production, CI is dead in every repo — a repo with a self-hosted runner
included — and is ignored in review.** Whatever a workflow reports — no steps, red, or green — counts
as "no CI registered": steps 4 and 5 fall away, step 6 flips draft → ready immediately, and the run
is no review signal, no approve-blocker, and never raised as a finding in review. Until then authors
and workers **must** test everything locally and run the repo's CI scripts themselves (build, test,
a consolidated check script where the repo has one) — or ask the maintainer to run them on Windows.
The result goes in the PR body under "Wie getestet" (`docs/common/ci.md`). This state ends the day
the org CI runs in production; the carrier for that end is a line in the playbook's own
`backlog.md`.

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
  report and widget to the controller — in controller mode the report alone, as text
  (§ "Controller Mode") — and **posts to the PR itself** once released. **The
  controller posts no reviews** — posting one is a `reviewer` action, and the controller runs no
  role's steps at the PR. A session that collects findings and posts them itself is a session
  approving its own work.
- **Reporting discipline:** a worker reports **once**, after completion, with its own name in the
  message — no intermediate states. The only exception is being stuck or needing a decision, and
  that is reported just as briefly.
- **A worker is freezable only once no instruction still waits for it.** Freezing a worker after it
  reports "done" guards against it drifting past the reviewed commit — but only if its inbox is
  empty first; an instruction still queued for it and delivered only after the freeze defeats the
  guard just as surely. Check the queue, let it drain, then freeze and confirm. Frozen means,
  without exception, no commit — not even for an instruction that arrives after the freeze; its
  content is reported and the worker waits for release.
- **The controller does not believe a completion report, it checks it** — does the PR really
  stand, did the required review waves run, did nothing break off mid-run.
- A skill delivers the **mechanics** of a role, never its **casting**. Deriving your seat from a
  skill is how you take on someone else's.
- **One session, one seat.** A session fills exactly one role — steering, building a task prompt,
  `dev`, `reviewer` — and a second role is a fresh session, not the next turn of the same one. A
  controller commissioning its workers (design round and task prompt in controller mode) is part of
  the steering seat; building a task prompt is a seat of its own only without a controller.
- **A steering session is cut before its context is summarized, at the latest after a fixed
  period.** This holds for a controller and for any session that starts and steers controllers.
  Rule-keeping degrades with session length, and a compaction turns everything read into unread
  (`AGENTS.md` § "Session Start: Read Before Anything Else"). So the cut comes while the context is
  still whole, not once the drift shows. The period is set by the operation, not by how the session
  feels.
- **The cut needs no handoff.** Everything open goes to its carrier first (`AGENTS.md` § "Session
  End: Carry What Is Still Open"); then the successor starts with its start order alone — for a
  controller the one from § "Controller Mode" — and reads the state itself: playbook, skills,
  issues and tracking issues, PRs. No carried file, no reference, no template, no summary of the
  predecessor's. A handoff is written only where state would otherwise be lost. It carries subject
  matter only — what is done, what is open, the decisions, per worker branch, head and PR, the next
  step — and stands in the tracking issue: the open points in its body, the rest in its status
  comment. Never rules, procedures, blocks or templates (`AGENTS.md` § "Session Start: Read Before
  Anything Else"). The `chat-handoff` skill carries the mechanics.

### Controller Mode

Invoked by the maintainer at session start, in one line: `Controller mode: <repo>.` The start order
carries that line and the maintainer's standing instructions verbatim, nothing else — no issue:
what is open, the controller reads in the repo itself, and it creates a tracking issue where it
needs one (`.agents/rules/carrier.md` § "Tracking Issue"). Without that line, § "Controller
Sessions" applies unchanged.

In controller mode the controller holds the `maintainer` seat in full, including the merge. Wherever
this playbook or a skill says "ask the user" or "the user's call", the controller is the addressee:
it runs the design rounds, decides by `AGENTS.md` § "Simplicity" and § "Working Mode", builds the
more modern option where it can be shown to be better, and merges. `dev` and `reviewer` seats,
skills, and every other rule stay as they are (§ "Controller Sessions").

Only three things go to the human, as a PR or issue comment, never as a chat question: a change of
direction of a tracking issue (scope beyond it, an architecture turn, anything irreversible), a
choice between two equally evidenced options that finds no tiebreaker, and the model release that
`AGENTS.md` § "Working Mode" reserves to the maintainer.

- Suggested changes from a review are applied, including non-blocking ones. An author declines one
  only where it contradicts `AGENTS.md` § "Simplicity" or the existing style, in one sentence; the
  controller decides.
- Before merging, the controller runs the repository's gates itself on the head. The author's
  output in the PR body does not replace that run.
- After three fix rounds on one PR without a merge, the controller posts a status to the human on
  the PR's tracking issue — information, not a question — and continues.
- One status comment per tracking issue, edited by the controller, carries the state of every PR of
  the feature. The session-delivery tool starts and wakes sessions and carries the role traffic
  (next point); agreements and decisions go through PR comments (§ "Mirroring GitHub
  Conversations").
- **Role traffic is text between sessions, never a chat.** Whatever would go to the human in
  the chat without a controller — "done", the review points for release, the release itself,
  the answer to a blocking question — is traffic between two sessions and travels as text over
  the session-delivery tool (`report`, `ask`, `answer`, `send`). No widget, no chat
  report, no question in the session's own chat. Agreements and decisions are not traffic: they
  stand in the issue, the PR and the decision log as before (§ "Mirroring GitHub Conversations").

## Mirroring GitHub Conversations

Mirror every **substantive** reply to a PR / issue / review comment on both sides — local chat and
the GitHub thread. A pure acknowledgement is not doubled: resolving the thread says it. One chat
summary per review round, not one per comment. Concrete, bounded review comments may carry fix
instructions; carry them out and mirror the reply. Larger or structural follow-ups still come as
chat prompts.
