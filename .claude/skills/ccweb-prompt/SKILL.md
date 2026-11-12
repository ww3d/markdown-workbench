---
name: ccweb-prompt
description: 'Design-Session: fuehrt die Design-Runde, schreibt Decision-Log, Zeilen-Datei und Spec-Datei, legt das Tracking Issue an und pusht alles auf einen Branch; die Spec ist der Auftrag, Startzeile /dev-task [repo]#[N]. Triggert bei "prompt fuer ccweb", "bau mir einen task", "prompt fuer issue #N", "prompt generieren", "task.md bauen", "design-runde". Nur fuer GitHub-Repos.'
metadata:
  version: "11.9.2"
  source: ww3d/playbook
  checksum: "sha256:8f15e9d27bf763e34117b874668a9261e215e1b4029a927949c7bc25b6cdd2c8"
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

## Kernprinzip

- Es gilt die **Artefakt-Regel**: a generated artifact (task spec, decision log, handoff, prompt)
  carries only verified state the repo cannot provide — decisions, cleared-up misconceptions,
  constellation — never rules or doc summaries.
- **Discussion before artifacts:** Keine Spec vor finalen Entscheidungen.

## Schritt 0: Gates

**Audit** (`.agents/rules/audit.md` § "State Audit"): vor jedem Design der Schnell-Check, der volle
Audit nur, wenn er faellig ist — nach Skill `state-audit`.

- **Faellig** → der volle Audit ist der erste Auftrag, nicht das Design. Im Controller-Modus fragt
  die Design-Session den Controller und liest danach das Ergebnis `docs/audit/state-*.md` am Head.

## Schritt 1: Design-Runde und Tracking Issue

- Ohne pwsh: die `rejected`- und `deferred`-Zeilen der `docs/decisions/*-ledger.jsonl` lesen.

- Ein Thema pro Turn, am Ende "gibt es noch was?". Nicht selbststaendig weiterspringen. Im
  Controller-Modus ist der Controller der Adressat; die Frage geht als blockierende Frage ueber das
  Zustell-Werkzeug an ihn (`.agents/rules/pr.md` § "Session Traffic"), nicht in den Chat.
- **Sechs Abschnitte je offener Entscheidung, in dieser Reihenfolge — die Pflichtform:**
  1. Worum es geht.
  2. Stand der Technik — recherchiert, nicht aus dem Gedaechtnis.
  3. Was andere machen — mehrere Vergleichsprojekte, nicht nur eins oder zwei.
  4. Ideen, naheliegende und unkonventionelle, verworfene mit Grund. **Die Vorgabe des Users ist
     hier eine Option unter anderen und wird gleich kritisch geprueft:** was spricht dagegen, welche
     Regel oder fruehere Entscheidung sie verletzt, welchen Preis sie hat, was besser waere.
  5. Empfehlung — eine klare Ansage, keine Auswahl zum Selbstentscheiden.
  6. Was uns abheben koennte — **faellt nie weg**, auch als "hier nichts". Methode, Abheber und
     Grenze: `.agents/rules/audit.md` § "Design Round", Punkt "Every design question".

  Dazu am Ende jeder Runde die Liste **"nicht nachgelesen"**. **Staffel:** volle Form fuer
  Architektur-, Regel- und Schnitt-Entscheidungen; **Kurzform** (Worum / Empfehlung / Verworfen mit
  Grund) fuer Kleines — die gewaehlte Stufe wird genannt. Laesst sich ein Abschnitt (Stand der
  Technik, Vergleichsprojekte) nicht sauber belegen, entfaellt der Slot statt geraten zu werden.
  Wie die Fragen dem Maintainer vorgelegt werden: `.agents/rules/chat.md` § "Talking to the Maintainer"
  (letzter Punkt).
- **Architektur-Abgleich, wo eine Entscheidung einen Mechanismus anlegt, verlegt oder aendert.** Ihre
  Semantik — was er tut, was er darf, was er nie darf — wird gegen den Architektur-Abschnitt
  gehalten, der ihn regelt, und dieser Abschnitt wird im Decision-Log genannt. "Eine Backlog-Zeile
  dazu abarbeiten" ersetzt diese Frage nicht — sie prueft nicht, ob der neue Mechanismus dem
  Abschnitt noch entspricht, sondern nur, ob irgendwas notiert wurde.
- Ergebnis als Decision-Log plus Zeilen-Datei, festgeschrieben **bevor** die Spec entsteht. **Zuerst
  lesen und quittieren:** [`reference/decision-log.md`](reference/decision-log.md). Eine offene
  Frage an den Maintainer steht als `(question <N>)`, `<N>` die Nummer, die ihr der Fragen-Kanal des
  Maintainers gab; der Marker gilt nur fuer eine offene Frage, eine beantwortete wird durch die
  Entscheidung mit ihrer Quelle ersetzt. Im Controller-Modus vergibt die Nummer der Controller, der
  die Frage einstellt; die Runde traegt sie nach seiner Antwort ein.

**Das Tracking Issue entsteht hier**, im selben Zug wie das Decision-Log und **bevor** die Spec
geschrieben wird, mit den Labels `tracking` und `state:design`, ohne Plan-Label, bis der Maintainer
es setzt (`controller-mode` § "Planung"). **Its anchor is a tracking issue** (created by the design
round before the spec file), no later.

**Feste Ueberschriften des Bodys**, in dieser Reihenfolge und woertlich: `## Order` (der Auftrag des
Maintainers woertlich), `## Design`, `## Open points` (die offenen Punkte als Kaestchen), `##
Unclear, to measure`, `## Corrected`, `## Done`. Einen Abschnitt `## Seats` legt die Design-Session
nicht an; ihn schreibt der Controller. Verlangt der Auftrag eine Sichtabnahme, setzt die
Design-Session unter `## Design` die Zeile `Visual acceptance: <what>`.

### Regeln des Tracking Issues

- **One design = one decision log = one tracking issue**, however many PRs the design takes —
  created **always**, even when no point stays open.
- **An order carries no closing keyword with a number** — whoever writes one (controller,
  orchestrator, design session) words it without `Closes #N`, `Fixes #N` or `Resolves #N`.
- Build nothing an open issue or PR already builds — check first.
- Read the running phase's decision logs always.

## Schritt 2: Repo-Kontext laden

Am echten Repo lesen:

- Laufende Scheibe lesen; Roadmap, Backlog und Architektur-Dokument nur on demand vor der Aussage,
  die sie betrifft.
- **Uebernahme-Check — was frueheren Scheiben hierher zugewiesen wurde:** vor dem Schnitt pruefen,
  ob eine Vorgaenger-Scheibe dieser Scheibe Punkte zugewiesen hat. Quelle ist **das Issue dieser
  Scheibe und ihre `roadmap.md`-/`backlog.md`-Zeile** — nicht der PR-Body des Vorgaengers. Jeder
  gefundene Punkt wird in der Spec entweder als Vorgabe gefuehrt oder ausdruecklich als bewusst
  nicht gebaut benannt.
- **Quellen-Erreichbarkeits-Check:** Jede Quelle, die die Spec referenziert (Issues, Decision-Logs,
  Konventions-Docs, fremde Repos), pruefen: existiert sie, ist sie gemergt/synced, und kann die
  **Ziel-Session** sie erreichen (Repo-Scope, Sandbox-Whitelist der Agent-Umgebung)? Was dann gilt:
  [`reference/spec.md`](reference/spec.md) § "Quellen in der Spec".

## Schritt 3: Spec bauen

**Zuerst den Review-Modus abfragen — Pflicht, keine Spec ohne diese Abfrage.** Er schlaegt einen
Modus vor (Heuristik in [`reference/spec.md`](reference/spec.md)) und fragt: "Review-Mode: hard /
light / soft / once?".

**Zuerst lesen und quittieren:** [`reference/spec.md`](reference/spec.md).

## Schritt 4: Pushen und verlinken

1. Decision-Log, Zeilen-Datei und Spec-Datei auf einen Branch committen und pushen
   ([`reference/decision-log.md`](reference/decision-log.md) § "Ablage per Push"); vorher
   `scripts/common/test-ledger.ps1` gruen.

   Daneben laeuft
   `pwsh scripts/common/test-question-markers.ps1 -Repo <owner/repo> -Issue <N>`; mit einem Fund gibt
   die Runde nicht ab. Der Weg vorbei ist `-Waive "<Grund>"` plus die Zeile
   `Question check waived: <Grund>` unter `## Design` des Tracking Issues.
2. Unter `## Design` im Body des Tracking Issues verlinken: Branch, Spec-Datei, Decision-Log,
   Zeilen-Datei, `Review-Mode: <mode>` und die Startzeile `/dev-task <owner/repo>#<N>`.
3. Das Zustands-Label des Issues pruefen: es steht auf `state:design`, auch wenn das Issue schon vor
   der Runde bestand.

Damit endet die Runde, mit der Abgabe nach `.agents/rules/pr.md` § "Session Traffic": der Link auf
das Tracking Issue an den Besitzer. Ohne Controller nennt die Session dem Maintainer die Startzeile
mit. Will der Controller vor dem Merge den zweiten Blick, bleibt die Session bis dahin bestehen.

## Zweiter Blick

Auf Anstoss des Controllers, am approvten Head: jede Festlegung des Decision-Logs und jeder Satz des
Auftrags (`## Order`) gegen den Diff. Funde gehen als Bericht-Datei an den Controller. Ohne Fund
geht nur die Abgabe, der Link auf das Tracking Issue.

## Strikte Regeln

- Wann diese Design-Session rotiert, sagt ihre Art in `.agents/session-kinds.json`; die Uebergabe regelt `.agents/rules/controller.md` § "Controller Sessions".
- Der Text eines Weckers (`ScheduleWakeup`, `/loop`) nennt den Schritt, auf den gewartet wird, und
  was danach zu tun ist, nie die Startzeile des Skills; ein Hintergrund-Lauf meldet sein Ende
  selbst, der Wecker ist nur Rueckfall.

## Repo-Konventionen

- Whether the folder rules of `.agents/rules/code.md` § "Folder Conventions" apply to the existing tree or only the diff is the repo's call, decided in the design round.
