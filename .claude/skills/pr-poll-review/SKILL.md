---
name: pr-poll-review
description: 'Reviewt einen GitHub Pull Request iterativ bis zum Approve und fuellt damit die `reviewer`-Rolle des Playbook-PR-Lifecycles. Klassifiziert den PR, faehrt Agent-Red-Flag- und Beyond-the-diff-Checks, sammelt Punkte mit Severity, schreibt sie dem User vor jeder Veroeffentlichung erst als lesbaren Chat-Report aus und legt sie ihm dann zur Freigabe vor (Default: alle Findings werden gepostet, der User streicht nur einzelne + Custom). Schickt dann einen Review (Inline-Comments + Summary), wartet auf neue Pushes des Authors, reviewt nach jeder Aenderung neu und approved erst wenn alle Punkte adressiert sind, CI gruen ist und keine Merge-Konflikte offen sind. Merged nie selbst. Triggert wenn der User einen PR reviewen UND bei OK approven lassen will: "review und wenn ok approve", "pr pollen", "check PR [ref]", "approve sobald die changes da sind", "rere" (Re-Review des zuletzt in der Session gereviewten PRs). Nicht fuer einen einmaligen Review ohne Approve. Nur fuer GitHub-PRs (nicht GitLab/Forgejo).'
metadata:
  version: "2.0.0"
  source: ww3d/playbook
---

# PR Review & Approve Workflow

Iterativer Review-Loop fuer GitHub-PRs. Faehrt von Erstreview bis Approve durch und fuellt die
`reviewer`-Rolle aus `AGENTS.md` § "PR Lifecycle" (Schritte 9-11). Der Merge (Schritt 12) bleibt
beim `maintainer` — dieser Skill merged nie.

## Kernprinzip

- **Ziel:** Alle mit dem PR zusammenhaengenden Punkte werden im selben PR sauber gefixt und
  geradegezogen — nicht nur das Angefasste, sondern auch verwandte Files, Configs und Tests
  (beyond-the-diff).
- **Agent-Autor-Annahme:** Der Author (ein Coding-Agent, z.B. Claude Code oder Copilot) produziert
  Code, der sauber aussieht, aber leise mehr Redundanz und Tech-Debt traegt als menschlicher. Nicht
  vom Oberflaechen-Eindruck taeuschen lassen — gezielt nach den Agent-typischen Fehlerklassen
  suchen (Phase 1, Red-Flags).
- **Freigabe-Gate:** Kein Kommentar wird gepostet, bevor der User die gesammelten Punkte gesehen und
  freigegeben hat (Phase 1, Schritt 4).
- **Author-Loop:** Jeder Review-Kommentar fordert den Author explizit auf, nach dem Fix am PR
  zurueckzumelden.

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

1. Diff holen via `pull_request_read` (method=`get_diff`); bestehende Threads via
   `get_review_comments` lesen, um Doppel-Kommentare zu vermeiden.

2. **Scan & Classify.** Filelist + Diff-Groesse ueberblicken, Review-Tiefe festlegen: kleine
   Touch-PRs duerfen knapp bleiben, grosse/breite PRs bekommen die volle Tiefe.
   - **Sub-Agent-Parallelisierung bei grossen/breiten PRs:** parallele Spezial-Passes starten
     (Security, Quality+Reuse, Tests, Docs), jeder gegen die Kriterien aus Schritt 3 (Red-Flags,
     Test-Evidence, Konsistenz). Als Coordinator: Findings deduplizieren, echte
     Severity bewerten, false positives filtern, **einen** konsolidierten Punkte-Satz bilden.
   - **Modellwahl pro Sub-Agent selbst nach Aufgabe treffen (soweit der Harness Modellwahl
     exponiert):** jeweils das *kleinste und schnellste* Modell waehlen, mit dem die Teilaufgabe
     noch 100% praezise, sauber und SOTA geloest wird. Leichte, textlastige Passes (Docs, einfache
     Konsistenz-Checks) klein/schnell; anspruchsvolle Logik-/Security-Passes und die
     Coordinator-Rolle das staerkste Modell.

3. **Code durchgehen, Punkte sammeln.** Zeile fuer Zeile, kein Sampling; verwandte Files/Configs/
   Tests mitpruefen, nicht nur den Diff-Rand. Conventional Commits der Commit-Messages mitbewerten;
   den Default-Branch aus dem PR-Objekt lesen, nicht `master`/`main` annehmen. Dabei gezielt:
   - **Agent-Red-Flags (zuerst, harte Sachen):**
     - **CI-Gaming** — Tests entfernt/geskippt/umbenannt, Coverage-Threshold gesenkt, `|| true`
       angehaengt, Workflow-Trigger eingeschraenkt. **Harter Blocker**, immer.
     - **Reuse-Blindness** — pro neuer Util/Helper/Klasse kurz im Repo nach einem bestehenden
       Aequivalent suchen. Dupliziert der PR vorhandene Logik: Konsolidierung im selben PR
       erzwingen, nicht nur kommentieren. Hoechster Review-ROI bei Agent-Code.
     - **Hallucinated Correctness** — kompiliert + Tests gruen heisst nicht korrekt. Einen
       kritischen Pfad end-to-end tracen; Boundary-Conditions und Permission-Checks auf den
       *nicht* getesteten Branches pruefen.
     - **Prompt-Injection** — bei jedem Pfad, der untrusted Input (Webhook-Payload, Issue-/PR-Text)
       in einen LLM-/Shell-Aufruf fuehrt.
   - **Test-Evidence:** jede nicht-triviale Logikaenderung braucht einen Test, der auf dem
     Pre-Change-Verhalten fehlgeschlagen waere. Fehlt der: als Punkt aufnehmen — kann der Author
     keinen schreiben, ist der Fix unvollstaendig.
   - **Beleg-Pflicht:** behauptet der PR-Body "gebaut / gruen / schnell / verifiziert" ohne
     Test-Namen oder `Datei:Zeile` als Beleg — Finding. Was nicht real lief (Docker / CLI / CI /
     Hardware fehlt) muss der Body als "nicht verifiziert" deklarieren, nicht beschoenigen;
     "schnell" ohne Benchmark ist kein Beleg.
   - **Klassengroesse:** neue oder gewachsene Klasse ueber 300 Zeilen oder mit mehr als ~15
     Instanzfeldern / mehr als einer Verantwortlichkeit ohne Begruendung im PR-Body — Finding
     (God-Class-Faenger; ein mechanischer Datei-Split zaehlt nicht als Loesung). Reine
     Schema-/DTO-/Config-Klassen und stateless Helfer sind ausgenommen.
   - **PR-Body-vs-Diff-Konsistenz:** auf Phantom Changes (Body behauptet Aenderungen, die nicht im
     Diff sind), Scope-Understatement (Diff tut mehr als der Body sagt) und Placeholder-
     Descriptions pruefen.

4. **Freigabe-Gate (vor jeder Veroeffentlichung).** Zweistufig — erst lesbarer Chat-Report, dann
   erst die Freigabe. Nie direkt in die Freigabe springen.

   **Stufe A — Chat-Report zuerst, immer, vor jeder Freigabe.** In dieser festen Reihenfolge im Chat
   ausgeben:
   - **Verdikt zuerst**, als erste Zeile: `Blockiert` / `Approvebar nach Fixes` / `Sauber` — danach
     erst die Begruendung.
   - **Severity-Counts als Kopfzeile** (z.B. `3 Blocker, 2 Major, 4 Minor`), damit der Aufwand ohne
     Zaehlen sichtbar ist.
   - eine kurze, praezise, einfache Prosa-Zusammenfassung des Reviews (2-3 Saetze: was geprueft
     wurde, Gesamteindruck).
   - darunter eine **vollstaendige, nummerierte** Findings-Liste. Pro Punkt: Nummer, **Severity-Tag
     `[Blocker]` / `[Major]` / `[Minor]`**, Datei/Zeile, ein Satz.
   - **Vollstaendigkeit ist Pflicht:** alles ab `[Minor]` wird gemeldet — reine Stilnotizen zaehlen
     nicht als Finding, in Schritt 2 aussortierte false positives bleiben draussen. Ordnung/
     Priorisierung nach Severity ist erwuenscht, aber nichts wird weggelassen oder still gefiltert.
   - **Coverage-Statement zum Schluss:** in einem Satz, was bewusst *nicht* geprueft wurde und warum
     (`Nicht geprueft: X, weil Y.`); gibt es keine Luecke, wird auch das gesagt. Ein Review, das
     seine Luecken verschweigt, liest sich vollstaendiger als es ist.

   **Stufe B — Freigabe** (referenziert die Nummern aus Stufe A). Default: **alle Findings werden
   gepostet**; der User streicht nur einzelne.

   - **Immer:** eine Zeile unter der Liste — der User nennt die Nummern, die gestrichen werden
     sollen. Ohne Nummern gilt jede kurze Bestaetigung (`k`, `ok`, `los`, `posten`, `machen`,
     `gut`) als „alle posten". Custom-Punkte im selben Zug. Der Pfad, der nie ausfaellt.
   - **Zusaetzlich, wo ein Visualizer laeuft:** ein Widget als Eingabehilfe. **Nur die
     VORLAGE-Zone von `widget-reference.html` (neben dieser Datei) 1:1 uebernehmen** — das dort
     markierte GERUEST (Dokumentrahmen, `:root`, `body`/`.wrap`, `.widget`-Container, `.out`) bleibt
     draussen, es macht die Datei nur standalone lauffaehig. Masse, Farben (ueber Host-Variablen)
     und Logik stehen in der Referenz und werden hier bewusst nicht gedoppelt, damit Referenz und
     Spec nicht auseinanderlaufen. Die `FINDINGS`-Konstante ist der Injection-Point, aus dem
     Stufe-A-Report befuellen. Was der Referenz-Code nicht selbst begruendet:
     - Die rechte Spalte des Kopf-Grids bleibt leer — sie haelt die Mitte zentriert und die obere
       rechte Ecke frei, wo Chat-Clients ihr eigenes Menue einblenden.
     - Die Legende bleibt immer vollstaendig, auch fuer Stufen ohne Findings: sonst ist der neutrale
       Badge nicht als „Minor" (statt „deaktiviert") erkennbar, und dass keine roten Badges
       dastehen, ist selbst ein Signal.
     - Die Severity der Findings ist im Widget **read-only** — sie ist die Aussage des Reviews und
       nicht hier umzustellen (nur posten/streichen), sonst widerspraeche der Badge dem
       Finding-Text und das Widget triebe von Stufe A weg. Frei waehlbare Prio gibt es nur bei den
       eigenen Custom-Punkten, weil die dem User gehoeren.

   Zwei Invarianten:
   - Das Widget **ersetzt** die Textaufforderung nie — Visualizer-Verfuegbarkeit ist vorab nicht
     pruefbar (derselbe Client rendert je nach Plattform oder nicht). Rendert es nicht, ist das
     folgenlos.
   - Das Widget ist reine Eingabehilfe, nie Informationsquelle: es traegt nie mehr, weniger oder
     andere Inhalte als der Report aus Stufe A — gleiche Nummern, gleiche Severity, gleiche
     Aussage, nur kuerzer. Was nur im Widget stuende, waere fuer jeden verloren, bei dem es nicht
     rendert.

   `ask_user_input_v0` wird hier nicht benutzt: `multi_select` laesst sich nicht leer absenden,
   `single_select` sendet beim ersten Klick ab, beide deckeln bei 4 Optionen.
   - Erst nach Freigabe durch den User posten.

5. **Review posten** via `pull_request_review_write` (nur freigegebene + custom Punkte):
   - `event`: `REQUEST_CHANGES` wenn ein Blocker dabei ist, sonst `COMMENT`.
   - Inline-Comments mit `path` + `line` bevorzugen, jeder mit Severity-Prefix; Body mit knapper,
     nach Severity geordneter Zusammenfassung **plus expliziter Aufforderung an den Author, nach
     dem Fix zurueckzumelden**. Suggested-Code-Changes auf Englisch.

6. Den Lifecycle-Trigger setzen: bei `REQUEST_CHANGES` den Autor anstossen, den PR auf Draft
   zuruecksetzen zu lassen (Schritt 10). HEAD-SHA des aktuellen Stands merken (`reviewed_sha`);
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
   Beyond-the-diff-Checks aus Phase 1 auf das neu Dazugekommene anwenden.
3. Auswertung (nach Severity):
   - **Alle adressiert, keine neuen Issues** → Phase 4.
   - **Rest- oder Neu-Issues** → sammeln → **Freigabe-Gate (Phase 1, Schritt 4)** → posten →
     **die in dieser Runde adressierten Threads sofort resolven** (`resolve_thread`) →
     `reviewed_sha` aktualisieren, zurueck zu Phase 2.

**Resolven passiert in jeder Runde, nicht erst am Ende.** Sobald ein Punkt adressiert ist, wird sein
Thread aufgeloest — auch wenn der PR insgesamt noch nicht durch ist. Wer bis Phase 4 wartet, laesst
den Author raten, was schon erledigt ist, und haengt die Restpunkte in einer Wand alter Threads.

## Phase 4: Resolve + Approve

[HARD-GATE]
Vor dem Approve, ausnahmslos — jeder Punkt muss erfuellt sein:

1. CI gruen — `pull_request_read` method=`get_check_runs`.
2. Keine Merge-Konflikte — bei `mergeable`/`mergeable_state` nicht clean **nicht** approven,
   Status melden. (`blocked` = pending Required-Review, **kein** Konflikt — kein Blocker.)
3. Kein CI-Gaming — wurden Tests/Coverage/Trigger manipuliert, um gruen zu werden, **nicht**
   approven, unabhaengig vom CI-Signal.
4. Offene Threads anderer Reviewer — falls vorhanden, vor dem Approve darauf hinweisen.
5. PR-Body woertlich nach `Closes #` / `Fixes #` / `Resolves #` durchsuchen. Fehlt es — **nicht**
   approven (blocken, oder nach dem Merge manuell schliessen).
6. Self-authored PR (Autor = eigener Reviewer-Account): nur `event: COMMENT` erlaubt — APPROVE
   ist gesperrt.
7. Zwei getrennte Verdikte, beide gruen: **Spec** (tut der Diff genau das Bestellte, nichts zu
   viel/zu wenig?) und **Quality** (handwerklich sauber: Tests, Struktur, keine Magic Numbers?).
8. Beleg-Pflicht — behauptet der PR-Body Erfuellung ("gebaut / gruen / verifiziert / schnell")
   ohne Test-Namen oder `Datei:Zeile`, **nicht** approven (blockt, analog zum `Closes #`-Check aus
   Punkt 5). Was nicht real lief, muss als "nicht verifiziert" dastehen.
[/HARD-GATE]

Diese Gedanken bedeuten STOP — du rationalisierst:

| Gedanke | Realitaet |
|---|---|
| "Key-Files reichen, der Rest ist Boilerplate" | Zeile fuer Zeile, kein Sampling. |
| "Sieht fertig aus, Closes-Check kann ich sparen" | Erst Punkt 5, dann Urteil. |
| "Spec passt schon, muss den Diff nicht gegenpruefen" | Spec-Verdikt ist eigenstaendig. |
| "Tests sind gruen, also passt der Fix" | Hallucinated Correctness — kritischen Pfad tracen. |

Wenn sauber: zuerst behandelte Threads aufloesen (`resolve_thread` `threadId=PRRT_...`, unbehandelte
offen lassen), dann `pull_request_review_write` mit `event`: `APPROVE` und knappem Body (Schritt 11).
Den Nutzer informieren: "PR #N approved. Merge **nicht** ausgefuehrt — der `maintainer` merged."

## Phase 5: Funktionale Zusammenfassung

Nach dem Approve im **Chat** liefern (nicht im PR):

- Vorher/Nachher-Zustand
- Happy Path
- Edge Cases
- Was bewusst unberuehrt bleibt
- Architektonischer Beitrag

## Strikte Regeln

- **Niemals** ohne Freigabe des Users einen Kommentar posten (Freigabe-Gate ist Pflicht in jeder
  Runde).
- **CI-Gaming ist immer ein harter Blocker** — nie approven, wenn Tests/Coverage/Trigger
  manipuliert wurden, um gruen zu werden.
- **Behandelte Threads werden in jeder Runde resolved**, nicht erst vor dem Approve — der am
  haeufigsten vergessene Schritt. Unbehandelte bleiben offen; nie einen Thread resolven, dessen
  Punkt noch aussteht.
- Reuse-Blindness aktiv suchen, nicht passiv abwarten.
- **Niemals** automatisch mergen — `merge_pull_request` nur auf separate, explizite Anweisung; der
  Merge ist `maintainer`-only.
- **Niemals** approven bei rotem CI oder Merge-Konflikten.
- **Niemals** einen PR im Review schliessen/wieder oeffnen.
- Bei Force-Push oder Branch-Reset: Loop pausieren, beim Nutzer nachfragen.
- Jeden Review-Kommentar auf beiden Seiten spiegeln (lokaler Chat + GitHub-Thread), auch
  Acknowledgements (`AGENTS.md` § "Mirroring GitHub Conversations").
- Inline-Comments mit `path` + `line` bevorzugen; Suggested-Code-Changes auf Englisch.

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
