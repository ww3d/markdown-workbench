---
trigger: docs
read-before: touching a doc or a timestamped file
---

Read before: touching a doc or a timestamped file

Split out of `AGENTS.md`, which keeps the core rules and the index of these files.

## Documentation

Every doc change keeps the docs short, clear, factual: cut redundancy, filler, and detours — never
lose knowledge or clarity. Prefer terse and unambiguous over exhaustive.

**A PR pulls only the doc places its own diff would otherwise make wrong** — a statement the cut
renders untrue. Everything else goes as a line to `backlog.md`; that file is a valid carrier
(`.agents/rules/carrier.md` § "Carrier Requirement"), so nothing is lost. Where the repo has no
`backlog.md` yet, the PR contributing the first line creates it. The catch-up runs bundled, once
per slice, at the state audit that runs before every slice anyway (`.agents/rules/audit.md`
§ "State Audit") — without that, the lines are a dump instead of a carrier. In doubt, pull it in
the same PR.

**A doc-only PR gets no review gate.** Where a diff touches exclusively `docs/**` and `*.md` in the
repository root — no code, no workflow, **no skills**, **no rule file under `.agents/rules/**`**,
no `VERSION` — green gates are enough and the PR may be merged without waiting for a review; a
review may follow afterwards. While CI counts as dead (`.agents/rules/pr.md` § "PR Lifecycle",
subsection "CI Counts as Dead Org-Wide"), the green gates are the author's local run in the PR body,
not a CI status. Everything else runs the full lifecycle unchanged. The skills and the rule
files are named explicitly because they are the ruleset the agents execute, not prose about it: a
wrong sentence in `docs/` breaks nothing, a wrong sentence in a skill or a rule file changes what
every agent does.

Markdown or prompt blocks that themselves contain triple-backtick code fences get a four-backtick
outer fence — everywhere: chat output, issue/PR bodies, docs. A triple outer fence is closed
prematurely by the first nested block.

## Correcting a Value

**A correction sweeps for the old value before it sets the new one.** A finding names the place it
was noticed, not every place the statement stands — a number or a commitment travels into a report,
a carrier, a spec file and an issue body alike, and a fix that pulls only the named place leaves the
rest wrong, provably so, since the same diff already corrected the first one. Before the fix, run
`git grep` against the **old** value across the whole repository, and give every hit an outcome:
pulled, or left standing with a reason — and show the sweep in the PR body: the `git grep`, its hit
count before and after, and the reason for every hit left standing. "Check the place, not the count"
(`.agents/rules/evidence.md` § "Evidence Requirement") applies here unchanged and is the reason the
second half of this rule exists: a hit inside an answer list or a literal quotation carries the old
wording **on purpose**, as proof of the correction, and is not itself corrected — a sweep without
that distinction does the exact harm the neighboring rule warns against. Dated snapshots (`audit/`,
`docs/decisions/`, `docs/handoffs/`, and `docs/tasks/**`, since a spec file holds the order as it
stood in its round) are exempt: a snapshot is truthful to when it was taken, not to now.

## Links in Synced Files

A synced file (`AGENTS.md`, everything under `.agents/rules/**`, `docs/common/**`, `tech/common/**`,
a synced skill or hook) is read inside every consumer, not only inside the playbook where it was
written. A path or link that only resolves in the playbook's own tree is dead in every consumer that
reads the same bytes — the sync copies the file, not the tree around it. Such a reference is either
an absolute link (`https://github.com/ww3d/playbook/blob/main/...`) or says "in the playbook"
instead of naming a path that may not exist where the reader stands.

## Target vs. Actual

- An architecture / baseline doc is the target state, not the actual state. Never assert actual
  state in prose.
- Every baseline statement carries a status marker: `[erfuellt]` / `[teilweise]` / `[geplant]` /
  `[nicht verifiziert]`.
- The marker points at its evidence: the architecture test where one exists, otherwise the latest
  state audit. `[erfuellt]` without evidence is not allowed.
- **`[nicht verifiziert]` is the fourth form, and its condition is narrower than the other
  three's.** It is allowed only where a statement can be neither proven nor disproven from this
  repo, because it talks about a foreign repo — a dependency pinned by version, a sibling repo's
  own architecture. The foreign repo is named at the statement. It does not substitute for
  `[geplant]` / `[teilweise]` on anything checkable from here: those say "not yet true", this says
  "true or false is not this repo's to say".
- **A `[teilweise]` names what is missing, in the same statement.** The statement carries the
  keyword `fehlt:` with the missing mechanism, optionally `steht:` with the part that is there —
  after the marker, up to the next marker or the end of the paragraph, whichever comes first. A
  `[teilweise]` without `fehlt:`
  is undetermined: "partly" without that split is the form in which a "not at all" survives.
  Splitting into two statements (`[erfuellt]` + `[geplant]`) stays allowed and is often better.
- **A marker may carry a reference to its carrier:** `[geplant #45]`, `[geplant roadmap]`,
  `[geplant backlog]`, and likewise `[teilweise #45]`, `[teilweise roadmap]`,
  `[teilweise backlog]`. A fourth reference form names an issue in a foreign repo, repo in front:
  `[geplant ww3d/<repo>#12]`, likewise `[teilweise ww3d/<repo>#12]`. There only open or closed is
  checked — the foreign repo decides its own carrier form. Each reference names a valid carrier
  (`.agents/rules/carrier.md` § "Carrier Requirement") and points from the marker to it, because
  carriers have identifiers (an issue number, a file name) and statements do not. The state audit
  sets it when it carries a point to a carrier; a marker without a reference stays valid.
- **"By construction" is a reason only with the construction named.** A statement that holds "by
  construction" names the construction that carries it; without it the marker is `[geplant]` — a
  guarantee that holds only because nothing happens at that place is a vacancy, not a property.
- **A marker is a display, not a carrier.** It says "this sentence is the target, not reality" at
  the place the sentence stands — which no issue can do. The marker itself does not say what exactly
  is missing — the statement's `fehlt:` does — nor who is on it; a reference only points at the
  carrier that is. The state audit connects the two: it carries every
  `[geplant]` / `[teilweise]` point that stands at no carrier to one — the tracking issue of the
  slice that makes it due, otherwise `roadmap.md` / `backlog.md`, and for a point implementable only
  in a foreign repo an open issue there (`.agents/rules/carrier.md`
  § "Carrier Requirement", `.agents/rules/audit.md` § "State Audit").

## Timestamps in File Names

One format everywhere: `YYYY-MM-DDTHHMMZ` — extended ISO date, compact time, minute precision, UTC.
Determined with `date -u +"%Y-%m-%dT%H%MZ"`. The same UTC stamp goes in the file's metadata block,
never a second, local-time form to reconcile against it.

Why UTC and not a named local zone: the previous rule read `TZ=Europe/Berlin date +"%Y-%m-%dT%H%M"`,
and on a host whose timezone database is absent (Git-Bash on Windows ships none) that command
silently falls back to UTC — exit 0, a well-formed stamp, no warning, wrong by one or two hours. The
gap was measured recurring at every log on such a host after being carried as "fixed" for weeks. `-u`
needs no zone lookup on any platform, so it cannot have this failure mode.

Why exactly this format otherwise: ISO 8601 sorts chronologically as text only under leading zeros
**and a single offset** — a list mixing zones sorts by string, not by moment. `Z` is a single, fixed
offset by definition; a named zone that resolves differently depending on tzdata availability is
not. The colon is out because Windows forbids it in a file name. The time is compact because in
`T00-36-slug` the boundary between stamp and slug is no longer readable.

Applies to output files, repo decision logs and audits. Not retroactive — existing files (including
ones already timestamped in local time) are not renamed.

**Link such a file, never write the path bare.** A link destination and a backticked path both
render intact; a bare path is no link at all and, once a name carries an underscore, is subject to
emphasis parsing. The timestamp itself is not what breaks.
