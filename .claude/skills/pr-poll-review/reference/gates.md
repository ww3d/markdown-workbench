# pr-poll-review — Gate-Kasuistik (Phase 4 und Phase 5)

## Inhalt

- [Was ein positives Abschluss-Verdikt ist](#was-ein-positives-abschluss-verdikt-ist)
- [Hard-Gate Punkt 4 — eigene Threads](#hard-gate-punkt-4--eigene-threads)
- [Hard-Gate Punkt 5 — Form der Auto-Close-Zeile](#hard-gate-punkt-5--form-der-auto-close-zeile)
- [Hard-Gate Punkt 5 — Vorkommen, Umkehrung, Ausnahme](#hard-gate-punkt-5--vorkommen-umkehrung-ausnahme)
- [Hard-Gate Punkt 7 — welcher Anker zaehlt](#hard-gate-punkt-7--welcher-anker-zaehlt)
- [Hard-Gate Punkt 8 — was zurueckgestellt zaehlt](#hard-gate-punkt-8--was-zurueckgestellt-zaehlt)
- [Hard-Gate Punkt 8 — ganzer Body, vierte Frage](#hard-gate-punkt-8--ganzer-body-vierte-frage)
- [Diese Gedanken bedeuten STOP — du rationalisierst](#diese-gedanken-bedeuten-stop--du-rationalisierst)
- [Gegenpruefung des Hard-Gates — Empfehlung, keine Pflicht](#gegenpruefung-des-hard-gates--empfehlung-keine-pflicht)
- [Warum das Warten auf den Merge ueberhaupt dasteht](#warum-das-warten-auf-den-merge-ueberhaupt-dasteht)
- [Merge-Gate — wenn du nicht schliessen kannst](#merge-gate--wenn-du-nicht-schliessen-kannst)
- [Rueckmeldung nach dem Merge](#rueckmeldung-nach-dem-merge)

Die Kasuistik der beiden Gates — die Faelle, an denen frueher etwas durchgerutscht ist. Die
Gates selbst stehen als Regel-Kurzform in der `SKILL.md`; hier steht, wie ihre Punkte im
Einzelfall zu rechnen sind.

## Was ein positives Abschluss-Verdikt ist

**Positives Abschluss-Verdikt** heisst: jede Aussage, die den PR als fertig, sauber, passend,
approve-faehig oder mergebar bezeichnet — auch relativiert („aus meiner Sicht", „im Grunde", „bis
auf Kleinigkeiten"). **Kanal egal:** `APPROVE`-Event, `COMMENT`-Review, Issue-Kommentar, Satz im
Chat sagen dem `maintainer` alle „du kannst mergen" und binden dieses Gate, auch wo GitHub keins
zulaesst; „nicht approven" unten heisst dasselbe. **Nicht** gebunden: Zwischenverdikte `Blockiert` /
`Approvebar nach Fixes` — dort sind die Threads der Grund.

## Hard-Gate Punkt 4 — eigene Threads

- **Die blockierenden Punkte muessen null sein** — `issue: (blocking)` und
  `question: (blocking)`. Ein offener eigener Thread dieser Art haelt das
  Verdikt auf; das Verdikt zu *formulieren*, bevor die Zaehlung null ergibt, ist selbst schon
  der Verstoss — nicht erst das Absenden.
- **Ein `nitpick:` haelt nichts auf**, weder Verdikt noch Merge, und braucht keinen Traeger. Er
  wurde als Suggestion gepostet; der Autor nimmt sie an oder nicht.
- **Vor dem Merge ist auch der Nit-Thread resolved.** Das ist kein Gate dieses Skills, sondern
  Mechanik: `docs/common/ci.md` § "Ruleset fuer `main`" setzt "Require conversation resolution"
  in jedem ww3d-Repo, GitHub laesst sonst nicht mergen. Der Reviewer resolved ihn, sobald der
  Autor die Suggestion angenommen oder begruendet abgelehnt hat — der Autor kann einen fremden
  Thread nicht selbst resolven.
- Threads *anderer* Reviewer werden nie selbst resolved, aber im Verdikt benannt.

## Hard-Gate Punkt 5 — Form der Auto-Close-Zeile

Die Form ist bereits definiert
und wird hier nur benutzt — `.agents/rules/pr.md` § "PR / MR Description" nennt sie "an English
closing line", `docs/common/developer-guide.md` § "PR / MR" den "Auto-Close-Footer am Ende des
Bodys". Keywords sind `Closes` / `Fixes` / `Resolves` und die uebrigen Formen derselben Verben,
die GitHub ebenfalls parst (`close`/`closed`, `fix`/`fixed`, `resolve`/`resolved`).

## Hard-Gate Punkt 5 — Vorkommen, Umkehrung, Ausnahme

- **Ein Vorkommen ist keine Zeile.** Im Fliesstext, in einem Zitat, in Backticks oder nach einer
  Verneinung zaehlt das Keyword weder als Anwesenheit noch als Abwesenheit. Die Textsuche, die
  hier frueher stand, zaehlte Nennung und Anweisung gleich — daran ist der Fall zu #182
  durchgerutscht: der Body erklaerte, warum er kein Keyword setzt, und das Tracking Issue ging
  beim Merge trotzdem zu. Mechanisch pruefbar ist nur "steht dort eine Anweisung", nicht "kommt
  das Wort irgendwo vor".
- **Die Umkehrung gilt genauso.** Eine Auto-Close-Zeile bleibt eine, auch wenn der Body sie
  erkennbar nicht als Anweisung meint — der Parser liest die Form, nicht die Absicht. Der billige
  Vorlauf dazu ist `scripts/common/check-terminology.ps1 -BodyPath`, das jedes Keyword-mit-Nummer
  meldet, das **nicht** auf einer eigenen Zeile steht (`.agents/rules/pr.md` § "PR / MR
  Description"); er sieht nur den Text, den man ihm uebergibt, und ersetzt dieses Gate nicht.
- **Eine Ausnahme, und nur diese:** das einzige in Frage kommende Ziel ist ein **Tracking
  Issue**, in dessen Body noch ein offener Punkt steht. Dann gehoert die Zeile nach
  `.agents/rules/carrier.md` § "Tracking Issue" ausdruecklich **nicht** in den Body, und ihr
  Fehlen ist korrekt statt ein Befund. Der Body nennt das Issue trotzdem, nur ohne Keyword;
  geschlossen wird nach dem Merge von Hand, und zwar von **dir** — Phase 5, `[MERGE-GATE]`.
- Zeigt die Auto-Close-Zeile auf ein Tracking Issue, ist umgekehrt ihre blosse Anwesenheit nicht
  genug: Punkt 8 rechnet sie gegen dessen Body. Anwesenheit und Abwesenheit sind hier dieselbe
  Frage von zwei Seiten — sie wird einmal beantwortet, in Punkt 8.

## Hard-Gate Punkt 7 — welcher Anker zaehlt

Beleg-Pflicht — behauptet der PR-Body **etwas, das der Reviewer nicht im Diff sieht**
(Testlauf, Benchmark, "verifiziert") ohne stabilen Anker (Test-/`It`-Name, Funktions-/
Symbolname, Variablenname, Kommentar-Ueberschrift; SHA-Permalink nur, wo es nichts
Repo-Internes gibt), **nicht** approven (blockt, analog zum `Closes #`-Check aus Punkt 5). Ein
Beleg aus branch-relativem `file:line` oder einem Branch-Link erfuellt die Pflicht nicht; als
Teil eines SHA-Permalinks ist `file:line` in Ordnung. **Was im Diff steht, braucht keinen
Anker** — und wird hier nicht geprueft.

## Hard-Gate Punkt 8 — was zurueckgestellt zaehlt

Zurueckgestellt sind: die Punkte unter „Offene Fragen" /
„Observations" / „Bewusst nicht" des PR-Bodys und jede eigene F-Nummer, die der User auf „offen
lassen" gesetzt hat. **Nicht** mitgezaehlt: ausdruecklich verworfene Punkte, jeder `nitpick:`,
und reine Umgebungsfeststellungen. Der zweite gueltige Ort bleibt eine Zeile in
`roadmap.md`/`backlog.md`.

## Hard-Gate Punkt 8 — ganzer Body, vierte Frage

- **Die dritte Frage geht ueber den GANZEN Body, nicht ueber die Punkte dieses PRs.** Genau
  das war die Luecke: die Zaehlung aus Frage zwei kennt nur, was *dieser* PR zurueckstellt, und
  ein Punkt, der vorher schon drin stand, kommt darin nicht vor. Gelesen wird der Body am Head
  (`gh`/`get_file_contents` bzw. `issue_read`), Zeile fuer Zeile: jede unabgehakte Checkbox
  zaehlt, egal aus welcher Runde sie stammt.
- **Offene Haken plus Auto-Close-Zeile = `issue: (blocking)`**, ohne Ermessen. Der Merge wuerde
  den Traeger schliessen, ohne irgendetwas zu pruefen, und ein geschlossener Traeger sieht aus
  wie ein erledigter (`.agents/rules/carrier.md` § "Tracking Issue", § "Carrier Requirement").
  Die Korrektur ist eindeutig und darum kein `question:`: entweder die offenen Punkte wandern
  vorher an einen anderen gueltigen Traeger, oder die Zeile faellt aus dem Body und der
  `maintainer` schliesst von Hand.
- **Eine Auto-Close-Zeile auf ein Nicht-Tracking-Issue ist davon unberuehrt** — die Bedingung
  haengt am Traeger-Charakter, nicht am Keyword.
- **Vierte Frage: steht im Body noch ein Punkt offen, den dieser PR liefert?** Jede unabgehakte
  Checkbox gegen den Diff halten — ist sie gebaut, muss der PR sie im selben Zug abhaken
  (`.agents/rules/carrier.md` § "Tracking Issue"). Nicht abgehakt trotz geliefert → `issue:
  (blocking)`. Der "Backlog-Gegencheck (beide Richtungen)" aus Phase 1 Schritt 3 sagt inhaltlich
  dasselbe und hat nicht getragen: er steht als Fliesstext zwischen zehn anderen Checks, und was
  nicht im Gate steht, wird nicht abgearbeitet. Die Kosten des Durchrutschens traegt nicht dieser
  PR, sondern die naechste Design-Runde, die den Body liest und Gebautes erneut beauftragt.

## Diese Gedanken bedeuten STOP — du rationalisierst

| Gedanke | Realitaet |
|---|---|
| "Key-Files reichen, der Rest ist Boilerplate" | Zeile fuer Zeile, kein Sampling. |
| "Sieht fertig aus, den Auto-Close-Check kann ich sparen" | Erst Punkt 5, dann Urteil. |
| "Spec passt schon, muss den Diff nicht gegenpruefen" | Spec-Verdikt ist eigenstaendig. |
| "Tests sind gruen, also passt der Fix" | Hallucinated Correctness — kritischen Pfad tracen. |
| "Ich hab die Threads doch resolved" | Nachzaehlen, nicht erinnern — `get_review_comments`, die blockierenden auf null. |
| "Die Zaehlung lief, aber ein offenes `issue: (blocking)` haelt das Fazit nicht auf" | Genau das haelt es auf — erst resolven, dann schreiben (Punkt 4). |
| "Der Punkt ist ausserhalb des Scopes, also blockt er" | Out-of-Scope blockt nicht — er wird eine eigene Aufgabe (Kernprinzip). |
| "Perfekt ist er noch nicht, also noch keine Freigabe" | Freigabe-Standard ist "eindeutig besser", nicht "nichts mehr zu finden". |
| "Steht doch im PR-Body, damit ist es gemeldet" | Ein gemergter Body ist ein Archiv — Tracking-Issue-Gate, Punkt 8. |
| "Der Autor sagt, das laeuft woanders schon" | Am Head nachlesen; ein geschlossenes Issue traegt nichts. |
| "Die Zeile ist da, Punkt 5 abgehakt, weiter" | Zeigt sie auf das Tracking Issue, entscheidet dessen ganzer Body — Punkt 8, dritte Frage. |
| "Das Keyword steht im Body, also blockt Punkt 8" | Nur eine Auto-Close-Zeile zaehlt. Eine Nennung im Fliesstext ist keine — Punkt 5. |
| "Die Punkte dieses PRs stehen alle drin, also passt der Auto-Close" | Der Auto-Close schliesst auch die Punkte der Runden davor. Ganzer Body, nicht nur die eigene Liste. |
| "Ich habe approved, damit bin ich fertig" | Das Tracking Issue schliesst **nach** dem Merge — `[MERGE-GATE]`, Phase 5. |

## Gegenpruefung des Hard-Gates — Empfehlung, keine Pflicht

Nach dem eigenen Durchlauf des Hard-Gates und **vor** dem positiven Abschluss-Verdikt: einen
**frischen** ccweb-Sub-Agenten ansetzen, der ausschliesslich die acht Punkte des `[HARD-GATE]` in
der `SKILL.md` nachrechnet —
**nicht den Code**. Er bekommt PR-Referenz und Repo, liest am Head selbst nach und meldet je Punkt
`geprueft` / `nicht geprueft` / `Befund`, in Conventional Comments.

- **Warum ein eigener Agent.** Er hat Checkout und `git grep`, die einer reinen Chat-Session
  fehlen. Die beiden Fehler, die diese Empfehlung ausgeloest haben, waren Rechenfehler — eine
  falsche Zahl und ein abgehaktes REQ, dessen Zahlen nie gegen den Basis-Branch gerechnet wurden —
  und beide waren damit in Sekunden zu finden.
- **Frisch heisst frisch:** nie der Autoren-Agent und nie der Agent, der den Review geschrieben
  hat. Wer die eigene Zaehlung nachzaehlt, bestaetigt sie.
- **Warum Empfehlung.** Als Pflicht waere es mehr Prozess, und zu viel Prozess ist der Anlass
  dieses Umbaus. Ob der Lauf etwas findet, misst `scripts/common/measure-review-comment.ps1` ueber
  die naechsten Schnitte; findet er nichts, faellt die Empfehlung wieder weg.
- **Wo es nicht geht** — eine Umgebung ohne Sub-Agenten —, entfaellt der Lauf ersatzlos. Er ist
  keine Bedingung des Verdikts, und ein nicht gefahrener Lauf wird als solcher benannt, nicht
  verschwiegen (`.agents/rules/evidence.md` § "Evidence Requirement").

## Warum das Warten auf den Merge ueberhaupt dasteht

Warum das ueberhaupt dasteht: die Zustaendigkeit stand schon an drei Stellen
(`.agents/rules/carrier.md` § "Tracking Issue", `docs/common/developer-guide.md` § "PR / MR", Phase
4 Punkt 5 und diese Phase), und #184/#185 sind nach dem Merge von PR #190 trotzdem liegengeblieben.
Es fehlte der Ausloeser, nicht die Regel: der Merge passiert Stunden nach dem Approve durch den
`maintainer`, und eine Reviewer-Session, die beim Approve aussteigt, ist dann nicht mehr da.

## Merge-Gate — wenn du nicht schliessen kannst

Kannst du nicht schliessen (Rechte, gesperrte Forge), geht es an den `maintainer`, mit derselben
einen Zeile. **Dasselbe gilt, wenn das Warten auslaeuft:** ohne Abo-Faehigkeit endet der
Poll-Fallback nach dem Timeout aus Phase 2, und ein Merge, der danach passiert, weckt niemanden
mehr. Dann geht das Schliessen ebenfalls mit **einer** Zeile an den `maintainer` — ein
abgelaufenes Warten ist eine Uebergabe, kein stiller Abbruch. Der **Merge** bleibt
`maintainer`-only; das Schliessen ist keiner.

## Rueckmeldung nach dem Merge

**Rueckmeldung nach dem Merge.** Laeuft der PR unter einer orchestrierenden Session, gehen nach dem
Merge genau drei Zeilen an sie: was gemergt wurde, was offen blieb, wo es steht. **Zeiger, kein
Inhalt** — alles Weitere liest die Ziel-Session am Repo. Eine weitergereichte Zusammenfassung waere
eine zweite Wahrheit neben dem Repo und genau die Fehlerklasse, gegen die das Tracking Issue
steht.
