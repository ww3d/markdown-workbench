---
name: controller-mode
description: 'Steuernde Session fuer ein Repo: /controller-mode [repo] [lite]. Liest den Stand, prueft Sessions und PRs mit festen Fragen, startet Design-, Dev- und Review-Sessions per Skill-Zeile, raeumt fertige ab, merged nach dem Merge-Gate. lite: Design und Review laufen mit dem Maintainer im Fenster. Triggert bei "/controller-mode", "controller mode", "controller-modus". Nur fuer GitHub-Repos.'
metadata:
  version: "1.0.0"
  source: ww3d/playbook
  checksum: "sha256:18d214de312c97674818d2cae31efbe00071cd8d980688cfb7422881e260fc1e"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#351"
---

# Controller-Modus

Der Ablauf der steuernden Session. Die Regeln stehen in `.agents/rules/pr.md` § "Controller
Sessions", § "Controller Mode", § "Controller Lite", § "State Labels", § "Session Traffic" und
§ "Merge"; dieser Skill traegt den Ablauf und verweist dorthin. Der Skill liefert die Mechanik des
Sitzes, nie die Besetzung: wer ihn nicht ausdruecklich mit dieser Zeile bekommen hat, ist kein
Controller.

## Aufruf

`/controller-mode <owner/repo>` oder `/controller-mode <owner/repo> lite`. Die Zeile ersetzt die
fruehere Startzeile `Controller mode: <repo>.` samt Block. Der Startauftrag traegt nur diese Zeile
(`.agents/rules/pr.md` § "Controller Mode"); was offen ist, liest der Controller im Repo selbst, und
stehende Anordnungen des Maintainers liest er an ihrem Traeger — im Body des Tracking Issues oder in
der `CLAUDE.md` des Repos. Fehlt das Repo: **fragen**.

## Schritt 0: Eingang

1. Session-Start nach `AGENTS.md` § "Session Start: Read Before Anything Else", mit Blob-SHA
   quittiert; `.agents/rules/pr.md` und `.agents/rules/carrier.md` vor der ersten Aktion ihres Typs
   lesen und quittieren.
2. Lehren der Rolle laden: `pwsh scripts/common/get-lessons.ps1 -Role controller`; ohne pwsh die
   Eintraege aus `.agents/lessons.md` lesen, deren `gilt fuer` `controller` oder `alle` nennt.
3. Konto pruefen (`gh api user --jq .login` bzw. `get_me` im GitHub-Connector) gegen
   `.agents/rules/pr.md` § "Accounts per Seat"; Modell nach `AGENTS.md` § "Models".

## Schritt 1: Stand lesen

- Offene Tracking Issues (Label `tracking`) mit Body, ihre Zustands-Labels
  (`.agents/rules/pr.md` § "State Labels"), offene PRs mit Kopf, letzter Bewegung und "Wie
  getestet" (`gh issue list --label tracking`, `gh pr list`; in einer Claude-Code-Session per REST
  `gh api "repos/<owner>/<repo>/issues?labels=tracking&state=open"` und
  `gh api "repos/<owner>/<repo>/pulls?state=open"`, weil `gh issue` und `gh pr` dort an GraphQL
  scheitern; Connector: `list_issues`, `list_pull_requests`).
- Laufende Sessions dieses Repos und ihren Auftrag, ueber das Zustell-Werkzeug der Operation.
- Den Stau zaehlen — offene PRs und ihre letzte Bewegung — und gegen "Finish before you start"
  halten (`.agents/rules/pr.md` § "Controller Sessions"), bevor eine neue Aufgabe startet.

## Schritt 2: Status in fester Form

Jeder Status — an sich selbst, im Status-Kommentar des Tracking Issues, an den Maintainer — hat
diese vier Teile, in dieser Reihenfolge:

```text
Stand: <was gemergt, was im PR, was laeuft, je mit owner/repo#N>
Prio: <was zuerst, ein Satz warum>
Plan: <naechste Schritte, je Session/Skill-Zeile>
Offene Entscheidungen: <nur echte Wahl des Maintainers, je mit Kosten/Nutzen, sonst "keine">
```

Ein Status-Kommentar je Tracking Issue, vom Controller fortgeschrieben, traegt den Stand jedes PRs
des Features.

## Schritt 3: Pruefen mit festen Fragen

Je Session und je PR, am PR und am Issue — nie auf eine Meldung warten:

1. **Fertig?** PR steht, Kopf unter "Wie getestet" ist der Kopf, Wellen des Modus belegt.
2. **Kreis?** Dreht sich die Session im Kreis (dieselbe Korrektur zweimal, kein neuer Commit)?
3. **Fortschritt?** Was hat sich seit dem letzten Blick bewegt?
4. **Naechster Schritt?** Wer ist dran, mit welcher Skill-Zeile?
5. **Auftrag?** Steht der Auftrag vollstaendig am Traeger, und tut der PR genau das?

Was eine Frage offenlegt, entscheidet der Controller nach `AGENTS.md` § "Simplicity"; an den
Maintainer geht nur, was `.agents/rules/pr.md` § "Controller Mode" ihm vorbehaelt.

## Schritt 4: Steuern

Die Kette ist Design → Dev → Review, jede Session frisch, jede mit ihrer Skill-Zeile gestartet:

| Sitz | Startzeile |
|---|---|
| Design | `/ccweb-prompt <owner/repo> #<N>` (oder die Aufgabe) |
| Dev | `/dev-task <owner/repo>#<N>` |
| Review | `/pr-poll-review <owner/repo>#<PR>` |
| Audit | `/state-audit` im Ziel-Repo |

Die Regeln dazu — eine Dev-Session je Aufgabe, Abraeumen erst nach Abgabe, Wiederanlauf nur nach
Absturz, Schutzvermerke, Weitergabe von Anordnungen, Fragen an den Maintainer — stehen in
`.agents/rules/pr.md` § "Controller Sessions", die drei erlaubten Nachrichtenarten in § "Session
Traffic". Der Ablauf:

- **Abraeumen:** `/exit` ueber das Zustell-Werkzeug, dann entfernen — die Design-Session, sobald
  Zweig und Link am Issue stehen, die Review-Session, sobald ihr Approve oder ihre Zeile
  `Review-Verdikt: approve <sha>` zum Kopf am PR steht. Ein Befund oder ein Kommentar-Review der
  sauberen Runde raeumt sie nicht ab: sie approved danach noch (`.agents/rules/pr.md` § "Controller
  Lite").
- **Zeilen-Datei der Review-Runde:** traegt ein Review sie im Body und ist die Dev-Session des PRs
  schon weg, startet der Controller eine frische mit `/dev-task <owner/repo>#<N>` (Tracking Issue
  des PRs); sie arbeitet auf dem offenen PR weiter und committet die Datei (`dev-task` Schritt 4).
- **Zustands-Labels** (`.agents/rules/pr.md` § "State Labels") setzt der Controller bei jedem
  Uebergang, das alte nimmt er ab: Design laeuft → `state:design` (legt `ccweb-prompt` das Issue
  an, setzt es das Label selbst); Dev-Session gestartet → `state:dev`; PR auf ready →
  `state:review`; Approve bzw. Verdikt-Zeile → `state:gate`; Merge-Gate gruen → `state:merge-ready`;
  Frage oder Sichtabnahme beim Maintainer → `state:human`; ein Release laeuft → `state:release`.
  Per REST `gh api repos/<owner>/<repo>/issues/<N>/labels -f "labels[]=<neu>"` und
  `gh api -X DELETE repos/<owner>/<repo>/issues/<N>/labels/<alt>`; Connector: `issue_write`.
  Ohne Controller setzen die Skills ihre Labels selbst — `ccweb-prompt` `state:design`, `dev-task`
  `state:dev` und `state:review`, `pr-poll-review` `state:gate` —; `state:merge-ready` und
  `state:release` setzt, wer merged.
- **Aufraeum-Auftrag:** Issues, PRs, Zweige und Sessions mit "DO NOT CLOSE" / "DO NOT MERGE" oder
  einem Entscheid des Maintainers daran einzeln als unantastbar nennen.
- **Fragen an den Maintainer** sammeln und gebuendelt stellen; bis zur Antwort an allem anderen
  weiterarbeiten.
- Das Werkzeug, das Sessions startet und Nachrichten zustellt, heisst hier nach seiner Rolle
  Zustell-Werkzeug; wie Sessions gestartet werden, ist Sache der Operation.

## Schritt 5: Merge

Nach `.agents/rules/pr.md` § "Merge":

1. Merge-Gate: `pwsh scripts/common/test-merge-ready.ps1 -Repo <owner/repo> -Pr <n>`; reviewt dasselbe
   Konto, das den PR schrieb (Gleiches-Konto-Fall, `.agents/rules/pr.md` § "Accounts per Seat"), kommt
   `-SameAccount` dazu — nur dann zaehlt dessen Verdikt-Zeile im Review. Ohne pwsh von
   Hand: die Laufzeilen gegen den Merge-Kopf halten, wie `.agents/rules/pr.md` § "Merge" es
   beschreibt, und pruefen, dass ein Review-Verdikt vorliegt.
2. Ist ein Punkt als Sichtabnahme markiert (`state:human`): erst nach dem OK des Maintainers.
3. Vor dem Merge, bei `state:merge-ready`, bekommt der Maintainer im Tracking Issue eine
   Kurzanleitung:

   ```text
   Was neu: <ein bis drei Saetze>
   Warum: <Anlass, owner/repo#N>
   Wo: <Dateien, Befehle, Oberflaechen>
   Testen: <Befehle zum Nachpruefen>
   ```

4. Mergen, dann `pwsh scripts/common/close-tracking-issue.ps1 -Repo <owner/repo> -Pr <n>` fuer den
   gemergten PR — schliesst nur, was schliessbar ist, sonst sagt es, warum es offen bleibt. Den
   Ablauf samt Rueckfall ohne Skript beschreibt
   `.claude/skills/pr-poll-review/reference/gates.md` § "Nach dem Merge";
   ihn vor dem ersten Merge der Session lesen.

## Schritt 6: Rotation und Neustart

Rotation und Neustart regelt `.agents/rules/pr.md` § "Controller Sessions" (Fuellstand, Schnitt,
WIP-Push vor dem Neustart). Der Ablauf:

- Den eigenen Fuellstand messen; ist die Grenze erreicht, den laufenden kleinen Block fertig machen
  oder sauber schneiden, alles Offene vorher an den Traeger (`AGENTS.md` § "Session End: Carry What
  Is Still Open").
- Vor einem geplanten Neustart jede Session, die er trifft, ihren Stand als WIP auf ihren Zweig
  pushen lassen.
- Der Nachfolger startet mit derselben Zeile `/controller-mode <owner/repo> [lite]` und liest den
  Stand selbst; ein Handoff nur, wo sonst Stand verloren ginge (Skill `chat-handoff`).

## lite

`/controller-mode <owner/repo> lite` (`.agents/rules/pr.md` § "Controller Lite"): Design- und
Review-Sessions laufen mit dem Maintainer im Fenster, jede Re-Review-Runde ebenso. Der Controller
startet die Dev-Session, prueft (Schritt 3) und merged (Schritt 5). Alles andere gilt unveraendert.
