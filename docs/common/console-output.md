# Konsolenausgabe: Status-Zeichen und Farben

Gilt fuer jedes ww3d-Werkzeug, das Statuszeilen fuer Menschen in ein Terminal schreibt — gleich in
welcher Sprache. Die Werte unten sind fest.

## Zeichen und Farben

| Status | Zeichen | ASCII-Fallback | Farbe (SGR) |
|---|---|---|---|
| Fehler | `×` U+00D7 | `x` | `91` hellrot, **ganze Zeile** |
| Erfolg | `✓` U+2713 | `+` | `32` gruen, nur das Zeichen |
| Warnung | `!` | `!` | `33` gelb, nur das Zeichen |
| Info / Eintrag | `▶` U+25B6 | `>` | `36` cyan, nur das Zeichen |
| Ueberschrift | — | — | `96` hellcyan, ganze Zeile |
| Nebenzeile | — | — | `38;5;246` grau, ganze Zeile |

Fuehrt es einen, dann mit diesem Zeichen und dieser Farbe — kein eigenes Symbol fuer dieselbe
Aussage. Jedes Nicht-ASCII-Zeichen hat einen ASCII-Fallback; er greift, wenn die Ausgabe kein UTF-8
traegt (umgeleitete Ausgabe, alte Codepage).

`§` gehoert nicht in die Ausgabe; dort steht `section`.

**Nicht verwenden:** `✗` `✘` `✖` `✔` `⚠` `ℹ`.

## Regeln

- **Nur Zeichen aus der Standardschrift.** Massstab ist Cascadia Mono/Code, die Standardschrift von
  Windows Terminal. Ein neues Zeichen kommt erst hinein, wenn seine Abdeckung dort gemessen ist.
- **Farbe ist nie das einzige Signal.** Zeichen und Text tragen die Aussage allein; die Farbe
  verstaerkt nur.
- **Kontrast WCAG AA (4,5:1)** gegen das Schwarz von Windows Terminal (`#0C0C0C`).
- **Farbe abschaltbar:** `NO_COLOR` (gesetzt, nicht leer), `--no-color` und `TERM=dumb` schalten
  sie ab, ebenso eine Ausgabe, die nicht in ein Terminal geht.

## Werkzeuge mit Nerd Font

Prompt-Werkzeuge, die bewusst eine Nerd Font voraussetzen, sind eine eigene Klasse: Nerd-Font-Icons
sind dort erlaubt. Sie brauchen aber einen Rueckfall ohne Nerd Font — Einstellung oder Erkennung —,
der auf die Zeichen oben zurueckgeht.
