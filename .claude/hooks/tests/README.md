# Tests fuer die Read-Confirmation-Hooks

```bash
bash .claude/hooks/tests/run-tests.sh [--jobs N] [<abschnitt>...]
```

`run-tests.sh` ist der einzige Einstieg. Die Faelle stehen je Abschnitt in einer Datei unter
`cases/`; jede sourct `harness.sh`, die eine Bibliothek mit Hook-Pfaden, Eingabebauern und
Pruefhilfen (`ok`, `bad`, `expect`, `has_text`, `check_line` und weitere). `json.sh` baut ein
JSON-Literal wie `jq -c` in Bash, so dass Eingaben und Fixtures ohne einen jq-Prozess je Fall
entstehen; `jq` dekodiert nur noch Hook-Ausgaben. Die Fixtures entstehen einmal je Lauf, jeder
Abschnitt arbeitet auf einer eigenen Kopie. `--jobs N` laesst N Abschnitte zugleich laufen
(Vorgabe: die nutzbaren Kerne), die groessten zuerst; Abschnittsnamen ohne `.sh` waehlen einzelne
aus. Ein Abschnitt, der Zeit misst, traegt im Kopf `# hook-tests: run alone` und laeuft allein nach
den anderen (heute `guard-kill-timing`). Am Ende stehen die Zeit je Abschnitt und eine Summenzeile; ein Abschnitt ohne Ergebniszeile
zaehlt als rot. Exit 0 ist gruen, 1 rot oder ohne Fixtures, 2 ein Aufruffehler (Option, Abschnitt
unbekannt oder doppelt genannt, bash aelter als 5).

Jeder Hook laeuft als neuer `bash`-Prozess wie unter Claude Code, nicht als Subshell: eine Subshell
erbt Variablen und Funktionen der Harness, und `$0` und `$PPID` aendern sich. Der Abschnitt
`harness-parity` haelt die Harness ehrlich: je Hook vergleicht er einen Aufruf mit einer per `jq`
gebauten Eingabe auf stdin gegen denselben Aufruf ueber die Harness, in Eingabe, Ausgabe, Exit und
hinterlassenem Zustand; die Eingaben baut er mit denselben Bausteinen wie die Abschnitte. Dazu
prueft er `decision_of`, das Urteil der Abschnitte, gegen `jq`, und meldet jeden Hook unter
`.claude/hooks/` ohne eigenen Fall rot. `HOOK_PARITY_MUTATE=1` verfaelscht `js` um ein Zeichen;
dann muss er rot werden.

Prueft `require-receipt.sh`, `require-rule-read.sh`, `record-rule-read.sh`, `guard-kill.sh`,
`read-confirm.sh`, `save-compact-state.sh`, `restore-compact-state.sh`,
`remind-before-compact.sh` und `block-announce-end.sh`, dazu die Registrierung in den
Einstellungen und `run-folder.sh`, das `run-tests.sh`, `bench.sh` und, wenn ein Abschnitt allein
laeuft, `harness.sh` einlesen: je Lauf ein Ordner unter `artifacts/tmp/test/`, Aufraeumen
frueherer Laeufe per `flock` oder PID. **Exit 0, wenn alle Faelle halten**, sonst 1; jeder Fall druckt sein Urteil und, wo er faellt, das erwartete daneben.
Braucht `bash`, `jq`, `awk` und `git`.

Der Abschnitt `segments` prueft `lib/segments.awk`, den einen Zerleger eines Befehls fuer
`require-rule-read.sh` ([ww3d/playbook#537](https://github.com/ww3d/playbook/issues/537)), direkt:
Trenner, Gruppen und Ersetzungen, Umgebungs-Zuweisungen, Schluesselwoerter und Wrapper, Code nach
`-c`/`-Command`/`/c`/`eval`, Anfuehrungszeichen, Kommentare und Fortsetzungszeilen, die
`GH_REPO=`- und `cd`-Werte im Gueltigkeitsbereich und die Felder, die das Review-Gate liest. Ohne
`lib/segments.awk` oder mit einem `awk`, das fehlt oder scheitert, laesst das Review-Gate den Aufruf durch, die anderen Sperren laufen weiter
(Faelle in `require-rule-read-review-post`). Die Pfadform von `lib/pathform.sh` pruefen
`record-rule-read` und `require-rule-read-tool-calls` mit, auch einen Pfad unter einem anderen
Git-Bash-Mount als einem Laufwerk.

`bench-split.sh [<ref>] [<n>]` misst, wie die Zeit fuer die Zerlegung mit der Laenge eines Befehls waechst:
vier Arten langer Befehle je bei n und 2n, der Arbeitsbaum gegen einen Ref (Vorgabe `origin/main`). Wie
`bench.sh` laeuft es nicht in `run-tests.sh` mit und liest `run-folder.sh` ein; Zeiten sind kein Testurteil.

Hier steht bewusst **keine Fallzahl**. Eine Zaehlung neben dem Code, der sie veraendert, driftet.
Wer sie braucht, liest sie aus der letzten Zeile des Laufs.

Die Faelle zum Einlesen nach einer Verdichtung
([ww3d/playbook#487](https://github.com/ww3d/playbook/issues/487)) stehen in vier Dateien.
`cases/compact-state-save-restore.sh` deckt die Restore-Datei ab dem Cursor der letzten Sicherung:
acht Abschnitte in fester Reihenfolge, Schritt (`Step:` ohne Lese-Quittung, sonst `none found`),
Skill-Zeile und Todos, nur vorhandene Regeldateien, die Saetze des Menschen, Nachrichten anderer
Sessions und Helfer-Ergebnisse woertlich, die Zeitgrenze und jeden fail-open-Fall, dazu die
Erkennung einer Helfer-Verdichtung an ihren drei Signalen. `cases/compact-state-restore-carriers.sh`
deckt die Traeger der letzten Sicherung: was kein Traeger haelt, und welche Traeger eine fremde Hand
seit `checked` geaendert hat, ohne die eigenen Schreibaufrufe (MCP und `gh` per Bash).
`cases/require-rule-read-compact-lock.sh` deckt die Sperre mit ihren zwei Forderungen
(`need=compact.restore`, `need=chat`; ohne `chat.md` im Projekt nur die erste), ohne Helfer: `Agent` und `Task` sind gesperrt wie jeder andere Aufruf,
dazu Ventil, Zug-Zaehler, Lesen in Teilen und das Netz fuer eine Sperre ohne Haupt-Grenze.
`cases/require-receipt.sh` deckt das Zugende: es haelt, solange die Datei ungelesen ist oder ein
Kasten offen steht, und gibt frei, wenn alles abgehakt ist.

Der Block zu [ww3d/playbook#526](https://github.com/ww3d/playbook/issues/526) deckt den Start einer
Design-Runde, eines State Audits oder einer Uebergabe: der Skill-Aufruf von `ccweb-prompt` und
`state-audit` (Trigger `audit`) und von `chat-handoff` (Trigger `session`), auch mit Namensraum, und das
getippte `/ccweb-prompt` (`UserPromptExpansion`, Marke `<session>-<trigger>-owed`) loesen den Trigger
aus, je Skill nach der einen Tabelle `skill_table` im Hook. Ein Test haelt die Skill-Namen der Tabelle
und der Matcher beider `settings.json` gleich. Dazu die Abdeckungsprobe: jeder Trigger aus
`.agents/rules/index.json` hat im Hook ein `add_trigger <trigger>` oder steht mit Grund in der
Ausnahmeliste (`chat` allein); eine Ausnahme ohne Grund oder eine inzwischen abgebildete faellt rot.

## Die Lese-Bibliothek der Hooks

Alle acht Hooks lesen ihre Eingabe ueber `.claude/hooks/lib/stdin.sh` (`read_hook_payload`), nicht
mehr ueber `$(</dev/stdin)`, das unter Git Bash auf Windows die Named Pipe nicht oeffnen kann
(ww3d/playbook#488). Kam die Eingabe leer zurueck, sagt der Hook das einmal je Hook und
Claude-Code-Session: eine Zeile auf stderr und eine `systemMessage` (`read-confirm.sh` nur auf
stderr, weil sein stdout ein eigenes JSON ist); er endet weiter mit Exit 0. Der Block "the hooks
read stdin through lib/stdin.sh" in `cases/hook-stdin.sh` prueft je Hook vier Faelle — Pipe,
Datei-Umleitung, leere Eingabe (eine Warnung, die zweite Eingabe derselben Session still) und Terminal (Handaufruf,
keine Warnung, braucht ein pty) —, dazu die Bibliothek selbst und einen Hook ohne sie.

Beim Laden wirft die Bibliothek ausserdem die Git-Bash-Schalter `MSYS_NO_PATHCONV` und
`MSYS2_ARG_CONV_EXCL` des Aufrufers ab: mit ihnen oeffnet ein natives `jq` keinen `/d/...`-Pfad
(ww3d/playbook#507). Die Suite nimmt beide an ihrem Anfang weg; der Fall "MSYS_NO_PATHCONV from the
caller: AGENTS.md keeps its SHA" prueft einen Hook, der sie erbt.

## Herkunft

Importiert aus der Hook-Test-Suite eines Consumer-Repos (Nachweis:
[Herkunftsbelege](https://github.com/ww3d/playbook/blob/main/docs/provenance.md) im Playbook),
wo dieselbe Suite zusaetzlich einen vierten Hook, `gate-actions.sh`, deckte, den dieses Repo nicht
kennt (er gehoert zu dessen eigener git/gh-Aktions-Klassifikation, nicht zum generischen
Playbook-Set). Was bei der Uebernahme blieb, wegfiel oder uebertragen wurde und aus welchem Anlass
spaetere Faelle dazukamen, steht ebenfalls dort; welche Faelle die Suite heute hat, zeigt
`cases/` je Abschnitt.

## Laufzeit messen

```bash
bash .claude/hooks/tests/bench.sh [<ref>] [<runs>]
```

Vergleicht `require-rule-read.sh`, `read-confirm.sh`, `guard-kill.sh`, `record-rule-read.sh` und die
beiden Verdichtungs-Hooks im
Arbeitsbaum mit dem Stand `<ref>` (Vorgabe `origin/main`; ein Hook, den `<ref>` noch nicht kennt,
wird nur neu gemessen), abwechselnd je Durchgang, damit Last beide gleich trifft: feste
Hook-Eingaben, ein synthetisches Transkript von rund 0,9 MB, ein synthetisches Projekt in der
Groesse eines echten Consumers und fuer die beiden Hooks, die bei jedem Shell-Aufruf und jedem
Read laufen, je ein kleiner und ein Aufruf von rund 50 KB; fuer `save-compact-state.sh` und
`restore-compact-state.sh` eine Session mit Eingaben, Nachrichten anderer Sessions und Antworten,
je Wiederholung neu nummeriert, damit die verschiedenen Eingaben mit der Groesse wachsen, in drei Groessen (rund 1, 10 und 40 MB), gesichert vor und eingespielt nach der Verdichtung wie im
Betrieb, dazu die Zeichen, die sie zurueckbringt (Datei und eingespielter Kontext, beide per
`wc -m`). Ausgabe je Fall der Median in ms und das Urteil. Kein Teil von
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

Die Fixtures der Verdichtungs-Hooks bilden dazu die Grenze `compact_boundary`, die Zusammenfassung
(`isCompactSummary`), `origin.kind` je Eingabe, Nachrichten anderer Sessions, Slash-Befehle,
eingereihte Eingaben und Aufgaben-Aufrufe nach. Die Faelle zu Restore, Traegern und Sperre bauen
sich ihre Transkripte meist selbst ueber die Bausteine in `harness.sh` (`human`, `said`, `call`,
`result`, `boundary`, `summary`) und ihren Zustand ueber `cs_state`. Die Faelle der Sperre decken
jeden Ventil-Fall ab (dritte Sperre im Zug, neuer Zug, fehlende Datei, Hook-Fehler), den
Zug-Zaehler an eigenen kleinen Transkripten — Tool-Ergebnis, Meta-Zeile und Zusammenfassung
beginnen keinen Zug, auch jenseits der 400 Zeilen, die `require-rule-read.sh` zuerst liest — und
das lueckenlose Lesen der Restore-Datei in Teilen ueber `record-rule-read.sh`.

`read-confirm.sh` ist kein Transkript-Konsument und hat darum keine `.jsonl`-Fixtures — seine
Faelle in `cases/read-confirm.sh` bauen sich stattdessen ein Wegwerf-Projektverzeichnis (`CLAUDE.md`,
`AGENTS.md`, `.claude/skills/*/SKILL.md`, `docs/decisions/*.md`) und rufen den Hook direkt mit
`CLAUDE_PROJECT_DIR` darauf gesetzt auf.

## Warum Gegenproben paarweise stehen

Jeder Block, der ein `DENY`/`BLOCK` verlangt, hat einen Nachbarn, der ein `ALLOW` verlangt. Eine
Suite aus lauter `DENY`-Zeilen ist auch dann gruen, wenn das Gate alles sperrt — und ein Gate, das
alles sperrt, ist genauso kaputt wie eines, das nichts sperrt.

## Nicht in `build.ps1` oder `PSScriptAnalyzer` verdrahtet

Die Hook-Tests haengen an `bash`/`jq`/`awk`/`git`, nicht an PowerShell — sie laufen als eigener
Schritt im `shellcheck`-Job aus `.github/workflows/ci.yml`.
