# Roadmap — Markdown Workbench

Stand: 2026-10-25T0133Z, am Kopf `aabccff` von `main` (Playbook 24.15.0, Version 0.35.1). Gelesen: alle offenen
Issues und PRs von ww3d/markdown-workbench samt Kommentaren der Tracking Issues, `backlog.md`,
`docs/DECISIONS.md`, `docs/ARCHITECTURE.md` (nur die Marker), das State Audit
[audit/ist-stand-2026-09-27T2058Z.md](../audit/ist-stand-2026-09-27T2058Z.md), die Fragen-Seite und die
Roadmap-Daten der Seite (ww3d/rc-control, Branch `pages`) sowie die drei Funde-Dateien der
Recherche (Ueberblick, Trockenlauf, Verlust). Bis zu dieser Roadmap gab es keine Roadmap-Datei im Repo
(kein `docs/roadmap.md`, kein `docs/roadmap/`, kein `ROADMAP.md`).

## Auf einen Blick

- Stand: 0.35.1 ist auf `main`. Zwei grosse PRs warten auf die Sichtabnahme des Maintainers:
  [ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen bearbeiten)
  und [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Webview in Module
  teilen, TypeScript 7). Beide sind bereit, keiner hat sich seit dem 2026-10-02 bewegt.
- Laeuft: diese Roadmap ([ww3d/markdown-workbench#146](https://github.com/ww3d/markdown-workbench/pull/146),
  Doku-PR). Sonst laeuft in diesem Repo nichts.
- Als Naechstes: Sichtabnahme, dann Merge von #91, Basis von #98 auf `main`, zwei volle Laeufe, frischer
  Reviewer, Merge von #98. Danach die drei Design-Runden zu #93, #49 und #56.
- Offen beim Maintainer: Sichtabnahme von #91 und #98; Entscheid zu P3 und P6 (Leistungsziele) und zur
  Build-Kennung; Freigabe der Dev-Abhaengigkeit `@vscode/test-electron` (ungeklaert, siehe Funde).

| Scheibe | Tracking Issue | Stand |
|---|---|---|
| Tabellen bearbeiten (Enter, Tab, Pfeile, Sortieren, Einfuegen) | [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90) | fertig gebaut, wartet auf Sichtabnahme (PR #91) |
| Webview in Module teilen, TypeScript 7 | [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) | fertig gebaut, wartet auf Sichtabnahme (PR #98) |
| Luecken-Audit zum TypeScript-Umzug | [ww3d/markdown-workbench#97](https://github.com/ww3d/markdown-workbench/issues/97) | geliefert in PR #98, schliesst mit dessen Merge |
| `build.ps1` ohne globales pnpm | [ww3d/markdown-workbench#103](https://github.com/ww3d/markdown-workbench/issues/103) | gebaut (in PR #98), `main` bekommt es mit dessen Merge |
| Tests auf Testuhr (Playbook 24.11.0) | [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132) | geplant, nichts gebaut |
| Abhaengigkeiten auf neueste Version, Build-Warnungen | [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145) | geplant, nichts gebaut |

## Einfache Liste

Laeuft gerade

- [ww3d/markdown-workbench#146](https://github.com/ww3d/markdown-workbench/pull/146) (diese Roadmap)

Wartet auf dich

- [ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen bearbeiten, Sichtabnahme)
- [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Module und TypeScript 7, Sichtabnahme; P3 und P6 annehmen oder nachbessern)

Danach, der Reihe nach

- [ww3d/markdown-workbench#93](https://github.com/ww3d/markdown-workbench/issues/93) (Clipboard-Diff: Hunk in beide Richtungen)
- [ww3d/markdown-workbench#49](https://github.com/ww3d/markdown-workbench/issues/49) (Canvas-Minimap statt DOM-Klon)
- [ww3d/markdown-workbench#56](https://github.com/ww3d/markdown-workbench/issues/56) (Mehrfachauswahl fuer Tabellen-Checkboxen)
- [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145) (alle Abhaengigkeiten auf die neueste Version)
- [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) (Playbook-TypeScript-Baseline uebernehmen)
- [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132) (Tests auf Testuhr)
- [ww3d/markdown-workbench#102](https://github.com/ww3d/markdown-workbench/issues/102) (Tests nur unter `artifacts/tmp/<lauf>/`)
- [ww3d/markdown-workbench#144](https://github.com/ww3d/markdown-workbench/issues/144) (Repo-Root an die Root-Liste des Playbooks angleichen)
- [ww3d/markdown-workbench#17](https://github.com/ww3d/markdown-workbench/issues/17) (eigener Markdown-Formatter)
- [ww3d/markdown-workbench#4](https://github.com/ww3d/markdown-workbench/issues/4) (Learn-Markdown 1:1 abgleichen)

---

# Ausfuehrliche Fassung (fuer Controller und Sessions)

Entscheidungen des Menschen stehen auf der Fragen-Seite (ww3d/rc-control, Branch `pages`,
`pages/fragen/db/questions/`); wo eine Quelle ihnen widerspricht, gilt die Antwort. Die Entscheide des
Menschen zu #91 und #98 stehen nur als Zitat in Kommentaren von Agenten (kein Kommentar von `ww3d`
selbst). Merge-Regel des Maintainers (2026-09-30T0115Z, zitiert in
[ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92)): Der Controller merged
alles ausser #91 und #98, die der Maintainer vorher visuell abnimmt; eine Sichtabnahme auf #98 reicht fuer
beide.

## Wartet auf dich, ausfuehrlich

- `[!]` **Sichtabnahme von #91 und #98**
  ([ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen bearbeiten),
  [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Module, TypeScript 7)).
  Testliste: 45 Faelle in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) (Kommentar 5937317030,
  Tabellen) und 98-1 bis 98-17 ([Kommentar 5937409776](https://github.com/ww3d/markdown-workbench/issues/92#issuecomment-5937409776)).
  Das `.vsix` vom Kopf `b66b473` (0.37.0, SHA-256
  `8901523fb744fd0ff7ecd1a2104c81643167e524b1f6e15bdcbd86cc9d179521`) liegt nur lokal (siehe Funde, F-3).
- `[!]` **P3 und P6 der Leistungsziele annehmen oder nachbessern** (P3 verfehlt, P6 +35 %), dazu der
  Entscheid zur Build-Kennung; Traeger: Kaestchen in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) (Tracking Issue
  Webview/TypeScript 7). Quelle des Wartens: Frage q227 (Antwort "a", Controller legt die drei Entscheide
  neu vor) und Plan p285 der Seite.
- `[!]` **Freigabe fuer `@vscode/test-electron` 3.1.0** (Dev-Abhaengigkeit der Integrationstests, trotz
  "keine Zusatzabhaengigkeiten"): Freigabe nicht gefunden, Stichprobe 1 von 4 Grenzfaellen (Trockenlauf-Fund
  N-mw3). Traeger: diese Zeile (F-4).

## Jetzt

- `[~]` Diese Roadmap: [ww3d/markdown-workbench#146](https://github.com/ww3d/markdown-workbench/pull/146).
- `[=]` [ww3d/markdown-workbench#91](https://github.com/ww3d/markdown-workbench/pull/91) (Tabellen bearbeiten):
  Branch `claude/rc-control-dev-mw-90-wixrob`, Kopf `f922dde`, Basis `main`, bereit, Review `hard v4` fertig,
  Windows-Lauf am Kopf gruen (826 von 826); `Closes #86`, `Refs #90`; letzte Bewegung 2026-09-30T0944Z.
  Wartet auf die Sichtabnahme. Bringt Version 0.36.0 und `docs/DECISIONS.md` #49.
- `[=]` [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) (Module und
  TypeScript 7): Branch `feat/typescript-webview`, Kopf `b66b473`, **Basis ist der Branch von #91**, bereit,
  sechs Review-Runden in zwei Wellen, zwei Windows-Laeufe; am Kopf `b66b473` lief kein voller Lauf mehr;
  `Refs #92`, `Closes #2`, `Closes #97`; letzte Bewegung 2026-10-02T1022Z. Enthaelt PR #104 (Atlas-Bootstrap,
  `Build.cmd` und `build.sh`, Fix zu #103) und das Audit `audit/ist-stand-2026-09-29T2304Z.md`; bringt
  Version 0.37.0 und `docs/DECISIONS.md` #50 und #51.
- Merge-Weg (Maintainer-Regel, Quelle oben): #91 mergen, Basis von #98 auf `main` umstellen, beide vollen
  Laeufe am neuen Merge-Kopf, Hard-Gate durch einen frischen Reviewer, Merge von #98. Traeger:
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) (Kaestchen
  "Windows-Lauf am Merge-Kopf") und
  [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90) (Merge-Gate).

## Als Naechstes

- `[ ]` [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145) (Abhaengigkeiten
  auf die neueste Version, Build-Warnungen; Antwort auf
  [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105)): neu angelegt von
  dieser Roadmap, drei Kaestchen. FEATURE/SCHULD.
- `[ ]` [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) (Playbook-Baseline:
  Node 24, pnpm ueber `packageManager`, Biome, Prettier fuer Markdown und YAML): vier Kaestchen offen.
  Herkunft Frage q160 (Antwort `issue`). Der Stand am Kopf ist nicht geprueft; siehe W-3.
- `[ ]` [ww3d/markdown-workbench#132](https://github.com/ww3d/markdown-workbench/issues/132) (Tests auf Testuhr,
  Tracking Issue): drei Kaestchen (Fundstellen erheben, umbauen, Echtzeit-Gruppe). Grenze des Maintainers
  2026-10-21T1417Z: "die 20 kommentare sollten reichen!!!". Nichts unter `.claude/` gehoert dazu.
- `[ ]` [ww3d/markdown-workbench#102](https://github.com/ww3d/markdown-workbench/issues/102) (Tests nur unter
  `artifacts/tmp/<lauf>/`): drei Kaestchen. Herkunft ww3d/playbook#327, Welle ww3d/playbook#348.
- `[ ]` [ww3d/markdown-workbench#144](https://github.com/ww3d/markdown-workbench/issues/144) (Root weicht von der
  Root-Liste ab, zwoelf Funde; Playbook-Sync): der Trockenlauf nennt `backlog.md` nach `docs/backlog.md`,
  `audit/` nach `docs/audit/`, `tech/common/*` nach `.agents/tech/*`, `.playbook-version` entfernen,
  `CLAUDE.md:2` umschreiben. Noch nicht ausgefuehrt. Beruehrt diese Roadmap und ihre Links auf das Audit, wenn
  die Pfade ziehen.

## Spaeter

Nach dem Merge von #91 und #98 (Entscheid des Menschen q227: die Design-Runden erst danach):

- `[ ]` [ww3d/markdown-workbench#93](https://github.com/ww3d/markdown-workbench/issues/93) (Clipboard-Diff, Hunk in
  beide Richtungen, vier Kaestchen). Zuerst zu klaeren: `diffEditor/gutter/hunk` ist laut Issue noch
  `proposed: 'contribDiffEditorGutterToolBarMenus'`, also nicht freigegeben. Folgt auf die Merges von
  ww3d/markdown-workbench#89 (gemergt) und #91.
- `[ ]` [ww3d/markdown-workbench#49](https://github.com/ww3d/markdown-workbench/issues/49) (Canvas-Minimap statt DOM-Klon).
  `content-visibility` ist nur messungsgetrieben; `docs/DECISIONS.md` #47 hat es gemessen und verworfen.
- `[ ]` [ww3d/markdown-workbench#56](https://github.com/ww3d/markdown-workbench/issues/56) (Mehrfachauswahl und ein Klick
  fuer Checkboxen in Tabellenzellen).
- `[ ]` [ww3d/markdown-workbench#106](https://github.com/ww3d/markdown-workbench/issues/106) (die drei Design-Auftraege
  fuer #93, #49, #56 liegen nur auf dem Branch `chore/ctrl-mw-10-orders`, Kopf `697b6f5`; sechs Kaestchen:
  Design-Runden, Auftraege nachziehen, danach #17 und #4 einplanen, Branch loeschen). Die Auftraege nennen
  noch `ctrl-markdown-workbench-10` und tragen den "Es gilt wie immer"-Block nicht (Trockenlauf V-M21).
- `[ ]` [ww3d/markdown-workbench#17](https://github.com/ww3d/markdown-workbench/issues/17) (eigener Formatter):
  "Prosa-Reflow verbindlich" laut Maintainer 2026-09-27; die drei Vorschlaege sind nicht freigegeben; drei
  Kaestchen; verwandt ww3d/playbook#333.
- `[ ]` [ww3d/markdown-workbench#4](https://github.com/ww3d/markdown-workbench/issues/4) (Learn-Markdown 1:1
  abgleichen, Kontext-Kommentar mit Quellen).
- `[ ]` Tests fuer 26 ungetestete Architektur-Aussagen und zwei veraltete Kommentare im Code
  (`scrollSpy`-Kopfkommentar in `media/webview.js`, Fold-Testkommentar mit 120-ms-Takt in
  `tests/webview.test.js`): Traeger ist `backlog.md` im Repo-Root (zwei Zeilen), Herleitung im State Audit.
- Ausserhalb des Umfangs (`docs/DECISIONS.md` #22): relative Bilder, Mermaid und Math, Theme fuer Shiki.

## Fertig (seit dem State Audit 2026-09-27T2058Z)

- `[x]` PR #84 (Node 26, pnpm, kanonischer CI-Check, Abhaengigkeiten, gemergt 2026-09-27); Issue #85 (pnpm kam
  mit #84, not_planned).
- `[x]` PR #87 (das State Audit selbst); Issue #73 (completed, 2026-09-27).
- `[x]` PR #89 (Clipboard-Diff, 0.35.0, 2026-09-28) samt Tracking Issue #88 und Issue #82.
- `[x]` PR #100 (Fix zu Issue #94, 0.35.1, 2026-09-30) samt Issue #94.
- `[x]` PR #108 und #113 (Testfelder in `CLAUDE.md`); Playbook-Sync-PRs, zuletzt #143.
- `[x]` Im Branch von #91 gemergt, noch nicht auf `main`: PR #99 (Audit auf dem Tabellen-Kopf).
- `[x]` Im Branch von #98 gemergt, noch nicht auf `main`: PR #104 (Fix zu #103, Atlas-Bootstrap).
- `[x]` Overlay-Abweichungen aus `backlog.md` (npm statt pnpm, CI Node 22, Biome und Prettier, Repo-Werkzeug im
  `.vsix`): erledigt mit #84, die Zeilen stehen durchgestrichen.

## Gestrichen

_none_

## Funde

Kennung F-n, je mit Traeger oder Beleg.

- **F-1** Das State Audit ist faellig: `scripts/common/get-audit-due.ps1` meldet "full audit due (c)", weil
  `audit/ist-stand-2026-09-27T2058Z.md` unter `**Commit:**` keinen Commit nennt (Schwelle 30 gemergte PRs).
  Dazu kommt, dass das neuere Audit `audit/ist-stand-2026-09-29T2304Z.md` nur im Branch von #98 liegt.
  Traeger: diese Zeile.
- **F-2** `[ ]` Alte Branches als einzige Traeger: `chore/rev-mw-98-review-report` (nach dem Merge von #98
  loeschen), `chore/atlas-reference-transport` (nach dem Merge loeschen), `claude/design-mw-ts7-i7272u`
  (erst nach dem Merge entscheiden), `chore/ctrl-mw-10-orders` (siehe #106). Traeger: Kaestchen in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) und
  [ww3d/markdown-workbench#106](https://github.com/ww3d/markdown-workbench/issues/106) (Trockenlauf V-M20).
- **F-3** `[ ]` Sichtabnahme-Material nur lokal: `markdown-workbench-pr98-b66b473.vsix` unter
  `D:\users\agt01\rc-control\work\abnahme-mw\` (Trockenlauf V-M22). Geht verloren, wenn der Ordner geraeumt
  wird. Traeger: diese Zeile.
- **F-4** `[!]` `@vscode/test-electron` 3.1.0 ohne gefundene Freigabe (siehe "Wartet auf dich").
- **F-5** `[ ]` [ww3d/markdown-workbench#103](https://github.com/ww3d/markdown-workbench/issues/103) (`build.ps1` ohne
  globales pnpm): gebaut als PR #104 und in den Branch von #98 gemergt. Zwei Kaestchen offen: `main` bekommt
  den Fix erst mit dem Merge von #98 (bis dahin bricht `build.ps1` auf `main` ohne globales pnpm), und
  "Workers abraeumen" (nur der Ordner von `dev-mw-104d` liegt noch).
- **F-6** `[ ]` Der Override "projekt-eigener CI" in `CLAUDE.md` nennt weder Traeger noch `permanent`; den
  Kanon-Check-Namen faehrt der Workflow seit #84. Traeger: Zeile in `backlog.md`.
- **F-7** Das Archiv bleibt: Maintainer "behalten", 2026-09-29T2248Z (Trockenlauf N-mw1-2). Nichts zu tun;
  Beleg gegen ein Loeschen.

## Widersprueche

Je einer eine Zeile, nicht geglaettet.

- **W-1** [ww3d/markdown-workbench#97](https://github.com/ww3d/markdown-workbench/issues/97) ist offen, hat aber
  56 abgehakte und 0 offene Kaestchen. Aufloesung: `Closes #97` steht im Body von #98; schliesst mit dessen
  Merge, vorher nicht (carrier.md: Tracking Issue schliesst, wenn kein Kaestchen offen ist; hier wartet der
  Merge). Traeger: [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98).
- **W-2** Plan p159 der Seite sagt, ww3d/playbook#336 (`consumers/markdown-workbench.yml` von javascript auf
  typescript) warte auf "Merge von markdown-workbench#2". #2 ist ein Issue, kein PR, und schliesst erst mit
  dem Merge von #98 (`Closes #2`). Traeger:
  [ww3d/markdown-workbench#2](https://github.com/ww3d/markdown-workbench/issues/2) (TypeScript-Umzug) und
  ww3d/playbook#336.
- **W-3** [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) verlangt Node 24, aber
  `CLAUDE.md` § "Project-Specific Overrides" setzt Node 26 (bis ww3d/playbook#334), und `package.json` am Kopf
  hat `engines.node` `>=26`, `packageManager` `pnpm@12.6.0`, Biome 2.5.14, Prettier 3.9.9 und tsdown
  `^0.23.0`. #84 hat pnpm und Node teils schon geliefert; weder #92 noch #98 tragen die vier Kaestchen. Der
  Stand je Kaestchen am Kopf ist nicht geprueft. Traeger: #140 (Kaestchen nachziehen).
- **W-4** Das Kaestchen "Windows-Lauf" in
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) nennt den zweiten Lauf
  noch "vorgemerkt in der Slot-Schlange", obwohl er schon gruen lief. Offen bleibt der Lauf am
  endgueltigen Merge-Kopf.
- **W-5** [ww3d/markdown-workbench#98](https://github.com/ww3d/markdown-workbench/pull/98) hat als Basis den Branch
  von #91, nicht `main`. Aufloesung: Basis umstellen nach dem Merge von #91 (Merge-Weg oben).
- **W-6** Plan p110 und p111 der Seite fuehren #98 und #91 als "liegt still"; die Kommentare der PRs
  (19 bei #91, 27 bei #98, Autoren `ww3-claude` und `ww3-claude-bot`) wurden nur gezaehlt, nicht Zeile fuer
  Zeile gelesen. Bekannt ist nur: kein Kommentar von `ww3d` selbst. Traeger: die beiden PRs.
- **W-7** [ww3d/markdown-workbench#140](https://github.com/ww3d/markdown-workbench/issues/140) und
  [ww3d/markdown-workbench#144](https://github.com/ww3d/markdown-workbench/issues/144) tragen kein Label
  `tracking`, #144 steht in keinem Plan der Seite; Traeger sind die offenen Issues selbst.
- **W-8** [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105) (vom Menschen angelegt,
  0 Kommentare) war ohne Kaestchen; q227 sagt, #105 "bekommt dabei eine Antwort und einen Auftrag". Neuer
  Traeger: [ww3d/markdown-workbench#145](https://github.com/ww3d/markdown-workbench/issues/145). #105 selbst
  bleibt unberuehrt offen.

## Zum Schliessen vorgeschlagen

- [ww3d/markdown-workbench#97](https://github.com/ww3d/markdown-workbench/issues/97) mit dem Merge von #98 (W-1).
- [ww3d/markdown-workbench#2](https://github.com/ww3d/markdown-workbench/issues/2) mit dem Merge von #98 (`Closes #2`).
- [ww3d/markdown-workbench#86](https://github.com/ww3d/markdown-workbench/issues/86) mit dem Merge von #91
  (alle Kaestchen abgehakt, `Closes #86`).
- [ww3d/markdown-workbench#90](https://github.com/ww3d/markdown-workbench/issues/90) und
  [ww3d/markdown-workbench#92](https://github.com/ww3d/markdown-workbench/issues/92) erst, wenn alle Kaestchen
  abgehakt sind (offen: 1 bzw. 9); [ww3d/markdown-workbench#103](https://github.com/ww3d/markdown-workbench/issues/103)
  erst nach dem Merge von #98 und dem Abraeumen.
- [ww3d/markdown-workbench#105](https://github.com/ww3d/markdown-workbench/issues/105) schliesst der Maintainer,
  sobald #145 geantwortet hat.

## Haengt an anderem Repo

- ww3d/playbook#334 (Node-26-Baseline im Overlay): bis dahin gilt der Override in `CLAUDE.md`; wartet laut
  Plan p160 bis 2026-10-28.
- ww3d/playbook#336 (Konsumenten-Datei auf typescript heben): wartet auf den Merge von #98 (W-2).
- ww3d/playbook#327 und Welle ww3d/playbook#348 (Tests nur unter `artifacts/tmp/`): Herkunft von #102.
- ww3d/playbook#333 (Formatter, verwandt mit #17) und ww3d/playbook#332 (Plan p096).
- `microsoft/vscode`: drei Aussagen des Audits sind `[nicht verifiziert]`, weil sie ein Fremd-Repo betreffen;
  `diffEditor/gutter/hunk` ist dort noch nicht freigegeben (#93).

## Legende

Status: `[ ]` offen - `[~]` in Arbeit - `[x]` fertig - `[!]` wartet auf dich - `[=]` blockiert durch anderen
Punkt - `[-]` gestrichen. Art: FEATURE, FEHLER, SCHULD, DOKU, TEST, BETRIEB, ENTSCHEIDUNG.
