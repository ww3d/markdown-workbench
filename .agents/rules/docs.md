---
trigger: docs
read-before: touching a doc or a timestamped file
budgetTokens: 2300
---

Read before: touching a doc or a timestamped file

## Documentation

Every doc change keeps the docs short, clear and factual — redundancy, filler and detours go, while
knowledge and clarity stay; terse and unambiguous over exhaustive. Prose in every Markdown file of
the repo is hard-wrapped at about 100 columns. Continuation lines of a list item hang under its
text column; code blocks, tables and links stay unbroken, even when longer.

**A spec or a review names every doc its change touches by name** — `architecture.md`,
`roadmap.md`, `backlog.md` and the rest — each as a point of its own: a collective formula ("pull
the docs") lets exactly the source fall through that nobody has in mind.

**A PR pulls only the doc places its own diff would otherwise make untrue.** Everything else goes as a
line to `backlog.md`, a valid carrier (`.agents/rules/carrier.md` § "Carrier Requirement"), created by
the PR that adds its first line. The catch-up runs bundled at the state audit
(`.agents/rules/audit.md` § "State Audit") — without that, the lines are a dump instead of a carrier; in
doubt, pull it in the same PR.

**A doc-only PR gets no review gate.** Where a diff touches only `docs/**` and root `*.md` other
than `AGENTS.md` and `CLAUDE.md` — no code, workflow, skill, rule file under `.agents/rules/**`
or `VERSION` — green gates are enough to merge, and a review may follow. While CI counts as dead the gates are the author's local run in the PR body
(`.agents/rules/pr.md` § "Test Runs"). Skills and rule files run the full lifecycle because they are
the ruleset agents execute: a wrong sentence in `docs/` breaks nothing, one in a skill or rule file
changes what every agent does.

Blocks that themselves contain triple-backtick fences get a four-backtick outer fence — in chat,
issue and PR bodies and docs alike; a triple outer fence closes at the first nested block.

## Correcting a Value

**A correction sweeps for the old value before it sets the new one.** A finding names where it was
noticed, but a number or commitment travels into reports, carriers, spec files and issue bodies, and a
fix that pulls only the named place leaves the rest provably wrong. Before the fix run `git grep`
against the **old** value across the repository and give every hit an outcome — pulled, or left with
a reason — and show the sweep in the PR body: the command, its hit count before and after, the reason
per hit left. A hit inside an answer list or a literal quotation carries the old wording on purpose,
as proof of the correction, and stays — a sweep without that distinction does the very harm the
neighbouring rule warns against (`.agents/rules/evidence.md` § "Evidence Requirement": check
the place, not the count). Dated snapshots — `audit/`, `docs/decisions/`, `docs/handoffs/`,
`docs/tasks/**` (a spec file holds the order as it stood in its round) — are exempt: a snapshot is
true to when it was taken.

## Target vs. Actual

- An architecture / baseline doc is the target state; actual state is never asserted in its prose.
- Every baseline statement carries a status marker: `[met]` / `[partial]` / `[planned]` /
  `[unverified]` (the earlier German markers are read until playbook 25.0.0), pointing at its
  evidence — the architecture test where one exists, otherwise the latest state audit. `[met]`
  needs evidence. A marker covers exactly one refutable statement — a statement with several is
  split until each part carries its own marker; an architecture or baseline doc carries no
  checkboxes — its markers carry the state.
- **`[unverified]`** is only for a statement this repo can neither prove nor disprove because
  it talks about a foreign repo (a pinned dependency, a sibling's architecture), named at the
  statement. On anything checkable from here, `[planned]` / `[partial]` say "not yet true"; this
  one says "not this repo's to say".
- **A `[partial]` names what is missing in the same statement:** `missing:` with the missing
  mechanism, optionally `present:` with the part that is there — after the marker, up to the next
  marker or the paragraph's end. Without `missing:` it is undetermined, the form in which a "not at
  all" survives. Splitting into `[met]` + `[planned]` stays allowed and is often better.
- **A marker may reference its carrier:** `[planned #45]`, `[planned roadmap]`, `[planned backlog]`,
  likewise for `[partial]`, and for a foreign issue `[planned <owner>/<repo>#12]`, where only open
  or closed is checked. The reference points from the marker to a valid carrier
  (`.agents/rules/carrier.md` § "Carrier Requirement"), because carriers have identifiers and
  statements do not; the state audit sets it, and a marker without one stays valid.
- **"By construction" names the construction;** without it the marker is `[planned]` — a guarantee
  that holds only because nothing happens at that place is a vacancy, not a property.
- **A marker is a display, not a carrier:** it says "target, not reality" where the sentence stands;
  `missing:` says what is missing, a reference points at who carries it, and the state audit carries
  every uncarried `[planned]` / `[partial]` point to one (`.agents/rules/carrier.md`,
  `.agents/rules/audit.md`).

## Timestamps in File Names

One format: `YYYY-MM-DDTHHMMZ` — extended ISO date, compact time, minutes, UTC — from
`date -u +"%Y-%m-%dT%H%MZ"`, never estimated or computed by hand; the same stamp goes into the file's
metadata block, never a second local-time form. `-u` needs no zone database, so it cannot silently
fall back the way a named zone does on a host without tzdata. ISO 8601 sorts as text only with leading
zeros and one offset, which `Z` is; the colon is out because Windows forbids it in file names, and the
time is compact so stamp and slug stay apart. Applies to output files, decision logs and audits; not
retroactive — existing files, local-time stamps included, are not renamed.

**Link such a file, never write the path bare** — a link or a backticked path renders intact, a bare
path with an underscore falls to emphasis parsing; the timestamp itself is not what breaks.

## Planning

The architecture / baseline document is the target. Roadmap (`roadmap.md`) and issues are the only
planning source — what is planned, in which order, stands there and nowhere else; a plan in a
decision log, a PR body or a chat is carried there or does not exist.
