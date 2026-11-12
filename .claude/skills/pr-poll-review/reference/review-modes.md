# Review-Modus-Bausteine

Die eine Stelle fuer den Wortlaut der Review-Modi.

**Wortlaut nie umformulieren.**

### Modelle der Wellen

- The coordinator names the critical focus; in a follow-up wave split by area it is the area holding
  the fixes.
- Every partial check inside a review runs Sonnet at least.
- A review without a wave is the critical focus.

## hard

Traegt eine Versions-Kennung, hochgezaehlt, sobald sich Schwerpunkte, Loop-Regel oder Cap aendern.

```md
Review-Mode: `hard v4`

Vor dem PR und vor jeder Fix-Runde eine parallele Welle von 3-4 Review-Sub-Agenten: frische
Sessions, verschiedene Schwerpunkte (Korrektheit/Randfaelle, Performance/Hot Paths, Vertraege/Docs,
Test-Luecken), alle auf demselben Commit-Stand. Befunde mergen/dedupen, fixen; die naechste Welle
verifiziert erst die Fixes.

Jede Welle meldet in Conventional Comments: je Punkt `issue:` / `nitpick:` / `question:` mit
`(blocking)` oder `(non-blocking)`, bei Altcode zusaetzlich `(pre-existing)`
(`.agents/rules/review.md` § "Review Comments").

Ab Welle 2 wird der Diff nach Bereich unter den Agenten geteilt, nicht viermal vollstaendig gelesen.

Abbruch, sobald eine Welle nur noch `nitpick:` findet. **Hard-Cap 2 Wellen, und der Cap geht der
Abbruch-Bedingung vor. Der Cap begrenzt die Wellen, nicht das Fixen:** was nach der zweiten Welle
offen ist, in einer Datei liegt, die der PR anlegt oder aendert, und einen bekannten Fix hat, wird
im PR gefixt. Alles andere Baubare: `.agents/rules/carrier.md` § "Carrier Requirement".

Reine Loesch-Diffs bekommen keine Welle. Dort traegt ein Waechter-Test, der rot wird, sobald das
Geloeschte wieder auftaucht.

```

## light

```md
Review-Mode: `light`

Eine einzige Gegen-Welle: 1 frischer Sub-Agent, voller Gegencheck, Modell nach `.agents/rules/agents.md` § "Models". Befunde fixen.
```

## soft

```md
Review-Mode: `soft`

Autonom bis zum Ende, Schleife bis perfekt und ohne Befunde: Self-Review + Refactoring-Runden,
Annahmen dokumentieren.
```

## once

Gilt mit und ohne Controller gleich.

```md
Review-Mode: `once`

Vor dem PR eine einzige Gegen-Welle wie bei `light`: 1 frischer Sub-Agent, voller Gegencheck, Modell
nach `.agents/rules/agents.md` § "Models". Befunde fixen.

Der Pruefer liest den PR in Runde 1 einmal voll und postet seinen Bericht ohne Freigabe durch Mensch
oder Controller; die Zeilen-Datei der Runde bleibt Pflicht (`reference/report.md` § "Zeilen-Datei der Runde").

Ein `issue: (blocking)` blockiert nur mit (1) einem Fehlerfall (Eingabe oder Zustand -> falsches
Ergebnis), (2) der genannten Blocker-Regel aus `.agents/rules/review.md`, die er bricht, oder (3) bei
Sicherheit, Datenverlust oder Nebenlaeufigkeit mit dem Pfad als Datei:Zeile; jeder andere Punkt geht
als `suggestion:` oder `nitpick:`. Eine `question: (blocking)` geht zusaetzlich als blockierende
Frage an den Besitzer des Pruefers (`.agents/rules/pr.md` § "Session Traffic").

Widerspricht der Autor einem blockierenden Punkt mit einem Satz am Thread und haelt der Pruefer ihn
im naechsten Blick, geht der Punkt als Frage an den Besitzer des Pruefers, im Controller-Modus weiter
an den Maintainer; die Entscheidung steht in der Zeilen-Datei der Runde als `accepted` oder als
`rejected` mit `reopen_only_with`.

Ab Runde 2 liest der Pruefer nur `git diff <gepruefter Head>..<neuer Head>`. Ein frueherer
blockierender Punkt ist zu, wenn sein Fehlerfall am neuen Head das richtige Ergebnis liefert oder
seine Regel dort erfuellt ist (dieselbe Suche der Fehlerart). Neue Punkte nur an Zeilen, die die
Korrektur geaendert hat; kein Lesen ueber den Diff hinaus, keine Aufrufer-Suche.

Runde 1 voll, Runden 2 und 3 je ein Blick. Blockiert der Blick der Runde 3 wieder, geht der PR an den
Maintainer (im Controller-Modus ueber den Controller); die Zeile `Review-Round-Decision:` vor Runde 4
traegt seine Entscheidung mit Quelle. Die Kreis-Regel (`.agents/rules/review.md` § "Hand-Back and Owner Change")
bleibt.
```
