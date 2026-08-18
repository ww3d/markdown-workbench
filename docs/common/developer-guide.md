# Developer Guide — ww3d Playbook

Praktische Anleitung fuer die Mitarbeit an einem ww3d-Projekt. Stack-Spezifika in den Overlays
(z. B. [`dotnet.md`](./dotnet.md), [`powershell.md`](./powershell.md)). Agent-Regeln in
[`AGENTS.md`](https://github.com/ww3d/playbook/blob/main/AGENTS.md) und in den Tech-Overlays unter
`tech/common/`.

## Conventional Commits

Format:

```
<type>(<scope>): <kurze beschreibung>

<body, optional, erklaert das Warum>

<footer, optional, z. B. "Closes #N">
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `chore`. Im
Zweifel: `chore`.

Title-Regeln: imperativ, lowercase nach dem Type-Doppelpunkt, kein Punkt am Ende, max ~72 Zeichen,
Englisch. Body erklaert das Warum, in vollen Saetzen.

Breaking Changes: `!` nach dem Scope (`feat(core)!: ...`).

## Branches

Format `<type>/<short-topic>`, lowercase, Bindestriche, Englisch, keine Umlaute. Beispiele:
`phase2/auth-handshake`, `fix/path-normalization`, `docs/runner-readme`.

Lifecycle: `main` aktuell holen → Branch anlegen → Commits → Push → Draft-PR → Review →
Squash-Merge durch Maintainer → Branch wird automatisch geloescht.

Atomare Commits: ein Commit = eine Aussage. Lieber viele kleine als einen grossen.

## PR / MR

Titel: Conventional-Commit-Stil, Englisch.

Beschreibung: Deutsch, mit fuenf Pflicht-Headings in dieser Reihenfolge:

1. **Was**
2. **Was bewusst nicht geaendert wurde**
3. **Entscheidungen**
4. **Wie getestet**
5. **Offene Fragen**

**Keine Mengenangaben ueber den Diff im Body** — keine Zeilen-, Datei-, Test- oder Funktionszahlen.
GitHub zeigt sie selbst und immer aktuell; eine handgepflegte Kopie ist nur eine Stelle, an der man
sich irren kann. Testlauf-Ergebnisse (`612 passed, 0 failed`) sind keine Diff-Zahlen und bleiben.
Die REQ-Liste steht nicht im Body, sondern in der Spec-Datei (`AGENTS.md` § "Task Spec"), die der
Body verlinkt.

Auto-Close-Footer am Ende des Bodys, Englisch (deutsche Varianten triggern den GitHub-Auto-Close
nicht). Mehrere Issues: Keyword pro Issue wiederholen (`Closes #N, closes #M`) oder Listen-Form mit
eigenem Keyword je Eintrag. Komma-Listen ohne Wiederholung schliessen nur das erste Issue.

**Sonst nirgends im Body Keyword und Nummer zusammen.** Wer begruendet, warum kein Footer gesetzt
ist, nennt das Issue ohne Keyword oder das Keyword ohne Nummer — nie beides in einem Atemzug. Beim
Squash-Merge wandert der Body in den Commit-Body, und der Parser unterscheidet Nennung und Anweisung
nicht: weder in Backticks noch nach einer Verneinung (`AGENTS.md` § "PR / MR Description", dort mit
dem gemessenen Fall).

**Zeigt das Keyword auf ein Tracking Issue, ist es an eine Bedingung geknuepft:** es geht nur in den
Body, wenn im Body dieses Issues kein offener Punkt mehr steht (`AGENTS.md` § "Tracking Issue").
Der Auto-Close prueft nichts — er schliesst beim Merge, und ein geschlossener Traeger sieht aus wie
ein erledigter. Steht noch etwas offen, nennt der PR das Issue ohne Keyword. Der Review rechnet
beides gegeneinander (`pr-poll-review` Phase 4, Punkt 8).

**Geschlossen wird von Hand, und zwar vom `reviewer`** — nach dem Merge, sobald der Body keinen
offenen Punkt mehr traegt und die Pruefung aus `AGENTS.md` § "Carrier Requirement" gelaufen ist
(was zeigt auf dieses Issue?). Kann er nicht, faellt es an den `maintainer`. Traegt der Body noch
Punkte, bleibt das Issue offen; umgehaengt wird nur, was nicht mehr zu diesem Design gehoert, nie
um schliessen zu koennen. Der **Merge** bleibt `maintainer`-only, das Schliessen ist keiner.

**Der Ausloeser ist das Merge-Ereignis, nicht das Approve.** Die Zustaendigkeit oben stand schon da,
als zwei Issues nach einem Merge liegenblieben — es fehlte der Anstoss, nicht die Regel: die
Reviewer-Sitzung endete beim Approve, der Merge kam Stunden spaeter. `pr-poll-review` haengt das
Schliessen darum als `[MERGE-GATE]` an das `merged`-Event (Phase 5).

Reviewer: `ww3-claude` und `ww3d`. Squash-Merge ist Default; PR-Description landet via Repo-Setting
im `main`-Commit-Body.

PR-Lifecycle-Mechanik (Drei Rollen, 12 Schritte): siehe `AGENTS.md` § "PR lifecycle".

## Code-Conventions

Detail in `AGENTS.md` und im Tech-Overlay. Uebergreifend:

- Nullables ueberall an, sofern die Sprache das unterstuetzt.
- Async fuer alle I/O.
- Records fuer Werte, Klassen mit Identitaet fuer Entitaeten.
- Guard Clauses am Anfang, Happy Path danach.
- UTC-Zeitstempel fuer gespeicherte Daten.
- Cancellation auf allen async Library-APIs.

### Klassen- und Methodengroesse

Groesse ist ein Kopplungs-Signal, kein Selbstzweck. Richtwerte nach Clean Code, die
Praxis-Obergrenze bewusst darunter — der Anlass war eine Klasse, die auf mehrere tausend Zeilen
wuchs (God-Class):

- **Klasse:** Richtwert ~150-200 Zeilen, harte Obergrenze 300. Clean Code nennt ~200 als
  Orientierung; die 300 ist die aus der Praxis gesenkte Reissleine — darueber nur mit Begruendung
  im PR-Body, sonst blockt der Review. Die Zeilenzahl ist aber nur die erste Achse.
- **Verantwortlichkeits-Achse:** unabhaengig von der Zeilenzahl blockt auch, wer mehr als ~15
  Instanzfelder oder mehr als eine klare Verantwortlichkeit traegt. Das ist der eigentliche
  God-Class-Faenger — eine grosse Klasse mit vielen Zustaenden und Zustaendigkeiten. Ein rein
  mechanischer Datei-Split (`partial`, mehrere Files) senkt die Zeilenzahl, loest die Kopplung aber
  nicht; er umgeht die Regel, statt sie zu erfuellen.
- **Ausnahme:** reine Schema-, DTO- und Config-Klassen sowie stateless Helfer sind von der
  Zeilengrenze ausgenommen. Sie werden gross durch die Zahl unabhaengiger Datensaetze, nicht durch
  Kopplung — hier zaehlt die Verantwortlichkeits-Achse, nicht die Zeile.
- **Methode:** Richtwert ~30 Zeilen. Zwei Komplexitaets-Masse ergaenzen die Zeilenzahl, weil sie
  Verschachtelung und Pfade messen statt bloss Laenge:
  - **Cognitive Complexity** (SonarSource) misst Lesbarkeit und bestraft Verschachtelung — das
    primaere Mass gegen God-Methoden. Richtwert ~15, C-Familie inkl. C# ~25.
  - **Cyclomatic Complexity** (McCabe/NIST) misst Testbarkeit ueber die Zahl unabhaengiger Pfade
    und ist ohne Tool im Kopf schaetzbar (Verzweigungen + 1). Richtwert ~10, Block ab ~25 — deckt
    sich mit .NET CA1502.
  - Faustregel darueber: tief verschachtelt oder schwer lesbar → aufteilen, auch wenn die Zahlen
    noch im Rahmen liegen.
- **Konstruktor:** wenige Parameter (~5); mehr → Parameter-Objekt. Kollaborateure hinter einem
  Interface, kein Beutel aus `Func<>`-Callbacks, keine zirkulaere Konstruktion.

## Tests

Public APIs in Library-Projekten bekommen Unit-Tests. Auch Fehlerpfade, Concurrency,
Persistenz-Edge-Cases. Trivial-Getter und DI-Verkabelung werden nicht getestet.

Test-Naming: `MethodName_Scenario_ExpectedResult` oder beschreibende Saetze.

Plattform-spezifische Tests werden auf der falschen Plattform mit Skip uebersprungen, nicht
ausgelassen oder mit alternativem Verhalten ersetzt.

Vor jedem Commit: lokaler Build und Tests gruen.

## CI

GitHub Actions auf Push und Pull Request, Matrix Linux + Windows. Details in [`ci.md`](./ci.md).

## Doku-Stil

Jede Doku-Aenderung haelt die Docs knapp, klar, sachlich: Redundanz und Fuellsaetze raus, kein Wissens-
oder Klarheitsverlust. Lieber knapp und eindeutig als ausfuehrlich.

Alle `.md`-Files im Repo wrappen Text-Zeilen bei ~100 Spalten (Soft-Wrap). Code-Bloecke, Tabellen
und Links bleiben unangetastet, auch wenn laenger.

## Architektur-Doku

`docs/`-Layout im Konsumenten-Repo:

- `docs/common/*.md` — 1:1-Mirror aus `ww3d/playbook` (synct, lokale Edits werden ueberschrieben).
- `docs/<file>.md` (`developer-guide.md`, `ci.md`, `dotnet.md`, `powershell.md`) — optionale
  Wrapper fuer projekt-spezifische Overrides.
- `docs/<architecture-baseline>.md`, `docs/<roadmap>.md`, `docs/<konzept>.md` — konsumenten-eigen,
  alle drei nur anlegen, wenn das Repo sie wirklich braucht.
- `docs/decisions/` — die Decision-Logs plus die lokale `README.md`, die deren Konvention haelt.
  Logs sind unveraenderlich, mit **einer Ausnahme:** das Log der laufenden Runde traegt am Ende
  `## Nachtraege aus den Review-Runden` (Wortlaut in der lokalen `docs/decisions/README.md`
  § "Immutabilitaet" — dort nachziehen, wo sie fehlt).
- `docs/tasks/` — die Spec-Dateien, eine je Aufgabe mit nummerierter Vorgabenliste, benannt nach
  ihrer Issue-Nummer (`AGENTS.md` § "Task Spec"). Anders als die Logs werden sie ueber mehrere
  Commits fortgeschrieben. Nur anlegen, sobald die erste Aufgabe eine solche Liste mitbringt.

Konkretes Set pro Repo: in der `CLAUDE.md` § "Project Context".

## Soll und Ist, Beleg-Pflicht

Ein Architektur- oder Baseline-Doc beschreibt das Zielbild, nicht den Ist-Stand. Wer beides in
derselben Prosa mischt, produziert Drift: Ist-Aussagen veralten unbemerkt, ganze Bloecke fehlen,
ohne dass es auffaellt — genau der Anlass fuer diese Regel.

- **Status-Marker.** Jede Baseline-Aussage traegt `[erfuellt]`, `[teilweise]` oder `[geplant]` und
  verweist auf ihren Beleg: den Architektur-Test, wo einer existiert, sonst den letzten
  State Audit. `[erfuellt]` ohne Beleg ist unzulaessig — es ist die Behauptung, die am
  leichtesten veraltet. Ein Marker deckt genau **eine** widerlegbare Aussage; deckt ein Satz mehrere
  Oberflaechen, Komponenten oder Lieferungen ab, wird er aufgeteilt, bis jeder Teil seinen eigenen
  Marker traegt — sonst hakt ein Marker Teile ab, die (noch) nicht stimmen. Die Marker bleiben
  dreiwertig; **keine** Checkboxen in Architektur- oder Baseline-Docs, auch nicht fuer
  Einzel-Aussagen — `[teilweise]` liesse sich binaer nicht abbilden. Checkboxen (`- [ ]`/`- [x]`)
  sind der Spec-Datei vorbehalten (`AGENTS.md` § "Task Spec"), wo die Aussage tatsaechlich
  zweiwertig ist (geliefert / nicht geliefert).
- **Beleg-Pflicht.** Keine Aussage "gebaut / erledigt / verifiziert / gruen / schnell" ohne
  stabilen Anker nach `AGENTS.md` § "Evidence Requirement" — repo-intern zuerst (Test-Name,
  Symbolname, relativer Pfad), ein SHA-Permalink nur, wo es nichts Repo-Internes gibt, ein
  Branch-Ref nie. Was nicht real lief — fehlendes Docker, CLI, CI oder Hardware — wird explizit als
  "nicht verifiziert" deklariert, nie beschoenigt. Performance-Aussagen brauchen einen
  Benchmark-Beleg; "schnell" ohne Zahl ist keine Aussage.
- **State Audit.** Vor jeder neuen Scheibe oder Phase ein Audit gegen das Baseline-Doc: jede
  Aussage gegen Code, Build und Test real gefahren, das Ergebnis als
  `audit/ist-stand-<YYYY-MM-DDTHHMM>.md` auf eigenem Branch (`AGENTS.md`
  § "Timestamps in File Names"). Hier ist `Datei:Zeile` die richtige Form und die Ausnahme zur
  Regel oben: das Audit nennt den Commit, an dem es genommen wurde, und fixiert damit den
  Bezugspunkt. So bleibt das Zielbild ehrlich, und Beschoenigung faellt im Review auf statt erst in
  Produktion.

Soll/Ist-Trennung und Beleg-Pflicht sind Drift- und Beschoenigungs-Schutz. Solange kein CI-Gate
sie maschinell prueft (Consumer haben teils kein laufendes CI), tragen lokale Tests und der Review
die Last. Ein Architektur-Test-Projekt, das die Marker gegen den Code prueft, ist der sinnvolle
Folge-Schritt, sobald CI wieder steht — hier bewusst noch nicht umgesetzt.

## Synchronisation aus dem Playbook

Sync-Set: `AGENTS.md` plus die Dateien unter `docs/common/` und `tech/common/`, **stack-gefiltert**.
Stack-neutrale Files (`ci.md`, `developer-guide.md`, die `README.md`s …) gehen an jeden Konsumenten;
die `<stack>.md`-Overlays (`dotnet.md`, `powershell.md` …) nur an Repos mit passendem `stack` im
`consumers/<name>.yml`. Adoption ergibt sich zusaetzlich aus dem `@`-Import in der
Konsumenten-`CLAUDE.md`. Dazu **alles unter `scripts/common/`** — die repo-uebergreifenden Checks
und die Datendateien daneben, ohne Suffix-Filter: eine Verbotsliste, die nicht mitwandert, laesst
den Check ueberall gruen laufen. Das `scripts/` daneben bleibt repo-eigen, dieselbe Trennung wie
zwischen `docs/common/` und den eigenen Docs. Zusaetzlich mirrort der Sync generische
`.claude`-Files
(`.claude/hooks/read-confirm.sh`, `.claude/hooks/require-receipt.sh`,
`.claude/commands/read-check.md`) und die teilbaren Skills unter
`.claude/skills/` — jedes Skill-Verzeichnis ausser dem Playbook-internen `playbook-onboard/` und der
`README.md`. `templates/*` und uebrige `.claude`-Files (`settings.json`, `session-start.sh`) sind
nicht Teil des Sync.

**Gesyncte Hook-Skripte werden ueber ihren Interpreter aufgerufen**, also
`bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh"` statt des nackten Pfads. Auf das x-Bit darf
sich nichts verlassen: der Sync kann es strukturell nicht transportieren (die GraphQL-Mutation
`createCommitOnBranch` kennt kein Mode-Feld, jede gesyncte Datei landet als `100644`), und die
Drift-Erkennung vergleicht Blob-SHAs — der Modus ist kein Byte und wuerde auch nie auffallen. Auf
Windows-Clones verwirft `core.filemode=false` das Bit ohnehin. Die Anfuehrungszeichen sind Pflicht,
sonst bricht der Aufruf bei einem Leerzeichen im Projektpfad.

Mechanik: automatisch via `.github/workflows/sync-consumers.yml` auf jedem Push auf `main`. Der
Workflow ruft nur das Playbook-Tooling auf (`scripts/sync-consumers.ps1`), das das Set pro Stack
waehlt (Stack-Enum aus `consumers/schema/consumer.schema.json`), pro driftendem Konsumenten einen
Draft-PR oeffnet und dort Files loescht, die nicht (mehr) ins Stack-Set gehoeren.

Consumer mit eigenem Format- oder Lint-Gate (prettier, ESLint, StyleCop o. ae.) muessen die gesyncten
Pfade (`AGENTS.md`, `.claude/`, `docs/common/`, `tech/common/`, `scripts/common/`,
`.playbook-version`) von diesem Gate
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
- **MINOR** — additiv, bricht nichts: neue Regel, neues Overlay, neue Always-Zeile (Beispiel:
  PR #75, Forge-CLIs).
- **PATCH** — Klarstellung, Wording oder Typo ohne inhaltliche Aenderung.

Jeder inhaltliche Playbook-PR zieht `/VERSION` passend hoch.

## Issue-Tracking

GitHub-Issues sind Single Source of Truth fuer offene Punkte ausserhalb von Roadmap und Code.
Sprache: Deutsch fuer Inhalt, Englisch fuer Titel.

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

Aufgeschobener Doku-Nachzug ist **kein eigenes Issue**, sondern eine Zeile in `backlog.md`
(`AGENTS.md` § "Documentation"): dort landen die Doku-Stellen, die ein PR nicht nachzieht, weil sein
Diff sie nicht falsch macht. Abgebaut wird das gebuendelt am State Audit vor jeder Scheibe. Ein
Tracking Issue haengt an einem Design und wird geschlossen — Doku-Schuld ueberlebt Designs, und
`backlog.md` ist eine Datei, die den Forge-Wechsel ueberlebt.

**Fehlt die Datei, legt sie der PR an, der die erste Zeile beitraegt.** Das gilt fuer jeden
zurueckgestellten Punkt, nicht nur fuer Doku-Schuld: eine fehlende `backlog.md` ist nie ein Grund,
einen Punkt ohne Traeger zu lassen (`AGENTS.md` § "Carrier Requirement"). Verteilt wird die Datei
bewusst nicht vorab — Regeln wandern per Sync, Dateien nicht, und eine leere Datei in jedem Repo
waere Datei-Sync statt Regel.

**Ein Tracking Issue wird in beide Richtungen gepflegt.** Ein zurueckgestellter Punkt kommt in den
Body, ein **gelieferter wird dort abgehakt** — im selben PR, der ihn liefert (`AGENTS.md`
§ "Tracking Issue"). Der Body ist kein Plan, sondern die aktuelle Antwort auf "was ist noch offen";
ein gebauter Punkt ohne Haken ist von einem ungebauten nicht zu unterscheiden und wird in der
naechsten Design-Runde erneut beauftragt. Die Spec-Datei hakt ihre `REQ` ab, der Issue-Body seine
Punkte — beides, nie nur eines.

Issue anlegen fuer: aufgeschobene Entscheidungen, Tech-Debt fuer spaeter, Design-Fragen,
Beobachtungen aus Reviews ausserhalb des aktuellen MR-Scopes. Direkt im Code loesen: was im
aktuellen Scope unter ~15 Minuten erledigt ist, offensichtliche Bugs waehrend der Arbeit, Cleanup
ohne Aufblaehen des Diffs. Im Zweifel: Issue.

## Coding-Workflow mit Agent

Greift fuer Code-Aenderungen — Features, Fixes, Tests, Refactorings. Reine Doku-, Issue- und
PR-Kommentar-Pflege macht `cweb` selbst direkt via `gh`, ohne Coding-Agent (auch das geht ueber
PR, weil das Ruleset Direkt-Push auf `main` blockt).

PR-Lifecycle-Mechanik (Draft, CI-Fix-Loop, Review, Merge): `AGENTS.md` § "PR lifecycle". Im
Coding-Workflow fuellt ein Coding-Agent die `dev`-Rolle, `cweb` oder `ww3d` die `reviewer`-Rolle,
`ww3d` alleinig die `maintainer`-Rolle.

Drei Workflow-spezifische Punkte, die die Sequenz nicht festschreibt:

**Prompt-Struktur (Schritt 1).** `cweb` schreibt einen Aufgaben-Prompt mit: Kontext, Aufgabe,
Vorgaben (nummerierte `REQ-NN`-Liste, vom Agent als Spec-Datei `docs/tasks/<issue>-<slug>.md`
anzulegen — `AGENTS.md` § "Task Spec"; nicht in den PR-Body), Vorgehen, Gates, Nicht-Tun, erwartete
Observations. Nicht hineingehoeren:
PR-Body-Vorlage (Agent schreibt die selbst), Workflow-Boilerplate (steckt in `AGENTS.md`),
Branch-Namen-Vorgabe (Agent waehlt).

**Session-Start auf `main`.** Kein "vorher Branch anlegen, dann Session oeffnen" — hat
Push-403-Probleme provoziert. Der Agent erzeugt den Branch innerhalb der Session.

**Fix-Medien (Schritt 10).** Zwei legitime Wege:

- **Fix-Prompt im Chat** fuer groessere oder strukturelle Nachbesserungen.
- **Review-Kommentar am PR** fuer praezise, punktuelle Nachbesserungen mit klar benannten
  Touchpoints.

Faustregel: Fix in zwei bis drei Saetzen mit benannten Dateien — PR-Kommentar. Sonst Chat-Prompt.
Code-Aenderungen bleiben durchgaengig beim Agent.

### Was ein Agent nicht ohne Nachfrage tut

Kanonisch in `AGENTS.md` — insbesondere §§ „Dependencies", „Product Name vs. Code Identifiers",
„Scope", „Never" und „PR Lifecycle" (Merge ist `maintainer`-only). Hier bewusst nicht gespiegelt,
um Drift zu vermeiden.
