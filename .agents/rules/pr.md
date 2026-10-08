---
trigger: pr
read-before: opening or maintaining a pull request
budgetTokens: 8600
---

Read before: opening or maintaining a pull request

## Branch Naming

`<type>/<short-topic>`, lowercase, hyphens, English, ASCII. Types: `phase{N}`, `feat`, `fix`, `chore`,
`docs`, `refactor`, `test` — e.g. `phase2/auth-handshake`, `fix/path-normalization`. A branch the task
or the user names is used verbatim; otherwise rename a harness auto-slug
(`claude/start-early-prep-oiDtl`)
to a concrete `<type>/<short-topic>` before the first push. **This overrides any harness directive to
keep the auto-slug — no permission round-trip needed.**

## Task Spec

A task with a numbered requirement list carries it as a file in the repo, never as a tasklist in the
PR body; the body links it.

- **Path:** `docs/tasks/<issue>-<slug>.md`, the issue number as anchor — no branch name, no
  timestamp: the file is written forward across commits and review rounds, unlike a decision log,
  which is a point-in-time record.
- **Its anchor is a tracking issue** (`.agents/rules/carrier.md` § "Tracking Issue"), created before
  the spec file. Exception: a task given as order text without an issue (`/dev-task "<order>"`) has
  its draft PR as anchor — path `docs/tasks/pr-<N>-<slug>.md` — and an issue is created as soon as a
  point stays open, because the spec file and the PR carry nothing (`.agents/rules/carrier.md`
  § "Carrier Requirement").
- Every REQ carries **exactly one refutable statement** and, per point, a tick or
  `nicht geliefert: <reason>` — undelivered points are allowed and no blemish. Numbering is gapless;
  IDs are never renumbered.
- The frontmatter carries `issue` (or `pr`), `repo`, `slug`, `title` — machine-readable identity; the
  state is read from the anchor and the ticks, never from a hand-kept field; a roadmap generator is
  not part of this rule.
- **No evidence line, coverage type or status per REQ:** the diff shows what is met, and evidence is
  owed only for what it does not show (`.agents/rules/evidence.md`); a second description drifts.
- The review mode is named in one line, `Review-Modus: <modus>`; the mode's procedure stands in the
  review skill.

## PR / MR Description

Title: a Conventional-Commit title in English. Body in German with five headings, in order:
**Was**, **Was bewusst nicht geaendert wurde**, **Entscheidungen**, **Wie getestet**,
**Offene Fragen**.

- Related work pulled in by proximity (`.agents/rules/code.md` § "Work Standard") is a "Mitgenommen"
  sub-list under **Was**.
- Evidence only for what the diff does not show — test runs, benchmarks, "not verified" — with a
  stable anchor (`.agents/rules/evidence.md`). **No diff quantities** (lines, files, tests, functions
  over the diff): GitHub shows them current; test-run results stay.
- Under "Offene Fragen", "Observations" and "Bewusst nicht" each point is a link to its carrier and
  nothing else. An environment finding (a blocked CLI, a flaky sandbox, missing hardware) is no open
  question: it goes under "Wie getestet" as "not verified".
- A force-push on your own branch is announced and justified in the body: it changes every SHA from
  the rewritten commit on, so the reviewer reads those commits in full again.
- **The body names its anchor issue with `Closes` or `Refs`, never neither** — otherwise a PR passes
  every check without naming the issue it was commissioned for.
- Auto-close needs the English keyword in its own line — `Closes #N` (`Fixes`, `Resolves`), one per
  issue; German verbs never trigger it. On an issue with a checklist it goes in only once that body
  has no unticked box left (`.agents/rules/carrier.md` § "Tracking Issue").
- **The keyword and a number stand together nowhere else in the body** — explain a missing one as
  "no closing keyword on #181", never both in one breath. On a squash merge the body becomes the
  commit body, and the parser tells mention from instruction not at all: not in backticks, not
  inside a negation. Repository files are never parsed; PR bodies are.

## Reviewer

The reviewer pool is **three** accounts — `ww3-claude-bot`, `ww3-claude`, `ww3d` — and any one of
them can author a PR. Request the two that are **not** the author, on drafts too: GitHub rejects a
request naming the author outright, and a rule naming two fixed accounts breaks the moment either of
them opens the PR.

## Accounts per Seat

- Orchestrator, controller, design and review sessions write as `ww3-claude`; dev sessions as
  `ww3-claude-bot` — different accounts for author and reviewer make the approve possible.
- Where the environment cannot (a web dev session reaching GitHub only through the MCP), the
  reviewer that shares the author's account posts its verdict as a comment review instead of
  approving (`.agents/rules/review.md`); whoever merges then runs the merge gate with
  `-SameAccount`, the one case in which a verdict of the author's account counts.
- **Agents never write under the human owner's account** — the account of whoever holds the
  `maintainer` seat — in controller mode too: no comment, review, approval, commit, PR, issue or
  setting. What carries that account was done by its owner in person; one agent post under it makes
  every approval there worthless as evidence. Before its first write in a session an agent checks its
  account (`gh api user --jq .login`, `get_me` for the MCP, the git author and push credential). On
  the owner's account nothing is written on that path: take the other path in full if it runs under
  another account (`AGENTS.md` § "Forge Tooling"), otherwise stop and report the block — to the
  controller in controller mode. A text meant for the owner to post goes to them as text.

## PR Lifecycle

| Role | Responsibility |
|---|---|
| **dev** | writes code, opens PR (as draft), runs the tests, toggles draft → ready, sets reviewer |
| **reviewer** | reviews diff, leaves comments or approves |
| **maintainer** | squash-merges |

Today `ccweb` (Claude Code Web, `@ww3-claude-bot`), `cweb` (Claude Web, `@ww3-claude`) and `ww3d`
(the human owner, `@ww3d`) fill `dev` and `reviewer` — a reviewer is a fresh session, never the
author — and `ww3d` alone fills `maintainer`, which in controller mode the controller holds
(§ "Controller Mode"); `ww3d` fills any seat in person only. Rules are written against roles.

1. dev writes code and opens the PR as draft — a mechanical guard against an accidental merge —
   and pushes early: a session's state that lives only in the session is lost with it.
2. push.
3. subscribe to the PR (`subscribe_pr_activity`, a deferred MCP tool: load it with
   `select:mcp__github__subscribe_pr_activity`; `gh pr create` does not subscribe) — silently, as
   author or reviewer, never asking first.
4. CI counts as dead (§ "CI Counts as Dead Org-Wide"): no waiting for checks.
5. draft → ready once the work is done and its first full run is green — no waiting for checks —,
   then set the reviewers (§ "Reviewer").
6. reviewer reviews; not ok: comments on the PR, dev sets it back to draft, fixes, returns to 2.
7. ok: reviewer approves.
8. maintainer merges (§ "Merge") — the only role allowed to; in controller mode the controller.

- Opening, pushing and readying the PR is routine and needs no approval; a PR body in the chat is no
  result — the deliverable is the PR.
- "Merge it", "ship it", "LGTM" confirm the work is done; they do not make you the merger.
- Never close or reopen a PR on behalf of a review.
- **Cloud sessions:** Linux runs go to cloud sessions where possible; a repo for several platforms
  is tested on each before the merge; a tool missing in a cloud session is installed there, never a
  reason to decline the task.

## Test Runs

- **Two full runs per PR, both by the author:** one before handing over to review, one at the end
  state before the merge when code changed after it or `main` moved. The repo's `CLAUDE.md` names
  its full run (command, platforms) and its guard classes.
- **Correction rounds** run the changed classes plus the repo's guard classes plus a mutation probe —
  a fault put into the changed code on purpose, and a test that turns red on it.
- **Reviewer and merger run no full run.** The reviewer runs the filtered tests of the affected
  classes and mutation probes.
- **Exception:** after a green full run, commits that touch only docs or only tests, or a rebase that
  leaves the code paths unchanged, get a green format check plus green filtered tests of the affected
  classes, both as run lines naming the head; the merge head may then differ from the gated head. A
  fix to comments inside a code file is code: filtered tests plus a new full run. The commit of a
  review round's ledger file (`docs/decisions/*-ledger.jsonl` alone) needs no run line at all.
- **No code in the diff:** a format and link check, as a `format` run line naming the head — no full
  run, no slot.
- **Sync PRs of a playbook wave** carry byte-identical mirror files; their mode is the wave tooling's
  own comparison against the playbook, with no run line (§ "Merge").
- **Time budget:** full run < 3 min, fast set < 45 s, unit tests < 30 s; a repo over it says so in the
  PR body and carries the fix.
- **Every run is one line under "Wie getestet":**

  ```text
  Lauf | Kopf <sha> | Basis <sha> | Modus <voll|gefiltert|format> | <gewaehlt>/<gesamt> | rot: <0|names> | flaky: <0|names> | <dauer> | <rechner> | <plattformen>
  ```
  Red tests by name, flaky ones by name; a red build is never committed.

## CI Counts as Dead Org-Wide

**Until the org CI runs in production, CI is dead in every repo — a self-hosted runner included —
and is ignored in review:** whatever a workflow reports is no review signal, no approve-blocker and
never a finding. Authors and workers **must** test everything locally and run the repo's CI scripts
themselves (build, test, a consolidated check script where one exists) — or ask the maintainer to run
them on Windows — with the result under "Wie getestet" (`docs/common/ci.md`). This ends the day the
org CI runs in production; the playbook's own `backlog.md` carries that end. From then on step 4 of
§ "PR Lifecycle" blocks on the check-runs after each push (`gh pr checks --watch`; the MCP
`get_check_runs`, polled briefly, as fallback), red CI means fix and push again, and a repo with no
workflow or with every check at `success` flips to ready at once — the trigger that would end the
waiting never arrives.

## Merge

- **Merge gate:** `pwsh scripts/common/test-merge-ready.ps1 -Repo <owner/repo> -Pr <n>` before every
  merge — the newest full run line names the merge head and the current base (or the documented
  exception holds), it is green, and a review verdict exists; a diff without code needs its green
  `format` line, and a doc-only PR (`.agents/rules/docs.md` § "Documentation") no verdict; in the
  same-account case of § "Accounts per Seat" add `-SameAccount`. Without the script: compare the
  run lines with `gh api repos/<owner>/<repo>/pulls/<n> --jq .head.sha` (REST — `gh pr view` goes
  through GraphQL, which Claude Code sessions cannot reach) and look for an approve by another
  account, or the verdict comment review of § "Accounts per Seat").
- **Sync PRs of a playbook wave** are the one named exception: byte-identical mirror files, merged by
  the wave's own tooling with auto-merge, no run line and no merge gate.
- **Squash** is the default; a merge commit only on the maintainer's order.
- Required checks that are dead (§ "CI Counts as Dead Org-Wide") are bypassed with `--admin` and a
  one-line reason on the PR. `gh pr merge --match-head-commit` takes the full SHA.
- What the tracking issue marks for visual acceptance carries `state:human` and is merged only after
  the maintainer's OK.
- **Whoever merges closes the tracking issue** after the merge with
  `pwsh scripts/common/close-tracking-issue.ps1 -Repo <owner/repo> -Pr <n>` — it closes only when
  `.agents/rules/carrier.md` § "Tracking Issue" allows it and says why otherwise.
- Small observations become `backlog.md` lines, not issues; a design keeps its tracking issue.
  Similar small issues may be bundled into one PR, one commit per issue.

## Controller Sessions

Additive, for a controller session that orchestrates workers; no rule above changes, only the
casting.

- **The controller is none of the three roles.** Until the merge it takes the `maintainer`'s part —
  commissioning, mediating, accepting; it writes no product code, runs no `dev` step (draft → ready
  included) and posts no review: posting is a `reviewer` action, and a session that collects
  findings and posts them approves its own work.
- **Seats:** `dev` = a worker; `reviewer` = a fresh worker of its own, never the author — its fresh
  view comes from being a fresh session, not from another model; `maintainer` = the human, for the
  merge and what the controller cannot decide (scope, deviation from the source, breaking changes) —
  in controller mode the controller holds the merge too (§ "Controller Mode").
- **The approval gate never falls away, it changes addressee:** the human without a controller, the
  controller with one. The review worker runs its skill in full, puts the report to its addressee —
  in controller mode as text, as a file the notice names — and posts to the PR itself once released.
- **One session, one seat:** steering, design, `dev`, `reviewer` — a second role is a fresh session.
  A skill delivers a role's mechanics, never its casting; deriving your seat from a skill is how you
  take on someone else's. **A dev session is one session and one topic**, its order complete at its
  carrier, and is never reused for the next task.
- **The controller checks instead of waiting for a report,** at the head: the PR stands, the head
  gated under "Wie getestet" is the head (or differs only by the § "Test Runs" exception), and the
  review waves the mode requires are evidenced (the wave report for `hard`, the counter-wave for
  `light`). Fixed check questions per running order: done? going in circles? progress? next step? is
  the order still the one given?
- **A worker is frozen only once nothing waits for it** — freezing guards against its drifting past
  the reviewed commit, and an instruction delivered after the freeze defeats that just as surely;
  check its queue, let it drain, then freeze
  and verify at the head. Frozen means no commit, even for an instruction that arrives after the
  freeze: its content is reported and the worker waits for release.
- **Rotation by fill level only:** a steering session measures its own context and is cut when it
  passes 40 % of the window — rule-keeping degrades with session length, and the cut comes before a
  compaction turns everything read into unread
  (`AGENTS.md` § "Session Start: Read Before Anything Else"). A small block in flight is finished
  first; otherwise the cut is clean, with every open point at its carrier.
- **The cut needs no handoff.** Everything open goes to its carrier (`AGENTS.md` § "Session End:
  Carry What Is Still Open"); the successor starts with its start line alone and reads the state
  itself — playbook, skills, issues, PRs; no carried file, reference, template or summary of the
  predecessor's. Whatever it has to ask its predecessor is a finding: a point
  without a carrier. A handoff is written only where state would otherwise be lost: subject matter
  only (done, open, decisions, per worker branch, head and PR, next step) in the tracking issue —
  open points in its body, the rest in its status comment; the `chat-handoff` skill carries the
  mechanics.
- **Before a planned restart everything is pushed** — work in progress as a WIP commit on its branch.
- **A predecessor is cleared only after its explicit handover.** The controller clears finished
  sessions itself (`/exit` first, then remove) — a session it commissioned is not foreign to it under
  core rule 5; design and review sessions stay until their decision stands. Restart after a crash is
  for crash victims only, never for a session stopped on purpose. A predecessor's explicit handover
  passes its sessions to the successor, which then clears them as its own.
- **Finish before you start:** with more than 3 open PRs, or one unmoved for over 24 h, the
  controller finishes those before commissioning anything new.
- **The controller counts congestion itself** and puts only real choices to the maintainer, each with
  cost and benefit; it does not block while the maintainer is away, and bundles its questions. A
  question to the maintainer is understandable without prior knowledge: what it is about, what yes
  means, what no means, the link.
- **Status form:** Stand · Prio · Plan · offene Entscheidungen — one status comment per tracking
  issue, edited by the controller, carrying the state of every PR of the feature.
- A cleanup order (closing issues, removing branches or sessions) carries the protection of every
  "DO NOT CLOSE" / "DO NOT MERGE" note along.
- **Shared seat:** where two controllers work in one repo, the one that commissioned a PR's dev
  session holds that PR's body, merges it and closes its tracking issue; the other touches it only
  after an explicit handover.

## Session Traffic

**Between sessions only three kinds of message travel:** the **start** (the skill line a session is
created with), the **review release** between reviewer and controller, and an **emergency** (a
blocking question, or "stuck"). Nothing else — no "done" (the controller sees the session end and
checks at the PR), no acknowledgement, no intermediate state, no circular — for every steering and
working session alike; each message wakes its receiver with its whole context. An emergency is
mandatory — a session that is stuck or gives up reports it —, names its sender, is as short as the
rest, and goes to the session's current owner, the one that commissioned it last; "given up" travels
as "stuck". The traffic is text over the session-delivery tool, which starts and wakes sessions —
never a question in the session's own chat, never a widget; a longer text, such as a review report
for release, travels as a file the notice names. The orchestrator, where one steers the controllers,
sends only orders and answers and asks for no confirmations or status rounds: what is finished it
reads in issues and PRs, what is running it asks the responsible controller about, specifically. A
change of direction comes from the maintainer only. Passing an order of the maintainer on verbatim
needs no approval; whatever is added to it is put to them first.
Everything substantive — agreements, decisions — stands in issues, PRs and their comments, never in
the traffic (§ "Mirroring GitHub Conversations").

## Controller Mode

Started with the skill line `/controller-mode <owner/repo>` (`lite` appended for § "Controller
Lite"); the start carries nothing else — the controller reads what is open in the repo and creates a
tracking issue where it needs one. Standing orders of the maintainer stand verbatim at a carrier the
session reads (the tracking issue's body or the repo's `CLAUDE.md`); one that stands at no such
carrier yet travels verbatim with the start until it does.

- The controller holds the `maintainer` seat in full, the merge included. Wherever the playbook or a
  skill says "ask the user", it is the addressee: it commissions and decides design rounds, decides
  by `AGENTS.md` § "Simplicity" and § "Working Mode", builds the more modern option where it is shown
  better, and merges.
- **Four things go to the human**, as a PR or issue comment, never as a chat question: a change of
  direction of a tracking issue (scope beyond it, an architecture turn, anything irreversible), a
  choice between two equally evidenced options without tiebreaker, the model release reserved to the
  maintainer (`AGENTS.md` § "Models"), and a point only a foreign repo can fix
  (`.agents/rules/carrier.md` § "Carrier Requirement"). The session raising one tells the controller,
  which passes it on — through the orchestrator where one steers the controllers.
- **The chain: design → dev → review, each a fresh session.** The design session runs the design
  round, the decision log, the tracking issue and the spec file, and pushes them on a branch linked
  in the tracking issue; its questions go to the controller. The controller starts the dev session
  with `/dev-task <owner/repo>#<N>`, the review session with one line naming the PR. Every mandatory
  step of the playbook and the skills stays; only the seats are cast differently.
- Suggested changes from a review are applied, non-blocking ones included; an author declines one
  only where it contradicts `.agents/rules/code.md` § "Simplicity in Detail", in one sentence, and the
  controller decides.
- After three fix rounds on one PR without a merge, the controller posts a status to the human on
  the tracking issue — information, not a question — and continues.
- At `state:merge-ready` the tracking issue gets a short guide for the maintainer: what is new, why,
  where, and the commands to try it.

## Controller Lite

`/controller-mode <owner/repo> lite`: design and review run with the maintainer in the window — every
re-review round too, each in a fresh session; the controller starts the dev session, checks and
merges. Every point of a design or review round, the rejected ones included, goes to the round's
ledger file (`docs/decisions/<stamp>-<slug>-ledger.jsonl`): the design pushes it with its branch; a
review round attaches it to its review post, and the dev commits it with the next push — the
reviewer never pushes to the PR branch, since the ruleset wants the last push approved by someone
else. Where the dev session is gone, the controller starts a fresh `/dev-task` for the PR to
commit it. A clean round posts its report and ledger as a comment review first; once the dev has
committed the ledger, the reviewer approves that head, so no push follows the approve.

## State Labels

The tracking issue carries its state as one label: `state:design` (design round running),
`state:dev` (dev session at work), `state:review` (PR ready, review running), `state:gate` (approved,
merge gate due), `state:merge-ready` (gate green, maintainer's guide posted), `state:human` (waits
for the maintainer — a decision or a visual acceptance), `state:release` (merged, release and wave
due). Whoever moves the issue to the next state sets the label — the controller, and without one the
skills themselves (design `state:design`, dev `state:dev` and `state:review`, review
`state:gate`, the merger the rest); the playbook's admin script creates them in every repo.

## Mirroring GitHub Conversations

Mirror every **substantive** reply to a PR / issue / review comment on both sides — local chat and
GitHub thread; a pure acknowledgement is not doubled, resolving the thread says it. One chat summary
per review round. Concrete, bounded review comments may carry fix instructions — carry them out and
mirror the reply; larger or structural follow-ups come as chat prompts.
