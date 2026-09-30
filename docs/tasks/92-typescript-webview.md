---
issue: 92
repo: ww3d/markdown-workbench
slug: typescript-webview
title: Webview in Module aufteilen und das Repo auf TypeScript 7 umstellen
---

# Spec: Webview aufteilen + TypeScript 7 (#92, schliesst #2)

Entscheidungen: `docs/DECISIONS.md` (neuer Eintrag, Decision-Log vom 2026-09-28T0946Z: D1–D5, P1–P8).
Basis: Head von ww3d/markdown-workbench#91 (`98f7590`), Entscheid des Maintainers vom 2026-09-29T2248Z.

Vorbedingung und Messung vorher:

- [x] REQ-001: Der PR-Body nennt Stempel und Commit des neuen State Audits auf `98f7590` (Head von #91,
      Entscheid des Maintainers 2026-09-29T2248Z), auf dem der PR aufsetzt.
- [x] REQ-002: Die drei Vorab-Klaerungen aus dem Decision-Log (`tsc` 7.0 mit `-b`; `url()` auf
      `media/codicon.ttf` durch `@tsdown/css`; Groessengrenze von `vscode.setState`) sind vor dem ersten
      Code-Commit mit Beleg beantwortet und stehen im PR-Body. Kippt eine den Plan: melden, bevor gebaut
      wird.
- [x] REQ-003: Die Vorher-Werte P1–P7 sind auf dem Basis-Head vor dem ersten Commit gemessen und stehen
      mit dessen SHA im PR-Body.

Werkzeug (D2):

- [x] REQ-004: `typescript` steht auf der neuesten stabilen 7.x (Registry am Tag des Pins) unter
      `devDependencies`.
- [x] REQ-005: `tsconfig.base.json` traegt die Flags aus `tech/common/typescript.md` § "Baseline".
- [x] REQ-006: Der Host-Pruefbereich kennt keine DOM-Typen: ein DOM-Global in einer Host-Datei ist ein
      Typfehler.
- [x] REQ-007: Der Webview-Pruefbereich kennt keine Node-Typen: ein Node-Global in einer Webview-Datei
      ist ein Typfehler.
- [x] REQ-008: `pnpm run typecheck` prueft jede `.ts`-Datei im Repo und endet ohne Fehler.
- [x] REQ-009: `./build.ps1 -Task Check` faehrt `typecheck`.
- [x] REQ-010: `@types/vscode` ist exakt 1.100.0 (passend zu `engines.vscode`); der Grund der Abweichung
      von "latest" steht im neuen `docs/DECISIONS.md`-Eintrag (JSON traegt keinen Kommentar).
- [x] REQ-011: `@types/node` steht auf der neuesten 26.x.
- [x] REQ-012: Biome prueft `noExplicitAny`, `useAwait` und `useImportType` auf `error`.
- [x] REQ-013: `pnpm outdated` ist vor und nach der Umstellung im PR-Body gezeigt; nach der Umstellung
      ist die Liste leer bis auf benannte Ausnahmen (REQ-010).
- [x] REQ-014: Jeder Major-Sprung einer Abhaengigkeit steht in einem eigenen Commit.

TypeScript und ESM (D2):

- [x] REQ-015: `package.json` traegt `"type": "module"` und `sideEffects` mit den CSS-Dateien.
- [x] REQ-016: Unter `src/` liegt keine `.js`-Datei mehr.
- [x] REQ-017: `src/` und `tests/` enthalten kein `require(`.
- [x] REQ-018: `src/` enthaelt keine Typ-Zusicherung `as T` ausser `as const`.
- [x] REQ-019: Jedes exportierte Symbol unter `src/` traegt TSDoc.
- [x] REQ-020: Alle Tests heissen `*.test.ts` und laufen mit `node --test` ohne Build-Schritt.
- [x] REQ-021: Das Coverage-Gate misst alle `.ts`-Dateien unter `src/` (einschliesslich `src/webview/`)
      mit unveraenderten Schwellen und ist gruen.
- [x] REQ-022: `dist/extension.cjs` bleibt ein CJS-Bundle, und der Bundle-Smoke ist aus einem isolierten
      Verzeichnis gruen.

Webview-Schnitt (D1):

- [x] REQ-023: `media/webview.js`, `media/webview.css` und `media/morphdom.js` sind entfernt.
- [x] REQ-024: Die Webview liegt unter `src/webview/` in Unterordnern je Fach; die Namen stehen im PR.
- [x] REQ-025: Keine Datei unter `src/webview/` hat mehr als 300 Zeilen.
- [x] REQ-026: Jedes Webview-Modul mit Styles importiert sein eigenes CSS; `@tsdown/css` erzeugt daraus
      `dist/webview.css`.
- [x] REQ-027: `tsdown.config.ts` hat einen zweiten Eintrag (`platform: 'browser'`, `format: 'iife'`,
      minifiziert), der `dist/webview.js` erzeugt.
- [x] REQ-028: `getWebviewHtml` gibt genau ein `<script>` (mit Nonce, Quelle `dist/webview.js`) und genau
      ein Stylesheet (`dist/webview.css`) aus.
- [x] REQ-029: morphdom kommt aus dem npm-Paket (exakt gepinnt) und steckt im Webview-Bundle.
- [x] REQ-030: `localResourceRoots` ist genau `dist/` und `media/`, mit Test.
- [x] REQ-031: Die CSP-Direktiven sind inhaltlich unveraendert, und ein Test prueft die ganze
      CSP-Zeichenkette (auch `default-src`, `img-src`, `font-src`).
- [x] REQ-032: Die Codicon-Schrift wird aus `dist/webview.css` gefunden: ein Test prueft, dass jede
      `url()` darin auf eine Datei zeigt, die im `.vsix` liegt.
- [x] REQ-033: Die Webview-Tests importieren die Module direkt; `new Function` und das Einlesen des
      Script-Textes sind aus `tests/` verschwunden.
- [x] REQ-034: Jeder Webview-Testname von vorher existiert nachher. Gewollte Differenz (Entscheid des
      Controllers, ww3d/markdown-workbench#97, DECISIONS #36): aus "measured height" wird "computed height" im
      Test `the breadcrumb reserves body top padding from its computed height`.
- [x] REQ-035: Ein Smoke-Test startet das gebaute `dist/webview.js` aus einem isolierten Verzeichnis im
      DOM-Mock und prueft einen sichtbaren Render.
- [x] REQ-036: Das `.vsix` enthaelt `dist/webview.js` und `dist/webview.css` und kein `src/`.
- [x] REQ-037: Ein Test sichert, dass `dist/extension.cjs` keinen Webview-Code enthaelt.

Typisiertes Protokoll (D4-1):

- [x] REQ-038: `src/webview/protocol.ts` definiert je Richtung eine Union aller Nachrichten.
- [x] REQ-039: Host und Webview senden und empfangen nur ueber diese Typen.
- [x] REQ-040: Eine Nachricht mit unbekanntem `type` ist ein Typfehler, belegt durch eine
      `@ts-expect-error`-Probe, die `typecheck` prueft.

Sofort-Stand nach Neustart (D4-2):

- [x] REQ-041: Nach jedem Render legt die Webview das HTML und die Scroll-Stelle per `setState` ab,
      solange das HTML eine feste Obergrenze (benannte Konstante) nicht ueberschreitet; genau die Grenze
      wird noch abgelegt.
- [x] REQ-042: Ueber der Obergrenze legt sie kein HTML ab; Tests decken beide Seiten der Grenze.
- [x] REQ-043: Beim Wiederherstellen zeigt die Webview das abgelegte HTML vor dem ersten Host-Render.
- [x] REQ-044: Nach dem ersten Host-Render entspricht der Inhalt dem Host-Render.

Leistung (D3):

- [x] REQ-045: Ein Skript im Gate-Lauf misst die gzip-Groessen von `dist/webview.js`, `dist/webview.css`
      und `dist/extension.cjs` und laesst den Lauf bei Ueberschreiten von P1 oder P2 scheitern; Name vom
      dev, im PR genannt.
- [x] REQ-046: P1 erfuellt: Webview-Auslieferung (JS + CSS) gz ≤ 28 000 B. Nicht erreichbar: mit
      Messwert melden, die Grenze nicht senken.
- [x] REQ-047: P2 erfuellt: `dist/extension.cjs` gz ≤ Basis + 2 %. Gemessen wird der beim Aktivieren geladene Host-Code:
      `extension.cjs` plus die direkt per `require` geladenen Chunks (Entscheid des Controllers 2026-09-30,
      DECISIONS.md #50).
- [x] REQ-048: Ein neuer Benchmark in `bench/` misst P3 im vorhandenen CDP-Harness, Median aus 21
      Laeufen.
- [ ] REQ-049: P3 erfuellt: Webview-Start ≤ Basis (Ziel −15 %, der erreichte Wert steht im PR).
      nicht geliefert: 5 × 21 Laeufe im Wechsel auf `36bde92`, Median Head 223,8 ms gegen Basis 217,3 ms (+3,0 %),
      Head in 4 von 5 Serien ueber der Basis; Ziel −15 % verfehlt (Entscheid des Controllers, PR-Kommentar
      2026-09-30T1143Z).
- [x] REQ-050: P4 erfuellt: morphdom-Edit ≤ Basis + 5 %.
- [x] REQ-051: P5 erfuellt: `tsc` 7 kalt ≤ 2 s und ≥ 5× schneller als TypeScript 6 auf demselben Baum.
- [x] REQ-052: P6 erfuellt: Testlauf ≤ Basis + 10 %.
- [x] REQ-053: P7 erfuellt: Aktivierung bis `ready` im Bundle-Smoke ≤ Basis + 5 %.
- [x] REQ-054: P8 gemessen: nach einem VS-Code-Neustart ist Inhalt vor dem ersten Host-Render sichtbar;
      die Zeit steht im PR.

Doku (je Quelle einzeln):

- [x] REQ-055: `docs/ARCHITECTURE.md` § "Module layout" beschreibt `src/webview/` und die zwei
      tsdown-Eintraege, mit Markern.
- [x] REQ-056: `docs/ARCHITECTURE.md` § "Webview loading" beschreibt ein Script, ein Stylesheet,
      `dist/`, `localResourceRoots` und die Obergrenze des Sofort-Stands, mit Markern.
- [x] REQ-057: `docs/ARCHITECTURE.md` § "Message protocol (host <-> webview)" nennt
      `src/webview/protocol.ts` als Quelle.
- [x] REQ-058: `docs/DECISIONS.md` hat einen neuen Eintrag mit dem Decision-Log (verbatim) und nennt die
      Revision von #7, #21 und des Vendor-Teils von #46.
- [x] REQ-059: `CLAUDE.md` § "Project Context" nennt TypeScript statt JavaScript, und die Override-Zeile
      zum Overlay fuer JavaScript ist angepasst.
- [x] REQ-060: `CONTRIBUTING.md` nennt `typecheck`, das Groessen-Gate und den neuen Benchmark.
- [x] REQ-061: `bench/README.md` beschreibt den neuen Benchmark und das Groessen-Gate.
- [x] REQ-062: `README.md` nennt den Sofort-Stand nach Neustart.
- [x] REQ-063: `CHANGELOG.md` hat einen Eintrag fuer die naechste freie Minor-Version am Head, und
      `package.json` `version` stimmt damit ueberein.
- [x] REQ-064: `docs/folder-rules.md` deckt `src/webview/` ab (Regel eingehalten oder Ausnahme mit
      Aufloesung).
- [x] REQ-065: Die veralteten Kommentare aus `backlog.md` (Kopf ueber `scrollSpy`, Fold-Re-Measure-Takt in
      `tests/webview.test.js`) sind in den verschobenen Dateien korrigiert und die Zeile ist
      durchgestrichen.

Build Atlas-nah (Vorgabe des Maintainers 2026-09-29T2254Z):

- [x] REQ-066: Alle Ausgabe- und Zwischenpfade kommen aus `eng/layout.ts`; ein Test prueft jedes unvermeidliche
      Pfad-Literal (`package.json` `main`, Ignore-Dateien, `tsconfig*.json`) gegen diese Stelle.
- [x] REQ-067: Der PR-Body fuehrt unter "Entscheidungen" den Abgleich mit ww3d/atlas je Punkt (Ausgabe-Layout,
      Wurzelskripte, Versionierung, reproduzierbare Pakete, Pflichtangaben): gleich, angeglichen oder abweichend
      mit Grund.

Neustart ohne neues Rendern (Entscheid des Maintainers 2026-09-29T2303Z, Ausbau D4-2):

- [ ] REQ-068: Der Webview-State traegt die Build-Kennung `BUILD_ID`, die tsdown per `define` aus der
      Paketversion setzt.
- [x] REQ-069: Der Webview-State traegt einen Schluessel, der ein Hash aus Text, Render-Einstellungen,
      Theme-Art und Zustand des Highlighters ist.
- [x] REQ-070: `ready` meldet Build-Kennung und Schluessel des wiederhergestellten Stands.
- [x] REQ-071: Stimmen Build-Kennung und Schluessel mit dem Host ueberein, rendert der Host nicht und schickt
      die Dokumentversion in einer eigenen Nachricht.
- [x] REQ-072: Weicht Build-Kennung oder Schluessel ab, rendert der Host wie bisher.
- [x] REQ-073: Eine andere Build-Kennung verwirft den gespeicherten Stand in der Webview.
- [x] REQ-074: Tests decken jeden Zweig ab: Treffer, Text anders, Einstellungen anders, Theme anders, Kennung
      anders.
- [x] REQ-075: Die P8-Messung nennt die Zahl der Host-Renders beim Wiederherstellen, und sie ist 0.

Ladezeit-Benchmark (Entscheid 2026-09-29T2303Z):

- [x] REQ-076: Ein Benchmark in `bench/` misst im CDP-Harness die Zeit vom Skriptbeginn bis `ready`, Median aus
      21 Laeufen; die CDP-Kennzahl ist im PR benannt.
- [x] REQ-077: Der Ladezeit-Wert steht fuer den Basis-Head und fuer den PR-Head (`dist/webview.js`) im PR.

Groessen-Gate auf ungepackte Bytes (Entscheid 2026-09-29T2303Z, aendert D3):

- [x] REQ-078: Das Groessen-Skript prueft zusaetzlich die ungepackten Bytes von `dist/webview.js` und
      `dist/webview.css` gegen je eine Grenze.
- [x] REQ-079: Jede Rohbyte-Grenze liegt nicht hoeher als der nach dem Umbau gemessene Wert; der Wert vor dem
      Umbau steht im PR.
- [x] REQ-080: Ein Test mit kleiner Fixture belegt fuer gzip- und Rohbyte-Grenze je beide Seiten.

Feste CSS-Zielversion (Entscheid 2026-09-29T2303Z):

- [x] REQ-081: Der Webview-Eintrag in `tsdown.config.ts` hat als `target` die Chromium-Version des
      Mindest-VS-Code (`engines.vscode` 1.100), belegt an den Release Notes von Electron bzw. VS Code.
- [x] REQ-082: Eine Build-Probe auf `dist/webview.css` sichert, dass CSS nicht unter diese Zielversion
      heruntergerechnet wird.

Audit-Luecken (ww3d/markdown-workbench#97):

- [x] REQ-083: Jeder Punkt aus ww3d/markdown-workbench#97 ist in diesem PR geliefert und dort abgehakt.
