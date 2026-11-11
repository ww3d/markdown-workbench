# Developer Guide — ww3d Playbook

## Conventional Commits

Die Typenliste steht in `.agents/rules/pr.md` § "Branch Naming", die Sprache in `.agents/rules/docs.md` § "Language".

## PR / MR

Geschlossen wird nach dem Merge, von dem, der merged (`controller-mode` § "Schritt 5: Merge").

## Doku-Stil

Stil der Docs: `.agents/rules/docs.md` § "Documentation".

## Soll und Ist, Beleg-Pflicht

- **Status-Marker:** `.agents/rules/docs.md` § "Target vs. Actual", Grammatik
  `.agents/rules/audit.md` § "Status Markers" (auch: keine Checkboxen in Architektur- oder
  Baseline-Docs).

## Synchronisation aus dem Playbook

Den Merge der Sync-PRs regelt `controller-mode` § "Schritt 5: Merge".

Consumer mit eigenem Format- oder Lint-Gate (prettier, ESLint, StyleCop o. ae.) muessen die
gesyncten Pfade (`AGENTS.md`, `.agents/rules/`, `.agents/core-rules.json`, `.claude/`,
`docs/common/`, `.agents/tech/*.md`, `scripts/common/`, `.agents/manifest.json`) von diesem Gate
ausnehmen (z. B. via `.prettierignore`).

### Override-Semantik in Wrappers

Wrapper-Regeln, die ein Common ersetzen oder erweitern, muessen das im Bullet textlich markieren:

- `*(overrides the baseline)*`
- `*(addition to the baseline)*`

## Coding-Workflow mit Agent

Die Kette Design → Dev → Review (je Schritt ein Skill: `ccweb-prompt`, `dev-task`,
`pr-poll-review`), die Startzeilen und die Regeln dazu: `.agents/rules/controller.md` § "Controller
Mode" und die Skills selbst; die Spec-Datei ist der Auftrag (`.agents/rules/pr.md` § "Task Spec"),
einen getrennten Auftrags-Prompt gibt es nicht.

Code-Aenderungen bleiben durchgaengig bei der Dev-Session (`.agents/rules/pr.md` § "Dev Session").

### Was ein Agent nicht ohne Nachfrage tut

Kanonisch in `AGENTS.md` § „Working Mode", in `.agents/rules/agents.md` § „Never: Ending Processes
and Sessions", in `.agents/rules/code.md` §§ „Never in Code" und „Dependencies" sowie in
`.agents/rules/pr.md` § „Controller Mode" (neue Namen) und in `controller-mode` § „Schritt 5:
Merge".
