---
trigger: evidence
read-before: claiming something is done, green, or measured
budgetTokens: 1100
---

Read before: claiming something is done, green, or measured

## Evidence Requirement

- **Evidence is owed only for what the reader cannot see in the diff** — test runs, benchmarks,
  "not verified"; what stands in the diff is proven by it, and a second prose description only drifts.
- Every claim of "built / done / verified / green / fast" carries a **stable anchor**, repo-internal
  first: a test or `It` name, a function, symbol or variable name, a comment heading, a relative path
  — found at the head with `git grep`, surviving squash, branch deletion and a change of forge.
- A permalink pinned to a commit SHA only where nothing repo-internal exists, and knowingly
  perishable: a migration does not carry PR refs, and their commits stop resolving.
- **A link into a branch ref is never evidence** — it dies with the branch. A bare `file:line`
  against a moving head is none either: every push shifts the line, and the reviewer then checks the
  wrong code. `file:line` holds where the
  reference point is fixed, in a SHA permalink or an audit that names its commit.
- **Anchor quick reference.** Valid: `TestName`, `MethodName`, `src/Foo.cs`;
  `https://github.com/<owner>/<repo>/blob/<sha>/src/Foo.cs#L142` where nothing else exists. Invalid:
  `Foo.cs:142`, any `.../blob/<branch>/...` or `.../tree/<branch>/...`.
- **An anchor is resolved, not just read:** file names against `git ls-files`, symbols and tests
  against `git grep`, both at the commit state — a file that ran but was never committed carries no
  repeatable test, however well its name is spelled. The form check alone produces a feeling of
  thoroughness and catches none of this class.
- Facts from three sources (`AGENTS.md` § "Working Mode"): two agreeing against the third is the
  finding, not a rounding error.
- Whatever did not really run (missing Docker, CLI, CI, hardware) is declared "not verified".
- **A negative claim needs a contrasting case** — a place where it does happen, or the check that
  would have shown it; without one the claim is only the original observation in larger type —
  **documented with its hit count:** a contrast that also returns 0 shows a
  broken measurement (encoding, quoting, the pipeline), and the second number is what makes the first
  readable.
- **Check the place, not the count:** a hit counts as an occurrence only once read at its place and
  not inside an answer list that carries the old wording on purpose. Correcting a statement that was
  right is worse than leaving the search unrun.
- Performance claims carry a benchmark reference.
