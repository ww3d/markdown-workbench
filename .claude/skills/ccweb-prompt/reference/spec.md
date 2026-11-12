# Spec-Datei bauen

Die Spec-Datei `docs/tasks/<issue>-<slug>.md` ist der Auftrag an die Dev-Session.

## Lese-Auftrag

Die Spec beginnt mit dem Satz *"Bei Widerspruch Spec vs. Docs gewinnen Docs — ausser die Spec setzt
eine Entscheidung um, die die Docs aendern soll."*, danach die Bloecke.

**Modell-Angabe:** die Zeile `Dev-Model: <modell>` nach `.agents/rules/agents.md` § "Models".

## Die Bloecke

Vor den Bloecken: der Auftrag des Maintainers woertlich.

- **The maintainer's order verbatim:** every spec — and every order text — carries the maintainer's
  order word for word (spelling corrected only), with date and source, under its own heading at the
  top, its sentences numbered. Every REQ names the sentence it implements (`from sentence 3`), a REQ
  from a design decision that decision (`from decision 4`); every sentence has at least one REQ or
  stands as `not implemented: <reason>`.
- Every REQ carries **exactly one refutable statement**. IDs are never renumbered.
- **No evidence line, coverage type or status per REQ:** the diff shows what is met, and evidence is
  owed only for what it does not show (`.agents/rules/evidence.md`); a second description drifts.

1. **Kontext** — Anlass, relevante Issues, Decision-Log und Zeilen-Datei der Runde, der Branch, auf
   dem die Spec liegt, und die bekannt roten Tests und Laeufe am Audit-Commit aus dem Audit-Kopf des
   neuesten State Audits.
2. **Aufgabe** — was konkret umzusetzen ist.
3. **Vorgaben** — die Aufgabe als nummerierte Liste `REQ-01`, `REQ-02`, … (ab mehr als 20 Punkten
   dreistellig: `REQ-001`). Der Schnitt in Aussagen liegt hier, nicht beim umsetzenden Agent: deckt
   eine Vorgabe mehrere Oberflaechen, Komponenten oder Lieferungen ab, wird sie in mehrere REQs
   aufgeteilt.
   - **Groesse und Schnitt.** Die Design-Session schaetzt je PR die geaenderten Zeilen und Dateien —
     reine Verschiebungen und generierte Dateien zaehlen nicht — und nennt die Schaetzung im Block
     **Aufgabe**. Ziel sind rund 500 Zeilen und hoechstens 10 Dateien; ab 1.000 Zeilen oder 40
     Dateien schneidet sie in mehrere PRs nacheinander, je mit eigener Spec-Datei und eigenem
     REQ-Bereich, oder begruendet die Ausnahme im Decision-Log und mit der Zeile `Size exception:
     <Grund>` unter `## Design` des Tracking Issues.
   - **Doku-Nachzug wird einzeln aufgezaehlt.** Verlangt die Spec, die Doku nachzuziehen, nennt sie
     jede Wahrheitsquelle **namentlich und je als eigenes `REQ-NN`** — `architecture.md`,
     `roadmap.md`, `backlog.md`, die betroffenen Nutzer-Docs.
4. **Gates** — Akzeptanz als ausfuehrbare Commands und pruefbare Kriterien, passend zum vollen Lauf
   aus `CLAUDE.md` (`.agents/rules/pr.md` § "Test Runs").

## Review-Modus waehlen

**Vorschlag fuer neue Specs: `once`.** `hard` waehlt die Design-Runde nach Risiko: breite oder
sicherheits-/performance-kritische Slices und alles, was in einen Hot Path fasst.

## Quellen in der Spec

Unerreichbares wird nicht verlinkt, sondern **inline in die Spec** uebernommen; der Verweis bleibt
nur als Herkunftsangabe.
