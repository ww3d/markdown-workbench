# Gegenabgleich des Transcripts

Der Ablauf des Helfers, der einen Bereich des Transcripts gegen die Traeger abgleicht. Die Session gibt ihm Transcript-Pfad, Zeilenbereich und Ergebnisdatei.

## Eingang

- **Transcript:** die JSONL-Datei der Session, eine Zeile je Eintrag.
- **Bereich:** `<von>-<bis>`, Zeilennummern der Datei. Vor einer Uebergabe, ohne Hinweis: von der Zeile nach `<gate>/<session>-cross-check-mark` (sonst 1) bis zum Transcript-Ende.
- **Ergebnisdatei:** der Pfad aus dem Hinweis, vor einer Uebergabe eine Datei im Scratchpad.

## Ablauf

1. **Auszug** — nur der Bereich, per `jq` ueber Bash:

   ```bash
   MAIN_AGENT_IDS=$(jq -c '[inputs | select(.type == "assistant" and (.isSidechain | not))
       | .message.content[]? | select(.type == "tool_use"
           and (.name == "Agent" or .name == "Task" or .name == "Workflow"))
       | .id]' "$transcript")
   sed -n "${von},${bis}p;${bis}q" "$transcript" | jq -r --argjson main_agent_ids "$MAIN_AGENT_IDS" --argjson off "$((von - 1))" '
     (.timestamp // "")[0:16] as $t | (input_line_number + $off) as $z |
     (select(.isSidechain | not) |
       (select(.type == "user" and (.isMeta | not) and (.isCompactSummary | not)
               and ((.origin.kind? // "") != "task-notification")
               and ((.message.content | type) != "array"
                    or (any(.message.content[]?; .type? == "tool_result") | not)))
         | .message.content | if type == "string" then . else
           ([.[]? | select(.type == "text") | .text] | join("\n")) end
         | select(length > 0) | "IN  Z\($z) \($t) " + .[0:2000]),
       (select(.type == "attachment" and .attachment.type == "queued_command")
         | "IN  Z\($z) \($t) " + (.attachment.prompt | tostring)[0:2000]),
       (select(.type == "assistant") | .message.content[]? | select(.type == "text")
         | "OUT Z\($z) \($t) " + .text[0:2000]),
       # PEN: open points of the last compaction summary. The summary is isCompactSummary=true;
       # its "Pending Tasks" (or equivalent) section typically sits at the end, so the tail is
       # kept, not the head.
       (select(.type == "user" and .isCompactSummary == true)
         | .message.content | if type == "string" then . else
           ([.[]? | select(.type == "text") | .text] | join("\n")) end
         | select(length > 0) | "PEN Z\($z) \($t) " + .[-2000:]),
       # HLP: sub-agent results. Two shapes - a tool_result for an Agent/Task/Workflow tool_use of
       # the main thread (bash looks the id up in the $main_agent_ids list), and a
       # <task-notification> user line (background helper).
       (select(.type == "user" and ((.origin.kind? // "") == "task-notification"))
         | .message.content | if type == "string" then . else
           ([.[]? | select(.type == "text") | .text] | join("\n")) end
         | select(length > 0) | "HLP Z\($z) \($t) task-notification: " + .[0:2000]),
       (select(.type == "user" and (.message.content | type) == "array")
         | .message.content[]? | select(.type == "tool_result"
             and (.tool_use_id | type == "string")
             and (.tool_use_id | . as $i | $main_agent_ids | index($i)))
         | "HLP Z\($z) \($t) sub-agent " + (.tool_use_id)
         + ": " + ((.content | if type == "string" then . else
             ([.[]? | select(.type == "text") | .text] | join("\n")) end)[0:2000]))
     )'
   ```

   `IN` ist jede Eingabe (Satz des Menschen, Nachricht einer anderen Session, eingespielter Auftrag, `queued_command`), `OUT` jeder eigene Text der Session, `HLP` ein Helfer-Ergebnis, `PEN` eine offene Zeile aus der letzten Verdichtungs-Zusammenfassung. `Z<n>` ist die
   Transcript-Zeile.
2. **Punkte sammeln:** jeder Satz des Menschen, der etwas verlangt, entscheidet oder fragt — eine Ruege (Kritik am eigenen Vorgehen) zaehlt als Verlangen und ist nur mit einer Traeger-Zeile zur gebrochenen Regel oder Erfahrung erledigt; jede Nachricht einer anderen Session mit Auftrag, Antwort, Befund oder Frage; jede eigene Zusage; jeder eigene Vorschlag, bis er dem Menschen als Frage vorgelegt oder an einem Traeger abgelegt ist; jedes Helfer-Ergebnis (`HLP`) mit Auftrag, Antwort, Befund oder Frage; jede offene Zeile der letzten Zusammenfassung (`PEN`). Steht in der Replay-Datei `the compaction summary is not in the transcript yet`, gilt der Abgleich der Eingaben gegen die Traeger trotzdem. Die eigene
   Antwort des letzten Zugs vor der Verdichtung (der Hinweis nennt ihre Zeilen) wird in jedem Fall
   auf Zusagen geprueft: eine Zusage, die kein spaeteres Werkzeugergebnis und keine Traeger-Zeile
   belegt, ist ein Punkt.
3. **Abgleich je Punkt** gegen die Traeger am Head: Issue-Body und -Kommentare, PR-Body,
   Review-Threads, Spec-Datei, Decision-Log (`gh api`, `git grep`). Ein Punkt ist erledigt, wenn
   er dort steht oder gebaut ist; sonst ist er offen. Eine Frage ohne Antwort ist offen.
   Behauptet ein eigener Satz, etwas sei erledigt oder stehe am Traeger, wird der genannte Inhalt dort gelesen; fehlt er, ist der Punkt offen.
4. **Ergebnis schreiben** — die Datei entsteht immer, auch ohne Fund: je offenem Punkt eine Zeile `- [<Zeit UTC>] Zeilen <von>-<bis> <Herkunft>: <Kern in eigenen Worten> — fehlt an <Traeger>`, ohne Fund im ganzen Bereich die eine Zeile `keine offenen Punkte (Zeilen <von>-<bis>)`.
   Erledigtes steht nicht darin.

## Grenzen

- Der Helfer schreibt nichts an Traeger und aendert nichts im Repo; Offenes traegt die Session
  nach, nachdem sie die Ergebnisdatei gelesen hat.
- Kein Zitat ueber einen Halbsatz hinaus in die Ergebnisdatei.
