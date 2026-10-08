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
| `edit-issue-body.ps1` | the one way to edit an issue body — ticks one checkbox (`-Check`) or replaces one section (`-Section`/`-Content`) and leaves every other byte as it was — see [below](#editing-an-issue-body); the only script here that writes |
| `find-closable-issues.ps1` | reports which open issues can be closed — the issues a PR names, or every open issue with a checklist — see [below](#closable-issues); reads only, never closes |
| `get-checklist-items.ps1` | lists the checkboxes of an issue body, each with its line — the one checkbox reading `get-audit-worklist.ps1`, `find-closable-issues.ps1` and `edit-issue-body.ps1` share: a checkbox in a quote counts, one in a code fence does not |
| `get-rest-items.ps1` | every page of a REST endpoint as one flat item stream (`gh api --paginate --slurp`) — the one REST reader the issue and PR scripts here share |
| `get-audit-settings.ps1` | the audit threshold (`Audit-Schwelle:` of `CLAUDE.md`), the default branch, the ref to count on and the merged-PR subject test — shared by `get-audit-due.ps1` and `get-audit-worklist.ps1` |
| `get-reference-pattern.ps1` | the patterns for `owner/repo#N` and issue/PR URLs — shared by `get-issue-links.ps1` and `find-closable-issues.ps1` |
| `get-ledger-file.ps1` | resolves files and folders to round ledger files — shared by `test-ledger.ps1` and `get-rejected-points.ps1` |
| `find-moved-fixes.ps1` | holds every carrier line a PR adds — to the tracking issue's body, `roadmap.md`, `backlog.md` — against the files of the PR diff; each hit is a moved fix (`.agents/rules/carrier.md` § "Carrier Requirement") — see [below](#moved-fixes); reads only |
| `get-audit-worklist.ps1` | builds the work list for the state audit (`.agents/rules/audit.md` § "State Audit") — see [below](#the-audit-work-list); `-Sarif` for a SARIF 2.1.0 log of the marker, marker-comment and remaining findings |
| `get-issue-links.ps1` | on-demand lookup, not a gate (a consolidated check that runs the `check-*` scripts does not pick it up): resolves every `owner/repo#N` (and issue/PR URL) in files or text over REST and prints state and title; exit 1 on one that does not resolve — see [Weitere Skripte](#weitere-skripte) |
| `close-tracking-issue.ps1` | closes the tracking issue a merged PR names, only if `find-closable-issues.ps1` says closable — see [Weitere Skripte](#weitere-skripte) |
| `get-audit-due.ps1` | says whether a full state audit is due, with the figure of each condition — see [Weitere Skripte](#weitere-skripte) |
| `get-lessons.ps1` | prints the lessons of `.agents/lessons.md` that apply to one role — see [Weitere Skripte](#weitere-skripte) |
| `get-rejected-points.ps1` | lists the points earlier rounds rejected, from the round ledgers — see [Weitere Skripte](#weitere-skripte) |
| `ledger.schema.json`, `test-ledger.ps1` | JSON Schema of a round ledger line and the line-by-line check against it — see [Weitere Skripte](#weitere-skripte) |
| `test-merge-ready.ps1` | merge gate: run lines of the PR body against the merge head, plus a review verdict — see [Weitere Skripte](#weitere-skripte) |
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
byte-identical mirror or a dated snapshot that keeps native umlauts on purpose, documented in that
consumer's own `CLAUDE.md` § "Project-Specific Overrides". `allowed_terms` are
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
| `backlog` | open point of `backlog.md` (root or `docs/`): a list item at the left margin with its continuation lines; struck-through points are left out. `Note` is `aged: N PRs merged since (threshold T)` once more than T PRs were merged into the default branch since the newest commit (`git blame`) of the point's lines — T is 30 or the `Audit-Schwelle: <N>` line of `CLAUDE.md`, PRs counted as `get-audit-due.ps1` counts them (squash commits with `(#n)` and `Merge pull request #n` commits on `--first-parent`) — or `aged: D days old (limit 30)` once that commit is more than 30 days old, whichever limit fell first; `ages: N PRs, D days` below both (`ages: D days (PRs unknown)` where the PR count is not computable); `ages: age unknown (no git history)` without one, `ages: age unknown (shallow history)` where a line's commit sits at the cut of a shallow clone — or `exempt: roadmap place` / `exempt: named trigger` for a point carrying `*(Eingereiht … roadmap.md …)*` or `**Ausloeser:**`, which does not age; `Hash` over the point's text |
| `uncovered-carriers` | open tracking issue, and open point of one, that no marker reference names; `roadmap.md` / `backlog.md` lines are not listed one by one, since a reference names the file, not a line. Not computed under `-SkipIssue` |
| `source-report` | source: raw hits, discarded hits and why — `marker` and `marker-comment` end the run with exit 1 when they discard every raw hit, `remaining` and `tracking-issue` do not; `carrier` counts the markers with a reference and each `Carrier` value, `uncovered-carriers` how long that list is |

**A file declares its own quotations.** A comment line of its own — `<!-- audit-worklist: quoted … -->`
in Markdown, `# audit-worklist: quoted …` or `// audit-worklist: quoted …` elsewhere — makes every
`marker`, `remaining` and `marker-comment` hit below it a quotation, counted in `source-report` as
`declared quoted`. It holds to the end of the file or to a line `audit-worklist: end` in the same
form. The state-audit skill writes it under the title of every report; fixtures and test files
carry it for their test data. Inside a Markdown code block, or anywhere but at the start of its own
line, the words declare nothing.

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
the emphasis around it and around its neighbours removed and whitespace collapsed. Every marker on a
line gets its own. A changed hash at the next audit means a changed statement. A marker alone on its
line has no segment of its own: it takes the nearest preceding non-empty line of the same paragraph,
or the literal `none` when a blank line or the file start comes first.

**`undetermined`** — a `teilweise` marker with no `fehlt:` after it, up to the next marker or the end of
its paragraph or list item, carries the `Note` `teilweise (undetermined)`. A hint, no error exit.

## Closable issues

`find-closable-issues.ps1` runs the two checks `.agents/rules/carrier.md` § "Carrier Requirement"
asks for before an issue is closed, and hands the list to whoever closes. It never closes, comments
or edits.

| Mode | Issues checked | Used by |
|---|---|---|
| `-Pr <n>` | every `#N`, `owner/repo#N` and issue or pull request URL in the PR body and its commit messages (GitHub lists at most 250 commits); this repository's counts as `#N`, another one's is reported as `foreign-reference` and not checked; an anchor (`#1-overview`), an HTML entity (`&#39;`) or a file fragment (`docs/x.md#12`) is no reference; a pull request or a missing number is reported as `skipped`; a closed issue is still searched for carrier formulas | `close-tracking-issue.ps1`, run by whoever merges |
| without `-Pr` | every open issue with at least one checkbox or Sub-Issue | `state-audit`, step 3 |

Each issue gets exactly one `Result`:

| `Result` | Meaning |
|---|---|
| `no-reference` | an open issue with neither a checkbox nor a Sub-Issue and without the label `tracking` — reported only, only under `-Pr`; an open `tracking` issue without either goes on to the carrier check and can be `closable` |
| `open-boxes` | `Count` unticked checkboxes plus open Sub-Issues; checkboxes as `get-checklist-items.ps1` reads them |
| `still-carried-by` | `Location` lists `path:line` in the committed tree (`HEAD`) of the whole repository where a carrier formula names the issue in the same clause, on one line or across one line break: `carried in`, `point in`, `getragen in`, `carrier:`, `Traeger` before the number, `#N ist der (gueltige) Traeger` / `#N is the carrier` after it; a quotation without a formula does not count. Also for a closed issue under `-Pr`, whose boxes are not counted. Not searched: `audit/`, `docs/decisions/`, `docs/handoffs/`, `docs/tasks/`, and `.agents/rules/carrier.md` |
| `closed-clean` | only under `-Pr`: the issue is closed and no carrier formula names it any more — the search ran, where a `skipped` entry says it did not; `Count` is the number of unticked checkboxes left in its body (closed too early) |
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
| `foreign-repo-only` | the point carries `**Nur im Fremd-Repo:** <owner/repo#N>`, naming a repo other than the one under check — not blocking by itself, the reviewer checks that the fix lies only there and the line links that repo's issue |
| `own-pr` | the point carries `**Eigener PR:** <owner/repo#N>` — buildable work waiting for its own PR, commissioned in that open PR or tracking issue; not blocking by itself, the reviewer checks that the target exists and is open |
| `source-report` | per carrier: new lines, points, hits |
| `unavailable` | the source could not be read — `SOURCE UNAVAILABLE`, never an empty result |

A tracking-issue hit also carries `Origin`: the edit that wrote its new lines (`edited <time> by
<login>`), or the opening of an issue younger than the work. The body keeps no author per line, so
a point a parallel PR of the same design added shows up as well; `Origin` tells the two apart.

The foreign-repo form without an `owner/repo`, or naming the repository under check, stays a
`moved-fix`. Exit 1 on any `moved-fix` and on any `unavailable`, otherwise 0.

## Editing an issue body

Read through PowerShell as a native command's output, an issue body arrives as an array of lines; a
`[string]` parameter, a `-replace` or an interpolation joins it with spaces, and uploaded again the
body is one line — no checkbox renders, every checklist reader sees nothing open.
`edit-issue-body.ps1` is the path around that:

- reads the body as one string from the REST answer (`gh api repos/{owner}/{repo}/issues/{n}`);
- changes one place: `-Check <words>` ticks the one unticked checkbox containing them (ticked before
  is `unchanged`, exit 0), `-Section <heading> -Content <lines>` replaces what stands under one
  heading outside a code fence, up to the next heading of its level, keeping the blank lines around
  it; a line array is joined with line breaks;
- refuses before writing when the text around that place would change or the line count moves by
  anything but the lines added minus the lines removed, and when the body was edited since it was
  read;
- writes the body as a JSON file (`gh api --method PATCH --input`), compares what GitHub stored with
  what it sent and writes the original back on a mismatch, exit 1.

Line endings stay per line. `-WhatIf` shows the change without writing.

## Weitere Skripte

Alle sieben sind eigenstaendig (kein Modul-Import), brauchen nur pwsh 7.4 und, wo sie das Forge
lesen, `gh`. Jedes Skript hat Hilfe: `Get-Help ./scripts/common/<name>.ps1 -Full`.

### Ist ein voller Audit faellig? (`get-audit-due.ps1`)

Rechnet die drei Bedingungen aus `.agents/rules/audit.md` § "State Audit" (Abschnitt "Full Audit")
und zeigt je Bedingung die Ist-Zahl: (a) kein `audit/ist-stand-*.md` im Repo; (b) das Design aendert
Code, den `docs/architecture*.md` oder `docs/*baseline*.md` beschreibt — Eingabe `-Path` mit den
Pfaden des Designs, ein Treffer ist ein Pfad oder dessen Ordner in Backticks, mit Dokument und
Zeile; (c) mehr als N gemergte PRs seit dem Commit der `**Commit:**`-Zeile des juengsten Audits
(gezaehlt werden Squash-Commits mit `(#n)` im Betreff und Merge-Commits `Merge pull request #n`
per `git log --first-parent`). N ist 30, je Repo ueberschreibbar durch eine Zeile `Audit-Schwelle: <N>` in der `CLAUDE.md`. Ist der Commit nicht
auffindbar (Shallow Clone), gilt (c) als faellig und die Zeile sagt warum. Reine Auskunft: Exit 0,
nur kaputte Eingaben enden mit Fehler.

```powershell
./scripts/common/get-audit-due.ps1 -Path src/Orders/Pipeline.cs,docs/x.md
# c: 34 PRs seit 5d82658 (Schwelle 30) -> faellig
```

### Runden-Zeilen-Datei pruefen und Verworfenes auflisten (`test-ledger.ps1`, `get-rejected-points.ps1`)

Jede Design- oder Review-Runde endet mit einer Zeilen-Datei
`docs/decisions/<stempel>-<slug>-ledger.jsonl`: ein JSON-Objekt je Zeile, Pflichtfelder `id`,
`status` (`angenommen`, `verworfen`, `zurueckgestellt`, `ersetzt`, `idee`), `satz`, `grund`,
`quelle`; optional `thema`, `neu_nur_mit`, `steht_schon_wo`, `haengt_an`, `prio`; keine weiteren
Schluessel (`ledger.schema.json`); bei `verworfen` ist `neu_nur_mit` (nicht leer) Pflicht — das
neue Argument, das den Punkt wieder oeffnet. `test-ledger.ps1` prueft jede Zeile (JSON, Schema, doppelte
`id`), nennt `Datei:Zeile` je Verstoss und endet mit Exit 1; ohne `-Path` laeuft es ueber alle
Zeilen-Dateien in `docs/decisions`. `get-rejected-points.ps1` macht daraus die Liste "schon
verworfen — nur mit neuem Argument wieder aufmachen" (Gruppe `verworfen`, getrennt davon
`zurueckgestellt`; je Punkt Nummer, Satz, Grund, `neu_nur_mit`, Quelle, Datei), als Markdown oder
mit `-Json`.

```powershell
./scripts/common/test-ledger.ps1
./scripts/common/get-rejected-points.ps1 > verworfen.md
```

### Merge-Gate (`test-merge-ready.ps1`)

Vor dem Merge (`.agents/rules/pr.md` § "Merge") haelt es die Laufzeilen unter "Wie getestet" gegen
den Merge-Kopf und prueft, dass ein Review-Verdikt vorliegt. Gruen, wenn: die neueste `voll`-Zeile
den aktuellen Kopf nennt (voll oder als Praefix ab 7 Zeichen) — oder einen aelteren und alle Commits
danach nur Markdown/`docs` oder nur Testdateien beruehren (oder der Kopf ist ein Rebase des geprueften
Kopfs mit gleichen Code-Pfaden) und je eine `format`- und eine `gefiltert`-Zeile den Kopf nennen (die
Ausnahme aus `.agents/rules/pr.md` § "Test Runs"; ein Kommentar-Fix in einer Codedatei zaehlt nicht,
er braucht einen neuen vollen Lauf); ein Diff ohne Code (nur Markdown und `docs/`) genuegt mit einer
`format`-Zeile fuer den Kopf. Alle herangezogenen Zeilen sagen `rot: 0`; das `Basis` der neuesten
`voll`-Zeile ist der aktuelle Kopf des Basis-Zweigs (sonst "main moved since the full run"; offline
mit `-BaseSha`); und ein APPROVED eines anderen Kontos als des Autors liegt vor — auch auf einem
aelteren Commit, es zaehlt, dass ein Verdikt existiert — oder eine Zeile `Review-Verdikt: approve <sha>`
zum Kopf in einer Review oder einem PR-Kommentar eines anderen Kontos; im Gleiches-Konto-Fall
(`.agents/rules/pr.md` § "Accounts per Seat") zaehlt sie mit `-SameAccount` auch in einer Review des
Autorenkontos, nie in einem PR-Kommentar. Ein PR nur aus
`docs/**` und Markdown im Wurzelordner braucht kein Verdikt (`.agents/rules/docs.md`
§ "Documentation"). Die Commits nach dem geprueften Kopf liest es aus dem Checkout (`-Root`, ein
`git log`), sonst vom Forge, parallel. Exit 1, wenn nicht merge-bereit.

```powershell
./scripts/common/test-merge-ready.ps1 -Repo ww3d/playbook -Pr 352
./scripts/common/test-merge-ready.ps1 -BodyPath body.md -HeadSha 4f2a1c9 -ReviewsPath reviews.json   # offline
./scripts/common/test-merge-ready.ps1 -Repo ww3d/playbook -Pr 352 -SameAccount                       # Gleiches-Konto-Fall
```

### Tracking Issue nach dem Merge schliessen (`close-tracking-issue.ps1`)

Wer mergt, schliesst das Tracking Issue (`.agents/rules/carrier.md` § "Tracking Issue"). Das Skript
nimmt die Issues, die der PR-Body per `Refs`/`Closes #N` nennt, laesst `find-closable-issues.ps1 -Pr`
urteilen und schliesst nur ein `closable` Issue (Kommentar aus dem Urteil, dann `completed`); sonst
steht dort, warum es offen bleibt (offene Checkbox, noch ein Traeger, Marker zuerst umhaengen). Ein
nicht gemergter PR wird abgelehnt (Exit 1), ebenso einer, dessen Merge-Commit nicht im `HEAD` von
`-Root` liegt (NOT VERIFIED: die Traeger-Suche las sonst einen Stand vor dem Merge). Ein offenes
Tracking Issue ohne Checkbox und ohne Sub-Issue gilt nach der Traeger-Pruefung als schliessbar.
`-WhatIf` urteilt, schreibt aber nichts.

```powershell
./scripts/common/close-tracking-issue.ps1 -Repo ww3d/playbook -Pr 352 -WhatIf
```

### Verweise pruefen (`get-issue-links.ps1`)

Findet jedes `owner/repo#N` und jeden Link `github.com/<owner>/<repo>/(issues|pull)/<n>` in `-Path`
(Dateien oder Ordner mit `*.md`) oder `-Text`, loest ihn einmal je Lauf ueber `gh api` auf (Issue
und PR) und gibt `owner/repo#N | Zustand | Titel` aus; `merged` fuer einen gemergten PR. Exit 1,
wenn einer nicht aufloest. Der Platzhalter `owner/repo#N` und ein nacktes `#N` zaehlen nicht;
`-Offline` listet nur.

```powershell
./scripts/common/get-issue-links.ps1 -Path docs/decisions
```

### Lehren je Rolle laden (`get-lessons.ps1`)

Liest `.agents/lessons.md` (Eintraege `## L04 — Titel`, darunter `gilt fuer: dev, review`) und
gibt nur die Eintraege aus, deren Liste die Rolle oder `alle` nennt — im Wortlaut. Eine unbekannte
Rolle ist ein Fehler (Exit 1) mit der Liste der bekannten. Ohne pwsh liest man die Eintraege mit
passendem `gilt fuer` von Hand.

```powershell
pwsh scripts/common/get-lessons.ps1 -Role review
```

## Self-contained by design

These scripts import **nothing** from the playbook's own `src/PlaybookOps/` — that module is
playbook-internal and reaches no consumer. Everything they need is in the file, and PowerShell 7.4
is the only prerequisite. The exceptions call a sibling in this directory, never a module:
`close-tracking-issue.ps1` calls `find-closable-issues.ps1`, which calls `get-audit-worklist.ps1`, and
both, like `edit-issue-body.ps1`, call `get-checklist-items.ps1`, the one checkbox reading they share
— all are mirrored together. A
helper that grew a dependency on `PlaybookOps` would run here and nowhere else, which is the
opposite of why this directory exists.

## Running them

```powershell
./scripts/common/check-terminology.ps1                 # exit 1 on any finding
./scripts/common/check-terminology.ps1 -Json           # machine-readable, for a CI step
./scripts/common/check-terminology.ps1 -Sarif > out.sarif   # SARIF 2.1.0 log
./scripts/common/check-terminology.ps1 -BodyPath body.md   # plus the PR body handed in
./scripts/common/get-audit-worklist.ps1                 # work list, grouped by source
./scripts/common/measure-review-comment.ps1 -PullRequest ww3d/playbook#178
./scripts/common/sweep-carriers.ps1 -Repo ww3d/playbook -Since 2026-08-16   # or 2026-08-16T0900Z
./scripts/common/find-closable-issues.ps1 -Repo ww3d/playbook -Pr 260   # after the merge of #260
./scripts/common/find-closable-issues.ps1 -Repo ww3d/playbook -Json     # clean-up run
./scripts/common/find-moved-fixes.ps1 -Repo ww3d/playbook -Pr 278       # every review round
./scripts/common/edit-issue-body.ps1 -Repo ww3d/playbook -Issue 325 -Check 'Hilfsskript'   # tick one box
./scripts/common/edit-issue-body.ps1 -Issue 210 -Section 'Offen' -Content (Get-Content offen.md) -WhatIf
```

Who triggers them in a consumer while that consumer runs no CI of its own is open — the point is
carried as a line in the playbook's own `backlog.md`.
