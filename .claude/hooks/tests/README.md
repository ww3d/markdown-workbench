# Tests fuer die Read-Confirmation-Hooks

```bash
bash .claude/hooks/tests/run-tests.sh
```

Prueft `require-receipt.sh`, `require-rule-read.sh` und `read-confirm.sh`. **Exit 0, wenn alle
Faelle halten**, sonst 1; jeder Fall druckt sein Urteil und, wo er faellt, das erwartete daneben.
Braucht `bash`, `jq`, `awk` und `git`.

Hier steht bewusst **keine Fallzahl**. Eine Zaehlung neben dem Code, der sie veraendert, driftet.
Wer sie braucht, liest sie aus der letzten Zeile des Laufs.

## Herkunft

Importiert aus `ww3d/rc-control@3de127c` (`.claude/hooks/tests/`), wo dieselbe Suite zusaetzlich
einen vierten Hook, `gate-actions.sh`, deckte, den dieses Repo nicht kennt (er gehoert zu
rc-controls eigener git/gh-Aktions-Klassifikation, nicht zum generischen Playbook-Set). Bei der
Uebernahme:

- **Uebernommen wie sie war:** der `require-receipt.sh`-Block (die fuenf/sieben Fixtures gegen den
  Stop-Hook) — er haengt an keiner rc-control-Eigenheit.
- **Gestrichen:** die rund 30 DENY/ALLOW-Paare, die `gate-actions.sh`s eigene Erkennung von
  git-/gh-"Acting"-Kommandos gegen eine einzelne globale Session-Quittung pruefen, sowie die
  Subagent-Faelle (`sub/SID.jsonl`, `sub/SID/subagents/agent-a.jsonl`), die auf `gate-actions.sh`s
  Eltern-/Subagent-Transkript-Weiterleitung zielen. Beides hat in `require-rule-read.sh` keine
  Entsprechung: dieser Hook klassifiziert nach Tool+Trigger (`.agents/rules/<trigger>.md`), nicht
  nach einer git/gh-Kommando-Allowlist, und leitet nie an ein Eltern-Transkript weiter.
- **Sinngemaess auf `require-rule-read.sh` uebertragen:** die Form der paarweisen Gegenproben
  (DENY neben ALLOW), der Fail-open-Test bei fehlendem Helferprogramm, und der
  jq-Exit-2-Inversionstest (`AGENTS.md` § "Always" verlangt einen Test, der den Erfolgspfad eines
  stillen Catch-and-degrade real erzwingt) — alle drei jetzt gegen `require-rule-read.sh`s eigene
  Trigger-Landkarte und seine `rule | <pfad> |`-Quittungszeile, nicht gegen `gate-actions.sh`s
  Kommando-Erkennung.
- **Neu, fuer diese Runde:** Faelle fuer `ww3d/playbook#198` Punkte 1-3 (die H1 muss mit
  `## Konventionen` im selben Text stehen; eine einzelne kaputte Transkriptzeile darf den Rest
  nicht mitreissen; ein `jq`-Fehler beim Bauen der eigenen BLOCK/DRIFT-Ausgabe darf den Hook nicht
  mit Fehlercode enden lassen), fuer die neue Quittungserkennung in `tool_use.input.command` bei
  `require-rule-read.sh`, und fuer `read-confirm.sh`s neue Gruppe `Skills`, das echte
  Memory-Nachsehen, das `OK` je Gruppe und den Blob-SHA-Cache (E17).

## Was hier steht und was nicht

`mkfixtures.sh` erzeugt die Transkript-Fixtures in einem Wegwerf-Verzeichnis. Sie sind
**synthetisch**: sie bilden die Form eines CC-Transkripts nach — die `SessionStart`-Injektion, einen
Assistant-Textblock, einen `tool_use` — tragen aber keinen Inhalt aus einer echten Session. Das
haelt sie klein und pruefbar und macht die Tests ueberall lauffaehig, statt nur dort, wo zufaellig
ein passendes Transkript liegt.

Die Form ist der tragende Teil, deshalb steht im Kopf von `mkfixtures.sh`, was beim Schreiben an
einem echten Transkript nachgesehen wurde: dass eine Assistant-Nachricht **je Content-Block eine
Zeile** bekommt und der Text vor dem `tool_use` steht; dass die Injektion als `type: "attachment"`
mit `attachment.hookEvent: "SessionStart"` erscheint; und dass ihr `stdout`-Feld den Quittungstext
**selbst** enthaelt.

`read-confirm.sh` ist kein Transkript-Konsument und hat darum keine `.jsonl`-Fixtures — seine
Faelle in `run-tests.sh` bauen sich stattdessen ein Wegwerf-Projektverzeichnis (`CLAUDE.md`,
`AGENTS.md`, `.claude/skills/*/SKILL.md`, `docs/decisions/*.md`) und rufen den Hook direkt mit
`CLAUDE_PROJECT_DIR` darauf gesetzt auf.

## Warum Gegenproben paarweise stehen

Jeder Block, der ein `DENY`/`BLOCK` verlangt, hat einen Nachbarn, der ein `ALLOW` verlangt. Eine
Suite aus lauter `DENY`-Zeilen ist auch dann gruen, wenn das Gate alles sperrt — und ein Gate, das
alles sperrt, ist genauso kaputt wie eines, das nichts sperrt.

## Nicht in `build.ps1` oder `PSScriptAnalyzer` verdrahtet

Die Hook-Tests haengen an `bash`/`jq`/`awk`/`git`, nicht an PowerShell — sie laufen als eigener
Schritt im `shellcheck`-Job aus `.github/workflows/ci.yml`.
