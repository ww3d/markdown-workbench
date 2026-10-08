# Decision-Log, Zeilen-Datei und Ablage

Gelesen und quittiert, bevor der Skill das Log der Runde schreibt (Schritt 1) und bevor er pusht
(Schritt 4).

## Decision-Log

**Format, Dateiname und Ablage im Repo folgen der `docs/decisions/README.md` des jeweiligen
Consumers** — der kanonischen Decision-Log-Konvention (MADR-Light), abgeleitet aus dem
Playbook-Skelett
[templates/docs/decisions-README.md](https://github.com/ww3d/playbook/blob/main/templates/docs/decisions-README.md)
(im Playbook, nicht im Consumer). Am Repo lesen, nicht annehmen; die Format-Details (vier
Pflicht-Sektionen plus eine optionale, Dateiname-Schema) hier nicht doppeln. Default-Ablage ist
`docs/decisions/`; fuehrt das Repo gar keine Logs, keins erzwingen.

Das Log nennt im Kopf, was die Runde vollstaendig gelesen hat: jede genannte Referenz, jedes
Schwester-Repo, das nach demselben Mechanismus abgesucht wurde, und das Ergebnis des Schnell-Checks
aus Schritt 0 als eine Zeile.

**Auflagen gehoeren an den Mechanismus, nicht nur ins Log.** Haelt die Design-Runde eine Bedingung
fest, die erst bei einer spaeteren Erweiterung greift ("bei Aktivierung Pflicht: …"), steht sie
zusaetzlich dort, wo diese Erweiterung ansetzt — im Body des Tracking Issues oder an der
Roadmap-Zeile des Mechanismus. Wer spaeter erweitert, liest die, nicht das Log der Runde davor
(`docs/decisions/README.md` § "Auflagen und Traeger").

**Das Log der laufenden Runde traegt am Ende die Nachtraege der Review-Runden.** Es entsteht vor dem
PR und muss dessen Endstand tragen; die Runden liegen nach seiner Niederschrift. Der festgehaltene
Entscheidungstext bleibt verbatim, der Abschnitt `## Nachtraege aus den Review-Runden` kommt
abgesetzt darunter (`docs/decisions/README.md` § Immutabilitaet).

Das Log liegt auf dem Zweig, den die Design-Session pusht, und damit im PR — ein Reviewer zieht es
von dort (nicht vom User weitergereicht).

## Zeilen-Datei

Am Ende jeder Runde schreibt die Design-Session neben das Log eine Zeilen-Datei
`docs/decisions/<stempel>-<slug>-ledger.jsonl`, eine Datei je Runde, mit demselben Stempel wie das
Log. Je Punkt der Runde eine JSON-Zeile: `id`, `status` (`angenommen` / `verworfen` /
`zurueckgestellt` / `ersetzt` / `idee`), `satz`, `grund`, `quelle`, wo es passt `thema`,
`neu_nur_mit`, `steht_schon_wo`, `haengt_an`, `prio`. Auch die Ideen aus "Was uns abheben koennte"
stehen dort mit ihrem Status.

- **Skript fahren:** `pwsh scripts/common/test-ledger.ps1 -Path <datei>` — prueft jede Zeile gegen
  `scripts/common/ledger.schema.json` und nennt Datei:Zeile je Verstoss.
- **Ohne pwsh:** jede Zeile ist ein eigenes JSON-Objekt, die fuenf Pflichtfelder sind da, `status`
  ist einer der fuenf Werte, kein anderer Schluessel als die oben genannten.

Ein Punkt mit `verworfen` traegt in `neu_nur_mit`, welches neue Argument ihn wieder aufmachen
darf. `scripts/common/get-rejected-points.ps1` erzeugt daraus die Liste, die die naechste Runde
vor dem Fragen liest (Schritt 1).

## Ablage per Push

Log, Zeilen-Datei und Spec-Datei gehen als Commits auf einen Zweig des Ziel-Repos, nie als Datei
in den Chat:

- **Claude Code:** `git switch -c <zweig>`, committen, `git push -u origin <zweig>`.
- **Claude Web (GitHub-Connector):** `create_branch`, dann `push_files` mit allen drei Dateien in
  einem Commit.

Zweigname nach `.agents/rules/pr.md` § "Branch Naming", in der Regel `docs/<issue>-<slug>`.

## Rueckfall ohne Schreibzugang

Nur wo die Design-Session nicht ins Ziel-Repo pushen kann, gehen die Artefakte als **Output-Datei**
raus (`create_file` + `present_files`), nie als Chat-Block — Chat-Text ist ein lossy Kanal. Dann
gilt:

| Art           | Dateiname                          |
|---------------|------------------------------------|
| Spec-Datei    | `YYYY-MM-DDTHHMMZ-spec.md`         |
| Decision-Log  | `YYYY-MM-DDTHHMMZ-decision-log.md` |
| Zeilen-Datei  | `YYYY-MM-DDTHHMMZ-ledger.jsonl`    |

- Zeitstempel nach `.agents/rules/docs.md` § "Timestamps in File Names"; die Endung bleibt dran,
  sonst verliert der Client beim Download die Typ-Erkennung.
- Ein Artefakt pro Datei — nie zusammengelegt.
- Jede Markdown-Datei beginnt mit der Marker-Zeile `<!-- transport: verbatim, do not re-render -->`,
  danach folgt direkt der Inhalt. **Kein Fence um den Inhalt** — er kostet in einer Datei nur die
  Vier-Backtick-Regel, sobald der Inhalt selbst einen Codeblock enthaelt.
- **Transport und Ablage sind zwei Dinge.** Der Chat-Dateiname ist reiner Transport; wer pusht,
  legt den Inhalt unveraendert unter dem Repo-Dateinamen ab (Spec: `docs/tasks/<issue>-<slug>.md`,
  Log und Zeilen-Datei nach der Consumer-Konvention).
- **Uebergabe:** Datei herunterladen und **als Datei anhaengen**, nicht den Inhalt hineinkopieren —
  Copy-Paste ueber gerenderten Chat zerstoert das Markdown.
