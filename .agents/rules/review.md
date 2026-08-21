---
trigger: review
read-before: posting a review
---

Read before: posting a review

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## Review Comments

Review points use **Conventional Comments** — the labels and the `(blocking)` / `(non-blocking)`
decorations, verbatim as the specification defines them. The labels stay English even in a German
review body (`AGENTS.md` § "Language": reference identifiers are quoted, not translated).

| Label | When |
|---|---|
| `issue: (blocking)` | a clear defect with an unambiguous correction |
| `nitpick: (non-blocking)` | polish, wording, style |
| `question: (blocking)` | the maintainer has to decide: scope, deviation from the source, breaking change, naming, posting something outward |
| `question: (non-blocking)` | the reviewer's comprehension question |
| `suggestion: (non-blocking)` | an alternative the author may take or leave |

The dividing line is not importance but **who has to answer**.

- **A `nitpick:` never blocks** — neither the closing verdict nor the merge — and needs no carrier.
- **Every `nitpick:` is posted as a suggested change**, not as prose. A nit that cannot be phrased
  as a suggestion is not one: then it is an `issue:` or a `suggestion:`.
- **Approval standard:** approve as soon as the PR clearly improves the state — not only once
  there is nothing left to find.
- **Out of scope does not block.** A concern about code outside the PR's scope becomes a separate
  task and does not hold up the running PR; it goes to the tracking issue or to `backlog.md`.
- **A finding whose fix moves what the architecture document governs is not decided on the way.** It
  goes to the maintainer as a `question: (blocking)` — also where it would be declared in the PR
  body, and also where the fix is obviously right. An entry in a PR body is a report, not a
  decision: nobody has to answer it, and the document it contradicts does not move because a PR
  mentioned it. This covers the case the rules were missing, the finding from your **own** review
  wave — "autonomous through to completion" (`.agents/rules/code.md` § "Work Standard") ends at a
  statement someone else owns. **It applies only where the architecture document governs the
  affected statement.** A fix inside what the architecture leaves open runs through autonomously;
  the distinction is checkable at the document, not by feel.
