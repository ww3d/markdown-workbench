---
name: dev-task
description: 'Dev-Session: /dev-task [repo]#[N] liest das Issue, findet Zweig und Spec-Datei der Design-Runde, arbeitet darauf und oeffnet den Draft-PR; /dev-task "[auftrag]" pusht sofort Zweig und Draft-PR mit dem Auftrag woertlich. Triggert bei "/dev-task", "dev-task", "setz issue #N um", "arbeite die spec ab". Nur fuer GitHub-Repos.'
metadata:
  version: "1.0.0"
  source: ww3d/playbook
  checksum: "sha256:b6b55f6dcaec1e34f2288ff662a82fdaeab6d895883c5d711b6fc8869a1b3f9f"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#351"
---

# Dev-Auftrag umsetzen

Fuellt die `dev`-Rolle aus `.agents/rules/pr.md` § "PR Lifecycle": Code schreiben, Draft-PR
oeffnen, testen, auf ready stellen, Reviewer setzen. Ein Dev-Auftrag ist eine Session und ein
Thema; sein Inhalt steht vollstaendig am Traeger (Issue, Spec-Datei, PR-Body), nie nur in der
Startnachricht. Der Merge gehoert nicht dazu (`.agents/rules/pr.md` § "Merge").

## Aufruf

- `/dev-task <owner/repo>#<N>` — Weg A: das Issue traegt den Auftrag; die Design-Runde
  (`ccweb-prompt`) hat Zweig, Spec-Datei, Decision-Log und Zeilen-Datei gepusht und im Body
  verlinkt.
- `/dev-task "<auftrag>"` — Weg B: der Auftragstext ist der Auftrag; Ziel-Repo ist das Repo der
  Session, sonst steht `<owner/repo>` davor.
- Fehlt beides oder ist das Repo unklar: **fragen**, nicht raten.

## Schritt 0: Eingang

1. Session-Start nach `AGENTS.md` § "Session Start: Read Before Anything Else": Pflichtkern lesen
   und je Datei mit Blob-SHA quittieren. Ohne Hooks ist das die erste Antwort.
2. Einsatzpunkt-Quittungen vor der ersten Aktion ihres Typs, einmal je Session je Datei:
   `.agents/rules/pr.md` (PR oeffnen), `.agents/rules/code.md` (Code schreiben),
   `.agents/rules/docs.md` (Doku anfassen), `.agents/rules/carrier.md` (Punkt zurueckstellen),
   `.agents/rules/evidence.md` (etwas fertig oder gruen nennen).
3. Lehren der Rolle laden: `pwsh scripts/common/get-lessons.ps1 -Role dev`; ohne pwsh die Eintraege
   aus `.agents/lessons.md` lesen, deren `gilt fuer` `dev` oder `alle` nennt.
4. Konto pruefen, bevor irgendetwas geschrieben wird: `gh api user --jq .login` bzw. `get_me` im
   GitHub-Connector, gegen `.agents/rules/pr.md` § "Accounts per Seat".
5. Modell nach `AGENTS.md` § "Models".

## Schritt 1a: Weg A — Issue

1. Den Issue-Body vollstaendig lesen (`gh issue view <N> -R <owner/repo>`; in einer
   Claude-Code-Session per REST `gh api repos/<owner>/<repo>/issues/<N> --jq .body`, weil `gh issue`
   und `gh pr` dort an GraphQL scheitern; Connector: `issue_read`). Er verlinkt Zweig, Spec-Datei
   `docs/tasks/<N>-<slug>.md`, Decision-Log, Zeilen-Datei und `Review-Modus: <modus>`.
2. Den Zweig holen: `git fetch origin && git switch <zweig>` (Connector: `get_file_contents` mit
   `ref` auf den Zweig). Auf **diesem** Zweig wird gearbeitet; kein neuer, kein Auto-Slug.
3. Spec-Datei, Decision-Log und Zeilen-Datei am Kopf des Zweigs **vollstaendig** lesen. Die Spec
   ist der Auftrag; bei Widerspruch zu den Docs gewinnen die Docs, ausser die Spec setzt eine
   Entscheidung um, die die Docs aendern soll.
4. Nennt das Issue keinen Zweig oder keine Spec: nicht raten, sondern eine blockierende Frage
   (Schritt 4).
5. Den Draft-PR frueh von diesem Zweig oeffnen (`gh pr create --draft`; per REST
   `gh api repos/<owner>/<repo>/pulls -f head=<zweig> -f base=<basis> -f title=<titel>
   -F body=@<datei> -F draft=true`; Connector: `create_pull_request` mit `draft: true`), Body nach
   `.agents/rules/pr.md` § "PR / MR Description", Spec verlinkt, Anker mit `Refs #<N>` oder
   `Closes #<N>` nach den Regeln dort. Steht von diesem Zweig schon ein offener PR, arbeitet die
   Session auf ihm weiter — zuerst eine Zeilen-Datei aus dem Review-Body und offene Befunde
   (Schritt 4).
6. **Ohne Controller** das Tracking Issue auf `state:dev` setzen und `state:design` abnehmen
   (`.agents/rules/pr.md` § "State Labels"): `gh api repos/<owner>/<repo>/issues/<N>/labels
   -f "labels[]=state:dev"` und
   `gh api -X DELETE repos/<owner>/<repo>/issues/<N>/labels/state:design`; Connector:
   `issue_write`. Im Controller-Modus setzt es der Controller.

## Schritt 1b: Weg B — Auftragstext

Weg B braucht einen Checkout: der Start-Commit ist leer, und den kann nur `git` pushen —
`push_files` des Connectors braucht Dateien, und GitHub oeffnet keinen PR ohne Commit vor der Basis.

1. Zweig nach `.agents/rules/pr.md` § "Branch Naming" anlegen.
2. Leerer Start-Commit (`git commit --allow-empty`), **sofort** pushen (`git push -u origin
   <zweig>`) und den Draft-PR oeffnen (`gh pr create --draft` oder die REST-Form aus Schritt 1a
   Punkt 5; Connector: `create_pull_request` mit `draft: true`). Der Auftrag steht **woertlich**
   im PR-Body, als Zitat unter **Was** — ungekuerzt, unveraendert.
3. Traegt der Auftrag eine nummerierte Liste: jetzt, mit der PR-Nummer, die Spec-Datei
   `docs/tasks/pr-<N>-<slug>.md` nach `.agents/rules/pr.md` § "Task Spec" committen und pushen
   (Spec ohne Issue, der PR ist der Anker); der Body verlinkt sie.
4. Ein Issue entsteht, sobald ein Punkt offen bleibt, der einen Traeger braucht
   (`.agents/rules/carrier.md` § "Carrier Requirement").

## Schritt 2: Bauen

- Nach der Spec, REQ fuer REQ; jede REQ abhaken oder `nicht geliefert: <grund>`. Gelieferte Punkte
  aus dem Body des Tracking Issues im selben PR dort abhaken (`.agents/rules/carrier.md`
  § "Tracking Issue"); den Body aus einer Shell per `scripts/common/edit-issue-body.ps1`.
- Den PR abonnieren (`subscribe_pr_activity`, Laden nach `.agents/rules/pr.md` § "PR Lifecycle").
- Stand frueh und oft pushen; vor jedem geplanten Ende alles gepusht, WIP auf dem Zweig.
- Review-Wellen nach dem Modus der Spec: den Baustein
  [`pr-poll-review/reference/review-modes.md`](../pr-poll-review/reference/review-modes.md) lesen
  und quittieren, bevor die erste Welle laeuft; der Wellen-Bericht geht in den PR-Body.

## Schritt 3: Testen

Nach `.agents/rules/pr.md` § "Test Runs" — dort stehen Zahl der vollen Laeufe, Korrekturrunden,
Zeitvorgabe und die Form der Laufzeile; hier nur der Ablauf:

1. Den vollen Lauf des Repos aus seiner `CLAUDE.md` (Befehl, Plattformen) und seine Waechterklassen
   nachlesen.
2. Voller Lauf vor der Uebergabe ans Review; je Lauf eine Laufzeile unter "Wie getestet".
3. Korrekturrunden: geaenderte Klassen, Waechterklassen, Mutationsprobe — je mit Laufzeile.
4. Am Endstand vor dem Merge der zweite volle Lauf, wenn sich nach dem ersten Code geaendert oder
   `main` bewegt hat.
5. Ohne Code im Diff: Format- und Linkpruefung statt vollem Lauf.

## Schritt 4: Ende

**Das Ende ist der PR**: Draft → ready, Reviewer nach `.agents/rules/pr.md` § "Reviewer" gesetzt,
Laufzeilen im Body. Keine "fertig"-Meldung — der Controller (oder der Maintainer) prueft am PR
(`.agents/rules/pr.md` § "Session Traffic"). **Ohne Controller** setzt die Session beim Schritt auf
ready das Tracking Issue auf `state:review` und nimmt `state:dev` ab, wie in Schritt 1a Punkt 6; im
Controller-Modus setzt es der Controller. Weg B ohne Tracking Issue setzt kein Label.

An den Controller, ohne Controller an den Maintainer, geht nur:

- eine **blockierende Frage** — in der Kurzform aus `ccweb-prompt` § "Schritt 1: Design-Runde und
  Tracking Issue" (Absatz "Staffel": Worum / Empfehlung / Verworfen mit Grund), Empfehlung
  vorbelegt;
- **"haengt"** mit einem Satz, woran.

Review-Befunde arbeitet die Session im selben PR ab, solange sie laeuft; eine neue Aufgabe ist eine
neue Session. Traegt ein Review die Zeilen-Datei seiner Runde als `jsonl`-Block im Body, committet
die Session sie unter dem dort genannten Namen mit ihrem naechsten Push, als eigenen Commit
(`.claude/skills/pr-poll-review/reference/report.md` § "Zeilen-Datei der Runde").

## Strikte Regeln

- Nie mergen, nie unter dem Konto des Maintainers schreiben (`.agents/rules/pr.md` § "Accounts per
  Seat").
- Nie einen anderen Zweig als den des Issues bzw. den eigenen benutzen; Force-Push nur auf den
  eigenen Zweig, mit Lease und im PR-Body begruendet.
- Den Auftrag nie kuerzen, weglassen, ersetzen oder verschieben — weniger Umfang geht als Frage an
  den Maintainer (`AGENTS.md` § "Core Rules").
- `git` + `gh` sind Default (`AGENTS.md` § "Forge Tooling"); in Claude Web der GitHub-Connector,
  dann in einem PR-Ablauf durchgehend.
