# Roadmap — Markdown Workbench

Stand: 2026-10-25T0150Z, am Kopf `aabccff` von `main` (Playbook 24.15.0, Version 0.35.1). Gelesen:
alle offenen Issues und PRs von ww3d/markdown-workbench samt allen Kommentaren der PRs
[ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) und
[ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (nur Bot-Konten;
die Entscheide des Menschen stehen dort als Nachtraege), die Tracking-Issues mit Kommentaren,
`backlog.md`, `docs/DECISIONS.md`, `docs/ARCHITECTURE.md` (nur die Marker), das State Audit
[ist-stand-2026-09-27T2058Z.md](../audit/ist-stand-2026-09-27T2058Z.md), die Fragen-Seite und die
Roadmap-Daten der Seite (ww3d/rc-control, Branch `pages`), die frueheren Fassungen und Funde der
Recherche (Roadmap vom 2026-10-02, Nachsuche vom 2026-09-28, Ueberblick, Trockenlauf, Verlust,
ruhende Repos). Bis zu dieser Datei gab es im Repo keine Roadmap (kein `docs/roadmap.md`, kein
`docs/roadmap/`, kein `ROADMAP.md`); die Fassung vom 2026-10-02 lag nur ausserhalb des Repos.

## Auf einen Blick

- Stand: 0.35.1 ist auf `main`. Zwei grosse PRs warten seit dem 2026-09-30 (#91) und 2026-10-02
  (#98) auf die Sichtabnahme des Maintainers; ein OK auf #98 gilt fuer beide. Seit dem 2026-10-02
  gibt es keinen Controller fuer dieses Repo.
- Laeuft: nur diese Roadmap
  ([ww3d/markdown-workbench#146](https://github.com/ww3d/markdown-workbench/pull/146), Doku-PR).
- Als Naechstes: Sichtabnahme, Merge von #91, Basis von #98 auf `main`, zwei volle Laeufe, frischer
  Reviewer, Merge von #98. Danach in dieser Reihenfolge (Vorschlag, nicht entschieden):
  #145, #140, #144, #132, #102, dann die Design-Runden #93, #49, #56, zuletzt #17 und #4.
- Offen beim Maintainer: (1) Sichtabnahme von #91 und #98; (2) Entscheid zu P3, P6 und zur
  Build-Kennung; (3) Besetzung und Start eines Controllers, Reihenfolge danach; (4) Freigabe von
  `@vscode/test-electron`; (5) Grenzfall "Ausnahme beim Speichern"; (6) Lesart zu `.claude/` in #132.
  Ausfuehrlich unter "Wartet auf dich, ausfuehrlich".

## Scheiben

| Scheibe | Tracking Issue | Stand |
|---|---|---|
| Tabellen bearbeiten (Enter, Tab, Pfeile, Sortieren, Einfuegen) | [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90) | gebaut (PR #91), wartet auf Sichtabnahme |
| Webview in Module teilen, TypeScript 7 | [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) | gebaut (PR #98), wartet auf Sichtabnahme und drei Entscheide |
| Luecken-Audit zum TypeScript-Umzug | [ww3d/markdown-workbench#97](https://github.com/ww3d/markdown-workbench/issues/97) | geliefert in PR #98, schliesst mit dessen Merge |
| `build.ps1` ohne globales pnpm | [ww3d/markdown-workbench#103](https://github.com/ww3d/markdown-workbench/issues/103) | gebaut (PR #104, im Branch von #98), `main` bekommt es mit #98 |
| Tests auf Testuhr (Playbook 24.11.0) | [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132) | geplant, nichts gebaut |
| Abhaengigkeiten auf neueste Version, Build-Warnungen | [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145) | geplant, nichts gebaut |

## Einfache Liste

Laeuft gerade

- [ww3d/markdown-workbench#146](https://github.com/ww3d/markdown-workbench/pull/146) (diese Roadmap)

Wartet auf dich

- [ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen bearbeiten, Sichtabnahme)
- [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Module und TypeScript 7, Sichtabnahme; P3, P6, Build-Kennung)
- [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) (Tracking: die Entscheide stehen dort als Kaestchen)

Danach, der Reihe nach (Vorschlag, die Reihenfolge ist nicht entschieden)

1. [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145) (alle Abhaengigkeiten auf die neueste Version, Antwort auf #105)
2. [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) (Playbook-TypeScript-Baseline; am Kopf fast erfuellt)
3. [ww3d/markdown-workbench#144](https://github.com/ww3d/markdown-workbench/issues/144) (Repo-Root an die Root-Liste des Playbooks angleichen)
4. [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132) (Tests auf Testuhr)
5. [ww3d/markdown-workbench#102](https://github.com/ww3d/markdown-workbench/issues/102) (Tests nur unter `artifacts/tmp/<lauf>/`)
6. [ww3d/markdown-workbench#93](https://github.com/ww3d/markdown-workbench/issues/93) (Clipboard-Diff: Hunk in beide Richtungen)
7. [ww3d/markdown-workbench#49](https://github.com/ww3d/markdown-workbench/issues/49) (Canvas-Minimap statt DOM-Klon)
8. [ww3d/markdown-workbench#56](https://github.com/ww3d/markdown-workbench/issues/56) (Mehrfachauswahl fuer Tabellen-Checkboxen)
9. [ww3d/markdown-workbench#17](https://github.com/ww3d/markdown-workbench/issues/17) (eigener Markdown-Formatter)
10. [ww3d/markdown-workbench#4](https://github.com/ww3d/markdown-workbench/issues/4) (Learn-Markdown 1:1 abgleichen)

---

# Ausfuehrliche Fassung (fuer Controller und Sessions)

Entscheidungen des Menschen stehen auf der Fragen-Seite (ww3d/rc-control, Branch `pages`,
`pages/fragen/db/questions/`); wo eine Quelle ihnen widerspricht, gilt die Antwort. In den
Issues und PRs dieses Repos schreibt `ww3d` selbst nicht: jeder Entscheid des Menschen steht als
Nachtrag "Entscheid des Maintainers" des Kontos `ww3-claude-bot`. Merge-Regel des Maintainers
(2026-09-30T0115Z, zitiert in [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92)):
Der Controller merged alles ausser #91 und #98, die der Maintainer vorher visuell abnimmt; ein OK
auf #98 reicht fuer beide (Entscheid 2026-09-29T2248Z: Reihenfolge #94, #91, #92, die Einzelpruefung von
#91 und #94 entfaellt, das TypeScript-Release wird als Ganzes abgenommen).
Dauerhafte Freigabe des Maintainers (2026-09-28T0926Z,
[ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90)): alle Abhaengigkeiten
auf dem neuesten Stand halten; ein Major-Sprung bleibt ein eigener Commit mit eigenem Testlauf.

## Wartet auf dich, ausfuehrlich

- `[!]` ENTSCHEIDUNG **Sichtabnahme von #91 und #98**
  ([ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen bearbeiten),
  [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Module, TypeScript 7)).
  Testliste: [Kommentar 5937317030](https://github.com/ww3d/markdown-workbench/issues/92#issuecomment-5937317030)
  (45 Faelle: 89-1 bis 89-15, 91-1 bis 91-15, 91-s1 bis 91-s15; 89-1 bis 89-6 sind schon geprueft; die
  im Body genannte Ergaenzung um #92, #94, #97 fehlt in der geborgenen Fassung) und
  [Kommentar 5937409776](https://github.com/ww3d/markdown-workbench/issues/92#issuecomment-5937409776)
  (98-1 bis 98-17). Das `.vsix` vom Kopf `b66b473` (0.37.0, SHA-256
  `8901523fb744fd0ff7ecd1a2104c81643167e524b1f6e15bdcbd86cc9d179521`) liegt nur lokal (F-3).
  Traeger: Kaestchen in [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92)
  und [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90).
- `[!]` ENTSCHEIDUNG **P3, Start der Webview** (Ziel "hoechstens Basis, Ziel -15 %", REQ-049 steht
  auf `nicht geliefert`). Entscheid des Maintainers 2026-09-30 ([Kommentar 5910756018](https://github.com/ww3d/markdown-workbench/pull/98#issuecomment-5910756018)):
  Option 3 zuerst, dieselbe Messung ruhiger beim Windows-Lauf am Merge-Kopf, danach entscheidet er;
  P3 wird bis dahin weder gestrichen noch angenommen. Option 2 (-15 % als eigenes Issue) ist
  davon unabhaengig und nicht entschieden. Beide bisherigen Windows-Laeufe liefen unter Last (CPU
  50 bis 98 %, [Kommentar 5917752066](https://github.com/ww3d/markdown-workbench/pull/98#issuecomment-5917752066):
  "nicht ruhig"). Traeger: Kaestchen in [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92);
  die ruhige Messung steht auch im Merge-Weg (Windows-Lauf am Merge-Kopf).
- `[!]` ENTSCHEIDUNG **P6, Laufzeit von `pnpm test`** (Ziel Basis + 10 %): Windows +35 % (8,05 s auf
  10,87 s, 1018 statt 798 Tests), Linux +1,5 %; Optionen: annehmen (Empfehlung des Controllers) oder
  Laufzeit nachbessern ([Kommentar 5920810826](https://github.com/ww3d/markdown-workbench/pull/98#issuecomment-5920810826)).
  Traeger: Kaestchen in [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92).
- `[!]` ENTSCHEIDUNG **Build-Kennung** fuer den Neustart ohne neues Rendern: Frage des Controllers
  [Kommentar 5904772662](https://github.com/ww3d/markdown-workbench/pull/98#issuecomment-5904772662).
  Traeger: Kaestchen in [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92).
- `[!]` ENTSCHEIDUNG **Besetzung und Start eines Controllers, Reihenfolge danach.** Es gibt seit
  2026-10-02 keinen Controller fuer dieses Repo. Plan p110 (#98) und p111 (#91) der Seite:
  "besetzen oder ruhen lassen"; q110 (Antwort `teil`, 2026-10-18): Plaene fuer limen, atlas, win-util und
  markdown-workbench werden vor jedem Start vorgelegt; q223 (Antwort "b"): markdown-workbench nach
  limen und atlas; q307 (2026-10-24): ein Controller startet erst auf das Wort des Menschen;
  [ww3d/rc-control#294](https://github.com/ww3d/rc-control/issues/294) (Reihenfolge des Menschen
  2026-10-21T1009Z: Controller fuer limen, win-util und markdown-workbench erst danach und nur auf sein
  Wort). Auch die Reihenfolge der Punkte nach den Merges (siehe "Einfache Liste") ist nicht entschieden;
  die Anordnung 2026-10-01T2307Z "alles bauen" und der Halt 2320Z gelten laut q110 nicht mehr.
  Traeger: diese Zeile.
- `[!]` ENTSCHEIDUNG **Freigabe fuer `@vscode/test-electron` 3.1.0** (Dev-Abhaengigkeit der
  Integrationstests) trotz "keine zusaetzlichen Abhaengigkeiten" aus #82: Freigabe nicht gefunden
  (Nachsuche 2026-09-28, Trockenlauf N-mw3). Die dauerhafte Freigabe oben gilt fuer das Aktualisieren,
  nicht fuer eine neue Abhaengigkeit. Traeger: diese Zeile.
- `[!]` ENTSCHEIDUNG **Grenzfall "Ausnahme bei gescheitertem Speichern"** gegen die Zusage "nichts
  auf die Platte" ([ww3d/markdown-workbench#82](https://github.com/ww3d/markdown-workbench/issues/82)
  (geschlossen), [ww3d/markdown-workbench#88](https://github.com/ww3d/markdown-workbench/issues/88)):
  gemeldet in der Nachsuche 2026-09-28, ein Entscheid ist nicht gefunden. Traeger: diese Zeile.
- `[!]` ENTSCHEIDUNG **Lesart zu `.claude/` in #132:** siehe W-7. Traeger:
  [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132).
- `[!]` ENTSCHEIDUNG **Formatter (#17):** die Vorschlaege (Listen-Ausrichtung, listenbewusster harter
  Umbruch, Hinweis auf zu lange Zeilen statt MD013) sind nicht freigegeben, die Design-Runde
  entscheidet einzeln; "Prosa-Reflow verbindlich" gilt seit 2026-09-27.
  Traeger: [ww3d/markdown-workbench#17](https://github.com/ww3d/markdown-workbench/issues/17).
- `[!]` ENTSCHEIDUNG **Clipboard-Diff (#93):** `diffEditor/gutter/hunk` ist laut Issue noch
  `proposed: 'contribDiffEditorGutterToolBarMenus'`, also nicht veroeffentlichbar; zuerst klaeren.
  Traeger: [ww3d/markdown-workbench#93](https://github.com/ww3d/markdown-workbench/issues/93).

## Jetzt

Es laeuft kein Worker; die Arbeit steht fertig und wartet auf Entscheide.

- `[~]` DOKU Diese Roadmap: [ww3d/markdown-workbench#146](https://github.com/ww3d/markdown-workbench/pull/146).
- `[=]` FEATURE [ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen
  bearbeiten): Branch `claude/rc-control-dev-mw-90-wixrob`, Kopf `f922dde`, Basis `main`, bereit; Review
  `hard v4`, Re-Review ohne blockierenden Punkt; Windows-Lauf am Kopf gruen (826 von 826), Linux-Lauf
  des Autors fuer den Kopf davor (`eb9d321`; am Kopf nur format und gefilterte Tests nach freigegebener
  Abweichung); `Closes #86`, `Refs #90`; letzte Bewegung 2026-09-30T0944Z. Der Zweig steht `behind`
  `main` (36 Commits auf `main` seit dem Kopf), das heisst: vor dem Merge Nachzug und neuer voller Lauf.
  Bringt 0.36.0 und `docs/DECISIONS.md` #49. Wartet auf die Sichtabnahme.
- `[=]` SCHULD [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Module und
  TypeScript 7): Branch `feat/typescript-webview`, Kopf `b66b473`, **Basis ist der Branch von #91**,
  bereit; drei Review-Wellen `hard v4` (Welle 1 auf `6b459db`, Welle 2 auf `e738c3d`, Folgewelle 3
  auf die Atlas-Commits) und sechs Runden von `rev-mw-98`; zwei Windows-Laeufe (`fdc447a`, `d2e4033`),
  am Kopf `b66b473` kein voller Lauf; `Refs #92`, `Closes #2`, `Closes #97`; letzte Bewegung
  2026-10-02T1022Z. Enthaelt PR #104 (Atlas-Bootstrap, `Build.cmd` und `build.sh`, Fix zu #103) und
  das Audit vom 2026-09-29T2304Z; bringt 0.37.0, `docs/DECISIONS.md` #50 und #51.
- Merge-Weg (Maintainer-Regel oben): #91 mergen, Basis von #98 auf `main` umstellen, beide vollen
  Laeufe am neuen Merge-Kopf (Linux im Web, Windows lokal; dabei die ruhige P3-Messung), Hard-Gate
  durch einen frischen Reviewer, Merge von #98. Traeger: Kaestchen in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) und das
  Merge-Gate-Kaestchen in [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90).

## Als Naechstes

Nach den Merges von #91 und #98, in der Reihenfolge der "Einfachen Liste" (Vorschlag):

- `[ ]` BETRIEB [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145)
  (Abhaengigkeiten auf die neueste Version, Build-Warnungen; Antwort auf
  [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105)): von dieser
  Roadmap angelegt, drei Kaestchen. Die Zeile nennt als bekannte Ausnahme `@types/vscode` (siehe W-10).
- `[ ]` SCHULD [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140)
  (Playbook-Baseline: Node 24, pnpm ueber `packageManager`, Biome fuer Code, JSON und CSS, Prettier nur
  fuer Markdown und YAML): vier Kaestchen offen. Am Kopf von `main` geprueft (`package.json`,
  `biome.json`): pnpm ueber `packageManager` `pnpm@12.6.0` steht; Biome 2.5.14 mit `lint`, `format`
  und `format:fix` und Prettier 3.9.9 nur fuer `**/*.{md,yml,yaml}` stehen; Node 24 ist nicht erfuellt,
  `engines.node` steht auf `>=26` (benannter Override in `CLAUDE.md`, siehe W-3). Drei Kaestchen sind
  damit erfuellt, aber nicht abgehakt. Herkunft: Frage q160 (Antwort `issue`), ww3d/playbook#415.
- `[ ]` SCHULD [ww3d/markdown-workbench#144](https://github.com/ww3d/markdown-workbench/issues/144) (Root
  weicht von der Root-Liste ab, zwoelf Funde; Playbook-Sync): der Trockenlauf verschiebt
  `backlog.md` nach `docs/backlog.md`, `audit/` nach `docs/audit/` und `tech/common/*` nach `.agents/tech/*`,
  entfernt `.playbook-version` und schreibt `CLAUDE.md:2` um; noch nicht ausgefuehrt. Fuer acht Pfade
  verschiebt er nichts und verlangt einen Eintrag (Pfad, Grund, Traeger) in
  .agents/config/root-layout.json oder einen Umzug: `.vscodeignore`, `CONTRIBUTING.md`, `bench/`,
  `build.ps1`, `media/`, `pnpm-workspace.yaml`, `publish.ps1`, `tsdown.config.ts`. Der Link auf das
  Audit in dieser Datei und in `backlog.md` zieht beim Umzug mit.
- `[ ]` TEST [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132) (Tests auf
  Testuhr, Tracking Issue): drei Kaestchen (Fundstellen erheben, umbauen, Echtzeit-Gruppe). Grenze des
  Maintainers 2026-10-21T1417Z: "die 20 kommentare sollten reichen!!!"; die Lesart zu `.claude/` ist
  offen (W-7).
- `[ ]` TEST [ww3d/markdown-workbench#102](https://github.com/ww3d/markdown-workbench/issues/102) (Tests nur
  unter `artifacts/tmp/<lauf>/`): drei Kaestchen. Herkunft ww3d/playbook#327; der genannte Anker
  ww3d/playbook#348 ist geschlossen.
- `[ ]` FEATURE [ww3d/markdown-workbench#93](https://github.com/ww3d/markdown-workbench/issues/93)
  (Clipboard-Diff: Pfeile in der Mitte je Block in beide Richtungen, klickbarer Hinweis, Knopf am
  Cursor, Sprung zum naechsten Unterschied; alle drei Varianten freigegeben, Wunsch 2026-09-28T1219Z):
  vier Kaestchen, erst die Design-Runde nach dem Merge (q227). Offene Frage: siehe oben.
- `[ ]` FEATURE [ww3d/markdown-workbench#49](https://github.com/ww3d/markdown-workbench/issues/49)
  (Canvas-Minimap statt DOM-Klon, Messung vorher und nachher; der Minimap-Code zieht mit #98 in Module
  um). `content-visibility: auto` nur messungsgetrieben: gemessen und verworfen in
  `docs/DECISIONS.md` #47, Wiedervorlage hier.
- `[ ]` FEATURE [ww3d/markdown-workbench#56](https://github.com/ww3d/markdown-workbench/issues/56)
  (Mehrfachauswahl und ein Klick fuer Checkboxen in Tabellenzellen, ein Undo-Schritt; haengt an #91
  und #98). Der Body plant es "hinter #49".
- `[ ]` DOKU [ww3d/markdown-workbench#106](https://github.com/ww3d/markdown-workbench/issues/106) (die drei
  Design-Auftraege fuer #93, #49, #56 liegen nur auf dem Branch `chore/ctrl-mw-10-orders`, Kopf
  `697b6f5`; sechs Kaestchen: Design-Runden, Auftraege nachziehen, danach #17 und #4 einplanen, Branch
  loeschen). Die Auftraege nennen noch `ctrl-markdown-workbench-10` und tragen den "Es gilt wie immer"-Block
  nicht (Trockenlauf V-M21).
- `[ ]` FEATURE [ww3d/markdown-workbench#17](https://github.com/ww3d/markdown-workbench/issues/17) (eigener
  Formatter: Marker-Abstand, Tabellen, Listen-Einrueckung, harter Prosa-Umbruch bei 100 Spalten;
  haengt an #91; drei Kaestchen; verwandt ww3d/playbook#333, dort geschlossen).
- `[ ]` FEATURE [ww3d/markdown-workbench#4](https://github.com/ww3d/markdown-workbench/issues/4)
  (Learn-Markdown 1:1 abgleichen, plattformgebundene Funktionen einzeln zur Entscheidung; haengt an der
  Modulstruktur aus #98). Der Body nennt noch `src/editing.js` (W-9).

## Spaeter

- `[ ]` TEST Eigenes Issue fuer das P3-Ziel "-15 %", falls der Maintainer P3 nicht annimmt (Option 2
  oben); im Body von #92 erwaehnt, nicht angelegt. Traeger: diese Zeile.
- `[ ]` FEATURE Learn-Markdown "Convert table to data matrix": Abgleich in
  [ww3d/markdown-workbench#4](https://github.com/ww3d/markdown-workbench/issues/4).
- `[ ]` TEST Tests fuer 26 ungetestete Architektur-Aussagen und zwei veraltete Kommentare im Code
  (`scrollSpy`-Kopfkommentar in `media/webview.js`, Fold-Testkommentar mit 120-ms-Takt in
  `tests/webview.test.js`): Traeger sind zwei Zeilen in `backlog.md`; laut #97 mit #98 geliefert, am Kopf
  von `main` offen.
- Ausserhalb des Umfangs (`docs/DECISIONS.md` #22): relative lokale Bilder, Mermaid und Math, genaues
  Nutzer-Theme fuer Shiki, strikte CSP (die Vorschau rendert eigene Dateien mit `html: true` und
  aktiven Skripten), Chrome-Minimap-Erweiterung (erkundet, zurueckgestellt).

## Fertig (seit dem State Audit 2026-09-27T2058Z)

- `[x]` BETRIEB PR #84 (Node 26, pnpm, kanonischer CI-Check, Abhaengigkeiten, gemergt 2026-09-27);
  Issue #85 (pnpm kam mit #84, not_planned).
- `[x]` DOKU PR #87 (das State Audit selbst); Issue #73 (completed, 2026-09-27).
- `[x]` FEATURE PR #89 (Clipboard-Diff, 0.35.0, 2026-09-28) samt Tracking Issue #88 und Issue #82.
- `[x]` FEHLER PR #100 (Fix zu Issue #94, 0.35.1, 2026-09-30) samt Issue #94.
- `[x]` BETRIEB PR #108 und #113 (Testfelder in `CLAUDE.md`); Playbook-Sync-PRs, zuletzt #143.
- `[x]` Im Branch von #91, nicht auf `main`: PR #99 (Audit auf dem Tabellen-Kopf).
- `[x]` Im Branch von #98, nicht auf `main`: PR #104 (Fix zu #103, Atlas-Bootstrap; Entscheid des
  Maintainers 2026-10-02T0850Z "alle Abweichungen angleichen, mit Bootstrap").
- `[x]` SCHULD Overlay-Abweichungen aus `backlog.md` (npm statt pnpm, CI auf Node 22, Biome und Prettier,
  Repo-Werkzeug im `.vsix`): erledigt mit #84, die Zeilen stehen durchgestrichen.

## Gestrichen

- `[-]` FEATURE Block-Delta, Entprellen beim Tippen und Abloesung von `retainContextWhenHidden`
  (Entscheid des Maintainers 2026-09-29T2303Z, [Kommentar 5900738178](https://github.com/ww3d/markdown-workbench/issues/92#issuecomment-5900738178):
  "nicht aufgenommen", nichts davon wird gebaut; Traeger
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92)).
- `[-]` FEATURE `content-visibility: auto` im Zuge von #92 (verworfen mit Beleg, `docs/DECISIONS.md`
  #47; Wiedervorlage bei [ww3d/markdown-workbench#49](https://github.com/ww3d/markdown-workbench/issues/49)).

## Funde

Kennung F-n, je mit Traeger oder Beleg.

- **F-1** `[ ]` BETRIEB Das State Audit ist faellig: `scripts/common/get-audit-due.ps1` meldet "full
  audit due (c)", weil das Audit vom 2026-09-27T2058Z unter `**Commit:**` keinen Commit nennt
  (Schwelle 30 gemergte PRs). Das neuere Audit vom 2026-09-29T2304Z liegt nur im Branch von #98.
  Traeger: diese Zeile.
- **F-2** `[ ]` BETRIEB Branches als einzige Traeger: `chore/rev-mw-98-review-report` (nach dem Merge von
  #98 loeschen), `chore/atlas-reference-transport` (nach dem Merge loeschen),
  `claude/design-mw-ts7-i7272u` (erst nach dem Merge entscheiden), `chore/ctrl-mw-10-orders` (siehe
  #106). Traeger: Kaestchen in [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92)
  und [ww3d/markdown-workbench#106](https://github.com/ww3d/markdown-workbench/issues/106) (Trockenlauf V-M20).
- **F-3** `[ ]` BETRIEB Sichtabnahme-Material nur lokal: in `D:\users\agt01\rc-control\work\abnahme-mw\`
  liegen `markdown-workbench-pr98-b66b473.vsix` (aktuell) und `markdown-workbench-pr98-d2e4033.vsix`
  (Trockenlauf V-M22). Geht mit dem Ordner verloren. Traeger: diese Zeile.
- **F-4** `[ ]` BETRIEB [ww3d/markdown-workbench#103](https://github.com/ww3d/markdown-workbench/issues/103)
  (`build.ps1` ohne globales pnpm): gebaut als PR #104, im Branch von #98. Zwei Kaestchen offen: `main`
  bekommt den Fix erst mit dem Merge von #98 (bis dahin bricht `build.ps1` auf `main` ohne globales
  pnpm), und "Workers abraeumen" (nur der Ordner von `dev-mw-104d` liegt noch).
- **F-5** `[ ]` DOKU Der Override "projekt-eigener CI" in `CLAUDE.md` nennt weder Traeger noch
  `permanent`; den Kanon-Check-Namen faehrt der Workflow seit #84. Traeger: Zeile in `backlog.md`.
- **F-6** Die zwei Funde der Nachsuche 2026-09-28 (Code-Ort `src/tables/` und `src/editing/` statt
  `src/editing.js` aus #86; Tabellen-Erkennung ueber den markdown-it-Block-Parse statt D1 des Decision-Logs
  zu #86) hat der Maintainer am 2026-09-29T2248Z mit "behalten" entschieden
  ([Kommentar 5900560550](https://github.com/ww3d/markdown-workbench/pull/91#issuecomment-5900560550)).
  Nichts zu tun; Beleg gegen ein Zurueckbauen.
- **F-7** Das Archiv der Recherche zu diesem Repo bleibt (Maintainer "behalten", 2026-09-29T2248Z,
  Trockenlauf N-mw1-2). Nichts zu tun.
- **F-8** `[ ]` BETRIEB Plan-Daten der Seite fuer dieses Repo (`repoplan`): Rang 8, gleichzeitig 2,
  "Plan-JSON ohne Schritte und Ist" (Ueberblick 2026-10-25T0036Z). Die Plaene p110, p111, p180, p285,
  p286 haben `repo = markdown-workbench`; sie verweisen auf #98, #91, #140, #105, #106. Traeger:
  diese Zeile.
- **F-9** `[ ]` BETRIEB Niedrig gewichtete Funde aus dem Verlust-Bericht 2026-10-14: Lehren aus der
  Abgabe von `ctrl-markdown-workbench-12`; Web-Sessions dieses Repos stehen in `rc list --all` ohne
  Archiv. Traeger: diese Zeile.

## Widersprueche

Je einer eine Zeile, nicht geglaettet.

- **W-1** [ww3d/markdown-workbench#97](https://github.com/ww3d/markdown-workbench/issues/97) ist offen, hat aber
  56 abgehakte und 0 offene Kaestchen. `Closes #97` steht im Body von #98: es schliesst mit dessen
  Merge. Traeger: [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98).
- **W-2** Plan p159 der Seite sagt, ww3d/playbook#336 (Konsumenten-Datei markdown-workbench.yml von
  javascript auf typescript) warte auf den "Merge von markdown-workbench#2". #2 ist ein Issue, kein PR,
  und schliesst erst mit dem Merge von #98 (`Closes #2`). Traeger:
  [ww3d/markdown-workbench#2](https://github.com/ww3d/markdown-workbench/issues/2) und ww3d/playbook#336.
- **W-3** [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) verlangt Node 24,
  `CLAUDE.md` § "Project-Specific Overrides" setzt Node 26 (bis ww3d/playbook#334, laut Plan p160 wartet
  das bis 2026-10-28). Drei der vier Kaestchen sind am Kopf erfuellt (siehe "Als Naechstes"). Traeger:
  #140.
- **W-4** Das Kaestchen "Windows-Lauf" in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) nennt den zweiten Lauf
  noch "vorgemerkt in der Slot-Schlange", obwohl er gruen lief (`d2e4033`); offen bleibt der Lauf am
  endgueltigen Merge-Kopf.
- **W-5** [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) hat als Basis den Branch
  von #91, nicht `main`; der Merge-Weg stellt sie nach dem Merge von #91 um.
- **W-6** [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) und
  [ww3d/markdown-workbench#144](https://github.com/ww3d/markdown-workbench/issues/144) tragen kein Label
  `tracking`; #144 steht in keinem Plan der Seite. Traeger sind die offenen Issues selbst.
- **W-7** [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132): der Maintainer
  schrieb zwei Saetze, "die 20 kommentare sollten reichen!!!" und "dass sachen unterhalb .claude angefasst
  werden sollte klar sein!". Die Lesart des Orchestrators im Body ist: nichts unter `.claude/` gehoert zum
  Umbau (`.claude/hooks/**` ist eine Playbook-Kopie). Der zweite Satz laesst sich auch als "Hook-Tests
  werden angefasst" lesen; ein Entscheid ist nicht gefunden. Traeger: #132 (Lesart bestaetigen).
- **W-8** [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105) (vom Menschen
  2026-10-04 angelegt, 0 Kommentare) hatte keine Kaestchen; q227 sagt, #105 "bekommt dabei eine Antwort und
  einen Auftrag". Neuer Traeger: [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145);
  #105 selbst bleibt unberuehrt offen.
- **W-9** [ww3d/markdown-workbench#4](https://github.com/ww3d/markdown-workbench/issues/4) und
  [ww3d/markdown-workbench#86](https://github.com/ww3d/markdown-workbench/issues/86) nennen noch
  `src/editing.js`; auf `main` gibt es die Datei, mit #91 wird daraus `src/editing/` und `src/tables/`
  (Entscheid "behalten", F-6). Traeger: beide Issues, Text mit dem Merge von #91 nachziehen.
- **W-10** `@types/vscode` bleibt auf 1.100.0 (passend zu `engines.vscode`, `docs/DECISIONS.md` #50),
  waehrend [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105) "ausnahmslos
  alle" auf der neuesten Version verlangt; `pnpm outdated` am Kopf von #98 meldet nur
  `@types/vscode 1.100.0 -> 1.138.0` (benannte Ausnahme REQ-010). Traeger:
  [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145) (ob die
  Ausnahme bleibt, steht dort als Frage; die Ausnahme selbst ist in #98 als REQ-010 begruendet).
- **W-11** Reihenfolge von #56 und #49: der Controller-Status auf #92 nennt "#56 vor #49", der Body von
  #56 plant es "hinter #49" ein; diese Roadmap folgt dem Body. Traeger:
  [ww3d/markdown-workbench#56](https://github.com/ww3d/markdown-workbench/issues/56).
- **W-12** P3-Zahlen widersprechen sich zwischen den Quellen: +1,0 % (2 x 21 Laeufe, Head `36bde92`),
  +3,0 % (5 x 21 Laeufe, Linux) und +1,2 % (Windows, Kopf `fdc447a`, unter Last); der PR-Body nennt
  "hoechstens Basis" als Ziel, es ist knapp verfehlt. Traeger: Kaestchen in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) (ruhige Messung).
- **W-13** Zustand von [ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91): die
  Seite meldet ihn "seit 24 Tagen unberuehrt" und der Ueberblick nennt ihn bereit; GitHub meldet
  `mergeable_state: behind`, 36 Commits hinter `main`. Bereit ist er fuer die Sichtabnahme, nicht fuer den
  Merge. Traeger: der Merge-Weg oben.
- **W-14** Auftragslage der Design-Runden: Anordnung 2026-10-01T2307Z "alles bauen, nichts verschieben"
  gegen Halt 2320Z (Orchestrator, bis zur Gesamtliste) gegen q227 (Design-Runden erst nach dem Merge) gegen
  q307 (Controller nur auf das Wort des Menschen). Gilt: der Entscheid des Menschen, also q227 und q307.
  Traeger: [ww3d/markdown-workbench#106](https://github.com/ww3d/markdown-workbench/issues/106).

## Zum Schliessen vorgeschlagen

- [ww3d/markdown-workbench#97](https://github.com/ww3d/markdown-workbench/issues/97) mit dem Merge von #98 (W-1).
- [ww3d/markdown-workbench#2](https://github.com/ww3d/markdown-workbench/issues/2) mit dem Merge von #98 (`Closes #2`).
- [ww3d/markdown-workbench#86](https://github.com/ww3d/markdown-workbench/issues/86) mit dem Merge von #91
  (alle Kaestchen abgehakt, `Closes #86`).
- [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90) und
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) erst, wenn alle Kaestchen
  abgehakt sind (offen: 1 bzw. 9); [ww3d/markdown-workbench#103](https://github.com/ww3d/markdown-workbench/issues/103)
  erst nach dem Merge von #98 und dem Abraeumen.
- [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140): die drei erfuellten
  Kaestchen abhaken, das erste (Node 24) als Override mit Traeger ww3d/playbook#334 festhalten.
- [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105) schliesst der Maintainer,
  sobald #145 geantwortet hat.

## Haengt an anderem Repo

- ww3d/playbook#334 (Node-26-Baseline im Overlay, offen): bis dahin gilt der Override in `CLAUDE.md`.
- ww3d/playbook#336 (Konsumenten-Datei auf typescript heben, offen): wartet auf den Merge von #98 (W-2).
- ww3d/playbook#327 (Test aendert nichts ausserhalb seines Ordners, offen laut Roadmap vom 2026-10-02;
  Herkunft von #102); ww3d/playbook#348 (Textwelle, geschlossen) ist nur noch Quelle.
- ww3d/playbook#333 (Umbruchregel an harten Umbruch angleichen, geschlossen 2026-10-02) ist die Regel hinter
  dem Reflow in #17; ww3d/playbook#332 (`get-audit-worklist.ps1` meldet synchronisierten Regeltext als
  Konsumenten-Marker, offen).
- ww3d/playbook#415 (Herkunft von #140) und ww3d/playbook#442 (Umzug der Playbook-Pfade, Quelle von #144).
- `microsoft/vscode`: drei Aussagen des Audits sind `[nicht verifiziert]`, weil sie ein Fremd-Repo
  betreffen; `diffEditor/gutter/hunk` ist dort noch nicht freigegeben (#93).

## Legende

Status: `[ ]` offen - `[~]` in Arbeit - `[x]` fertig - `[!]` wartet auf dich - `[=]` blockiert durch anderen
Punkt - `[-]` gestrichen. Art: FEATURE neue Faehigkeit - FEHLER Fehler beheben - SCHULD aufraeumen oder
umbauen - DOKU Dokumentation - TEST Tests und Qualitaet - BETRIEB Bau, Auslieferung, Laufzeit -
ENTSCHEIDUNG braucht ein Ja oder Nein.
