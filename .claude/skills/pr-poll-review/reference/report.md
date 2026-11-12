# pr-poll-review — Freigabe-Gate (Phase 1 Schritte 4 bis 7)

## Inhalt

- [Stufe A — Chat-Report](#stufe-a--chat-report)
- [Stufe B — Freigabe](#stufe-b--freigabe)
- [Widget-Befuellung](#widget-befuellung)
- [Invarianten](#invarianten)
- [Zeilen-Datei der Runde](#zeilen-datei-der-runde)
- [Suggested Change als Postform](#suggested-change-als-postform)
- [Entschiedene offene Fragen posten](#entschiedene-offene-fragen-posten)

## Stufe A — Chat-Report

**Stufe A — Chat-Report zuerst, immer, vor jeder Freigabe.** In dieser festen Reihenfolge ausgeben — im Chat, im Controller-Modus als Text-Datei an den Controller (`SKILL.md`, Kernprinzip):

- **Offene Fragen** (nur wenn es welche gibt) — je `question: (blocking)` in der vollen Form aus
  `ccweb-prompt` § "Schritt 1: Design-Runde und Tracking Issue" (die Pflichtform, sechs Abschnitte
  plus "nicht nachgelesen"); **die Empfehlung ist vorbelegt**.
- **Beobachtungen** (nur wenn es welche gibt) — was gefiltert wurde plus jeder heute gruene
  Mechanismus mit erkennbarem kuenftigem Bruchrisiko: je ein Satz mit der Einschaetzung des
  Reviewers, ohne Abstimmung und ohne Widget-Eintrag.
- **Verschobenes** (Pflicht-Tabelle, auch wenn leer) — jeder Punkt, den der PR-Body oder eine
  waehrend des PRs neu geschriebene Traeger-Zeile (Body des Tracking Issues, `roadmap.md`,
  `backlog.md`) als zurueckgestellt fuehrt, in drei Spalten: **Datei in diesem PR angefasst?** /
  **Fix bekannt?** / **Frage-Nr.** Die ersten beiden am Diff belegt, nicht behauptet — die erste liefert `find-moved-fixes.ps1`, die zweite prueft `reference/checks.md` § "Backlog-Gegencheck".
  Ja/Ja geht als eigener `issue: (blocking)` in die Punkte-Liste ein. **Frage-Nr.** traegt die F-Nummer, unter der ein
  offener Entscheid dieses Punktes zur Abstimmung steht (`reference/checks.md` § "Beim Sammeln pro
  Punkt festlegen", Autor-Punkte). Steht in einer Zeile ein offener Entscheid ("wartet auf den
  Maintainer", "braucht deinen Entscheid") und die Spalte ist leer, ist der Report unvollstaendig —
  erst die Frage anlegen, dann weiterschreiben.
- **Form, blockt nie** (nur wenn es welche gibt) — die roten Zeilen von `scripts/common/test-pr-form.ps1`, die nicht Inhalt sind (`reference/gates.md` § "Form haelt das Approve nie auf"), und die Formpunkte, die das Skript nicht sieht, als **ein** Block, ohne Label und ohne Nummer in der Punkte-Liste.

─── darunter, sichtbar abgetrennt, der Detail-Teil ───

- **Verdikt**, als erste Zeile des Detail-Teils: `Blockiert` / `Approvebar nach Fixes` / `Sauber` —
  danach erst die Begruendung.
- **Label-Counts als Kopfzeile.**
- eine **kurze Prosa-Zusammenfassung des Reviews — hart auf max. 3 Saetze**: was geprueft wurde und
  der Gesamteindruck.
- darunter eine **vollstaendige, nummerierte** Punkte-Liste. Pro Punkt: Nummer, **Label mit Dekoration** (bei Altcode zusaetzlich `(pre-existing)`), Datei/Zeile, ein Satz. Bei
  einem `issue:` dazu drei Zeilen: **Fehlerart**, **Suche** (der eine Befehl, woertlich) und
  **Fundstellen** (alle, die er am Head fand; `reference/checks.md` § "Fehlerart je Befund"). Bei
  einem `nitpick:` steht der Suggestion-Text mit dabei — er ist das, was gepostet wird.
- **Vollstaendigkeit ist Pflicht:** auch jeder `nitpick:` wird gemeldet; in Schritt 2
  aussortierte false positives bleiben draussen. Nichts wird weggelassen oder still gefiltert.
- **Coverage-Statement zum Schluss:** in einem Satz, was bewusst *nicht* geprueft wurde und warum
  (`Nicht geprueft: X, weil Y.`); gibt es keine Luecke, wird auch das gesagt.

## Stufe B — Freigabe

**Stufe B — Freigabe** entfaellt im Modus `once` (Stufe A und die Zeilen-Datei bleiben;
[`review-modes.md`](review-modes.md)). Default: **alle Punkte werden
gepostet, jedes Label wie vorbelegt**; der User streicht oder stellt nur einzelne um.

- **Immer:** eine Zeile unter der Liste — der User nennt die Nummern, die gestrichen werden
  sollen, die Nummern, deren Label er umstellt (`3: issue`, `5: nitpick`), und fuer die offenen
  Fragen nur die, bei denen er von der vorbelegten Empfehlung abweicht (`F2: verworfen`,
  `F3: custom …`). Ohne Angaben gilt jede kurze Bestaetigung (`k`, `ok`, `los`,
  `posten`, `machen`, `gut`) als „alles posten, jedes Label wie vorbelegt, bei jeder Frage die
  Empfehlung". Custom-Punkte im selben Zug.
- **Das Label ist in beide Richtungen umstellbar** (`nitpick:` ↔ `issue: (blocking)`).
  Der **Text des Punktes bleibt unveraendert** — er wird nie umgeschrieben, nur anders
  eingeordnet.
- **Zwei getrennte Ausstiege, beide ausdruecklich waehlbar**: `F3: offen lassen` — nicht als Anweisung posten, der Punkt **geht an einen gueltigen Traeger** (`.agents/rules/carrier.md` § "Carrier Requirement"); oder `F3: verwerfen` — der Punkt endet ersatzlos, kein Traeger, und wird im Review-Body einzeilig als verworfen protokolliert. Fehlt die Angabe, gilt „offen
  lassen"; „verwerfen" wird nie unterstellt.
- **Batch-Aktionen fuer die Nits:** „alle Nits als Suggestion posten" und „alle Nits streichen".

## Widget-Befuellung

- **Nur die VORLAGE-Zone von `widget-reference.html` 1:1 uebernehmen**; das dort markierte GERUEST bleibt draussen.

- **Offene Fragen sind ein eigener, vom Punkte-Block klar abgetrennter Bereich** mit anderer
  Interaktion: nicht posten/streichen, sondern **eine Wahl pro Frage** — waehlbar sind die
  **Empfehlung** (vorbelegt), **je verworfene Idee** aus Abschnitt 4 der Form unter "Offene
  Fragen" (§ "Stufe A — Chat-Report"), und eine eigene (Custom-)Antwort; die uebrigen Abschnitte
  sind keine Option, sondern die Beschreibung der Frage selbst.

## Invarianten

- Das Widget **ersetzt** die Textaufforderung nie. Rendert es nicht, ist das folgenlos, und der
  Text-Pfad traegt die Freigabe allein.
- Das Widget ist reine Eingabehilfe, nie Informationsquelle: es traegt nie mehr, weniger oder andere Inhalte als der Report aus Stufe A — gleiche Nummern, gleicher Text, gleiche Label-Vorbelegung, gleiche Fragen (`F1`, `F2`, …) mit denselben Optionen und derselben Vorbelegung.

`ask_user_input_v0` wird hier nicht benutzt.

## Zeilen-Datei der Runde

Am Ende jeder Review-Runde — nach der Freigabe (die saubere Runde braucht keine), vor dem Posten — eine Zeilen-Datei je Runde, eine Zeile je Punkt, **auch je verworfenem**. Der Reviewer pusht nie auf den PR-Branch: die Runde haengt sie an ihren Review-Post, der Dev committet sie mit seinem naechsten Push.

- **Ort:** `docs/decisions/<stempel>-<slug>-review-<n>-ledger.jsonl` auf dem **PR-Branch**, `<n>`
  die Nummer der Runde, `<slug>` der der Spec-Datei (sonst der des Branches), Stempel nach
  `.agents/rules/docs.md` § "Timestamps in File Names".
- **Anhang:** als eingezaeunter `jsonl`-Block im Review-Body, darueber der Dateiname. Der Autor committet sie als eigenen Commit nur mit dieser Datei (`docs(decisions): record review round <n> of #<pr>`).
- Je Ausgang: gepostet `accepted`, gestrichen oder `verwerfen` `rejected`, `offen lassen` `deferred` (`already_at` = Traeger oder `**Own PR:**`-Ziel), Frage mit eigener Antwort des Users (Label umgestellt) `superseded`, Beobachtung ohne Label `idea`; dazu `id` `R<n>-<Nummer>` bzw. `R<n>-F<Nummer>`, `source` `<owner/repo>#<pr>@<sha7>` plus Datei und Zeile, `topic` das Label.
- **Pruefen:** wie die Zeilen-Datei der Design-Runde, nach
  `.claude/skills/ccweb-prompt/reference/decision-log.md` § "Zeilen-Datei".

## Suggested Change als Postform

- **Jeder `nitpick:` geht als Suggested Change**: ein mit `suggestion` ausgezeichneter
  Codeblock im `body` des
  Inline-Kommentars, mit `path` und `line`. Per MCP im `body` von `add_comment_to_pending_review`, per `gh` ueber `gh api` auf den Comments-Endpunkt.

- **Nur so beweisbar:** nur Zeilen der rechten Diff-Seite (`side: RIGHT`, bei mehreren Zeilen
  `start_line` bis `line`), genau ein Block je Kommentar, der Block der woertliche Ersatz genau
  dieses Bereichs, nie zwei Kommentare ueber denselben Zeilen.
- **Im Bericht je Vorschlag `beruehrt Code: ja/nein`** (Dateien ohne Code: `scripts/common/test-merge-ready.ps1`, Pruefung 1).

## Entschiedene offene Fragen posten

- Eine Frage, bei der der User „offen lassen / nicht in diesem PR"
  waehlt, wird nicht als Anweisung gepostet — **„offen lassen" ist eine Ablage, kein Verwerfen**:
  ein baubarer Punkt folgt `.agents/rules/carrier.md` § "Carrier Requirement", ein nicht baubarer
  geht an einen gueltigen Traeger, bevor der Review abgeschlossen wird.
