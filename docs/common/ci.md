# CI / GitHub Actions

Pipeline fuer ww3d-Projekte. Stack-Snippets in der Overlay-Doku des Stacks
(`docs/common/<stack>.md`, Auswahl je Stack: `docs/common/README.md`).

## Pipeline

- Trigger: Push auf `main` und auf jeden PR.
- Matrix: `ubuntu-latest` + `windows-latest`, sofern beide Plattformen relevant.
- Schritte: Checkout → Toolchain mit Caching → Restore → Build → (optional) Format-Check →
  Test → Test-Reporter.
- Pack-Artefakte nur auf `main`, nicht auf PRs.
- Required Checks: die kanonisch benannten Build/Test-Matrix-Jobs (siehe "Canonical Check Names").

## Workflow-Aufbau

Zwei Jobs in `.github/workflows/ci.yml`:

1. **`build-test`** — jeder Trigger, Matrix Linux+Windows. Required Check.
2. **`pack`** — nur auf `main`, `needs: build-test`. Kein Required Check.

Ein File, nicht mehrere — Triggers, Permissions und Concurrency-Group werden sonst dupliziert.

## Canonical Check Names

Die CI-Job- und damit Check-Namen sind playbook-weit kanonisch, **nicht** pro Repo frei gewaehlt.
Neue Repos uebernehmen das Stack-Snippet (Overlay-Doku bzw. `templates/`) unveraendert, sodass die
Matrix exakt die kanonischen Namen erzeugt — nur so bleiben die Required-Status-Checks stack-weit
per identischem Namen setzbar.

- **dotnet:** `build-test (ubuntu-latest)`, `build-test (windows-latest)` als Pflicht-Kern.
  Repo-spezifische Zusatz-Jobs (`build-test-mssql`, `docker-integration (ubuntu-latest)`, `pack`)
  bleiben **ausserhalb** des Required-Sets.
- **powershell:** `PowerShell (windows-latest / powershell)`, `PowerShell (windows-latest / pwsh)`,
  `PowerShell (ubuntu-latest / pwsh)`. Ein Windows-only-Repo ohne Linux-Job traegt entsprechend nur
  die zwei `windows-latest`-Checks — im selben Namensschema, kein eigener Name.
- **rust:** `build-test (ubuntu-latest)`, `build-test (windows-latest)` — dasselbe Schema wie
  dotnet, Teilmenge je nach den Plattformen des Repos.
- **typescript:** `build-test (ubuntu-latest)` — Chrome-Extensions laufen im Default nur auf
  `ubuntu-latest`; ein Repo mit einer zweiten Plattform traegt den entsprechenden zusaetzlichen
  Namen im selben Schema.
- **javascript:** `build-test (ubuntu-latest)` — dasselbe Schema, fuer die JS/TS-Familie ohne
  eigenen Typ-Level (`tech/common/typescript.md` deckt beide Stacks ab);
  VS-Code-Extensions laufen im Default ebenfalls nur auf `ubuntu-latest`.

Required wird pro Repo die **Teilmenge** dieser Namen, die das Repo tatsaechlich faehrt — nie ein
abweichend benannter Job. Ein neu gewaehlter Job-Name (z. B. `linux`/`windows` statt
`build-test (<os>)`) ist ein Konventionsbruch und blockiert die einheitliche Ruleset-Pflege.
Plattform-Teilmengen (ein Repo faehrt legitim nicht jede Plattform seines Stacks) laufen ueber das
Manifest-Feld `platforms`, dokumentiert im Playbook, nicht ueber einen eigenen Job-Namen.

## Build-Verzeichnis je Stack

| Stack | Ziel | Heutiges Ist |
|---|---|---|
| powershell | Layout offen | `_build/<Module>/` |
| dotnet | `artifacts/{bin,obj,packages,log,TestResults}` (arcade) | bereits Ist |
| rust | `artifacts/{bin,obj,packages,log,TestResults}` (arcade) | `target/` (Cargo-Default) |
| typescript | Layout offen | WXT: `.output/` |
| javascript | Layout offen | Bundler (z. B. `tsdown`): `dist/` |

Das arcade-Layout (`RepoLayout.props` des Build-SDKs der Org) ist fuer keinen der vier
Nicht-.NET-Stacks bereits Ist; WXT und Cargo legen ihr Verzeichnis tool-nativ an und gitignoren es.
Bis ein Build fuer den jeweiligen Stack ein festgelegtes Layout uebernimmt, bleibt das tool-native
Verzeichnis (`target/`, `.output/`, `dist/`) der reale Build-Ort. Ob ein `typescript`- oder
`javascript`-Consumer eine Chrome-Extension oder eine VS-Code-VSIX baut, entscheidet das Repo, nicht
der Stack.

## Testlaeufe

Solange die Org-CI nicht produktiv laeuft (unten), tragen die lokalen Laeufe des Autors die
Pruefung. Wann welcher Lauf faellig ist — voll, gefiltert oder nur Format —, die Laufzeile unter
"How tested" und die Zeitvorgabe stehen in `.agents/rules/pr.md` § "Test Runs". Was der volle Lauf
eines Repos ist (Befehl, Plattformen) und welche Guard classes es hat, nennt seine `CLAUDE.md`.

## Testordner je Stack

Die Regel (Temp-Ordner im Ausgabe-Ordner des Baus, Aufraeumen, kurzer Pfad fuer Sockets) steht in
`.agents/rules/code.md` § "Test Isolation". Der Test-Einstieg entfernt beim Start nur die Ordner
frueherer Laeufe, die kein laufender Prozess mehr haelt. Die Tabelle nennt je Stack, was der
Umlenkung folgt, und die benannten Ausnahmen — Orte, die ein Werkzeug fest ins Repo legt, und
Toolchain-Caches, die das Wiederherstellen der Pakete schreibt, nicht der Test.

| Stack | Folgt der Umlenkung | Benannte Ausnahmen |
|---|---|---|
| dotnet | `Path.GetTempPath()` | `~/.nuget` (Paket-Cache) |
| rust | `std::env::temp_dir()`, `tempfile` | `target/tmp` (`CARGO_TARGET_TMPDIR`, im Repo); `~/.cargo`, `~/.rustup` |
| powershell | Pesters `TestDrive:` | — |
| typescript | `os.tmpdir()`, vitest | `.vscode-test/` (im Repo); npm-/pnpm-Cache |
| javascript | `os.tmpdir()` | npm-/pnpm-Cache |
| zig | — | `.zig-cache/tmp` (`std.testing.tmpDir`, im Repo) |

Was die Umlenkung nicht faengt — `%LOCALAPPDATA%` ueber `GetFolderPath`, Registry (auch Pesters
`TestRegistry:`), Laufwerksbuchstaben, geplante Aufgaben —, bleibt ohne Ausnahme verboten. Ein Repo,
dessen `.gitignore` `artifacts/` nicht deckt, traegt es nach.

## Format-Check

Eigener `format`-Step (z. B. `dotnet format --verify-no-changes`), der vor `build` laeuft. Nur in
einer Matrix-Variante (typisch Linux), Format-Regeln sind plattform-unabhaengig.

## Permissions

Explizit auf Workflow- oder Job-Ebene. Kein `write-all`. Typisches Set: `contents: read`,
`checks: write`, `pull-requests: write` (der YAML-Block steht im Stack-Snippet der Overlay-Doku).
Breitere Permissions nur auf dem einen betroffenen Job, nicht workflow-weit.

## Concurrency

Die Gruppe je Workflow und Ref (`${{ github.workflow }}-${{ github.ref }}`) mit
`cancel-in-progress: true`; der YAML-Block steht im Stack-Snippet der Overlay-Doku.

## Repo-Settings

- **Merge-Methoden** in den Repo-Settings genau die, die das Ruleset erlaubt (§ "Ruleset fuer
  `main`", Zeile "Erlaubte Merge-Methoden"), **jede** mit Default-Commit-Message "Pull request
  title and description" — die deutsche Fuenf-Sections-Description landet damit im
  `main`-Commit-Body.
- **Allow auto-merge** aktiviert — das Sync-Werkzeug armt Auto-Merge auf ready-PRs; ohne dieses
  Setting bleibt der ready-PR offen und braucht einen manuellen Merge.
- **Always suggest updating pull request branches** aktiviert.
- **Automatically delete head branches** aktiviert.
- **Default-Branch:** `main`.

## CI gilt org-weit als tot, bis die Org-CI produktiv laeuft

Die Regel steht in `.agents/rules/pr.md` § "CI Counts as Dead Org-Wide"; wann ein PR ready wird
(nach dem ersten vollen Lauf, der gruen ist, ohne auf Checks zu warten): § "PR Lifecycle" ebenda.
Das Ergebnis der lokalen Laeufe steht im PR-Body unter "How tested".

## Ruleset fuer `main`

| Regel | Wert |
|---|---|
| Restrict deletions | aktiviert |
| Block force pushes | aktiviert |
| Require pull request | aktiviert |
| Require approvals | 1 |
| Dismiss stale approvals on push | aktiviert |
| Require conversation resolution | aktiviert |
| Require status checks to pass | aktiviert (kanonische Namen, Teilmenge pro Repo) |
| Require last push approval | aktiviert |
| Require branches up to date | aktiviert |
| Do not enforce on create | aktiviert |
| Erlaubte Merge-Methoden | `squash` + `merge` |
| Bypass-Liste | Admin-Rolle (`always`), Write-Rolle (`pull_request`) |

Keine lineare-History-Pflicht. Die Admin-Rolle
steht auf der Bypass-Liste, damit ein Admin im Notfall einen Hotfix landen kann. Die Write-Rolle
steht zusaetzlich darauf, damit die Bot-Accounts (`ww3-claude-bot`, `ww3-claude`, beide Rolle
`write`) ihre Sync- und Bot-PRs auch bei toter Consumer-CI mergen koennen. `pull_request` laesst
die Rolle Regeln nur an Pull Requests uebergehen (GitHub-REST-Referenz: "an actor can only bypass
rules on pull requests"); Loeschen und Force-Push auf `main` sind keine Pull Requests und bleiben
fuer sie gesperrt.

Pro Repo die Teilmenge nachtragen:
[`templates/github-rulesets/README.md`](https://github.com/ww3d/playbook/blob/main/templates/github-rulesets/README.md).
