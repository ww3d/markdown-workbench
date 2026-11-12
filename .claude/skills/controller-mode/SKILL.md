---
name: controller-mode
description: 'Steuernde Session fuer ein Repo: /controller-mode [repo] [lite]. Startet Design-, Dev- und Review-Sessions per Skill-Zeile, prueft sie am PR und merged nach dem Merge-Gate. Triggert bei "/controller-mode", "controller mode", "controller-modus". Nur fuer GitHub-Repos.'
metadata:
  version: "2.14.0"
  source: ww3d/playbook
  checksum: "sha256:9ce6137d0083b074cf3b34e65340a9c855dadf726b478b7457de1ee14cd8871c"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#351"
---

# Controller-Modus

## Schritt 0: Eingang

2. Konto pruefen und setzen nach `.agents/rules/pr.md` § "Accounts per Seat". Orchestrator,
   controller, design and review sessions write as `ww3-claude`.

## Schritt 1: Stand lesen

Erst mit dem Auftrag des Maintainers.

- Offene Tracking Issues (Label `tracking`) mit Body, ihre Zustands-Labels
  (Schritt 4, Zustands-Labels), offene PRs mit Head, letzter Bewegung und "How
  tested" (`gh api "repos/<owner>/<repo>/issues?labels=tracking&state=open"` und
  `gh api "repos/<owner>/<repo>/pulls?state=open"`; Connector: `list_issues`,
  `list_pull_requests`).
- Den Plan des Repos: `pwsh scripts/common/test-plan-labels.ps1 -Repo <owner/repo>` (nur
  lesend; Befunde der Plan-Regel aus § "Planung", Exit 1 bei Befund).
- Laufende Sessions dieses Repos und ihren Auftrag, ueber das Zustell-Werkzeug der Operation.

## Schritt 2: Status in fester Form

Jeder Status hat diese vier Teile, in dieser Reihenfolge:

```text
Stand: <was gemergt, was im PR, was laeuft, je mit owner/repo#N>
Prio: <was zuerst, ein Satz warum>
Plan: <naechste Schritte, je Session/Skill-Zeile>
Offene Entscheidungen: <was der Maintainer entscheidet, sonst "keine">
```

## Schritt 3: Pruefen mit festen Fragen

Der Text eines Weckers (`ScheduleWakeup`, `/loop`) nennt den Schritt, auf den gewartet wird, und
was danach zu tun ist, nie die Startzeile des Skills; ein Hintergrund-Lauf meldet sein Ende selbst,
der Wecker ist nur Rueckfall.

## Schritt 4: Steuern

| Sitz | Startzeile |
|---|---|
| Controller | `/controller-mode <owner/repo>` oder `/controller-mode <owner/repo> lite` |
| Design | `/ccweb-prompt <owner/repo> #<N>` (oder die Aufgabe) |
| Dev | `/dev-task <owner/repo>#<N>` oder `/dev-task "<auftrag>"` |
| Review | `/pr-poll-review <owner/repo>#<PR>` |
| Audit | `/state-audit` im Ziel-Repo |

**Ablauf eines Auftrags**, Phase fuer Phase:

1. **Design:** frische Session (Startzeile des Sitzes) mit dem Auftrag des Maintainers woertlich im
   Start. Fragt sie, weil der volle Audit faellig ist, startet der Controller eine frische Session
   (Zeile "Audit"); ihr Ergebnis `docs/audit/state-*.md` kommt als kleiner eigener Durchlauf ins
   Repo — PR, Review (Phase 3), Merge (Schritt 5) —, bevor das Design weiterlaeuft. Abgabe: Link am
   Tracking Issue. **Sitz-Zeile:** bei seinem ersten Auftrag auf dem Issue schreibt der Controller
   `Seat: <seat>` unter `## Seats`, der Sitzname wie das Zustell-Werkzeug ihn kennt, nie ein
   Sessionname — besteht das Issue schon, beim Design-Start, sonst gleich nach der Abgabe der
   Design-Session, vor dem Dev-Start —, mit `pwsh scripts/common/edit-issue-body.ps1 -Issue <N>
   -Section 'Seats' -Create -Content 'Seat: <seat>'`. Neu geschrieben wird die Zeile nur bei einem
   Wechsel des Sitzes (Uebergabe bei geteiltem Sitz), nie bei einer Rotation; ohne Controller gibt
   es keine. Wer sie liest, nimmt den Sitz aus der Zeile und fragt das Zustell-Werkzeug, wer ihn
   haelt; ob das zu dem passt, was wirklich arbeitet, prueft der Leser.
2. **Dev:** frische Session (Zeile "Dev"); ihre Abgabe `#N Head <sha> bereit` an den Controller
   startet Phase 3.
3. **Review-Schleife:** frische Session (Zeile "Review"); der Reviewer bekommt im Start den Namen
   der Dev-Session, die Dev-Session den des Reviewers als Hinweis. Den Bericht prueft der Controller
   und gibt ihn frei; Punkte der Liste fuer den Maintainer (`.agents/rules/pr.md` § "Controller
   Mode") gehen vorher an ihn. Danach laufen Dev und Reviewer untereinander, bis der Reviewer `#N
   approved <sha>` meldet.
4. **Vor dem Merge, gleichzeitig:** wo der Controller es je PR will, der zweite Blick der
   Design-Session (`ccweb-prompt` § "Zweiter Blick", Anstoss als Hinweis), ihre Funde als neue Runde
   in Phase 3; und je Plattform aus `**Full run:**` der `CLAUDE.md`, die der Dev-Lauf nicht hat, ein
   voller Lauf gleichzeitig (Linux in einer Web-Session, Windows lokal) — die Dev-Session startet ihn
   als eigene Session und traegt die Laufzeile ein.
5. **Merge:** Schritt 5 unten; danach alle Sessions des Auftrags nach Pruefung ihrer Klone (nichts
   Ungepushtes) beenden und abraeumen.

- **Zeilen-Datei der Review-Runde:** in einer Runde mit Funden committet sie der Dev; ist die
  Dev-Session des PRs schon weg, startet der Controller eine frische (Zeile "Dev", mit dem Tracking
  Issue des PRs), die auf dem offenen PR weiterarbeitet (`dev-task` Schritt 4).
- **Zustands-Labels:** The tracking issue carries its state as one label; which event sets which
  stands in `.agents/state-labels.json`, no `state:*` label means it rests. Whoever causes a
  transition sets its label and takes the old one off — `state:merge-ready` (gate green) and
  `state:human` (waits for the maintainer) too.
  Per REST `gh api repos/<owner>/<repo>/issues/<N>/labels -f "labels[]=<neu>"` und
  `gh api -X DELETE repos/<owner>/<repo>/issues/<N>/labels/<alt>`. Ueber den Connector erst die
  vorhandenen Labels lesen (`issue_read`), dann mit `issue_write` die volle neue Liste schicken —
  `issue_write` ersetzt die Liste, ein einzelnes Label darin loescht alle anderen.

### Weitere Regeln der Tracking-Issue-Fuehrung

- **Around 30 checkboxes, open points move to GitHub Sub-Issues;** the body then carries the current
  state.
- A controller never releases Fable itself.
- A session is ended only through the session-delivery tool, never by a shell command.

### Planung

- **Roadmap (`roadmap.md`) and issues are the only planning source** — what is planned, in which
  order, stands there and nowhere else; a plan in a decision log, a PR body or a chat is carried
  there or does not exist.
- When an issue is due stands as exactly one label on it — `plan/now`, `plan/next` or `plan/later` —
  and its order inside `plan/now` and `plan/next` as a rank line in its body; both at the issue and
  nowhere else.
- Only the maintainer changes `<N>` of the cap on `plan/now`, an agent never.
- **Column and rank are the maintainer's decision.** An agent sets them only to carry out such a
  decision.
## Schritt 5: Merge

- **Merge gate:** `pwsh scripts/common/test-merge-ready.ps1 -Repo <owner/repo> -Pr <n>` before every
  merge — the newest full run line names the merge head and the current base, or one moved since
  only by files without code (or the documented exception holds, per platform), it is green, every
  platform of `.agents/rules/pr.md` § "Test Runs" has its line, and a review verdict names the head
  or a commit after which only what `.agents/rules/review.md` § "Review Comments" lists follows
  (`.agents/rules/pr.md` § "Round Ledger" included); a diff without code needs its green `format`
  line, and a doc-only PR (`scripts/common/test-merge-ready.ps1`) no verdict; `pr-form`
  (`scripts/common/test-pr-form.ps1`) is green, drawing a review's block "Form, blockt nie"; same
  account (`.agents/rules/review.md` § "Review Comments"): add `-SameAccount`.
- **Whoever merges reads every `WARN` of the gate** — a passed check that does not block, such as a
  platform excused by a `Not run:` line — and merges over it only where that reason holds under
  `.agents/rules/pr.md` § "Test Runs", the platform could not run; otherwise the missing run comes first.
- **Only the gate checks a foreign verdict:** write accounts bypass the ruleset's pull-request rule
  (`bypass_mode: pull_request` for the write role in the playbook's
  [ruleset template](https://github.com/ww3d/playbook/blob/main/templates/github-rulesets/main.json)),
  so the ruleset enforces no approve by another account.
- **Sync PRs of a playbook wave** are the one named exception: byte-identical mirror files only,
  checked by the wave tooling's own comparison against the playbook and merged by that tooling with
  auto-merge, no run line and no merge gate. A sync PR that rewrites or moves consumer-owned files
  is no part of it: it goes ready without auto-merge and is merged per consumer only after a look
  at the rewritten files, which the wave report lists.
- **Squash** is the default; for a large PR the controller proposes a merge commit, and the
  maintainer decides.
- Required checks that are dead (`.agents/rules/pr.md` § "CI Counts as Dead Org-Wide") are bypassed with `--admin` and a
  one-line reason on the PR. `gh pr merge --match-head-commit` takes the full SHA.
- **Visual acceptance:** a tracking issue the PR anchors (a `Closes #N` / `Refs #N` line of this
  repo) whose body carries the line `Visual acceptance: <what>` waits at `state:human` and is merged
  only once a review or comment by the maintainer account, on the PR or on that issue, has a line
  starting with `Visual acceptance OK` (case-insensitive), written after the commit of the current
  head (its time against the head commit's committer time) — every change of the head needs a new
  OK; the merge gate checks account, place (PR or issue) and time — no agent writes under that
  account.
- Similar small issues may be bundled into one PR, one commit per issue.

Zuerst, wo das Approve einer sauberen Runde eine Zeilen-Datei im Body traegt: sie aus dem
`jsonl`-Block unter dem genannten Dateinamen auf den PR-Branch legen, als eigenen Commit nur mit
dieser Datei (Form: `.claude/skills/pr-poll-review/reference/report.md` § "Zeilen-Datei der Runde"),
`pwsh scripts/common/test-ledger.ps1 -Path <datei>` gruen, pushen.

1. Merge-Gate: `pwsh scripts/common/test-merge-ready.ps1 -Repo <owner/repo> -Pr <n>`; reviewt
   dasselbe Konto, das den PR schrieb (Gleiches-Konto-Fall, `.agents/rules/review.md` § "Review
   Comments"), kommt `-SameAccount` dazu — nur dann zaehlt dessen Verdikt-Zeile im Review. Ein `#N
   Head <sha> bereit` nach einem solchen Approve fuehrt hierher, nicht in eine neue Review-Runde;
   die Threads der Vorschlaege resolvt die Dev-Session (`dev-task`), fehlt sie, eine frische fuer
   den PR. **Veraltetes `CHANGES_REQUESTED`** nimmt ab, wer merged, wenn eine spaetere Runde den
   Head mit gueltigem Verdikt traegt (Approve oder `Review-Verdict: approve <sha>`) und jeder Punkt
   des CR dort erledigt oder getragen ist — mit einer Nachricht, die die ersetzende Review verlinkt.
3. Vor dem Merge, bei `state:merge-ready`, bekommt der Maintainer im Tracking Issue eine
   Kurzanleitung:

   ```text
   Was neu: <ein bis drei Saetze>
   Warum: <Anlass, owner/repo#N>
   Wo: <Dateien, Befehle, Oberflaechen>
   Testen: <Befehle zum Nachpruefen>
   ```

4. Mergen, dann `pwsh scripts/common/close-tracking-issue.ps1 -Repo <owner/repo> -Pr <n>` fuer den
   gemergten PR — schliesst nur, was schliessbar ist, sonst sagt es, warum es offen bleibt.

### Schliessen des Tracking Issues

- **Where no closing line closed it on the merge, whoever merges closes it** (step 4 above). Without
  the script, run those checks by hand. A point moves only because it no longer belongs to this
  design, never to make the issue closable. The same holds for every issue with a checklist. Where
  no PR ticks the last point (ticked by hand, moved), whoever does that closes it under the same
  conditions. Where the closer cannot, it falls to the `maintainer`. A tracking issue whose body
  never held a checkbox is closed the same way once the carrier checks ran.
- **Before closing an issue, check what points to it:**
  1. **Checkboxes against the other carriers:** every open point is moved first, or recorded as
     resolved with it.
  2. **The issue's name across the whole repository:** a place naming it as carrier ("carried in",
     "point in") is a carrier formula; a quotation ("the finding `#36` lists") is not.
  3. **Where other repositories consume this one as their playbook:** their `CLAUDE.md` exceptions
     bound to the issue ("until #N", "bis #N") each fall with the close or name their new carrier.
     Also search across repos (`gh search code '<owner/repo>#N' --owner <org>`), and where the issue
     carries a note of the maintainer ("DO NOT CLOSE", a decision), ask first.

## Schritt 6: Rotation und Neustart

Der Ablauf:

- Hat die Art eine Marke (`rotateAt`), den laufenden kleinen Block fertig machen oder sauber
  schneiden; an der Marke gilt ihr `atMark` (`.agents/rules/controller.md` § "Controller Sessions").
- Bei `compact` (controller, orchestrator) sichert die Session an der Marke und verdichtet; sie bleibt
  im Sitz, der naechste Punkt gilt dann nicht, nur bei einem Neustart.
- Zum Schluss startet die geschnittene Session ihren Nachfolger selbst — dieselbe Zeile
  `/controller-mode <owner/repo> [lite]`, unter demselben Besitzer, wo es einen gibt —, nennt ihn im
  Abschnitt `## Hand-back` im Body des Tracking Issues (mit der Check-Zeile aus `chat-handoff`,
  Schritt 2; fehlt die Ueberschrift, legt `edit-issue-body.ps1 -Section 'Hand-back' -Create` sie an)
  und schickt die Abgabe "Rotation ready" mit dem Link und seinem Namen.
- Vor einem geplanten Neustart jede Session, die er trifft, ihren Stand als WIP auf ihren Branch
  pushen lassen.
- Der Nachfolger liest den Stand selbst und beendet den Vorgaenger, sobald er den Sitz haelt.
