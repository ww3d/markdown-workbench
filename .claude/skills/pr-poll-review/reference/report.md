# pr-poll-review — Freigabe-Gate (Phase 1 Schritte 4 bis 7)

## Inhalt

- [Stufe A — Chat-Report](#stufe-a--chat-report)
- [Stufe B — Freigabe](#stufe-b--freigabe)
- [Widget-Befuellung](#widget-befuellung)
- [Invarianten](#invarianten)
- [Zeilen-Datei der Runde](#zeilen-datei-der-runde)
- [Suggested Change als Postform](#suggested-change-als-postform)
- [Entschiedene offene Fragen posten](#entschiedene-offene-fragen-posten)

Der Chat-Report, die Freigabe, die Befuellung des Widgets, die beiden Invarianten, die Zeilen-Datei
der Runde — und die beiden Formvorschriften, mit denen das Freigegebene in Schritt 7 an den PR geht.
Jede Review-Runde faehrt dasselbe Gate.

## Stufe A — Chat-Report

**Stufe A — Chat-Report zuerst, immer, vor jeder Freigabe.** In dieser festen Reihenfolge im Chat
ausgeben — im Controller-Modus denselben Report als Text-Datei an den Controller, als
Review-Freigabe nach `.agents/rules/pr.md` § "Session Traffic", nicht in den Chat (`SKILL.md`,
Kernprinzip "Freigabe-Gate"):
**Der obere Teil ist neu und komplett in einfacher Alltagssprache (kein Fachjargon) — er soll den
ganzen PR abdecken, damit der Leser nicht mehr in den PR wechseln muss. Der technische
Detail-Report darunter bleibt unveraendert und ist nur fuer den Fall da, dass jemand reingehen
will.**

- **Mergebarkeit** (allererste Zeile) — die Ein-Blick-Antwort: kann der PR gemergt werden, und wenn
  nicht, was steht im Weg. Faltet Verdikt, CI-Status, Merge-Konflikte und offene blockende Punkte in
  einen Satz, z.B. „Approvebar — blockt: nichts" oder „Blockt noch: CI laeuft, 1 Merge-Konflikt, 2
  offene `issue: (blocking)`". Nicht blockierende Punkte gehoeren nicht in diesen Satz. Das ist
  die konsolidierte Kurzantwort; der ausfuehrliche Verdikt steht unten im Detail-Teil.
- **Kurzfassung** — der ganze PR in 2-4 Saetzen Klartext: was macht der PR, ist er ok, gibt es etwas
  zu tun.
- **Was der Autor entschieden hat** — die wichtigsten Design-/Umsetzungsentscheidungen des PRs,
  einfach zusammengefasst (keine woertlichen Zitate, kein Jargon), 2-5 kurze Punkte. Gibt der PR
  dazu wenig her, entsprechend kurz — nichts erfinden.
- **Changes-Tabelle** (optional, nur bei breiten PRs mit vielen Dateien) — verwandte Aenderungen zu
  Zeilen **gruppiert** (nie file-by-file; eine Quelldatei + 20 Uebersetzungsdateien sind zwei
  Zeilen), je Zeile eine Beschreibung in Alltagssprache. Bei kleinen/schmalen PRs entfaellt sie —
  die Kurzfassung reicht dann.
- **Ablauf-Diagramm** (optional, nur wenn die Aenderung einen echten Fluss hat — API-Aufrufe,
  Event-/Async-Flow, Zustandsuebergaenge) — ein kompaktes Mermaid-Sequenz- oder Flussdiagramm des
  geaenderten Ablaufs (rendert in GitHub und vielen Chat-Clients; sonst bleibt der Mermaid-Block als
  Rohtext lesbar). Kein Diagramm um des Diagramms willen — hat der PR keinen nennenswerten Fluss,
  entfaellt es.
- **Offene Fragen** (nur wenn es welche gibt) — je `question: (blocking)` in der **Kurzform** aus
  `ccweb-prompt` § "Schritt 1: Design-Runde und Tracking Issue" (Absatz "Staffel"): Worum es geht /
  Empfehlung / verworfene Alternativen mit Grund;
  **die Empfehlung ist vorbelegt**. Kein eigenes a/b/c-Format mehr — das Playbook fuehrt die Form
  nur einmal, und `pr-poll-review` verweist darauf statt sie zu doppeln. Quelle: was der Autor
  im PR offen liess + was Claude im Review sieht, **nach dem Filter aus Schritt 3** — nur
  Entscheidungsfragen. Dieselben Fragen stehen, wo es ein Widget gibt, dort zur Auswahl. Gibt es
  keine, wird das gesagt.
- **Beobachtungen** (nur wenn es welche gibt) — was gefiltert wurde plus jeder heute gruene
  Mechanismus mit erkennbarem kuenftigem Bruchrisiko: je ein Satz mit der Einschaetzung des
  Reviewers, ohne Abstimmung und ohne Widget-Eintrag. Sie tragen kein Label und
  wuerden sonst herausfallen.
- **Verschobenes** (Pflicht-Tabelle, auch wenn leer) — jeder Punkt, den der PR-Body oder eine
  waehrend des PRs neu geschriebene Traeger-Zeile (Body des Tracking Issues, `roadmap.md`,
  `backlog.md`) als zurueckgestellt fuehrt, in drei Spalten: **Datei in diesem PR angefasst?** /
  **Fix bekannt?** / **Frage-Nr.** Die ersten beiden am Diff belegt, nicht behauptet — die erste
  liefert `find-moved-fixes.ps1` (`reference/checks.md` § "Backlog-Gegencheck"), die zweite liest
  bei `no-known-fix` den genannten Grund, bei `foreign-repo-only` das genannte Fremd-Repo und bei
  `own-pr` den genannten PR bzw. das Tracking Issue nach
  (`.agents/rules/review.md` § "Review Comments").
  Ja/Ja geht als eigener `issue: (blocking)` in die Punkte-Liste ein — hier steht die Tabelle nur
  zur Uebersicht, sie ersetzt den Befund nicht. **Frage-Nr.** traegt die F-Nummer, unter der ein
  offener Entscheid dieses Punktes zur Abstimmung steht (`reference/checks.md` § "Beim Sammeln pro
  Punkt festlegen", Autor-Punkte). Steht in einer Zeile ein offener Entscheid ("wartet auf den
  Maintainer", "braucht deinen Entscheid") und die Spalte ist leer, ist der Report unvollstaendig —
  erst die Frage anlegen, dann weiterschreiben.

─── ab hier der bestehende Detail-Report, **unveraendert** (nur zum Reingehen); mit einer sichtbaren
Trennung davor ───

- **Verdikt**, als erste Zeile des Detail-Teils: `Blockiert` / `Approvebar nach Fixes` / `Sauber` —
  danach erst die Begruendung.
- **Label-Counts als Kopfzeile** (z.B. `3 issue (blocking), 1 question (blocking), 6 nitpick`),
  damit ohne Zaehlen sichtbar ist, wieviel ueberhaupt blockt.
- eine **kurze Prosa-Zusammenfassung des Reviews — hart auf max. 3 Saetze**: was geprueft wurde und
  der Gesamteindruck. **Keine Beleg-Aufzaehlung hier** — keine Anker-Listen, keine
  Test-Namen, kein „ich habe X, Y, Z getraced". Belege gehoeren an den jeweiligen Punkt, nicht in
  den Verdikt-Absatz. Wird der Absatz laenger als 3 Saetze oder zaehlt er Belege auf, ist er falsch.
- darunter eine **vollstaendige, nummerierte** Punkte-Liste. Pro Punkt: Nummer, **Label mit
  Dekoration** (`issue: (blocking)` / `nitpick: (non-blocking)` / …), Datei/Zeile, ein Satz. Bei
  einem `nitpick:` steht der Suggestion-Text mit dabei — er ist das, was gepostet wird.
- **Vollstaendigkeit ist Pflicht:** auch jeder `nitpick:` wird gemeldet; in Schritt 2
  aussortierte false positives bleiben draussen. Ordnung nach Blocking-Wirkung ist erwuenscht,
  aber nichts wird weggelassen oder still gefiltert.
- **Coverage-Statement zum Schluss:** in einem Satz, was bewusst *nicht* geprueft wurde und warum
  (`Nicht geprueft: X, weil Y.`); gibt es keine Luecke, wird auch das gesagt. Ein Review, das
  seine Luecken verschweigt, liest sich vollstaendiger als es ist.

## Stufe B — Freigabe

**Stufe B — Freigabe** (referenziert die Nummern aus Stufe A). Default: **alle Punkte werden
gepostet, jedes Label wie vorbelegt**; der User streicht oder stellt nur einzelne um.

- **Immer:** eine Zeile unter der Liste — der User nennt die Nummern, die gestrichen werden
  sollen, die Nummern, deren Label er umstellt (`3: issue`, `5: nitpick`), und fuer die offenen
  Fragen nur die, bei denen er von der vorbelegten Empfehlung abweicht (`F2: verworfen`,
  `F3: custom …`). Ohne Angaben gilt jede kurze Bestaetigung (`k`, `ok`, `los`,
  `posten`, `machen`, `gut`) als „alles posten, jedes Label wie vorbelegt, bei jeder Frage die
  Empfehlung". Custom-Punkte im selben Zug. Der Pfad, der nie ausfaellt.
- **Das Label ist in beide Richtungen umstellbar** (`nitpick:` ↔ `issue: (blocking)`). Die
  Vorbelegung ist die Einschaetzung des Reviews; die Einstufung ist eine Maintainer-Entscheidung.
  Der **Text des Punktes bleibt unveraendert** — er wird nie umgeschrieben, nur anders
  eingeordnet.
- **Zwei getrennte Ausstiege, beide ausdruecklich waehlbar** (sonst rutscht jeder Punkt in den
  bequemeren): `F3: offen lassen` — nicht als Anweisung posten, der Punkt **geht an einen
  gueltigen Traeger** (`.agents/rules/carrier.md` § "Carrier Requirement"); oder `F3: verwerfen`
  — der Punkt endet ersatzlos, kein Traeger, und wird im Review-Body einzeilig als verworfen
  protokolliert, damit die Entscheidung nachvollziehbar bleibt. Fehlt die Angabe, gilt „offen
  lassen"; „verwerfen" wird nie unterstellt.
- **Batch-Aktionen fuer die Nits:** „alle Nits als Suggestion posten" und „alle Nits streichen".
  Sie sind der Grund, warum ein Nit billig ist — einzeln durchzugehen waere derselbe Aufwand wie
  ein blockierender Punkt.

## Widget-Befuellung

- **Mitliefern, wenn ein Mensch im claude.ai-Chat der Adressat ist:** ein Widget als Eingabehilfe —
  in jeder Runde, unabhaengig davon, ob ein Visualizer verfuegbar ist (rendert es nicht, ist es
  folgenlos; siehe Invarianten). **Im Controller-Modus und in Claude Code entfaellt das Widget
  ganz**: niemand sitzt an einem Chat, der es rendern koennte, bzw. es gibt keinen Widget-Host, und
  der Text-Pfad traegt die Freigabe allein. Die zweite Invariante unten gilt unveraendert. **Nur die
  VORLAGE-Zone von `widget-reference.html` 1:1 uebernehmen** — die Datei liegt nur im Playbook und
  wird von dort geholt (`SKILL.md`, Phase 1 Schritt 4) —; das dort
  markierte GERUEST (Dokumentrahmen, `:root`, `body`/`.wrap`, `.widget`-Container, `.out`) bleibt
  draussen, es macht die Datei nur standalone lauffaehig. Masse, Farben (ueber Host-Variablen)
  und Logik stehen in der Referenz und werden hier bewusst nicht gedoppelt, damit Referenz und
  Spec nicht auseinanderlaufen. Zwei Injection-Points, beide aus dem Stufe-A-Report befuellen:
  `FINDINGS` (die Punkte mit Label) und `QUESTIONS` (die offenen Fragen; leer lassen, wenn es
  keine gibt — dann entfaellt der Fragen-Bereich sichtbar). Was der Referenz-Code nicht selbst
  begruendet:
  - Die rechte Spalte des Kopf-Grids bleibt leer — sie haelt die Mitte zentriert und die obere
    rechte Ecke frei, wo Chat-Clients ihr eigenes Menue einblenden.
  - Die Legende bleibt immer vollstaendig, auch fuer Stufen ohne Punkte: sonst ist der neutrale
    Badge nicht als „nitpick" (statt „deaktiviert") erkennbar, und dass keine roten Badges
    dastehen, ist selbst ein Signal.
  - **Alle Punkte stehen im Widget, auch die nicht blockierenden.** Wer nur die blockierenden zeigte,
    zwingt den Maintainer zurueck in den Report, sobald er einen Nit hochziehen will.
  - **Das Label ist umstellbar, der Finding-Text ist read-only.** Vorbelegt mit der
    Einschaetzung des Reviews, umstellbar in beide Richtungen (`nitpick:` ↔ `issue: (blocking)`).
    Die Invariante bleibt gewahrt: das Widget traegt denselben Text wie Stufe A, nur die
    Einordnung ist eine Maintainer-Entscheidung.
  - **Kopfzeile mit dem Ergebnis der Umstellung** — „nach deinen Aenderungen: 2 blockend, 6 nicht
    blockend". Ohne sie ist die Wirkung des Umstellens erst nach dem Absenden sichtbar.
  - **Zwei Batch-Aktionen fuer die Nits:** „alle Nits als Suggestion posten" und „alle Nits
    streichen".
  - **Offene Fragen sind ein eigener, vom Punkte-Block klar abgetrennter Bereich** mit anderer
    Interaktion: nicht posten/streichen, sondern **eine Wahl pro Frage** — waehlbar sind die
    **Empfehlung** (vorbelegt), **je verworfene Alternative** aus der Kurzform aus `ccweb-prompt` §
    "Schritt 1: Design-Runde und Tracking Issue", und eine eigene (Custom-)Antwort; `Worum` ist
    keine Option, sondern die Beschreibung der Frage selbst. Darunter abgesetzt die beiden
    Ausstiege `offen lassen` und `verwerfen`. Die Ausstiege stehen fest und kommen nicht aus dem
    Injection-Point; abgesetzt stehen sie, weil sie die Frage beenden statt sie zu beantworten.
    Ihr Ziel ist eindeutig: **`offen lassen` heisst „nicht in diesem PR"**: baubar wird der Punkt
    ein eigener PR (bis dahin `**Eigener PR:** <owner/repo#N>`), sonst geht er an einen gueltigen
    Traeger (`.agents/rules/carrier.md` § "Carrier Requirement"); **`verwerfen` beendet den
    Punkt ersatzlos**.
    **Die Empfehlung ist vorbelegt**; der User uebersteuert nur, wo er anders entscheidet — dasselbe
    Default-Prinzip wie „alles posten". Der Options-Text ist read-only (die recherchierte Aussage
    aus Stufe A), waehlbar ist nur, welche Option gilt. Unter dem Frage-Titel steht die
    `→ heisst:`-Klartext-Zeile (Feld `explain` je Frage), damit die Entscheidung ohne Jargon
    verstaendlich ist — gleiche Aussage wie in Stufe A.

## Invarianten

Zwei Invarianten:
- Das Widget **ersetzt** die Textaufforderung nie — es wird zwar immer mitgeliefert, wenn ein
  Mensch der Adressat ist, aber die Visualizer-Verfuegbarkeit ist vorab nicht pruefbar (derselbe
  Client rendert je nach Plattform oder nicht). Rendert es nicht, ist das folgenlos, und der
  Text-Pfad traegt die Freigabe allein. Im Controller-Modus und in Claude Code gibt es kein Widget;
  dort traegt der Text-Pfad die Freigabe von vornherein allein.
- Das Widget ist reine Eingabehilfe, nie Informationsquelle: es traegt nie mehr, weniger oder
  andere Inhalte als der Report aus Stufe A — gleiche Nummern, gleicher Text, gleiche
  Label-Vorbelegung, gleiche Fragen (`F1`, `F2`, …) mit denselben Optionen (Empfehlung, je
  verworfene Alternative, eigene Antwort) und derselben Vorbelegung, nur kuerzer. Was nur im
  Widget stuende, waere fuer jeden verloren, bei dem es
  nicht rendert. Das Umstellen eines Labels ist keine Ausnahme davon: es ist eine **Eingabe** des
  Users, kein Inhalt des Widgets.

`ask_user_input_v0` wird hier nicht benutzt: `multi_select` laesst sich nicht leer absenden,
`single_select` sendet beim ersten Klick ab, beide deckeln bei 4 Optionen.

## Zeilen-Datei der Runde

Am Ende jeder Review-Runde — nach der Freigabe, vor dem Posten — eine Zeilen-Datei, eine Datei je
Runde, eine Zeile je Punkt, **auch je verworfenem**: sonst kommt ein verworfener Punkt in der
naechsten Runde als neu zurueck, und `scripts/common/get-rejected-points.ps1` kennt ihn nicht.

- **Ort:** `docs/decisions/<stempel>-<slug>-review-<n>-ledger.jsonl` auf dem **PR-Zweig**, `<n>` die
  Nummer der Runde, `<slug>` der der Spec-Datei (sonst der des Zweigs), Stempel nach
  `.agents/rules/docs.md` § "Timestamps in File Names". Derselbe Ort wie beim Design, das seine
  Zeilen-Datei neben sein Decision-Log auf seinen Zweig legt: die Datei steht dort, wo die Runde
  entschieden hat, und kommt mit dem Merge auf `main`.
- **Wie sie dorthin kommt:** der Reviewer haengt sie an seinen Review — als eingezaeunter
  `jsonl`-Block im Review-Body, darueber der Dateiname. Er **pusht nie auf den PR-Zweig**: das
  `main`-Ruleset verlangt, dass den letzten Push jemand anderes als sein Pusher approved
  (`require_last_push_approval`), und ein Commit des Reviewers machte sein eigenes Approve wertlos.
  Der Autor committet die Datei mit seinem naechsten Push, als eigenen Commit nur mit dieser Datei
  (`docs(decisions): record review round <n> of #<pr>`). In der sauberen Runde geht der Report samt
  Zeilen-Datei zuerst als `COMMENT`-Review raus; approved wird erst der Head mit diesem Commit, damit
  kein Push mehr auf das Approve folgt. Das Merge-Gate laesst den Commit ohne Laufzeile durch
  (`.agents/rules/pr.md` § "Test Runs").
- **Felder** (Schema `scripts/common/ledger.schema.json`): `id` — `R<n>-<Nummer>` bzw.
  `R<n>-F<Nummer>`; `status` — `angenommen` (gepostet), `verworfen` (gestrichen oder `verwerfen`),
  `zurueckgestellt` (`offen lassen`, mit `steht_schon_wo` = Traeger oder `**Eigener PR:**`-Ziel),
  `ersetzt` (Frage mit eigener Antwort des Users, Label umgestellt), `idee` (Beobachtung ohne
  Label); `satz` — der Text des Punktes; `grund` — warum dieser Status; `quelle` —
  `<owner/repo>#<pr>@<sha7>` plus Datei und Zeile; optional `thema` (das Label), `neu_nur_mit`
  (bei `verworfen`: welches neue Argument ihn wieder oeffnet), `haengt_an`, `prio`.
- **Pruefen** — Skript fahren: `pwsh scripts/common/test-ledger.ps1 -Path <datei>`. Ohne Skript:
  jede Zeile ein JSON-Objekt, die fuenf Pflichtfelder gesetzt, `status` aus der Liste oben, kein
  Feld ausserhalb des Schemas.

## Suggested Change als Postform

- **Jeder `nitpick:` geht als Suggested Change**: ein mit `suggestion` ausgezeichneter
  Codeblock im `body` des
  Inline-Kommentars, mit `path` und `line`. Reines Markdown, kein Sonderfeld — per MCP im `body`
  von `add_comment_to_pending_review`, per `gh` ueber `gh api` auf den Comments-Endpunkt. Der
  Suggestion-Inhalt ist der Text, der die Stelle ersetzt; Prosa daneben nur, wo sie noetig ist.
  Suggested-Code-Changes auf Englisch.

## Entschiedene offene Fragen posten

- **Entschiedene offene Fragen** werden als konkrete Anweisung an den Author gepostet — der vom User
  gewaehlte Ansatz (einer der Kurzform-Slots oder seine Custom-Antwort), nicht die Frage. Ab hier
  ist es fuer den Author eine Vorgabe wie ein `issue:`; die verworfenen Optionen nur nennen, wenn
  die Begruendung dem Author hilft. Eine Frage, bei der der User „offen lassen / nicht in diesem PR"
  waehlt, wird nicht als Anweisung gepostet — **„offen lassen" ist eine Ablage, kein Verwerfen**:
  baubar wird der Punkt ein eigener PR (bis dahin `**Eigener PR:** <owner/repo#N>`), sonst geht er
  an einen gueltigen Traeger, bevor der Review abgeschlossen wird (`.agents/rules/carrier.md` §
  "Carrier Requirement"). Nur „verwerfen" beendet einen Punkt ersatzlos, und das ist eine
  ausdrueckliche Entscheidung des Users, keine Nebenwirkung.
