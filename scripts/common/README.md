# Common — synced from ww3d/playbook

Files in this directory are mirrors of
[`ww3d/playbook`](https://github.com/ww3d/playbook). Whatever lands here is byte-for-byte upstream;
local edits will be overwritten on the next sync — propose changes upstream as an issue or PR
against the playbook.

Repo-owned tooling lives one level up in `scripts/`, which is never synced. The split is the same
one `docs/` already draws between `docs/common/` and the repo's own docs.

## What is in here

Cross-repo checks and helpers that every consumer can run, whatever its stack:

| Script | Purpose |
|---|---|
| `check-terminology.ps1` | umlauts in repo text, retired terms from `forbidden-terms.txt`, dead relative Markdown paths, backtick-quoted repository paths that exist nowhere, a leftover `templates/` onboarding banner or placeholder, workflow boilerplate in a task spec or prompt file; with `-BodyPath` also a PR body against the closing-line rule; `-Sarif` for a SARIF 2.1.0 log |
| `find-closable-issues.ps1` | reports which open issues can be closed — the issues a PR names, or every open issue with a checklist — see [below](#closable-issues); reads only, never closes |
| `get-checklist-items.ps1` | lists the checkboxes of an issue body — the one checkbox reading `get-audit-worklist.ps1` and `find-closable-issues.ps1` share: a checkbox in a quote counts, one in a code fence does not |
| `find-moved-fixes.ps1` | holds every carrier line a PR adds — to the tracking issue's body, `roadmap.md`, `backlog.md` — against the files of the PR diff; each hit is a moved fix (`.agents/rules/carrier.md` § "Carrier Requirement") — see [below](#moved-fixes); reads only |
| `get-audit-worklist.ps1` | builds the work list for the state audit (`.agents/rules/audit.md` § "State Audit") — see [below](#the-audit-work-list); `-Sarif` for a SARIF 2.1.0 log of the marker, marker-comment and remaining findings |
| `measure-review-comment.ps1` | counts the Conventional Comments on a PR — how many block, how many rounds |
| `sweep-carriers.ps1` | finds closed tracking issues with an open checkbox and open issues referencing a carrier that has since closed; reads issues over REST (`gh api`), `-Since` filters by `closed_at`; exit 1 on a finding and when a source is unavailable |

`forbidden-terms.txt` sits next to the script rather than inside it: the list changes far more
often than the check, and a consumer reading it should not have to read PowerShell.

`.agents/rules/local/terminology.yml`, read from the repository `check-terminology.ps1` scans (not
from this directory), carries a consumer's own overrides — never synced (`local/` is excluded from
the managed `.agents` set). Two top-level keys, each a list of plain strings, `#` comments and blank
lines ignored, no nesting:

```yaml
exempt_paths:
  - docs/handoffs/*
allowed_terms:
  - Grundsaetze
```

`exempt_paths` are repo-relative glob patterns excluded from the umlaut check only — for a
byte-identical mirror or a dated snapshot that keeps native umlauts on purpose, the way
`CLAUDE.md` § "Project-Specific Overrides" documents for `ww3d/rc-control`. `allowed_terms` are
whole words that stay allowed wherever they appear.

## The audit work list

`get-audit-worklist.ps1` emits one entry per point with `Source`, `Path`, `Line`, `Text`, `Note`,
`Carrier`, `Hash` and `Reference`; the last three are empty where they do not apply. Issues are
read over the REST API only (`gh api`), never GraphQL, so the script runs in a Claude Code session;
the repository comes from `-Repo` or from the checkout's git remote.

| `Source` | One entry per |
|---|---|
| `marker` | applied status marker in Markdown — several on one line are several entries. A marker is a quotation, not an entry, inside a code block, inside a longer inline code span, in a file that defines the grammar, or as one link of an enumeration: a chain of markers joined by nothing but separators (whitespace, `,` `;` `/`, emphasis, `oder` / `und` / `bzw.` / `or` / `and`) that holds more than one distinct marker — another word, or the same word with another reference. `[erfuellt], [erfuellt]` stays two statements |
| `marker-comment` | `TODO` / `HACK` / `FIXME`, colon or not, with the form of its carrier reference — not in `get-audit-worklist.ps1` itself, which defines the grammar |
| `tracking-issue` | open checklist line (as `get-checklist-items.ps1` reads it) or open Sub-Issue of an open tracking issue |
| `remaining` | `fehlt:` (lowercase) in prose outside code blocks, decision logs and the files that define the grammar: `Text` runs to the next marker — on the same line or a later one —, `steht:`, the end of the paragraph or list item, or in a table row the end of its cell; a full stop does not end it; `Note` is the nearest heading above, `Hash` that of the `teilweise` statement it belongs to. When the nearest marker within reach before it carries another word, `Note` is `fehlt: without teilweise` and `Hash` is its own segment's |
| `backlog` | open point of `backlog.md` (root or `docs/`): a list item at the left margin with its continuation lines; struck-through points are left out. `Note` is `aged: survived N audits` from three on, `ages: survived N audits` below — audits counted from the stamps of `audit/ist-stand-*.md` later than the newest commit time (`git blame`) of the point's lines, `ages: age unknown (no git history)` without one, `ages: age unknown (shallow history)` where a line's commit sits at the cut of a shallow clone — or `exempt: roadmap place` / `exempt: named trigger` for a point carrying `*(Eingereiht … roadmap.md …)*` or `**Ausloeser:**`, which does not age; `Hash` over the point's text |
| `uncovered-carriers` | open tracking issue, and open point of one, that no marker reference names; `roadmap.md` / `backlog.md` lines are not listed one by one, since a reference names the file, not a line. Not computed under `-SkipIssue` |
| `source-report` | source: raw hits, discarded hits and why — `marker` and `marker-comment` end the run with exit 1 when they discard every raw hit, `remaining` and `tracking-issue` do not; `carrier` counts the markers with a reference and each `Carrier` value, `uncovered-carriers` how long that list is |

**`Carrier`** — one value per `marker` entry, from the optional reference in the brackets
(`.agents/rules/docs.md` § "Target vs. Actual"):

| Value | Meaning |
|---|---|
| `covered` | `[… roadmap]` / `[… backlog]`: the file stands in the root or under `docs/`. `[… #N]`: the issue is open **and** a carrier — label `tracking` (`-Label`), a checkbox in its body, or an open Sub-Issue of an open tracking issue. A reference qualified with this repository counts as `#N`. `[… owner/repo#N]`: the foreign issue is open; its repo decides its own carrier form |
| `not-a-carrier` | `[… #N]` is open but no carrier: no label, no checkbox, or a pull request |
| `carrier-closed` | the issue is closed, carrier or not |
| `target-missing` | the file is missing, or no issue has that number |
| `unverifiable` | no reference — or an issue reference while issues were not read (`-SkipIssue`, `gh` unavailable, the lookup failed with anything but 404). A hint for the audit, not an error |

Whether a `roadmap.md` / `backlog.md` line really carries the point stays audit work.

**`Reference`** — on a `marker` entry, the carrier reference inside that marker's own brackets, as
written (`#N`, `owner/repo#N`, `roadmap`, `backlog`), empty without one. `Text` is the whole line
and may name other numbers; the reference is what the marker points at.

**`Hash`** — the first eight hex characters of SHA-256 over the statement segment: from the previous
marker on the line (or its start) to the next one (or its end), with the marker, its reference and
the emphasis around it and around its neighbours removed and whitespace collapsed. Every marker on a line gets its own. A
changed hash at the next audit means a changed statement.

**`undetermined`** — a `teilweise` marker with no `fehlt:` after it, up to the next marker or the end of
its paragraph or list item, carries the `Note` `teilweise (undetermined)`. A hint, no error exit.

## Closable issues

`find-closable-issues.ps1` runs the two checks `.agents/rules/carrier.md` § "Carrier Requirement"
asks for before an issue is closed, and hands the list to whoever closes. It never closes, comments
or edits.

| Mode | Issues checked | Used by |
|---|---|---|
| `-Pr <n>` | every `#N`, `owner/repo#N` and issue or pull request URL in the PR body and its commit messages (GitHub lists at most 250 commits); this repository's counts as `#N`, another one's is reported as `foreign-reference` and not checked; an anchor (`#1-overview`), an HTML entity (`&#39;`) or a file fragment (`docs/x.md#12`) is no reference; a pull request or a missing number is reported as `skipped`; a closed issue is still searched for carrier formulas | `pr-poll-review`, `[MERGE-GATE]` |
| without `-Pr` | every open issue with at least one checkbox or Sub-Issue | `state-audit`, step 3 |

Each issue gets exactly one `Result`:

| `Result` | Meaning |
|---|---|
| `no-reference` | an open issue with neither a checkbox nor a Sub-Issue — reported only, only under `-Pr` |
| `open-boxes` | `Count` unticked checkboxes plus open Sub-Issues; checkboxes as `get-checklist-items.ps1` reads them |
| `still-carried-by` | `Location` lists `path:line` in the committed tree (`HEAD`) of the whole repository where a carrier formula names the issue in the same clause, on one line or across one line break: `carried in`, `point in`, `getragen in`, `carrier:`, `Traeger` before the number, `#N ist der (gueltige) Traeger` / `#N is the carrier` after it; a quotation without a formula does not count. Also for a closed issue under `-Pr`, whose boxes are not counted. Not searched: `audit/`, `docs/decisions/`, `docs/handoffs/`, `docs/tasks/`, and `.agents/rules/carrier.md` |
| `closed-clean` | only under `-Pr`: the issue is closed and no carrier formula names it any more — the search ran, where a `skipped` entry says it did not |
| `closable` | neither of the above; `Note` carries the closing comment in German — the PR that delivered the last point (under `-Pr` that PR, otherwise the newest commit naming the issue), both checks, date and commit |

A `rehang-first` entry stands before a `closable` issue for each applied status marker whose own
reference names it (`[geplant #N]`, its `Reference`, not a mention elsewhere on the line) or
`TODO` / `HACK` / `FIXME` that names it — taken from `get-audit-worklist.ps1 -SkipIssue`, so this
script needs its sibling in the same directory. When `gh`, the repository search or the marker check
is unavailable, the run says `SOURCE UNAVAILABLE` and exits 1; otherwise it exits 0.

## Moved fixes

`find-moved-fixes.ps1 -Pr <n>` reads the PR, its files and its commits over REST and collects the
carrier lines the PR adds: lines its diff adds to `roadmap.md` / `backlog.md` (root or `docs/`), and
lines new in the body of each tracking issue the PR body names (label `tracking`, or `-TrackingIssue`)
since the work began — the earlier of the PR's creation and its first commit's author date. That
body history comes from the issue's edits, which GitHub serves over GraphQL only; where GraphQL is
blocked the issue is reported `unavailable`. Lines are grouped into points (list item or paragraph);
a struck-through point or a ticked checkbox is delivered and left out.

A point hits when a new line of it names a file the PR adds or changes — by its path, or by a
trailing part of it that no other tracked file ends with (`git ls-files` under `-Path`; without git
only the full path counts). A point that names its file in no such form — by a class or function
name, or in prose — is not found; the reviewer's table "Verschobenes" stays the net for it.

| `Result` | Meaning |
|---|---|
| `moved-fix` | an `issue: (blocking)`, no judgement involved |
| `no-known-fix` | the point carries `**Kein Fix bekannt:**` and its reason — not blocking by itself, the reviewer checks the reason |
| `source-report` | per carrier: new lines, points, hits |
| `unavailable` | the source could not be read — `SOURCE UNAVAILABLE`, never an empty result |

A tracking-issue hit also carries `Origin`: the edit that wrote its new lines (`edited <time> by
<login>`), or the opening of an issue younger than the work. The body keeps no author per line, so
a point a parallel PR of the same design added shows up as well; `Origin` tells the two apart.

Exit 1 on any `moved-fix` and on any `unavailable`, otherwise 0.

## Self-contained by design

These scripts import **nothing** from the playbook's own `src/PlaybookOps/` — that module is
playbook-internal and reaches no consumer. Everything they need is in the file, and PowerShell
7.4 is the only prerequisite. The exceptions call a sibling in this directory, never a module:
`find-closable-issues.ps1` calls `get-audit-worklist.ps1`, and both call `get-checklist-items.ps1`,
the one checkbox reading they share — all are mirrored together. A helper that grew a dependency on
`PlaybookOps` would run here and nowhere else, which is the opposite of why this directory exists.

## Running them

```powershell
./scripts/common/check-terminology.ps1                 # exit 1 on any finding
./scripts/common/check-terminology.ps1 -Json           # machine-readable, for a CI step
./scripts/common/check-terminology.ps1 -Sarif > out.sarif   # SARIF 2.1.0 log
./scripts/common/check-terminology.ps1 -BodyPath body.md   # plus the PR body handed in
./scripts/common/get-audit-worklist.ps1                 # work list, grouped by source
./scripts/common/measure-review-comment.ps1 -PullRequest ww3d/playbook#178
./scripts/common/sweep-carriers.ps1 -Repo ww3d/playbook -Since 2026-08-16
./scripts/common/find-closable-issues.ps1 -Repo ww3d/playbook -Pr 260   # after the merge of #260
./scripts/common/find-closable-issues.ps1 -Repo ww3d/playbook -Json     # clean-up run
./scripts/common/find-moved-fixes.ps1 -Repo ww3d/playbook -Pr 278       # every review round
```

Who triggers them in a consumer while that consumer runs no CI of its own is open — the point is
carried as a line in the playbook's own `backlog.md`.
