# CI / GitHub Actions

Pipeline fuer ww3d-Projekte. Stack-Snippets in der jeweiligen Overlay-Doku, dem einzigen
`docs/common/<stack>.md`, den ein Consumer fuer seinen eigenen Stack erhaelt (z. B. `dotnet.md`
fuer .NET-Consumer, `powershell.md` fuer PowerShell-Consumer — nicht beide).

## Pipeline

- Trigger: Push auf `main` und auf jeden PR.
- Matrix: `ubuntu-latest` + `windows-latest`, sofern beide Plattformen relevant.
- Schritte: Checkout → Toolchain mit Caching → Restore → Build → (optional) Format-Check →
  Test → Test-Reporter.
- Pack-Artefakte nur auf `main`, nicht auf PRs.
- Required Checks: die kanonisch benannten Build/Test-Matrix-Jobs (siehe "Kanonische Check-Namen").

## Workflow-Aufbau

Zwei Jobs in `.github/workflows/ci.yml`:

1. **`build-test`** — jeder Trigger, Matrix Linux+Windows. Required Check.
2. **`pack`** — nur auf `main`, `needs: build-test`. Kein Required Check.

Ein File, nicht mehrere — Triggers, Permissions und Concurrency-Group werden sonst dupliziert.

## Kanonische Check-Namen

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
- **typescript:** `build-test (ubuntu-latest)` — Chrome-Extensions laufen heute ausschliesslich auf
  `ubuntu-latest`; ein Repo mit einer zweiten Plattform traegt den entsprechenden zusaetzlichen
  Namen im selben Schema.
- **javascript:** `build-test (ubuntu-latest)` — dasselbe Schema, fuer die JS/TS-Familie ohne
  eigenen Typ-Level (`tech/common/typescript.md` deckt beide Stacks ab, ww3d/playbook#111);
  VS-Code-Extensions laufen heute ebenfalls ausschliesslich auf `ubuntu-latest`.

Required wird pro Repo die **Teilmenge** dieser Namen, die das Repo tatsaechlich faehrt — nie ein
abweichend benannter Job. Ein neu gewaehlter Job-Name (z. B. `linux`/`windows` statt
`build-test (<os>)`) ist ein Konventionsbruch und blockiert die einheitliche Ruleset-Pflege.
Plattform-Teilmengen (ein Repo faehrt legitim nicht jede Plattform seines Stacks) laufen ueber das
Manifest-Feld `platforms`, dokumentiert im Playbook, nicht ueber einen eigenen Job-Namen.

## Build-Verzeichnis je Stack

| Stack | Ziel (arcade, `ww3d/atlas`) | Heutiges Ist |
|---|---|---|
| powershell | eigenes SDK geplant (Muster `Atlas.Sdk.<Stack>`), Layout offen | `_build/<Module>/` |
| dotnet | `artifacts/{bin,obj,packages,log,TestResults}` | bereits Ist |
| rust | `artifacts/{bin,obj,packages,log,TestResults}` (kein eigenes SDK geplant, laeuft unter native/win-util mit) | `target/` (Cargo-Default) |
| typescript | Chrome-Extensions- bzw. VS-Code-VSIX-SDK geplant (Muster `Atlas.Sdk.<Stack>`, je nach Artefakt des Consumers), Layout offen | WXT: `.output/` |
| javascript | Chrome-Extensions- bzw. VS-Code-VSIX-SDK geplant (Muster `Atlas.Sdk.<Stack>`, je nach Artefakt des Consumers), Layout offen | Bundler (z. B. `tsdown`): `dist/` |

Das arcade-Layout ist fuer keinen der vier Nicht-.NET-Stacks bereits Ist. Laut
`ww3d/atlas docs/architecture-baseline.md` plant atlas eigene SDKs nach dem Muster
`Atlas.Sdk.<Stack>` fuer PowerShell, AutoHotkey, VS-Code-VSIX und Chrome-Extensions — konkrete Namen
nennt atlas nicht, nur das Muster und die Stack-Liste; der Baum kennt bislang nur
`DotNet.Atlas.Sdk*`. Atlas schneidet dabei nach **Artefakt** (Chrome-Extension, VS-Code-VSIX), nicht
nach Sprache — eine TypeScript-VS-Code-Extension waere ebenso VSIX wie eine JavaScript-Extension;
welches Artefakt ein `typescript`- oder `javascript`-Consumer baut, ist Repo-Sache, keine feste
Zuordnung ueber den Stack. Nur fuer Rust steht ausdruecklich **kein** eigenes SDK im Plan (laeuft
unter dem native/win-util-Build-Pfad mit). Ob die geplanten SDKs das `artifacts/`-Layout
uebernehmen, ist dort nicht festgelegt; das Wort "TypeScript" fehlt in atlas, der Stack nicht. Bis
ein `atlas.sdk`-Build fuer den jeweiligen Stack existiert, bleibt das tool-native Verzeichnis
(`target/`, `.output/`, `dist/`) der reale Build-Ort.

## Format-Check

Eigener `format`-Step (z. B. `dotnet format --verify-no-changes`), der vor `build` laeuft. Nur in
einer Matrix-Variante (typisch Linux), Format-Regeln sind plattform-unabhaengig.

## Permissions

Explizit auf Workflow- oder Job-Ebene. Kein `write-all`. Typisches Set:

```yaml
permissions:
  contents: read
  checks: write
  pull-requests: write
```

Breitere Permissions nur auf dem einen betroffenen Job, nicht workflow-weit.

## Concurrency

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Repo-Settings

- **Squash-Merge** und **Merge-Commit** als erlaubte Merge-Methoden (kein Rebase-Merge), passend zum
  Ruleset. **Beide** mit Default-Commit-Message "Pull request title and description" — die deutsche
  Fuenf-Sections-Description landet damit im `main`-Commit-Body.
- **Allow auto-merge** aktiviert — der Sync-Workflow armt Auto-Merge auf ready-PRs; ohne dieses
  Setting bleibt der ready-PR offen und braucht einen manuellen Merge.
- **Always suggest updating pull request branches** aktiviert.
- **Automatically delete head branches** aktiviert.
- **Default-Branch:** `main`.

## CI gilt org-weit als tot, bis `iris.ci` produktiv laeuft

Eine registrierte CI, deren Jobs in ein bis zwei Sekunden ohne einen einzigen Schritt enden, zaehlt
wie **keine registrierte CI**: kein Review-Signal, kein Approve-Blocker, kein Befund im Review — der
PR wird sofort ready geflippt. Nachweis kommt stattdessen aus lokalen Laeufen (Build, Test, ein
gebuendeltes Check-Skript, wo vorhanden), belegt im PR-Body unter "Wie getestet". **Ausnahme:** ein Repo
mit self-hosted Runner — dort zaehlt CI wie gewohnt, weil dort keine unerreichbaren gehosteten
Minuten im Weg stehen. Der Zustand endet, sobald `iris.ci` produktiv laeuft; Traeger fuer das Ende
ist eine Zeile im `backlog.md` des Playbooks. Regeltext und Lifecycle-Einordnung:
`.agents/rules/pr.md` § "PR Lifecycle", Unterabschnitt "CI Counts as Dead Org-Wide".

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

Keine lineare-History-Pflicht — neben Squash ist auch ein Merge-Commit erlaubt. Die Admin-Rolle
steht auf der Bypass-Liste, damit ein Admin im Notfall einen Hotfix landen kann. Die Write-Rolle
steht zusaetzlich darauf, damit die Bot-Accounts (`ww3-claude-bot`, `ww3-claude`, beide Rolle
`write`) ihre Sync- und Bot-PRs auch bei toter Consumer-CI mergen koennen. `pull_request` laesst
die Rolle Regeln nur an Pull Requests uebergehen (GitHub-REST-Referenz: "an actor can only bypass
rules on pull requests"); Loeschen und Force-Push auf `main` sind keine Pull Requests und bleiben
fuer sie gesperrt.

Pro Repo die passende Teilmenge der kanonischen Check-Namen nachtragen — siehe "Kanonische
Check-Namen" oben und
[`templates/github-rulesets/README.md`](https://github.com/ww3d/playbook/blob/main/templates/github-rulesets/README.md).
