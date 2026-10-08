# Tests fuer die Read-Confirmation-Hooks

```bash
bash .claude/hooks/tests/run-tests.sh
```

Prueft `require-receipt.sh`, `require-rule-read.sh`, `record-rule-read.sh`, `guard-kill.sh` und
`read-confirm.sh`, dazu die Registrierung in den Einstellungen und `run-folder.sh`, das
`run-tests.sh` und `bench.sh` einlesen: je Lauf ein Ordner unter `artifacts/tmp/test/`, Aufraeumen
frueherer Laeufe per `flock` oder PID. **Exit 0, wenn alle
Faelle halten**, sonst 1; jeder Fall druckt sein Urteil und, wo er faellt, das erwartete daneben.
Braucht `bash`, `jq`, `awk` und `git`.

Hier steht bewusst **keine Fallzahl**. Eine Zaehlung neben dem Code, der sie veraendert, driftet.
Wer sie braucht, liest sie aus der letzten Zeile des Laufs.

## Herkunft

Importiert aus der Hook-Test-Suite eines Consumer-Repos (Nachweis:
[Herkunftsbelege](https://github.com/ww3d/playbook/blob/main/docs/herkunftsbelege.md) im Playbook),
wo dieselbe Suite zusaetzlich einen vierten Hook, `gate-actions.sh`, deckte, den dieses Repo nicht
kennt (er gehoert zu dessen eigener git/gh-Aktions-Klassifikation, nicht zum generischen
Playbook-Set). Was bei der Uebernahme blieb, wegfiel oder uebertragen wurde und aus welchem Anlass
spaetere Faelle dazukamen, steht ebenfalls dort; welche Faelle die Suite heute hat, zeigt
`run-tests.sh` je Block.

## Laufzeit messen

```bash
bash .claude/hooks/tests/bench.sh [<ref>] [<runs>]
```

Vergleicht `require-rule-read.sh`, `read-confirm.sh`, `guard-kill.sh` und `record-rule-read.sh` im
Arbeitsbaum mit dem Stand `<ref>` (Vorgabe `origin/main`; ein Hook, den `<ref>` noch nicht kennt,
wird nur neu gemessen), abwechselnd je Durchgang, damit Last beide gleich trifft: feste
Hook-Eingaben, ein synthetisches Transkript von rund 0,9 MB, ein synthetisches Projekt in der
Groesse eines echten Consumers und fuer die beiden Hooks, die bei jedem Shell-Aufruf und jedem
Read laufen, je ein kleiner und ein Aufruf von rund 50 KB. Ausgabe je Fall der Median in ms und das Urteil. Kein Teil von
`run-tests.sh` — eine Zeit ist kein Bestanden/Nicht-bestanden, aber eine Laufzeit-Aussage im PR
braucht eine Quelle, die jeder wiederholen kann.

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
