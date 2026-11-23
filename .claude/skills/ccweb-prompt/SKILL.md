---
name: ccweb-prompt
description: 'Design-Session: fuehrt die Design-Runde, schreibt Decision-Log, Zeilen-Datei und Spec-Datei, legt das Tracking Issue an und pusht alles auf einen Branch; die Spec ist der Auftrag, Startzeile /dev-task [repo]#[N]. Triggert bei "prompt fuer ccweb", "bau mir einen task", "prompt fuer issue #N", "prompt generieren", "task.md bauen", "design-runde". Nur fuer GitHub-Repos.'
metadata:
  version: "12.3.0"
  source: ww3d/playbook
  checksum: "sha256:c3fdfec40f85ef210b746e6eb640ce46cba0cd611fabb415c5d4531f1b4dc449"
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
  Zustell-Werkzeug an ihn (`.agents/rules/pr.md` § "Session Traffic"), nicht in den Chat. With design=page
  and design=auto the controller puts each question or decision as a sub-question of the round's one
  question on the question channel and passes the answer back word for word; with design=live the
  maintainer answers in the window.
- **Sechs Abschnitte je offener Entscheidung, in dieser Reihenfolge — die Pflichtform:**
  1. Worum es geht.
  2. Stand der Technik — recherchiert, nicht aus dem Gedaechtnis.
  3. Was andere machen — mehrere Vergleichsprojekte, nicht nur eins oder zwei.
  4. Ideen, naheliegende und unkonventionelle, verworfene mit Grund. **Die Vorgabe des Users ist
     hier eine Option unter anderen und wird gleich kritisch geprueft:** was spricht dagegen, welche
     Regel oder fruehere Entscheidung sie verletzt, welchen Preis sie hat, was besser waere.
  5. Empfehlung — eine klare Ansage, keine Auswahl zum Selbstentscheiden.
  6. Was uns abheben koennte — never left out. Besides the features of `.agents/rules/audit.md` § "Design
     Round", item "Every design question", it always carries one idea of its own that meets every word of the
     goal sentence (the check questions there), researched by the research rule there; "hier nichts" or "none
     found" is no answer (maintainer 2026-11-16T0055Z: „Nimm zusaetzlich unter Punkt 6 immer noch eine coole,
     ultra, mega, laessige, SOTA-, moderne, High-Performance-Idee mit auf, bzw. lass diese sauber nach unseren
     Research-Vorgaben (mind. 30-50 Quellen in den Bereichen) recherchieren.").

  Dazu am Ende jeder Runde die Liste **"nicht nachgelesen"**. **Staffel:** **Short form** (what it is about /
  recommendation / rejected with reason) only for small operational choices — a version step, a file name,
  an order of steps —; every rule, architecture or cut decision gets the full form with research. The round
  names the form it chose. A section that cannot be proven is researched further or put to the maintainer as
  a gap. Wie die Fragen dem Maintainer vorgelegt werden: `.agents/rules/chat.md` § "Talking to the Maintainer"
  (letzter Punkt).
- **Mandatory questions for every UI** (maintainer 2026-11-15T2324Z, point 4: „Pflichtfragen bei allen
  UI/UX-Sachen: Wie wird sie aufgebaut, als Liste, Spalten oder Board? Was passiert bei 10, 400 und
  5.000.000.000.000 Eintraegen? Gibt es Suche und Filter? Getestet wird mit echter Menge."; the list added by
  the orchestrator from 57 sources, accepted by the maintainer 2026-11-17): layout as list, columns or board,
  and why; columns, sort order, density; the amount by the check question "scalable", 0 and 1 included, and
  what lives in the browser and what on the server; pages, load more or endless; search and filter, and what
  "no results" shows; speed budgets; keyboard, touch, 320 px, screen reader, dark mode, languages, live
  changes; empty, loading, partial failure, offline; errors at the field, undo instead of a confirm dialog; a
  link to every view, the back button, a wizard with a way back; tested with the real amount and difficult
  data. Full list: [`reference/mandatory-questions.md`](reference/mandatory-questions.md).
- **Mandatory questions for all data** — database, file, sync, export, backup (maintainer 2026-11-18T2354Z:
  „Sollten wir dies nicht generell auch fuer jegliche Daten machen? UI ist ok, aber was ist mit
  Datenbanken/Files usw. usf???", yes 2355Z; text by the orchestrator from 57 sources, accepted
  2026-11-19T0137Z): which key, which format, how are time and text stored (UTC, Unicode)? The amount by the
  check question "scalable": bytes, the limit of the technology, splitting, old data? What happens on a crash
  mid-write, how is silent corruption found? How much data loss and downtime are allowed, and when did a
  restore last really run, measured? How is live data copied consistently? Who may do what, what is personal
  data, how is it deleted? A schema change without downtime, with a way back? Tested with the real amount and
  difficult data. A task with a UI and data answers both lists. Full list:
  [`reference/mandatory-questions.md`](reference/mandatory-questions.md).
- Neither list names an amount of its own beyond the quotes; the amount is the check question "scalable" of
  `.agents/rules/audit.md` § "Design Round".
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

**Design document before committing** (maintainer 2026-11-12T1428Z: „Ich will fuer jedes Design hier, das ohne
mich laeuft und gelaufen ist, ab jetzt ein sauberes Designdokument VORHER immer. Also wenn die Designsession
noch laeuft. Am Ende. Bevor sie die Entscheidungen festschreibt. Das Designdokument einfach und
umgangssprachlich. Kurz und praezise. Damit ich lenken kann"): a round without the maintainer in the window
writes at its end, before it commits decisions, spec or ledger file, a design document as a file on its
branch — the only source — in the report form of `.agents/rules/chat.md`, with links to the new texts, and puts
it to him as one question on the question channel: the short form in the question, the link to the file;
a follow-up that needs his new word asks the question anew (`.agents/rules/chat.md` § "Working With the Maintainer"). It commits only after his answer. With design=page the
sub-questions replace it; where the round makes new rule text from the maintainer's sentences, that wording
goes to him once for acceptance (`.agents/rules/docs.md` § "Quoting the Maintainer"). With design=auto the
unread sub-questions replace it; the decision log is written as always.

**Das Tracking Issue entsteht hier**, im selben Zug wie das Decision-Log und **bevor** die Spec
geschrieben wird, mit den Labels `tracking` und `state:design`, ohne Plan-Label, bis der Maintainer
es setzt (`controller-mode` § "Planung"). **Its anchor is a tracking issue** (created by the design
round before the spec file), no later.

**Der Body beginnt** vor `## Order` mit dem Hinweiskasten `> [!NOTE]` (Worum, Naechster Schritt) und dem leeren
Maschinen-Abschnitt (beide Marken): `edit-issue-body.ps1 -Issue <n> -Status -Create -Hand '**Worum:** <..>','**Naechster Schritt:** <..>'`
direkt nach dem Anlegen; Form und Pflege: `.agents/rules/carrier.md` § "Tracking Issue".

**Feste Ueberschriften des Bodys**, in dieser Reihenfolge und woertlich: `## Order` (der Auftrag des
Maintainers woertlich), `## Design`, `## Open points` (die offenen Punkte als Kaestchen), `##
Unclear, to measure`, `## Corrected`, `## Done`. Einen Abschnitt `## Seats` legt die Design-Session
nicht an; ihn schreibt der Controller. Verlangt der Auftrag eine Sichtabnahme, setzt die
Design-Session unter `## Design` die Zeile `Visual acceptance: <what>`, fragt die Freigabe zum
Einspielen mit und traegt sie unter `## Design` als `Go-live approval: <was, wohin> (<Quelle>)` ein und
setzt unter `## Open points` den Haken `- [ ] Visual acceptance live: <what>`.

### Regeln des Tracking Issues

- **One design = one decision log = one tracking issue**, however many PRs the design takes —
  created **always**, even when no point stays open.
- **An order carries no closing keyword with a number** — whoever writes one (controller,
  orchestrator, design session) words it without `Closes #N`, `Fixes #N` or `Resolves #N`.
- Build nothing an open issue or PR already builds — check first.
- Read the running phase's decision logs as `.agents/rules/audit.md` § "Design Round" says.

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

The spec names `Review-Mode: once`; another mode only as [`reference/spec.md`](reference/spec.md) §
"Review-Modus waehlen" says.

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
