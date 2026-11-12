# Paar-Pruefung vor dem Verdichten

Der Auftrag des Helfers der Paar-Pruefung; wer ihn wann startet und was mit seinen Befunden geschieht, steht in
`.agents/rules/session.md` (ww3d/playbook#487). `save` hat geprueft, *ob* ein Traeger jeden Satz seit dem Cursor traegt; der
Helfer prueft, ob die Stelle am Traeger *noch stimmt*.

## Eingang

- **Paar-Datei:** `.agent/state/<session>-pairs.md` im Projekt, eine Zeile je Paar:
  `L<zeile> <art>: <kandidat> => <owner/repo#N>: <passende Stelle>`.
- Nichts sonst: der Helfer liest den Verlauf nicht.

## Ablauf

1. Die Paar-Datei ganz lesen.
2. Je Zeile die Stelle am Traeger gegen den Kandidaten halten; wo die Zeile nicht reicht, den Traeger selbst lesen
   (`gh api repos/<owner>/<repo>/issues/<N> --jq .body`, Kommentare mit `.../comments`).
3. Je Zeile ein Urteil:
   - `ok` - die Stelle gibt den Kandidaten richtig und aktuell wieder;
   - `veraltet` - die Stelle traegt einen alten Stand (Plan-Zeile, Kasten offen statt erledigt, alter Wert);
   - `falsch` - die Stelle schreibt etwas falsch zu oder behauptet, was der Kandidat nicht sagt (falscher Absender,
     Zusage ohne Zustellbeleg, Halt nur im Chat).

## Ergebnis

Nur als Antwort an die Session, keine Datei: je Zeile `L<zeile> ok|veraltet|falsch - <ein Satz Grund>`, die Zeilen
mit `veraltet` und `falsch` zuerst. Nach den Berichtigungen laeuft `save` erneut bis Exit 0.
