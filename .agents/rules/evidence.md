---
trigger: evidence
read-before: claiming something is done, green, or measured
budgetTokens: 450
---

Read before: claiming something is done, green, or measured

## Evidence Requirement

- Every claim of "built / done / verified / green / fast" carries a **stable anchor**, repo-internal
  first: a test or `It` name, a function, symbol or variable name, a comment heading, a relative path.
- A permalink pinned to a commit SHA only where nothing repo-internal exists.
- **A link into a branch ref is never evidence**, nor a bare `file:line` against a moving head.
  `file:line` holds where the reference point is fixed, in a SHA permalink or an audit that names its
  commit.
- **An anchor is resolved, not just read:** file names against `git ls-files`, symbols and tests
  against `git grep`, both at the commit state.
- **A negative claim needs a contrasting case** — a place where it does happen, or the check that
  would have shown it — **documented with its hit count.**
- **Check the place, not the count:** a hit counts as an occurrence only once read at its place and
  not inside an answer list that carries the old wording on purpose.

## Facts and Real Runs

- **Facts from three sources.** Before any factual statement — numbers, field names, rules, APIs —
  hold it against target (docs), actual (code) and why (decisions, issues, PRs); never from one.
  Unsourced means unwritten. Being sure is the reason to look it up, not the reason to skip it.
- **Every probe, measurement or run a session starts ends by itself:** under a time limit
  (`timeout <s>`, `Wait-Process -Timeout`, a tool's `--timeout`), with any wrapper ending with its
  child; nothing is ended by number afterwards. From Git Bash, `cmd //c start //affinity <mask>
  //wait //b <command>` takes no `""` title.
