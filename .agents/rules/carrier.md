---
trigger: carrier
read-before: deferring a point, or setting a closing keyword
budgetTokens: 4000
---

Read before: deferring a point, or setting a closing keyword

## Tracking Issue

- **Every open point of the design stands in the tracking issue's body** — one list; deferring a
  point means editing that body.
- **Delivering ticks it off, in the same PR that delivers it** — the spec file ticks the `REQ`, the
  issue body ticks the point.
- **Edit the body from a shell with `scripts/common/edit-issue-body.ps1`** — one tick or one
  section, every other byte unchanged. Through the forge connector, compare the body before and
  after: only the intended place differs.
- **`Closes #N` on an issue with a checklist only once its body has no unticked box left;** while a
  point is open the PR names the issue without keyword. Where the boxes this PR ticks leave none
  unticked, the dev sets the `Closes #N` line, counted at the head on every round, once
  `scripts/common/find-closable-issues.ps1 -Repo <owner/repo> -Pr <n>` reports the issue `closable`.

## Carrier Requirement

A **carrier** is the place a deferred point is written down so it can be found again. Every point a
PR consciously leaves open has one before the PR gets a positive closing verdict.

- **A point is buildable** when this repository can implement it without an open decision of the
  maintainer. Every finding or piece of work that belongs to the order is built in the same PR; a
  finding unrelated to the order is its own PR, and the maintainer is told (`.agents/rules/pr.md`
  § "Controller Mode"). While it waits, its line reads
  `**Own PR:** <owner/repo#N>` — the open PR or open tracking issue that commissions it.
- **Exactly three cases are not buildable:**
  1. **Only in a foreign repo** — an issue there, here `**Foreign repo only:** <owner/repo#N>`, and
     a report to the maintainer.
  2. **No fix known** — after documented research: `**No known fix:** <reason with sources>`.
  3. **A decision of the maintainer** (`.agents/rules/pr.md` § "Controller Mode") — a question, not
     a line.
- **Valid carriers, listed only here:** the design's open tracking issue; a line in `roadmap.md`, or
  in `backlog.md` for what is not buildable and for the doc catch-up; for a foreign-only point an
  open issue in that repo.
- **No carrier:** the PR body, a review or issue comment, a chat, a decision log, the task spec file,
  a `[planned]` / `[partial]` marker, a hook's state file, a handover or plan file in a scratchpad.
  An obligation that stands only there gets a carrier line in addition.
- **A carrier line names the state of the mechanism, not only of its guard.**
- **A gap in a file the PR creates or changes, with a known fix, is fixed in the PR;** written into a
  carrier instead, it is a moved fix. For a file of the PR only the three line forms above are valid.
- **A point handed to a future slice counts once it stands at that slice's tracking issue or
  `roadmap.md` line;** without a destination it goes to `backlog.md`.
- **No marker without a number:** a `TODO`, `HACK` or `FIXME` in source-of-truth prose references an
  open carrier.
