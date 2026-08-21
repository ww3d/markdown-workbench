---
name: ccweb-prompt
description: 'Baut den Auftrags-Prompt (in manchen Repos "TASK"), mit dem ein Coding-Agent eine Aufgabe in einem Repo umsetzt und einen Draft-PR oeffnet; fuellt damit die Vorstufe der `dev`-Rolle des Playbook-PR-Lifecycles. Prueft zuerst zwei Gates: Projekt-Typ und ein vorliegender State Audit fuer das neue Design. Klaert offene Entscheidungen in einer Design-Runde, haelt sie in einem Decision-Log fest, legt im selben Zug das Tracking Issue des Designs an, laedt den Repo-Kontext aus den Repo-Docs, fragt den Review-Modus ab (hard / light / soft, Vorschlag vorbelegt) und liefert Prompt und Decision-Log als Output-Dateien (`YYYY-MM-DDTHHMM-[art].md`), nicht als Chat-Block. Baut keinen Review-Prompt — den gibt es nicht mehr, `pr-poll-review` beschafft seinen Kontext selbst. Triggert bei "prompt fuer ccweb", "bau mir einen task", "prompt fuer issue #N", "prompt generieren", "task.md bauen". Nutzt das GitHub MCP oder `gh`. Nur fuer GitHub-Repos.'
metadata:
  version: "5.1.0"
  source: ww3d/playbook
---

# Agent-Prompt (TASK) bauen

Erzeugt den Prompt, mit dem ein Coding-Agent eine Aufgabe umsetzt. Fuellt die Handoff-Vorstufe der
`dev`-Rolle aus `.agents/rules/pr.md` § "PR Lifecycle": der Prompt geht an den Agenten, der Agent
(Rolle `dev`) oeffnet den PR. Dieser Skill oeffnet keinen PR und schreibt keinen Code.

**Es gibt keinen Review-Prompt mehr.** `pr-poll-review` beschafft seinen Kontext selbst am Head
(Spec-Datei, Tracking Issue, Decision-Log, CI, Konstellation); der Review-Chat startet mit einer
Zeile. Ein Artefakt traegt nur Zustand, den das Repo nicht liefert — nach diesem Umbau liefert das
Repo alles, was ein Review-Prompt getragen haette.

## Kernprinzip

- **Environment, nicht Framework:** Der Prompt setzt Kontext + Aufgabe. Alles, was in AGENTS.md /
  CLAUDE.md steht (Workflow, Commit-/PR-Konvention, Branch-Wahl), gehoert NICHT hinein — der Agent
  kennt es. Es gilt die Artefakt-Regel aus `AGENTS.md` § "Session Start: Read Before Anything
  Else", woertlich dort und hier nicht wiederholt; sie deckt Auftrags-Prompt, Decision-Log, Handoff
  und Spec-Datei gleichermassen ab.
- **Docs gewinnen:** Bei Widerspruch Prompt vs. Repo-Docs gewinnen die Docs. Das steht im Prompt und
  gilt beim Bauen genauso — Repo-Fakten werden am Repo verifiziert, nicht aus dem Gedaechtnis gesetzt.
- **Discussion before artifacts:** Kein Prompt vor finalen Entscheidungen. Erst klaeren, dann Log,
  dann Prompt.
- **Datei-Transport:** Jedes Artefakt geht als Output-Datei raus, nie als Chat-Block (siehe
  "Ausgabe"). Chat-Text ist ein lossy Kanal.

## Eingabe

- Ziel-Repo (`owner/repo`) und die Aufgabe (frei oder Issue-Referenz `#N`).
- Fehlt eines: **fragen**, nicht raten.

## Schritt 0: Gates

Zwei Gates, beide vor allem anderen.

**Projekt-Typ.**

- **Code-Repo mit Coding-Flow:** normaler Prompt, weiter mit Schritt 1.
- **Reines Design-/Infra-/Doku-Projekt** ohne Coding-Agent-Flow: KEIN Prompt. Stattdessen
  Design-Diskussion + Decision-Log. Hier stoppen und das klarstellen.

**State Audit.** Kein Auftrags-Prompt fuer ein **neues Design**, solange kein State Audit dafuer
vorliegt (`.agents/rules/audit.md` § "State Audit"). Fehlt er, **ist er der erste Auftrag** — dann
baut dieser Skill den Prompt fuer den Audit und nicht den fuer das Design.

- **Faellig wird der Audit durch ein neues Tracking Issue**, nicht durch einen neuen PR: weitere
  PRs am selben Tracking Issue loesen keinen aus.
- **Mechanisch pruefbar:** der Stempel des juengsten `audit/ist-stand-<YYYY-MM-DDTHHMM>.md` gegen
  den Abschluss des Vorgaenger-Designs halten. Liegt der Audit davor, ist er verbraucht.
- **Ausfuehrender ist `ccweb`**, nicht `cweb`: der Audit verlangt Checkout, Build und real
  gefahrene Tests. Mechanik im Skill `state-audit`.

## Schritt 1: Design-Runde und Tracking Issue

Nicht-triviale Aufgaben erst durchentscheiden:

- Ein Thema pro Turn, am Ende "gibt es noch was?". Nicht selbststaendig weiterspringen.
- **Vier Kategorien je offener Entscheidung**, in dieser Reihenfolge: a) SOTA/modern, b) was die
  anderen machen, c) Empfehlung, d) eigene Ideen — naheliegende und unkonventionelle. Laesst sich
  eine Kategorie nicht sauber belegen, entfaellt der Slot statt geraten zu werden.
- Ergebnis als Decision-Log (siehe unten), festgeschrieben **bevor** der Prompt entsteht.

**Das Tracking Issue entsteht hier**, im selben Zug wie das Decision-Log und **bevor** der erste
Auftrags-Prompt geschrieben wird (`.agents/rules/carrier.md` § "Tracking Issue"):

- **Ein Design = ein Decision-Log = ein Tracking Issue**, unabhaengig von der Zahl der PRs.
  **Immer** anlegen, auch wenn kein Punkt offen bleibt — eine Ausnahme waere eine Ermessensfrage,
  und ein leeres Issue kostet dreissig Sekunden. Nach dem Merge wird es geschlossen.
- Sein **Body** traegt alle offenen Punkte des Designs; der Prompt verlinkt das Issue, und der
  Agent traegt seine zurueckgestellten Punkte dort ein.
- Entstuende es erst beim ersten PR, gaebe es zwischen Design-Abschluss und erstem PR ein Fenster
  ohne Traeger.

## Schritt 2: Repo-Kontext laden

Am echten Repo verifizieren (GitHub MCP oder `gh`), nicht annehmen:

- Pflichtkern nach `AGENTS.md` § "Session Start: Read Before Anything Else", Baustein 1 —
  AGENTS-Kern, `CLAUDE.md`, Audit-Kopf, je mit Blob-SHA quittiert. Roadmap, Backlog und
  Architektur-Dokument werden **nicht** vollstaendig gelesen: Pflicht sind der Doc-Index
  (Pfad + Zweck) und die laufende Scheibe (Body des offenen Tracking Issues plus dessen
  `roadmap.md`-Zeilen), alles Weitere on demand vor der Aussage, die es betrifft (Baustein 2).
- Einsatzpunkt-Quittung: dieser Skill schreibt einen Auftrag und legt ein Tracking Issue an, also
  werden `.agents/rules/carrier.md` und `.agents/rules/pr.md` vor der ersten Aktion ihres Typs
  vollstaendig gelesen und quittiert (`AGENTS.md` § "Session Start: Read Before Anything Else",
  Baustein 3). Einmal je Session je Datei.
- Issue-/Label-Konvention und den Decision-Log-Ort des Repos (Konvention in `docs/decisions/README.md`
  — siehe unten).
- Betroffene Quell-Files, damit der Prompt sie gezielt benennen kann.
- **Uebernahme-Check — was frueheren Scheiben hierher zugewiesen wurde:** vor dem Schnitt pruefen,
  ob eine Vorgaenger-Scheibe dieser Scheibe Punkte zugewiesen hat. Quelle ist **das Issue dieser
  Scheibe und ihre `roadmap.md`-/`backlog.md`-Zeile** — nicht der PR-Body des Vorgaengers, den
  niemand zurueckliest. Jeder gefundene Punkt wird im Prompt entweder als Vorgabe gefuehrt oder
  ausdruecklich als bewusst nicht gebaut benannt; stillschweigendes Uebergehen ist genau der
  Fehler, gegen den dieser Check steht.
- **Quellen-Erreichbarkeits-Check:** Jede Quelle, die der Prompt referenziert (Issues,
  Decision-Logs, Konventions-Docs, fremde Repos), pruefen: existiert sie, ist sie gemergt/synced,
  und kann die **Ziel-Session** sie erreichen (Repo-Scope, Sandbox-Whitelist der Agent-Umgebung)?
  Unerreichbares wird nicht verlinkt, sondern **inline in den Prompt** uebernommen; der Verweis
  bleibt nur als Herkunftsangabe. Inline geht ausschliesslich **Zustand** (Issue-Text,
  Entscheidungen, ausgeraeumte Fehlannahmen) — nie Regeln oder Konventionen.

## Schritt 3: Prompt bauen

**Zuerst den Review-Modus abfragen — Pflicht, kein Prompt ohne diese Abfrage.** Der Skill schlaegt
selbst einen Modus vor (Heuristik unten) und fragt mit vorbelegtem Vorschlag:
"Review-Modus: hard / light / soft?". Der gewaehlte Baustein wird 1:1 aus dem Abschnitt
"Review-Modus-Bausteine" uebernommen, nie freihaendig formuliert.

Bei Repos mit AGENTS.md / CLAUDE.md beginnt der Prompt mit dem Lese-Auftrag
(*"Session-Start-Pflicht aus AGENTS.md § 'Session Start: Read Before Anything Else' gilt:
Pflichtkern (AGENTS-Kern, CLAUDE.md, Audit-Kopf) vollstaendig lesen und je Datei mit Blob-SHA
quittieren, BEVOR irgendetwas anderes passiert; die Regeldatei zu einem Trigger vor der ersten
Aktion dieses Typs, ebenfalls mit Quittung. Bei Widerspruch Prompt vs. Docs gewinnen Docs."*),
danach acht Bloecke:

1. **Kontext** — Anlass, relevante Issues (*"Lies Issue #N vollstaendig"*).
2. **Aufgabe** — was konkret umzusetzen ist.
3. **Vorgaben** — die Aufgabe als nummerierte Liste `REQ-01`, `REQ-02`, … (ab mehr als 20 Punkten
   dreistellig: `REQ-001`). IDs werden hier beim Bau vergeben und ueber alle Review-Runden hinweg
   **nie umnummeriert**. Jedes `REQ-NN` traegt **genau eine widerlegbare Aussage** — deckt eine
   Vorgabe mehrere Oberflaechen, Komponenten oder Lieferungen ab, wird sie beim Bau in mehrere REQs
   aufgeteilt (der Schnitt liegt hier, nicht beim umsetzenden Agent). Der Prompt verpflichtet den
   Agenten, diese Liste als **Spec-Datei** `docs/tasks/<issue>-<slug>.md` anzulegen und im PR-Body
   nur zu verlinken; die Form steht in `.agents/rules/pr.md` § "Task Spec" und wird hier nicht
   gedoppelt. Der Prompt nennt nur, was die Aufgabe eigen hat: Issue-Nummer und Slug der Datei.
   **Doku-Nachzug wird einzeln aufgezaehlt.** Verlangt der Prompt, die Doku nachzuziehen, nennt er
   jede Wahrheitsquelle **namentlich und je als eigenes `REQ-NN`** — `architecture.md`,
   `roadmap.md`, `backlog.md`, die betroffenen Nutzer-Docs. Eine Sammelformel ("die Doku
   nachziehen") laesst genau die Quelle durchfallen, die niemand im Kopf hat. **Offen gelassene
   Punkte gehen ins Tracking Issue.** Der Prompt verpflichtet den Agenten: was er bewusst nicht
   baut, traegt er im selben PR in den **Body des Tracking Issues** ein — oder, wo der Punkt kein
   Design-Punkt ist, als Zeile in `roadmap.md`/`backlog.md`. Mehr gueltige Orte gibt es nicht; der
   PR-Body allein zaehlt nicht (`.agents/rules/carrier.md` § "Carrier Requirement"). **Und die
   Gegenrichtung, im selben Satz beauftragt: gelieferte Punkte werden abgehakt.** Der Prompt
   verpflichtet den Agenten, jeden Punkt, den er aus dem Body des Tracking Issues liefert, im selben
   PR dort **abzuhaken** (`.agents/rules/carrier.md` § "Tracking Issue"). Nur die eine Richtung zu
   beauftragen ist der teurere Fehler: die Spec-Datei hakt ihre `REQ` ab, der Issue-Body bleibt
   voller Haken, und der Uebernahme-Check aus Schritt 2 beauftragt in der naechsten Runde Gebautes
   erneut.
4. **Vorgehen** — schrittweise (Files sichten, aendern, testen).
5. **Gates** — Akzeptanz als ausfuehrbare Commands + pruefbare Kriterien (Build/Test gruen, keine
   Warnings), passend zum Test-Gate des Repos. Beleg-Pflicht: der Abschluss-Kommentar fuehrt jede
   Erfuellungs-Behauptung mit einem stabilen Anker aus Block 3.
6. **Review-Modus** — der gewaehlte Baustein, verbatim aus "Review-Modus-Bausteine".
7. **Nicht-Tun** — aufgabenspezifische Scope-Grenze (nur was fuer diese Aufgabe gilt; Generelles wie
   CI-Files oder Dependencies steht schon in AGENTS.md — nicht wiederholen).
8. **Erwartete Observations** — was der Agent im Abschluss-Kommentar meldet, inkl. ehrlicher
   Deklaration, was nicht real lief (fehlendes Docker / CLI / CI / Hardware) statt es zu
   beschoenigen.

**Model-Empfehlung (Pflicht):** In jedem Prompt das passende Modell explizit nennen, soweit der
Harness Modellwahl exponiert (`AGENTS.md` § "Working Mode"). Prinzip: das kleinste/schnellste Modell,
das die Aufgabe noch 100% sauber und SOTA loest. Bei parallelen Sub-Agenten waehlt jeder sein
kleinstes taugliches selbst, die Koordinator-Rolle das staerkste.

## Review-Modus-Bausteine

Drei feste Bausteine. **Wortlaut nie umformulieren** — nur der zutreffende Block wird kopiert; so
driften Modellwahl und Wellen-Regel nicht von Session zu Session weg.

**Heuristik fuer den Vorschlag:** Groesse, Kritikalitaet und Hot-Path-Naehe der Aufgabe. Breite oder
sicherheits-/performance-kritische Slices und alles, was in einen Hot Path fasst → `hard`. Mittlere
Aufgaben mit echtem Logik-Anteil → `light`. Konventions-, Doku- und Text-Aenderungen ohne
Algorithmus-Risiko → `soft`.

**hard** — traegt eine Versions-Kennung. Aktuell `hard v2`; sie wird hochgezaehlt, sobald sich
Modellwahl, Schwerpunkte, Loop-Regel oder Cap aendern. Der Prompt reicht die Kennung in den PR-Body
durch, damit der Reviewer weiss, gegen welche Fassung er prueft.

```md
Review-Modus: `hard v2`

Vor dem PR und vor jeder Fix-Runde eine parallele Welle von 3-4 Review-Sub-Agenten: frische
Sessions, verschiedene Schwerpunkte (Korrektheit/Randfaelle, Performance/Hot Paths, Vertraege/Docs,
Test-Luecken), alle auf demselben Commit-Stand. Befunde mergen/dedupen, fixen; die naechste Welle
verifiziert erst die Fixes.

Jede Welle meldet in Conventional Comments: je Punkt `issue:` / `nitpick:` / `question:` mit
`(blocking)` oder `(non-blocking)` (`.agents/rules/review.md` § "Review Comments"). Das
Zusammenfuehren wird damit mechanisch statt Ermessen, und der Coordinator sieht sofort, was
ueberhaupt blocken kann.

Modelle nach Welle gestaffelt, nicht je Agent rotiert: Welle 1 faehrt die staerksten — opus fuer
den kritischen Schwerpunkt, sonnet fuer die uebrigen, der vierte Reviewer noch einmal sonnet;
haiku nur fuer rein mechanische Pruefungen. Folgewellen verifizieren nur Fixes und fahren die
billigen.

Ab Welle 2 wird der Diff nach Bereich unter den Agenten geteilt, nicht viermal vollstaendig
gelesen: Welle 1 traegt den Ertrag, weil ein systemischer Fehler nur auffaellt, wenn jemand alles
liest — danach ist der Diff bekannt.

Abbruch, sobald eine Welle nur noch `nitpick:` findet. **Hard-Cap 2 Wellen, und der Cap geht der
Abbruch-Bedingung vor**: was nach der zweiten Welle offen ist, geht in den Body des Tracking
Issues (`.agents/rules/carrier.md` § "Carrier Requirement"), nicht in den PR-Body.

Reine Loesch-Diffs bekommen keine Welle. Dort traegt ein Waechter-Test, der rot wird, sobald das
Geloeschte wieder auftaucht.

Wellen-Bericht im PR-Body ist Pflicht: je Welle eine Zeile mit Nummer, Modellen, Schwerpunkten und
Befundzahl je Label (auch `0`).
```

**light** — eine einzige Gegen-Welle. Fuer mittlere Aufgaben: 80% des Wertes zum Bruchteil der
Kosten. Kein Wellen-Bericht-Gate.

```md
Review-Modus: `light`

Eine einzige Gegen-Welle: 1 frischer Sub-Agent, anderes Modell, voller Gegencheck. Befunde fixen.
Kein Wellen-Bericht noetig.
```

**soft** — nur die Schleifen-Formel. Kein Bericht, kein Gate.

```md
Review-Modus: `soft`

Autonom bis zum Ende, Schleife bis perfekt und ohne Befunde: Self-Review + Refactoring-Runden,
Annahmen dokumentieren. Kein Wellen-Bericht noetig.
```

## Was NICHT in den Prompt gehoert

Steckt in AGENTS.md / CLAUDE.md — der Agent kennt es:

- Keine PR-Body-Vorlage (der Agent schreibt die Description aus dem Diff).
- Keine Workflow-Boilerplate (Commit-Konvention, kein force-push, Draft-PR, nicht selbst mergen).
- Keine Branch-Namen-Vorgabe — der Agent waehlt selbst, Session startet auf dem Default-Branch.
  Einzige Ausnahme: Abzweig von einem Nicht-Default-Branch (dann Basis explizit nennen).

## Ausgabe

Alle Artefakte gehen als **Output-Datei** raus (`create_file` + `present_files`), nie als
Chat-Block. Feste Art-Taxonomie und Namensschema:

| Art             | Dateiname                            |
|-----------------|--------------------------------------|
| Agent-Prompt    | `YYYY-MM-DDTHHMM-prompt.md`          |
| Decision-Log    | `YYYY-MM-DDTHHMM-decision-log.md`    |

- Zeitstempel nach `.agents/rules/docs.md` § "Timestamps in File Names"; die `.md`-Endung bleibt
  dran, sonst verliert der Client beim Download die Typ-Erkennung.
- Ein Artefakt pro Datei — Prompt und Log werden nie zusammengelegt.
- Jede Datei beginnt mit der Marker-Zeile `<!-- transport: verbatim, do not re-render -->`, danach
  folgt direkt der Inhalt. **Kein Fence um den Inhalt** — er stammt aus der Zeit, als der Prompt im
  Chat als Block kopiert wurde, und kostet in einer Datei nur die Vier-Backtick-Regel, sobald der
  Inhalt selbst einen Codeblock enthaelt.
- **Uebergabe:** Datei herunterladen und in der Ziel-Session **als Datei anhaengen**, nicht den
  Inhalt hineinkopieren — Copy-Paste ueber gerenderten Chat zerstoert das Markdown.
- Nie ungefragt nach GitHub posten. Eine Fix-Anweisung fuer einen offenen PR geht als
  PR-Review-Kommentar (via MCP oder `gh`) nach expliziter Freigabe.

## Decision-Log

**Format, Dateiname und Ablage im Repo folgen der `docs/decisions/README.md` des jeweiligen
Consumers** — der kanonischen Decision-Log-Konvention (MADR-Light), abgeleitet aus dem
Playbook-Skelett `templates/docs/decisions-README.md`. Am Repo lesen, nicht annehmen; die
Format-Details (vier Pflicht-Sektionen plus eine optionale, Dateiname-Schema) hier nicht doppeln.
Default-Ablage ist `docs/decisions/`; fuehrt das Repo gar keine Logs, keins erzwingen.

**Transport und Ablage sind zwei Dinge.** Der Chat-Dateiname (`…-decision-log.md`) ist reiner
Transport zur Ziel-Session; der Agent legt den Inhalt unveraendert unter dem Repo-Dateinamen der
Consumer-Konvention ab.

**Auflagen gehoeren an den Mechanismus, nicht nur ins Log.** Haelt die Design-Runde eine Bedingung
fest, die erst bei einer spaeteren Erweiterung greift ("bei Aktivierung Pflicht: …"), steht sie
zusaetzlich dort, wo diese Erweiterung ansetzt — im Body des Tracking Issues oder an der
Roadmap-Zeile des Mechanismus. Wer spaeter erweitert, liest die, nicht das Log der Runde davor
(`docs/decisions/README.md` § "Auflagen und Traeger").

**Das Log der laufenden Runde traegt am Ende die Nachtraege der Review-Runden.** Es entsteht mit dem
PR und muss dessen Endstand tragen; die Runden liegen nach seiner Niederschrift. Der uebergebene
Entscheidungstext bleibt verbatim, der Abschnitt `## Nachtraege aus den Review-Runden` kommt
abgesetzt darunter (`docs/decisions/README.md` § Immutabilitaet).

Sobald der Agent den Draft-PR geoeffnet hat, liegt das Log im PR — ein Reviewer zieht es von dort
(nicht vom User weitergereicht).

## Strikte Regeln

- Nie einen Prompt unaufgefordert nach GitHub posten. Reine Status-Reads (PR/CI) sind ohne Freigabe ok.
- Kein Auftrags-Prompt fuer ein neues Design ohne das State-Audit-Gate aus Schritt 0 und ohne das
  angelegte Tracking Issue aus Schritt 1.
- Neue Code-Level-Namen nicht annehmen — im Prompt offen lassen oder nachfragen. Bestehende
  (Fork-)Identifier nie unaufgefordert umbenennen.
- Verifizieren statt spekulieren: Repo-Fakten kommen aus dem Repo, nicht aus dem Gedaechtnis — und
  jede referenzierte Quelle muss fuer die Ziel-Session erreichbar sein (Schritt 2), sonst inline.
- Jedes Artefakt als Output-Datei mit Verbatim-Marker, nie als Chat-Block.
- Kein Prompt ohne die Review-Modus-Abfrage aus Schritt 3; der gewaehlte Baustein wird verbatim
  uebernommen.
- Kein Prompt ohne den Uebernahme-Check aus Schritt 2 und ohne einzeln aufgezaehlte
  Doku-Nachzugs-Quellen.
- Artefakt-Regel nach `AGENTS.md` § "Session Start: Read Before Anything Else" — sie gilt fuer
  Prompt und Log gleichermassen.

## Repo-Konventionen

- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); das
  GitHub MCP nur als Fallback oder fuer MCP-only-Tools.
- Rollen getrennt: der Agent oeffnet Draft-PRs (`dev`), der `maintainer` merged
  (`.agents/rules/pr.md` § "PR Lifecycle").
