---
trigger: audit
read-before: starting a new slice or design round, running a state audit, or syncing from or diverging from a source
budgetTokens: 2200
---

Read before: starting a new slice or design round, running a state audit, or syncing from or diverging from a source

## State Audit

### Quick Check

Before every design round, the quick check runs the existing scripts — the audit work list, the
carrier sweep, the closable issues, the plan check — and its result goes into the design's decision
log as one line, with no PR of its own.

### Full Audit

**A full audit is due only when** (a) the repo has none yet, or (c) more than 30 PRs were merged
since the last full audit — a repo sets its own threshold in `CLAUDE.md` (`**Audit threshold:**
<N>`). `pwsh scripts/common/get-audit-due.ps1` computes (a) and (c) with their figures; without the
script, count the merged PRs since the commit the latest audit names and check (a) by hand.

- Each baseline statement is checked against the code (`file:line` against the commit the audit
  names, `.agents/rules/evidence.md` § "Evidence Requirement"), the build and the test actually run.
- **The audit walks the tracking issues in both directions:** a `[planned]` / `[partial]` marker
  with no point at a valid carrier, and a tracking-issue point with no marker or line behind it, are
  both findings (`.agents/rules/carrier.md` § "Carrier Requirement").
- **Every mechanism marker is also held against the architecture section that governs it.** A marker
  whose code contradicts its section is a delta entry, never `[met]`. This holds for `[partial]` and
  `[planned]` too: under a marker naming a missing guard the mechanism is checked, and where it is
  missing as well, marker and text are corrected (§ "Status Markers").
- The result is `docs/audit/state-<YYYY-MM-DDTHHMMZ>.md` on its own branch (`.agents/rules/docs.md`
  § "Timestamps in File Names"); it leads with the metadata block, then a short-form section — the
  **audit head**. A session reads the latest audit head — metadata block plus the short-form
  section, in full — before the first action of the trigger `audit`, and receipts it as `+ Audit —
  <sha> read (<file name>)`.
- The audit works off the doc catch-up lines in `backlog.md` (`.agents/rules/docs.md` §
  "Documentation") in one bundle, index files included (`CLAUDE.md`, `README.md`, link lists under
  `docs/**`); it changes no production or test code — it corrects markers and enters points,
  everything else becomes an order of its own. A backlog line is aged once more PRs than the audit
  threshold were merged since it was written, or more than 30 days passed, whichever comes first; an
  aged line goes as a mandatory point into the tracking issue of the next slice.

- **A marker is covered once its point stands at any valid carrier;** a marker at none is a finding
  the state audit carries to one — the tracking issue of the slice that makes it due, otherwise
  `roadmap.md` / `backlog.md`, for a foreign-only point an open issue there — never to a foreign
  design's tracking issue.
## Design Round

- References the maintainer or the task names are read **in full before the first question**, and
  the decision log lists them.
- Parallel PRs from one round get fixed ranges for IDs, diagnostic codes and numbers in the design,
  so no two hand out the same one.
- Where a decision log already decided, the work follows it without a new round.
- The round's points — accepted, rejected, deferred, superseded, ideas — go into its ledger file
  (skills `ccweb-prompt` and `pr-poll-review`); a
  point already rejected is reopened only with a new argument (`scripts/common/get-rejected-points.ps1`).
- We want to be SOTA, modern, high-performance and clean code, and shine with features the others
  simply don't have — just better, smarter and mega fast.
- **Every design question** first reads what is really asked and researches the state of the art —
  never guessed. Then a fresh background session researches competitors and gaps and finds or
  invents 1 to 4 features other tools do not have and that really help the user; a second fresh
  background session sketches per feature how it looks SOTA, modern, high-performance and clean
  code — a sketch, not code. At least one of the 1 to 4 features is the standout: one that exists
  nowhere yet, mega cool, the latest thing, that everyone wants; with it stand who wants it, what
  users take instead today (three names with links) and where the search went. The second session
  first tries to refute it; "none found" with the search list is a valid answer. Where no
  background session is possible, research yourself. Every such answer gives concrete, evidenced
  points of difference; ideas only, building is the maintainer's decision. A small decision in
  operation the session researches itself, without background sessions.

- **State, selectively:** the index of the remaining docs (`docs/**` and root `*.md` as path +
  purpose, without `docs/overview/`) and the **running slice** (open tracking issue body plus its
  `roadmap.md` lines). Roadmap, backlog and architecture doc are not read in full up front; any
  source a statement or decision touches — a document, a decision log, an issue, a dependency or
  model-template repo — is read **in full first**.
- **No block without measured evidence:** a block, an omission or a "rejected as risky" rests on a
  measurement, not an assumption — measure first; every block has a named way past (an explicit
  switch, set from above, journaled); limits the maintainer set stay, and a review checks each new block.

## Divergences From a Source

A **divergence** is a place where the repo deliberately departs from a source it otherwise follows —
an upstream it syncs or vendors from, a template it was built from, or the playbook (a
project-specific override in `CLAUDE.md`). Its reason stands beside it.

- **A divergence is checked for "the reason holds at the head"**, not for "a reason is there". Every
  state audit, and every sync bringing a new state of the source into files with divergences, walks
  them and gives each `holds`, `no longer holds` or `not checkable` — measured or shown at the code,
  never read off the reason's wording. A sync also reads the source's delta itself, not only the
  folders it copies.
- **`no longer holds` is a finding:** back to the source's form, or a reason that holds today — in
  the same pass where it touches the files anyway, otherwise as `.agents/rules/carrier.md`
  § "Carrier Requirement" says.
- **`not checkable` names why** (a foreign system out of reach, a state this repo cannot see) and
  never counts as `holds`.
- **A reason bound to a state names what lifts it:** a carrier (`until #N`) or a checkable
  condition; a reason meant for good says `permanent`. A reason bound to a state without what lifts
  it is a finding of its own.

## Status Markers

- A marker covers exactly one refutable statement — a statement with several is split until each part
  carries its own marker; an architecture or baseline doc carries no checkboxes — its markers carry
  the state.
- **`[unverified]`** is only for a statement this repo can neither prove nor disprove because it
  talks about a foreign repo (a pinned dependency, a sibling's architecture), named at the statement.
  On anything checkable from here, `[planned]` / `[partial]` say "not yet true".
- A `[partial]` may add `present:` with the part that is there — after the marker, up to the next
  marker or the paragraph's end. Without `missing:` it is undetermined, the form in which a "not at
  all" survives. Splitting into `[met]` + `[planned]` stays allowed.
- **A marker may reference its carrier:** `[planned #45]`, `[planned roadmap]`, `[planned backlog]`,
  likewise for `[partial]`, and for a foreign issue `[planned <owner>/<repo>#12]`, where only open
  or closed is checked. The state audit sets the reference; a marker without one stays valid.
- **"By construction" names the construction;** without it the marker is `[planned]`.
- **A marker is a display, not a carrier:** the state audit carries every uncarried `[planned]` /
  `[partial]` point to one.
