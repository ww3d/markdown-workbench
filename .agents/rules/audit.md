---
trigger: audit
read-before: starting a new slice or design round, running a state audit, or syncing from or diverging from a source
budgetTokens: 2100
---

Read before: starting a new slice or design round, running a state audit, or syncing from or diverging from a source

## State Audit

### Quick Check

Before every design round, the quick check runs the existing scripts — the audit work list, the
carrier sweep, the closable issues — and its result goes into the design's decision log as one line,
with no PR of its own. Mechanics: the `state-audit` skill.

### Full Audit

**A full audit is due only when** (a) the repo has none yet, (b) the design changes code the
architecture / baseline document describes, or (c) more than 30 PRs were merged since the last full
audit — a repo sets its own threshold in `CLAUDE.md` (`Audit-Schwelle: <N>`).
`pwsh scripts/common/get-audit-due.ps1` computes the three conditions with their figures; without
the script, count the merged PRs since the commit the latest audit names and check (a) and (b) by
hand.

- Each baseline statement is checked against the code (`file:line` — the audit names its commit, which
  fixes the reference point like a permalink), the build and the test actually run.
- **The audit walks the tracking issues in both directions:** a `[geplant]` / `[teilweise]` marker
  with no point at a valid carrier, and a tracking-issue point with no marker or line behind it, are
  both findings (`.agents/rules/carrier.md` § "Carrier Requirement").
- **Every mechanism marker is also held against the architecture section that governs it.** The code
  answers "was this built", not "does it still do what the architecture promises"; a marker whose code
  contradicts its section is a delta entry, never `[erfuellt]` — counting it as fulfilled without that
  second check is how a relocated trigger or a narrowed guarantee survives an audit unnoticed. This
  holds for `[teilweise]` and
  `[geplant]` too: under a marker naming a missing guard the mechanism is checked, and where it is
  missing as well, marker and text are corrected (`.agents/rules/docs.md` § "Target vs. Actual").
- The result is `audit/ist-stand-<YYYY-MM-DDTHHMMZ>.md` on its own branch
  (`.agents/rules/docs.md` § "Timestamps in File Names"); it leads with the metadata block, then a
  short-form section — the **audit head** every session reads (`AGENTS.md` § "Session Start: Read
  Before Anything Else"), so the result sits up front: an audit that buries it behind the
  per-statement detail is an audit nobody reads.
- The audit works off the doc catch-up lines in `backlog.md` (`.agents/rules/docs.md`
  § "Documentation"); a backlog line ages by time or by merged PRs since it was written, not by audit
  stamps.
- **The audit walks the repo's own divergences** (§ "Divergences From a Source").

## Design Round

- References the maintainer or the task names are read **in full before the first question**, and
  the decision log lists them.
- Sister repos are searched for the same mechanism before a new one is designed.
- Parallel PRs from one round get fixed ranges for IDs, diagnostic codes and numbers in the design,
  so no two hand out the same one.
- Where a decision log already decided, the work follows it without a new round.
- The round's points — accepted, rejected, deferred, replaced, ideas — go into its ledger file; a
  point already rejected is reopened only with a new argument (`scripts/common/get-rejected-points.ps1`).
- A design statement about platform rights or behaviour is checked against the code or the vendor's
  documentation before anyone agrees to it.

## Divergences From a Source

A **divergence** is a place where the repo deliberately departs from a source it otherwise follows —
an upstream it syncs or vendors from, a template it was built from, or the playbook (a
project-specific override in `CLAUDE.md`). Its reason stands beside it or in the evidence document a
comment points to (`.agents/rules/code.md` § "Code Comments").

- **A divergence is checked for "the reason holds at the head"**, not for "a reason is there". Every
  state audit, and every sync bringing a new state of the source into files with divergences, walks
  them and gives each `gilt`, `gilt nicht mehr` or `nicht pruefbar` — measured or shown at the code,
  never read off the reason's wording: the state can go while the sentence stays, and a check for
  presence passes it on every sync after that. A sync also reads
  the source's delta itself, not only the folders it copies.
- **`gilt nicht mehr` is a finding:** back to the source's form, or a reason that holds today — in
  the same pass where it touches the files anyway, otherwise its own PR, at a carrier only where not
  buildable.
- **`nicht pruefbar` names why** (a foreign system out of reach, a state this repo cannot see) and
  never counts as `gilt`.
- **A reason bound to a state names what lifts it:** a carrier (`until #N`) or a checkable condition.
  "Not yet", "for now", "until X works" tell the next audit neither what to look at nor when; a reason
  meant for good says `permanent`, as a folder exception does.
