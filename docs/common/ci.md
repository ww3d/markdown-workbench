# CI / GitHub Actions

## Pipeline

- Was die CI baut, baut auch lokal, mit denselben Befehlen — kein Schritt, der nur in der CI geht;
  ein Test, der in der CI rot ist, ist lokal nachstellbar.

## Canonical Check Names

Die CI-Job- und damit Check-Namen sind playbook-weit kanonisch, **nicht** pro Repo frei gewaehlt.
Neue Repos uebernehmen das Stack-Snippet (Overlay-Doku bzw. `templates/`) unveraendert, sodass die
Matrix exakt die kanonischen Namen erzeugt.

- **dotnet:** `build-test (ubuntu-latest)`, `build-test (windows-latest)` als Pflicht-Kern.
- **powershell:** `PowerShell (windows-latest / pwsh)`, `PowerShell (ubuntu-latest / pwsh)`.
- **rust:** `build-test (ubuntu-latest)`, `build-test (windows-latest)`.
- **typescript:** `build-test (ubuntu-latest)`.
- **javascript:** `build-test (ubuntu-latest)`.

## Testlaeufe

Eine Web- oder Cloud-Session mit aelterer vorinstallierter pwsh installiert 7.6 vor dem Lauf, und
die Laufzeile nennt die Version.

## Testordner je Stack

| Stack | Folgt der Umlenkung | Benannte Ausnahmen |
|---|---|---|
| dotnet | `Path.GetTempPath()` | `~/.nuget` (Paket-Cache) |
| rust | `std::env::temp_dir()`, `tempfile` | `target/tmp` (`CARGO_TARGET_TMPDIR`, im Repo); `~/.cargo`, `~/.rustup` |
| powershell | Pesters `TestDrive:` | — |
| typescript | `os.tmpdir()`, vitest | `.vscode-test/` (im Repo); npm-/pnpm-Cache |
| javascript | `os.tmpdir()` | npm-/pnpm-Cache |

## Format-Check

Eigener `format`-Step (z. B. `dotnet format --verify-no-changes`), der vor `build` laeuft. Nur in
einer Matrix-Variante (typisch Linux).
