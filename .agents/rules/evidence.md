---
trigger: evidence
read-before: claiming something is done, green, or measured
---

Read before: claiming something is done, green, or measured

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## Evidence Requirement

- **Evidence is owed only for what the reader cannot see in the diff** — test runs, benchmarks,
  "not verified". What stands in the diff is proven by the diff and needs no anchor; a second prose
  description of the same change is only a place for the two to drift apart. Where evidence *is*
  owed, the rest of this section defines its form.
- No claim of "built / done / verified / green / fast" without a **stable anchor**. Repo-internal
  anchors come first: a test / `It` name, a function or symbol name, a variable name, a comment
  heading, a relative path. They are found at the head with `git grep` and survive squash, branch
  deletion, migration and a change of forge.
- A permalink pinned to a commit SHA only where nothing repo-internal exists — and then knowingly
  as a perishable anchor: it depends on the forge keeping the object. A migration does not carry
  the PR refs along, and the commits behind them stop resolving.
- **A link into a branch ref is never evidence.** It dies with the branch, and the branch is
  deleted on merge.
- A bare `file:line` relative to a moving branch head is **not** evidence: every push in the review
  cycle shifts the line, and the reviewer then checks the wrong code. `file:line` stays valid where
  the reference point is fixed — as part of a SHA permalink, or in a state audit that names
  its commit.
- **Anchor quick reference.** Valid: `TestName`, `MethodName`, `src/Foo.cs` as a path;
  `https://github.com/<owner>/<repo>/blob/<sha>/src/Foo.cs#L142` where nothing else exists.
  Invalid: `Foo.cs:142`, and any link into a branch
  (`.../blob/<branch>/...`, `.../tree/<branch>/...`).
- **Form is not existence — the anchor is resolved, not just read.** An anchor can be formally
  flawless and point at nothing. File names go against `git ls-files`, symbol and test names against
  `git grep`, both **at the commit state**, never in the working tree: a file that ran but was never
  committed carries no repeatable test, however correctly its name is spelled. The form check alone
  produces a feeling of thoroughness and catches none of this class.
- **No factual claim from a single source.** Hold every one against all three: target (the docs),
  actual (the code), and why (decision logs, issues, PRs). Two of them agreeing against the third
  is the finding, not a rounding error.
- Whatever did not really run (missing Docker / CLI / CI / hardware) is declared "not verified"
  explicitly, never glossed over.
- **A negative claim needs a contrasting case.** "X happens nowhere", "that no longer runs" — name
  a case where it does happen, or the check that would have shown it. Without one the claim is only
  the original observation in larger type.
- **The contrasting case is documented with its hit count.** A contrast that returns 0 as well
  relieves nothing — it shows a broken measurement, and "0 hits" out of one is a correct conclusion
  from an unusable search. Encoding, quoting and the pipeline the search ran through all break it
  silently; the second number is what makes the first one readable.
- **Check the place, not the count.** A search does not distinguish an occurrence from a quotation.
  In a document that answers its own findings, the answer list carries the old wording on purpose,
  as proof of the correction — so a hit counts as an occurrence only once it has been read at its
  place and does not stand in that answer list. Correcting a statement that was right is worse than
  leaving the search unrun.
- Performance claims need a benchmark reference.
