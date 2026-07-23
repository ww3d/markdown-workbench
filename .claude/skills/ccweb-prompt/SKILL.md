---
name: ccweb-prompt
description: 'Baut den Auftrags-Prompt (in manchen Repos "TASK"), mit dem ein Coding-Agent eine Aufgabe in einem Repo umsetzt und einen Draft-PR oeffnet, und fuellt damit die Vorstufe der `dev`-Rolle des Playbook-PR-Lifecycles. Klaert bei Bedarf offene Entscheidungen in einer Design-Runde, haelt sie in einem Decision-Log fest, laedt den Repo-Kontext aus den Repo-Docs und gibt den fertigen Prompt als 4-Backtick-Block zur Uebergabe aus. Der Prompt setzt nur Environment und Aufgabe — Workflow, PR-Format und Branch-Wahl kennt der Agent aus AGENTS.md/CLAUDE.md. Triggert bei Anfragen wie "prompt fuer ccweb", "bau mir einen task", "handoff fuer [repo]", "prompt fuer issue #N", "prompt generieren", "task.md bauen". Nutzt das GitHub MCP oder `gh`. Nur fuer GitHub-Repos.'
metadata:
  version: "2.4.0"
  source: ww3d/playbook
---

# Agent-Prompt (TASK) bauen

Erzeugt den Prompt, mit dem ein Coding-Agent eine Aufgabe umsetzt. Fuellt die Handoff-Vorstufe der
`dev`-Rolle aus `AGENTS.md` § "PR Lifecycle": der Prompt geht an den Agenten, der Agent (Rolle
`dev`) oeffnet den PR. Dieser Skill oeffnet keinen PR und schreibt keinen Code.

## Kernprinzip

- **Environment, nicht Framework:** Der Prompt setzt Kontext + Aufgabe. Alles, was in AGENTS.md /
  CLAUDE.md steht (Workflow, Commit-/PR-Konvention, Branch-Wahl), gehoert NICHT hinein — der Agent
  kennt es.
- **Docs gewinnen:** Bei Widerspruch Prompt vs. Repo-Docs gewinnen die Docs. Das steht im Prompt und
  gilt beim Bauen genauso — Repo-Fakten werden am Repo verifiziert, nicht aus dem Gedaechtnis gesetzt.
- **Discussion before artifacts:** Kein Prompt vor finalen Entscheidungen. Erst klaeren, dann Log,
  dann Prompt.

## Eingabe

- Ziel-Repo (`owner/repo`) und die Aufgabe (frei oder Issue-Referenz `#N`).
- Fehlt eines: **fragen**, nicht raten.

## Schritt 0: Projekt-Typ pruefen

- **Code-Repo mit Coding-Flow:** normaler Prompt, weiter mit Schritt 1.
- **Reines Design-/Infra-/Doku-Projekt** ohne Coding-Agent-Flow: KEIN Prompt. Stattdessen
  Design-Diskussion + Decision-Log. Hier stoppen und das klarstellen.

## Schritt 1: Design-Runde (bei Bedarf)

Nicht-triviale Aufgaben erst durchentscheiden:

- Ein Thema pro Turn, am Ende "gibt es noch was?". Nicht selbststaendig weiterspringen.
- Ergebnis als Decision-Log (siehe unten), festgeschrieben **bevor** der Prompt entsteht.

## Schritt 2: Repo-Kontext laden

Am echten Repo verifizieren (GitHub MCP oder `gh`), nicht annehmen:

- `CLAUDE.md` + `docs/` (rekursiv) — Stack, Test-Gate, Architektur-Prinzipien, Overrides.
- Issue-/Label-Konvention und den Decision-Log-Ort des Repos (Konvention in `docs/decisions/README.md`
  — siehe unten).
- Betroffene Quell-Files, damit der Prompt sie gezielt benennen kann.
- **Quellen-Erreichbarkeits-Check:** Jede Quelle, die der Prompt referenziert (Issues,
  Decision-Logs, Konventions-Docs, fremde Repos), pruefen: existiert sie, ist sie gemergt/synced,
  und kann die **Ziel-Session** sie erreichen (Repo-Scope, Sandbox-Whitelist der Agent-Umgebung)?
  Unerreichbares wird nicht verlinkt, sondern **inline in den Prompt** uebernommen; der Verweis
  bleibt nur als Herkunftsangabe.

## Schritt 3: Prompt bauen

Der Prompt ist ein **fenced `md`-Block**. Bei Repos mit AGENTS.md / CLAUDE.md beginnt er mit dem
Lese-Auftrag (*"Lies erst CLAUDE.md und alle Dateien unter docs/ rekursiv vollstaendig; bei
Widerspruch Prompt vs. Docs gewinnen Docs."*), danach sieben Bloecke:

1. **Kontext** — Anlass, relevante Issues (*"Lies Issue #N vollstaendig"*).
2. **Aufgabe** — was konkret umzusetzen ist.
3. **Vorgaben** — die Aufgabe als nummerierte Checkbox-Liste `REQ-01`, `REQ-02`, … (ab mehr als 20
   Punkten dreistellig: `REQ-001`). IDs werden hier beim Bau vergeben und ueber alle Review-Runden
   hinweg **nie umnummeriert**. Jedes `REQ-NN` traegt **genau eine widerlegbare Aussage** — deckt
   eine Vorgabe mehrere Oberflaechen, Komponenten oder Lieferungen ab, wird sie beim Bau in mehrere
   REQs aufgeteilt (der Schnitt liegt hier, nicht beim umsetzenden Agent). Der Prompt verpflichtet
   den Agenten, diese Liste unveraendert als GitHub-Tasklist (`- [ ]`/`- [x]`) in den PR-Body zu
   uebernehmen: pro Punkt entweder Haken plus Beleg (Testname, `Datei:Zeile` oder Commit-SHA) oder
   unchecked plus `nicht geliefert: <Grund>` — Haken ohne Beleg und unchecked ohne Grund sind beide
   unzulaessig. Die "nicht geliefert"-Zeile ist ausdruecklich erlaubt und kein Makel.
4. **Vorgehen** — schrittweise (Files sichten, aendern, testen).
5. **Gates** — Akzeptanz als ausfuehrbare Commands + pruefbare Kriterien (Build/Test gruen, keine
   Warnings), passend zum Test-Gate des Repos. Beleg-Pflicht: der Abschluss-Kommentar fuehrt jede
   Erfuellungs-Behauptung mit Test-Namen oder `Datei:Zeile`.
6. **Nicht-Tun** — aufgabenspezifische Scope-Grenze (nur was fuer diese Aufgabe gilt; Generelles wie
   CI-Files oder Dependencies steht schon in AGENTS.md — nicht wiederholen).
7. **Erwartete Observations** — was der Agent im Abschluss-Kommentar meldet, inkl. ehrlicher
   Deklaration, was nicht real lief (fehlendes Docker / CLI / CI / Hardware) statt es zu
   beschoenigen.

**Model-Empfehlung (Pflicht):** In jedem Prompt das passende Modell explizit nennen, soweit der
Harness Modellwahl exponiert (`AGENTS.md` § "Working Mode"). Prinzip: das kleinste/schnellste Modell,
das die Aufgabe noch 100% sauber und SOTA loest. Bei parallelen Sub-Agenten waehlt jeder sein
kleinstes taugliches selbst, die Koordinator-Rolle das staerkste.

## Was NICHT in den Prompt gehoert

Steckt in AGENTS.md / CLAUDE.md — der Agent kennt es:

- Keine PR-Body-Vorlage (der Agent schreibt die Description aus dem Diff).
- Keine Workflow-Boilerplate (Commit-Konvention, kein force-push, Draft-PR, nicht selbst mergen).
- Keine Branch-Namen-Vorgabe — der Agent waehlt selbst, Session startet auf dem Default-Branch.
  Einzige Ausnahme: Abzweig von einem Nicht-Default-Branch (dann Basis explizit nennen).

## Ausgabe

- Standalone-Prompt: inline als **4-Backtick**-Block (der Prompt enthaelt selbst Triple-Backticks).
  Nie ungefragt nach GitHub posten.
- Fix-Anweisung fuer einen offenen PR: als PR-Review-Kommentar (via MCP oder `gh`) nach expliziter
  Freigabe, nicht als Chat-Block.

## Decision-Log

**Format, Dateiname und Ablage folgen der `docs/decisions/README.md` des jeweiligen Consumers** —
der kanonischen Decision-Log-Konvention (MADR-Light), abgeleitet aus dem Playbook-Skelett
`templates/docs/decisions-README.md`. Am Repo lesen, nicht annehmen; die Format-Details (vier
Pflicht-Sektionen plus eine optionale, Dateiname-Schema) hier nicht doppeln. Default-Ablage ist
`docs/decisions/`; fuehrt das Repo gar keine Logs, keins erzwingen.

**Uebergabe als 4-Backtick-Block, nicht als Datei-Download.** Das Log wird im Chat als roher
4-Backtick-Block ausgegeben (getrennt vom Prompt, der ein eigener 4-Backtick-Block ist), damit sein
inneres Markdown roh bleibt und ein Copy-Paste in die Ziel-Session ueberlebt. **Nicht** ueber
`create_file` + `present_files` als `.md` zum Herunterladen liefern: eine im Chat gerenderte
Markdown-Datei verliert beim Kopieren Header/`##`/`---`/Bold, und der Coding-Agent checkt sie dann
zerstoert ein (der Reviewer faengt das als "nicht verbatim", aber die Fehlerquelle liegt hier). Der
User kopiert den Block 1:1 in die ccweb-Session; der Agent legt ihn unveraendert im Repo ab.

Sobald der Agent den Draft-PR geoeffnet hat, liegt das Log im PR — ein Reviewer zieht es von dort
(nicht vom User weitergereicht).

## Strikte Regeln

- Nie einen Prompt unaufgefordert nach GitHub posten. Reine Status-Reads (PR/CI) sind ohne Freigabe ok.
- Neue Code-Level-Namen nicht annehmen — im Prompt offen lassen oder nachfragen. Bestehende
  (Fork-)Identifier nie unaufgefordert umbenennen.
- Verifizieren statt spekulieren: Repo-Fakten kommen aus dem Repo, nicht aus dem Gedaechtnis — und
  jede referenzierte Quelle muss fuer die Ziel-Session erreichbar sein (Schritt 2), sonst inline.
- Decision-Log als roher 4-Backtick-Block, nie als renderbare Download-Datei (verbatim-Erhalt beim
  Copy-Paste).

## Repo-Konventionen

- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); das
  GitHub MCP nur als Fallback oder fuer MCP-only-Tools.
- Rollen getrennt: der Agent oeffnet Draft-PRs (`dev`), der `maintainer` merged
  (`AGENTS.md` § "PR Lifecycle").
