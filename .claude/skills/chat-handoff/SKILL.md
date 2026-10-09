---
name: chat-handoff
description: 'Schneidet eine laufende Session sauber ab, damit ein Nachfolger in einem neuen Chat weitermacht — bei defekter Session, Neustart, Rotation oder erschoepftem Budget. Triggert bei "handoff", "chat wechseln", "session uebergeben", "neuer chat", "budget erschoepft", "weiter im neuen chat". Baut keinen Auftrags-Prompt.'
metadata:
  version: "5.1.0"
  source: ww3d/playbook
  checksum: "sha256:3d4fa430d83a9587d948e1c4a37a2f2c143db77185b913ae6558d845f2a4f220"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#210"
---

# Session-Schnitt in einen neuen Chat

Macht eine laufende Session in einem frischen Chat verlustfrei fortsetzbar — defekte Session,
Neustart, Rotation, oder das Budget des benutzten Claude-Accounts ist aufgebraucht. Ob eine
Uebergabe noetig ist und wo sie steht, regelt `.agents/rules/pr.md` § "Controller Sessions"; sonst
liest der Nachfolger den Stand selbst dort, wo er ohnehin steht.

## Wann

Wenn eine Session endet, bevor ihre Arbeit fertig ist — defekte Session, Neustart, Rotation oder
erschoepftes Budget eines Claude-Accounts. Alles Offene geht an einen gueltigen Traeger — nie in
einen Kommentar —, dann startet der Nachfolger mit seiner Startzeile und liest den Stand selbst
nach. Vorher geht die Session rueckwaerts durch und listet alles "offen, aber nirgends
persistiert" zur Bestaetigung. Eine Uebergabe nach `.agents/rules/pr.md` § "Controller Sessions",
nur Fachliches; eine Handoff-Datei (`YYYY-MM-DDTHHMMZ-handoff.md`) nur fuer Stand, der sich
nirgends im Repo ablegen laesst. Den
Auftrags-Prompt baut `ccweb-prompt`. Nutzt `gh api` (REST) oder das GitHub MCP.

## Kernprinzip

- **Persist-first.** GitHub ist der Truth-Store. Was an ein Issue oder einen PR gehoert, wird dort
  festgehalten, **bevor** die Session endet. Danach bleibt im Regelfall nichts mehr zu uebergeben.
- **Ein offener Punkt geht an einen Traeger, nicht in einen Kommentar.** Gueltig sind nur die Orte
  aus `.agents/rules/carrier.md` § "Carrier Requirement" — fuer das laufende Design zuerst der
  **Body seines offenen Tracking Issues**; was dort nicht als Traeger zaehlt, liest niemand als
  Arbeitsvorrat zurueck. Kommentare bleiben
  zulaessig fuer Kontext, der kein offener Punkt ist (Zwischenstand, Begruendung, Verweis).
- **Schlanker Startauftrag.** Der Nachfolger startet mit der Skill-Zeile seines Sitzes (Tabelle in
  `controller-mode` § "Schritt 4: Steuern"); was der Start sonst tragen darf, regelt
  `.agents/rules/pr.md` § "Controller Mode", was er nicht traegt und wann ein Controller
  geschnitten wird, § "Controller Sessions". Playbook, Skills, Issues samt Tracking Issues und PRs
  liest er selbst.
- **Uebergabe nur nach `.agents/rules/pr.md` § "Controller Sessions".** Sie traegt nur Fachliches
  (Abschnitt "Handoff-Inhalt"), nie Regeln, Ablaeufe, Bloecke oder Vorlagen — es gilt die
  Artefakt-Regel aus `AGENTS.md` § "Session Start: Read Before Anything Else".

## Ablauf

1. **Persistieren.** Alles Offene und noch nicht Festgehaltene an einen gueltigen Traeger
   (`.agents/rules/carrier.md` § "Carrier Requirement"), fuer das laufende Design zuerst der Body
   seines Tracking Issues (fehlt eines, wird es angelegt — `.agents/rules/carrier.md` § "Tracking
   Issue"; bearbeitet mit `scripts/common/edit-issue-body.ps1`).
   Dateien, die nur im Chat-Output liegen (typisch: ein laufendes Decision-Log), gehen an ihren Ort
   im Repo. Kontext ohne offenen Punkt darf als Kommentar an das jeweilige Issue / den PR. Was
   Routine ohne Freigabe ist — Body bearbeiten, Push —, sagt `AGENTS.md` § "Working Mode",
   dazu die Uebergabe nach `.agents/rules/pr.md` § "Controller Sessions"; jeden anderen Kommentar
   **erst nach Freigabe** — nie ungefragt.
2. **Vollstaendigkeits-Check.** Die Session rueckwaerts durchgehen und alles auflisten, was "offen,
   aber nirgends persistiert" ist — getroffene Entscheidungen ohne Log-Eintrag, ausgeraeumte
   Fehlannahmen, vertagte Punkte, laufende Auftraege. Die Liste vorlegen und bestaetigen lassen,
   dass nichts fehlt, bevor die Session endet. Im Controller-Modus geht die Liste nicht als
   Nachricht an den Controller: ihre Punkte stehen nach Schritt 1 am Traeger, und der Controller
   prueft dort; was an ihn geht — die Abgabe mit dem Link, ein Punkt, der eine Entscheidung braucht,
   als blockierende Frage —, regelt `.agents/rules/pr.md` § "Session Traffic".
3. **Uebergabe, nur wenn noetig.** Verlangt `.agents/rules/pr.md` § "Controller Sessions" eine
   oder bleibt nach Schritt 1 Stand uebrig, der sonst verloren ginge: den Handoff-Inhalt dort
   schreiben, wo diese Stelle ihn hinlegt, Freigaben wie in Schritt 1. Sonst entfaellt der Schritt.
4. **Handoff-Datei, nur als letzter Ausweg.** Nur fuer Stand, der sich weder an einen Traeger noch
   ins Tracking Issue noch an seinen Ort im Repo bringen laesst (etwa ohne Schreibrecht). Dann im
   claude.ai-Chat `create_file` + `present_files`, in Claude Code die Datei im Scratchpad der
   Session schreiben und ihren Pfad nennen — Struktur siehe unten, mit der Anweisung, die Datei im
   neuen Chat **als Datei anzuhaengen**.
5. **Abgabe.** Zum Schluss geht die Abgabe an den Besitzer der Session, wo es einen gibt: nur der
   Link auf ihren Traeger (`.agents/rules/pr.md` § "Session Traffic", Punkt 2). Eine geschnittene
   Session startet vorher ihren Nachfolger selbst, nennt ihn am Traeger und schickt "Rotation
   ready" mit Link und Namen des Nachfolgers; der Nachfolger beendet sie
   (`.agents/rules/pr.md` § "Controller Sessions").

## Handoff-Inhalt

Nur Fachliches, nie eine Zusammenfassung dessen, was ohnehin in Issues oder PRs steht — dort steht
nur die Referenz. Wo die Uebergabe steht, regelt `.agents/rules/pr.md` § "Controller Sessions"; im
Tracking Issue so:

- **Offen** → Body des Tracking Issues (Traeger).
- **Erledigt**, **Entscheidungen**, **je Worker Branch, Head, PR**, **naechster Schritt** →
  Status-Kommentar des Tracking Issues.

## Handoff-Datei

Nur fuer Schritt 4.

- **Dateiname:** `YYYY-MM-DDTHHMMZ-handoff.md` — Zeitstempel nach `.agents/rules/docs.md`
  § "Timestamps in File Names", `.md`-Endung bleibt dran (Typ-Erkennung beim Download).
- **Uebergabe:** herunterladen und im neuen Chat als Datei anhaengen. Nicht ueber den gerenderten
  Chat kopieren — das zerstoert das Markdown.
- **Feste Reihenfolge** der Abschnitte:

```md
<!-- transport: verbatim, do not re-render -->
# projekt(modul): thema - issue #N - pr #M

**Naechster Schritt:** <naechster Schritt>

## Stand
- Erledigt: <was fertig ist, mit Issue-/PR-Referenz>
- Offen: <was aussteht, mit Issue-/PR-Referenz>
- Worker: <je Worker Branch, Head, PR>

## Nicht im Repo ablegbar
<Stand und Entscheidungen, die in keinem Issue, PR oder Log stehen koennen, mit Grund>
```

- Die H1-Zeile ist der **Chatname** im Conventional-Format `projekt(modul): thema - issue #N -
  pr #M`; fehlt ein Issue oder PR, entfaellt der Teil.
- Der Marker `<!-- transport: verbatim, do not re-render -->` steht immer als erste Zeile.

## Strikte Regeln

- Nichts nach GitHub posten ohne Freigabe — auch nicht "nur schnell den Stand"; die Ausnahmen nennt
  Schritt 1.
- **Kein offener Punkt in einen Kommentar.** Ein Issue-Kommentar meldet den Punkt, traegt ihn aber
  nicht — er braucht einen der Traeger aus dem Kernprinzip.
- Kein Handoff und keine Datei, wo der Stand schon im Repo steht; wo etwas persistiert wurde, steht
  nur die Referenz.
- Kein Startauftrag ueber `.agents/rules/pr.md` § "Controller Mode" hinaus — kein Stand des
  Vorgaengers, kein Verweis auf einen Handoff.
- Kein Schnitt ohne den Vollstaendigkeits-Check aus Schritt 2.
- Der Schnitt baut keinen Auftrags-Prompt — das ist `ccweb-prompt` (anderer Zweck, eigener
  Trigger-Raum), und dort steht auch, dass es keinen Review-Prompt gibt.

## Repo-Konventionen

- GitHub-Zugriffe nach `AGENTS.md` § "Forge Tooling".
- Sprache der geposteten Kommentare/Bodies nach `AGENTS.md` § "Language".
