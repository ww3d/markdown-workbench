# state-audit — Ausgabe und Gate

## Ausgabe

- **Im Kopf der Datei** zwei Zeilen des Metadatenblocks, woertlich so:

  ```text
  - **Commit:** `<sha>`
  - **Timestamp:** <YYYY-MM-DDTHHMMZ>
  ```

  `**Commit:**` traegt den SHA, an dem der Audit genommen wurde.
- **Direkt unter dem Titel die Selbstauskunft** als eigene Zeile: `<!-- audit-worklist: quoted -
  state audit report, describes commit <sha> -->`.
- Die Kurzfassung traegt in wenigen Zeilen: Zahl der geprueften Punkte je Ausgang, das Delta in
  beide Richtungen als Zahl, und was nicht real lief.
- **Aufbau:** Titel · Selbstauskunft · Metadatenblock · **Kurzfassung** · Arbeitsliste je Quelle
  (Zahlen aus dem `source-report`) · Ergebnis je Punkt (Aussage, `Datei:Zeile`, Hash, gefahrener
  Test, Marker vorher/nachher) · Traeger-Wiedervorlage · **Eigene Abweichungen** (Tabelle:
  Abweichung, Grund, Ausgang, Messung) · Delta in beide Richtungen · **Restliste**
  (die `remaining`-Eintraege nach Datei und Abschnitt, dazu die unbestimmten `[partial]`) · was
  nicht real lief.

## Gate

**Erledigt ist der Audit, wenn jeder Punkt der Arbeitsliste einen Ausgang hat** — genau einen von
vier:

- **bestaetigt** — Aussage geprueft, Marker stimmt,
- **korrigiert** — Marker im selben Lauf gezogen,
- **an einen Traeger getragen** — der Punkt steht ab jetzt an einem gueltigen Traeger, den man
  durchzaehlen kann (`.agents/rules/carrier.md` § "Carrier Requirement"),
- **nicht verifiziert (Fremd-Repo <name>)**, Marker `[unverified]` — das Fremd-Repo wird benannt.

Dazu hat jede eigene Abweichung aus Schritt 3b genau einen ihrer drei Ausgaenge.
