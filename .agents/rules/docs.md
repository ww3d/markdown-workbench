---
trigger: docs
read-before: touching a doc or a timestamped file
budgetTokens: 800
---

Read before: touching a doc or a timestamped file

## Documentation

Every doc change keeps the docs short, clear and factual — redundancy, filler and detours go, while
knowledge and clarity stay; terse and unambiguous over exhaustive.

**A PR pulls only the doc places its own diff would otherwise make untrue.** Everything else goes as
a line to `backlog.md`, created by the PR that adds its first line; in doubt, pull it in the same PR.

## Correcting a Value

**A correction sweeps for the old value before it sets the new one.** Before the fix run `git grep`
against the **old** value across the repository and give every hit an outcome — pulled, or left with
a reason — and show the sweep in the PR body: the command, its hit count before and after, the
reason per hit left. A hit inside an answer list or a literal quotation carries the old wording on
purpose and stays. Dated snapshots — `docs/audit/`, `docs/decisions/`, `docs/handoffs/`,
`docs/tasks/**` — are exempt.

## Target vs. Actual

An architecture / baseline doc is the target state; each of its statements carries a status marker
`[met]` / `[partial]` / `[planned]` / `[unverified]`, never actual state in prose. `[met]` needs
evidence — the architecture test where one exists, otherwise the latest state audit; a `[partial]`
names `missing:`. The rest of the marker grammar: `.agents/rules/audit.md` § "Status Markers".

## Timestamps in File Names

One format: `YYYY-MM-DDTHHMMZ`, UTC, read from the system clock, never estimated; the same stamp goes
into the file's metadata block. Not retroactive: existing files are not renamed.

## Language

- **English is mandatory for everything code, tools or sessions read:** code, comments,
  identifiers, file and folder names, markers, formats, schemas with their fields and values, line
  markers, fixed headings of a PR or issue body, `CLAUDE.md` field names, branch names, commit
  titles, PR and issue titles, and the like; such names stay ASCII in addition. The one exception:
  the review-loop messages of `.agents/rules/pr.md` § "Session Traffic" (the maintainer's wording).
- **German is mandatory** for the chat with the maintainer and for PR, issue and review bodies and
  comments, a script's posted text included — its markers and forms stay English; commit bodies
  may be German or English; one language per comment.
- German is allowed in `docs/` and user help texts where the repo's `CLAUDE.md` settles it;
  otherwise ask the maintainer when the text is first created.
- User-visible UI strings keep their umlauts.

## Local Rules

A consuming repo adds its own rules under `.agents/rules/local/` as `*.md` files with the same
frontmatter; the playbook sync never touches them. Only there a rule may add `gate: <trigger>[, ...]`,
naming triggers of the table in `AGENTS.md` § "Rule Files" whose actions the hook blocks until the
file is read. A tool's settings file belongs under `.agents/config/`.
