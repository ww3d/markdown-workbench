<!-- transport: verbatim, do not re-render -->

# Decision-Log: Webview aufteilen + TypeScript 7 (#92)

| Feld           | Wert                                                                                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stempel        | 2026-09-28T0946Z                                                                                                                                                                |
| Repo / Basis   | ww3d/markdown-workbench, `main` nach dem Merge von ww3d/markdown-workbench#89 und #91 (bei Niederschrift `4221a9f`, 0.34.0; Fakten von den PR-Heads `88f52ff` / `20ea905`)      |
| Anlass         | Entscheid des Maintainers vom 2026-09-28T0926Z plus Nachtrag 0927Z auf ww3d/markdown-workbench#90; ww3d/markdown-workbench#2                                                    |
| Tracking Issue | ww3d/markdown-workbench#92                                                                                                                                                      |
| Runde          | Design-Session `design-mw-ts7`; Entscheider: Controller `ctrl-markdown-workbench-3`; Vorlage `design/ts7-webview/2026-09-28T0934Z-design-round.md` (volle Form je Entscheidung) |
| Audit-Gate     | neuer State Audit auf `main` nach beiden Merges, als erster Auftrag (Entscheid des Controllers, Frage 1); `audit/ist-stand-2026-09-27T2058Z.md` gilt als verbraucht             |
| Review-Modus   | `hard v4`                                                                                                                                                                       |

Ablage im Repo: Das Repo fuehrt keine `docs/decisions/`; der dev-PR traegt den Inhalt als neuen
Eintrag in `docs/DECISIONS.md` (naechste freie Nummer am Head) ein.

## Rahmen (Maintainer, vor der Runde)

- Ladeweg der Webview: eigener tsdown-Eintrag nach `dist/`, alles sauber aufgeteilt, ein Script-Tag mit
  Nonce.
- TypeScript 7 fuer die Webview-Module und den Rest von `src/` (ww3d/markdown-workbench#2) in
  **demselben** PR, ausdruecklich statt der vom Controller empfohlenen zwei PRs. `tsc` 7 prueft nur
  Typen; uebersetzt wird vom Bundler bzw. beim Test durch Node.
- Dauerfreigabe: alle Abhaengigkeiten auf neuestem Stand; ein Major-Sprung bleibt eigener Commit mit
  eigenem Testlauf (`AGENTS.md` § "Dependencies" Regel 3).
- Schnell, sauber, Stand der Technik; messbare Leistungsziele mit Benchmark.
- Start erst auf `main` nach dem Merge von ww3d/markdown-workbench#89 und #91.

## Ausgeraeumte Fehlannahmen

- ww3d/markdown-workbench#2 (2026-06) nennt Node 22, `tsx` und "CI unveraendert" — ueberholt: Node 26
  entfernt Typen ohne Flag, ein Loader ist nicht noetig.
- "Ein Script-Tag" gilt heute nicht: `getWebviewHtml` laedt zwei (`media/morphdom.js` vor
  `media/webview.js`, `docs/DECISIONS.md` #46).
- Der Tab-Wechsel laedt die Webview nicht neu (`retainContextWhenHidden: true` an beiden
  Panel-Stellen, idempotenter Render `docs/DECISIONS.md` #45); ein Nachlade-Teil fuer schnelleren
  Start braechte dort nichts.
- Es gibt keine Messung zu Webview-Start, Aktivierung, Bundle-Groesse oder Typpruefung; `bench/`
  misst Scroll, Fold, Render (und auf den PR-Branches Anker und Tabellen), ausdruecklich nicht als Gate.
- `@types/vscode` "latest" (1.138.0) wuerde gegen APIs pruefen, die `engines.vscode ^1.100.0` nicht
  zusichert.

## Entscheidungen

### D1 Aufbau und Build der Webview

- Fachordner `src/webview/` mit Unterordnern je vorhandenem Abschnitt (Scroll-Sync, Minimap, Folding,
  Scroll-Spy, TOC, Breadcrumb/Sticky, Tabellen-Sortierknopf); Namen der Unterordner legt der dev nach
  den Abschnitten fest und nennt sie im PR.
- CSS neben dem Code, vom Modul importiert; `@tsdown/css` zieht es zu `dist/webview.css`.
- Ein IIFE-Bundle `dist/webview.js`, keine Nachlade-Teile, ein Script-Tag mit Nonce.
- morphdom aus dem npm-Paket eingebuendelt; `media/morphdom.js` und das zweite Script-Tag entfallen.
- Tests importieren die Module direkt (kein `new Function`, keine String-Ersetzung von
  `acquireVsCodeApi`); dazu ein Smoke-Test, der das gebaute `dist/webview.js` im DOM-Mock startet.
- `localResourceRoots` auf `dist/` plus `media/`; CSP inhaltlich wie heute (`docs/DECISIONS.md` #22).
- Freigegebene neue Namen: `src/webview/`, `dist/webview.js`, `dist/webview.css`, Paket
  `@tsdown/css`.
- Verworfen: CSS als eigener Baum mit `@import`-Einstieg (trennt Zusammengehoeriges); ESM-Script
  (`type="module"`, kein Gewinn bei einem Bundle); Nachlade-Teile (widerspricht einem Tag, kein Gewinn
  bei `retainContextWhenHidden`); morphdom-Kopie behalten (zweites Tag, Version von Hand).
- Architektur-Abgleich: `docs/ARCHITECTURE.md` § "Module layout" und § "Webview loading";
  revidiert `docs/DECISIONS.md` #7 ("no build step for the view") und den Vendor-Teil von #46;
  #23 (Schnitt entlang vorhandener Funktionen) gilt weiter.

### D2 Form der TypeScript-7-Umstellung

- ESM-Quellen (`"type": "module"`, `import`/`export`, `.ts`-Endungen in relativen Imports); CJS nur
  aus dem Bundler (`dist/extension.cjs`). Der Bundle-Smoke bleibt und belegt, dass die Rolldown-Falle
  aus `docs/DECISIONS.md` #21 nicht mehr greift.
- `tsconfig.base.json` nach `tech/common/typescript.md` § "Baseline"; zwei Pruefbereiche: Host mit
  Node-Typen ohne DOM, Webview mit DOM ohne Node-Typen; das Protokoll lesen beide.
- `@types/vscode` 1.100.0 (passend zu `engines.vscode`), Grund an der Pin-Stelle; `@types/node`
  26.x.
- Tests als `*.test.ts` unter `node --test`, Coverage mit c8; Attrappen mit Typen an den Grenzen,
  kein `as T` als Ausweg.
- Commit-Schnitt: Werkzeug (tsconfig, `typecheck`, Biome-Regeln des Overlays) → ESM-Umstellung → je
  Fachordner `.js`→`.ts` mit Typen → Webview-Schnitt (D1) → Messung (D3); jeder Schritt gruen.
- Verworfen: JSDoc + `@ts-check` als Zwischenschritt; zwei PRs (Maintainer).
- Ausserhalb: Playbook-Manifest `consumers/markdown-workbench.yml` auf `stack: typescript` —
  Traeger ww3d/playbook#336.
- Architektur-Abgleich: `CLAUDE.md` (Stack-Satz, Override-Zeile zum Overlay), `docs/ARCHITECTURE.md`
  § "Module layout", `docs/DECISIONS.md` #7 und #21, `CONTRIBUTING.md`, `build.ps1`.

### D3 Leistungsziele und Benchmark

- Groesse als hartes Gate im Gate-Lauf (eigenes kleines Skript, gzip-Bytes, kein neues Paket).
- Zeiten als Benchmark mit Zielwert, nicht als Gate (`bench/README.md`; Praxis aus #89); Median aus 21
  Laeufen; "vorher" auf dem Basis-Head vor dem ersten Commit, "nachher" auf dem PR-Head, beides im
  PR-Body.
- Ziele:

| Nr. | Messgroesse                                                                       | Ziel                                                         | Art       |
| --- | --------------------------------------------------------------------------------- | ------------------------------------------------------------ | --------- |
| P1  | Webview-Auslieferung gz, JS + CSS (am `4221a9f`: 41 418 B inkl. morphdom)         | ≤ 28 000 B                                                   | Gate      |
| P2  | `dist/extension.cjs` gz                                                           | ≤ Basis + 2 %                                                | Gate      |
| P3  | Webview-Start: HTML gesetzt bis erster Render sichtbar (CDP-Harness, 400 Bloecke) | ≤ Basis, Ziel −15 %                                          | Benchmark |
| P4  | Update: morphdom-Edit (`bench/render-bench.js`)                                   | ≤ Basis + 5 %                                                | Benchmark |
| P5  | Typpruefung `tsc` 7, ganzes Repo, kalt                                            | ≤ 2 s und ≥ 5× schneller als TypeScript 6 auf demselben Baum | Benchmark |
| P6  | Testlauf `node --test` gesamt                                                     | ≤ Basis + 10 %                                               | Benchmark |
| P7  | Aktivierung bis `ready` im Bundle-Smoke                                           | ≤ Basis + 5 %                                                | Benchmark |
| P8  | VS-Code-Neustart bis Inhalt sichtbar (Sofort-Stand, D4-2)                         | Inhalt vor dem ersten Host-Render sichtbar; Zeit gemessen    | Benchmark |

- P1 wird gemessen, nicht gesenkt: ist die Grenze nicht erreichbar, meldet der dev das mit Messwert.
- Verworfen: Zeit als hartes Gate (flackert, widerspricht `bench/README.md`); `size-limit`
  (Abhaengigkeit fuer 20 Zeilen).

### D4 Alleinstellungsmerkmale

1. **Typisiertes Nachrichtenprotokoll** `src/webview/protocol.ts` (Name freigegeben): eine Union aller
   Nachrichten beider Richtungen, beide Seiten importieren sie; kein Laufzeitcode.
2. **Sofort-Stand nach VS-Code-Neustart:** die Webview legt das zuletzt gerenderte HTML samt
   Scroll-Stelle in `setState`, zeigt es beim Wiederherstellen sofort und ersetzt es beim ersten
   echten Render. Feste Obergrenze fuer den State, mit Test fuer beide Seiten der Grenze; darueber
   kein Sofort-Stand.
3. Groessen-Gate (D3).

- Verworfen: Nachlade-Teile; Nutzer-Befehl "Preview Performance" (Nische, doppelt zu `bench/`).
- Abheben: nach einem Neustart sofort da; Host und Webview koennen nicht aneinander vorbei reden;
  jede Groessenzunahme faellt im Gate auf — bei keinem Vergleichsprojekt gefunden (GitLens, Markdown
  Preview Enhanced, Foam, VS-Code-Preview; "nicht gefunden", kein Gegenbeleg).

### D5 Review-Modus und Zuschnitt

- `hard v4`; Commit-Schnitt nach D2.

## Vorab-Klaerung durch den dev

Nicht nachgelesen in der Runde; der dev klaert sie zuerst und meldet, falls einer den Plan kippt:

- `tsc` 7.0 mit Projekt-Referenzen (`-b`), sonst zwei `tsc -p`-Aufrufe.
- `url()` auf `media/codicon.ttf` durch `@tsdown/css`.
- Groessengrenze von `vscode.setState` in Webviews (setzt die Obergrenze aus D4-2).

## Nicht in diesem Design

- Strengere CSP (`docs/DECISIONS.md` #22, bleibt aus).
- Playbook-Manifest: ww3d/playbook#336.

## Konstellation

- ww3d/markdown-workbench#89 (Clipboard-Diff, `src/clipboard-diff/`, `docs/folder-rules.md`,
  Integrationstests mit `@vscode/test-electron`) und #91 (Tabellen-Editing, `src/{editing,render,
tables,views}/`) sind vor dem Start gemergt; beide aendern `media/webview.js`/`.css`.
- Offene Punkte aus #90, die nach dem Merge von #89 noch an #91 haengen (Reflow-Zusammenfuehrung,
  `src/`-Ausnahme in `docs/folder-rules.md`), gehoeren nicht zu diesem Design.
