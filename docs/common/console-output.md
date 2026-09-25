# Konsolenausgabe: Status-Zeichen und Farben

Gilt fuer jedes ww3d-Werkzeug, das Statuszeilen fuer Menschen in ein Terminal schreibt — gleich in
welcher Sprache. Ziel: ein Fehler sieht in jedem Werkzeug gleich aus, ist in der Standardschrift
lesbar und bleibt ohne Farbe verstaendlich. Wie ein Stack das umsetzt (eigene Writer, eine
gemeinsame Bibliothek), entscheidet das Repo; die Werte unten sind fest.

## Zeichen und Farben

| Status | Zeichen | ASCII-Fallback | Farbe (SGR) |
|---|---|---|---|
| Fehler | `×` U+00D7 | `x` | `91` hellrot, **ganze Zeile** |
| Erfolg | `✓` U+2713 | `+` | `32` gruen, nur das Zeichen |
| Warnung | `!` | `!` | `33` gelb, nur das Zeichen |
| Info / Eintrag | `▶` U+25B6 | `>` | `36` cyan, nur das Zeichen |
| Ueberschrift | — | — | `96` hellcyan, ganze Zeile |
| Nebenzeile | — | — | `38;5;246` grau, ganze Zeile |

Ein Werkzeug muss nicht jeden Status fuehren. Fuehrt es einen, dann mit diesem Zeichen und dieser
Farbe — kein eigenes Symbol fuer dieselbe Aussage.

Weitere Zeichen in der Ausgabe: `→` (Fallback `->`) fuer eine Aenderung von–nach, `…` (Fallback
`...`) fuer eine Kuerzung. `§` gehoert nicht in die Ausgabe — unter Codepage 437 wird es zum
Steuerzeichen; dort steht `section`.

**Nicht verwenden:** `✗` `✘` `✖` `✔` `⚠` `ℹ`. Keins davon ist in Cascadia Mono/Code oder Consolas
enthalten; das Terminal greift auf eine Ersatzschrift zurueck (bei `✗` eine Pinselstrich-Form).

## Regeln

- **Nur Zeichen aus der Standardschrift.** Massstab ist Cascadia Mono/Code, die Standardschrift von
  Windows Terminal. Ein neues Zeichen kommt erst hinein, wenn seine Abdeckung dort gemessen ist.
- **Farbe ist nie das einzige Signal.** Zeichen und Text tragen die Aussage allein (WCAG 2.2,
  SC 1.4.1); die Farbe verstaerkt nur.
- **Kontrast WCAG AA (4,5:1)** gegen das Schwarz von Windows Terminal (`#0C0C0C`). Darum `91` statt
  `31` fuer Fehler und `96` statt eines Magentas fuer Ueberschriften.
- **Jedes Nicht-ASCII-Zeichen hat einen ASCII-Fallback.** Er greift, wenn die Ausgabe kein UTF-8
  traegt (umgeleitete Ausgabe, alte Codepage).
- **Farbe abschaltbar:** `NO_COLOR` (gesetzt, nicht leer), `--no-color` und `TERM=dumb` schalten
  sie ab, ebenso eine Ausgabe, die nicht in ein Terminal geht.
- **Die Zuordnung Status → Zeichen steht an einer Stelle im Code**, nicht in jeder Aufrufstelle.
  Ein Status ohne Eintrag wird gemeldet, nicht still als Erfolg gezeichnet.

## Bekannte Grenzen

- **PowerShell-Blau** (`#012456`, Schema "Campbell Powershell"): `91` erreicht dort 3,93:1, `32`
  4,42:1 — knapp unter AA. Kein Rot der Standardpalette schafft dort 4,5:1. Hingenommen: 3:1 fuer
  Nicht-Text ist erfuellt, und Zeichen plus Text tragen die Aussage.
- **Consolas** (Standardschrift der alten Windows-Konsole) enthaelt `✓` und `▶` nicht. Wie die
  alte Konsole sie dann zeichnet, ist nicht gemessen; der ASCII-Fallback haengt an der Kodierung,
  nicht an der Schrift, und faengt diesen Fall nicht ab.

## Werkzeuge mit Nerd Font

Prompt-Werkzeuge, die bewusst eine Nerd Font voraussetzen (wie oh-my-posh oder starship), sind eine
eigene Klasse: Nerd-Font-Icons sind dort erlaubt. Sie brauchen aber einen Rueckfall ohne Nerd Font —
Einstellung oder Erkennung —, der auf die Zeichen oben zurueckgeht.

## Herkunft

Recherche, Quellen (MSBuild, dotnet, gh, cargo, winget, Windows Terminal, WCAG) und Messwerte —
Schriftabdeckung und Kontrast je SGR-Code — stehen in der
[Spec zu ww3d/limen#118](https://github.com/ww3d/limen/blob/1f6632df18ce1e0f6cfdb246ac4836d405f0d2ce/docs/tasks/118-status-colours-glyphs.md).
Die Werte hier sind von dort uebernommen, nicht neu gemessen.
