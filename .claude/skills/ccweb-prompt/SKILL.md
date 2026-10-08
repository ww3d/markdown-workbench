---
name: ccweb-prompt
description: 'Design-Session: fuehrt die Design-Runde, schreibt Decision-Log, Zeilen-Datei und Spec-Datei, legt das Tracking Issue an und pusht alles auf einen Zweig; die Spec ist der Auftrag, Startzeile /dev-task [repo]#[N]. Triggert bei "prompt fuer ccweb", "bau mir einen task", "prompt fuer issue #N", "prompt generieren", "task.md bauen", "design-runde". Nur fuer GitHub-Repos.'
metadata:
  version: "10.0.0"
  source: ww3d/playbook
  checksum: "sha256:300d9bcb06e22c12e0d3575d2160599398c5a149f6ca0402c131050557bf4e20"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#210"
---

# Design-Runde und Spec (TASK) bauen

Fuehrt die Design-Runde zu einer Aufgabe und liefert, was die Dev-Session braucht: Decision-Log,
Zeilen-Datei, Tracking Issue und die Spec-Datei `docs/tasks/<issue>-<slug>.md`, gepusht auf einen
Zweig, der Link im Tracking Issue. **Die Spec-Datei ist der Auftrag** — einen getrennten
Auftrags-Prompt gibt es nicht mehr. Die Dev-Session startet mit der Zeile
`/dev-task <owner/repo>#<N>` (Skill `dev-task`) und oeffnet den Draft-PR von diesem Zweig
(`.agents/rules/pr.md` § "PR Lifecycle"). Dieser Skill oeffnet keinen PR und schreibt keinen Code.

**Im Controller-Modus laeuft er in einer eigenen, frischen Designsession**, nie im Controller: der
Controller beauftragt und entscheidet, die Designsession fuehrt Runde, Log, Zeilen-Datei, Tracking
Issue und Spec (`.agents/rules/pr.md` § "Controller Mode"). Ihr Ende ist der gepushte Zweig mit dem
Link im Tracking Issue; eine "fertig"-Meldung gibt es nicht (`.agents/rules/pr.md` § "Session
Traffic").

**Es gibt keinen Review-Prompt.** `pr-poll-review` beschafft seinen Kontext selbst am Head
(Spec-Datei, Tracking Issue, Decision-Log, CI, Konstellation); der Review-Chat startet mit einer
Zeile. Ein Artefakt traegt nur Zustand, den das Repo nicht liefert.

## Kernprinzip

- **Environment, nicht Framework:** Die Spec setzt Kontext + Aufgabe. Alles, was in AGENTS.md /
  CLAUDE.md steht (Workflow, Commit-/PR-Konvention), gehoert NICHT hinein — der Agent kennt es. Es
  gilt die Artefakt-Regel aus `AGENTS.md` § "Session Start: Read Before Anything Else"; sie deckt
  Spec-Datei, Decision-Log, Zeilen-Datei und Handoff gleichermassen ab.
- **Docs gewinnen:** Bei Widerspruch Spec vs. Repo-Docs gewinnen die Docs. Das steht in der Spec
  und gilt beim Bauen genauso — Repo-Fakten werden am Repo verifiziert, nicht aus dem Gedaechtnis
  gesetzt.
- **Discussion before artifacts:** Keine Spec vor finalen Entscheidungen. Erst klaeren, dann Log,
  dann Spec.
- **Datei-Transport:** Jedes Artefakt geht als Commit auf den Zweig, nie als Chat-Block; nur ohne
  Schreibzugang als Output-Datei ([`reference/decision-log.md`](reference/decision-log.md)).
- **Lehren der Rolle laden:** `pwsh scripts/common/get-lessons.ps1 -Role design`; ohne pwsh die
  Eintraege aus `.agents/lessons.md` lesen, deren `gilt fuer` `design` oder `alle` nennt.
- **Modell:** die Design-Session laeuft nach `AGENTS.md` § "Models".

## Eingabe

- Ziel-Repo (`owner/repo`) und die Aufgabe (frei oder Issue-Referenz `#N`).
- Fehlt eines: **fragen**, nicht raten.

## Schritt 0: Gates

**Projekt-Typ.**

- **Code-Repo mit Coding-Flow:** normale Spec, weiter mit Schritt 1.
- **Reines Design-/Infra-/Doku-Projekt** ohne Coding-Agent-Flow: KEINE Spec. Stattdessen
  Design-Diskussion + Decision-Log. Hier stoppen und das klarstellen.

**Audit** (`.agents/rules/audit.md` § "State Audit"). Vor jedem Design laeuft der Schnell-Check;
ein voller Audit nur, wenn er faellig ist.

- **Skript fahren:** `pwsh scripts/common/get-audit-due.ps1 -Path <pfade, die das Design anfasst>`.
  Es nennt je Bedingung die Ist-Zahl und das Verdikt. Die Ausgabe geht als eine Zeile ins
  Decision-Log.
- **Ohne pwsh von Hand:** (a) liegt kein `audit/ist-stand-*.md` im Repo? (b) aendert das Design
  Code, den das Architektur-/Baseline-Dokument beschreibt? (c) sind seit dem Commit des juengsten
  Audits mehr PRs gemergt als die Schwelle (30, oder `Audit-Schwelle:` in `CLAUDE.md`)? Je Frage die
  Zahl ins Log.
- **Faellig** → der volle Audit ist der erste Auftrag, nicht das Design. Ausfuehrender ist `ccweb`,
  nicht `cweb`: der Audit verlangt Checkout, Build und real gefahrene Tests. Mechanik im Skill
  `state-audit`.
- **Nicht faellig** → den Schnell-Check nach `state-audit` fahren und sein Ergebnis als Zeile ins
  Decision-Log; kein eigener PR.

## Schritt 1: Design-Runde und Tracking Issue

**Vor der ersten Frage** (`.agents/rules/audit.md` § "Design Round"):

- Jede Referenz, die der Auftrag nennt, **vollstaendig** lesen und im Log listen.
- Schwester-Repos nach demselben Mechanismus absuchen; was es dort schon gibt, ist Vorbild oder
  Abweichung mit Grund.
- `pwsh scripts/common/get-rejected-points.ps1` lesen: was schon `verworfen` ist, kommt nur mit
  neuem Argument (`neu_nur_mit`) wieder auf den Tisch. Ohne pwsh: die `verworfen`- und
  `zurueckgestellt`-Zeilen der `docs/decisions/*-ledger.jsonl` lesen.
- Wo ein Decision-Log eine Frage schon entschieden hat, wird ohne neue Runde nachgezogen.

**Die Runde.** Nicht-triviale Aufgaben erst durchentscheiden:

- Ein Thema pro Turn, am Ende "gibt es noch was?". Nicht selbststaendig weiterspringen. Im
  Controller-Modus ist der Controller der Adressat; die Frage geht als blockierende Frage ueber das
  Zustell-Werkzeug an ihn (`.agents/rules/pr.md` § "Session Traffic"), nicht in den Chat.
- **Sechs Abschnitte je offener Entscheidung, in dieser Reihenfolge — die Pflichtform:**
  1. Worum es geht.
  2. Stand der Technik — recherchiert, nicht aus dem Gedaechtnis.
  3. Was andere machen — mehrere Vergleichsprojekte.
  4. Ideen, naheliegende und unkonventionelle, verworfene mit Grund. **Die Vorgabe des Users ist
     hier eine Option unter anderen und wird gleich kritisch geprueft:** was spricht dagegen, welche
     Regel oder fruehere Entscheidung sie verletzt, welchen Preis sie hat, was besser waere.
  5. Empfehlung — eine klare Ansage.
  6. Was uns abheben koennte — **faellt nie weg**, auch als "hier nichts". Methode: zwei frische
     Hintergrund-Sessions. Die erste recherchiert Konkurrenz und Luecken und findet oder erfindet
     1 bis 4 Features, die andere Tools nicht haben und dem User echt etwas bringen; die zweite
     skizziert je Feature, wie es SOTA, modern, high-performance und Clean Code aussieht — als
     Skizze, nicht als Code. Wo keine Hintergrund-Session moeglich ist, recherchiert die
     Design-Session selbst. Das Ergebnis sind belegte Differenzierungspunkte; gebaut wird nur, was
     entschieden ist.

  Dazu am Ende jeder Runde die Liste **"nicht nachgelesen"**. **Staffel:** volle Form fuer
  Architektur-, Regel- und Schnitt-Entscheidungen; **Kurzform** (Worum / Empfehlung / Verworfen mit
  Grund) fuer Kleines — die gewaehlte Stufe wird genannt. Laesst sich ein Abschnitt (Stand der
  Technik, Vergleichsprojekte) nicht sauber belegen, entfaellt der Slot statt geraten zu werden.
- **Architektur-Abgleich, wo eine Entscheidung einen Mechanismus anlegt, verlegt oder aendert.** Ihre
  Semantik — was er tut, was er darf, was er nie darf — wird gegen den Architektur-Abschnitt
  gehalten, der ihn regelt, und dieser Abschnitt wird im Decision-Log genannt. "Eine Backlog-Zeile
  dazu abarbeiten" ersetzt diese Frage nicht — sie prueft nicht, ob der neue Mechanismus dem
  Abschnitt noch entspricht, sondern nur, ob irgendwas notiert wurde.
- Ergebnis als Decision-Log plus Zeilen-Datei, festgeschrieben **bevor** die Spec entsteht.
  **Zuerst lesen und quittieren:** [`reference/decision-log.md`](reference/decision-log.md), in der
  Zeilenform aus `AGENTS.md` § "Session Start: Read Before Anything Else", Schritt 3.

**Das Tracking Issue entsteht hier**, im selben Zug wie das Decision-Log und **bevor** die Spec
geschrieben wird (`.agents/rules/carrier.md` § "Tracking Issue"): ein Design = ein Decision-Log =
ein Tracking Issue, immer, mit den Labels `tracking` und `state:design`. Sein **Body** traegt alle
offenen Punkte des Designs; die Spec verlinkt das Issue, und der Agent traegt seine
zurueckgestellten Punkte dort ein.
Entstuende es erst beim ersten PR, gaebe es zwischen Design-Abschluss und erstem PR ein Fenster ohne
Traeger.

## Schritt 2: Repo-Kontext laden

Am echten Repo verifizieren (`gh` oder GitHub-Connector: `get_file_contents`, `issue_read`), nicht
annehmen:

- Pflichtkern und laufende Scheibe nach `AGENTS.md` § "Session Start: Read Before Anything Else",
  Schritte 1 und 2 — je mit Blob-SHA quittiert; Roadmap, Backlog und Architektur-Dokument nur on
  demand vor der Aussage, die sie betrifft.
- Einsatzpunkt-Quittung: dieser Skill schreibt einen Auftrag und legt ein Tracking Issue an, also
  werden `.agents/rules/carrier.md`, `.agents/rules/pr.md` und `.agents/rules/audit.md` vor der
  ersten Aktion ihres Typs vollstaendig gelesen und quittiert (Schritt 3). Einmal je Session je
  Datei.
- Issue-/Label-Konvention und den Decision-Log-Ort des Repos (`docs/decisions/README.md`).
- Betroffene Quell-Files, damit die Spec sie gezielt benennen kann.
- **Uebernahme-Check — was frueheren Scheiben hierher zugewiesen wurde:** vor dem Schnitt pruefen,
  ob eine Vorgaenger-Scheibe dieser Scheibe Punkte zugewiesen hat. Quelle ist **das Issue dieser
  Scheibe und ihre `roadmap.md`-/`backlog.md`-Zeile** — nicht der PR-Body des Vorgaengers, den
  niemand zurueckliest. Jeder gefundene Punkt wird in der Spec entweder als Vorgabe gefuehrt oder
  ausdruecklich als bewusst nicht gebaut benannt; stillschweigendes Uebergehen ist genau der
  Fehler, gegen den dieser Check steht.
- **Quellen-Erreichbarkeits-Check:** Jede Quelle, die die Spec referenziert (Issues, Decision-Logs,
  Konventions-Docs, fremde Repos), pruefen: existiert sie, ist sie gemergt/synced, und kann die
  **Ziel-Session** sie erreichen (Repo-Scope, Sandbox-Whitelist der Agent-Umgebung)? Was dann gilt:
  [`reference/spec.md`](reference/spec.md) § "Quellen in der Spec".

## Schritt 3: Spec bauen

**Zuerst den Review-Modus abfragen — Pflicht, keine Spec ohne diese Abfrage.** Der Skill schlaegt
selbst einen Modus vor (Heuristik in [`reference/spec.md`](reference/spec.md)) und fragt mit
vorbelegtem Vorschlag: "Review-Modus: hard / light / soft?". Im Controller-Modus ist der Controller
der Adressat, als blockierende Frage (`.agents/rules/pr.md` § "Session Traffic"). Die Spec nennt nur
die Zeile `Review-Modus: <modus>`; der Wortlaut steht in
[`pr-poll-review/reference/review-modes.md`](../pr-poll-review/reference/review-modes.md).

**Zuerst lesen und quittieren:** [`reference/spec.md`](reference/spec.md) — Lese-Auftrag, die acht
Bloecke, REQ-Schnitt, Doku-Nachzug, Baubar-Pflicht und Abhaken, was nicht hineingehoert. Dann die
Spec-Datei nach `.agents/rules/pr.md` § "Task Spec" schreiben.

## Schritt 4: Pushen und verlinken

1. Decision-Log, Zeilen-Datei und Spec-Datei auf einen Zweig committen und pushen
   ([`reference/decision-log.md`](reference/decision-log.md) § "Ablage per Push"); vorher
   `scripts/common/test-ledger.ps1` gruen.
2. Im Body des Tracking Issues verlinken: Zweig, Spec-Datei, Decision-Log, Zeilen-Datei,
   `Review-Modus: <modus>` und die Startzeile `/dev-task <owner/repo>#<N>`. Den Body aus einer Shell
   per `scripts/common/edit-issue-body.ps1` aendern (`.agents/rules/carrier.md` § "Tracking
   Issue"); ueber den Connector (`issue_write`) vorher und nachher lesen und vergleichen.
3. Das Zustands-Label des Issues nach `.agents/rules/pr.md` § "State Labels" pruefen: es steht auf
   `state:design` (Schritt 1), auch wenn das Issue schon vor der Runde bestand; das setzt dieser
   Skill selbst, mit und ohne Controller. `state:dev` setzt der Controller, ohne Controller
   `dev-task` beim Start.

Damit endet die Session. Ohne Controller nennt sie dem Maintainer die Startzeile; im
Controller-Modus liest der Controller sie am Issue.

## Strikte Regeln

- Nie ungefragt etwas nach GitHub posten ausser Zweig, Tracking Issue samt Body und Zustands-Label
  aus diesem Ablauf. Reine Status-Reads (PR/CI) sind ohne Freigabe ok. Eine Fix-Anweisung fuer
  einen offenen PR geht als PR-Review-Kommentar nach expliziter Freigabe.
- Keine Spec fuer ein neues Design ohne Schritt 0 und ohne das angelegte Tracking Issue aus
  Schritt 1.
- Neue Code-Level-Namen nicht annehmen — in der Spec offen lassen oder nachfragen. Bestehende
  (Fork-)Identifier nie unaufgefordert umbenennen.
- Verifizieren statt spekulieren: Repo-Fakten kommen aus dem Repo, nicht aus dem Gedaechtnis — und
  jede referenzierte Quelle muss fuer die Ziel-Session erreichbar sein (Schritt 2), sonst inline.
- Keine Spec ohne die Review-Modus-Abfrage aus Schritt 3, ohne den Uebernahme-Check aus Schritt 2
  und ohne einzeln aufgezaehlte Doku-Nachzugs-Quellen.

## Repo-Konventionen

- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); der
  GitHub-Connector nur als Fallback oder fuer Connector-only-Tools, in Claude Web der einzige Weg.
- Rollen getrennt: die Dev-Session oeffnet Draft-PRs (`dev`), gemergt wird nach
  `.agents/rules/pr.md` § "Merge".
