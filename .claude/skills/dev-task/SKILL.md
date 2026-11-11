---
name: dev-task
description: 'Dev-Session: /dev-task [repo]#[N] arbeitet die Spec der Design-Runde auf ihrem Branch ab und oeffnet den Draft-PR; /dev-task "[auftrag]" pusht sofort Branch und Draft-PR mit dem Auftrag woertlich. Triggert bei "/dev-task", "dev-task", "setz issue #N um", "arbeite die spec ab". Nur fuer GitHub-Repos.'
metadata:
  version: "2.11.1"
  source: ww3d/playbook
  checksum: "sha256:8b3539921d8436700c318b4507dd5ad738a0c3767f89e0925a1762bc7cec8b6f"
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

## Aufruf

- `/dev-task <owner/repo>#<N>` — Weg A: das Issue traegt den Auftrag; die Design-Runde
  (`ccweb-prompt`) hat Branch, Spec-Datei, Decision-Log und Zeilen-Datei gepusht und im Body
  verlinkt.
- `/dev-task "<auftrag>"` — Weg B: der Auftragstext ist der Auftrag; Ziel-Repo ist das Repo der
  Session, sonst steht `<owner/repo>` davor.

## Schritt 1a: Weg A — Issue

1. Den Issue-Body vollstaendig lesen (`gh api repos/<owner>/<repo>/issues/<N> --jq .body`;
   Connector: `issue_read`). Er verlinkt Branch, Spec-Datei
   `docs/tasks/<N>-<slug>.md`, Decision-Log, Zeilen-Datei und `Review-Mode: <mode>`.
2. Den Branch holen: `git fetch origin && git switch <branch>` (Connector: `get_file_contents` mit
   `ref` auf den Branch).
3. Spec-Datei, Decision-Log und Zeilen-Datei am Head des Branches **vollstaendig** lesen. Die Spec
   ist der Auftrag; bei Widerspruch zu den Docs gilt ihr Lese-Auftrag
   ([`.claude/skills/ccweb-prompt/reference/spec.md`](../ccweb-prompt/reference/spec.md)
   § "Lese-Auftrag").
5. Den Draft-PR frueh von diesem Branch oeffnen (`gh api repos/<owner>/<repo>/pulls -f head=<branch>
   -f base=<basis> -f title=<titel> -F body=@<datei> -F draft=true`; Connector:
   `create_pull_request` mit `draft: true`). Steht von diesem Branch schon ein offener PR, arbeitet
   die Session auf ihm weiter — zuerst eine Zeilen-Datei aus dem Review-Body (im Controller-Modus
   nur die einer Runde mit Funden) und offene Befunde (Schritt 4).
6. Das Tracking Issue auf `state:dev` setzen und `state:design` abnehmen (`controller-mode`
   § "Schritt 4: Steuern", Zustands-Labels, dort die Befehle).

## Schritt 1b: Weg B — Auftragstext

Weg B braucht einen Checkout: den leeren Start-Commit kann nur `git` pushen.

1. Branch nach `.agents/rules/pr.md` § "Branch Naming" anlegen.
2. Leerer Start-Commit (`git commit --allow-empty`), **sofort** pushen (`git push -u origin
   <branch>`) und den Draft-PR oeffnen (REST-Form aus Schritt 1a Punkt 5; Connector:
   `create_pull_request` mit `draft: true`). Der Auftrag steht **woertlich**
   im PR-Body, als Zitat unter **What** — ungekuerzt, unveraendert.
3. Traegt der Auftrag eine nummerierte Liste: jetzt die Spec-Datei nach `.agents/rules/pr.md`
   § "Task Spec" (Form: `.claude/skills/ccweb-prompt/reference/spec.md`) committen und pushen; der Body verlinkt sie. Nennt der Auftragstext ein Issue, ist
   es der Anker: `docs/tasks/<issue>-<slug>.md`, im Body `Refs #<issue>`. Nur ohne Issue ist der PR
   der Anker: `docs/tasks/pr-<N>-<slug>.md` mit der PR-Nummer.
4. Nennt der Auftragstext kein Issue, entsteht eines, sobald ein Punkt offen bleibt, der einen
   Traeger braucht (`.agents/rules/carrier.md` § "Carrier Requirement"); nennt er eines, steht
   der Punkt in dessen Body.

## Schritt 2: Bauen

- Den PR abonnieren, wo `subscribe_pr_activity` vorhanden ist: ein deferred MCP-Tool, laden mit
  `select:mcp__github__subscribe_pr_activity`; `gh pr create` abonniert nicht.
- Stand frueh und oft pushen; vor jedem geplanten Ende alles gepusht, WIP auf dem Branch.
- Review-Wellen nach dem Modus der Spec: den Baustein
  [`pr-poll-review/reference/review-modes.md`](../pr-poll-review/reference/review-modes.md) lesen,
  bevor die erste Welle laeuft; der Wellen-Bericht geht in den PR-Body.

## Schritt 4: Ende

**Das Ende ist der PR und seine Abgabe**: zuerst ein Durchgang allein ueber den ganzen Diff, jedes
REQ per `git grep` am Head belegt — gesucht wird der Code, den es verlangt, nicht seine Nummer; dann
der volle Lauf, Push, `pwsh scripts/common/test-pr-form.ps1 -Repo <owner/repo> -Pr <n>` gruen
(Verzicht nur mit `-Waive "<Grund>"` und der Zeile `Form check waived: <Grund>` unter `## Design`
des Tracking Issues), Draft → ready, Reviewer setzen (`gh api
repos/<owner>/<repo>/pulls/<n>/requested_reviewers -f "reviewers[]=<konto>"` je Konto), Laufzeilen
im Body; dann die Abgabe an den Besitzer, im Controller-Modus `#N Head <sha> bereit`. Beim Schritt auf
ready setzt die Session das Tracking Issue auf `state:review` und nimmt `state:dev` ab, wie in
Schritt 1a Punkt 6. Weg B ohne Tracking Issue setzt kein Label.

Eine blockierende Frage steht in der Kurzform aus `ccweb-prompt` § "Schritt 1: Design-Runde und
Tracking Issue" (Absatz "Staffel": Worum / Empfehlung / Verworfen mit Grund), Empfehlung vorbelegt,
vorgelegt nach `.agents/rules/chat.md` § "Talking to the Maintainer" (letzter Punkt); "stuck" mit
einem Satz, woran.

**Approve mit Vorschlaegen:** kommt das Approve (oder die Zeile `Review-Verdict: approve <sha>`) mit
offenen `suggestion`-Blocks, spielt die Session sie nach `.agents/rules/pr.md` § "Controller Mode"
ein, testet, pusht, resolvt die Threads der eingespielten und der abgelehnten Vorschlaege (der
Ruleset verlangt geloeste Threads) und meldet `#N Head <sha> bereit` — im Controller-Modus an den
Controller.

**Block "Form, blockt nie":** steht er im Review, zieht die Session seine Punkte vor dem Merge nach
und faehrt das Form-Skript.

Auf `#N Review zu <sha> steht` stellt sie den PR auf Entwurf, fixt alles — je `issue:` fuehrt sie
dessen Suche selbst am Head aus und behebt jeden Treffer der Fehlerart, nicht nur die genannten
Zeilen; einen vorgegebenen Fix-Text prueft sie am Code, statt ihn abzuschreiben —, testet nach den
Regeln fuer Korrekturrunden, pusht, faehrt das Form-Skript, stellt ihn wieder bereit und schickt dem
Reviewer ohne Antwort `#N Head <sha> bereit`. Die Zeilen-Datei einer Review-Runde committet sie mit
dem naechsten Push (Name und Commit-Form: `.claude/skills/pr-poll-review/reference/report.md` §
"Zeilen-Datei der Runde"); im Controller-Modus pusht die einer sauberen Runde der Controller — nach
deren Approve pusht die Session nichts mehr.

## Strikte Regeln

- Nie einen anderen Branch als den des Issues bzw. den eigenen benutzen.
- Der Text eines Weckers (`ScheduleWakeup`, `/loop`) nennt den Schritt, auf den gewartet wird, und
  was danach zu tun ist, nie die Startzeile des Skills; ein Hintergrund-Lauf meldet sein Ende
  selbst, der Wecker ist nur Rueckfall.
