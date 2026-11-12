---
name: chat-handoff
description: 'Schneidet eine laufende Session sauber ab, damit ein Nachfolger in einem neuen Chat weitermacht — bei defekter Session, Neustart, Rotation oder erschoepftem Budget. Triggert bei "handoff", "chat wechseln", "session uebergeben", "neuer chat", "budget erschoepft", "weiter im neuen chat". Baut keinen Auftrags-Prompt.'
metadata:
  version: "6.0.0"
  source: ww3d/playbook
  checksum: "sha256:7ef95516c2f97d04e7846e310e138d529bdbe4cdc29472af1fe5ece25c77b165"
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

Ob eine Uebergabe noetig ist und wo sie steht, regelt `.agents/rules/controller.md` § "Controller Sessions" (Dev-Session: `.agents/rules/pr.md` § "Dev Session").

## Kernprinzip

- Der Nachfolger startet mit der Skill-Zeile seines Sitzes; was der Start sonst tragen darf, regelt `.agents/rules/controller.md` § "Controller Mode", was er nicht traegt und wann ein Controller geschnitten wird, § "Controller Sessions".
- Eine Uebergabe traegt nur Fachliches (Abschnitt "Handoff-Inhalt"), nie Regeln, Ablaeufe, Bloecke oder Vorlagen (Artefakt-Regel: `ccweb-prompt` § "Kernprinzip").

## Ablauf

1. **Persistieren** nach Kernregel 11 und `.agents/rules/carrier.md`. Alles Offene an seinen Traeger, fuer das laufende Design zuerst der Body seines Tracking Issues (fehlt eines: `ccweb-prompt` Schritt 1; bearbeitet mit `scripts/common/edit-issue-body.ps1`).
   Jeden anderen Kommentar als die Routine aus `.agents/rules/chat.md` § "Working With the Maintainer" und die Uebergabe nach `.agents/rules/controller.md` § "Controller Sessions" **erst nach Freigabe** — nie ungefragt.
2. **Vollstaendigkeits-Check.** Zuerst SICHERN: `bash .claude/hooks/session-state.sh save` mit den
   eigenen Traegern (`.agents/rules/pr.md` § "Session Traffic", Punkt 7); seine offenen Kaesten gehen in
   die Liste. Dann die Session rueckwaerts durchgehen und alles auflisten, was offen, aber nirgends persistiert ist. Hat das Session-Werkzeug die Faehigkeit, die Eingaben einer Session nach Herkunft aufzulisten (`.agents/rules/controller.md` § "Steering Messages"), arbeitet der Gang ihre Liste ab, Eingabe fuer Eingabe, von der letzten bis zum Start; jede bekommt einen Traeger oder steht als offen in der Liste. Ohne die Faehigkeit geht der Gang durch den Verlauf; was er nach einer Verdichtung nicht mehr zeigt, steht in der Liste mit dem Zeitpunkt der Verdichtung. Die Eingaben des
   Vorgaengers gelten nur als geprueft, wenn sein `## Hand-back` die Check-Zeile traegt; fehlt sie,
   gehen sie mit in den Gang. Die Liste vorlegen und bestaetigen lassen, dass nichts fehlt, bevor
   die Session endet. Im Controller-Modus steht die Liste — oder "keine" — an ihrem Traeger nach `.agents/rules/controller.md` § "Controller Sessions", nie als Nachricht; was an den Controller geht, regelt `.agents/rules/pr.md` § "Session Traffic".
3. **Uebergabe, nur wenn noetig.** Verlangt `.agents/rules/controller.md` § "Controller Sessions" eine oder ginge sonst Stand verloren: den Handoff-Inhalt dort schreiben, wo diese Stelle ihn hinlegt.
4. **Handoff-Datei, nur als letzter Ausweg.** Nur fuer Stand, der sich weder an einen Traeger noch an seinen Ort im Repo bringen laesst. Dann im
   claude.ai-Chat `create_file` + `present_files`, in Claude Code die Datei im Scratchpad der
   Session schreiben und ihren Pfad nennen — Struktur siehe unten, mit der Anweisung, die Datei im
   neuen Chat **als Datei anzuhaengen**.
5. Eine geschnittene Session startet vorher ihren Nachfolger selbst (`.agents/rules/controller.md` § "Controller Sessions").

## Handoff-Inhalt

Wo die Uebergabe steht, regelt `.agents/rules/controller.md` § "Controller Sessions".

## Handoff-Datei

- **Dateiname:** `YYYY-MM-DDTHHMMZ-handoff.md`.
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
