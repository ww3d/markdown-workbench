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

## Code Comments

`AGENTS.md` § "Always" says what gets documented; this section bounds how a comment reads.

- **Short why.** A comment says briefly why the code is as it is — guideline 1–3 lines. A longer
  rationale lives in the evidence document (decision log, architecture or upstream doc); the
  comment points there and does not restate it.
- **No history.** No review rounds or finding numbers, no "this used to be …", no quotes of earlier
  states — git history and the decision log carry how the code got here. A pointer to a decision
  or a carrier (`TODO #N`) is not history. A review round that lengthens a comment is the wrong
  fix: shorten it, or move the reasoning to the evidence document.
- **Line limit: 120 characters** for every line that carries a comment, indentation included. The
  stack overlay names the tool that checks it; where no tool can, the review check point in
  `pr-poll-review` carries it.
- **Exception: upstream comments taken over verbatim** — code synced or vendored from another
  project and kept comparable with its source. Rewriting them breaks that comparison on the next
  sync. The exception covers the verbatim text only; a comment of our own beside it follows this
  section.

## Folder Conventions

Detail per stack lives in the tech overlay; these five rules are cross-stack.

1. **Folders are named for the subject, never the technical role.** Default ban-list: `Services`,
   `Helpers`, `Utils`, `Models`, `Interfaces`, `Extensions`, `Common`, `Misc`, `Shared`. `Tenancy/`,
   `Dispatch/`, `Status/`, `Planning/` instead of `Services/`. Exceptions are allowed but cost a line
   in the exception file (below).
2. **No sediment.** The top level of a project/module carries only files that concern the whole
   (entry point, DI/module root, project/manifest file). Hard cap **three**; everything else lives
   in a folder.
3. **Namespace equals path**, without exception, wherever the language has a namespace concept.
4. **The test project mirrors — in both directions.** Every product folder gets a same-named test
   folder, **and** no test folder exists without a product-folder counterpart. The second direction
   is the one nobody measures, and it is the more interesting failure: a test folder with no
   product counterpart means the code moved and the tests stayed, which is exactly the state where
   a test checks the wrong thing and still passes.
5. **Folder size guideline**, soft, ~15 files, analogous to the class-size guideline. Beyond it:
   split, or justify in the PR body.

**Exceptions live in one file per repo, never in comments.** The ban-list, its exceptions, and the
sediment cap stand together in one file; an exception then costs a visible diff line instead of
disappearing into a comment — the same mechanic as a dependency-direction allow-matrix. **Every
exception carries a resolution note** — a carrier reference, or the word `permanent` — without
which the list is an eternity guarantee instead of a tracked one. Applying the rule to an existing
tree rather than only the diff is the repo's own call: a permanently red gate teaches everyone to
ignore it.

## Work Standard

Beyond the working mode in `AGENTS.md` § "Working Mode" — the bar for finished work:

- Grasp the full context before a design decision: docs, issues, PRs, backlogs, and the rejected
  approaches too; reuse prior work.
- **Pull related work into the same pass only with proximity — the same files or the same
  mechanism.** This is the resolution of an apparent conflict with `AGENTS.md` § "Simplicity"
  ("don't refactor adjacent code"): proximity is the dividing line between the two, not a judgement
  call each time. In-scope means: touched in its own commits, listed in the PR body under
  "Mitgenommen". Pulling in unrelated work "while we're at it" is what § "Simplicity" forbids —
  bycatch without proximity makes PRs large and review waves expensive.
- Cover every use case, including the ones you derive yourself; the result stays intuitive.
- No dead paths.
- Hot paths allocate nothing; measure, don't guess.
- Structured logging with no hot-path cost.
- Tests cover the happy path plus every edge case plus every error path.
- Autonomous through to completion; self-review and refactor rounds until clean.
