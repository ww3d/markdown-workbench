---
trigger: review
read-before: posting a review
budgetTokens: 1500
---

Read before: posting a review

## Review Comments

Review points use **Conventional Comments** — labels and the `(blocking)` / `(non-blocking)`
decorations verbatim (language: `AGENTS.md` § "Language").

| Label | When |
|---|---|
| `issue: (blocking)` | a clear defect with an unambiguous correction |
| `nitpick: (non-blocking)` | polish, wording, style |
| `question: (blocking)` | the maintainer has to decide (the list in `.agents/rules/pr.md` § "Controller Mode") |
| `question: (non-blocking)` | the reviewer's comprehension question |
| `suggestion: (non-blocking)` | an alternative the author may take or leave |

The dividing line is **who has to answer**, not importance.

- **A `nitpick:` never blocks** — neither verdict nor merge — needs no carrier, and is posted as a
  suggested change; a nit that cannot be phrased as one is an `issue:` or a `suggestion:`.
- **Approve as soon as the PR clearly improves the state**, not only once nothing is left to find.
- **Out of scope does not block, and is built, not carried** (`.agents/rules/carrier.md`
  § "Carrier Requirement").
- **A moved fix is always an `issue: (blocking)`, at every carrier:** a line the PR adds to a
  carrier for a gap in a file the same PR creates or changes. A line in one of the three carrier
  line forms (`.agents/rules/carrier.md` § "Carrier Requirement") is not blocking by itself — its
  reason and sources, the linked foreign issue, or the open target are checked; a fix known after
  all, or a missing or closed target, makes it a moved fix again.
- **A change of behaviour without its doc delta is an `issue: (blocking)`:** where the diff changes
  what a doc of the repo describes and leaves that doc as it was.
- **A finding whose fix moves what the architecture document governs is never decided in the
  review** — moving what an architecture document governs is a design decision, not a review
  verdict. Not as a `question:` on the PR either: it goes, without label, to the maintainer or
  controller as the trigger for a design round (`ccweb-prompt`), and no positive verdict comes until
  that round has decided — approving or merging while the contradiction stands would ship exactly
  what this rule exists to stop. Your own review wave included, however obvious the fix looks:
  "autonomous through to completion" (`.agents/rules/code.md` § "Work Standard") ends at a statement
  someone else owns. It applies only where the architecture document governs the statement —
  checkable at the document; inside what the architecture leaves open the fix runs through.
- **Same account as the author:** every point that would default to "leave open" goes to the human
  as a question — in controller mode to the controller —, since the same account deciding both
  sides of that default is the self-approval failure the role split exists to prevent; the verdict
  is a comment review (`event: COMMENT`) carrying `Review-Verdict: approve <sha>` (the earlier
  `Review-Verdikt:` is read until playbook 25.0.0) instead of an approve, and whoever merges runs
  the merge gate with `-SameAccount` (`.agents/rules/pr.md` § "Accounts per Seat").
- **A push after the approve dismisses it** where the ruleset says so: suggestions are applied
  before the approve, and before the last approve the branch is checked for `behind`.
- **A review is posted only after `pr-poll-review` ran for exactly the PR's current head, and once
  released:** after that run the addressee of the report (`.agents/rules/pr.md` § "Controller
  Sessions"), without a controller the maintainer in the chat, releases it — a clean round's comment
  review excepted (`.agents/rules/pr.md` § "Round Ledger"). In Claude Code
  `require-rule-read.sh` enforces the run on the current head; without hooks the reviewer checks it
  before posting. The release no hook checks — the reviewer waits for it and checks its sender.
- **The reviewer's model follows `AGENTS.md` § "Models"** in every review mode.
- **The author does not scope the review** — no backlog line or other means defines what the
  reviewer skips.
