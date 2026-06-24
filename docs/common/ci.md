# CI / GitHub Actions

Pipeline für ww3d-Projekte. Stack-Snippets in der jeweiligen Overlay-Doku
(z. B. [`dotnet.md`](./dotnet.md)).

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

Die CI-Job- und damit Check-Namen sind playbook-weit kanonisch, **nicht** pro Repo frei gewählt.
Neue Repos übernehmen das Stack-Snippet (Overlay-Doku bzw. `templates/`) unverändert, sodass die
Matrix exakt die kanonischen Namen erzeugt — nur so bleiben die Required-Status-Checks stack-weit
per identischem Namen setzbar.

- **dotnet:** `build-test (ubuntu-latest)`, `build-test (windows-latest)` als Pflicht-Kern.
  Repo-spezifische Zusatz-Jobs (`build-test-mssql`, `docker-integration (ubuntu-latest)`, `pack`)
  bleiben **außerhalb** des Required-Sets.
- **powershell:** `PowerShell (windows-latest / powershell)`, `PowerShell (windows-latest / pwsh)`,
  `PowerShell (ubuntu-latest / pwsh)`. Ein Windows-only-Repo ohne Linux-Job trägt entsprechend nur
  die zwei `windows-latest`-Checks — im selben Namensschema, kein eigener Name.

Required wird pro Repo die **Teilmenge** dieser Namen, die das Repo tatsächlich fährt — nie ein
abweichend benannter Job. Ein neu gewählter Job-Name (z. B. `linux`/`windows` statt
`build-test (<os>)`) ist ein Konventionsbruch und blockiert die einheitliche Ruleset-Pflege.

## Format-Check

Eigener `format`-Step (z. B. `dotnet format --verify-no-changes`), der vor `build` läuft. Nur in
einer Matrix-Variante (typisch Linux), Format-Regeln sind plattform-unabhängig.

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
  Fünf-Sections-Description landet damit im `main`-Commit-Body.
- **Allow auto-merge** aktiviert — der Sync-Workflow armt Auto-Merge auf ready-PRs; ohne dieses
  Setting bleibt der ready-PR offen und braucht einen manuellen Merge.
- **Always suggest updating pull request branches** aktiviert.
- **Automatically delete head branches** aktiviert.
- **Default-Branch:** `main`.

## Ruleset für `main`

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
| Bypass-Liste | Admin-Rolle (`always`) |

Keine lineare-History-Pflicht — neben Squash ist auch ein Merge-Commit erlaubt. Die Admin-Rolle
steht auf der Bypass-Liste, damit ein Admin im Notfall einen Hotfix landen kann.

Pro Repo die passende Teilmenge der kanonischen Check-Namen nachtragen — siehe "Kanonische
Check-Namen" oben und
[`templates/github-rulesets/README.md`](https://github.com/ww3d/playbook/blob/main/templates/github-rulesets/README.md).
