---
name: pr-poll-review
description: 'Reviewt einen GitHub Pull Request iterativ bis zum Approve und fuellt die reviewer-Rolle des Playbook-PR-Lifecycles. Beschafft den Kontext selbst am Head (Spec-Datei, Tracking Issue, Decision-Log, CI, Konstellation) — ein Review-Prompt existiert nicht. Klassifiziert den PR, faehrt Agent-Red-Flag- und Beyond-the-diff-Checks und meldet jeden Punkt in Conventional Comments: issue / nitpick / question / suggestion mit (blocking) oder (non-blocking). Ein nitpick blockt nie und geht als Suggested Change raus; eine blockende question kommt zur Abstimmung, mit a) SOTA b) andere c) Empfehlung, Empfehlung vorbelegt. Legt alles vor jeder Veroeffentlichung erst als Chat-Report plus Widget zur Freigabe vor, postet dann, wartet auf Pushes, reviewt neu und approved erst bei gruener CI ohne Merge-Konflikte. Merged nie selbst und schliesst nach dem Merge das Tracking Issue. Triggert bei "review und wenn ok approve", "pr pollen", "check PR [ref]", "approve sobald die changes da sind", "rere". Nur fuer GitHub-PRs.'
metadata:
  version: "8.0.0"
  source: ww3d/playbook
---

# PR Review & Approve Workflow

Iterativer Review-Loop fuer GitHub-PRs. Faehrt von Erstreview bis Approve durch und fuellt die
`reviewer`-Rolle aus `.agents/rules/pr.md` § "PR Lifecycle" (Schritte 9-11). Der Merge (Schritt 12)
bleibt beim `maintainer` — dieser Skill merged nie.

## Kernprinzip

- **Session-Start-Pflicht:** Vor Phase 1 gilt `AGENTS.md` § "Session Start: Read Before Anything
  Else" des Ziel-Repos — Pflichtkern (AGENTS-Kern, `CLAUDE.md`, Audit-Kopf) lesen und je Datei mit
  Blob-SHA quittieren. Der Review laeuft am Head des Repos, nie aus dem Chat-Verlauf oder dem
  Gedaechtnis.
- **Einsatzpunkt-Quittung als Eingangsschritt.** Dieser Skill loest vier Trigger aus: er postet
  einen Review, er beurteilt einen PR-Body, er prueft Traeger und er wiegt Belege. Vor Phase 1
  werden darum `.agents/rules/review.md`, `.agents/rules/pr.md`, `.agents/rules/carrier.md` und
  `.agents/rules/evidence.md` **vollstaendig gelesen und quittiert** — Format und Pflicht stehen in
  `AGENTS.md` § "Session Start: Read Before Anything Else", Baustein 3, einmal je Session je Datei.
  In ccweb erzwingt der `require-rule-read.sh`-Hook dasselbe; wo kein Hook laeuft, ist dieser
  Schritt die einzige Absicherung. Die Regeltexte werden hier **nicht** gedoppelt, sondern gelesen.
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
  **ausserhalb des PR-Scopes haelt den PR nicht auf**: er wird eine eigene Aufgabe und geht ins
  Tracking Issue oder in den Backlog (`.agents/rules/review.md` § "Review Comments").
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
- **a/b/c bei `question: (blocking)`:** Jede wird mit drei Perspektiven zur Auswahl aufbereitet:
  **a) SOTA/modern** (der State-of-the-Art-Ansatz), **b) was andere / die Grossen machen** (verbreitete
  Praxis grosser Projekte), **c) Empfehlung** (Claudes konkreter Rat fuer genau diesen PR) — **c) ist
  vorbelegt**. Wo a) oder b) sich nicht sauber belegen laesst, den Slot weglassen statt raten. Die
  uebrigen Labels brauchen kein a/b/c — ihre Korrektur steht im Text selbst.
- **Freigabe-Gate:** Kein Kommentar wird gepostet, bevor der User die gesammelten Punkte gesehen und
  freigegeben hat (Phase 1, Schritt 4).
- **Author-Loop:** Jeder Review-Kommentar fordert den Author explizit auf, nach dem Fix am PR
  zurueckzumelden.
- **Doku-only-PR:** Beruehrt der Diff ausschliesslich `docs/**` und `*.md` im Repo-Root — kein Code,
  kein Workflow, **keine Skills**, **keine Regeldatei unter `.agents/rules/**`**, kein `VERSION` —,
  genuegt gruene CI; der Review ist kein Gate und darf nachlaufen (`.agents/rules/docs.md`
  § "Documentation"). Skills und Regeldateien sind ausdruecklich nicht doku-only.

## Eingabe

PR-Referenz, Pflicht (sonst danach **fragen**, nicht raten):

- `owner/repo#123` oder URL `https://github.com/owner/repo/pull/123`.
- Ausnahme `rere`: Re-Review des zuletzt in dieser Session per `/pr-poll-review` gereviewten PRs,
  ohne die Referenz erneut zu nennen. Ohne vorherigen Review in der Session weiterhin **fragen**.

Optional (nur fuer den Polling-Fallback relevant):

- `poll_interval` — Sekunden zwischen Polls (Default: 30; Remote-API-Rate-Limits beachten).
- `max_iterations` — Review-Runden bevor abgebrochen wird (Default: 10).
- `timeout_minutes` — Gesamttimeout (Default: 60).

## Phase 1: Erstreview

1. **Kontext selbst beschaffen — es gibt keinen Review-Prompt.** Der Review-Chat startet mit einer
   Zeile ("Review PR `owner/repo`#N"); alles Weitere wird am Head gelesen, nie aus dem Chat
   uebernommen. Zu holen, in dieser Reihenfolge:

   - Diff via `pull_request_read` (method=`get_diff`); bestehende Threads via
     `get_review_comments`, um Doppel-Kommentare zu vermeiden.
   - **Spec-Datei** `docs/tasks/<issue>-<slug>.md`, **Tracking Issue** und **Decision-Log** — je am
     Head lesen (`get_file_contents` am Head-SHA bzw. `gh`), nicht dem PR-Body glauben. Der PR-Body
     verlinkt sie.
   - **CI-Status** via `get_check_runs`, **Default-Branch** aus dem PR-Objekt.
   - **Review-Modus** aus dem PR-Body (`hard vN` / `light` / `soft`); steht dort keiner, gilt kein
     Wellen-Bericht-Gate.
   - **Konstellation am PR messen.** `get_me` gegen den PR-Autor halten: gleicher Account → nur
     `COMMENT` mit explizitem Blocking-/OK-Vermerk (GitHub sperrt `APPROVE` am eigenen PR);
     verschiedene Accounts → `APPROVE` erlaubt.

2. **Scan & Classify.** Filelist + Diff-Groesse ueberblicken, Review-Tiefe festlegen: kleine
   Touch-PRs duerfen knapp bleiben, grosse/breite PRs bekommen die volle Tiefe.
   Wie parallelisiert und welches Modell je Pass: [`reference/checks.md`](reference/checks.md).

3. **Code durchgehen, Punkte sammeln.** **Zuerst lesen und quittieren:**
   [`reference/checks.md`](reference/checks.md) — der Pruefkatalog, nach dem gesucht wird,
   und was pro Punkt festzulegen ist. Dann: Zeile fuer Zeile, kein Sampling; verwandte
   Files/Configs/Tests mitpruefen, nicht nur den Diff-Rand. Conventional Commits der
   Commit-Messages mitbewerten; den Default-Branch aus dem PR-Objekt lesen, nicht
   `master`/`main` annehmen.

4. **Freigabe-Gate (vor jeder Veroeffentlichung).** **Zuerst lesen und quittieren:**
   [`reference/report.md`](reference/report.md) — Stufe A, Stufe B, die Widget-Befuellung
   und die beiden Invarianten; die VORLAGE-Zone, die Stufe B 1:1 uebernimmt, steht in
   [`reference/widget-reference.html`](reference/widget-reference.html). Dann: zweistufig —
   erst lesbarer Chat-Report, dann erst die Freigabe. Nie direkt in die Freigabe springen.

5. **Review posten** via `pull_request_review_write` (nur freigegebene + custom Punkte + entschiedene
   Fragen):
   - `event`: `REQUEST_CHANGES` wenn ein blockierender Punkt dabei ist, sonst `COMMENT`. Ein Review
     aus lauter Nits ist nie `REQUEST_CHANGES`.
   - Inline-Comments mit `path` + `line` bevorzugen, jeder mit dem Label als Prefix (`issue:
     (blocking)` …); Body mit knapper, nach Blocking-Wirkung geordneter Zusammenfassung **plus
     expliziter Aufforderung an den Author, nach dem Fix zurueckzumelden**.
   - **Jeder `nitpick:` geht als Suggested Change**, und eine entschiedene offene Frage geht
     als Anweisung an den Author statt als Frage. Beide Formen:
     [`reference/report.md`](reference/report.md).

6. Den Lifecycle-Trigger setzen: bei `REQUEST_CHANGES` den Autor anstossen, den PR auf Draft
   zuruecksetzen zu lassen (Schritt 10). Ein Review aus lauter nicht blockierenden Punkten wirft den
   PR **nicht** auf Draft zurueck. HEAD-SHA des aktuellen Stands merken (`reviewed_sha`);
   Thread-IDs der eigenen Inline-Comments notieren (fuer spaeteres Resolve).

## Phase 2: Auf Aenderungen warten

- **Bevorzugt (Claude Code Web/Remote):** `subscribe_pr_activity` aufrufen und den Turn beenden.
  Neue Pushes und Kommentare kommen als `[github-webhook-activity]`-Events zurueck. **Nicht** mit
  `sleep` aktiv pollen.
- **Fallback (reiner Chat-Kontext ohne Webhooks):** alle `poll_interval` Sekunden
  `pull_request_read` (method=`get`) abfragen und `head_sha` mit `reviewed_sha` vergleichen, bis er
  sich aendert oder `max_iterations` / `timeout_minutes` erreicht sind. Transiente API-Fehler
  tolerieren.

Webhooks liefern CI-Erfolg, neue Pushes und Merge-Konflikt-Uebergaenge nicht zuverlaessig — bei
Unsicherheit den PR-Zustand aktiv nachladen.

## Phase 3: Re-Review

1. Diff zwischen `reviewed_sha` und neuem `head_sha` holen.
2. Pro vorherigem Comment pruefen: Stelle geaendert? Punkt adressiert? Zusaetzlich die Red-Flag-/
   Doku-Integritaets-/Beyond-the-diff-Checks aus Phase 1 auf das neu Dazugekommene anwenden — ein
   Fix-Commit kann ein Decision-Log kaputt-pasten oder einen Beleg tot machen, der vorher stimmte.
3. Auswertung (nach Blocking-Wirkung):
   - **Alle blockierenden adressiert, keine neuen** → Phase 4.
   - **Rest- oder Neu-Punkte** → sammeln → **Freigabe-Gate (Phase 1, Schritt 4)** → posten →
     **die in dieser Runde adressierten Threads sofort resolven** (`resolve_thread`) →
     `reviewed_sha` aktualisieren, zurueck zu Phase 2.

**Resolven passiert in jeder Runde, nicht erst am Ende** — wer bis Phase 4 wartet, laesst den Author
raten, was schon erledigt ist, und haengt die Restpunkte in einer Wand alter Threads.

## Phase 4: Resolve + Abschluss

[HARD-GATE]
Vor jedem **positiven Abschluss-Verdikt**, ausnahmslos — jeder Punkt muss erfuellt sein.

**Zuerst lesen und quittieren:** [`reference/gates.md`](reference/gates.md) — was ein
positives Abschluss-Verdikt ueberhaupt ist, die Kasuistik zu den Punkten 4, 5, 7 und 8, die
STOP-Tabelle und die Gegenpruefung. Ohne diesen Lauf faellt das Verdikt nicht.

1. CI gruen — `pull_request_read` method=`get_check_runs`.
2. Keine Merge-Konflikte — bei `mergeable`/`mergeable_state` nicht clean **nicht** approven,
   Status melden. (`blocked` = pending Required-Review, **kein** Konflikt — haelt nichts auf.)
3. Kein CI-Gaming — wurden Tests/Coverage/Trigger manipuliert, um gruen zu werden, **nicht**
   approven, unabhaengig vom CI-Signal.
4. **Eigene Threads nach Blocking-Wirkung — Vorbedingung des Schreibens, keine Nachpruefung.** Erst
   resolven, dann schreiben: `get_review_comments` frisch abrufen, die **selbst eroeffneten**
   Threads durchgehen, jeden am Head adressierten Punkt jetzt `resolve_thread`
   (`threadId=PRRT_...`). Wie im Einzelfall gerechnet wird: `reference/gates.md`.
5. **Traegt der PR-Body eine Auto-Close-Zeile?** Geprueft wird die **Zeile**, nicht das Vorkommen:
   eine eigene Zeile, Schliess-Keyword am Zeilenanfang, mit Nummer. Fehlt die
   Zeile — **nicht** approven (blocken, oder nach dem Merge manuell schliessen). Form,
   Keywords, Vorkommen-vs-Zeile und die Tracking-Issue-Ausnahme: `reference/gates.md`.
6. Zwei getrennte Verdikte, beide gruen: **Spec** (tut der Diff genau das Bestellte, nichts zu
   viel/zu wenig?) und **Quality** (handwerklich sauber: Tests, Struktur, keine Magic Numbers?).
7. Beleg-Pflicht — behauptet der PR-Body **etwas, das der Reviewer nicht im Diff sieht**
   (Testlauf, Benchmark, "verifiziert") ohne stabilen Anker, **nicht** approven (blockt,
   analog zum `Closes #`-Check aus Punkt 5). Welcher Anker zaehlt: `reference/gates.md`.
8. **Tracking-Issue-Gate — drei Fragen am Head.** **Existiert das Tracking Issue des Designs und
   ist es offen?** · **Stehen die in diesem PR zurueckgestellten Punkte in seinem Body?** ·
   **Traegt der PR-Body eine Auto-Close-Zeile auf genau dieses Issue, waehrend in dessen
   Body noch ein offener Punkt steht?** Gerechnet wird gegen die **Zeile** aus Punkt 5, nie gegen
   ein Vorkommen im Fliesstext: sonst blockt hier die Begruendung, warum bewusst keine gesetzt
   wurde. **Ergebnis muss null ungetragene Punkte sein** — sonst **nicht approven**,
   dieselbe Haerte wie der Auto-Close-Zeilen-Check aus Punkt 5. Was als zurueckgestellt
   zaehlt, und die vierte Frage: `reference/gates.md`.
[/HARD-GATE]

Wenn sauber: `pull_request_review_write` mit `event`: `APPROVE` und knappem Body (Schritt 11) — die
eigenen Threads sind hier bereits aufgeloest (Punkt 4), fremde bleiben unberuehrt; bei einem
self-authored PR sperrt GitHub `APPROVE`, dann `event: COMMENT`. Den Nutzer informieren: "PR #N
abgeschlossen. Merge **nicht** ausgefuehrt — der `maintainer` merged." Danach **nicht** aussteigen:
Phase 5 haengt am Merge-Ereignis.

## Phase 5: Funktionale Zusammenfassung

Nach dem Abschluss-Verdikt im **Chat** liefern (nicht im PR):

- Vorher/Nachher-Zustand
- Happy Path
- Edge Cases
- Was bewusst unberuehrt bleibt
- Architektonischer Beitrag

**Das Approve ist nicht das Ende des Auftrags.** Nach dem Abschluss-Verdikt endet die Session
nicht: sie abonniert erneut (`subscribe_pr_activity`, dasselbe Mittel wie Phase 2) und wartet auf
das `merged`-Event. Ohne Webhook-Faehigkeit gilt der Poll-Fallback aus Phase 2 — `pull_request_read`
(method=`get`) bis `merged` steht oder das Timeout greift. Erst dieses Ereignis loest das
`[MERGE-GATE]` unten aus.

[MERGE-GATE] **Nach dem Merge: das Tracking Issue schliessen — oder begruendet offen lassen.**
Ausnahmslos, jeder Punkt muss erfuellt sein; dieselbe Haerte wie das `[HARD-GATE]` in Phase 4. Das
ist `reviewer`-Arbeit, nicht `maintainer`-Arbeit (`.agents/rules/carrier.md` § "Tracking Issue"),
und der Grund ist mechanisch: der Body ist in Phase 4 Punkt 8 ohnehin frisch am Head gelesen worden.

1. Body am Head **nachzaehlen**, nicht erinnern: steht noch eine unabgehakte Checkbox darin?
2. Die Pruefung aus `.agents/rules/carrier.md` § "Carrier Requirement" fahren — **was zeigt auf
   dieses Issue?** Jeder Punkt, der es als Traeger nennt, steht vorher woanders oder ist
   ausdruecklich als mit ihm erledigt vermerkt.
3. Beides sauber → schliessen. Sonst **offen lassen** und in **einer Zeile** sagen, warum und was
   noch aussteht. Ein Punkt wird umgehaengt, weil er nicht mehr zu diesem Design gehoert — nie,
   um schliessen zu koennen.
[/MERGE-GATE]

Warum das Warten dasteht, was gilt, wenn du nicht schliessen kannst oder das Warten
auslaeuft, und die Rueckmeldung nach dem Merge: [`reference/gates.md`](reference/gates.md).

## Strikte Regeln

Nur was nirgends sonst in dieser Datei oder in `reference/` steht:

- **Das Widget wird immer inline gerendert** (Visualizer/`show_widget`) — nie als Datei-Anhang,
  nie als Code-Block, nie als Beschreibung dessen, was es enthielte. Die VORLAGE-Zone rechnet
  mit den Host-Variablen; ausserhalb des Hosts ist sie ungestyltes Markup und damit wertlos.
  Aufwand ist kein Grund, den Kanal zu wechseln.
- **Nie einen Thread resolven, dessen Punkt noch aussteht.**
- **Niemals** automatisch mergen — `merge_pull_request` nur auf separate, explizite Anweisung;
  der Merge ist `maintainer`-only.
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
