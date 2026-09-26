---
name: chat-handoff
description: 'Schneidet eine laufende Session sauber ab, damit ein Nachfolger in einem neuen Chat weitermacht — bei defekter Session, Neustart, Rotation oder erschoepftem Budget eines Claude-Accounts. Regelfall ohne Handoff: alles Offene geht nach Freigabe an einen gueltigen Traeger (Body des offenen Tracking Issues, Zeile in roadmap.md/backlog.md oder Issue im Fremd-Repo) — nie in einen Kommentar —, dann startet der Nachfolger mit dem schlanken Startauftrag seiner Rolle und liest den Stand selbst nach. Geht die Session vorher rueckwaerts durch und listet alles "offen, aber nirgends persistiert" zur Bestaetigung. Ein Handoff nur, wenn sonst Stand verloren ginge: nur Fachliches, im Tracking Issue; eine Handoff-Datei (`YYYY-MM-DDTHHMMZ-handoff.md`) nur fuer Stand, der sich nirgends im Repo ablegen laesst. Triggert bei "handoff", "chat wechseln", "session uebergeben", "neuer chat", "budget erschoepft", "weiter im neuen chat". Baut keinen Auftrags-Prompt — dafuer ist ccweb-prompt zustaendig. Nutzt das GitHub MCP oder `gh`.'
metadata:
  version: "4.0.0"
  source: ww3d/playbook
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
Neustart, Rotation, oder das Budget des benutzten Claude-Accounts ist aufgebraucht. Der Regelfall
braucht keinen Handoff: der Nachfolger liest den Stand selbst dort, wo er ohnehin steht.

## Kernprinzip

- **Persist-first.** GitHub ist der Truth-Store. Was an ein Issue oder einen PR gehoert, wird dort
  festgehalten, **bevor** die Session endet. Danach bleibt im Regelfall nichts mehr zu uebergeben.
- **Ein offener Punkt geht an einen Traeger, nicht in einen Kommentar.** Gueltig sind nur die Orte
  aus `.agents/rules/carrier.md` § "Carrier Requirement": der **Body des offenen Tracking Issues**
  des laufenden Designs · eine Zeile in `roadmap.md`/`backlog.md` · fuer einen nur im Fremd-Repo
  umsetzbaren Punkt ein offenes Issue dort. Issue-Kommentar,
  PR-Body, Decision-Log, Spec-Datei und ein `[geplant]`/`[teilweise]`-Marker sind ausdruecklich
  **keine** Traeger — der Marker ist Soll/Ist-Anzeige, den Rest liest niemand als Arbeitsvorrat
  zurueck. Kommentare bleiben zulaessig fuer Kontext, der kein offener Punkt ist (Zwischenstand,
  Begruendung, Verweis).
- **Schlanker Startauftrag.** Der Nachfolger startet mit dem Startauftrag seiner Rolle und nichts
  sonst — fuer einen Controller steht er in `.agents/rules/pr.md` § "PR Lifecycle", Unterabschnitt
  "Controller Mode". Keine durchgetragenen Dateien, keine Verweise, keine Vorlagen: Playbook,
  Skills, Issues samt Tracking Issues und PRs liest er selbst.
- **Handoff nur, wenn sonst Stand verloren ginge.** Er traegt nur Fachliches (Abschnitt
  "Handoff-Inhalt") und steht im Tracking Issue, nie Regeln, Ablaeufe, Bloecke oder Vorlagen — es
  gilt die Artefakt-Regel aus `AGENTS.md` § "Session Start: Read Before Anything Else".

## Ablauf

1. **Persistieren.** Alles Offene und noch nicht Festgehaltene an einen gueltigen Traeger: den Body
   des Tracking Issues des laufenden Designs (fehlt eines, wird es angelegt —
   `.agents/rules/carrier.md` § "Tracking Issue"), eine Zeile in `roadmap.md`/`backlog.md` oder, fuer
   einen nur im Fremd-Repo umsetzbaren Punkt, ein offenes Issue dort (§ "Carrier Requirement").
   Dateien, die nur im Chat-Output liegen (typisch: ein laufendes Decision-Log), gehen an ihren Ort
   im Repo. Kontext ohne offenen Punkt darf als Kommentar an das jeweilige Issue / den PR. **Erst
   nach Freigabe posten oder committen** — nie ungefragt.
2. **Vollstaendigkeits-Check.** Die Session rueckwaerts durchgehen und alles auflisten, was "offen,
   aber nirgends persistiert" ist — getroffene Entscheidungen ohne Log-Eintrag, ausgeraeumte
   Fehlannahmen, vertagte Punkte, laufende Auftraege. Die Liste vorlegen und bestaetigen lassen,
   dass nichts fehlt, bevor die Session endet. Im Controller-Modus wird die Liste dem Controller per
   `rc ask` vorgelegt, nicht im Chat.
3. **Handoff, nur wenn noetig.** Bleibt nach Schritt 1 Stand uebrig, der sonst verloren ginge:
   Handoff-Inhalt ins Tracking Issue schreiben, nach Freigabe. Sonst entfaellt der Schritt.
4. **Handoff-Datei, nur als letzter Ausweg.** Nur fuer Stand, der sich weder an einen Traeger noch
   ins Tracking Issue noch an seinen Ort im Repo bringen laesst (etwa ohne Schreibrecht). Dann
   `create_file` + `present_files`, Struktur siehe unten, mit der Anweisung, die Datei im neuen
   Chat **als Datei anzuhaengen**.

## Handoff-Inhalt

Nur Fachliches, nie eine Zusammenfassung dessen, was ohnehin in Issues oder PRs steht — dort steht
nur die Referenz:

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

- Nichts nach GitHub posten ohne Freigabe — auch nicht "nur schnell den Stand".
- **Kein offener Punkt in einen Kommentar.** Ein Issue-Kommentar meldet den Punkt, traegt ihn aber
  nicht — er braucht einen der Traeger aus dem Kernprinzip.
- Kein Handoff und keine Datei, wo der Stand schon im Repo steht; wo etwas persistiert wurde, steht
  nur die Referenz.
- Kein Startauftrag, der mehr traegt als seine Rolle vorsieht — kein Stand des Vorgaengers, kein
  Verweis auf einen Handoff.
- Kein Schnitt ohne den Vollstaendigkeits-Check aus Schritt 2.
- Der Schnitt baut keinen Auftrags-Prompt — das ist `ccweb-prompt` (anderer Zweck, eigener
  Trigger-Raum). Einen Review-Prompt baut niemand mehr; `pr-poll-review` beschafft seinen Kontext
  selbst.

## Repo-Konventionen

- `git` + `gh` sind Default fuer alle GitHub-Operationen (`AGENTS.md` § "Forge Tooling"); das
  GitHub MCP nur als Fallback oder fuer MCP-only-Tools.
- Sprache der geposteten Kommentare/Bodies nach `AGENTS.md` § "Language" (Deutsch fuer Inhalt).
