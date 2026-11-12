# pr-poll-review — Pruefkatalog (Phase 1)

## Inhalt

- [Fehlendes Artefakt — wann es blockt](#fehlendes-artefakt--wann-es-blockt)
- [Sub-Agent-Passes und Modellwahl](#sub-agent-passes-und-modellwahl)
- [Agent-Red-Flags (zuerst, harte Sachen)](#agent-red-flags-zuerst-harte-sachen)
- [Doku-Integritaet](#doku-integritaet)
- [Doku-Delta](#doku-delta)
- [Mechanismus und zweite Fundstelle](#mechanismus-und-zweite-fundstelle)
- [Beleg-Pflicht](#beleg-pflicht)
- [Mengenangaben](#mengenangaben)
- [Klassengroesse](#klassengroesse)
- [Kommentare](#kommentare)
- [PR-Body vs. Diff](#pr-body-vs-diff)
- [Backlog-Gegencheck](#backlog-gegencheck)
- [Mitgeliefertes Log](#mitgeliefertes-log)
- [Fehlerart je Befund](#fehlerart-je-befund)
- [Altcode-Marke je Befund](#altcode-marke-je-befund)
- [Beim Sammeln pro Punkt festlegen](#beim-sammeln-pro-punkt-festlegen)

## Fehlendes Artefakt — wann es blockt

- **Tracking Issue** — wo die Aufgabe aus einem Design kommt; es entsteht dort immer, auch ohne
  offenen Punkt (`ccweb-prompt` Schritt 1); die Ausnahme fuer den PR aus
  Auftragstext steht in `dev-task` Schritt 1b.

Fehlt die Spec-Datei, obwohl der Auftrag eine `REQ`-Liste trug, ist das ein `issue: (blocking)`.

## Sub-Agent-Passes und Modellwahl

- Die parallelen Passes bilden eine
  Review-Welle, der Coordinator benennt ihren kritischen Schwerpunkt.

## Agent-Red-Flags (zuerst, harte Sachen)

- **Reuse:** pro neuer Util/Helper/Klasse im Repo nach einem bestehenden Aequivalent suchen. Dupliziert der PR vorhandene Logik: Konsolidierung im selben PR
  erzwingen, nicht nur kommentieren.

## Doku-Integritaet

- **Doku-Integritaet:** aendert der PR Docs oder legt er ein mitgeliefertes Dokument ab, wird dessen Stand am PR-Head verifiziert, nicht dem PR-Body geglaubt.
  - **Mitgeliefertes Decision-Log / uebergebenes Dokument verbatim?** Behauptet der PR "verbatim / unveraendert uebernommen", wird die Datei am Head gegen die Quelle geprueft; zerstoertes Markdown oder fehlende Abschnitte → `issue:`.
  - **Belege leben am Head?** Zitiert eine geaenderte Doc-Stelle einen Beleg-Anker (Symbol-/Testname, SHA-Permalink) oder einen Marker (`[met]`/`[partial]`/`[planned]`), stichprobenartig gegen den Head-Stand gegenpruefen: verweist der Beleg auf in diesem PR geloeschten/umbenannten Code, oder widerspricht der Marker dem Gebauten → `issue:`.
  - **`[met]`-Marker gegen Dateiliste.** Wird im Diff ein Marker auf `[met]` gezogen, gegen die Dateiliste des PRs halten: deckt die Aussage eine Oberflaeche oder Komponente ab, zu der der Diff keine Datei enthaelt → `issue:`.
  - **Spec-Datei gegen das Issue.** Ihre Form steht in `.agents/rules/pr.md` § "Task Spec" und `.claude/skills/ccweb-prompt/reference/spec.md`, die Haken je REQ prueft das Skript (Formpunkt `spec-file`); eine `REQ`-Tasklist **im Body** statt der verlinkten Datei ist ein `issue:`. Die Datei wird **gegen das Issue** geprueft: deckt sie dessen Auftrag ab?
  - **Auftrag woertlich (Pruefung A).** Traegt die Spec den Auftrag des Maintainers, wird jeder seiner Saetze geprueft: hat er ein REQ oder ein `not implemented: <reason>`, ist das REQ geliefert, und sagt es dasselbe wie der Satz? Fehlt
    ein Satz, weicht ein REQ ab, oder fehlt der Wortlaut in einer Spec, deren Auftrag vom
    Maintainer kam → `issue: (blocking)`.
  - **Verbleib ueber Sprachgrenzen:** wo das Repo eine Verbleib-Tabelle fuehrt, wird jede Zeile, deren Satz deutsch und deren Ziel englisch ist oder umgekehrt, von Hand gegen ihr Ziel gehalten — steht die Aussage dort nicht, ist das ein `issue: (blocking)`.

## Doku-Delta

- Als Dokument zaehlen Architektur-/Baseline-Doc, `README.md`, `docs/**`, `CLAUDE.md`, ein Skill, eine Regeldatei, die Comment-Based-Help eines Skripts.
- **Gesucht wird mechanisch:** je geaenderter Oberflaeche (Funktions-, Skript-, Parameter-,
  Konfigurations- oder Schaltername, Meldungstext, Pfad, Default) `git grep` ueber die
  Dokumente am Head; jeder Treffer, dessen Aussage der Diff unwahr macht, wird gegen die Dateiliste
  des PRs gehalten.

## Mechanismus und zweite Fundstelle

Zwei Pruefpunkte fuer jeden Diff, der Regel- oder Skill-Text aendert (`AGENTS.md`, `.agents/**`,
`.claude/skills/**`, `docs/common/**`, `.agents/tech/**`, Hooks):

- **Gibt es den Mechanismus?** Jeder neue oder geaenderte Satz, der einen Mechanismus nennt — ein
  Skript, einen Parameter, einen Hook, ein Werkzeug, eine Faehigkeit, einen Endpunkt, ein Feld, das
  etwas liest —, wird gegen Code oder Doku gehalten, mit `Datei:Zeile` am Head bzw. URL der
  Hersteller-Doku. Laesst sich der Mechanismus nicht finden oder tut er anderes als der Satz sagt,
  ist das ein `issue: (blocking)`; der Report nennt je Satz den Beleg.
- **Steht die Vorgabe schon woanders?** Jede neue oder geaenderte Vorgabe wird per `git grep` nach
  ihren tragenden Woertern auf eine zweite Fundstelle gesucht. Steht sie schon an anderer Stelle,
  gilt die Rangfolge Regeldatei, `AGENTS.md`, Skill, Doc: die hoehere Stelle traegt sie, die andere
  verweist nur; eine zweite Fassung ist ein `issue: (blocking)`, eine widersprechende erst recht.

## Beleg-Pflicht

- **Beleg-Pflicht:** was sie verlangt und welcher Anker zaehlt, steht in `.agents/rules/evidence.md`
  § "Evidence Requirement" — nur fuer das, was der Reviewer **nicht im Diff sieht**; einen Beleg
  fuer Sichtbares einzufordern ist selbst der Fehler.

## Mengenangaben

- **Mengenangaben ueber den Diff** prueft das
  Skript (Formpunkt `body-quantity`), der Reviewer meldet keine als Befund und rechnet
  keine nach.

## Klassengroesse

- Eine neue oder gewachsene Klasse darueber ohne
  Begruendung im PR-Body ist ein `issue:`.

## Kommentare

- **Kommentare** (Regel: `.agents/rules/code.md` § "Code Comments"), an Kommentaren, die der Diff neu schreibt oder aendert:
  - Review-Runden- oder Befund-Verweise, "hier stand frueher" oder Zitate frueherer Staende →
    `issue: (blocking)`.
  - Begruendung, die schon im Beleg-Dokument steht (Doppelung) → `issue: (blocking)`.
  - Begruendung nur ueber dem Richtwert von 1–3 Zeilen, ohne Doppelung →
    `suggestion: (non-blocking)`, sie ins Beleg-Dokument zu verlegen.

## PR-Body vs. Diff

- **PR-Body gegen Diff:** auf Phantom Changes (Body behauptet Aenderungen, die nicht im Diff sind) und Scope-Understatement (Diff tut mehr als der Body sagt) pruefen.
- **Schliess-Zeilen schon in Runde 1.** Je Issue, das der PR-Body oder eine geaenderte
  Wahrheitsquelle als von diesem PR erledigt fuehrt, das Issue am Head lesen: offen? Checkliste,
  und steht darin noch ein unabgehakter Punkt?

## Backlog-Gegencheck

- **Backlog-Gegencheck (beide Richtungen).** Erledigt der PR einen Eintrag, der in `backlog.md`, `roadmap.md` oder einem Issue als offen gefuehrt wird, **muss er ihn im selben PR streichen** (durchstreichen, nicht loeschen). Bei Doku-Nachzuegen die Wahrheitsquellen **einzeln** gegenpruefen — `architecture.md`, `roadmap.md`, `backlog.md`, betroffene Nutzer-Docs.
- Jeder Eintrag `moved-fix` ist ein `issue: (blocking)`, ohne Ermessen. Ein
  Eintrag `no-known-fix` (die Zeile traegt `**No known fix:**`) blockt nicht von selbst: er
  steht in der Tabelle "Verschobenes", und der Grund wird am Diff geprueft — ist der Fix doch
  bekannt, ist es wieder ein `issue: (blocking)`. Ebenso ein Eintrag `foreign-repo-only` (die Zeile
  traegt `**Foreign repo only:** <owner/repo#N>`): geprueft wird, dass der Fix wirklich nur im
  genannten Repo liegt und die Zeile das dort angelegte, offene Issue verlinkt; fehlt das Issue oder
  liegt der Fix doch hier, ist es wieder ein `issue: (blocking)`.

## Mitgeliefertes Log

Pruefen: steht dort ein Punkt noch als ungetragen, der inzwischen einen Traeger hat?
  Beschreibt es einen Scope, den der reale Diff nicht mehr hat? Dann fehlt der Abschnitt
  `## Nachtraege aus den Review-Runden` am Ende des Files → `issue:`.

## Fehlerart je Befund

5. **Derselbe Wortlaut in Folgerunden:** trifft ein `issue:` die Fehlerart einer frueheren Runde,
   steht in seiner Zeile `Fehlerart:` dieselbe Formulierung, nicht eine neue.

## Altcode-Marke je Befund

Fester Schritt je Befund, vor dem Bericht: **gehoert die Zeile zu den `+`-Zeilen des PR-Diffs?**
Nein — die Zeile stand so schon am Basis-Commit — dann traegt der Punkt `(pre-existing)` (`.agents/rules/review.md` § "Review Comments").

## Beim Sammeln pro Punkt festlegen

- **Autor-Punkte:** Unter "Open questions", "Observations" und "Deliberately not changed" steht je Punkt nur der Link auf seinen Traeger, eine Umgebungsfeststellung gehoert unter "How tested" (`scripts/common/test-pr-form.ps1`, Formpunkte `body-headings` und `body-list`). Jeder dieser Links bekommt **genau eine eigene
  F-Nummer**; kein Buendeln, kein Weglassen mit der Begruendung "ausserhalb des Auftrags" oder "vom
  Autor korrekt eingeordnet" — **ob ein Punkt ausserhalb bleibt, entscheidet der User, nicht der
  Review**. Die eigenen Funde zaehlen zusaetzlich.
- Was der Review am Tracking Issue prueft, steht in
  `.claude/skills/pr-poll-review/SKILL.md` Phase 4, welche Orte gueltig sind, in
  `.agents/rules/carrier.md` § "Carrier Requirement" — wer den Punkt eintraegt, in
  `.agents/rules/review.md` § "Review Comments"; wann eine Weitergabe an eine
  kuenftige Scheibe zaehlt, steht in `.agents/rules/carrier.md`.
- **Was dem Menschen vorgelegt wird — gefiltert, nicht gestrichen.** Zur Abstimmung geht nur eine
  `question: (blocking)` (die Faelle: Tabelle in `.agents/rules/review.md` § "Review Comments").
Lautet die eigene Empfehlung "akzeptieren" oder "stehenlassen", ist es keine Frage.
