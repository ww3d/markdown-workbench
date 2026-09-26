---
trigger: audit
read-before: starting a new slice, running a state audit, or syncing from or diverging from a source
---

Read before: starting a new slice, running a state audit, or syncing from or diverging from a source

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## State Audit

- Before every new slice / phase, audit against the baseline doc: each statement checked against
  the code (`file:line`), the build, and the test actually run. `file:line` is the right form here:
  the audit names the commit it was taken at, which fixes the reference point the way a permalink
  does.
- **The audit also walks the tracking issues**, in both directions: a `[geplant]` / `[teilweise]`
  marker with no point at any valid carrier (`.agents/rules/carrier.md` § "Carrier Requirement"),
  and a point in a tracking issue with no marker or line behind it, are both findings.
- **Every mechanism marker is additionally held against the architecture section that governs it.**
  Confirming a marker against the code answers "was this built"; it does not answer "does what was
  built still do what the architecture document promises". A marker whose code contradicts its
  governing section is a delta entry, never `[erfuellt]` — counting it as fulfilled without that
  second check is how a relocated trigger or a narrowed guarantee survives an audit unnoticed.
  The check holds for `[teilweise]` and `[geplant]` too, not only against a too generous
  `[erfuellt]`: a marker that names a missing guard is checked for the mechanism under it, and
  where that is missing as well, the marker and its text are corrected
  (`.agents/rules/carrier.md` § "Carrier Requirement", `.agents/rules/docs.md` § "Target vs.
  Actual").
- **The trigger is mechanically checkable:** a **new tracking issue** makes the audit due. Further
  PRs on the same tracking issue do not. Checked over the file stamp of
  `audit/ist-stand-<YYYY-MM-DDTHHMMZ>.md` against the close of the preceding design.
- Record the result as `audit/ist-stand-<YYYY-MM-DDTHHMMZ>.md` on its own branch
  (`.agents/rules/docs.md` § "Timestamps in File Names"). Mechanics: the `state-audit` skill.
- **The audit head is mandatory session reading**, so the audit file leads with it: the metadata
  block, then a short-form section as the FIRST section after it. `AGENTS.md` § "Session Start:
  Read Before Anything Else" reads that head and nothing further, so an audit that buries its
  result behind the per-statement detail is an audit nobody reads.
- The audit is also where the deferred documentation catch-up in `backlog.md` is worked off
  (`.agents/rules/docs.md` § "Documentation").
- **The audit also walks the repo's own divergences** (§ "Divergences From a Source").

## Divergences From a Source

A **divergence** is a place where the repo deliberately departs from a source it otherwise follows:
an upstream it syncs or vendors from, a template it was built from, or the playbook itself (a
project-specific override in `CLAUDE.md`). Its reason stands beside it, or in the evidence document
a comment there points to (`.agents/rules/code.md` § "Code Comments").

- **A divergence is checked for "the reason holds at the head", not for "a reason is there".**
  Every state audit, and every sync that brings a new state of the source into files carrying
  divergences, walks the repo's own divergences and gives each one outcome: `gilt`,
  `gilt nicht mehr` or `nicht pruefbar`. The outcome is measured, or shown at
  the code — never read off the reason's wording. A reason describes a state; the state can go away
  while the sentence stays, and a check for presence passes it on every sync after that.
- **`gilt nicht mehr` is a finding.** The divergence goes back to the source's form, or gets a
  reason that holds today — in the same pass where it touches the files anyway, otherwise at a
  carrier (`.agents/rules/carrier.md` § "Carrier Requirement").
- **`nicht pruefbar` names why** — a foreign system out of reach, a state this repo cannot see —
  and never counts as `gilt`.
- **A reason bound to a state names the state that lifts it:** a carrier (`until #N`) or a
  checkable condition (`until <property> is set at this point of evaluation`). "Not yet", "for
  now", "until X works" alone tell the next audit neither what to look at nor when — the same gap
  a `TODO` without a number leaves (`.agents/rules/carrier.md` § "Carrier Requirement"). A reason
  meant to hold for good says `permanent`, as a folder exception does (`.agents/rules/code.md`
  § "Folder Conventions").
