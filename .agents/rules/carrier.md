---
trigger: carrier
read-before: deferring a point, or closing an issue
---

Read before: deferring a point, or closing an issue

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

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
- **An agent editing the body from a shell uses `scripts/common/edit-issue-body.ps1`** — ticking a
  point or rewriting a section. It changes that one place and refuses any other change. Read by
  hand through a PowerShell string, a body arrives as lines and goes back as one: no checkbox
  renders, and every reader of the list sees nothing open. A session that writes the whole body
  through the forge connector instead reads it before and after and compares the two: only the
  intended place may differ.
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
- **Past a size guideline, points move to GitHub Sub-Issues.** Around 30 checkboxes, a tracking
  issue trades its open points for GitHub Sub-Issues; the body then carries the current state
  instead of every point in Markdown. Reason: issue bodies have a length limit, and a full body
  looks exactly as tended as a healthy one. Known gap: sub-issues are not forge-neutral
  (GitLab / Forgejo model them differently) — accepted as long as every repo lives on GitHub.
- **`Closes #N` on an issue with a checklist only where that issue's body carries no unticked
  checkbox left — with or without the label `tracking`.** The condition hangs on the checklist, not
  on the label. The keyword closes on merge and checks nothing on its way; a closed carrier is the
  worst carrier there is, because it looks like a finished one (§ "Carrier Requirement"). While a
  point stands open, the PR names the issue without a closing keyword, and it is closed by hand
  once its last point is ticked (see the next two bullets for who). This holds for `Fixes #N` and
  `Resolves #N` alike, and it is the one place where the auto-close footer from
  `.agents/rules/pr.md` § "PR / MR Description" is conditional.
- **Who closes it, and in which order: the `reviewer` first, the `maintainer` as fallback.** After
  the merge the `reviewer` closes the tracking issue, once **both** hold: its body carries no open
  point left, and the check from § "Carrier Requirement" has run ("before closing an issue, check
  what points to it"). If the body still carries points, the issue **stays open** — a point is
  moved only because it no longer belongs to this design, never to make the issue closable. Where
  the `reviewer` cannot, it falls to the `maintainer`. The rank is named on purpose: two
  responsible parties without an order is a judgement call, and this section exists because
  judgement calls are where points get lost. The `reviewer` goes first for a mechanical reason —
  the gate already had them read that body fresh at the head. The **merge** stays `maintainer`-only.
- **The same order holds for every issue with a checklist, with or without the label `tracking`.**
  After the merge of the PR that ticks off its last point, that PR's `reviewer` closes it, the
  `maintainer` as fallback — under the same two conditions: no unticked checkbox left, and the
  checks from § "Carrier Requirement" have run. Whether this PR ticked the last point is counted
  again at the head, never remembered. Where no PR ticks the last point — it is ticked off by hand,
  or moved to another carrier — whoever does that closes the issue, under the same two conditions,
  the `maintainer` as fallback; the state audit stays the net below, not the first one responsible.
  A doc-only PR merged without review
  (`.agents/rules/docs.md` § "Documentation") has no `reviewer`; there it falls to the `maintainer`
  directly. The label marks a design with a decision log, not what may be closed.
- **The review checks two things instead of N:** does the tracking issue exist and is it open, do
  the points this PR defers stand in it — and, where the PR carries a closing keyword for it, is
  its body free of open points (`pr-poll-review`, Phase 4).

## Carrier Requirement

A **carrier** is the place a deferred point is written down so it can be found again. Every point a
PR consciously leaves open needs one **before the PR gets a positive closing verdict** — an
approval, a "looks mergeable" comment or a sentence in chat all count, whatever the channel. See
also `pr-poll-review`, Phase 4, the carrier gate.

- **Everything buildable is built; only what is not buildable is carried.** A point is
  **buildable** when it can be implemented in this repository and needs no open decision of the
  maintainer. "Outside the PR's scope" is no reason to carry a buildable point: it becomes its own
  PR. A work limit sets only the order, never the scope — a buildable point waiting for its turn
  is work, not a deferral, and is built. Its line carries the fixed form
  `**Eigener PR:** <owner/repo#N>`, where `#N` is the open PR or the open tracking issue that
  commissions the work — never a session name. A reviewer checks that the target exists and is
  open; a line without one is a deferral. The one scheduled form without a target is the doc
  catch-up: a `backlog.md` line the next state audit works off (`.agents/rules/docs.md`
  § "Documentation").
- **Exactly three cases are not buildable**, each with its own handling:
  1. **Implementable only in a foreign repo** — an issue there; here a carrier line in the fixed
     form `**Nur im Fremd-Repo:** <owner/repo#N>`, linking that issue; and a report to the
     maintainer (in controller mode through the orchestrator, where one steers the controllers).
  2. **No fix known** — only after documented research, sources named: the fixed form
     `**Kein Fix bekannt:** <reason with sources>`.
  3. **Needs a decision of the maintainer** (direction, scope, a break) — no carrier line, which
     would only lie there, but a question to the maintainer; in controller mode to the controller
     (`.agents/rules/pr.md` § "PR Lifecycle", subsection "Controller Mode").
- **Valid carriers:** the design's open **tracking issue** (§ "Tracking Issue"); a line in
  `roadmap.md` or `backlog.md`; and, for a point implementable only in a foreign repo, an issue in
  that repo (next bullet). What they share is that someone goes through them again — the state
  audit walks them before every slice.
- **A point implementable only in a foreign repo is carried by an issue in that repo.** That issue
  is the carrier; this repo only links it — a repo that cannot fix a point does not carry it. Like
  any carrier issue, it must be open.
- **A missing `backlog.md` is never a reason to leave a point uncarried.** Where the repo has none
  yet, the PR contributing the first line creates it (`.agents/rules/docs.md` § "Documentation").
  The clause is repeated here because this is the section someone reads while deferring a point,
  and the other one is the section they read while writing docs.
- **Not carriers:** the PR body, a review comment, an issue comment, a chat — **nor a decision
  log**, **nor the task spec file** (`.agents/rules/pr.md` § "Task Spec"). A merged PR body is an
  archive nobody reads back; a decision log is the record of one day, read for the why, never as a
  list of what is left; a spec file is opened again by nobody after the merge, and its finished
  items make the whole file look finished. An obligation held in a log gets a tracking-issue line
  or a backlog line in addition. Naming a point is not carrying it.
- **A `[geplant]` / `[teilweise]` marker is not a carrier either** — it is a target-vs-actual
  display at the place of the statement (`.agents/rules/docs.md` § "Target vs. Actual"). It used to
  be the third entry in the list above. This revises decision N1 of the playbook's own carrier
  round of 2026-08-06
  ([`docs/decisions/2026-08-06T1930-playbook-traeger-pflicht-decisions.md`](https://github.com/ww3d/playbook/blob/main/docs/decisions/2026-08-06T1930-playbook-traeger-pflicht-decisions.md)),
  which had put the markers into the list deliberately. **A marker is covered once its point stands
  at any valid carrier** from that list — an open tracking issue, a `roadmap.md` / `backlog.md`
  line, an issue in the foreign repo. Only a marker at no carrier at all is a finding, and the state
  audit carries it to one: the tracking issue of the slice that makes it due, otherwise
  `roadmap.md` / `backlog.md`, and for a point implementable only in a foreign repo an open issue
  there — never the tracking issue of a design it does not belong to, whose body would become a
  dump the next design round reads as an order.
- **A carrier issue must be open.** A closed one is the worst carrier there is: it looks like a
  finished one. Roadmap / backlog lines hold no state — they count until the point is struck
  through.
- **A carrier line names the state of the mechanism, not only that of its guard.** Test question:
  *does the thing this line is meant to guard exist?* A line that describes the gap as a missing
  guard over a present mechanism, while the mechanism itself is missing, meets every other rule
  here and still misleads every later reading.
- **Who writes it:** the dev, in the same PR. Only where the PR touches none of those files does
  the reviewer file it instead.
- **A gap in a file the PR itself creates or changes, with a known fix, is not deferred — it is
  fixed in the PR.** Whatever it is written into — the tracking issue's body, a `roadmap.md` line, a
  `backlog.md` line — it is then no carrier but a **moved fix**: a buildable gap in untouched code
  becomes its own PR, a gap in code the PR is already editing is in scope right now, and writing
  it down instead of fixing it is the deferral these rules exist to prevent, wearing a carrier's
  shape. A review-wave cap limits the waves, never the fixing. A carrier line for a file of the PR
  is valid only in one of the fixed forms above — `**Kein Fix bekannt:**`, `**Nur im Fremd-Repo:**`
  or `**Eigener PR:**` —, and a reviewer checks the reason, that the fix really lies only in the
  named repo and its issue is linked, or that the named PR or tracking issue exists, is open and
  commissions the work. The review side — label and hardness — stands in
  `.agents/rules/review.md` § "Review Comments".
- **Handing a point to a future slice counts only once it stands at the destination** — that
  slice's tracking issue or its `roadmap.md` line. A sentence in the sender's PR body is a note to
  nobody: the receiver reads its own issue, not foreign PR bodies. If the destination does not
  exist yet, the point goes to `backlog.md`, never to a slice nobody has heard of.
- **Before closing an issue, check what points to it — two checks, plus a third for a playbook.**
  A `Closes #N` in a PR body closes without ever running any of them, which is why the keyword is
  conditional on an issue with a checklist (§ "Tracking Issue").
  1. **Checkboxes against the other carriers.** Every open point this issue's body carries is moved
     to another carrier first, or explicitly recorded as resolved with it.
  2. **The issue's name, searched across the whole repository.** This finds what the checkbox check
     cannot: a place that *names* this issue as its carrier without being a checkbox in its body.
     The distinction that matters here is mechanical: a **quotation** ("the finding `#36` lists
     under Z4") is not a carrier; a **carrier formula** ("carried in", "point in", "carrier line …
     and point in") is one.
  3. **Where other repositories consume this one as their playbook, their `CLAUDE.md` exceptions
     bound to the issue** ("until #N", "bis #N"). Check 2 searches only this repository and never
     finds them. Each is checked against the close: the exception falls with it, or it names the
     carrier it now waits for.
- **No marker without a number.** A `TODO`, `HACK`, or `FIXME` — in code or in the prose of a
  source-of-truth document — carries a reference to an open carrier. Where the caveat qualifies a
  statement in a source-of-truth document, it belongs **on that statement**, not in a follow-up
  document.
- **A `nitpick:` is not an open point** (`.agents/rules/review.md` § "Review Comments"). It blocks
  nothing and gets no carrier — it is fixed or dropped.

Known gap: nothing enforces the closing rule mechanically. The periodic sweep over all carrier
links is carried as a line in the playbook's own `backlog.md` (the periodic `sweep-carriers.ps1`
run) and still waits for the org CI — the sweep script itself is built
(`scripts/common/sweep-carriers.ps1`) and wired into the state audit; only the recurring,
unattended run is still open. Points deferred before this rule existed are no longer part of
that gap: the state audit walks the tracking issues and the markers before every slice
(`.agents/rules/audit.md` § "State Audit"), which is what the sweep was deferred for.
