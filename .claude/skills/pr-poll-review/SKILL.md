---
name: pr-poll-review
description: 'Reviewt einen GitHub Pull Request iterativ bis zum Approve und fuellt die reviewer-Rolle des Playbook-PR-Lifecycles. Beschafft den Kontext selbst am Head (Spec-Datei, Tracking Issue, Decision-Log, CI, Konstellation) — ein Review-Prompt existiert nicht. Klassifiziert den PR, faehrt Agent-Red-Flag- und Beyond-the-diff-Checks und meldet jeden Punkt in Conventional Comments: issue / nitpick / question / suggestion mit (blocking) oder (non-blocking). Ein nitpick blockt nie und geht als Suggested Change raus; eine blockende question kommt zur Abstimmung, mit a) SOTA b) andere c) Empfehlung, Empfehlung vorbelegt. Legt alles vor jeder Veroeffentlichung erst als Chat-Report plus Widget zur Freigabe vor, postet dann, wartet auf Pushes, reviewt neu und approved erst bei gruener CI ohne Merge-Konflikte. Merged nie selbst und schliesst nach dem Merge das Tracking Issue. Triggert bei "review und wenn ok approve", "pr pollen", "check PR [ref]", "approve sobald die changes da sind", "rere". Nur fuer GitHub-PRs.'
metadata:
  version: "7.1.0"
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
  gedoppelt. Kurzform:

  | Label | Anlass | Interaktion |
  |---|---|---|
  | `issue: (blocking)` | klarer Mangel, eindeutige Korrektur | posten / streichen |
  | `nitpick: (non-blocking)` | Politur, Formulierung, Stil | als Suggested Change posten / streichen |
  | `question: (blocking)` | Maintainer muss entscheiden (Scope, Abweichung von der Quelle, Breaking Change, Namenswahl, etwas nach aussen posten) | User stimmt ab |
  | `question: (non-blocking)` | Verstaendnisfrage des Reviewers | posten / streichen |
  | `suggestion: (non-blocking)` | Alternative, die der Autor annehmen oder ablehnen kann | posten / streichen |

  Der Trennstrich ist nicht die Wichtigkeit, sondern **wer antworten muss**. Im Zweifel, ob eine
  Korrektur wirklich eindeutig ist, ist es eine `question:` — praeskriptiv als `issue:` posten nur,
  wenn sie es ist.
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
     **Ein fehlendes Artefakt blockt nur, wenn der PR es beansprucht** — sonst traefe die Regel
     jeden kleinen Touch-PR und jeden Alt-PR aus der Zeit davor, und zwei Absaetze weiter steht,
     dass ein Touch-PR knapp bleiben darf:
     - **Spec-Datei** — nur, wenn der Auftrag eine `REQ`-Liste trug (`.agents/rules/pr.md` § "Task
       Spec" bindet die Datei ausdruecklich daran).
     - **Tracking Issue** — nur, wenn der PR Punkte zurueckstellt, also "Offene Fragen" /
       "Observations" / "Bewusst nicht" nicht leer sind.
     - **Decision-Log** — nur, wenn der PR sich darauf beruft.

     Fehlt eines in einem PR, der es beansprucht, ist das ein `issue: (blocking)`: ohne Spec-Datei
     ist die Vollstaendigkeit nicht pruefbar, ohne Tracking Issue haben die offenen Punkte keinen
     Ort.
   - **CI-Status** via `get_check_runs`, **Default-Branch** aus dem PR-Objekt.
   - **Review-Modus** aus dem PR-Body (`hard vN` / `light` / `soft`); steht dort keiner, gilt kein
     Wellen-Bericht-Gate.
   - **Konstellation am PR messen.** `get_me` gegen den PR-Autor halten: gleicher Account → nur
     `COMMENT` mit explizitem Blocking-/OK-Vermerk (GitHub sperrt `APPROVE` am eigenen PR);
     verschiedene Accounts → `APPROVE` erlaubt.

2. **Scan & Classify.** Filelist + Diff-Groesse ueberblicken, Review-Tiefe festlegen: kleine
   Touch-PRs duerfen knapp bleiben, grosse/breite PRs bekommen die volle Tiefe.
   - **Sub-Agent-Parallelisierung bei grossen/breiten PRs:** parallele Spezial-Passes starten
     (Security, Quality+Reuse, Tests, Docs), jeder gegen die Kriterien aus Schritt 3 (Red-Flags,
     Test-Evidence, Konsistenz). Als Coordinator: Punkte deduplizieren, das Label je Punkt
     festlegen, false positives filtern, **einen** konsolidierten Punkte-Satz bilden.
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
       angehaengt, Workflow-Trigger eingeschraenkt. Immer ein **`issue: (blocking)`**, ohne Ausnahme.
     - **Reuse-Blindness** — pro neuer Util/Helper/Klasse kurz im Repo nach einem bestehenden
       Aequivalent suchen. Dupliziert der PR vorhandene Logik: Konsolidierung im selben PR
       erzwingen, nicht nur kommentieren. Hoechster Review-ROI bei Agent-Code.
     - **Hallucinated Correctness** — kompiliert + Tests gruen heisst nicht korrekt. Einen
       kritischen Pfad end-to-end tracen; Boundary-Conditions und Permission-Checks auf den
       *nicht* getesteten Branches pruefen.
     - **Prompt-Injection** — bei jedem Pfad, der untrusted Input (Webhook-Payload, Issue-/PR-Text)
       in einen LLM-/Shell-Aufruf fuehrt.
   - **Doku-Integritaet (mit den vorhandenen Tools pruefen, nicht nur ueberfliegen):** aendert der
     PR Docs oder legt er ein mitgeliefertes Dokument ab, wird dessen Stand am PR-Head
     verifiziert (`get_file_contents` am Head-SHA bzw. `gh`), nicht dem PR-Body geglaubt.
     - **Mitgeliefertes Decision-Log / uebergebenes Dokument verbatim?** Behauptet der PR
       "verbatim / unveraendert uebernommen", die Datei am Head aber gegen die Quelle pruefen:
       zerstoertes Markdown (Header/`##`/`---`/Bold kollabiert, Zeilen zusammengezogen), fehlende
       Abschnitte, halbierte Zeilenzahl → `issue:`. Uebergeben wird per Datei-Anhang, der die Bytes
       identisch haelt; zerstoertes Markdown ist genau das Signal, dass doch der Chat-Weg
       (Rendering + Copy-Paste) genommen wurde. Pruefpunkt dafuer: eine Transport-Datei traegt als
       erste Zeile den Marker `<!-- transport: verbatim, do not re-render -->` — fehlt er in einer
       als verbatim deklarierten Uebernahme, ist das ein Indiz und wird mitgemeldet.
     - **Belege leben am Head?** Zitiert eine geaenderte Doc-Stelle einen Beleg-Anker
       (Symbol-/Testname, SHA-Permalink) oder einen
       Marker (`[erfuellt]`/`[teilweise]`/`[geplant]`), stichprobenartig gegen den Head-Stand
       gegenpruefen: verweist der Beleg auf in diesem PR geloeschten/umbenannten Code
       (tote Belegstelle), oder widerspricht der Marker dem Gebauten → `issue:`. Besonders bei
       Retire-/Umzugs-PRs und Soll/Ist-markierten Architektur-Docs. **Das gilt fuer Belege, die im
       Repo-Text stehen** — nicht fuer die Spec-Datei, die keine mehr traegt.
     - **`[erfuellt]`-Marker gegen Dateiliste.** Wird im Diff ein Marker von `[geplant]`/
       `[teilweise]` auf `[erfuellt]` gezogen, gegen die Dateiliste des PRs halten: deckt die
       Aussage eine Oberflaeche oder Komponente ab, zu der der Diff keine Datei enthaelt →
       `issue:`, auch wenn der danebenstehende Beleg plausibel klingt.
     - **Spec-Datei gegen das Issue.** Traegt der Auftrag eine `REQ-NN`-Liste, liegt sie als
       Spec-Datei `docs/tasks/<issue>-<slug>.md` (`.agents/rules/pr.md` § "Task Spec") und ist im
       PR-Body nur verlinkt — eine `REQ`-Tasklist **im Body** ist selbst ein `issue:`. Die Datei
       wird **gegen das Issue** geprueft, nicht nur in sich: deckt sie den Auftrag des Issues ab,
       ist die Nummerierung lueckenlos, traegt jedes REQ genau eine widerlegbare Aussage, und steht
       je Punkt ein Haken oder `nicht geliefert: <Grund>`? Ob die Aussage stimmt, wird **am Diff**
       geprueft, nicht an einer Beleg-Zeile — die Datei traegt keine. Eine Umsetzung im Diff, die zu
       keinem REQ gehoert, bleibt ein Punkt: Scope-Ueberschuss ist ein Befund wie eine Luecke.
     - **Wellen-Bericht (konditional).** Nur pruefen, wenn der PR-Body Review-Wellen behauptet oder
       der Auftrag den Review-Modus `hard vN` trug (der PR-Body traegt die Kennung). Dann gilt: je
       Welle eine Zeile mit Nummer, Modellen, Schwerpunkten und Befundzahl (auch `0`); fehlender
       oder unplausibler Bericht → `issue:`. Ab `hard v2` ist eine letzte Welle, die **nur noch
       Nits** findet, ein regulaerer Abbruch und kein Mangel, und die Restpunkte nach dem Cap stehen
       im Tracking Issue statt im Body — geprueft wird das in Punkt 8, nicht hier. Traegt der PR
       `light` oder `soft` — oder gar keinen Modus — und behauptet keine Wellen, ist ein fehlender
       Bericht **kein** Befund.
   - **Test-Evidence:** jede nicht-triviale Logikaenderung braucht einen Test, der auf dem
     Pre-Change-Verhalten fehlgeschlagen waere. Fehlt der: als Punkt aufnehmen — kann der Author
     keinen schreiben, ist der Fix unvollstaendig.
   - **Beleg-Pflicht:** sie gilt **nur** fuer das, was der Reviewer **nicht im Diff sieht** —
     Testlaeufe, Benchmarks, "nicht verifiziert" (`.agents/rules/evidence.md` § "Evidence
     Requirement"). Was im Diff steht, ist durch den Diff belegt und braucht keinen Anker; ein Beleg
     dafuer einzufordern ist selbst der Fehler. Behauptet der Body einen Testlauf oder eine Messung
     ohne stabilen Anker (Test-/Symbolname; Permalink nur, wo es nichts Repo-Internes gibt) —
     `issue:`; nacktes branch-relatives `file:line` und ein Link auf einen Branch-Ref zaehlen nicht
     als Beleg. Was nicht real lief (Docker / CLI / CI / Hardware fehlt) muss der Body als "nicht
     verifiziert" deklarieren, nicht beschoenigen; "schnell" ohne Benchmark ist kein Beleg.
   - **Mengenangaben ueber den Diff sind im Body verboten** (`.agents/rules/pr.md` § "PR / MR
     Description"). Steht dort eine Zeilen-, Datei-, Test- oder Funktionszahl ueber den Diff, ist
     das ein `nitpick:`; nachgerechnet wird sie nicht. Testlauf-Ergebnisse sind keine Diff-Zahlen.
   - **Klassengroesse:** neue oder gewachsene Klasse ueber 300 Zeilen oder mit mehr als ~15
     Instanzfeldern / mehr als einer Verantwortlichkeit ohne Begruendung im PR-Body — `issue:`
     (God-Class-Faenger; ein mechanischer Datei-Split zaehlt nicht als Loesung). Reine
     Schema-/DTO-/Config-Klassen und stateless Helfer sind ausgenommen.
   - **PR-Body-vs-Diff-Konsistenz:** auf Phantom Changes (Body behauptet Aenderungen, die nicht im
     Diff sind), Scope-Understatement (Diff tut mehr als der Body sagt) und Placeholder-
     Descriptions pruefen.
   - **Backlog-Gegencheck (beide Richtungen).** Erledigt der PR einen Eintrag, der in
     `backlog.md`, `roadmap.md` oder einem Issue als offen gefuehrt wird, **muss er ihn im selben
     PR streichen** (durchstreichen, nicht loeschen) — sonst taucht er in der naechsten
     Design-Runde wieder als offen auf und beschreibt womoeglich einen Stand, den es nicht mehr
     gibt. Umgekehrt gilt: was der PR offen laesst, steht im Tracking Issue. Bei
     Doku-Nachzuegen die Wahrheitsquellen **einzeln** gegenpruefen — `architecture.md`,
     `roadmap.md`, `backlog.md`, betroffene Nutzer-Docs; eine Sammelformel ("die Doku nachziehen")
     laesst genau die Quelle durchfallen, die niemand im Kopf hat.
   - **Beobachtung ohne Befund.** Ein heute gruener Mechanismus mit erkennbarem kuenftigem
     Bruchrisiko ist kein Punkt mit Label. Er wird als **Beobachtung** gesammelt und
     bekommt seinen Platz im Verdikt (Schritt 4, Stufe A) — nicht weggelassen, nicht zum `issue:`
     hochgestuft, nicht zur Abstimmung gestellt.
   - **Mitgeliefertes Log gegen die Review-Runden gelesen?** Ein Decision-Log, das **in diesem PR
     neu entsteht**, traegt dessen Endstand — die Review-Runden liegen nach seiner Niederschrift.
     Pruefen: steht dort ein Punkt noch als ungetragen, der inzwischen einen Traeger hat?
     Beschreibt es einen Scope, den der reale Diff nicht mehr hat? Dann fehlt der Abschnitt
     `## Nachtraege aus den Review-Runden` am Ende des Files → `issue:`. **Das hebt den
     Verbatim-Check oben nicht auf:** der uebergebene Entscheidungstext bleibt byte-identisch, der
     Nachtrag steht abgesetzt darunter (`docs/decisions/README.md` § Immutabilitaet).

   **Beim Sammeln pro Punkt festlegen (fuer die Freigabe in Schritt 4):**
   - **Label und Dekoration**, nach der Tabelle im Kernprinzip. Ein klarer Mangel ohne
     Ermessensspielraum ist ein `issue: (blocking)`; wo mehrere Wege valide sind oder die Wahl an
     Kontext haengt, den nur der User hat, ist es eine `question: (blocking)` — nicht praeskriptiv
     als `issue:` verkleiden. Politur ist ein `nitpick:` und wird als Suggestion formuliert; laesst
     sie sich nicht als Suggestion schreiben, war es keine Politur.
   - **Autor-Punkte:** Unter "Offene Fragen", "Observations" und "Bewusst nicht" steht je Punkt nur
     der Link auf seinen Traeger (`.agents/rules/pr.md` § "PR / MR Description"). Jeder dieser Links
     bekommt **genau eine eigene F-Nummer**; kein Buendeln, kein Weglassen mit der Begruendung
     "ausserhalb des Auftrags" oder "vom Autor korrekt eingeordnet" — **ob ein Punkt ausserhalb
     bleibt, entscheidet der User, nicht der Review**. Die eigenen Funde zaehlen zusaetzlich. Steht
     dort statt eines Links ausformulierter Text, ist das ein `nitpick:`; steht dort eine reine
     Umgebungsfeststellung (gesperrtes CLI, flakende Sandbox, fehlende Hardware), gehoert sie unter
     "Wie getestet" als "nicht verifiziert" und ist **kein** offener Punkt.
   - **Tracking Issue — eine Pruefung statt N.** Alle offenen Punkte eines Designs stehen im
     **Body** seines Tracking Issues (`.agents/rules/carrier.md` § "Tracking Issue"). Der Review
     prueft daher nur: existiert das Tracking Issue, ist es offen, stehen die in diesem PR
     zurueckgestellten Punkte darin, und — wo der PR-Body ein `Closes` darauf traegt — ist dessen
     Body frei von offenen Haken. Alles am Head nachgelesen, nie der Angabe im PR-Body geglaubt. Der
     zweite gueltige Ort ist eine Zeile in `roadmap.md`/`backlog.md`; mehr gibt es nicht. **Nicht**
     gueltig: PR-Body, Review-Kommentar, Issue-Kommentar, Chat, Decision-Log, Spec-Datei — und auch
     kein `[geplant]`/`[teilweise]`-Marker: der ist Soll/Ist-Anzeige, und ins Tracking Issue traegt
     ihn der State Audit, nicht dieser PR.
     - **Ein `nitpick:` braucht keinen Traeger** und wird hier nicht mitgezaehlt.
     - **Weitergabe an eine kuenftige Scheibe gilt erst, wenn sie am Ziel steht** — im Tracking
       Issue der Ziel-Scheibe oder in deren `roadmap.md`-Zeile. Gibt es das Ziel noch nicht,
       gehoert der Punkt in den Backlog — nie an eine Scheibe, die niemand kennt.
     - **Wer ihn eintraegt:** der Autor, im selben PR, als Anweisung aus dem Review. Nur wenn der
       PR keine dieser Dateien anfasst, editiert der Reviewer den Issue-Body selbst.
   - **Was dem Menschen vorgelegt wird — gefiltert, nicht gestrichen.** Zur Abstimmung geht nur eine
     `question: (blocking)`: Scope, Abweichung von der Quelle, Breaking Change, Namenswahl, etwas
     nach aussen posten. Alles andere bleibt eine **Beobachtung** und
     steht mit der Einschaetzung des Reviewers im Verdikt, ohne Abstimmung. Der Test ist einfach:
     lautet die eigene Empfehlung "akzeptieren" oder "stehenlassen", war es keine Frage.
   - **a/b/c fuer jede `question: (blocking)`:** kurz a) SOTA/modern, b) was andere machen,
     c) Empfehlung recherchieren/formulieren. Nicht spekulieren — laesst sich a) oder b) nicht sauber
     belegen, den Slot weglassen statt raten. c) ist immer Claudes eigener, begruendeter Rat.

4. **Freigabe-Gate (vor jeder Veroeffentlichung).** Zweistufig — erst lesbarer Chat-Report, dann
   erst die Freigabe. Nie direkt in die Freigabe springen.

   **Stufe A — Chat-Report zuerst, immer, vor jeder Freigabe.** In dieser festen Reihenfolge im Chat
   ausgeben:
   **Der obere Teil ist neu und komplett in einfacher Alltagssprache (kein Fachjargon) — er soll den
   ganzen PR abdecken, damit der Leser nicht mehr in den PR wechseln muss. Der technische
   Detail-Report darunter bleibt unveraendert und ist nur fuer den Fall da, dass jemand reingehen
   will.**

   - **Mergebarkeit** (allererste Zeile) — die Ein-Blick-Antwort: kann der PR gemergt werden, und wenn
     nicht, was steht im Weg. Faltet Verdikt, CI-Status, Merge-Konflikte und offene blockende Punkte in
     einen Satz, z.B. „Approvebar — blockt: nichts" oder „Blockt noch: CI laeuft, 1 Merge-Konflikt, 2
     offene `issue: (blocking)`". Nicht blockierende Punkte gehoeren nicht in diesen Satz. Das ist
     die konsolidierte Kurzantwort; der ausfuehrliche Verdikt steht unten im Detail-Teil.
   - **Kurzfassung** — der ganze PR in 2-4 Saetzen Klartext: was macht der PR, ist er ok, gibt es etwas
     zu tun.
   - **Was der Autor entschieden hat** — die wichtigsten Design-/Umsetzungsentscheidungen des PRs,
     einfach zusammengefasst (keine woertlichen Zitate, kein Jargon), 2-5 kurze Punkte. Gibt der PR
     dazu wenig her, entsprechend kurz — nichts erfinden.
   - **Changes-Tabelle** (optional, nur bei breiten PRs mit vielen Dateien) — verwandte Aenderungen zu
     Zeilen **gruppiert** (nie file-by-file; eine Quelldatei + 20 Uebersetzungsdateien sind zwei
     Zeilen), je Zeile eine Beschreibung in Alltagssprache. Bei kleinen/schmalen PRs entfaellt sie —
     die Kurzfassung reicht dann.
   - **Ablauf-Diagramm** (optional, nur wenn die Aenderung einen echten Fluss hat — API-Aufrufe,
     Event-/Async-Flow, Zustandsuebergaenge) — ein kompaktes Mermaid-Sequenz- oder Flussdiagramm des
     geaenderten Ablaufs (rendert in GitHub und vielen Chat-Clients; sonst bleibt der Mermaid-Block als
     Rohtext lesbar). Kein Diagramm um des Diagramms willen — hat der PR keinen nennenswerten Fluss,
     entfaellt es.
   - **Offene Fragen** (nur wenn es welche gibt) — je `question: (blocking)` ein Satz Klartext,
     worum es geht, dann
     a) SOTA/modern · b) was andere machen · c) Empfehlung; **c) ist vorbelegt**. Quelle: was der Autor
     im PR offen liess + was Claude im Review sieht, **nach dem Filter aus Schritt 3** — nur
     Entscheidungsfragen. Dieselben Fragen stehen zur Auswahl im Widget. Gibt es keine, wird das
     gesagt.
   - **Beobachtungen** (nur wenn es welche gibt) — was gefiltert wurde plus jeder heute gruene
     Mechanismus mit erkennbarem kuenftigem Bruchrisiko: je ein Satz mit der Einschaetzung des
     Reviewers, ohne Abstimmung und ohne Widget-Eintrag. Sie tragen kein Label und
     wuerden sonst herausfallen.

   ─── ab hier der bestehende Detail-Report, **unveraendert** (nur zum Reingehen); mit einer sichtbaren
   Trennung davor ───

   - **Verdikt**, als erste Zeile des Detail-Teils: `Blockiert` / `Approvebar nach Fixes` / `Sauber` —
     danach erst die Begruendung.
   - **Label-Counts als Kopfzeile** (z.B. `3 issue (blocking), 1 question (blocking), 6 nitpick`),
     damit ohne Zaehlen sichtbar ist, wieviel ueberhaupt blockt.
   - eine **kurze Prosa-Zusammenfassung des Reviews — hart auf max. 3 Saetze**: was geprueft wurde und
     der Gesamteindruck. **Keine Beleg-Aufzaehlung hier** — keine Anker-Listen, keine
     Test-Namen, kein „ich habe X, Y, Z getraced". Belege gehoeren an den jeweiligen Punkt, nicht in
     den Verdikt-Absatz. Wird der Absatz laenger als 3 Saetze oder zaehlt er Belege auf, ist er falsch.
   - darunter eine **vollstaendige, nummerierte** Punkte-Liste. Pro Punkt: Nummer, **Label mit
     Dekoration** (`issue: (blocking)` / `nitpick: (non-blocking)` / …), Datei/Zeile, ein Satz. Bei
     einem `nitpick:` steht der Suggestion-Text mit dabei — er ist das, was gepostet wird.
   - **Vollstaendigkeit ist Pflicht:** auch jeder `nitpick:` wird gemeldet; in Schritt 2
     aussortierte false positives bleiben draussen. Ordnung nach Blocking-Wirkung ist erwuenscht,
     aber nichts wird weggelassen oder still gefiltert.
   - **Coverage-Statement zum Schluss:** in einem Satz, was bewusst *nicht* geprueft wurde und warum
     (`Nicht geprueft: X, weil Y.`); gibt es keine Luecke, wird auch das gesagt. Ein Review, das
     seine Luecken verschweigt, liest sich vollstaendiger als es ist.

   **Stufe B — Freigabe** (referenziert die Nummern aus Stufe A). Default: **alle Punkte werden
   gepostet, jedes Label wie vorbelegt**; der User streicht oder stellt nur einzelne um.

   - **Immer:** eine Zeile unter der Liste — der User nennt die Nummern, die gestrichen werden
     sollen, die Nummern, deren Label er umstellt (`3: issue`, `5: nitpick`), und fuer die offenen
     Fragen nur die, bei denen er von der vorbelegten Empfehlung
     abweicht (`F2: b`, `F3: custom …`). Ohne Angaben gilt jede kurze Bestaetigung (`k`, `ok`, `los`,
     `posten`, `machen`, `gut`) als „alles posten, jedes Label wie vorbelegt, bei jeder Frage die
     Empfehlung". Custom-Punkte im selben Zug. Der Pfad, der nie ausfaellt.
   - **Das Label ist in beide Richtungen umstellbar** (`nitpick:` ↔ `issue: (blocking)`). Die
     Vorbelegung ist die Einschaetzung des Reviews; die Einstufung ist eine Maintainer-Entscheidung.
     Der **Text des Punktes bleibt unveraendert** — er wird nie umgeschrieben, nur anders
     eingeordnet.
   - **Zwei getrennte Ausstiege, beide ausdruecklich waehlbar** (sonst rutscht jeder Punkt in den
     bequemeren): `F3: offen lassen` — nicht als Anweisung posten, der Punkt **geht als Zeile in den
     Body des Tracking Issues**; oder `F3: verwerfen` — der Punkt endet ersatzlos, kein Traeger, und
     wird im Review-Body einzeilig als verworfen protokolliert, damit die Entscheidung
     nachvollziehbar bleibt. Fehlt die Angabe, gilt „offen lassen"; „verwerfen" wird nie
     unterstellt.
   - **Batch-Aktionen fuer die Nits:** „alle Nits als Suggestion posten" und „alle Nits streichen".
     Sie sind der Grund, warum ein Nit billig ist — einzeln durchzugehen waere derselbe Aufwand wie
     ein blockierender Punkt.
   - **Immer mitliefern:** ein Widget als Eingabehilfe — in jeder Runde, unabhaengig davon, ob ein
     Visualizer verfuegbar ist (rendert es nicht, ist es folgenlos; siehe Invarianten). **Nur die
     VORLAGE-Zone von `widget-reference.html` (neben dieser Datei) 1:1 uebernehmen** — das dort
     markierte GERUEST (Dokumentrahmen, `:root`, `body`/`.wrap`, `.widget`-Container, `.out`) bleibt
     draussen, es macht die Datei nur standalone lauffaehig. Masse, Farben (ueber Host-Variablen)
     und Logik stehen in der Referenz und werden hier bewusst nicht gedoppelt, damit Referenz und
     Spec nicht auseinanderlaufen. Zwei Injection-Points, beide aus dem Stufe-A-Report befuellen:
     `FINDINGS` (die Punkte mit Label) und `QUESTIONS` (die offenen Fragen; leer lassen, wenn es keine gibt —
     dann entfaellt der Fragen-Bereich sichtbar). Was der Referenz-Code nicht selbst begruendet:
     - Die rechte Spalte des Kopf-Grids bleibt leer — sie haelt die Mitte zentriert und die obere
       rechte Ecke frei, wo Chat-Clients ihr eigenes Menue einblenden.
     - Die Legende bleibt immer vollstaendig, auch fuer Stufen ohne Punkte: sonst ist der neutrale
       Badge nicht als „nitpick" (statt „deaktiviert") erkennbar, und dass keine roten Badges
       dastehen, ist selbst ein Signal.
     - **Alle Punkte stehen im Widget, auch die nicht blockierenden.** Wer nur die blockierenden zeigte,
       zwingt den Maintainer zurueck in den Report, sobald er einen Nit hochziehen will.
     - **Das Label ist umstellbar, der Finding-Text ist read-only.** Vorbelegt mit der
       Einschaetzung des Reviews, umstellbar in beide Richtungen (`nitpick:` ↔ `issue: (blocking)`).
       Die Invariante bleibt gewahrt: das Widget traegt denselben Text wie Stufe A, nur die
       Einordnung ist eine Maintainer-Entscheidung.
     - **Kopfzeile mit dem Ergebnis der Umstellung** — „nach deinen Aenderungen: 2 blockend, 6 nicht
       blockend". Ohne sie ist die Wirkung des Umstellens erst nach dem Absenden sichtbar.
     - **Zwei Batch-Aktionen fuer die Nits:** „alle Nits als Suggestion posten" und „alle Nits
       streichen".
     - **Offene Fragen sind ein eigener, vom Punkte-Block klar abgetrennter Bereich** mit anderer
       Interaktion: nicht posten/streichen, sondern **eine Wahl pro Frage** — `a) SOTA`, `b) Grosse`,
       `c) Empfehlung`, eine eigene (Custom-)Antwort, und darunter abgesetzt die beiden Ausstiege
       `offen lassen` und `verwerfen`. Die Ausstiege stehen fest und kommen nicht aus dem
       Injection-Point; abgesetzt stehen sie, weil sie die Frage beenden statt sie zu beantworten.
       Ihr Ziel ist eindeutig: **`offen lassen` heisst „geht als Zeile ins Tracking Issue"**,
       **`verwerfen` beendet den Punkt ersatzlos**.
       **c) ist vorbelegt**; der User uebersteuert nur, wo er anders entscheidet — dasselbe
       Default-Prinzip wie „alles posten". Der a/b/c-Text ist read-only (die recherchierte
       Aussage aus Stufe A), waehlbar ist nur, welche Option gilt. Unter dem Frage-Titel steht die
       `→ heisst:`-Klartext-Zeile (Feld `explain` je Frage), damit die Entscheidung ohne Jargon
       verstaendlich ist — gleiche Aussage wie in Stufe A.

   Zwei Invarianten:
   - Das Widget **ersetzt** die Textaufforderung nie — es wird zwar immer mitgeliefert, aber die
     Visualizer-Verfuegbarkeit ist vorab nicht pruefbar (derselbe Client rendert je nach Plattform
     oder nicht). Rendert es nicht, ist das folgenlos, und der Text-Pfad traegt die Freigabe allein.
   - Das Widget ist reine Eingabehilfe, nie Informationsquelle: es traegt nie mehr, weniger oder
     andere Inhalte als der Report aus Stufe A — gleiche Nummern, gleicher Text, gleiche
     Label-Vorbelegung, gleiche Fragen (`F1`, `F2`, …) mit denselben a/b/c-Optionen und derselben
     Vorbelegung, nur kuerzer. Was nur im Widget stuende, waere fuer jeden verloren, bei dem es
     nicht rendert. Das Umstellen eines Labels ist keine Ausnahme davon: es ist eine **Eingabe** des
     Users, kein Inhalt des Widgets.

   `ask_user_input_v0` wird hier nicht benutzt: `multi_select` laesst sich nicht leer absenden,
   `single_select` sendet beim ersten Klick ab, beide deckeln bei 4 Optionen.
   - Erst nach Freigabe durch den User posten.

5. **Review posten** via `pull_request_review_write` (nur freigegebene + custom Punkte + entschiedene
   Fragen):
   - `event`: `REQUEST_CHANGES` wenn ein blockierender Punkt dabei ist, sonst `COMMENT`. Ein Review
     aus lauter Nits ist nie `REQUEST_CHANGES`.
   - Inline-Comments mit `path` + `line` bevorzugen, jeder mit dem Label als Prefix (`issue:
     (blocking)` …); Body mit knapper, nach Blocking-Wirkung geordneter Zusammenfassung **plus
     expliziter Aufforderung an den Author, nach dem Fix zurueckzumelden**.
   - **Jeder `nitpick:` geht als Suggested Change**: ein mit `suggestion` ausgezeichneter
     Codeblock im `body` des
     Inline-Kommentars, mit `path` und `line`. Reines Markdown, kein Sonderfeld — per MCP im `body`
     von `add_comment_to_pending_review`, per `gh` ueber `gh api` auf den Comments-Endpunkt. Der
     Suggestion-Inhalt ist der Text, der die Stelle ersetzt; Prosa daneben nur, wo sie noetig ist.
     Suggested-Code-Changes auf Englisch.
   - **Entschiedene offene Fragen** werden als konkrete Anweisung an den Author gepostet — der vom
     User gewaehlte Ansatz (a/b/c oder seine Custom-Antwort), nicht die Frage. Ab hier ist es fuer
     den Author eine Vorgabe wie ein `issue:`; die verworfenen Optionen nur nennen, wenn die
     Begruendung dem Author hilft. Eine Frage, bei der der User „offen lassen / nicht in diesem PR"
     waehlt, wird nicht als Anweisung gepostet — **„offen lassen" ist eine Ablage, kein
     Verwerfen**: der Punkt geht als Zeile in den Body des Tracking Issues, bevor der Review
     abgeschlossen wird. Nur „verwerfen" beendet einen Punkt ersatzlos, und das ist eine
     ausdrueckliche Entscheidung des Users, keine Nebenwirkung.

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

**Positives Abschluss-Verdikt** heisst: jede Aussage, die den PR als fertig, sauber, passend,
approve-faehig oder mergebar bezeichnet — auch relativiert („aus meiner Sicht", „im Grunde", „bis
auf Kleinigkeiten"). **Kanal egal:** `APPROVE`-Event, `COMMENT`-Review, Issue-Kommentar, Satz im
Chat sagen dem `maintainer` alle „du kannst mergen" und binden dieses Gate, auch wo GitHub keins
zulaesst; „nicht approven" unten heisst dasselbe. **Nicht** gebunden: Zwischenverdikte `Blockiert` /
`Approvebar nach Fixes` — dort sind die Threads der Grund.

1. CI gruen — `pull_request_read` method=`get_check_runs`.
2. Keine Merge-Konflikte — bei `mergeable`/`mergeable_state` nicht clean **nicht** approven,
   Status melden. (`blocked` = pending Required-Review, **kein** Konflikt — haelt nichts auf.)
3. Kein CI-Gaming — wurden Tests/Coverage/Trigger manipuliert, um gruen zu werden, **nicht**
   approven, unabhaengig vom CI-Signal.
4. **Eigene Threads nach Blocking-Wirkung — Vorbedingung des Schreibens, keine Nachpruefung.** Erst
   resolven, dann schreiben: `get_review_comments` frisch abrufen, die **selbst eroeffneten**
   Threads durchgehen, jeden am Head adressierten Punkt jetzt `resolve_thread`
   (`threadId=PRRT_...`).
   - **Die blockierenden Punkte muessen null sein** — `issue: (blocking)` und
     `question: (blocking)`. Ein offener eigener Thread dieser Art haelt das
     Verdikt auf; das Verdikt zu *formulieren*, bevor die Zaehlung null ergibt, ist selbst schon
     der Verstoss — nicht erst das Absenden.
   - **Ein `nitpick:` haelt nichts auf**, weder Verdikt noch Merge, und braucht keinen Traeger. Er
     wurde als Suggestion gepostet; der Autor nimmt sie an oder nicht.
   - **Vor dem Merge ist auch der Nit-Thread resolved.** Das ist kein Gate dieses Skills, sondern
     Mechanik: `docs/common/ci.md` § "Ruleset fuer `main`" setzt "Require conversation resolution"
     in jedem ww3d-Repo, GitHub laesst sonst nicht mergen. Der Reviewer resolved ihn, sobald der
     Autor die Suggestion angenommen oder begruendet abgelehnt hat — der Autor kann einen fremden
     Thread nicht selbst resolven.
   - Threads *anderer* Reviewer werden nie selbst resolved, aber im Verdikt benannt.
5. **Traegt der PR-Body eine Auto-Close-Zeile?** Geprueft wird die **Zeile**, nicht das Vorkommen:
   eine eigene Zeile, Schliess-Keyword am Zeilenanfang, mit Nummer. Die Form ist bereits definiert
   und wird hier nur benutzt — `.agents/rules/pr.md` § "PR / MR Description" nennt sie "an English
   closing line", `docs/common/developer-guide.md` § "PR / MR" den "Auto-Close-Footer am Ende des
   Bodys". Keywords sind `Closes` / `Fixes` / `Resolves` und die uebrigen Formen derselben Verben,
   die GitHub ebenfalls parst (`close`/`closed`, `fix`/`fixed`, `resolve`/`resolved`). Fehlt die
   Zeile — **nicht** approven (blocken, oder nach dem Merge manuell schliessen).
   - **Ein Vorkommen ist keine Zeile.** Im Fliesstext, in einem Zitat, in Backticks oder nach einer
     Verneinung zaehlt das Keyword weder als Anwesenheit noch als Abwesenheit. Die Textsuche, die
     hier frueher stand, zaehlte Nennung und Anweisung gleich — daran ist der Fall zu #182
     durchgerutscht: der Body erklaerte, warum er kein Keyword setzt, und das Tracking Issue ging
     beim Merge trotzdem zu. Mechanisch pruefbar ist nur "steht dort eine Anweisung", nicht "kommt
     das Wort irgendwo vor".
   - **Die Umkehrung gilt genauso.** Eine Auto-Close-Zeile bleibt eine, auch wenn der Body sie
     erkennbar nicht als Anweisung meint — der Parser liest die Form, nicht die Absicht. Der billige
     Vorlauf dazu ist `scripts/common/check-terminology.ps1 -BodyPath`, das jedes Keyword-mit-Nummer
     meldet, das **nicht** auf einer eigenen Zeile steht (`.agents/rules/pr.md` § "PR / MR
     Description"); er sieht nur den Text, den man ihm uebergibt, und ersetzt dieses Gate nicht.
   - **Eine Ausnahme, und nur diese:** das einzige in Frage kommende Ziel ist ein **Tracking
     Issue**, in dessen Body noch ein offener Punkt steht. Dann gehoert die Zeile nach
     `.agents/rules/carrier.md` § "Tracking Issue" ausdruecklich **nicht** in den Body, und ihr
     Fehlen ist korrekt statt ein Befund. Der Body nennt das Issue trotzdem, nur ohne Keyword;
     geschlossen wird nach dem Merge von Hand, und zwar von **dir** — Phase 5, `[MERGE-GATE]`.
   - Zeigt die Auto-Close-Zeile auf ein Tracking Issue, ist umgekehrt ihre blosse Anwesenheit nicht
     genug: Punkt 8 rechnet sie gegen dessen Body. Anwesenheit und Abwesenheit sind hier dieselbe
     Frage von zwei Seiten — sie wird einmal beantwortet, in Punkt 8.
6. Zwei getrennte Verdikte, beide gruen: **Spec** (tut der Diff genau das Bestellte, nichts zu
   viel/zu wenig?) und **Quality** (handwerklich sauber: Tests, Struktur, keine Magic Numbers?).
7. Beleg-Pflicht — behauptet der PR-Body **etwas, das der Reviewer nicht im Diff sieht**
   (Testlauf, Benchmark, "verifiziert") ohne stabilen Anker (Test-/`It`-Name, Funktions-/
   Symbolname, Variablenname, Kommentar-Ueberschrift; SHA-Permalink nur, wo es nichts
   Repo-Internes gibt), **nicht** approven (blockt, analog zum `Closes #`-Check aus Punkt 5). Ein
   Beleg aus branch-relativem `file:line` oder einem Branch-Link erfuellt die Pflicht nicht; als
   Teil eines SHA-Permalinks ist `file:line` in Ordnung. **Was im Diff steht, braucht keinen
   Anker** — und wird hier nicht geprueft.
8. **Tracking-Issue-Gate — drei Fragen am Head.** **Existiert das Tracking Issue des Designs und
   ist es offen?** · **Stehen die in diesem PR zurueckgestellten Punkte in seinem Body?** ·
   **Traegt der PR-Body eine Auto-Close-Zeile auf genau dieses Issue, waehrend in dessen
   Body noch ein offener Punkt steht?** Gerechnet wird gegen die **Zeile** aus Punkt 5, nie gegen
   ein Vorkommen im Fliesstext: sonst blockt hier die Begruendung, warum bewusst keine gesetzt
   wurde. Zurueckgestellt sind: die Punkte unter „Offene Fragen" /
   „Observations" / „Bewusst nicht" des PR-Bodys und jede eigene F-Nummer, die der User auf „offen
   lassen" gesetzt hat. **Nicht** mitgezaehlt: ausdruecklich verworfene Punkte, jeder `nitpick:`,
   und reine Umgebungsfeststellungen. Der zweite gueltige Ort bleibt eine Zeile in
   `roadmap.md`/`backlog.md`. **Ergebnis muss null ungetragene Punkte sein** — sonst **nicht
   approven**, dieselbe Haerte wie der Auto-Close-Zeilen-Check aus Punkt 5.
   - **Die dritte Frage geht ueber den GANZEN Body, nicht ueber die Punkte dieses PRs.** Genau
     das war die Luecke: die Zaehlung aus Frage zwei kennt nur, was *dieser* PR zurueckstellt, und
     ein Punkt, der vorher schon drin stand, kommt darin nicht vor. Gelesen wird der Body am Head
     (`gh`/`get_file_contents` bzw. `issue_read`), Zeile fuer Zeile: jede unabgehakte Checkbox
     zaehlt, egal aus welcher Runde sie stammt.
   - **Offene Haken plus Auto-Close-Zeile = `issue: (blocking)`**, ohne Ermessen. Der Merge wuerde
     den Traeger schliessen, ohne irgendetwas zu pruefen, und ein geschlossener Traeger sieht aus
     wie ein erledigter (`.agents/rules/carrier.md` § "Tracking Issue", § "Carrier Requirement").
     Die Korrektur ist eindeutig und darum kein `question:`: entweder die offenen Punkte wandern
     vorher an einen anderen gueltigen Traeger, oder die Zeile faellt aus dem Body und der
     `maintainer` schliesst von Hand.
   - **Eine Auto-Close-Zeile auf ein Nicht-Tracking-Issue ist davon unberuehrt** — die Bedingung
     haengt am Traeger-Charakter, nicht am Keyword.
   - **Vierte Frage: steht im Body noch ein Punkt offen, den dieser PR liefert?** Jede unabgehakte
     Checkbox gegen den Diff halten — ist sie gebaut, muss der PR sie im selben Zug abhaken
     (`.agents/rules/carrier.md` § "Tracking Issue"). Nicht abgehakt trotz geliefert → `issue:
     (blocking)`. Der "Backlog-Gegencheck (beide Richtungen)" aus Phase 1 Schritt 3 sagt inhaltlich
     dasselbe und hat nicht getragen: er steht als Fliesstext zwischen zehn anderen Checks, und was
     nicht im Gate steht, wird nicht abgearbeitet. Die Kosten des Durchrutschens traegt nicht dieser
     PR, sondern die naechste Design-Runde, die den Body liest und Gebautes erneut beauftragt.
[/HARD-GATE]

Diese Gedanken bedeuten STOP — du rationalisierst:

| Gedanke | Realitaet |
|---|---|
| "Key-Files reichen, der Rest ist Boilerplate" | Zeile fuer Zeile, kein Sampling. |
| "Sieht fertig aus, den Auto-Close-Check kann ich sparen" | Erst Punkt 5, dann Urteil. |
| "Spec passt schon, muss den Diff nicht gegenpruefen" | Spec-Verdikt ist eigenstaendig. |
| "Tests sind gruen, also passt der Fix" | Hallucinated Correctness — kritischen Pfad tracen. |
| "Ich hab die Threads doch resolved" | Nachzaehlen, nicht erinnern — `get_review_comments`, die blockierenden auf null. |
| "Die Zaehlung lief, aber ein offenes `issue: (blocking)` haelt das Fazit nicht auf" | Genau das haelt es auf — erst resolven, dann schreiben (Punkt 4). |
| "Der Punkt ist ausserhalb des Scopes, also blockt er" | Out-of-Scope blockt nicht — er wird eine eigene Aufgabe (Kernprinzip). |
| "Perfekt ist er noch nicht, also noch keine Freigabe" | Freigabe-Standard ist "eindeutig besser", nicht "nichts mehr zu finden". |
| "Steht doch im PR-Body, damit ist es gemeldet" | Ein gemergter Body ist ein Archiv — Tracking-Issue-Gate, Punkt 8. |
| "Der Autor sagt, das laeuft woanders schon" | Am Head nachlesen; ein geschlossenes Issue traegt nichts. |
| "Die Zeile ist da, Punkt 5 abgehakt, weiter" | Zeigt sie auf das Tracking Issue, entscheidet dessen ganzer Body — Punkt 8, dritte Frage. |
| "Das Keyword steht im Body, also blockt Punkt 8" | Nur eine Auto-Close-Zeile zaehlt. Eine Nennung im Fliesstext ist keine — Punkt 5. |
| "Die Punkte dieses PRs stehen alle drin, also passt der Auto-Close" | Der Auto-Close schliesst auch die Punkte der Runden davor. Ganzer Body, nicht nur die eigene Liste. |
| "Ich habe approved, damit bin ich fertig" | Das Tracking Issue schliesst **nach** dem Merge — `[MERGE-GATE]`, Phase 5. |

### Gegenpruefung des Hard-Gates — Empfehlung, keine Pflicht

Nach dem eigenen Durchlauf des Hard-Gates und **vor** dem positiven Abschluss-Verdikt: einen
**frischen** ccweb-Sub-Agenten ansetzen, der ausschliesslich die acht Punkte oben nachrechnet —
**nicht den Code**. Er bekommt PR-Referenz und Repo, liest am Head selbst nach und meldet je Punkt
`geprueft` / `nicht geprueft` / `Befund`, in Conventional Comments.

- **Warum ein eigener Agent.** Er hat Checkout und `git grep`, die einer reinen Chat-Session
  fehlen. Die beiden Fehler, die diese Empfehlung ausgeloest haben, waren Rechenfehler — eine
  falsche Zahl und ein abgehaktes REQ, dessen Zahlen nie gegen den Basis-Branch gerechnet wurden —
  und beide waren damit in Sekunden zu finden.
- **Frisch heisst frisch:** nie der Autoren-Agent und nie der Agent, der den Review geschrieben
  hat. Wer die eigene Zaehlung nachzaehlt, bestaetigt sie.
- **Warum Empfehlung.** Als Pflicht waere es mehr Prozess, und zu viel Prozess ist der Anlass
  dieses Umbaus. Ob der Lauf etwas findet, misst `scripts/common/measure-review-comment.ps1` ueber
  die naechsten Schnitte; findet er nichts, faellt die Empfehlung wieder weg.
- **Wo es nicht geht** — eine Umgebung ohne Sub-Agenten —, entfaellt der Lauf ersatzlos. Er ist
  keine Bedingung des Verdikts, und ein nicht gefahrener Lauf wird als solcher benannt, nicht
  verschwiegen (`.agents/rules/evidence.md` § "Evidence Requirement").

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

Warum das ueberhaupt dasteht: die Zustaendigkeit stand schon an drei Stellen
(`.agents/rules/carrier.md` § "Tracking Issue", `docs/common/developer-guide.md` § "PR / MR", Phase
4 Punkt 5 und diese Phase), und #184/#185 sind nach dem Merge von PR #190 trotzdem liegengeblieben.
Es fehlte der Ausloeser, nicht die Regel: der Merge passiert Stunden nach dem Approve durch den
`maintainer`, und eine Reviewer-Session, die beim Approve aussteigt, ist dann nicht mehr da.

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

Kannst du nicht schliessen (Rechte, gesperrte Forge), geht es an den `maintainer`, mit derselben
einen Zeile. **Dasselbe gilt, wenn das Warten auslaeuft:** ohne Abo-Faehigkeit endet der
Poll-Fallback nach dem Timeout aus Phase 2, und ein Merge, der danach passiert, weckt niemanden
mehr. Dann geht das Schliessen ebenfalls mit **einer** Zeile an den `maintainer` — ein
abgelaufenes Warten ist eine Uebergabe, kein stiller Abbruch. Der **Merge** bleibt
`maintainer`-only; das Schliessen ist keiner.

**Rueckmeldung nach dem Merge.** Laeuft der PR unter einer orchestrierenden Session, gehen nach dem
Merge genau drei Zeilen an sie: was gemergt wurde, was offen blieb, wo es steht. **Zeiger, kein
Inhalt** — alles Weitere liest die Ziel-Session am Repo. Eine weitergereichte Zusammenfassung waere
eine zweite Wahrheit neben dem Repo und genau die Fehlerklasse, gegen die das Tracking Issue
steht.

## Strikte Regeln

- **Niemals** ohne Freigabe des Users einen Kommentar posten (Freigabe-Gate ist Pflicht in jeder
  Runde).
- **Das Punkte-Widget wird in jeder Runde immer mitgeliefert**, unabhaengig von der
  Visualizer-Verfuegbarkeit — es ersetzt aber nie den Text-Pfad (rendert es nicht, folgenlos).
- **Das Widget wird immer inline gerendert** (Visualizer/`show_widget`) — nie als Datei-Anhang, nie
  als Code-Block, nie als Beschreibung dessen, was es enthielte. Die VORLAGE-Zone rechnet mit den
  Host-Variablen; ausserhalb des Hosts ist sie ungestyltes Markup und damit wertlos. Aufwand ist
  kein Grund, den Kanal zu wechseln.
- **Kein offener Punkt ohne Traeger** — was dieser PR bewusst nicht loest, steht vor dem Verdikt im
  Body des offenen Tracking Issues oder als Zeile in `roadmap.md`/`backlog.md`. Mehr gueltige Orte
  gibt es nicht: PR-Body, Kommentare, Decision-Logs, Spec-Datei und `[geplant]`-Marker zaehlen
  nicht; eine Weitergabe zaehlt erst am Ziel. Ein `nitpick:` ist kein offener Punkt.
- **Das Label steuert die Blocking-Wirkung, der Text bleibt read-only.** Im Widget ist die
  Einstufung eines Punktes umstellbar (`nitpick:` ↔ `issue: (blocking)`) — sie ist eine
  Maintainer-Entscheidung. **Der Finding-Text ist read-only** und wird nie umgeschrieben; nur so
  traegt das Widget dieselben Inhalte wie Stufe A.
- **Eine `question:` nie einseitig als `issue:` entscheiden** — wo mehrere Wege valide sind oder die
  Wahl an User-Kontext haengt, wird abgestimmt (Empfehlung vorbelegt), nicht praeskriptiv gepostet.
- **CI-Gaming ist immer ein `issue: (blocking)`** — nie approven, wenn Tests/Coverage/Trigger
  manipuliert wurden, um gruen zu werden.
- **Behandelte Threads werden in jeder Runde resolved**, nicht erst vor dem Verdikt — der am
  haeufigsten vergessene Schritt; nie einen resolven, dessen Punkt noch aussteht. Und **kein
  positives Abschluss-Verdikt mit einem offenen eigenen blockierenden Punkt**, ueber keinen Kanal:
  erst resolven, bis die frische Zaehlung von `issue: (blocking)` und `question: (blocking)` null
  ergibt, dann schreiben (Phase 4 Punkt 4). Ein `nitpick:` darf offen bleiben. **Vor dem Merge
  resolved ihn der Reviewer trotzdem**, nachdem der Autor die Suggestion angenommen oder begruendet
  abgelehnt hat: das Ruleset aus `docs/common/ci.md` laesst sonst nicht mergen.
- **Jeder `nitpick:` geht als Suggested Change raus**, nie als Prosa-Kommentar. Laesst er sich nicht
  als Suggestion formulieren, ist es keiner.
- Reuse-Blindness aktiv suchen, nicht passiv abwarten.
- **Das Approve beendet den Auftrag nicht.** Nach dem Verdikt wird erneut abonniert, und das
  `merged`-Event loest das `[MERGE-GATE]` aus Phase 5 aus: Tracking Issue schliessen oder in einer
  Zeile begruenden, warum nicht.
- **Niemals** automatisch mergen — `merge_pull_request` nur auf separate, explizite Anweisung; der
  Merge ist `maintainer`-only.
- **Niemals** approven bei rotem CI oder Merge-Konflikten.
- **Niemals** einen PR im Review schliessen/wieder oeffnen.
- Bei Force-Push oder Branch-Reset: Loop pausieren, beim Nutzer nachfragen.
- Inhaltliche Antworten auf beiden Seiten spiegeln (lokaler Chat + GitHub-Thread); reine
  Acknowledgements nicht doppeln — das Resolven sagt es, und in den Chat geht **eine**
  Zusammenfassung je Review-Runde (`.agents/rules/pr.md` § "Mirroring GitHub Conversations").
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
