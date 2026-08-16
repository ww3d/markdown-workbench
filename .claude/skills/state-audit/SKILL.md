---
name: state-audit
description: 'Faehrt den State Audit, den `AGENTS.md` § "State Audit" vor jedem neuen Design verlangt, und liefert damit das Gate aus `ccweb-prompt` Schritt 0. Baut sich zuerst die Arbeitsliste selbst — alle `[erfuellt]`/`[teilweise]`/`[geplant]`-Marker der Architektur-/Baseline-Docs, alle offenen Punkte aus den Tracking Issues, alle `TODO`/`HACK`/`FIXME` mit ihrer Traeger-Referenz — und geht jeden Punkt in fester Reihenfolge durch: Aussage lesen, im Code verifizieren, Test real fahren, Marker bestaetigen oder korrigieren. Meldet das Delta in beide Richtungen: Marker ohne Punkt im Tracking Issue und Punkt im Tracking Issue ohne Marker oder Code. Schreibt das Ergebnis als `audit/ist-stand-[stempel].md` auf einem eigenen Branch, mit dem Commit-SHA im Kopf. Ein ccweb-Skill: setzt Checkout, Build, Test und `git grep` voraus. Triggert bei "state audit", "ist-stand pruefen", "audit vor der scheibe", "soll-ist abgleich".'
metadata:
  version: "2.0.1"
  source: ww3d/playbook
---

# State Audit

Prueft das Zielbild der Architektur-/Baseline-Docs gegen den tatsaechlichen Stand des Repos und
schreibt das Ergebnis fest. `AGENTS.md` § "State Audit" verlangt ihn vor jedem neuen Design; das
Gate dafuer sitzt in `ccweb-prompt` Schritt 0.

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
  (`AGENTS.md` § "Evidence Requirement").
- **Das Ergebnis ist eine Datei, kein Chat-Bericht.** Sie ueberlebt die Session, den Branch und den
  Forge-Wechsel.

## Eingabe

- Ziel-Repo und, falls mehrere existieren, das Architektur-/Baseline-Doc, gegen das geprueft wird.
- Fehlt eines: **fragen**, nicht raten.

## Schritt 1: Arbeitsliste erzeugen

Vorbereitet durch `scripts/common/get-audit-worklist.ps1`; das Ergebnis wird gelesen, nicht neu
zusammengesucht. Drei Quellen:

1. **Soll/Ist-Marker** — jede Aussage in den Architektur-/Baseline-Docs mit `[erfuellt]`,
   `[teilweise]` oder `[geplant]`, mit Pfad und Zeile.
2. **Offene Punkte der Tracking Issues** — der Body jedes offenen Issues mit dem Label
   `tracking` (`AGENTS.md` § "Tracking Issue"), Punkt fuer Punkt. Das Label ist der Filter; ohne
   es liefert die Quelle leer, und leer ist im Bericht nicht von "nichts offen" zu unterscheiden.
3. **`TODO` / `HACK` / `FIXME`** in Code und in der Prosa der Wahrheitsquellen, je mit der
   Traeger-Referenz, die `AGENTS.md` § "Carrier Requirement" verlangt — ein Marker ohne Referenz
   ist selbst ein Befund.

Ist eine Quelle leer, wird das im Bericht gesagt. Eine stillschweigend uebersprungene Quelle ist
nicht von einer leeren zu unterscheiden.

## Schritt 2: Pruefreihenfolge je Punkt

Fest, in dieser Reihenfolge — kein Punkt wird uebersprungen, keine Stufe vorgezogen:

1. **Aussage lesen.** Was genau behauptet der Satz? Deckt er mehr als eine widerlegbare Aussage,
   wird er beim Korrigieren aufgeteilt (`AGENTS.md` § "Target vs. Actual").
2. **Im Code verifizieren.** Die Stelle suchen (`git grep`), lesen, `Datei:Zeile` notieren. Nicht
   der Doku glauben und nicht dem Marker.
3. **Test real fahren.** Den Test, der die Aussage traegt, wirklich starten. Gibt es keinen, ist
   das der Befund — nicht die Gelegenheit, den Marker trotzdem zu bestaetigen.
4. **Marker bestaetigen oder korrigieren.** Passt er, bleibt er stehen; passt er nicht, wird er im
   selben Lauf auf den wahren Wert gezogen. `[erfuellt]` ohne Beleg ist unzulaessig.

## Schritt 3: Traeger-Wiedervorlage

Ein eigener Abschnitt, nicht in Schritt 2 vermischt. Hier wird der Bestand der Traeger geprueft,
den sonst niemand durchgeht:

- **Zeigt jeder Traeger-Link noch auf ein offenes Ziel?** Ein geschlossenes Tracking Issue ist der
  schlechteste Traeger, den es gibt — es sieht aus wie ein erledigter.
- **Die seit dem letzten Audit geschlossenen Tracking Issues auf offene Haken durchgehen.** Jedes
  Issue mit Label `tracking`, das seit dem Stempel des vorigen Audits geschlossen wurde
  (`gh issue list --label tracking --state closed --search 'closed:>=<Stempel>'`; ohne
  Vorgaenger-Audit alle geschlossenen), Body Zeile fuer Zeile: jede unabgehakte Checkbox ist ein
  Befund. Sie wird an einen offenen Traeger gehoben — Nachfolge-Tracking-Issue oder
  `backlog.md`-Zeile — und der Fund im Bericht benannt.
  **Das ist das Netz unter dem Gate aus `pr-poll-review` Phase 4 Punkt 8**, und die einzige Stufe,
  die einen **bereits eingetretenen** Fehler noch findet: das Gate verhindert den naechsten
  Auto-Close, gegen den letzten richtet es nichts aus. Anlass ist ein realer Fall — ein `Closes`
  auf `ww3d/playbook#180` hat dessen Tracking Issue mit sechs offenen Punkten geschlossen, und
  gefunden hat das niemand ausser einem Menschen von Hand.
- **Traegt das Ziel wirklich den Punkt?** Am Head nachlesen.
- **Ist ein Tracking Issue fertig?** Dann schliessen — aber erst, nachdem geprueft ist, was darauf
  zeigt (`AGENTS.md` § "Carrier Requirement"). **Der Regelweg laeuft vorher woanders:** zustaendig
  ist nach dem Merge der `reviewer`, hilfsweise der `maintainer` (`AGENTS.md` § "Tracking Issue").
  Der Audit ist der letzte Aufraeumer, nicht der erste Zustaendige — was er hier findet, ist
  liegengeblieben, und das gehoert in den Bericht.
- **Doku-Schuld abbauen.** Die aufgeschobenen Doku-Zeilen in `backlog.md` werden hier gebuendelt
  abgearbeitet (`AGENTS.md` § "Documentation"). Ohne diesen Termin waeren sie eine Halde statt
  eines Traegers.

## Schritt 4: Delta in beide Richtungen melden

Zwei Listen, beide Pflicht — je Richtung eine, auch wenn sie leer ist:

- **Marker ohne Punkt im Tracking Issue.** Jede `[geplant]`- oder `[teilweise]`-Aussage, zu der in
  keinem offenen Tracking Issue ein Punkt steht. Der Audit **traegt sie dort ein** — das ist die
  Verbindung, die der Marker allein nicht herstellt (`AGENTS.md` § "Target vs. Actual").
- **Punkt im Tracking Issue ohne Marker oder Code.** Ein Punkt, dem im Repo nichts entspricht:
  entweder ist er erledigt und niemand hat ihn gestrichen, oder die Doku hat die Aussage nie
  aufgenommen. Beides wird benannt, nicht stillschweigend geglaettet.

Nur eine Richtung zu melden ist der haeufigere Fehler und der teurere: eine Liste, die nur nach
fehlenden Markern sucht, laesst genau die Punkte stehen, die es nicht mehr gibt.

## Ausgabe

- **Datei:** `audit/ist-stand-<YYYY-MM-DDTHHMM>.md`, Zeitstempel nach `AGENTS.md`
  § "Timestamps in File Names" (`TZ=Europe/Berlin date +"%Y-%m-%dT%H%M"`).
- **Eigener Branch**, nie direkt auf `main`.
- **Im Kopf der Datei:** der **Commit-SHA**, an dem der Audit genommen wurde, plus der volle
  Zeitstempel mit Offset. Ohne den SHA ist jedes `Datei:Zeile` darin wertlos — er ist der
  Bezugspunkt, der die Form ueberhaupt zulaessig macht.
- **Aufbau:** Arbeitsliste je Quelle · Ergebnis je Punkt (Aussage, `Datei:Zeile`, gefahrener Test,
  Marker vorher/nachher) · Traeger-Wiedervorlage · Delta in beide Richtungen · was nicht real lief.

## Gate

**Erledigt ist der Audit, wenn jeder Punkt der Arbeitsliste einen Ausgang hat** — genau einen von
drei:

- **bestaetigt** — Aussage geprueft, Marker stimmt,
- **korrigiert** — Marker im selben Lauf gezogen,
- **ins Tracking Issue getragen** — der Punkt steht ab jetzt an einem Ort, den man durchzaehlen
  kann.

Ein Punkt ohne Ausgang bedeutet: der Audit ist nicht fertig. "Sah unveraendert aus" ist kein
Ausgang.

## Strikte Regeln

- **Keine Aussage ohne real gefahrenen Test oder gelesene Codestelle.** Ein Audit, der die Doku
  gegen die Doku prueft, misst nichts.
- **`[erfuellt]` nie ohne Beleg setzen** — das ist die Behauptung, die am schnellsten veraltet.
- Nichts stillschweigend glaetten: was nicht stimmt, wird benannt, auch wenn es der eigene
  Vorgaenger-Lauf war.
- Der Audit **aendert keinen Produktivcode**. Er korrigiert Marker und traegt Punkte ein; alles
  andere wird zu einem eigenen Auftrag.
- Nie ungefragt nach GitHub posten; das Editieren eines Tracking-Issue-Bodys ist Teil des Auftrags
  und damit Routine im Sinn von `AGENTS.md` § "Working Mode" — es braucht keine eigene Freigabe.

## Repo-Konventionen

- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); das
  GitHub MCP nur als Fallback oder fuer MCP-only-Tools.
- Sprache des Berichts nach `AGENTS.md` § "Language" (Deutsch fuer Doku-Inhalt).
