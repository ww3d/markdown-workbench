# pr-poll-review — Pruefkatalog (Phase 1)

## Inhalt

- [Fehlendes Artefakt — wann es blockt](#fehlendes-artefakt--wann-es-blockt)
- [Sub-Agent-Passes und Modellwahl](#sub-agent-passes-und-modellwahl)
- [Agent-Red-Flags (zuerst, harte Sachen)](#agent-red-flags-zuerst-harte-sachen)
- [Doku-Integritaet](#doku-integritaet)
- [Test-Evidence](#test-evidence)
- [Beleg-Pflicht](#beleg-pflicht)
- [Mengenangaben](#mengenangaben)
- [Klassengroesse](#klassengroesse)
- [PR-Body vs. Diff](#pr-body-vs-diff)
- [Backlog-Gegencheck](#backlog-gegencheck)
- [Beobachtung ohne Befund](#beobachtung-ohne-befund)
- [Mitgeliefertes Log](#mitgeliefertes-log)
- [Beim Sammeln pro Punkt festlegen](#beim-sammeln-pro-punkt-festlegen)

Wonach in Phase 1 gezielt gesucht wird, was pro gesammeltem Punkt festzulegen ist, und die
beiden Kasuistiken der Schritte 1 und 2. Phase 3 wendet denselben Katalog auf das neu
Dazugekommene an.

## Fehlendes Artefakt — wann es blockt

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

## Sub-Agent-Passes und Modellwahl

- **Sub-Agent-Parallelisierung bei grossen/breiten PRs:** parallele Spezial-Passes starten
  (Security, Quality+Reuse, Tests, Docs), jeder gegen die Kriterien aus Schritt 3 (Red-Flags,
  Test-Evidence, Konsistenz). Als Coordinator: Punkte deduplizieren, das Label je Punkt
  festlegen, false positives filtern, **einen** konsolidierten Punkte-Satz bilden.
- **Modellwahl pro Sub-Agent selbst nach Aufgabe treffen (soweit der Harness Modellwahl
  exponiert):** jeweils das *kleinste und schnellste* Modell waehlen, mit dem die Teilaufgabe
  noch 100% praezise, sauber und SOTA geloest wird. Leichte, textlastige Passes (Docs, einfache
  Konsistenz-Checks) klein/schnell; anspruchsvolle Logik-/Security-Passes und die
  Coordinator-Rolle das staerkste Modell.

## Agent-Red-Flags (zuerst, harte Sachen)

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

## Doku-Integritaet

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

## Test-Evidence

- **Test-Evidence:** jede nicht-triviale Logikaenderung braucht einen Test, der auf dem
  Pre-Change-Verhalten fehlgeschlagen waere. Fehlt der: als Punkt aufnehmen — kann der Author
  keinen schreiben, ist der Fix unvollstaendig.

## Beleg-Pflicht

- **Beleg-Pflicht:** sie gilt **nur** fuer das, was der Reviewer **nicht im Diff sieht** —
  Testlaeufe, Benchmarks, "nicht verifiziert" (`.agents/rules/evidence.md` § "Evidence
  Requirement"). Was im Diff steht, ist durch den Diff belegt und braucht keinen Anker; ein Beleg
  dafuer einzufordern ist selbst der Fehler. Behauptet der Body einen Testlauf oder eine Messung
  ohne stabilen Anker (Test-/Symbolname; Permalink nur, wo es nichts Repo-Internes gibt) —
  `issue:`; nacktes branch-relatives `file:line` und ein Link auf einen Branch-Ref zaehlen nicht
  als Beleg. Was nicht real lief (Docker / CLI / CI / Hardware fehlt) muss der Body als "nicht
  verifiziert" deklarieren, nicht beschoenigen; "schnell" ohne Benchmark ist kein Beleg.

## Mengenangaben

- **Mengenangaben ueber den Diff sind im Body verboten** (`.agents/rules/pr.md` § "PR / MR
  Description"). Steht dort eine Zeilen-, Datei-, Test- oder Funktionszahl ueber den Diff, ist
  das ein `nitpick:`; nachgerechnet wird sie nicht. Testlauf-Ergebnisse sind keine Diff-Zahlen.

## Klassengroesse

- **Klassengroesse:** neue oder gewachsene Klasse ueber 300 Zeilen oder mit mehr als ~15
  Instanzfeldern / mehr als einer Verantwortlichkeit ohne Begruendung im PR-Body — `issue:`
  (God-Class-Faenger; ein mechanischer Datei-Split zaehlt nicht als Loesung). Reine
  Schema-/DTO-/Config-Klassen und stateless Helfer sind ausgenommen.

## PR-Body vs. Diff

- **PR-Body-vs-Diff-Konsistenz:** auf Phantom Changes (Body behauptet Aenderungen, die nicht im
  Diff sind), Scope-Understatement (Diff tut mehr als der Body sagt) und Placeholder-
  Descriptions pruefen.

## Backlog-Gegencheck

- **Backlog-Gegencheck (beide Richtungen).** Erledigt der PR einen Eintrag, der in
  `backlog.md`, `roadmap.md` oder einem Issue als offen gefuehrt wird, **muss er ihn im selben
  PR streichen** (durchstreichen, nicht loeschen) — sonst taucht er in der naechsten
  Design-Runde wieder als offen auf und beschreibt womoeglich einen Stand, den es nicht mehr
  gibt. Umgekehrt gilt: was der PR offen laesst, steht im Tracking Issue. Bei
  Doku-Nachzuegen die Wahrheitsquellen **einzeln** gegenpruefen — `architecture.md`,
  `roadmap.md`, `backlog.md`, betroffene Nutzer-Docs; eine Sammelformel ("die Doku nachziehen")
  laesst genau die Quelle durchfallen, die niemand im Kopf hat.

## Beobachtung ohne Befund

- **Beobachtung ohne Befund.** Ein heute gruener Mechanismus mit erkennbarem kuenftigem
  Bruchrisiko ist kein Punkt mit Label. Er wird als **Beobachtung** gesammelt und
  bekommt seinen Platz im Verdikt (Schritt 4, Stufe A) — nicht weggelassen, nicht zum `issue:`
  hochgestuft, nicht zur Abstimmung gestellt.

## Mitgeliefertes Log

- **Mitgeliefertes Log gegen die Review-Runden gelesen?** Ein Decision-Log, das **in diesem PR
  neu entsteht**, traegt dessen Endstand — die Review-Runden liegen nach seiner Niederschrift.
  Pruefen: steht dort ein Punkt noch als ungetragen, der inzwischen einen Traeger hat?
  Beschreibt es einen Scope, den der reale Diff nicht mehr hat? Dann fehlt der Abschnitt
  `## Nachtraege aus den Review-Runden` am Ende des Files → `issue:`. **Das hebt den
  Verbatim-Check oben nicht auf:** der uebergebene Entscheidungstext bleibt byte-identisch, der
  Nachtrag steht abgesetzt darunter (`docs/decisions/README.md` § Immutabilitaet).

## Beim Sammeln pro Punkt festlegen

Fuer jeden gesammelten Punkt wird festgelegt (fuer die Freigabe in Schritt 4):

- **Label und Dekoration**, nach `.agents/rules/review.md` § "Review Comments". Ein klarer Mangel ohne
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
