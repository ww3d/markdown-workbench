# Developer Guide — ww3d Playbook

Praktische Anleitung fuer die Mitarbeit an einem ww3d-Projekt. Die Regeln selbst stehen in den
Regeldateien; dieser Guide verweist darauf und traegt nur, was dort nicht hingehoert: Erklaerung,
Beispiele und die Mechanik des Syncs. Stack-Spezifika in den Overlays
(z. B. [`dotnet.md`](https://github.com/ww3d/playbook/blob/main/docs/common/dotnet.md),
[`powershell.md`](https://github.com/ww3d/playbook/blob/main/docs/common/powershell.md)) — nur das
zu den eigenen `stacks` passenden Overlays landen ueberhaupt im Consumer, ein relativer Link waere
dort fuer jeden anderen Stack tot. Agent-Regeln in
[`AGENTS.md`](https://github.com/ww3d/playbook/blob/main/AGENTS.md), den Regeldateien unter
`.agents/rules/` und den Tech-Overlays unter `tech/common/`.

## Conventional Commits

Format:

```
<type>(<scope>): <kurze beschreibung>

<body, optional, erklaert das Warum>

<footer, optional, z. B. "Closes #N">
```

Die Typenliste steht in `.agents/rules/pr.md` § "Branch Naming", die Titelregeln (imperativ,
lowercase nach dem Doppelpunkt, kein Punkt, ~72 Zeichen, Scope, `!` fuer Breaking
Changes, Body erklaert das Warum) in `AGENTS.md` § "Working Mode", die Sprache in § "Language".

## Branches

Format und Typ: `.agents/rules/pr.md` § "Branch Naming". Der Lebenslauf von Branch und PR (Draft,
Review, Merge, Aufraeumen): § "PR Lifecycle" ebenda; der Branch wird nach dem Merge per Repo-Setting
geloescht (`docs/common/ci.md` § "Repo-Settings").

## PR / MR

Titel, Body-Ueberschriften, Mengenangaben, Spec-Datei, Auto-Close-Keyword und die Bedingung bei
Issues mit Checkliste: `.agents/rules/pr.md` § "PR / MR Description" und
`.agents/rules/carrier.md` § "Tracking Issue".

Geschlossen wird nach dem Merge, von dem, der merged (`.agents/rules/pr.md` § "Merge"). Reviewer
(`.agents/rules/pr.md` § "Reviewer"), Rollen und Lebenslauf (§ "PR Lifecycle") stehen dort einmal.

## Code-Conventions

Regeln: `.agents/rules/code.md` § "Code Conventions" (Klassen-, Methoden- und Konstruktorgroesse) und
das Tech-Overlay des Stacks (Nullables, Records, Guard Clauses, UTC, Cancellation).

### Klassen- und Methodengroesse

Groesse ist ein Kopplungs-Signal, kein Selbstzweck. Die Zahlen stehen in der Regeldatei; hier die
Begruendung:

- Clean Code nennt ~200 Zeilen als Orientierung; die harte Obergrenze darueber ist eine Reissleine
  aus der Praxis, weil eine Klasse ohne harte Grenze zur God-Class waechst.
- Die Zeilenzahl ist nur die erste Achse. Ein rein mechanischer Datei-Split (`partial`, mehrere
  Files) senkt sie, loest die Kopplung aber nicht; er umgeht die Regel, statt sie zu erfuellen.
  Schema-, DTO- und Config-Klassen werden gross durch die Zahl unabhaengiger Datensaetze, nicht durch
  Kopplung — hier zaehlt die Verantwortlichkeits-Achse.
- **Cognitive Complexity** (SonarSource) misst Lesbarkeit und bestraft Verschachtelung — das
  primaere Mass gegen God-Methoden. **Cyclomatic Complexity** (McCabe/NIST) misst Testbarkeit ueber
  die Zahl unabhaengiger Pfade und ist ohne Tool im Kopf schaetzbar (Verzweigungen + 1); sie deckt
  sich mit .NET CA1502.

## Tests

Regeln: `.agents/rules/code.md` § "Work Standard" und `AGENTS.md` § "Always" (Tests fuer neue
Public-Library-APIs), Namensmuster und Plattform-Skip im Tech-Overlay des Stacks. Trivial-Getter und
DI-Verkabelung werden nicht getestet.

Wann welcher Lauf faellig ist, die Laufzeile und die Zeitvorgabe: `.agents/rules/pr.md`
§ "Test Runs". Was der volle Lauf eines Repos ist (Befehl, Plattformen) und welche Guard classes es
hat, steht in seiner `CLAUDE.md`. Den Temp-Ordner gibt der Lauf vor: `.agents/rules/code.md`
§ "Test Isolation", die Ausnahmen je Stack in `docs/common/ci.md` § "Testordner je Stack".

## CI

Pipeline, Trigger und Matrix: [`ci.md`](./ci.md). Solange die Org-CI nicht laeuft, gilt
`.agents/rules/pr.md` § "CI Counts as Dead Org-Wide".

## Doku-Stil

Stil und harter Umbruch der Docs: `.agents/rules/docs.md` § "Documentation".

## Architektur-Doku

`docs/`-Layout im Konsumenten-Repo:

- `docs/common/*.md` — 1:1-Mirror aus `ww3d/playbook` (synct, lokale Edits werden ueberschrieben).
- `docs/<file>.md` (`developer-guide.md`, `ci.md`, `dotnet.md`, `powershell.md`) — optionale
  Wrapper fuer projekt-spezifische Overrides.
- `docs/<architecture-baseline>.md`, `docs/<roadmap>.md`, `docs/<konzept>.md` — konsumenten-eigen,
  alle drei nur anlegen, wenn das Repo sie wirklich braucht.
- `docs/decisions/` — die Decision-Logs plus die lokale `README.md`, die deren Konvention haelt
  (Immutabilitaet und die Ausnahme `## Nachtraege aus den Review-Runden`: dort nachziehen, wo sie
  fehlt).
- `docs/tasks/` — die Spec-Dateien (`.agents/rules/pr.md` § "Task Spec"). Nur anlegen, sobald die
  erste Aufgabe eine nummerierte Vorgabenliste mitbringt.

Konkretes Set pro Repo: in der `CLAUDE.md` § "Project Context".

## Soll und Ist, Beleg-Pflicht

Ein Architektur- oder Baseline-Doc beschreibt das Zielbild, nicht den Ist-Stand. Wer beides in
derselben Prosa mischt, produziert Drift: Ist-Aussagen veralten unbemerkt, ganze Bloecke fehlen,
ohne dass es auffaellt — genau der Anlass fuer diese Regeln.

- **Status-Marker:** `.agents/rules/docs.md` § "Target vs. Actual" (auch: keine Checkboxen in
  Architektur- oder Baseline-Docs). Warum: ein mehrwertiger Marker liesse sich binaer nicht
  abbilden; Checkboxen gehoeren dorthin, wo die Aussage zweiwertig ist — Spec-Dateien und
  Tracking-Issue-Bodies.
- **Beleg-Pflicht:** `.agents/rules/evidence.md` § "Evidence Requirement". Performance-Aussagen
  brauchen einen Benchmark-Beleg; "schnell" ohne Zahl ist keine Aussage.
- **State Audit:** `.agents/rules/audit.md` § "State Audit".

Soll/Ist-Trennung und Beleg-Pflicht sind Drift- und Beschoenigungs-Schutz. Solange kein CI-Gate
sie maschinell prueft (Consumer haben teils kein laufendes CI), tragen lokale Tests und der Review
die Last. Ein Architektur-Test-Projekt, das die Marker gegen den Code prueft, ist der sinnvolle
Folge-Schritt, sobald CI wieder steht — hier bewusst noch nicht umgesetzt.

## Synchronisation aus dem Playbook

Sync-Set: `AGENTS.md` plus die Dateien unter `docs/common/` und `tech/common/`, **stack-gefiltert**.
Stack-neutrale Files (`ci.md`, `developer-guide.md`, die `README.md`s …) gehen an jeden Konsumenten;
die `<stack>.md`-Overlays (`dotnet.md`, `powershell.md` …) nur an Repos, die den Stack in
`stacks` im `consumers/<name>.yml` fuehren — bei mehreren Stacks die Overlays aller. Adoption
ergibt sich zusaetzlich aus dem `@`-Import in der Konsumenten-`CLAUDE.md`, eine Zeile je Stack. Dazu
**alles unter `scripts/common/`** — die repo-uebergreifenden Checks und die Datendateien daneben,
ohne Suffix-Filter: eine Verbotsliste, die nicht mitwandert, laesst
den Check ueberall gruen laufen. Das `scripts/` daneben bleibt repo-eigen, dieselbe Trennung wie
zwischen `docs/common/` und den eigenen Docs. Dazu die Regeldateien direkt unter `.agents/rules/`
samt dem generierten `.agents/rules/index.json` — die ausgelagerten Teile von `AGENTS.md`, die der
Kern indexiert. **`.agents/rules/local/` ist ausgenommen:** dort liegen die consumer-eigenen
Regeln, und der Sync fasst sie nie an, weder schreibend noch loeschend. Neben den Regeldateien
gehen die zwei Datendateien `.agents/core-rules.json` und `.agents/lessons.md` mit. Zusaetzlich
mirrort der Sync die sechs generischen `.claude`-Files (`.claude/hooks/read-confirm.sh`,
`require-receipt.sh`, `require-rule-read.sh`, `record-rule-read.sh`, `guard-kill.sh` und
`.claude/commands/read-check.md`), die Hook-Tests unter `.claude/hooks/tests/` und die teilbaren
Skills unter `.claude/skills/` — jedes Skill-Verzeichnis ausser dem Playbook-internen
`playbook-onboard/`, ohne das Review-Widget `pr-poll-review/reference/widget-reference.html` und
ohne die `README.md`. Die verbindliche Liste fuer einen Consumer zeigt
`sync-consumers.ps1 -WhatIf` im Playbook. `.claude/settings.json` liefert der Sync ebenfalls aus,
je Consumer gebaut aus der Playbook-Vorlage plus dem Manifest-Feld `claude_settings` — lokale
Edits werden ueberschrieben, ein Zusatz gehoert ins Manifest im Playbook. `templates/*` und uebrige
`.claude`-Files (`session-start.sh`) sind nicht Teil des Sync.

**Gesyncte Hook-Skripte werden ueber ihren Interpreter aufgerufen, in der `args`-Form**:
`"command": "bash", "args": ["${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh"]` statt des nackten
Pfads. Auf das x-Bit darf sich nichts verlassen: der Sync kann es strukturell nicht transportieren
(die GraphQL-Mutation `createCommitOnBranch` kennt kein Mode-Feld, jede gesyncte Datei landet als
`100644`), und die Drift-Erkennung vergleicht Blob-SHAs — der Modus ist kein Byte und wuerde auch nie
auffallen. Auf Windows-Clones verwirft `core.filemode=false` das Bit ohnehin. Die `args`-Form statt
eines `command`-Strings, weil Claude Code einen String an eine Shell gibt, und die ist unter Windows
PowerShell: dort ist `$CLAUDE_PROJECT_DIR` eine leere Variable, `bash` bekommt
`/.claude/hooks/<name>.sh`, und der Fehler gilt als nicht blockierend — der Hook laeuft nie, ohne
dass es auffaellt. In der `args`-Form setzt Claude Code den Platzhalter selbst ein, ohne Shell
dazwischen; ein Leerzeichen im Projektpfad ist damit auch ohne Anfuehrungszeichen unschaedlich.

Mechanik: von Hand per
[scripts/sync-all.ps1](https://github.com/ww3d/playbook/blob/main/scripts/sync-all.ps1) **im
Playbook**, gefahren vom Controller des Playbooks, bis die Org-CI produktiv laeuft. Der Workflow
[.github/workflows/sync-consumers.yml](https://github.com/ww3d/playbook/blob/main/.github/workflows/sync-consumers.yml)
liegt weiter im Playbook, ist aber abgeschaltet und kommt mit der Org-CI zurueck. Beide Wege rufen
nur das Playbook-Tooling auf
([scripts/sync-consumers.ps1](https://github.com/ww3d/playbook/blob/main/scripts/sync-consumers.ps1),
ebenfalls im Playbook), das das Set je Consumer ueber alle seine Stacks waehlt (Stack-Enum aus
[consumers/schema/consumer.schema.json](https://github.com/ww3d/playbook/blob/main/consumers/schema/consumer.schema.json),
im Playbook), pro driftendem Konsumenten einen Draft-PR oeffnet und dort Files loescht, die nicht
(mehr) ins Stack-Set gehoeren. Den Merge der Sync-PRs regelt `.agents/rules/pr.md` § "Merge".

Consumer mit eigenem Format- oder Lint-Gate (prettier, ESLint, StyleCop o. ae.) muessen die
gesyncten Pfade (`AGENTS.md`, `.agents/rules/`, `.agents/core-rules.json`, `.agents/lessons.md`,
`.claude/`, `docs/common/`, `tech/common/`, `scripts/common/`, `.playbook-version`) von diesem Gate
ausnehmen — es sind byte-identische Mirror-Artefakte, die lokal nie umformatiert werden duerfen,
sonst bricht die naechste Sync-Welle am Format-Check (z. B. via `.prettierignore`). Beim Onboarding
eines solchen Repos gehoert der Ausschluss gleich mit angelegt.

### Override-Semantik in Wrappers

`@`-Imports werden nebeneinander geladen, ohne formale Override-Reihenfolge. Wrapper-Regeln, die ein
Common ersetzen oder erweitern, muessen das im Bullet textlich markieren:

- `*(overrides the baseline)*`
- `*(addition to the baseline)*`

Ohne Marker ist der Konflikt nicht-deterministisch.

## Playbook-Versionierung

Das Playbook traegt eine zentrale Version nach **SemVer 2.0.0**, gehalten in einer einzigen Datei
`/VERSION` im Playbook-Root (nackte Versionszeile, kein Header). Ein Sync = ein Stand = eine
Version. Die Sync-Action schreibt den jeweils aktuellen Wert als `.playbook-version` in jeden
Konsumenten-Root, damit die Read-Confirmation (siehe `AGENTS.md` § "Session Receipt") die Version
melden kann. Die einzelnen gesyncten Files bleiben bewusst header-frei.

Bump-Regel — "Conventions als API", aus Sicht der Konsumenten:

- **MAJOR** — Breaking fuer Konsumenten: eine Regel wird verschaerft oder entfernt und kann
  bestehenden Code oder offene PRs brechen (z. B. CS1591 von Warning auf Error, neues
  Pflicht-Gate).
- **MINOR** — additiv, bricht nichts: neue Regel, neues Overlay, neue Always-Zeile.
- **PATCH** — Klarstellung, Wording oder Typo ohne inhaltliche Aenderung.

Jeder inhaltliche Playbook-PR zieht `/VERSION` passend hoch. Ein PR, der `VERSION` aendert, ist
nie doku-only und durchlaeuft den vollen Review-Ablauf (`.agents/rules/docs.md`
§ "Documentation").

## Issue-Tracking

Wann ein Punkt ein Issue, eine `backlog.md`-Zeile oder direkt ein Fix ist: `.agents/rules/carrier.md`
§ "Carrier Requirement". Sprache der Issues: `AGENTS.md` § "Language".

Labels — pro Issue ggf. mehrere:

- **Art:** `deferred`, `tech-debt`, `design-question`, `bug`, `enhancement`
- **Phase:** `phase-1`, `phase-2.a`, … — Granularitaet pro Projekt
- **Bereich:** repo-spezifisch (typisch `core`, `service`, `runner`, `host`, `api`, `web`,
  `testing`, `docs`, `ci`, `infrastructure`)

Empfohlene Struktur:

- **Kontext** — wo ist das Problem, wie ist es entstanden
- **Varianten** (bei Design-Fragen) — mit Pro/Contra
- **Empfehlung** — Vorschlag des Autors
- **Zeitpunkt** — wann die Umsetzung dran ist
- **Referenz** — Verweise auf Code, Docs, verwandte Issues / PRs

Aufgeschobener Doku-Nachzug ist kein eigenes Issue, sondern eine Zeile in `backlog.md`
(`.agents/rules/docs.md` § "Documentation"). Ein Tracking Issue haengt an einem Design und wird
geschlossen — Doku-Schuld ueberlebt Designs, und `backlog.md` ist eine Datei, die den Forge-Wechsel
ueberlebt. Verteilt wird die Datei bewusst nicht vorab — Regeln wandern per Sync, Dateien nicht, und
eine leere Datei in jedem Repo waere Datei-Sync statt Regel. Pflege des Tracking-Issue-Bodys in
beide Richtungen: `.agents/rules/carrier.md` § "Tracking Issue".

## Coding-Workflow mit Agent

Greift fuer Code-Aenderungen — Features, Fixes, Tests, Refactorings. Reine Doku-, Issue- und
PR-Kommentar-Pflege macht `cweb` selbst direkt via `gh`, ohne Coding-Agent (auch das geht ueber
PR, weil das Ruleset Direkt-Push auf `main` blockt).

Rollen und Lebenslauf: `.agents/rules/pr.md` § "PR Lifecycle". Die Kette Design → Dev → Review
(je Schritt ein Skill: `ccweb-prompt`, `dev-task`, `pr-poll-review`), die Startzeilen und die Regeln
dazu: `.agents/rules/pr.md` § "Controller Mode" und die Skills selbst; die Spec-Datei ist der Auftrag
(§ "Task Spec"), einen getrennten Auftrags-Prompt gibt es nicht.

Wie eine Nachbesserung zur Dev-Session kommt — Review-Kommentar oder Auftrag am Traeger —, regelt
`.agents/rules/pr.md` § "Mirroring GitHub Conversations". Code-Aenderungen bleiben durchgaengig bei
der Dev-Session.

### Was ein Agent nicht ohne Nachfrage tut

Kanonisch in `AGENTS.md` §§ „Scope" und „Never", in `.agents/rules/code.md` §§ „Dependencies"
und „Product Name vs. Code Identifiers" sowie in `.agents/rules/pr.md` § „Merge". Hier bewusst
nicht gespiegelt, um Drift zu vermeiden.
