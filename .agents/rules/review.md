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
  task and does not hold up the running PR; it goes to a valid carrier — the tracking issue, a
  `roadmap.md` / `backlog.md` line, or an issue in the foreign repo (`.agents/rules/carrier.md`
  § "Carrier Requirement").
- **A `backlog.md` line the PR itself writes for a gap in a file that same PR creates or changes is
  not a carrier — it is a moved fix.** A gap in untouched code is legitimately deferred; a gap in code
  the PR is already editing is in scope right now, and writing a backlog line for it instead of
  fixing it is the deferral this playbook's carrier rules exist to prevent, wearing a carrier's
  shape. Always an `issue: (blocking)`.
- **A finding whose fix moves what the architecture document governs never gets decided inside the
  review.** It does not become a `question: (blocking)` on the PR — an architecture contradiction
  found in review goes back into a design round (`ccweb-prompt` § "Design-Runde"), because moving
  what an architecture document governs is a design decision, not a review verdict. This holds
  even where the fix looks obviously right and even where it surfaces from your **own** review
  wave — "autonomous through to completion" (`.agents/rules/code.md` § "Work Standard") ends at a
  statement someone else owns. **It applies only where the architecture document governs the
  affected statement.** A fix inside what the architecture leaves open runs through autonomously;
  the distinction is checkable at the document, not by feel. **The finding goes to the
  maintainer or controller with no label**, as the trigger for a design round — not posted on the
  PR as a `question:` — and **no positive closing verdict until that round has decided**: approving
  or merging while the contradiction stands unresolved would ship exactly what this rule exists to
  stop.
- **Same account as author and reviewer.** Where the reviewing session shares its account with the
  PR's author, every point that would otherwise default to "leave open" is instead put to the
  human as a question — never pre-set to leave-open, because the same account deciding both sides
  of that default is the self-approval failure this playbook's role split exists to prevent. In
  controller mode (`.agents/rules/pr.md` § "PR Lifecycle", subsection "Controller Mode") the
  controller is that addressee.
- **Reviewer model differs from author model, in every review mode** — `hard`, `light`, and `soft`
  alike, not only the modes that already ran a second pass. A reviewer on the same model as the
  author shares its blind spots; the author cannot define, via a backlog line or otherwise, what the
  reviewer skips checking.
