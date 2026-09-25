---
name: state-audit
description: 'Faehrt den State Audit, den `.agents/rules/audit.md` § "State Audit" vor jedem neuen Design verlangt, und liefert damit das Gate aus `ccweb-prompt` Schritt 0. Baut sich zuerst die Arbeitsliste selbst — alle `[erfuellt]`/`[teilweise]`/`[geplant]`/`[nicht verifiziert]`-Marker der Architektur-/Baseline-Docs, alle offenen Punkte aus den Tracking Issues, alle `TODO`/`HACK`/`FIXME` mit ihrer Traeger-Referenz — und geht jeden Punkt in fester Reihenfolge durch: Aussage lesen, im Code verifizieren, Test real fahren, Marker bestaetigen oder korrigieren. Meldet das Delta in beide Richtungen: Marker ohne gueltigen Traeger und Punkt im Tracking Issue ohne Marker oder Code. Schreibt das Ergebnis als `audit/ist-stand-[stempel].md` auf einem eigenen Branch, mit dem Commit-SHA im Kopf. Ein ccweb-Skill: setzt Checkout, Build, Test und `git grep` voraus. Triggert bei "state audit", "ist-stand pruefen", "audit vor der scheibe", "soll-ist abgleich".'
metadata:
  version: "2.9.0"
  source: ww3d/playbook
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#210"
---

# State Audit

Prueft das Zielbild der Architektur-/Baseline-Docs gegen den tatsaechlichen Stand des Repos und
schreibt das Ergebnis fest. `.agents/rules/audit.md` § "State Audit" verlangt ihn vor jedem neuen
Design; das Gate dafuer sitzt in `ccweb-prompt` Schritt 0.

**Dieser Skill ist ein `ccweb`-Skill.** Er darf Werkzeuge voraussetzen — Checkout, Build, Test,
`git grep`. Eine Session ohne Arbeitsverzeichnis kann ihn nicht fahren: sie kann Tests nicht real
laufen lassen, und ein Audit, der Testlaeufe behauptet statt sie zu fahren, ist genau die
Beschoenigung, gegen die er steht.

## Kernprinzip

- **Fertige Arbeitsliste statt leerem Blatt.** Der Skill sammelt die zu pruefenden Punkte
  maschinell (Schritt 1), bevor irgendetwas beurteilt wird. Wer die Liste im Kopf zusammenstellt,
  laesst genau die Quelle aus, die niemand im Kopf hat.
- **Real fahren, nicht ableiten.** Jede Aussage wird am Code, am Build und am wirklich gelaufenen
  Test geprueft. Was nicht lief (fehlendes Docker, CLI, CI, Hardware), steht als "nicht verifiziert"
  im Bericht — nie beschoenigt.
- **`Datei:Zeile` ist hier die richtige Belegform.** Der Audit nennt den Commit, an dem er genommen
  wurde, und fixiert damit den Bezugspunkt so, wie es sonst nur ein SHA-Permalink tut
  (`.agents/rules/evidence.md` § "Evidence Requirement").
- **Das Ergebnis ist eine Datei, kein Chat-Bericht.** Sie ueberlebt die Session, den Branch und den
  Forge-Wechsel.
- **Einsatzpunkt-Quittung als Eingangsschritt.** Der Audit ist selbst ein Trigger und er fasst
  Traeger, Doku und Belege an: `.agents/rules/audit.md`, `.agents/rules/carrier.md`,
  `.agents/rules/docs.md` und `.agents/rules/evidence.md` werden vor Schritt 1 vollstaendig gelesen
  und quittiert (`AGENTS.md` § "Session Start: Read Before Anything Else", Baustein 3). Einmal je
  Session je Datei; die Regeltexte werden hier nicht gedoppelt.

## Eingabe

- Ziel-Repo und, falls mehrere existieren, das Architektur-/Baseline-Doc, gegen das geprueft wird.
- Fehlt eines: **fragen**, nicht raten.

## Schritt 1: Arbeitsliste erzeugen

Vorbereitet durch `scripts/common/get-audit-worklist.ps1` (mit `-Repo <owner/name>`); das Ergebnis
wird gelesen, nicht neu zusammengesucht. Spalten und Listen erklaert `scripts/common/README.md`.
Drei Quellen:

1. **Soll/Ist-Marker** — jede Aussage in den Architektur-/Baseline-Docs mit `[erfuellt]`,
   `[teilweise]`, `[geplant]` oder `[nicht verifiziert]`, mit Pfad und Zeile.
2. **Offene Punkte der Tracking Issues** — der Body jedes offenen Issues mit dem Label `tracking`
   (`.agents/rules/carrier.md` § "Tracking Issue"), Punkt fuer Punkt, **und dessen GitHub Sub-Issues**
   (`.agents/rules/carrier.md` § "Tracking Issue": ab Richtwert 30 Kaestchen traegt ein Tracking
   Issue seine offenen Punkte dort statt im Body). Das Label ist der Filter; ohne es liefert die
   Quelle leer, und leer ist im Bericht nicht von "nichts offen" zu unterscheiden.
3. **`TODO` / `HACK` / `FIXME`** in Code und in der Prosa der Wahrheitsquellen, je mit der
   Traeger-Referenz, die `.agents/rules/carrier.md` § "Carrier Requirement" verlangt — ein Marker
   ohne Referenz ist selbst ein Befund.

Ist eine Quelle leer, wird das im Bericht gesagt. Eine stillschweigend uebersprungene Quelle ist
nicht von einer leeren zu unterscheiden. Die Zahlen dafuer stehen fertig im `source-report` des
Skripts (Rohtreffer, verworfen je Grund, nutzbar) und werden in den Bericht uebernommen.

Aus der Arbeitsliste kommen zusaetzlich vier Angaben, die spaetere Schritte lesen:

- **Liste `backlog`** — jede offene `backlog.md`-Zeile mit ihrem Alter in Audit-Stempeln: Quelle der
  Alterung in Schritt 3.

- **Spalte `Carrier` je Marker — Quelle fuer Schritt 4.** `target-missing` und `carrier-closed`
  sind Marker ohne gueltigen Traeger; `not-a-carrier` ebenso (der Verweis zeigt auf ein offenes
  Issue, das kein Traeger ist); `unverifiable` (kein Verweis, oder Issues nicht gelesen) wird von
  Hand geprueft; `covered` ist gedeckt — ob die `roadmap.md`-/`backlog.md`-Zeile den Punkt wirklich
  traegt, prueft der Audit trotzdem. Die Spalte `Hash` wird je Punkt in den Bericht uebernommen;
  ein anderer Hash als im vorigen Audit heisst: die Aussage wurde geaendert.
- **Liste `uncovered-carriers`** — offene Tracking Issues und Punkte, auf die kein Marker-Verweis
  zeigt; Eingang fuer die zweite Richtung in Schritt 4. Solange Verweise selten sind, ist sie lang
  und heisst "Verweise fehlen", nicht Delta.
- **Liste `remaining`** — jede `fehlt:`-Angabe mit Datei, Abschnitt und Hash: die Restliste. Ein
  `[teilweise]` ohne `fehlt:` steht mit `Note` `teilweise (undetermined)` in der Liste und wird in
  Schritt 4 als unbestimmt gemeldet.

## Schritt 2: Pruefreihenfolge je Punkt

Fest, in dieser Reihenfolge — kein Punkt wird uebersprungen, keine Stufe vorgezogen:

1. **Aussage lesen.** Was genau behauptet der Satz? Deckt er mehr als eine widerlegbare Aussage,
   wird er beim Korrigieren aufgeteilt (`.agents/rules/docs.md` § "Target vs. Actual").
2. **Im Code verifizieren.** Die Stelle suchen (`git grep`), lesen, `Datei:Zeile` notieren. Nicht
   der Doku glauben und nicht dem Marker.
3. **Test real fahren.** Den Test, der die Aussage traegt, wirklich starten. Gibt es keinen, ist
   das der Befund — nicht die Gelegenheit, den Marker trotzdem zu bestaetigen.
4. **Marker bestaetigen oder korrigieren.** Passt er, bleibt er stehen; passt er nicht, wird er im
   selben Lauf auf den wahren Wert gezogen. `[erfuellt]` ohne Beleg ist unzulaessig. Redet die
   Aussage ueber ein Fremd-Repo und laesst sich von hier aus weder belegen noch widerlegen, wird
   der Marker `[nicht verifiziert]` gesetzt statt bestaetigt oder korrigiert — das Fremd-Repo wird
   im selben Satz genannt (`.agents/rules/docs.md` § "Target vs. Actual").

**Zusaetzlich, wo der Punkt einen Mechanismus beschreibt:** gegen den Architektur-Abschnitt halten,
der ihn regelt (`.agents/rules/audit.md` § "State Audit") — der Code-Check in Schritt 2.2 beantwortet
nur "wurde das gebaut", nicht "tut es noch, was der Architektur-Abschnitt verspricht". Ein
Widerspruch ist ein Delta-Eintrag (Schritt 4), nie `[erfuellt]`.

## Schritt 3: Traeger-Wiedervorlage

Ein eigener Abschnitt, nicht in Schritt 2 vermischt. Hier wird der Bestand der Traeger geprueft,
den sonst niemand durchgeht:

- **Zeigt jeder Traeger-Link noch auf ein offenes Ziel?** Ein geschlossenes Tracking Issue ist der
  schlechteste Traeger, den es gibt — es sieht aus wie ein erledigter.
- **Die seit dem letzten Audit geschlossenen Tracking Issues auf offene Haken durchgehen.** Jedes
  Issue mit Label `tracking`, das seit dem Stempel des vorigen Audits geschlossen wurde (ohne
  Vorgaenger-Audit alle geschlossenen), Body Zeile fuer Zeile: jede unabgehakte Checkbox ist ein
  Befund. Sie wird an einen offenen Traeger gehoben — Nachfolge-Tracking-Issue oder
  `backlog.md`-Zeile — und der Fund im Bericht benannt. Gefunden werden sie mit
  `scripts/common/sweep-carriers.ps1 -Repo <repo> -Since <Stempel des vorigen Audits>`: das Skript
  liest ueber REST und filtert nach Schliessdatum, und es meldet zusaetzlich Referenzen auf
  inzwischen geschlossene Traeger-Issues. `gh issue list` laeuft ueber GraphQL und ist in einer
  Claude-Code-Session gesperrt.
  **Das ist das Netz unter dem Gate aus `pr-poll-review` Phase 4 Punkt 8**, und die einzige Stufe,
  die einen **bereits eingetretenen** Fehler noch findet: das Gate verhindert den naechsten
  Auto-Close, gegen den letzten richtet es nichts aus. Anlass ist ein realer Fall — ein `Closes`
  auf `ww3d/playbook#180` hat dessen Tracking Issue mit sechs offenen Punkten geschlossen, und
  gefunden hat das niemand ausser einem Menschen von Hand.
- **Traegt das Ziel wirklich den Punkt?** Am Head nachlesen.
- **Ist ein Issue mit Checkliste fertig?** Das gilt fuer jedes, mit oder ohne Label `tracking`.
  Dann schliessen — aber erst, nachdem geprueft ist, was darauf zeigt (`.agents/rules/carrier.md`
  § "Carrier Requirement"). **Der Regelweg laeuft vorher woanders:** zustaendig ist nach dem Merge
  der `reviewer` des PRs, der den letzten Punkt abgehakt hat; hakt kein PR ihn ab, wer ihn von Hand
  abhakt oder umhaengt; hilfsweise der `maintainer` (`.agents/rules/carrier.md` § "Tracking
  Issue"). Der Audit ist der letzte Aufraeumer, nicht der erste Zustaendige — was er hier findet,
  ist liegengeblieben, und das gehoert in den Bericht.
  Den Aufraeumlauf faehrt `scripts/common/find-closable-issues.ps1 -Repo <repo>` ohne `-Pr`: er meldet
  jedes offene Issue mit Checkliste als `closable`, `open-boxes` oder `still-carried-by`, davor
  `rehang-first` je Marker, der noch auf ein schliessbares Issue zeigt. Jedes `closable` ist ein
  Fund und steht mit seiner Nummer im Bericht; `SOURCE UNAVAILABLE` steht dort als nicht
  verifiziert.
- **Doku-Schuld abbauen.** Die aufgeschobenen Doku-Zeilen in `backlog.md` werden hier gebuendelt
  abgearbeitet (`.agents/rules/docs.md` § "Documentation"). Ohne diesen Termin waeren sie eine Halde
  statt eines Traegers. Dazu zaehlen ausdruecklich auch Index-Dateien (`CLAUDE.md`, `README.md`,
  Verweislisten unter `docs/**`) — Produktiv- und Testcode bleiben ausserhalb des Audits.
  **Alterung:** eine `backlog.md`-Zeile, die drei Audit-Stempel ueberlebt hat, spuelt der Audit als
  Pflicht-Punkt in das Tracking Issue der naechsten Scheibe hoch — eine Zeile, die niemand abraeumt,
  ist keine Warteschlange mehr, sondern eine Halde. Gezaehlt wird nicht von Hand: die Quelle
  `backlog` der Arbeitsliste fuehrt jede offene Zeile mit `Note` `aged: …` (hochspuelen),
  `ages: …` (liegt weiter) oder `exempt: …`. **Nicht altern** zwei Formen, weil sie absichtlich
  warten: der Vermerk `*(Eingereiht … roadmap.md …)*` (die Zeile hat einen Platz in `roadmap.md`)
  und das Label `**Ausloeser:**` mit dem Ereignis, das sie faellig macht. Beide woertlich und mit
  Gross-/Kleinschreibung — eine Ausnahme, die man frei formulieren darf, waere eine Ermessensfrage.

## Schritt 4: Delta in beide Richtungen melden

Zwei Listen, beide Pflicht — je Richtung eine, auch wenn sie leer ist:

- **Marker ohne gueltigen Traeger.** Massstab ist die Traeger-Liste aus
  `.agents/rules/carrier.md` § "Carrier Requirement": offenes Tracking Issue, Zeile in
  `roadmap.md`/`backlog.md`, offenes Issue im Fremd-Repo. Eine `[geplant]`- oder
  `[teilweise]`-Aussage, deren Punkt an einem davon steht, ist gedeckt und kein Delta. Delta ist
  nur ein Marker ohne jeden Traeger. Den **traegt der Audit an den passenden Traeger** — das
  Tracking Issue der Scheibe, die ihn faellig macht, sonst `roadmap.md`/`backlog.md`, bei einem nur
  im Fremd-Repo umsetzbaren Punkt ein offenes Issue dort; nie in ein Tracking Issue, zu dessen
  Design er nicht gehoert — und setzt am Marker den Verweis auf diesen Traeger, wo
  `.agents/rules/docs.md` § "Target vs. Actual" eine Form dafuer kennt. Das ist die Verbindung, die der Marker allein nicht herstellt
  (`.agents/rules/docs.md` § "Target vs. Actual").
- **Punkt im Tracking Issue ohne Marker oder Code.** Ein Punkt, dem im Repo nichts entspricht:
  entweder ist er erledigt und niemand hat ihn gestrichen, oder die Doku hat die Aussage nie
  aufgenommen. Beides wird benannt, nicht stillschweigend geglaettet.

Nur eine Richtung zu melden ist der haeufigere Fehler und der teurere: eine Liste, die nur nach
fehlenden Markern sucht, laesst genau die Punkte stehen, die es nicht mehr gibt.

## Ausgabe

- **Datei:** `audit/ist-stand-<YYYY-MM-DDTHHMMZ>.md`, Zeitstempel nach `.agents/rules/docs.md`
  § "Timestamps in File Names" (`date -u +"%Y-%m-%dT%H%MZ"`).
- **Eigener Branch**, nie direkt auf `main`.
- **Im Kopf der Datei:** der **Commit-SHA**, an dem der Audit genommen wurde, plus der volle
  UTC-Stempel (`YYYY-MM-DDTHHMMZ`). Ohne den SHA ist jedes `Datei:Zeile` darin wertlos — er ist der
  Bezugspunkt, der die Form ueberhaupt zulaessig macht.
- **Direkt hinter dem Metadatenblock steht die Kurzfassung — als erste Sektion, vor allem
  anderen.** Metadatenblock plus Kurzfassung sind zusammen der **Audit-Kopf**, und der ist
  Pflichtlektuere jeder Session (`AGENTS.md` § "Session Start: Read Before Anything Else",
  Baustein 1, und `.agents/rules/audit.md` § "State Audit"). Eine Session liest genau diesen Kopf
  und nichts weiter; steht das Ergebnis hinter der Punkt-fuer-Punkt-Liste, liest es niemand. Die
  Kurzfassung traegt in wenigen Zeilen: Zahl der geprueften Punkte je Ausgang, das Delta in beide
  Richtungen als Zahl, und was nicht real lief.
- **Aufbau:** Metadatenblock · **Kurzfassung** · Arbeitsliste je Quelle (Zahlen aus dem
  `source-report`) · Ergebnis je Punkt (Aussage, `Datei:Zeile`, Hash, gefahrener Test, Marker
  vorher/nachher) · Traeger-Wiedervorlage · Delta in beide Richtungen · **Restliste** (die
  `remaining`-Eintraege nach Datei und Abschnitt, dazu die unbestimmten `[teilweise]`) · was nicht
  real lief.

## Gate

**Erledigt ist der Audit, wenn jeder Punkt der Arbeitsliste einen Ausgang hat** — genau einen von
vier:

- **bestaetigt** — Aussage geprueft, Marker stimmt,
- **korrigiert** — Marker im selben Lauf gezogen,
- **an einen Traeger getragen** — der Punkt steht ab jetzt an einem Ort, den man durchzaehlen
  kann: im Tracking Issue der Scheibe, die ihn faellig macht, sonst als Zeile in
  `roadmap.md`/`backlog.md`, bei einem nur im Fremd-Repo umsetzbaren Punkt in einem offenen Issue
  dort (`.agents/rules/carrier.md` § "Carrier Requirement"),
- **nicht verifiziert (Fremd-Repo <name>)** — die Aussage ist aus diesem Repo heraus weder zu
  belegen noch zu widerlegen, weil sie ueber ein Fremd-Repo redet; das Fremd-Repo wird benannt.

Ein Punkt ohne Ausgang bedeutet: der Audit ist nicht fertig. "Sah unveraendert aus" ist kein
Ausgang.

## Strikte Regeln

- **Keine Aussage ohne real gefahrenen Test oder gelesene Codestelle.** Ein Audit, der die Doku
  gegen die Doku prueft, misst nichts.
- **`[erfuellt]` nie ohne Beleg setzen** — das ist die Behauptung, die am schnellsten veraltet.
- Nichts stillschweigend glaetten: was nicht stimmt, wird benannt, auch wenn es der eigene
  Vorgaenger-Lauf war.
- Der Audit **aendert keinen Produktivcode**. Er korrigiert Marker und traegt Punkte ein; alles
  andere wird zu einem eigenen Auftrag. Die Doku-Schuld aus `backlog.md` (§ "Traeger-Wiedervorlage",
  Schritt 3) gehoert dabei ausdruecklich zum Audit — einschliesslich Index-Dateien wie `CLAUDE.md`,
  `README.md` und `docs/**`-Verweislisten; Produktiv- und Testcode bleiben ausgeschlossen
  (`.agents/rules/audit.md` § "State Audit").
- Nie ungefragt nach GitHub posten; das Editieren eines Tracking-Issue-Bodys ist Teil des Auftrags
  und damit Routine im Sinn von `AGENTS.md` § "Working Mode" — es braucht keine eigene Freigabe.

## Repo-Konventionen

- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); das
  GitHub MCP nur als Fallback oder fuer MCP-only-Tools.
- Sprache des Berichts nach `AGENTS.md` § "Language" (Deutsch fuer Doku-Inhalt).
