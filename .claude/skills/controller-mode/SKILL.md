---
name: controller-mode
description: 'Steuernde Session fuer ein Repo: /controller-mode [repo] [lite]. Liest den Stand, prueft Sessions und PRs mit festen Fragen, startet Design-, Dev- und Review-Sessions per Skill-Zeile, raeumt fertige ab, merged nach dem Merge-Gate. lite: Design und Review laufen mit dem Maintainer im Fenster. Triggert bei "/controller-mode", "controller mode", "controller-modus". Nur fuer GitHub-Repos.'
metadata:
  version: "2.13.1"
  source: ww3d/playbook
  checksum: "sha256:4e81ba93501dc7170423a7539b05559ad336da7b54fdebceea1df9322f9fdebe"
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

Der Ablauf der steuernden Session. Die Regeln stehen in `.agents/rules/controller.md` § "Controller
Sessions", § "Steering Messages", § "Controller Mode" und § "Controller Lite", in `.agents/rules/pr.md`
§ "Session Traffic" und § "Controller Mode"; die Regeln fuer Zustands-Labels (Schritt 4) und Merge
(Schritt 5) stehen in diesem Skill, der den Ablauf traegt und sonst dorthin verweist. Der Skill liefert die Mechanik des
Sitzes, nie die Besetzung: wer ihn nicht ausdruecklich mit dieser Zeile bekommen hat, ist kein
Controller.

## Aufruf

`/controller-mode <owner/repo>` oder `/controller-mode <owner/repo> lite`. Die Zeile ersetzt die
fruehere Startzeile `Controller mode: <repo>.` samt Block. Was der Startauftrag ausser dieser Zeile
tragen darf und was ein Controller ohne eigenen Auftrag tut, regelt `.agents/rules/controller.md`
§ "Controller Mode": ohne Auftrag nur Schritt 0, dann warten; Schritt 1 und alles danach erst mit
dem Auftrag des Maintainers. Stehende Anordnungen des Maintainers liest er an ihrem Traeger — im
Body des Tracking Issues oder in der `CLAUDE.md` des Repos. Fehlt das Repo: **fragen**.

## Schritt 0: Eingang

1. Session-Start nach `.agents/rules/session.md` § "Session Receipt", mit Blob-SHA
   quittiert; die Regeldateien nach `AGENTS.md` § "Rule Files" vor der ersten Aktion ihres Typs,
   fuer den Controller vor allem `pr`, `controller` und `carrier`.
2. Konto pruefen und setzen nach `.agents/rules/pr.md` § "Accounts per Seat". Orchestrator,
   controller, design and review sessions write as `ww3-claude`. Modell nach
   `.agents/rules/agents.md` § "Models".

## Schritt 1: Stand lesen

Erst mit dem Auftrag des Maintainers (Abschnitt "Aufruf").

- Offene Tracking Issues (Label `tracking`) mit Body, ihre Zustands-Labels
  (Schritt 4, Zustands-Labels), offene PRs mit Head, letzter Bewegung und "How
  tested" (`gh api "repos/<owner>/<repo>/issues?labels=tracking&state=open"` und
  `gh api "repos/<owner>/<repo>/pulls?state=open"`; Connector: `list_issues`,
  `list_pull_requests`).
- Den Plan des Repos: `pwsh scripts/common/test-plan-labels.ps1 -Repo <owner/repo>` (nur
  lesend; Befunde der Plan-Regel aus § "Planung", Exit 1 bei Befund).
- Laufende Sessions dieses Repos und ihren Auftrag, ueber das Zustell-Werkzeug der Operation. Als
  Nachfolger eines Controllers uebernimmt die Session dabei im Werkzeug die Sessions ihres
  Vorgaengers (Faehigkeit "Besitz umhaengen", `.agents/rules/controller.md` § "Steering Messages").
- Vor einer neuen Aufgabe "Finish before you start" halten (`.agents/rules/controller.md` § "Controller
  Sessions").

## Schritt 2: Status in fester Form

Jeder Status — an sich selbst, im Status-Kommentar des Tracking Issues, an den Maintainer — hat
diese vier Teile, in dieser Reihenfolge:

```text
Stand: <was gemergt, was im PR, was laeuft, je mit owner/repo#N>
Prio: <was zuerst, ein Satz warum>
Plan: <naechste Schritte, je Session/Skill-Zeile>
Offene Entscheidungen: <was der Maintainer entscheidet, sonst "keine">
```

Die Zeile "Offene Entscheidungen" folgt `.agents/rules/chat.md` § "Talking to the Maintainer" (letzter Punkt).

Wo der Status steht, regelt `.agents/rules/controller.md` § "Controller Sessions" (Status form).

## Schritt 3: Pruefen mit festen Fragen

Je Session und je PR, am PR und am Issue — nie auf eine Meldung warten:

1. **Fertig?** PR steht, der Head unter "How tested" ist der Head, Wellen des Modus belegt.
2. **Kreis?** Dreht sich die Session im Kreis (dieselbe Korrektur zweimal, kein neuer Commit)?
   Der Hook sperrt das Review ab Runde 4, bei wiederholter Fehlerart ab Runde 3, bis am Tracking
   Issue (ohne Anker-Issue am PR) steht: `Review-Round-Decision: #<pr> round <n> recut|continue: <Grund>` (eigene Zeile).
3. **Fortschritt?** Was hat sich seit dem letzten Blick bewegt?
4. **Naechster Schritt?** Wer ist dran, mit welcher Skill-Zeile?
5. **Auftrag?** Steht der Auftrag vollstaendig am Traeger, und tut der PR genau das?

Was eine Frage offenlegt, entscheidet der Controller nach `.agents/rules/code.md` § "Simplicity"; an den
Maintainer geht nur, was `.agents/rules/pr.md` § "Controller Mode" ihm vorbehaelt.

Der Text eines Weckers (`ScheduleWakeup`, `/loop`) nennt den Schritt, auf den gewartet wird, und
was danach zu tun ist, nie die Startzeile des Skills; ein Hintergrund-Lauf meldet sein Ende selbst,
der Wecker ist nur Rueckfall.

## Schritt 4: Steuern

Die Kette ist Design → Dev → Review, jede Session frisch, jede mit ihrer Skill-Zeile gestartet:

| Sitz | Startzeile |
|---|---|
| Controller | `/controller-mode <owner/repo>` oder `/controller-mode <owner/repo> lite` |
| Design | `/ccweb-prompt <owner/repo> #<N>` (oder die Aufgabe) |
| Dev | `/dev-task <owner/repo>#<N>` oder `/dev-task "<auftrag>"` |
| Review | `/pr-poll-review <owner/repo>#<PR>` |
| Audit | `/state-audit` im Ziel-Repo |

Diese Tabelle ist die eine Stelle fuer die Startzeilen aller Sitze; Regeln, Skills und Vorlagen
verweisen hierher.

- **Dev-Start mit Modell:** der Controller startet die Dev-Session mit dem Modell aus der Spec-Zeile
  `Dev-Model:` (aeltere Specs: `Dev-Modell:`) und bestaetigt oder ueberstimmt es nach `.agents/rules/agents.md` § "Models".

**Ablauf eines Auftrags**, Phase fuer Phase; Nachrichten kurz und ohne Inhalt, alles Inhaltliche
steht an Issue und PR (`.agents/rules/pr.md` § "Session Traffic"):

1. **Design:** frische Session (Startzeile des Sitzes) mit dem Auftrag des Maintainers woertlich im
   Start. Fragt sie, weil der volle Audit faellig ist, startet der Controller eine frische Session
   (Zeile "Audit"); ihr Ergebnis `docs/audit/state-*.md` kommt als kleiner eigener Durchlauf ins
   Repo — PR, Review (Phase 3), Merge (Schritt 5) —, bevor das Design weiterlaeuft. Abgabe: Link am
   Tracking Issue. **Sitz-Zeile:** bei seinem ersten Auftrag auf dem Issue schreibt der Controller
   `Seat: <seat>` unter `## Seats` (Regel: `.agents/rules/controller.md` § "Controller Sessions"), der
   Sitzname wie das Zustell-Werkzeug ihn kennt, nie ein Sessionname — besteht das Issue schon, beim
   Design-Start, sonst gleich nach der Abgabe der Design-Session, vor dem Dev-Start —, mit `pwsh
   scripts/common/edit-issue-body.ps1 -Issue <N> -Section 'Seats' -Create -Content 'Seat: <seat>'`;
   `-Create` legt den Abschnitt an, wenn er fehlt. Neu geschrieben wird die Zeile nur bei einem
   Wechsel des Sitzes (Uebergabe bei geteiltem Sitz), nie bei einer Rotation; ohne Controller gibt
   es keine. Wer sie liest, nimmt den Sitz aus der Zeile und fragt das Zustell-Werkzeug, wer ihn
   haelt; ob das zu dem passt, was wirklich arbeitet, prueft der Leser.
2. **Dev:** frische Session (Zeile "Dev"); ihre Abgabe `#N Head <sha> bereit` an den Controller
   startet Phase 3, die Session laeuft weiter.
3. **Review-Schleife:** frische Session (Zeile "Review"); der Reviewer bekommt im Start den Namen
   der Dev-Session, die Dev-Session den des Reviewers als Hinweis (`.agents/rules/controller.md`
   § "Steering Messages", "Hint or halt"). Den Bericht prueft der Controller und gibt ihn frei; Punkte der
   Liste fuer den Maintainer (`.agents/rules/pr.md` § "Controller Mode") gehen vorher an
   ihn. Danach laufen Dev und Reviewer untereinander (`.agents/rules/pr.md` § "Session Traffic",
   Punkt 6), bis der Reviewer `#N approved <sha>` meldet.
4. **Vor dem Merge, gleichzeitig:** wo der Controller es je PR will, der zweite Blick der
   Design-Session (`ccweb-prompt` § "Zweiter Blick", Anstoss als Hinweis), ihre Funde als neue Runde
   in Phase 3; und je Plattform aus `**Full run:**` der `CLAUDE.md`, die der Dev-Lauf nicht hat, ein
   voller Lauf gleichzeitig (Linux in einer Web-Session, Windows lokal) — die Dev-Session startet ihn
   als eigene Session und traegt die Laufzeile ein.
5. **Merge:** Schritt 5 unten; danach alle Sessions des Auftrags nach Pruefung ihrer Klone (nichts
   Ungepushtes) beenden und abraeumen.

Meldet eine arbeitende Session "Rotation ready" mit dem Link auf ihre Uebergabe und dem Namen ihres
Nachfolgers, den sie selbst gestartet hat (`.agents/rules/controller.md` § "Controller Sessions"), nennt der
Controller in der Review-Schleife der Gegenseite den neuen Namen (Hinweis); die alte beendet ihr
Nachfolger, nicht der Controller.

Die Regeln dazu — Abraeumen erst nach Abgabe, Wiederanlauf nur nach Absturz, Schutzvermerke —
stehen in `.agents/rules/controller.md` § "Controller Sessions" und § "After the End", eine
Dev-Session je Aufgabe in `.agents/rules/pr.md` § "Dev Session", die Weitergabe von Anordnungen in
`.agents/rules/controller.md` § "Steering Messages" ("Change of direction"), Fragen an den
Maintainer in `.agents/rules/chat.md` § "Talking to the Maintainer" (letzter Punkt), die erlaubten Nachrichten — die Abgabe am Ende jeder
Session eingeschlossen — in `.agents/rules/pr.md` § "Session Traffic", ausbleibende Antworten dort unter "Questions and
Follow-Up", Auftraege am Besitzer vorbei, auch vom Maintainer direkt, unter "Orders and Rank", ein
Nachtrag des Maintainers zu einem laufenden PR in `.agents/rules/pr.md` § "Controller Mode". Der Ablauf:

- **Review-Freigabe:** den Bericht des Review-Workers liest der Controller als dessen Adressat und
  schickt die Freigabe zurueck (`.agents/rules/controller.md` § "Steering Messages", "Review report and release"); bei `Review-Mode:
  once` entfaellt sie, der Controller gibt den blockierenden Blick der Runde 3 und jede Streit-Frage
  an den Maintainer und schreibt `Review-Round-Decision:` mit dessen Antwort und Quelle
  ([`review-modes.md`](../pr-poll-review/reference/review-modes.md)).
- **Abraeumen:** vor dem Beenden die Liste der Session am Traeger bestaetigen (`.agents/rules/controller.md`
  § "Controller Sessions"), dann mit dem Zustell-Werkzeug beenden und abraeumen — die
  Design-Session, sobald Branch und Link am Issue stehen und kein zweiter Blick (Phase 4) mehr
  kommt, die Review-Session, sobald ihr Approve oder ihre Zeile `Review-Verdict: approve <sha>` zum
  Head am PR steht und kein zweiter Blick mehr kommt, dessen Funde sie als neue Runde braucht
  (`.agents/rules/controller.md` § "Controller Sessions"). Ein Befund raeumt sie nicht ab; wie es dann
  weitergeht, regelt `.agents/rules/pr.md` § "Round Ledger" und der naechste Punkt.
- **Zeilen-Datei der Review-Runde:** in einer Runde mit Funden committet sie der Dev; ist die
  Dev-Session des PRs schon weg, startet der Controller eine frische (Zeile "Dev", mit dem Tracking
  Issue des PRs), die auf dem offenen PR weiterarbeitet (`dev-task` Schritt 4). Die Zeilen-Datei der
  sauberen Runde pusht der Controller selbst, direkt vor dem Merge (Schritt 5).
- **Zustands-Labels:** The tracking issue carries its state as one label; which event sets which
  stands in `.agents/state-labels.json`, no `state:*` label means it rests. Whoever causes a
  transition sets its label and takes the old one off — `state:merge-ready` (gate green) and
  `state:human` (waits for the maintainer) too; `require-live-state.sh` holds the turn end until
  the label of each event in the table stands, in controller mode also until an issue comment of
  the repository is edited.
  Per REST `gh api repos/<owner>/<repo>/issues/<N>/labels -f "labels[]=<neu>"` und
  `gh api -X DELETE repos/<owner>/<repo>/issues/<N>/labels/<alt>`. Ueber den Connector erst die
  vorhandenen Labels lesen (`issue_read`), dann mit `issue_write` die volle neue Liste schicken —
  `issue_write` ersetzt die Liste, ein einzelnes Label darin loescht alle anderen.
- **Aufraeum-Auftrag:** Issues, PRs, Branches und Sessions mit "DO NOT CLOSE" / "DO NOT MERGE" oder
  einem Entscheid des Maintainers daran einzeln als unantastbar nennen.
- **Fragen an den Maintainer** nach `.agents/rules/chat.md` § "Talking to the Maintainer" (letzter Punkt).
- Das Zustell-Werkzeug und seine Faehigkeiten nennt `.agents/rules/controller.md` § "Steering Messages";
  welcher Befehl wozu gehoert, ist Sache der Operation.

### Weitere Regeln der Tracking-Issue-Fuehrung

- **Around 30 checkboxes, open points move to GitHub Sub-Issues;** the body then carries the current
  state — issue bodies have a length limit, and a full body looks as tended as a healthy one.
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
  platform of `.agents/rules/pr.md` § "Test Runs" has its line, and a review verdict names the head or a commit after which
  only what `.agents/rules/review.md` § "Review Comments" lists follows (`.agents/rules/pr.md` § "Round Ledger"
  included); a diff without code needs its green `format` line, and a doc-only PR
  (`scripts/common/test-merge-ready.ps1`) no verdict; `pr-form`
  (`scripts/common/test-pr-form.ps1`) is green, drawing a review's block "Form, blockt nie";
  same account (`.agents/rules/review.md` § "Review Comments"): add `-SameAccount`. The way without the script stands
  in items 1 and 2 below.
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
- **Whoever merges closes the tracking issue** after the merge (item 4 below).
- Similar small issues may be bundled into one PR, one commit per issue.

Zuerst, wo das Approve einer sauberen Runde eine Zeilen-Datei im Body traegt: sie aus dem
`jsonl`-Block unter dem genannten Dateinamen auf den PR-Branch legen, als eigenen Commit nur mit
dieser Datei (Form: `.claude/skills/pr-poll-review/reference/report.md` § "Zeilen-Datei der
Runde"), `pwsh scripts/common/test-ledger.ps1 -Path <datei>` gruen, pushen — kein Dev-Schritt
(`.agents/rules/controller.md` § "Controller Sessions"). Danach kommt nichts mehr auf den Branch.

1. Merge-Gate: `pwsh scripts/common/test-merge-ready.ps1 -Repo <owner/repo> -Pr <n>`; reviewt dasselbe
   Konto, das den PR schrieb (Gleiches-Konto-Fall, `.agents/rules/review.md` § "Review Comments"), kommt
   `-SameAccount` dazu — nur dann zaehlt dessen Verdikt-Zeile im Review. Ohne pwsh von
   Hand: die Laufzeilen gegen den Merge-Head halten
   (`gh api repos/<owner>/<repo>/pulls/<n> --jq .head.sha`), wie der
   Regelblock oben das Gate beschreibt, und pruefen, dass ein Approve eines anderen Kontos oder die Zeile
   `Review-Verdict: approve <sha>` (im Gleiches-Konto-Fall das Kommentar-Review nach
   `.agents/rules/review.md` § "Review Comments") zum Head vorliegt — oder zu einem Commit, nach dem
   nur Zeilen-Datei-Commits folgen. Aenderungen allein unter `docs/tasks/**` und `docs/decisions/**`
   lassen das Verdikt ebenfalls stehen; mit pwsh prueft das Gate dazu Form und Groesse
   (`test-pr-form.ps1`, ein am Issue begruendeter Verzicht kommt mit `-FormWaive "<Grund>"`). Ein bewiesener Nachzug der Basis laesst ein aelteres Verdikt nur
   mit pwsh gelten (`scripts/common/test-pure-catch-up.ps1`); von Hand zaehlt er nicht. Ebenso
   Vorschlaege, die der Dev nach einem Approve mit offenen Blocks woertlich eingespielt hat: das Gate
   beweist sie mit `scripts/common/test-applied-suggestions.ps1` und nennt je Vorschlag angewandt
   oder weggelassen; von Hand zaehlen sie nicht. Die Lauf-Pruefungen bleiben. Ein `#N Head <sha>
   bereit` nach einem solchen Approve fuehrt hierher, nicht in eine neue Review-Runde; die Threads
   der Vorschlaege resolvt die Dev-Session (`dev-task`), fehlt sie, eine frische fuer den PR — wie fuer
   die Zeilen-Datei (Schritt 4, Zeilen-Datei der Review-Runde).
   **Veraltetes `CHANGES_REQUESTED`:** GitHub nimmt es nie selbst ab, und das Gate bleibt rot, bis es
   abgenommen ist. Wer merged, nimmt es ab, wenn eine spaetere Runde den Head mit gueltigem Verdikt
   traegt (Approve oder `Review-Verdict: approve <sha>`) und jeder Punkt des CR dort erledigt oder
   getragen ist — mit einer Nachricht, die die ersetzende Review verlinkt:
   `gh api -X PUT repos/<owner>/<repo>/pulls/<n>/reviews/<id>/dismissals -f message='<Grund, mit Link>'`
   (das Gate nennt Review-ID und Kommando, wo ein neueres Verdikt fuer den Head gilt). Nie ein CR mit
   offenem Punkt.
2. Traegt das Tracking Issue die Zeile `Visual acceptance: <what>` (Regelblock oben):
   erst nach dem `Visual acceptance OK` des Maintainers zum aktuellen Head.
3. Vor dem Merge, bei `state:merge-ready`, bekommt der Maintainer im Tracking Issue eine
   Kurzanleitung:

   ```text
   Was neu: <ein bis drei Saetze>
   Warum: <Anlass, owner/repo#N>
   Wo: <Dateien, Befehle, Oberflaechen>
   Testen: <Befehle zum Nachpruefen>
   ```

4. Mergen, dann `pwsh scripts/common/close-tracking-issue.ps1 -Repo <owner/repo> -Pr <n>` fuer den
   gemergten PR — schliesst nur, was schliessbar ist, sonst sagt es, warum es offen bleibt. Den
   Ablauf beschreibt der Kopf von `scripts/common/close-tracking-issue.ps1` (Meldung
   `SOURCE UNAVAILABLE`), den Rueckfall ohne Skript § "Schliessen des Tracking Issues";
   den Kopf vor dem ersten Merge der Session lesen.

### Schliessen des Tracking Issues

- **Where no closing line closed it on the merge, whoever merges closes it** (step 4 above) — the script closes only when
  **both** hold: the body has no open point left, and the checks below ("before
  closing an issue …") ran. Without the script, run those checks by hand. With points left the issue
  **stays open**; a point moves only because it no longer belongs to this design, never to make the
  issue closable. The same holds for every issue with a checklist; whether this PR ticked the last
  point is counted at the head, never remembered. Where no PR ticks the last point (ticked by hand,
  moved), whoever does that closes it under the same conditions. Where the closer cannot, it falls
  to the `maintainer`; the state audit stays the net below. A tracking issue whose body never held a
  checkbox is closed the same way once the carrier checks ran.
- **Before closing an issue, check what points to it** — a `Closes #N` closes without any check,
  which is why the keyword is conditional:
  1. **Checkboxes against the other carriers:** every open point is moved first, or recorded as
     resolved with it.
  2. **The issue's name across the whole repository** — it finds what the checkbox check cannot, a
     place that names this issue as its carrier without being a checkbox in its body: a place naming
     it as carrier ("carried in",
     "point in") is a carrier formula; a quotation ("the finding `#36` lists") is not.
  3. **Where other repositories consume this one as their playbook:** their `CLAUDE.md` exceptions
     bound to the issue ("until #N", "bis #N"), which check 2 never finds since it searches only this
     repository — each falls with the close or names its new carrier.
     Also search across repos (`gh search code '<owner/repo>#N' --owner <org>`), and where the issue
     carries a note of the maintainer ("DO NOT CLOSE", a decision), ask first: closing is never an
     end in itself.

## Schritt 6: Rotation und Neustart

Grenze und Neustart regelt `.agents/rules/controller.md` § "Controller Sessions" mit den Werten aus
`.agents/session-kinds.json` (Art controller). Der Ablauf:

- Hat die Art eine Marke (`rotateAt`), den laufenden kleinen Block fertig machen oder sauber
  schneiden; ohne Marke verdichtet die Session bei ihrem `autoCompactWindow` und schneidet nicht.
  Alles Offene vorher an den Traeger (core rule 11).
- Zum Schluss startet die geschnittene Session ihren Nachfolger selbst — dieselbe Zeile
  `/controller-mode <owner/repo> [lite]`, unter demselben Besitzer, wo es einen gibt —, nennt
  ihn im Abschnitt `## Hand-back` im Body des Tracking Issues (mit der Check-Zeile aus
  `chat-handoff`, Schritt 2; fehlt die Ueberschrift, legt `edit-issue-body.ps1 -Section
  'Hand-back' -Create` sie an) und schickt die Abgabe "Rotation ready" mit dem Link und seinem Namen
  (`.agents/rules/controller.md` § "Controller Sessions", `.agents/rules/pr.md` § "Session Traffic", Punkt 2).
- Vor einem geplanten Neustart jede Session, die er trifft, ihren Stand als WIP auf ihren Branch
  pushen lassen.
- Der Nachfolger liest den Stand selbst und beendet den Vorgaenger, sobald er den Sitz haelt
  (`.agents/rules/controller.md` § "Controller Sessions"); was dabei als sein Auftrag gilt, regelt
  `.agents/rules/controller.md` § "Controller Mode". Ein Handoff nur, wo sonst Stand verloren ginge (Skill
  `chat-handoff`).

## lite

`/controller-mode <owner/repo> lite` (`.agents/rules/controller.md` § "Controller Lite"): Design- und
Review-Sessions laufen mit dem Maintainer im Fenster, jede Re-Review-Runde ebenso. Der Controller
startet die Dev-Session, prueft (Schritt 3) und merged (Schritt 5). Alles andere gilt unveraendert.
