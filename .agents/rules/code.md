---
trigger: code
read-before: writing code
---

Read before: writing code

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## Code Conventions

Detail per stack lives in the tech overlay; these size limits are cross-stack.

- **Class size.** Guideline ~150-200 lines, hard cap 300. Beyond 300 only with a justification in
  the PR body, otherwise blocked.
- **Responsibility axis** (independent of the line count). Blocked also above ~15 instance fields
  or more than one clear responsibility — this is the real God-class catcher; a mechanical file
  split does not evade it.
- **Exception.** Pure schema / DTO / config classes and stateless helpers are exempt from the line
  limit — they grow through the number of independent records, not through coupling.
- **Method size.** Guideline ~30 lines. Two complexity measures: Cognitive Complexity ~15
  (C family incl. C# ~25) as the readability measure (punishes nesting); Cyclomatic Complexity
  guideline ~10, blocked from ~25, as the testability measure. Rule of thumb on top: deeply nested
  or hard to read → split.
- **Constructor.** Few parameters (~5); more → a parameter object. Collaborators behind an
  interface, not a bag of `Func<>` callbacks; no circular construction.

## Work Standard

Beyond the working mode in `AGENTS.md` § "Working Mode" — the bar for finished work:

- Grasp the full context before a design decision: docs, issues, PRs, backlogs, and the rejected
  approaches too; pull the related work into the same pass and reuse prior work.
- Cover every use case, including the ones you derive yourself; the result stays intuitive.
- No dead paths.
- Hot paths allocate nothing; measure, don't guess.
- Structured logging with no hot-path cost.
- Tests cover the happy path plus every edge case plus every error path.
- Autonomous through to completion; self-review and refactor rounds until clean.
