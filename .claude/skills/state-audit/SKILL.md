---
name: state-audit
description: 'Faehrt vor jedem neuen Design den Schnell-Check und, wenn faellig, den vollen State Audit nach `.agents/rules/audit.md` § "State Audit" — das Gate aus `ccweb-prompt` Schritt 0. Setzt Checkout, Build, Test und `git grep` voraus. Triggert bei "state audit", "ist-stand pruefen", "audit vor der scheibe", "soll-ist abgleich".'
metadata:
  version: "5.3.7"
  source: ww3d/playbook
  checksum: "sha256:109323104f7ff01e0cb9ce69eb2d98d91c81d514a5ae95fda690b3dd7babce78"
  # Written by ./scripts/check-skill-budget.ps1 -UpdateMeasurement, which needs an
  # ANTHROPIC_API_KEY; every later run recomputes the value and reports drift. Empty means no
  # real measurement has run yet - an invented number would be the false green this gate is against.
  measurement:
    tokens:
    model:
    measured:
    source: "not measured - no ANTHROPIC_API_KEY in the build environment of ww3d/playbook#210"
---

# State Audit

**Dieser Skill ist ein `ccweb`-Skill.**

## Schritt 0: Schnell-Check, dann faellig oder nicht

Vor jedem Design laeuft der **Schnell-Check** (`.agents/rules/audit.md` § "State Audit", "Quick
Check"):

- Skript fahren: `pwsh scripts/common/get-audit-worklist.ps1 -Repo <owner/name>` — Zahl der
  Punkte je Quelle und die `aged:`-Zeilen des Backlogs.
- Skript fahren: `pwsh scripts/common/sweep-carriers.ps1 -Repo <owner/name> -Since <Stempel des
  letzten Audits>` — der Stempel aus dem Dateinamen (`YYYY-MM-DDTHHMMZ`) oder ein Datum
  `YYYY-MM-DD`; das Skript meldet geschlossene Tracking Issues mit offenen Haken und Verweise auf
  geschlossene Traeger.
- Skript fahren: `pwsh scripts/common/find-closable-issues.ps1 -Repo <owner/name>` — schliessbare
  Issues mit Checkliste.
- Skript fahren: `pwsh scripts/common/test-plan-labels.ps1 -Repo <owner/name>` — Befunde der
  Plan-Regel (`controller-mode` § "Planung"): Tracking Issue ohne Plan-Label, mehr als ein
  Label, Deckel von `plan/now`, Rang-Zeilen; Exit 1 bei Befund, 2 bei Lesefehler.

Ohne Skripte: dieselben vier Fragen von Hand nach Schritt 1 und Schritt 3, und die Zeile sagt `by
hand`.

Nicht faellig → der Skill endet mit der Zeile. Faellig → weiter mit Schritt 1.

## Schritt 1: Arbeitsliste erzeugen

Skript fahren: `pwsh scripts/common/get-audit-worklist.ps1 -Repo <owner/name>`; das Ergebnis wird
gelesen, nicht neu zusammengesucht. Spalten und Listen erklaert `scripts/common/README.md`. Ohne
Skript werden die drei Quellen unten von Hand gesammelt, und der Bericht sagt das. Drei Quellen:

1. **Soll/Ist-Marker** — jede Aussage in den Architektur-/Baseline-Docs mit `[met]`, `[partial]`,
   `[planned]` oder `[unverified]`, mit Pfad und Zeile.
2. **Offene Punkte der Tracking Issues** — der Body jedes offenen Issues mit dem Label `tracking`,
   Punkt fuer Punkt, **und dessen GitHub Sub-Issues**.
3. **`TODO` / `HACK` / `FIXME`** in Code und in der Prosa der Wahrheitsquellen; ein Marker ohne
   Traeger-Referenz ist selbst ein Befund.

Ist eine Quelle leer, wird das im Bericht gesagt.

Aus der Arbeitsliste kommen zusaetzlich vier Angaben, die spaetere Schritte lesen:

- **Liste `backlog`** — jede offene `backlog.md`-Zeile mit ihrem Alter: Quelle der Alterung in
  Schritt 3.

- **Spalte `Carrier` je Marker — Quelle fuer `.agents/rules/audit.md` § "State Audit", "Full Audit".**
- **Liste `uncovered-carriers`** — offene Tracking Issues und Punkte, auf die kein Marker-Verweis
  zeigt; Eingang fuer die zweite Richtung (`.agents/rules/audit.md` § "State Audit", "Full Audit").
- **Liste `remaining`** — jede `missing:`-Angabe mit Datei, Abschnitt und Hash: die Restliste. Ein
  `[partial]` ohne `missing:` steht mit einer `Note` `… (undetermined)` in der Liste und wird nach
  `.agents/rules/audit.md` § "State Audit", "Full Audit" als unbestimmt gemeldet.

## Schritt 2: Pruefreihenfolge je Punkt

Fest, in dieser Reihenfolge — kein Punkt wird uebersprungen, keine Stufe vorgezogen:

1. **Aussage lesen.**
2. **Im Code verifizieren.** Die Stelle suchen (`git grep`), lesen, `Datei:Zeile` notieren.
3. **Test real fahren.** Den Test, der die Aussage traegt, wirklich starten. Gibt es keinen, ist das
   der Befund.
4. **Marker bestaetigen oder korrigieren.** Passt er, bleibt er stehen; passt er nicht, wird er im
   selben Lauf auf den wahren Wert gezogen.

## Schritt 3: Traeger-Wiedervorlage

Hier wird der Bestand der Traeger geprueft:

- **Zeigt jeder Traeger-Link noch auf ein offenes Ziel?**
- **Die seit dem letzten Audit geschlossenen Tracking Issues auf offene Haken durchgehen.** Jedes
  Issue mit Label `tracking`, das seit dem Stempel des vorigen Audits geschlossen wurde (ohne
  Vorgaenger-Audit alle geschlossenen), Body Zeile fuer Zeile: jede unabgehakte Checkbox ist ein
  Befund. Sie wird an einen offenen Traeger gehoben — Nachfolge-Tracking-Issue oder
  `backlog.md`-Zeile — und der Fund im Bericht benannt. Skript fahren: `pwsh
  scripts/common/sweep-carriers.ps1 -Repo <repo> -Since <Stempel des vorigen Audits>`. Ohne Skript:
  die geschlossenen `tracking`-Issues per REST (`gh api
  "repos/<repo>/issues?state=closed&labels=tracking"` bzw. `list_issues`) holen, nach Schliessdatum
  filtern und jeden Body lesen.
- **Traegt das Ziel wirklich den Punkt?** Am Head nachlesen.
- **Ist ein Issue mit Checkliste fertig?** Das gilt fuer jedes, mit oder ohne Label `tracking`. Dann
  schliessen — aber erst, nachdem geprueft ist, was darauf zeigt (`.agents/rules/carrier.md` §
  "Carrier Requirement"). Skript fahren: `pwsh scripts/common/find-closable-issues.ps1 -Repo <repo>`
  ohne `-Pr`. Jedes `closable` ist ein Fund und steht mit seiner Nummer im Bericht; `SOURCE
  UNAVAILABLE` steht dort als nicht verifiziert. Ohne Skript: je offenem Issue mit Checkliste den
  Body am Head auf offene Haken lesen und per `git grep` nach `#N` pruefen, was noch darauf zeigt.
- Die Quelle `backlog` der Arbeitsliste fuehrt jede offene Zeile mit `Note` `aged: …` (hochspuelen),
  `ages: …` (liegt weiter) oder `exempt: …`.

## Schritt 3b: Eigene Abweichungen pruefen

Der Schritt sammelt sie zuerst ein, dann prueft er jede:

1. **Einsammeln**, je mit Fundstelle: die Ausnahmen in der `CLAUDE.md` des Repos, die Abweichungen
   von einer Upstream- oder Vorlagen-Quelle (`git grep` nach den Formeln, mit denen das Repo sie
   kennzeichnet) und die Ausnahme-Datei der Ordner-Konventionen (`.agents/rules/code.md` § "Folder
   Conventions"). Eine leere Liste wird im Bericht als leer gesagt, nie weggelassen.

## Ausgabe und Gate

**Zuerst lesen und quittieren:** [`reference/report.md`](reference/report.md).
