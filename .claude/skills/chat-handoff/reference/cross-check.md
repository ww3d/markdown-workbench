# Gegenabgleich des Transcripts

Der Ablauf des Helfers, der einen Teil des Transcripts gegen die Traeger abgleicht: nach jeder
Verdichtung, wenn der aeltere Teil gewachsen ist (`restore-compact-state.sh` nennt Zeilen und
Ergebnisdatei im Hinweis), und vor jeder Uebergabe (`SKILL.md`, Schritt 2). Er laeuft als
Unter-Agent mit Sonnet: die Session gibt ihm Transcript-Pfad, Zeilenbereich und Ergebnisdatei und
liest danach nur die Ergebnisdatei.

## Eingang

- **Transcript:** die JSONL-Datei der Session, eine Zeile je Eintrag.
- **Bereich:** `<von>-<bis>`, Zeilennummern der Datei. Vor einer Uebergabe ohne Hinweis: von der
  Zeile nach dem letzten Abgleich (`<gate>/<session>-cross-check-mark`, sonst 1) bis zur letzten.
- **Ergebnisdatei:** der Pfad aus dem Hinweis, vor einer Uebergabe eine Datei im Scratchpad.
- **Stuecke:** ein Bereich ueber 300 Zeilen laeuft in Stuecken von hoechstens 300 Zeilen; die
  Schritte 1 bis 3 gelten je Stueck, und die Ergebnisdatei waechst je Stueck um dessen offene
  Punkte.

## Ablauf

1. **Auszug.** Nur der Bereich, per `jq` ueber Bash — das Transcript ist zu gross fuer einen Read,
   und eine Zeile kann Megabytes tragen:

   ```bash
   sed -n "${von},${bis}p;${bis}q" "$transcript" | jq -r '(.timestamp // "")[0:16] as $t | select(.isSidechain | not) |
     (select(.type == "user" and (.isMeta | not) and (.isCompactSummary | not))
       | .message.content | if type == "string" then . else
         ([.[]? | select(.type == "text") | .text] | join("\n")) end
       | select(length > 0) | "IN  \($t) " + .[0:2000]),
     (select(.type == "attachment" and .attachment.type == "queued_command")
       | "IN  \($t) " + (.attachment.prompt | tostring)[0:2000]),
     (select(.type == "assistant") | .message.content[]? | select(.type == "text")
       | "OUT \($t) " + .text[0:2000])'
   ```

   `IN` ist jede Eingabe — Satz des Menschen, Nachricht einer anderen Session, vom Werkzeug
   eingespielter Auftrag; eine Nachricht, die waehrend eines Zugs eintrifft, steht als
   `queued_command` —, `OUT` jeder eigene Text der Session. Tool-Ergebnisse fallen weg.
2. **Punkte sammeln:** jeder Satz des Menschen, der etwas verlangt, entscheidet oder fragt; jede
   Nachricht einer anderen Session mit Auftrag, Antwort, Befund oder Frage; jede eigene Zusage
   ("ich mache", "folgt", "trage nach").
3. **Abgleich je Punkt** gegen die Traeger am Head: Issue-Body und -Kommentare, PR-Body,
   Review-Threads, Spec-Datei, Decision-Log (`gh api`, `git grep`). Ein Punkt ist erledigt, wenn
   er dort steht oder gebaut ist; sonst ist er offen. Eine Frage ohne Antwort ist offen.
4. **Ergebnis schreiben** — die Datei entsteht immer, auch ohne Fund, denn die Sperre wartet auf
   sie: je offenem Punkt eine Zeile `- [<Zeit UTC>] <Herkunft>: <Kern in eigenen Worten> —
   fehlt an <Traeger>`, ohne Fund im ganzen Bereich die eine Zeile
   `keine offenen Punkte (Zeilen <von>-<bis>)`.
   Erledigtes steht nicht darin.

## Grenzen

- Der Helfer schreibt nichts an Traeger und aendert nichts im Repo; Offenes traegt die Session
  nach, nachdem sie die Ergebnisdatei gelesen hat.
- Kein Zitat ueber einen Halbsatz hinaus, kein Geheimnis und kein Token in die Ergebnisdatei.
