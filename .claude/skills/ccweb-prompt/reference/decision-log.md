# Decision-Log, Zeilen-Datei und Ablage

## Decision-Log

**Format, Dateiname und Ablage im Repo folgen der `docs/decisions/README.md` des jeweiligen
Consumers.**

**Das Log der laufenden Runde traegt am Ende die Nachtraege der Review-Runden.** Der festgehaltene
Entscheidungstext bleibt verbatim, der Abschnitt `## Nachtraege aus den Review-Runden` kommt
abgesetzt darunter (`docs/decisions/README.md` § Immutabilitaet).

Das Log liegt auf dem Branch der Design-Session und damit im PR; ein Reviewer zieht es von dort.

## Zeilen-Datei

Am Ende jeder Runde schreibt die Design-Session neben das Log eine Zeilen-Datei
`docs/decisions/<stempel>-<slug>-ledger.jsonl`, eine Datei je Runde, mit demselben Stempel wie das
Log. Every point of a design round, the rejected ones included, goes to the round's ledger file, in
every mode; the design pushes it with its branch.

- **Skript fahren:** `pwsh scripts/common/test-ledger.ps1 -Path <datei>`.
- **Ohne pwsh:** jede Zeile von Hand gegen `scripts/common/ledger.schema.json` halten.

## Ablage per Push

Log, Zeilen-Datei und Spec-Datei gehen als Commits auf einen Branch des Ziel-Repos, nie als Datei
in den Chat.

## Rueckfall ohne Schreibzugang

Nur wo die Design-Session nicht ins Ziel-Repo pushen kann, gehen die Artefakte als **Output-Datei**
raus (`create_file` + `present_files`), nie als Chat-Block:

| Art           | Dateiname                          |
|---------------|------------------------------------|
| Spec-Datei    | `YYYY-MM-DDTHHMMZ-spec.md`         |
| Decision-Log  | `YYYY-MM-DDTHHMMZ-decision-log.md` |
| Zeilen-Datei  | `YYYY-MM-DDTHHMMZ-ledger.jsonl`    |

- Ein Artefakt pro Datei — nie zusammengelegt.
- Jede Markdown-Datei beginnt mit der Marker-Zeile `<!-- transport: verbatim, do not re-render -->`,
  danach folgt direkt der Inhalt. **Kein Fence um den Inhalt.**
- **Transport und Ablage sind zwei Dinge.** Der Chat-Dateiname ist reiner Transport; wer pusht,
  legt den Inhalt unveraendert unter dem Repo-Dateinamen ab (Spec: `docs/tasks/<issue>-<slug>.md`,
  Log und Zeilen-Datei nach der Consumer-Konvention).
- **Uebergabe:** Datei herunterladen und **als Datei anhaengen**, nicht den Inhalt hineinkopieren.
