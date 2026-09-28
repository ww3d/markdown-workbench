<!-- transport: verbatim, do not re-render -->
# Design-Runde: Webview aufteilen + TypeScript 7 (Vorlage fuer den Controller)

| Feld | Wert |
|---|---|
| Stempel | 2026-09-28T0934Z |
| Session | `design-mw-ts7` (Design-Seat), Adressat: Controller `ctrl-markdown-workbench-3` |
| Auftrag | Entscheid des Maintainers vom 2026-09-28T0926Z plus Nachtrag 0927Z auf ww3d/markdown-workbench#90; ww3d/markdown-workbench#2 |
| Basis | `main` nach dem Merge von ww3d/markdown-workbench#89 und #91 (heute `4221a9f`; Fakten unten von beiden PR-Heads `88f52ff` / `20ea905`) |

Fest vorgegeben (nicht Gegenstand der Runde): tsdown-Eintrag fuer die Webview, alles aufgeteilt, ein
Script-Tag mit Nonce; TypeScript 7 fuer `src/` und Webview in **einem** PR; `tsc` 7 nur Typpruefung;
Abhaengigkeiten dauerhaft auf neuestem Stand, Majors je eigener Commit; messbare Leistungsziele mit
Benchmark.

Registry am 2026-09-28T0934Z: `typescript` latest 7.0.2, `tsdown` 0.23.0, `@tsdown/css` 0.23.0
(Lightning CSS 1.33), `@types/vscode` latest 1.138.0 (1.100.0 vorhanden), `@types/node` 26.6.3,
`morphdom` 2.7.8.

---

## D1 — Aufbau und Build der Webview (volle Form)

**1. Worum es geht.** `media/webview.js` (2183 Zeilen auf #91) und `media/webview.css` (1105) laden roh per
`<script>`/`<link>`, dazu `media/morphdom.js` als zweites Script vor `webview.js` (vendort, globales
`morphdom`). Die Webview-Tests lesen die Datei als Text und fuehren sie per `new Function` aus, mit
String-Ersetzung von `acquireVsCodeApi()` (`tests/helpers/dom-mock.js:144-221`). Zu entscheiden: Ordner,
Schnitt, Format des Bundles, CSS-Weg, morphdom, Tests.

**2. Stand der Technik.** tsdown 0.23.0 baut Browser-Bundles (`platform: 'browser'`, `format: 'iife'`,
https://tsdown.dev/options/output-format). CSS laeuft seit 2026 ueber das Paket `@tsdown/css` (Lightning
CSS: `@import`-Inlining, Minify, Lowering nach `target`, https://tsdown.dev/options/css). Die
VS-Code-Referenz fuer Webviews ist ein Script mit Nonce und `default-src 'none'`
(https://code.visualstudio.com/api/extension-guides/webview).

**3. Was andere machen.** VS Code `markdown-language-features` buendelt `preview-src` mit esbuild
(Skript `esbuild.browser.mts`). GitLens: Webpack mit Chunks je Webview und extrahiertem CSS
(https://github.com/gitkraken/vscode-gitlens/blob/main/webpack.config.mjs). Markdown Preview Enhanced:
Webpack. `vscode-language-nextflow` ging fuer die Webview von Vite zurueck auf einen schlichten Bundler
(https://github.com/nextflow-io/vscode-language-nextflow/pull/235).

**4. Ideen.**

- a) **Fachordner mit CSS neben dem Code** (Empfehlung): `src/webview/` mit Unterordnern je Fach, die
  heute schon als Abschnitte existieren (Scroll-Sync 593 Zeilen, Minimap 263, Folding 295, Scroll-Spy 166,
  TOC 333, Breadcrumb/Sticky 475, dazu Tabellen-Sortierknopf von #91). Jedes Modul importiert sein CSS
  (`import './minimap.css'`), `@tsdown/css` zieht alles zu einer `dist/webview.css`. Preis: ein
  Dev-Paket `@tsdown/css`; Codicon-Schrift muss aus dem CSS erreichbar bleiben.
- b) CSS getrennt als eigener Baum mit `@import`-Einstieg: geht auch, trennt aber zusammengehoerige
  Dinge wieder. Verworfen zugunsten von a.
- c) **Format IIFE, ein Bundle, kein Aufteilen in Nachlade-Teile** (Empfehlung): die ganze Webview ist
  heute ~41 KB gzip; ein Nachlade-Teil braucht weitere Tags oder dynamischen Import unter der Nonce und
  widerspricht dem Entscheid "ein Script-Tag". Die Panels laufen mit `retainContextWhenHidden: true`
  (`src/extension.js:33`, `:99-101`), ein Tab-Wechsel laedt also nicht neu. ESM-`<script type="module">`
  verworfen: kein Gewinn bei einem Bundle, nur ein zweiter Lade-Modus.
- d) **morphdom aus dem npm-Paket einbuendeln** (Empfehlung): `media/morphdom.js` und das zweite
  Script-Tag entfallen, die Version kommt aus `package.json` statt aus einer Kopie. Revidiert den
  Vendor-Teil von `docs/DECISIONS.md` #46. Verworfen: Kopie behalten (zweites Tag, Version von Hand).
- e) **Tests laden Module direkt**, nicht mehr per `new Function`: jedes Modul exportiert, was es testet;
  `acquireVsCodeApi` wird ueber einen kleinen Zugriffspunkt statt per String-Ersetzung gereicht. Dazu ein
  Smoke-Test, der das **gebaute** `dist/webview.js` im DOM-Mock startet und einen Render prueft
  (Verbraucher-Topologie, `AGENTS.md` § "Always"). Die CSS-Regel-Tests lesen die Quell-CSS je Modul.
- f) `localResourceRoots` auf `dist/` plus `media/` (Icons, Codicon-Schrift) begrenzen; CSP bleibt
  inhaltlich wie heute (`docs/DECISIONS.md` #22: keine strengere CSP in dieser Runde).
- g) Vorgabe des Maintainers kritisch: ein zweiter Build-Eintrag macht die Webview abhaengig vom Build —
  Tests laufen trotzdem ohne Build (Type-Stripping), nur der Smoke-Test braucht `dist/`. Der Preis ist
  klein und wird durch e) abgesichert.

**Architektur-Abgleich:** aendert `docs/ARCHITECTURE.md` § "Module layout" (Webview nie im Host-Bundle —
bleibt wahr, jetzt eigener Eintrag) und § "Webview loading" (zwei Tags → ein Tag, `media/` → `dist/`);
revidiert `docs/DECISIONS.md` #7 ("no build step for the view") und den Vendor-Teil von #46; #23 ist der
Vorlaeufer (Schnitt entlang vorhandener Funktionen, keine neuen Abstraktionen) und gilt weiter.

**5. Empfehlung.** a + c + d + e + f. Neue Namen zur Freigabe: Ordner `src/webview/` (Unterordner je Fach,
Namen legt der dev nach den vorhandenen Abschnitten fest und nennt sie im PR), Ausgabe `dist/webview.js`
und `dist/webview.css`, Paket `@tsdown/css`.

**6. Was uns abheben koennte.** Das typisierte Nachrichtenprotokoll (D4, Kandidat 1) sitzt genau an der
Naht, die dieser Schnitt freilegt: Host und Webview importieren dieselben Typen.

---

## D2 — Form der TypeScript-7-Umstellung (volle Form)

**1. Worum es geht.** `src/` ist durchgaengig CommonJS-JavaScript (`require`, kein `"type"`), keine
Typen, kein `tsconfig.json`, kein `@types/vscode`; Tests `*.test.js`. Das Overlay
`tech/common/typescript.md` beschreibt das Zielbild (ESM-Quellen, `tsconfig.base.json` mit festen
Flags, `typecheck`, Tests `*.test.ts` aus den Quellen, Biome-Regeln `noExplicitAny`/`useAwait`/
`useImportType`). ww3d/markdown-workbench#2 ist von 2026-06 (nennt Node 22, `tsx`) und damit ueberholt.

**2. Stand der Technik.** TypeScript 7.0.2 (nativer Compiler) ist stabil; ohne stabile Programm-API bis
7.1 (Plan 24.11.2026) — betrifft nur Werkzeuge auf der Compiler-API, hier keines
(https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/). Node 26 entfernt Typen ohne Flag;
nicht erlaubt sind `enum`, Laufzeit-`namespace`, Parameter-Properties
(https://nodejs.org/api/typescript.html).

**3. Was andere machen.** GitLens und Markdown Preview Enhanced uebersetzen vor Test und Auslieferung
(Webpack/`esbuild-loader`); ein Lauf der Tests direkt aus `.ts` ist dort nicht belegt.

**4. Ideen.**

- a) **ESM-Quellen, CJS nur aus dem Bundler** (Empfehlung, Overlay): `"type": "module"`, `import`/
  `export`, Endungen `.ts` in relativen Imports; `dist/extension.cjs` bleibt CJS. Die Rolldown-Falle aus
  `docs/DECISIONS.md` #21 (`module.exports = {...}` im Einstieg) soll mit ESM wegfallen — der
  Bundle-Smoke bleibt und belegt es.
- b) **Zwei Pruefbereiche**: Host mit `types: ["node"]` ohne DOM, Webview mit `lib: ["dom", …]` ohne
  Node-Typen; das geteilte Protokoll wird von beiden gelesen. Ob `tsc -b` mit Projekt-Referenzen in 7.0
  laeuft oder zwei `tsc -p`-Aufrufe noetig sind, prueft der dev (nicht nachgelesen).
- c) **`@types/vscode` auf 1.100.0**, passend zu `engines.vscode ^1.100.0`, nicht auf latest 1.138:
  sonst prueft `tsc` gegen APIs, die der unterstuetzte Mindeststand nicht hat. Benannte Abweichung von
  "latest", Grund an der Pin-Stelle. `@types/node` 26.x folgt der Node-Linie (Overlay).
- d) **Tests nach `.test.ts`**, weiter `node --test`, Coverage mit c8 (V8-Abdeckung ueberlebt das
  Entfernen der Typen, weil Node Typen durch Leerzeichen ersetzt). Die Attrappen (`tests/helpers/`)
  bekommen Typen an den Grenzen; kein `as T` als Ausweg.
- e) Reihenfolge im PR als eigene Commits: Werkzeug (tsconfig, `typecheck`, Biome-Regeln) → ESM-Umstellung
  → je Fachordner `.js`→`.ts` mit Typen → Webview-Schnitt (D1) → Messung (D3). Dazwischen jeweils gruen.
- f) Vorgabe des Maintainers kritisch: ein PR fuer beides ist gross (~9k Zeilen Quelltext plus Tests),
  der Controller hatte zwei PRs empfohlen; der Maintainer hat ausdruecklich einen gewaehlt. Folge fuer die
  Runde: `hard`-Review (D5) und ein fester Commit-Schnitt nach e).
- g) Verworfen: JSDoc + `@ts-check` als Zwischenschritt (Overlay "Recommended, not active") — verdoppelt
  die Arbeit, der Entscheid lautet TypeScript.

**Folgen ausserhalb:** Im Playbook muss `consumers/markdown-workbench.yml` auf `stack: typescript`
gehoben werden (ww3d/markdown-workbench#2). Weder diese Session noch der dev erreichen ww3d/playbook;
Traeger muss ein Issue dort sein — Bitte an den Controller, es anlegen zu lassen.

**Architektur-Abgleich:** `CLAUDE.md` (Stack-Satz "JavaScript", Override-Zeile zum Overlay fuer
JavaScript), `docs/ARCHITECTURE.md` § "Module layout", `docs/DECISIONS.md` #7 und #21, `CONTRIBUTING.md`
(Gate-Befehle), `build.ps1` (Task `Check` um `typecheck`).

**5. Empfehlung.** a–e. Keine neuen Code-Namen ausser `tsconfig.json`/`tsconfig.base.json`
(Overlay-Namen) und dem Skript `typecheck` (Overlay).

**6. Was uns abheben koennte.** Tests laufen direkt aus den `.ts`-Quellen ohne Build — belegt nur als
Folge des Overlays, kein eigenes Merkmal; hier nichts Weiteres.

---

## D3 — Messbare Leistungsziele und Benchmark (volle Form)

**1. Worum es geht.** Der Maintainer verlangt Ziele mit Benchmark, vorher/nachher. Heute gibt es
`bench/` (Headless-Chromium ueber CDP: `render-bench`, `fold-bench`, `scroll-bench`; auf den Branches
dazu `anchor-bench`, `table-bench`), ausdruecklich als Diagnose, **nicht** als Gate (`bench/README.md`).
Keine Messung zu Webview-Start, Aktivierung, Bundle-Groesse, Typpruefung.

Gemessen am 2026-09-28T0934Z auf `main` (`4221a9f`), `gzip -9`: `webview.js` 90 564 B roh / 29 047 B gz;
`morphdom.js` 12 762 / 3 336; `webview.css` 30 536 / 9 035 — zusammen **41 418 B gz**, heute unminifiziert.

**2. Stand der Technik.** Groessen-Budgets als harter Check sind ueblich (`size-limit`,
https://github.com/ai/size-limit), Zeitmessungen gelten als maschinenabhaengig und laufen als Benchmark
mit Median ueber mehrere Laeufe, nicht als Gate. Webview-Zeiten misst man mit `performance.mark`/
`measure` in der Seite.

**3. Was andere machen.** Ein dokumentiertes Budget fuer Typpruefzeit oder Webview-Start fand die
Recherche bei keinem Vergleichsprojekt (GitLens, MPE, Foam, VS Code) — "nicht gefunden", kein Gegenbeleg.

**4. Ideen.**

- a) **Groesse als hartes Gate** (Empfehlung): deterministisch, also im Gate-Lauf pruefbar
  (`build.ps1 -Task All`), ohne neues Paket: ein kleines Skript misst gzip-Bytes von `dist/webview.js`,
  `dist/webview.css`, `dist/extension.cjs` gegen feste Grenzen.
- b) **Zeiten als Benchmark mit Zielwert, nicht als Gate** (Empfehlung): folgt `bench/README.md` und der
  Praxis aus ww3d/markdown-workbench#89 ("Benchmark, nicht Gate"). Neuer `bench/`-Lauf fuer den
  Webview-Start im vorhandenen CDP-Harness; Median aus 21 Laeufen; vorher (auf dem Basis-Head, vor dem
  ersten Commit) und nachher im PR-Body.
- c) Zeit als hartes Gate: verworfen — flackert auf fremder Hardware, widerspricht `bench/README.md`.
- d) `size-limit` als Paket: verworfen — 20 Zeilen Node reichen, keine neue Abhaengigkeit.

Vorgeschlagene Ziele (jedes ein REQ, vorher/nachher gemessen):

| Nr. | Messgroesse | Ziel | Art |
|---|---|---|---|
| P1 | Webview-Auslieferung gz (JS + CSS, heute 41 418 B inkl. morphdom) | ≤ 28 000 B (−32 %, durch Minify) | Gate |
| P2 | `dist/extension.cjs` gz | ≤ Basis + 2 % | Gate |
| P3 | Webview-Start: HTML gesetzt bis erster Render sichtbar (CDP, 400 Bloecke) | ≤ Basis, Ziel −15 % | Benchmark |
| P4 | Update: morphdom-Edit (`render-bench`) | ≤ Basis + 5 % | Benchmark |
| P5 | Typpruefung `tsc` 7, ganzes Repo, kalt | ≤ 2 s, und ≥ 5× schneller als TypeScript 6 auf demselben Baum | Benchmark |
| P6 | Testlauf `node --test` gesamt | ≤ Basis + 10 % | Benchmark |
| P7 | Aktivierung bis `ready` im Bundle-Smoke | ≤ Basis + 5 % | Benchmark |

P1 ist eine Schaetzung (Minify von JS/CSS spart erfahrungsgemaess ein Drittel); der dev misst zuerst und
meldet, falls die Grenze nach Minify nicht erreichbar ist, statt sie zu senken. P5 mit TypeScript 6 als
Vergleich, weil es kein "vorher" gibt.

**Architektur-Abgleich:** `bench/README.md` (Diagnose, nicht Gate) bleibt fuer Zeiten wahr; das Groessen-Gate
ist neu und gehoert in `docs/ARCHITECTURE.md` (Build) und `CONTRIBUTING.md`.

**5. Empfehlung.** a + b mit P1–P7.

**6. Was uns abheben koennte.** Ein festes Groessen-Budget im Gate plus ein Webview-Start-Benchmark — bei
keinem Vergleichsprojekt gefunden.

---

## D4 — Alleinstellungsmerkmale fuer diese Scheibe (volle Form)

**1. Worum es geht.** Abschnitt 6 mit echten Merkmalen (Nachtrag des Maintainers). Nur Ideen; was davon in
den PR kommt, entscheidet der Controller.

**2./3. Stand der Technik und andere.** Recherche oben; keines der Vergleichsprojekte zeigt ein
gemeinsam typisiertes Host↔Webview-Protokoll, einen Sofort-Stand nach Neustart oder ein Leistungsbudget
im Gate (jeweils "nicht gefunden", kein Gegenbeleg).

**4. Kandidaten.**

1. **Typisiertes Nachrichtenprotokoll Host↔Webview** — ein Modul mit einer Union aller Nachrichten
   beider Richtungen (heute `render`, `config`, `scrollTo`, `ready`, `toggle`, `toggleCell`,
   `scrolled`, `sortTable`), beide Seiten importieren es; eine vergessene oder falsch geformte Nachricht
   wird zum Typfehler. Preis klein, kein Laufzeitcode. **Empfehlung: in den PR.** Neuer Name zur
   Freigabe: `src/webview/protocol.ts`.
2. **Sofort-Stand nach VS-Code-Neustart** — die Webview legt das zuletzt gerenderte HTML samt Scroll-Stelle
   in `setState`; beim Wiederherstellen (`registerWebviewPanelSerializer`, `src/extension.js:135-152`)
   zeigt sie es sofort und ersetzt es beim ersten echten Render. Heute steht nur `documentUri` im State
   (`media/webview.js:275-277`). Preis klein, Risiko: Groesse des States bei sehr grossen Dokumenten (nicht
   nachgelesen) → Obergrenze, darueber kein Sofort-Stand. **Empfehlung: in den PR**, mit Messung
   "Neustart bis Inhalt sichtbar" als P8 (Benchmark).
3. **Groessen-Budget im Gate** (D3 a) — gehoert ohnehin dazu.
4. Verworfen: Nachlade-Teile fuer einen schnelleren Start (widerspricht "ein Script-Tag", kaum Gewinn bei
   `retainContextWhenHidden`); Befehl "Preview Performance" fuer Nutzer (Nische, doppelt zu `bench/`,
   `AGENTS.md` § "Simplicity").

**5. Empfehlung.** 1 und 2 in den PR, 3 ueber D3.

**6. Was uns abheben koennte.** Genau diese drei; zusammen: die Preview ist nach einem Neustart sofort da,
Host und Webview koennen nicht mehr aneinander vorbei reden, und jede Groessenzunahme faellt im Gate auf.

---

## D5 — Review-Modus und Zuschnitt (Kurzform)

- **Worum:** Review-Modus und Commit-Schnitt fuer einen grossen PR.
- **Empfehlung:** `hard v4` (breit, Hot Path der Preview, Build-Umbau). Commit-Schnitt nach D2 e.
- **Verworfen:** `light` — ein PR ueber den ganzen Quelltext mit neuem Build-Weg braucht die Wellen.

---

## Nicht nachgelesen

- Ob `tsc` 7.0 Projekt-Referenzen (`-b`) voll kann; Verhalten von `@tsdown/css` mit `url()` auf
  `media/codicon.ttf`.
- Groessengrenze von `vscode.setState` in Webviews.
- Exakte esbuild-Konfiguration der VS-Code-Preview (`esbuild.browser.mts`, Datei nicht abrufbar).
- Inhalt von `media/webview.js` auf den PR-Heads im Einzelnen (nur Zeilenzahlen und Diff-Umfang).
