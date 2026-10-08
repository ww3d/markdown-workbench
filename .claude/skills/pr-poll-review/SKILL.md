---
name: pr-poll-review
description: 'Reviewt einen GitHub Pull Request iterativ bis zum Approve und fuellt die reviewer-Rolle des Playbook-PR-Lifecycles; endet mit dem Approve. Triggert bei "review und wenn ok approve", "pr pollen", "check PR [ref]", "approve sobald die changes da sind", "rere". Nur fuer GitHub-PRs.'
metadata:
  version: "13.0.0"
  source: ww3d/playbook
  checksum: "sha256:a598b4dbe1ccf7b4b0a1d36bb8fdb0a69937f3cd9a6800a2d4798d7ceb7a4ab5"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#210"
---

# PR Review & Approve Workflow

Iterativer Review-Loop fuer GitHub-PRs. Faehrt von Erstreview bis Approve durch und fuellt die
`reviewer`-Rolle aus `.agents/rules/pr.md` § "PR Lifecycle" (Schritte 6-7). Der Merge und das
Schliessen des Tracking Issues liegen bei dem, der merged (`.agents/rules/pr.md` § "Merge") — dieser
Skill merged nie und endet mit dem Approve.

## Wann

Wenn ein PR zu reviewen ist, bis zum Approve: Kontext selbst am Head beschaffen, ein Review-Prompt
existiert nicht (Phase 1, Schritt 1); klassifizieren und pruefen, jeden Punkt in Conventional
Comments (Kernprinzip, Schritte 2-3); vor jeder Veroeffentlichung Chat-Report — im claude.ai-Chat
plus Widget — zur Freigabe (Schritt 4); posten, auf Pushes warten, neu reviewen (Phasen 2-3);
approven erst mit belegtem lokalem Testlauf ohne Merge-Konflikte (Phase 4).

## Kernprinzip

- **Session-Start-Pflicht:** Vor Phase 1 gilt `AGENTS.md` § "Session Start: Read Before Anything
  Else" des Ziel-Repos — Pflichtkern (AGENTS-Kern, `CLAUDE.md`, Audit-Kopf) lesen und je Datei mit
  Blob-SHA quittieren. Der Review laeuft am Head des Repos, nie aus dem Chat-Verlauf oder dem
  Gedaechtnis.
- **Einsatzpunkt-Quittung als Eingangsschritt.** Dieser Skill loest vier Trigger aus: er postet
  einen Review, er beurteilt einen PR-Body, er prueft Traeger und er wiegt Belege. Vor Phase 1
  werden darum `.agents/rules/review.md`, `.agents/rules/pr.md`, `.agents/rules/carrier.md` und
  `.agents/rules/evidence.md` **vollstaendig gelesen und quittiert** — Format und Pflicht stehen in
  `AGENTS.md` § "Session Start: Read Before Anything Else", Schritt 3, einmal je Session je Datei.
  In ccweb erzwingt der `require-rule-read.sh`-Hook dasselbe; wo kein Hook laeuft, ist dieser
  Schritt die einzige Absicherung. Die Regeltexte werden hier **nicht** gedoppelt, sondern gelesen.
- **Lehren der Rolle laden:** `pwsh scripts/common/get-lessons.ps1 -Role review`. Ohne pwsh: die
  Eintraege aus `.agents/lessons.md` lesen, deren Zeile `gilt fuer` `review` oder `alle` nennt.
- **Dieselbe Quittung fuer die drei Referenzdateien.** `reference/checks.md`,
  `reference/report.md` und `reference/gates.md` tragen die Kasuistik dieses Skills. Jede wird
  an ihrer Einsatzstelle **vollstaendig gelesen und quittiert**, bevor der Schritt laeuft, der
  sie braucht — nicht ueberflogen, einmal je Session je Datei, in derselben Zeilenform:

  ```text
  role | path | blob SHA | read / not found
  rule | .claude/skills/pr-poll-review/reference/checks.md | 4f2a1c9… | read
  ```
- **Freigabe-Standard:** freigeben, sobald der PR den Zustand **eindeutig verbessert** — nicht erst,
  wenn nichts mehr zu finden ist. Ein PR muss nicht perfekt sein, er muss besser sein.
- **Beyond the diff bleibt Suchmethode, nicht Blocking-Grund.** Verwandte Files, Configs und Tests
  werden mitgelesen — dort liegt die Fehlerklasse, die sonst niemand sieht. Aber ein Punkt
  **ausserhalb des PR-Scopes haelt den PR nicht auf** — und wird nicht getragen, sondern gebaut: ist
  er baubar (in diesem Repo umsetzbar, ohne offene Entscheidung des Maintainers), wird er ein
  eigener PR, bis dahin mit der Zeile `**Eigener PR:** <owner/repo#N>`. Nur die drei nicht baubaren
  Faelle gehen anders: Fremd-Repo-Issue plus Zeile `**Nur im Fremd-Repo:** <owner/repo#N>`,
  `**Kein Fix bekannt:**` nach belegter Recherche, oder eine Frage an den Maintainer, im
  Controller-Modus an den Controller (`.agents/rules/review.md` § "Review Comments",
  `.agents/rules/carrier.md` § "Carrier Requirement").
- **Modell dieser Session und ihrer Sub-Agenten nach `AGENTS.md` § "Models"**, in jedem
  Review-Modus (`.agents/rules/review.md` § "Review Comments").
- **Agent-Autor-Annahme:** Der Author (ein Coding-Agent, z.B. Claude Code oder Copilot) produziert
  Code, der sauber aussieht, aber leise mehr Redundanz und Tech-Debt traegt als menschlicher. Nicht
  vom Oberflaechen-Eindruck taeuschen lassen — gezielt nach den Agent-typischen Fehlerklassen
  suchen (Phase 1, Red-Flags).
- **Conventional Comments sind das Vokabular.** Jeder Punkt traegt genau ein Label mit Dekoration;
  die Zuordnung steht in `.agents/rules/review.md` § "Review Comments" und wird hier nicht
  gedoppelt. Der Trennstrich ist nicht die Wichtigkeit, sondern **wer antworten muss**. Im
  Zweifel, ob eine Korrektur wirklich eindeutig ist, ist es eine `question:` — praeskriptiv
  als `issue:` posten nur, wenn sie es ist.
- **Ein `nitpick:` blockt nie** — weder das Abschluss-Verdikt noch den Merge — und braucht **keinen
  Traeger**. Er wird gefixt oder verworfen.
- **Jeder `nitpick:` geht als Suggested Change raus**, nicht als Prosa-Kommentar: als
  `suggestion`-Codeblock im `body` des Inline-Kommentars, mit `path` und `line`. Das ist zugleich
  der Filter — ein Nit, der sich nicht als Suggestion formulieren laesst, ist keiner; dann ist es
  ein `issue:` oder ein `suggestion:`.
- **Jede `question: (blocking)` in der Kurzform aus `ccweb-prompt` § "Schritt 1: Design-Runde und
  Tracking Issue" (Absatz "Staffel"):** Worum es
  geht / Empfehlung / verworfene Alternativen mit Grund — **die Empfehlung ist vorbelegt**. Kein
  eigenes a/b/c-Format mehr; das Playbook fuehrt die Design-Runden-Form nur einmal, Details in
  `reference/report.md`. Die uebrigen Labels brauchen keine Kurzform — ihre Korrektur steht im
  Text selbst.
- **Freigabe-Gate:** Kein Kommentar wird gepostet, bevor der Adressat die gesammelten Punkte
  gesehen und freigegeben hat (Phase 1, Schritt 4). Adressat ist der Mensch — oder im
  Controller-Modus der Controller (`.agents/rules/pr.md` § "Controller Mode"): dann geht Stufe A
  als Text-Datei an ihn, als Review-Freigabe, eine der drei erlaubten Nachrichten zwischen Sessions
  (`.agents/rules/pr.md` § "Session Traffic"); die Freigabe kommt als Text zurueck, und das Widget
  entfaellt.
- **Author-Loop:** Jeder Review-Kommentar fordert den Author explizit auf, nach dem Fix am PR
  zurueckzumelden.
- **Doku-only-PR:** kein Review-Gate, gruene Gates genuegen und der Review darf nachlaufen; Skills
  und Regeldateien sind ausdruecklich nicht doku-only (`.agents/rules/docs.md` § "Documentation").

## Eingabe

PR-Referenz, Pflicht (sonst danach **fragen**, nicht raten):

- `owner/repo#123` oder URL `https://github.com/owner/repo/pull/123`.
- Ausnahme `rere`: Re-Review des zuletzt in dieser Session per `/pr-poll-review` gereviewten PRs,
  ohne die Referenz erneut zu nennen. Ohne vorherigen Review in der Session weiterhin **fragen**.

Optional (nur fuer den Polling-Fallback relevant):

- `poll_interval` — Sekunden zwischen Polls (Default: 30; Remote-API-Rate-Limits beachten).
- `max_iterations` — Review-Runden bevor abgebrochen wird (Default: 10).
- `timeout_minutes` — Gesamttimeout (Default: 60).

Werkzeuge: `gh` ist der Standard (`AGENTS.md` § "Forge Tooling"); die Namen des GitHub-MCP stehen
daneben fuer Umgebungen ohne `gh`, etwa den claude.ai-Chat.

## Phase 1: Erstreview

1. **Kontext selbst beschaffen — es gibt keinen Review-Prompt.** Der Review-Chat startet mit einer
   Zeile ("Review PR `owner/repo`#N"); alles Weitere wird am Head gelesen, nie aus dem Chat
   uebernommen. Zu holen, in dieser Reihenfolge:

   - Diff via `gh pr diff <n> -R <repo>` (in einer Claude-Code-Session per REST
     `gh api repos/<repo>/pulls/<n> -H "Accept: application/vnd.github.diff"`, weil `gh pr` dort an
     GraphQL scheitert) bzw. `pull_request_read` (method=`get_diff`); bestehende
     Threads via `gh api repos/<repo>/pulls/<n>/comments` bzw. `get_review_comments`, um
     Doppel-Kommentare zu vermeiden.
   - **Spec-Datei** `docs/tasks/<issue>-<slug>.md`, **Tracking Issue** und **Decision-Log** — je am
     Head lesen (`gh api repos/<repo>/contents/<pfad>?ref=<sha>` bzw. `get_file_contents` am
     Head-SHA), nicht dem PR-Body glauben. Der PR-Body verlinkt sie.
   - **CI-Status** via `gh pr checks <n> -R <repo>` (per REST
     `gh api repos/<repo>/commits/<sha>/check-runs`) bzw. `get_check_runs`, **Default-Branch** aus
     dem PR-Objekt.
   - **Review-Modus** aus dem PR-Body (`hard vN` / `light` / `soft`); steht dort keiner, gilt kein
     Wellen-Bericht-Gate. Die Wellen werden gegen den Baustein des Modus geprueft:
     [`reference/review-modes.md`](reference/review-modes.md).
   - **Konstellation am PR messen.** `gh api user --jq .login` bzw. `get_me` zuerst gegen das Konto
     des menschlichen Inhabers des `maintainer`-Sitzes halten (auch im Controller-Modus nie das des
     Controllers): ist es dieses Konto, wird auf diesem Weg nichts gepostet, weder Kommentar noch
     Review noch Approve — anderer Weg unter anderem Konto oder STOP und Blockade melden
     (`AGENTS.md` § "Core Rules", `.agents/rules/pr.md` § "Accounts per Seat"). Dann gegen den
     PR-Autor: gleicher Account → nur `COMMENT` mit explizitem Blocking-/OK-Vermerk (GitHub sperrt
     `APPROVE` am eigenen PR); verschiedene Accounts → `APPROVE` erlaubt.

2. **Scan & Classify.** Filelist + Diff-Groesse ueberblicken, Review-Tiefe festlegen: kleine
   Touch-PRs duerfen knapp bleiben, grosse/breite PRs bekommen die volle Tiefe.
   Wie parallelisiert und welches Modell je Pass: [`reference/checks.md`](reference/checks.md).

3. **Code durchgehen, Punkte sammeln.** **Zuerst lesen und quittieren:**
   [`reference/checks.md`](reference/checks.md) — der Pruefkatalog, nach dem gesucht wird,
   und was pro Punkt festzulegen ist. **Mechanisch vorweg, in jeder Runde — Skript fahren:**
   `pwsh scripts/common/find-moved-fixes.ps1 -Repo <repo> -Pr <n>` — jeder `moved-fix` ist ein
   `issue: (blocking)` ohne Ermessen. Ohne Skript: jede waehrend des PRs neu in den Body des
   Tracking Issues, in `roadmap.md` oder `backlog.md` gekommene Zeile von Hand gegen die Dateiliste
   des Diffs halten (`reference/checks.md` § "Backlog-Gegencheck"). Dann: Zeile fuer Zeile, kein
   Sampling; verwandte Files/Configs/Tests mitpruefen, nicht nur den Diff-Rand. **Code-Aenderung
   ohne Doku-Delta** ist ein `issue: (blocking)` (`reference/checks.md` § "Doku-Delta").
   Conventional Commits der Commit-Messages mitbewerten; den Default-Branch aus dem PR-Objekt
   lesen, nicht `master`/`main` annehmen.

4. **Freigabe-Gate (vor jeder Veroeffentlichung).** **Zuerst lesen und quittieren:**
   [`reference/report.md`](reference/report.md) — Stufe A, Stufe B, die Widget-Befuellung, die
   beiden Invarianten und die Zeilen-Datei der Runde. Dann: zweistufig — erst lesbarer Chat-Report,
   dann erst die Freigabe. Nie direkt in die Freigabe springen. **Das Widget gibt es nur im
   claude.ai-Chat mit dem Maintainer.** Dort wird die VORLAGE-Zone, die Stufe B 1:1 uebernimmt, aus
   dem Playbook geholt: `https://raw.githubusercontent.com/ww3d/playbook/main/.claude/skills/pr-poll-review/reference/widget-reference.html`
   bzw. `get_file_contents` (owner `ww3d`, repo `playbook`, gleicher Pfad). In Claude Code gibt es
   keinen Widget-Host und keine Datei im Consumer-Repo; dort traegt der Text-Pfad die Freigabe
   allein. Im Controller-Modus ist der Controller der Adressat, ohne Widget (Kernprinzip
   "Freigabe-Gate").

5. **Zeilen-Datei der Runde** schreiben und pruefen, bevor gepostet wird — eine Zeile je Punkt,
   auch je verworfenem. Sie geht als JSONL-Block in den Body des Reviews; der Autor committet sie
   mit seinem naechsten Push. **Der Reviewer pusht nie auf den PR-Zweig**
   (`reference/report.md` § "Zeilen-Datei der Runde"). Skript fahren:
   `pwsh scripts/common/test-ledger.ps1 -Path <datei>`; ohne Skript: jede Zeile ein JSON-Objekt mit
   `id`, `status`, `satz`, `grund`, `quelle` und keinem fremden Feld.

6. **Review-Kopf festhalten**, nach dem Holen des Heads, mit einem eigenen Befehl, direkt vor dem
   Posten — der Hook `require-rule-read.sh` liest diese Zeile, genau in dieser Form (voller
   40-stelliger SHA):

   ```bash
   echo "review-head | <owner>/<repo>#<n> | $(gh api repos/<owner>/<repo>/pulls/<n> --jq .head.sha)"
   ```

   Ohne `gh`: den vollen Head-SHA aus `pull_request_read` (method=`get`) in derselben Zeilenform
   ausgeben. Bewegt sich der Head, wird die Zeile neu ausgegeben; postet ein Sub-Agent, gibt er sie
   selbst aus. Der Hook sperrt den Post ausserdem, solange `reference/checks.md` und
   `reference/gates.md` in dieser Session (bzw. diesem Sub-Agenten) nicht vollstaendig gelesen sind
   — der Read selbst zaehlt, die Quittungszeile ist zweite Quelle.

7. **Review posten** via `gh api` auf den Reviews-Endpunkt bzw. `pull_request_review_write` (nur
   freigegebene + custom Punkte + entschiedene Fragen):
   - `event`: `REQUEST_CHANGES` wenn ein blockierender Punkt dabei ist, sonst `COMMENT`. Ein Review
     aus lauter Nits ist nie `REQUEST_CHANGES`.
   - Inline-Comments mit `path` + `line` bevorzugen, jeder mit dem Label als Prefix (`issue:
     (blocking)` …); Body mit knapper, nach Blocking-Wirkung geordneter Zusammenfassung **plus
     expliziter Aufforderung an den Author, nach dem Fix zurueckzumelden**.
   - **Jeder `nitpick:` geht als Suggested Change**, und eine entschiedene offene Frage geht
     als Anweisung an den Author statt als Frage. Beide Formen:
     [`reference/report.md`](reference/report.md).

8. Den Lifecycle-Trigger setzen: bei `REQUEST_CHANGES` den Autor anstossen, den PR auf Draft
   zuruecksetzen zu lassen (`.agents/rules/pr.md` § "PR Lifecycle", Schritt 6). Ein Review aus
   lauter nicht blockierenden Punkten wirft den PR **nicht** auf Draft zurueck. HEAD-SHA des
   aktuellen Stands merken (`reviewed_sha`); Thread-IDs der eigenen Inline-Comments notieren (fuer
   spaeteres Resolve).

## Phase 2: Auf Aenderungen warten

- **Bevorzugt (Claude Code Web/Remote):** `subscribe_pr_activity` aufrufen und den Turn beenden.
  Neue Pushes und Kommentare kommen als `[github-webhook-activity]`-Events zurueck. **Nicht** mit
  `sleep` aktiv pollen.
- **Fallback (ohne Webhooks):** alle `poll_interval` Sekunden den Head abfragen
  (`gh api repos/<repo>/pulls/<n> --jq .head.sha` bzw. `pull_request_read`, method=`get`) und mit
  `reviewed_sha` vergleichen, bis er sich aendert oder `max_iterations` / `timeout_minutes`
  erreicht sind. Transiente API-Fehler tolerieren.

Webhooks liefern CI-Erfolg, neue Pushes und Merge-Konflikt-Uebergaenge nicht zuverlaessig — bei
Unsicherheit den PR-Zustand aktiv nachladen.

## Phase 3: Re-Review

1. Diff zwischen `reviewed_sha` und neuem `head_sha` holen.
2. Pro vorherigem Comment pruefen: Stelle geaendert? Punkt adressiert? Zusaetzlich die Red-Flag-/
   Doku-Integritaets-/Doku-Delta-/Beyond-the-diff-Checks aus Phase 1 auf das neu Dazugekommene
   anwenden — ein Fix-Commit kann ein Decision-Log kaputt-pasten oder einen Beleg tot machen, der
   vorher stimmte.
3. Auswertung (nach Blocking-Wirkung):
   - **Alle blockierenden adressiert, keine neuen** → Phase 4.
   - **Rest- oder Neu-Punkte** → sammeln → **Freigabe-Gate, Zeilen-Datei, Review-Kopf (Phase 1,
     Schritte 4-6)** → posten → **die in dieser Runde adressierten Threads sofort resolven**
     (`resolve_thread` mit `threadId=PRRT_...`, bzw. die GraphQL-Mutation `resolveReviewThread`
     per `gh api graphql`, wo die Umgebung GraphQL zulaesst) → `reviewed_sha` aktualisieren,
     zurueck zu Phase 2.

**Resolven passiert in jeder Runde, nicht erst am Ende** — wer bis Phase 4 wartet, laesst den Author
raten, was schon erledigt ist, und haengt die Restpunkte in einer Wand alter Threads.

## Phase 4: Resolve + Abschluss

[HARD-GATE]
Vor jedem **positiven Abschluss-Verdikt**, ausnahmslos — jeder Punkt muss erfuellt sein.

**Zuerst lesen und quittieren:** [`reference/gates.md`](reference/gates.md) — was ein
positives Abschluss-Verdikt ueberhaupt ist, die Kasuistik zu den Punkten 4, 5 und 7, die
STOP-Tabelle und die Gegenpruefung. Ohne diesen Lauf faellt das Verdikt nicht.

1. **CI zaehlt als tot**, bis die Org-CI produktiv laeuft — in allen Repos, auch mit self-hosted
   Runner (`.agents/rules/pr.md` § "CI Counts as Dead Org-Wide"). Was ein Workflow meldet, ob ohne
   Schritte, rot oder gruen, ist kein Blocker und kein Befund. Statt des CI-Status zaehlt der lokale
   Lauf von Tests und CI-Skripten (oder der Windows-Lauf des Maintainers) im PR-Body unter "Wie
   getestet", als Laufzeile nach `.agents/rules/pr.md` § "Test Runs"; fehlt er, **nicht**
   approven. Einen vollen Lauf faehrt der Reviewer nicht; er faehrt selbst die gefilterten Tests
   der betroffenen Klassen und mindestens eine Mutationsprobe (`.agents/rules/pr.md` § "Test Runs")
   und nennt beide im Review-Body.
2. Keine Merge-Konflikte — bei `mergeable`/`mergeable_state` nicht clean **nicht** approven,
   Status melden. (`blocked` = pending Required-Review, **kein** Konflikt — haelt nichts auf.)
3. Kein CI-Gaming — wurden Tests/Coverage/Trigger manipuliert, um gruen zu werden, **nicht**
   approven, unabhaengig vom CI-Signal.
4. **Eigene Threads nach Blocking-Wirkung — Vorbedingung des Schreibens, keine Nachpruefung.** Erst
   resolven, dann schreiben: die Review-Kommentare frisch abrufen (`get_review_comments` bzw.
   `gh api`), die **selbst eroeffneten** Threads durchgehen, jeden am Head adressierten Punkt jetzt
   resolven. Wie im Einzelfall gerechnet wird: `reference/gates.md`.
5. **Anker-Issue, Auto-Close-Zeile und Tracking Issue — eine Pruefung, am Head.**
   - **Nennt der Body sein Anker-Issue ueberhaupt — mit `Closes` oder mit `Refs`?** Fehlt beides,
     ist das ein eigener `issue: (blocking)` (`.agents/rules/pr.md` § "PR / MR Description").
   - **Auto-Close-Zeile:** geprueft wird die **Zeile**, nicht das Vorkommen — eine eigene Zeile,
     Schliess-Keyword am Zeilenanfang, mit Nummer. Fehlt sie, wo das Ziel keinen offenen Punkt
     mehr hat — **nicht** approven (blocken, oder vom Merger per Skript schliessen lassen).
   - **Existiert das Tracking Issue des Designs und ist es offen?** · **Stehen die in diesem PR
     zurueckgestellten Punkte in seinem Body — und ist keiner davon ein verschobener Fix
     (`find-moved-fixes.ps1` am Head: null `moved-fix`)?** · **Zeigt eine Auto-Close-Zeile auf ein
     Issue mit Checkliste, waehrend in dessen ganzem Body noch ein offener Punkt steht?** Gerechnet
     wird gegen die Zeile, nie gegen ein Vorkommen im Fliesstext.
   - **Ergebnis muss null ungetragene Punkte sein** — sonst **nicht approven**. Keywords, Ausnahme
     fuer ein Issue mit offener Checkliste, was als zurueckgestellt zaehlt, und die vierte Frage:
     `reference/gates.md`.
6. Zwei getrennte Verdikte, beide gruen: **Spec** (tut der Diff genau das Bestellte, nichts zu
   viel/zu wenig?) und **Quality** (handwerklich sauber: Tests, Struktur, keine Magic Numbers?).
7. Beleg-Pflicht — behauptet der PR-Body **etwas, das der Reviewer nicht im Diff sieht**
   (Testlauf, Benchmark, "verifiziert") ohne stabilen Anker, **nicht** approven (blockt,
   analog zum Auto-Close-Zeilen-Check aus Punkt 5). Welcher Anker zaehlt: `reference/gates.md`.
[/HARD-GATE]

Wenn sauber: Report und Zeilen-Datei zuerst als `COMMENT`-Review (Phase 1, Schritt 5); hat der
Autor die Zeilen-Datei committet, Review-Kopf am neuen Head (Schritt 6), dann `APPROVE` mit knappem
Body (Lifecycle-Schritt 7) — die eigenen Threads sind hier bereits aufgeloest (Punkt 4), fremde
bleiben unberuehrt. Bei einem self-authored PR sperrt GitHub `APPROVE`, dann `event: COMMENT` mit
der eigenen Zeile `Review-Verdikt: approve <head-sha>`, die das Merge-Gate liest.

**Ohne Controller** setzt der Skill mit dem Approve bzw. der Verdikt-Zeile das Tracking Issue auf
`state:gate` und nimmt `state:review` ab (`.agents/rules/pr.md` § "State Labels";
`gh api repos/<repo>/issues/<N>/labels -f "labels[]=state:gate"`,
`gh api -X DELETE repos/<repo>/issues/<N>/labels/state:review`; Connector: `issue_write`); im
Controller-Modus setzt es der Controller.

Den Nutzer informieren, die Nummer als Link: "owner/repo#N (Titel) abgeschlossen. Merge **nicht**
ausgefuehrt — wer merged, faehrt vorher `scripts/common/test-merge-ready.ps1` und schliesst danach
das Tracking Issue mit `scripts/common/close-tracking-issue.ps1` (`.agents/rules/pr.md` § "Merge")."

## Phase 5: Funktionale Zusammenfassung

Nach dem Abschluss-Verdikt im **Chat** liefern — im Controller-Modus als Abschnitt im Body des
Approves, denn der Controller prueft am PR, und eine Fertig-Meldung zwischen Sessions gibt es nicht
(`.agents/rules/pr.md` § "Session Traffic"):

- Vorher/Nachher-Zustand
- Happy Path
- Edge Cases
- Was bewusst unberuehrt bleibt
- Architektonischer Beitrag

**Damit endet der Skill.** Er wartet nicht auf den Merge; was nach dem Merge zu tun ist und warum
es beim Merger liegt: [`reference/gates.md`](reference/gates.md) § "Nach dem Merge".

## Strikte Regeln

Nur was nirgends sonst in dieser Datei oder in `reference/` steht:

- **Das Widget wird, wo ein Mensch im claude.ai-Chat der Adressat ist, immer inline gerendert**
  (Visualizer/`show_widget`) — in Claude Code und im Controller-Modus gibt es keins; nie als
  Datei-Anhang, nie als Code-Block, nie als Beschreibung dessen, was es enthielte. Die
  VORLAGE-Zone rechnet mit den Host-Variablen; ausserhalb des Hosts ist sie ungestyltes Markup und
  damit wertlos. Aufwand ist kein Grund, den Kanal zu wechseln.
- **Nie einen Thread resolven, dessen Punkt noch aussteht.**
- **Niemals** automatisch mergen — `gh pr merge` bzw. `merge_pull_request` nur auf separate,
  explizite Anweisung; wer merged, regeln `.agents/rules/pr.md` § "PR Lifecycle" (Schritt 8) und
  § "Controller Mode".
- **Niemals** einen PR im Review schliessen/wieder oeffnen.
- Bei Force-Push oder Branch-Reset: Loop pausieren, beim Nutzer nachfragen.
- Inhaltliche Antworten auf beiden Seiten spiegeln (lokaler Chat + GitHub-Thread); reine
  Acknowledgements nicht doppeln — das Resolven sagt es, und in den Chat geht **eine**
  Zusammenfassung je Review-Runde (`.agents/rules/pr.md` § "Mirroring GitHub Conversations").

## Repo-Konventionen

- Conventional Commits beim Bewerten der Commit-Messages erwarten.
- Default-Branch aus dem PR-Objekt lesen.
- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); das
  GitHub MCP nur als Fallback, wenn `gh` etwas nicht sauber kann, oder fuer MCP-only-Tools.
- Falls via MCP gereviewt wird: Inline-Comments in drei Schritten — `create` (pending) →
  `add_comment_to_pending_review` → `submit_pending` (`event: COMMENT`/`REQUEST_CHANGES`); sonst
  scheitert der Inline-Review still. Bei `gh` entfaellt das.
- Bei Backport-relevanten Punkten pruefen, ob im betroffenen Upstream-/Nachbar-Repo ein
  Tracking-Issue vorliegt.
