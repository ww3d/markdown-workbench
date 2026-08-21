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
no `VERSION` — green CI is enough and the PR may be merged without waiting for a review; a review
may follow afterwards. Everything else runs the full lifecycle unchanged. The skills and the rule
files are named explicitly because they are the ruleset the agents execute, not prose about it: a
wrong sentence in `docs/` breaks nothing, a wrong sentence in a skill or a rule file changes what
every agent does.

Markdown or prompt blocks that themselves contain triple-backtick code fences get a four-backtick
outer fence — everywhere: chat output, issue/PR bodies, docs. A triple outer fence is closed
prematurely by the first nested block.

## Target vs. Actual

- An architecture / baseline doc is the target state, not the actual state. Never assert actual
  state in prose.
- Every baseline statement carries a status marker: `[erfuellt]` / `[teilweise]` / `[geplant]`.
- The marker points at its evidence: the architecture test where one exists, otherwise the latest
  state audit. `[erfuellt]` without evidence is not allowed.
- **A marker is a display, not a carrier.** It says "this sentence is the target, not reality" at
  the place the sentence stands — which no issue can do. It does not say what exactly is missing or
  who is on it, which no marker can do. The state audit connects the two: it carries every
  `[geplant]` / `[teilweise]` point into the tracking issue (`.agents/rules/carrier.md`
  § "Tracking Issue", `.agents/rules/audit.md` § "State Audit").

## Timestamps in File Names

One format everywhere: `YYYY-MM-DDTHHMM` — extended ISO date, compact time, minute precision.
Determined with `TZ=Europe/Berlin date +"%Y-%m-%dT%H%M"`, which settles CET/CEST by itself. The full
stamp including the offset goes in the file's metadata block, never in the name.

Why exactly this: ISO 8601 sorts chronologically as text only under leading zeros **and a single
offset** — a list mixing UTC and local time sorts by string, not by moment, and the offset inside
the file resolves the October double hour. The colon is out because Windows forbids it in a file
name. The time is compact because in `T00-36-slug` the boundary between stamp and slug is no longer
readable.

Applies to output files, repo decision logs and audits. Not retroactive — existing files are not
renamed.

**Link such a file, never write the path bare.** A link destination and a backticked path both
render intact; a bare path is no link at all and, once a name carries an underscore, is subject to
emphasis parsing. The timestamp itself is not what breaks.
