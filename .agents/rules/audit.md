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
- **The trigger is mechanically checkable:** a **new tracking issue** makes the audit due. Further
  PRs on the same tracking issue do not. Checked over the file stamp of
  `audit/ist-stand-<YYYY-MM-DDTHHMM>.md` against the close of the preceding design.
- Record the result as `audit/ist-stand-<YYYY-MM-DDTHHMM>.md` on its own branch
  (`.agents/rules/docs.md` § "Timestamps in File Names"). Mechanics: the `state-audit` skill.
- **The audit head is mandatory session reading**, so the audit file leads with it: the metadata
  block, then a short-form section as the FIRST section after it. `AGENTS.md` § "Session Start:
  Read Before Anything Else" reads that head and nothing further, so an audit that buries its
  result behind the per-statement detail is an audit nobody reads.
- The audit is also where the deferred documentation catch-up in `backlog.md` is worked off
  (`.agents/rules/docs.md` § "Documentation").
