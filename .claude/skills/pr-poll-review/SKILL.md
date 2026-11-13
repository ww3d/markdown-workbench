---
name: pr-poll-review
description: 'Reviewt einen GitHub Pull Request iterativ bis zum Approve (reviewer-Rolle). Triggert bei "review und wenn ok approve", "pr pollen", "check PR [ref]", "approve sobald die changes da sind", "rere". Nicht fuer einen einmaligen Review ohne Approve. Nur fuer GitHub-PRs.'
metadata:
  version: "14.14.0"
  source: ww3d/playbook
  checksum: "sha256:9aa07d1f1e09f62ee9c847bd9d30d32f229778c100dd9df89a484a12071d66f9"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#210"
---

# PR Review & Approve Workflow

Dieser Skill merged nie und endet mit dem Approve; das Tracking Issue schliesst, wer merged.

## Kernprinzip

- Ein `issue:` traegt im geposteten Kommentar die Zeilen Fehlerart, Suche (der Befehl, woertlich) und Fundstellen.
- Im Controller-Modus ist der Controller der Adressat: Stufe A geht als Text-Datei an ihn — lokal nennt die Nachricht den Pfad, im Web liegt die Datei auf dem Branch `review/<N>-report` (nie ein PR, nach dem Approve geloescht) und die Nachricht nennt ihren Pfad; die Freigabe kommt als Text zurueck, ohne Widget. Faellt der Nachrichtenweg aus, gilt `.agents/rules/review.md` § "Hand-Back and Owner Change".
- Review-Schleife im Controller-Modus mit der Dev-Session aus dem Start: jede Runde findet alle Punkte, auch die nicht blockierenden (bei `once` ab Runde 2 nur der Blick, Phase 3); nach dem Posten `#N Review zu <sha> steht` an den Dev, auf sein `#N Head <sha> bereit` laeuft Phase 3.

## Eingabe

- Ausnahme `rere`: Re-Review des zuletzt in dieser Session gereviewten PRs.

## Phase 1: Erstreview

0. Eingang: `pwsh scripts/common/test-pr-form.ps1 -Repo <repo> -Pr <n>` im Checkout, vor allem anderen — Exit 0 gruen, 1 rot, 2 nicht lesbar. Bei Rot kein Review: nichts wird gepostet, der Reviewer schickt dem Dev (Name aus dem Start) die roten Zeilen und wartet wie in Phase 2. Laeuft das Skript nicht (Exit 2, kein `pwsh`, kein Checkout), gehen die Formpunkte von Hand in den Block "Form, blockt nie", und der Review-Body sagt, dass es nicht lief.

1. Spec-Datei, Tracking Issue und Decision-Log am Head-SHA lesen, nicht dem PR-Body glauben.
   Review-Modus aus der Zeile `Review-Mode:` der Spec am Head, nie aus dem PR-Body; Bausteine: [`reference/review-modes.md`](reference/review-modes.md).

2. Ab rund 300 geaenderten Zeilen (ohne reine Verschiebungen und generierte Dateien) wird je Commit
   oder je Datei getrennt geprueft, die Funde danach zusammengefuehrt; die Suche je Fehlerart laeuft
   weiter ueber den ganzen PR (`.agents/rules/review.md` § "Review Comments").

3. Ohne Skript, und fuer eine Quelle, die das Skript als `SOURCE UNAVAILABLE` meldet: jede waehrend des PRs neu in den Body des Tracking Issues, in `roadmap.md` oder `backlog.md` gekommene Zeile von Hand gegen die Dateiliste des Diffs halten; der Report sagt das.

3a. Sprache: neue Bezeichner, Feldnamen und Adressen im Diff pruefen (`.agents/rules/review.md` § "Review Comments").

4. Freigabe-Gate (vor jeder Veroeffentlichung). Zuerst lesen und quittieren: [`reference/report.md`](reference/report.md). **Dann den Review-Head festhalten**, nach dem
   Holen des Heads und vor Bericht und Freigabe-Bitte, mit einem eigenen Befehl — der Hook
   `require-rule-read.sh` liest diese Zeile, genau in dieser Form (voller 40-stelliger SHA):

   ```bash
   echo "review-head | <owner>/<repo>#<n> | $(gh api repos/<owner>/<repo>/pulls/<n> --jq .head.sha)"
   ```

   Ohne `gh`: den vollen Head-SHA aus `pull_request_read` (method=`get`) in derselben Zeilenform
   ausgeben. Das Widget gibt es nur im claude.ai-Chat mit dem Maintainer; die VORLAGE-Zone kommt ueber die Contents-API (das Repo ist privat): `gh api repos/ww3d/playbook/contents/.claude/skills/pr-poll-review/reference/widget-reference.html -H "Accept: application/vnd.github.raw"` bzw. `get_file_contents`.

5. Zeilen-Datei der Runde schreiben und pruefen, bevor gepostet wird (`reference/report.md` § "Zeilen-Datei der Runde"); sie haengt am Review-Post, der Reviewer pusht nie auf den PR-Branch.

7. Review posten via `gh api` auf den Reviews-Endpunkt bzw. `pull_request_review_write` (nur freigegebene Punkte):
   - `event`: `REQUEST_CHANGES` wenn ein blockierender Punkt dabei ist, sonst `COMMENT` — ausser beim
     Approve mit offenen Vorschlaegen (`.agents/rules/review.md` § "Review Comments").
   - Eine entschiedene offene Frage geht als Anweisung an den Author statt als Frage.

8. Den Head als `reviewed_sha` merken.

## Phase 2: Auf Aenderungen warten

Neu reviewt wird erst der Head, an dem der PR wieder bereit ist; ein Push auf den Entwurf ist noch
kein Stand zum Reviewen.

- Im Controller-Modus: auf `#N Head <sha> bereit` der Dev-Session warten.
- Sonst `subscribe_pr_activity` aufrufen und den Turn beenden.
  Je Event Head und Entwurfs-Zustand nachladen.
- Der Text eines Weckers (`ScheduleWakeup`, `/loop`) nennt den Schritt, auf den gewartet wird, und
  was danach zu tun ist, nie die Startzeile des Skills; ein Hintergrund-Lauf meldet sein Ende
  selbst, der Wecker ist nur Rueckfall.
- Ohne Webhooks Head und Entwurfs-Zustand nachfragen (`gh api repos/<repo>/pulls/<n> --jq '{sha: .head.sha, draft: .draft}'` bzw. `pull_request_read`), bis der Head von `reviewed_sha` abweicht und der PR nicht Entwurf ist.

## Phase 3: Re-Review

Ab hier sperrt Form nie: das Skript aus Schritt 0 laeuft am neuen Head erneut; seine roten Zeilen (ausser denen, die `reference/gates.md` § "Form haelt das Approve nie auf" als Inhalt blocken laesst) und die Formpunkte, die kein Skript sieht, stehen als ein Block "Form, blockt nie" im Review-Body, kein Inline-Kommentar.

1. Erst den Beweis, im Checkout nach `git fetch origin <default-branch> <head-branch>`: `pwsh scripts/common/test-pure-catch-up.ps1 -Reviewed <reviewed_sha> -Head <head_sha> -Base origin/<default-branch>`; nach einem Verdikt mit offenen Vorschlaegen `pwsh scripts/common/test-applied-suggestions.ps1 -Repo <repo> -Pr <n> -Verdict <reviewed_sha> -Head <head_sha> -Base origin/<default-branch>`; im Gleiches-Konto-Fall fuehrt den Beweis das Merge-Gate. `PURE` bzw. `PROVEN`: keine neue Runde, das Verdikt bleibt stehen. Sonst (`NOT PURE`, `NOT PROVEN`, kein Checkout oder `pwsh`) weiter mit Schritt 2.
2. Diff zwischen `reviewed_sha` und neuem `head_sha` holen.
3. Pro frueherem Punkt pruefen, ob er am neuen Head adressiert ist; fuer jedes fruehere `issue:` dieselbe Suche wie im Bericht am neuen Head wiederholen; der Fix gilt erst, wenn sie keine Fundstelle der Fehlerart mehr findet (`reference/checks.md` § "Fehlerart je Befund").
   Die Checks aus Phase 1 auf das neu Dazugekommene anwenden; bei `once` nur der Blick aus `reference/review-modes.md`.
4.
   - Alle blockierenden adressiert, keine neuen → Phase 4.
   - Rest- oder Neu-Punkte → sammeln → Freigabe-Gate (bei `once` ohne), Zeilen-Datei, Review-Head (Phase 1, Schritte 4-5) → posten → die in dieser Runde adressierten Threads sofort resolven (`resolve_thread` mit `threadId=PRRT_...`; mit `gh` die Mutation `resolveReviewThread`) → `reviewed_sha` aktualisieren, zurueck zu Phase 2.

## Phase 4: Resolve + Abschluss

[HARD-GATE]
Vor jedem **positiven Abschluss-Verdikt**, ausnahmslos — jeder Punkt muss erfuellt sein.

Zuerst lesen und quittieren: [`reference/gates.md`](reference/gates.md).

1. Laufzeile statt CI-Status: es zaehlt die Laufzeile unter "How tested", die `.agents/rules/pr.md` § "Test Runs" fuer diesen Diff verlangt. Belegt keine
   Zeile den Lauf fuer den Head, **nicht** approven; nur die Gestalt der Zeile ist Form
   (`reference/gates.md` § "Form haelt das Approve nie auf"). Der Reviewer faehrt keinen vollen Lauf, sondern die gefilterten Tests der betroffenen Klassen und Mutationsproben, und nennt sie im Review-Body.
3. Kein CI-Gaming — wurden Tests/Coverage/Trigger manipuliert, um gruen zu werden, **nicht**
   approven, unabhaengig vom CI-Signal.
4. Eigene Threads — Vorbedingung des Schreibens: Review-Kommentare frisch abrufen (`get_review_comments` bzw. `gh api`), die selbst eroeffneten durchgehen, jeden am Head adressierten Punkt jetzt resolven.
5. **Anker-Issue, Auto-Close-Zeile und Tracking Issue — eine Pruefung, am Head.**
   - Existiert das Tracking Issue des Designs und ist es offen? Stehen die in diesem PR zurueckgestellten Punkte im Body des Tracking Issues? Zeigt eine Auto-Close-Zeile auf ein Issue mit Checkliste, in dessen ganzem Body noch ein offener Punkt steht? Gerechnet wird gegen die Zeile, nie gegen ein Vorkommen im Fliesstext.
   - Ergebnis muss null ungetragene Punkte sein, sonst nicht approven.
6. Zwei getrennte Verdikte, beide gruen: **Spec** (tut der Diff genau das Bestellte, nichts zu
   viel/zu wenig?) und **Quality** (handwerklich sauber: Tests, Struktur, keine Magic Numbers?).
7. Behauptet der PR-Body etwas, das der Reviewer nicht im Diff sieht (Testlauf, Benchmark, "verifiziert") ohne stabilen Anker (`.agents/rules/evidence.md`), nicht approven; nur die Schreibweise eines treffenden Ankers ist Form.
[/HARD-GATE]

Wenn sauber (keine neuen Punkte), ohne Freigabe; vor jedem Post laeuft der Review-Head (Phase 1, Schritt 4):

- Im Controller-Modus sofort `APPROVE`, ohne Zusatzrunde. Der Body traegt Kurzfassung, Laeufe, die Zeilen-Datei als `jsonl`-Block mit Dateinamen und die Zeile `Review-Verdict: approve <head-sha>`, die das Verwerfen des Approves ueberlebt. Die
  Zeilen-Datei pusht der Controller allein und direkt vor dem Merge.
- Ohne Controller zuerst Report und Zeilen-Datei als Kommentar-Review; am neuen Head, der nur die Zeilen-Datei hinzufuegt oder bewiesen nur nachzieht (Phase 3, Schritt 1), das `APPROVE` ohne neue Freigabe — sonst Report und Freigabe neu.

Lag der Bericht im Web auf `review/<N>-report`, loescht der Reviewer diesen Branch nach dem Approve
  (`gh api -X DELETE repos/<repo>/git/refs/heads/review/<N>-report`).

Mit dem Verdikt setzt der Skill das Tracking Issue auf `state:gate` und nimmt `state:review` ab (`controller-mode` Schritt 4, dort die Befehle).

## Strikte Regeln

- Das Widget wird, wo ein Mensch im claude.ai-Chat der Adressat ist, inline gerendert (Visualizer/`show_widget`) — in Claude Code und im Controller-Modus gibt es keins.
- Rotation: Art `review` in `.agents/session-kinds.json`; der Stand steht in einem PR-Kommentar, ueberschrieben bei jedem Schnitt.
