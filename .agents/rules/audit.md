---
trigger: audit
read-before: starting a new slice, or running a state audit
---

Read before: starting a new slice, or running a state audit

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## State Audit

- Before every new slice / phase, audit against the baseline doc: each statement checked against
  the code (`file:line`), the build, and the test actually run. `file:line` is the right form here:
  the audit names the commit it was taken at, which fixes the reference point the way a permalink
  does.
- **The audit also walks the tracking issues**, in both directions: a `[geplant]` / `[teilweise]`
  marker with no point in a tracking issue, and a point in a tracking issue with no marker or line
  behind it, are both findings.
- **Every mechanism marker is additionally held against the architecture section that governs it.**
  Confirming a marker against the code answers "was this built"; it does not answer "does what was
  built still do what the architecture document promises". A marker whose code contradicts its
  governing section is a delta entry, never `[erfuellt]` — counting it as fulfilled without that
  second check is how a relocated trigger or a narrowed guarantee survives an audit unnoticed.
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
