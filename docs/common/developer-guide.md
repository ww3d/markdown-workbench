# Developer Guide — ww3d Playbook

Praktische Anleitung für die Mitarbeit an einem ww3d-Projekt. Stack-Spezifika in den Overlays
(z. B. [`dotnet.md`](./dotnet.md), [`powershell.md`](./powershell.md)). Agent-Regeln in
[`AGENTS.md`](https://github.com/ww3d/playbook/blob/main/AGENTS.md) und in den Tech-Overlays unter
`tech/common/`.

## Conventional Commits

Format:

```
<type>(<scope>): <kurze beschreibung>

<body, optional, erklärt das Warum>

<footer, optional, z. B. "Closes #42">
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `chore`. Im
Zweifel: `chore`.

Title-Regeln: imperativ, lowercase nach dem Type-Doppelpunkt, kein Punkt am Ende, max ~72 Zeichen,
Englisch. Body erklärt das Warum, in vollen Sätzen.

Breaking Changes: `!` nach dem Scope (`feat(core)!: ...`).

## Branches

Format `<type>/<short-topic>`, lowercase, Bindestriche, Englisch, keine Umlaute. Beispiele:
`phase2/auth-handshake`, `fix/path-normalization`, `docs/runner-readme`.

Lifecycle: `main` aktuell holen → Branch anlegen → Commits → Push → Draft-PR → Review →
Squash-Merge durch Maintainer → Branch wird automatisch gelöscht.

Atomare Commits: ein Commit = eine Aussage. Lieber viele kleine als einen großen.

## PR / MR

Titel: Conventional-Commit-Stil, Englisch.

Beschreibung: Deutsch, mit fünf Pflicht-Headings in dieser Reihenfolge:

1. **Was**
2. **Was bewusst nicht geändert wurde**
3. **Entscheidungen**
4. **Wie getestet**
5. **Offene Fragen**

Auto-Close-Footer am Ende des Bodys, Englisch (deutsche Varianten triggern den GitHub-Auto-Close
nicht). Mehrere Issues: Keyword pro Issue wiederholen (`Closes #1, closes #2`) oder Listen-Form mit
eigenem Keyword je Eintrag. Komma-Listen ohne Wiederholung schließen nur das erste Issue.

Reviewer: `ww3-claude` und `ww3d`. Squash-Merge ist Default; PR-Description landet via Repo-Setting
im `main`-Commit-Body.

PR-Lifecycle-Mechanik (Drei Rollen, 12 Schritte): siehe `AGENTS.md` § "PR lifecycle".

## Code-Conventions

Detail in `AGENTS.md` und im Tech-Overlay. Übergreifend:

- Nullables überall an, sofern die Sprache das unterstützt.
- Async für alle I/O.
- Records für Werte, Klassen mit Identität für Entitäten.
- Guard Clauses am Anfang, Happy Path danach.
- UTC-Zeitstempel für gespeicherte Daten.
- Cancellation auf allen async Library-APIs.

## Tests

Public APIs in Library-Projekten bekommen Unit-Tests. Auch Fehlerpfade, Concurrency,
Persistenz-Edge-Cases. Trivial-Getter und DI-Verkabelung werden nicht getestet.

Test-Naming: `MethodName_Scenario_ExpectedResult` oder beschreibende Sätze.

Plattform-spezifische Tests werden auf der falschen Plattform mit Skip übersprungen, nicht
ausgelassen oder mit alternativem Verhalten ersetzt.

Vor jedem Commit: lokaler Build und Tests grün.

## CI

GitHub Actions auf Push und Pull Request, Matrix Linux + Windows. Details in [`ci.md`](./ci.md).

## Doku-Stil

Jede Doku-Änderung hält die Docs knapp, klar, sachlich: Redundanz und Füllsätze raus, kein Wissens-
oder Klarheitsverlust. Lieber knapp und eindeutig als ausführlich.

Alle `.md`-Files im Repo wrappen Text-Zeilen bei ~100 Spalten (Soft-Wrap). Code-Blöcke, Tabellen
und Links bleiben unangetastet, auch wenn länger.

## Architektur-Doku

`docs/`-Layout im Konsumenten-Repo:

- `docs/common/*.md` — 1:1-Mirror aus `ww3d/playbook` (synct, lokale Edits werden überschrieben).
- `docs/<file>.md` (`developer-guide.md`, `ci.md`, `dotnet.md`, `powershell.md`) — optionale
  Wrapper für projekt-spezifische Overrides.
- `docs/<architecture-baseline>.md`, `docs/<roadmap>.md`, `docs/<konzept>.md` — konsumenten-eigen,
  alle drei nur anlegen, wenn das Repo sie wirklich braucht.

Konkretes Set pro Repo: in der `CLAUDE.md` § "Project Context".

## Synchronisation aus dem Playbook

Sync-Set: `AGENTS.md` plus die Dateien unter `docs/common/` und `tech/common/`, **stack-gefiltert**.
Stack-neutrale Files (`ci.md`, `developer-guide.md`, die `README.md`s …) gehen an jeden Konsumenten;
die `<stack>.md`-Overlays (`dotnet.md`, `powershell.md` …) nur an Repos mit passendem `stack` im
`consumers/<name>.yml`. Adoption ergibt sich zusätzlich aus dem `@`-Import in der
Konsumenten-`CLAUDE.md`. Zusätzlich mirrort der Sync generische `.claude`-Files
(`.claude/hooks/read-confirm.sh`, `.claude/commands/read-check.md`) und die teilbaren Skills unter
`.claude/skills/` — jedes Skill-Verzeichnis außer dem Playbook-internen `playbook-onboard/` und der
`README.md`. `templates/*` und übrige `.claude`-Files (`settings.json`, `session-start.sh`) sind
nicht Teil des Sync.

Mechanik: automatisch via `.github/workflows/sync-consumers.yml` auf jedem Push auf `main`. Der
Workflow wählt das Set pro Stack mit `.github/scripts/select-sync-files.sh` (Stack-Enum aus
`consumers/schema/consumer.schema.json`), öffnet pro driftendem Konsumenten einen Draft-PR und
löscht dort Files, die nicht (mehr) ins Stack-Set gehören.

Consumer mit eigenem Format- oder Lint-Gate (prettier, ESLint, StyleCop o. ä.) müssen die gesyncten
Pfade (`AGENTS.md`, `.claude/`, `docs/common/`, `tech/common/`, `.playbook-version`) von diesem Gate
ausnehmen — es sind byte-identische Mirror-Artefakte, die lokal nie umformatiert werden dürfen,
sonst bricht die nächste Sync-Welle am Format-Check (z. B. via `.prettierignore`). Beim Onboarding
eines solchen Repos gehört der Ausschluss gleich mit angelegt.

### Override-Semantik in Wrappers

`@`-Imports werden nebeneinander geladen, ohne formale Override-Reihenfolge. Wrapper-Regeln, die ein
Common ersetzen oder erweitern, müssen das im Bullet textlich markieren:

- `*(overrides the baseline)*`
- `*(addition to the baseline)*`

Ohne Marker ist der Konflikt nicht-deterministisch.

## Playbook-Versionierung

Das Playbook trägt eine zentrale Version nach **SemVer 2.0.0**, gehalten in einer einzigen Datei
`/VERSION` im Playbook-Root (nackte Versionszeile, kein Header). Ein Sync = ein Stand = eine
Version. Die Sync-Action schreibt den jeweils aktuellen Wert als `.playbook-version` in jeden
Konsumenten-Root, damit die Read-Confirmation (siehe `AGENTS.md` § "Session Receipt") die Version
melden kann. Die einzelnen gesyncten Files bleiben bewusst header-frei.

Bump-Regel — "Conventions als API", aus Sicht der Konsumenten:

- **MAJOR** — Breaking für Konsumenten: eine Regel wird verschärft oder entfernt und kann
  bestehenden Code oder offene PRs brechen (z. B. CS1591 von Warning auf Error, neues
  Pflicht-Gate).
- **MINOR** — additiv, bricht nichts: neue Regel, neues Overlay, neue Always-Zeile (Beispiel:
  PR #75, Forge-CLIs).
- **PATCH** — Klarstellung, Wording oder Typo ohne inhaltliche Änderung.

Jeder inhaltliche Playbook-PR zieht `/VERSION` passend hoch.

## Issue-Tracking

GitHub-Issues sind Single Source of Truth für offene Punkte außerhalb von Roadmap und Code.
Sprache: Deutsch für Inhalt, Englisch für Titel.

Labels — pro Issue ggf. mehrere:

- **Art:** `deferred`, `tech-debt`, `design-question`, `bug`, `enhancement`
- **Phase:** `phase-1`, `phase-2.a`, … — Granularität pro Projekt
- **Bereich:** repo-spezifisch (typisch `core`, `service`, `runner`, `host`, `api`, `web`,
  `testing`, `docs`, `ci`, `infrastructure`)

Empfohlene Struktur:

- **Kontext** — wo ist das Problem, wie ist es entstanden
- **Varianten** (bei Design-Fragen) — mit Pro/Contra
- **Empfehlung** — Vorschlag des Autors
- **Zeitpunkt** — wann die Umsetzung dran ist
- **Referenz** — Verweise auf Code, Docs, verwandte Issues / PRs

Issue anlegen für: aufgeschobene Entscheidungen, Tech-Debt für später, Design-Fragen,
Beobachtungen aus Reviews außerhalb des aktuellen MR-Scopes. Direkt im Code lösen: was im
aktuellen Scope unter ~15 Minuten erledigt ist, offensichtliche Bugs während der Arbeit, Cleanup
ohne Aufblähen des Diffs. Im Zweifel: Issue.

## Coding-Workflow mit Agent

Greift für Code-Änderungen — Features, Fixes, Tests, Refactorings. Reine Doku-, Issue- und
PR-Kommentar-Pflege macht `cweb` selbst direkt via `gh`, ohne Coding-Agent (auch das geht über
PR, weil das Ruleset Direkt-Push auf `main` blockt).

PR-Lifecycle-Mechanik (Draft, CI-Fix-Loop, Review, Merge): `AGENTS.md` § "PR lifecycle". Im
Coding-Workflow füllt ein Coding-Agent die `dev`-Rolle, `cweb` oder `ww3d` die `reviewer`-Rolle,
`ww3d` alleinig die `maintainer`-Rolle.

Drei Workflow-spezifische Punkte, die die Sequenz nicht festschreibt:

**Prompt-Struktur (Schritt 1).** `cweb` schreibt einen Aufgaben-Prompt mit: Kontext, Aufgabe,
Vorgehen, Gates, Nicht-Tun, erwartete Observations. Nicht hineingehören: PR-Body-Vorlage (Agent
schreibt die selbst), Workflow-Boilerplate (steckt in `AGENTS.md`), Branch-Namen-Vorgabe (Agent
wählt).

**Session-Start auf `main`.** Kein "vorher Branch anlegen, dann Session öffnen" — hat
Push-403-Probleme provoziert. Der Agent erzeugt den Branch innerhalb der Session.

**Fix-Medien (Schritt 10).** Zwei legitime Wege:

- **Fix-Prompt im Chat** für größere oder strukturelle Nachbesserungen.
- **Review-Kommentar am PR** für präzise, punktuelle Nachbesserungen mit klar benannten
  Touchpoints.

Faustregel: Fix in zwei bis drei Sätzen mit benannten Dateien — PR-Kommentar. Sonst Chat-Prompt.
Code-Änderungen bleiben durchgängig beim Agent.

### Was ein Agent nicht ohne Nachfrage tut

Kanonisch in `AGENTS.md` — insbesondere §§ „Dependencies", „Product Name vs. Code Identifiers",
„Scope", „Never" und „PR Lifecycle" (Merge ist `maintainer`-only). Hier bewusst nicht gespiegelt,
um Drift zu vermeiden.
