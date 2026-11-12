# pr-poll-review — Gate-Kasuistik (Phase 4 und nach dem Merge)

## Was ein positives Abschluss-Verdikt ist

**Positives Abschluss-Verdikt** heisst: jede Aussage, die den PR als fertig, sauber, approve-faehig oder mergebar bezeichnet, auch relativiert. **Kanal egal:** `APPROVE`-Event, `COMMENT`-Review, Issue-Kommentar oder Satz im Chat binden dieses Gate gleich. **Nicht** gebunden: Zwischenverdikte `Blockiert` /
`Approvebar nach Fixes` — dort sind die Threads der Grund.

## Form haelt das Approve nie auf

Was an den Punkten 1, 5 und 7 Form ist und was nicht:

- **Punkt 1:** Form ist die Gestalt der Laufzeile (Felder, Reihenfolge, Plattformliste), wo der
  Lauf am Head belegt ist. Blockt weiter: kein Lauf fuer den Head belegt (die Zeile nennt ihn nicht,
  `red:` ist nicht 0, eine Plattform fehlt ohne `Not run:`).
- **Punkt 5:** Form sind die fehlende Anker-Zeile, die falsche Gestalt der Auto-Close-Zeile, ihr
  Fehlen, wo das Ziel keinen offenen Punkt mehr hat, und ein geschlossenes Anker-Issue. Blockt
  weiter: ein Punkt ohne gueltigen Traeger, offene Haken plus Auto-Close-Zeile, gelieferte, nicht
  abgehakte Punkte, ein verschobener Fix.
- **Punkt 7:** Form ist ein Anker, der nur anders geschrieben ist (`Datei:Zeile`, ein Branch-Link),
  aber am Head die behauptete Stelle trifft. Blockt weiter: ein Beleg-Anspruch ohne Anker oder mit
  einem, der am Head nichts findet.

## Hard-Gate Punkt 4 — eigene Threads

- **Die blockierenden Punkte muessen null sein** — `issue: (blocking)` und
  `question: (blocking)`. Ein offener eigener Thread dieser Art haelt das
  Verdikt auf; das Verdikt zu *formulieren*, bevor die Zaehlung null ergibt, ist selbst schon
  der Verstoss — nicht erst das Absenden.

## Hard-Gate Punkt 5 — was zurueckgestellt zaehlt

Zurueckgestellt sind die Punkte unter "Open questions", "Observations" und "Deliberately not changed" des PR-Bodys und jede F-Nummer, die der User auf "offen lassen" gesetzt hat.

## Hard-Gate Punkt 5 — ganzer Body, vierte Frage

- **Die dritte Frage geht ueber den ganzen Body, nicht ueber die Punkte dieses PRs.** Gelesen wird der Body am Head
  (`gh api repos/<repo>/issues/<n> --jq .body` bzw. `issue_read`), Zeile fuer Zeile: jede
  unabgehakte Checkbox zaehlt, egal aus welcher Runde sie stammt.
- **Offene Haken plus Auto-Close-Zeile = `issue: (blocking)`**, ohne Ermessen.

- **Vierte Frage: steht im Body noch ein unabgehakter Punkt, den dieser PR liefert?** Dann `issue: (blocking)`.

## Gegenpruefung des Hard-Gates — Empfehlung, keine Pflicht

Empfehlung: nach dem eigenen Durchlauf und vor dem positiven Verdikt einen frischen Sub-Agenten (nie den Autor, nie den Schreiber des Reviews) nur die sieben Punkte des `[HARD-GATE]` am Head nachrechnen lassen; er meldet je Punkt `checked` / `not checked` / `finding`. Ohne Sub-Agenten entfaellt der Lauf und wird als nicht gefahren benannt.
