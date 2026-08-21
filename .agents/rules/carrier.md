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
  one place where the auto-close footer from `.agents/rules/pr.md` § "PR / MR Description" is
  conditional.
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
  be the third entry in the list above; the state audit now carries every marked point into the
  tracking issue, which is the one place a point can be counted. This revises decision N1 of the
  carrier round of 2026-08-06
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
- **A `nitpick:` is not an open point** (`.agents/rules/review.md` § "Review Comments"). It blocks
  nothing and gets no carrier — it is fixed or dropped.

Known gap: nothing enforces the closing rule mechanically. The periodic sweep over all carrier
links is tracked in `ww3d/playbook#158` and still waits for `iris.ci`. Points deferred before this
rule existed are no longer part of that gap: the state audit walks the tracking issues and the
markers before every slice (`.agents/rules/audit.md` § "State Audit"), which is what the sweep was
deferred for.
