#!/usr/bin/env bash
#
# Stop hook - a turn never ends on an announcement without the act (.agents/rules/pr.md, section
# "Session Traffic"; ww3d/playbook#502). Generic, byte-identical across consumers.
#
# Blocks the turn end when the last assistant message carries no tool_use and one of its sentences,
# or a part of it between ";" and ": ", announces an act (ANN below: "ich werde ...", "ich pruefe
# jetzt ...", "als Naechstes ...", "Bericht folgt", "I'll ...", "let me ..."). Free stay a part with
# a condition or a wait (COND), a negation (NEG), a report of what was done (REPORT), a sentence that
# ends on "?" - a turn may end on a question -, a bare heading ("Als Naechstes:", "## Danach"), a
# report head of time word and past participle ("Jetzt geprueft: ..."), and
# text that cites: double quotes, inline code, a code fence, a quote line (">"). The patterns follow
# the instance hook the maintainer switched on (docs/provenance.md); no model judges.
#
# The text is the event's last_assistant_message where Claude Code sends one; otherwise every
# assistant entry of the transcript with the message id of the newest one (one entry per content
# block), read from the transcript's last 200 lines only - the file grows to tens of MB and this runs
# at every turn end. A line that does not parse (a write in progress cut it) is skipped.
#
# Loop guard: Claude Code sets stop_hook_active when the turn already continues on a Stop hook's
# block; the hook then lets the turn end and says so in a systemMessage instead of blocking again.
# Fail-open: no text, no jq, or jq failing lets the turn end without output.
#
# Stdin:  the Stop hook event JSON ({ transcript_path, last_assistant_message, stop_hook_active }).
# Stdout: when blocking { decision: "block", reason, systemMessage }; on the loop guard
#         { systemMessage } only; otherwise nothing.

set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
hook_payload_quiet=1 read_hook_payload
input="$hook_input"

stop_hook_active="$(printf '%s' "$input" | jq -r '.stop_hook_active == true' 2>/dev/null || true)"
stop_hook_active="${stop_hook_active%$'\r'}" # jq for Windows ends its lines with CRLF
text="$(printf '%s' "$input" | jq -r '.last_assistant_message | strings' 2>/dev/null || true)"
if [ -z "$text" ]; then
  transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  transcript="${transcript%$'\r'}"
  [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  last_jq='
      [ split("\n")[] | select(length > 0) | (fromjson? // empty) | select(.type == "assistant") ] as $a
    | if ($a | length) == 0 then empty else
      ($a | last | .message.id?) as $id
    | [ $a[] | select(if $id == null then false else .message.id? == $id end) ] as $msg
    | (if ($msg | length) > 0 then $msg else [$a | last] end) as $msg
    | [ $msg[] | .message.content? | if type == "array" then .[] else empty end ] as $blocks
    | if ($blocks | any(.type? == "tool_use")) then empty
      else [ $blocks[] | select(.type? == "text") | .text | strings ] | join("\n") end
    end
  '
  text="$(tail -n 200 -- "$transcript" 2>/dev/null | grep -F '"type":"assistant"' | jq -Rrs "$last_jq" 2>/dev/null || true)"
fi
[ -n "$text" ] || exit 0

# The patterns, one alternative per line; ${V} is a first-person verb, ${ADV} a time word.
V='(?:starte|mache|pr(?:ue|ü)fe|schaue|schau|lese|baue|schicke|gebe|setze|hole|trage|frage|kl(?:ae|ä)re|lege|melde|gehe|r(?:ae|ä)ume|merge|committe|pushe|dokumentiere|messe|st(?:oe|ö)(?:ss|ß)e|fange|beginne|(?:ue|ü)bernehme|erledige|erg(?:ae|ä)nze|sende|rufe|suche|ziehe|bringe|schreibe|lasse|stelle|f(?:ue|ü)hre|fixe|checke|beantworte|antworte|sage|teile|lade|kopiere|aktualisiere|kuemmere|k(?:ue|ü)mmere|nehme|gleiche|erstelle|poste|(?:oe|ö)ffne|schlie(?:ss|ß)e|ordne|vermerke|lösche|loesche|l(?:oe|ö)se|stoppe|stosse|beende|wiederhole|wechsle|pflege|bereite|verschiebe|schiebe|kontrolliere|entferne|ersetze|sichere|stelle|spiele|teste|probiere|verfolge|vergleiche|analysiere|werte|zähle|zaehle|notiere|lies|sehe|hole|nutze|verwende|liefere|korrigiere|repariere|bessere|rolle|fahre|(?:ue|ü)berpr(?:ue|ü)fe|(?:ue|ü)bertrage|(?:ue|ü)berarbeite|mach|leg|pack|geh|fang|bau|trag|start|schick|komm|pruef|prüf)'
ADV='(?:noch heute|zuerst|zun(?:ae|ä)chst|als erste[sn]|erste[sn]|im anschluss|jetzt|gleich|nun|sofort|danach|dann|anschlie(?:ss|ß)end|zuerst|zun(?:ae|ä)chst|direkt|umgehend|im anschluss|als n(?:ae|ä)chstes|in k(?:ue|ü)rze|sp(?:ae|ä)ter|erst mal|erstmal|nachher|noch heute|gleich mal|im n(?:ae|ä)chsten schritt|n(?:ae|ä)chstens|zuallererst|vorher)'
ann=''
while IFS= read -r alt; do ann="${ann:+${ann}|}${alt}"; done <<'ANN'
\bich werde\b
\bich ${V}\b[^.!?\n;]*\b${ADV}\b
\b${ADV}\b[^.!?\n;]*\bich ${V}\b
\b${ADV}\s+${V}\s+ich\b
\bich ${V}\b[^.!?\n;]*\b(?:an|ein|auf|aus|ab|zu|um|nach|zurueck|zur(?:ue|ü)ck|fest|los|vor|mit|weiter|hinzu)\b[^.!?\n;]*$
^(?:ja,? |ok,? |gut,? )?ich ${V}\b
\b(?:mach|pack|leg|schau|kuemmer|k(?:ue|ü)mmer|trag|guck|seh|gehe?|fang|bau|start|schick|check|pr(?:ue|ü)f|lese?|hol|nehm|bring|mel[dt]|setz|stell|f(?:ue|ü)hr|schreib|lad|r(?:ae|ä)um|erled|klaer|kläer) ich\b
\bbin (?:gleich|sofort|direkt|schon|jetzt) (?:dran|zur(?:ue|ü)ck|wieder da|da)\b|\bbin dran\b|\bbleib(?:e)? dran\b
\bals n(?:ae|ä)chste[sn]?\b
\bn(?:ae|ä)chster schritt\b
\b(?:bericht|ergebnis|details?|antwort|schritte?|meldung|r(?:ue|ü)ckmeldung|rest|mehr|fortsetzung|release|controller|dev-auftrag|registry) (?:folgt|folgen|kommt|kommen)\b
\bich [a-zäöüß]+\b[^.!?\n;]*\b${ADV}\b
\b[a-zäöüß]{3,}e ich\b[^.!?\n;]*\b${ADV}\b
\b(?:k(?:ue|ü)mmer[a-zäöüß]* mich|geht gleich los|leg gleich los|meld mich|geb(?:e)? bescheid|mehr dazu gleich|dran bin ich|bin gleich zur(?:ue|ü)ck|ich bin gleich)\b
\b(?:wird erledigt|mach mich dran|bin gleich dabei|hab ich gleich|l(?:ae|ä)uft gleich an|auf geht's)\b
\b(?:proceeding to|stay tuned|to follow|coming up|in a moment|will be \w+ed|for now i)\b
\bwird\b[^.!?\n;]*\b(?:erg(?:ae|ä)nzt|nachgereicht|committet|gestartet|angelegt|ge(?:oe|ö)ffnet|gelesen|gemergt|gepusht)\b
\b(?:kommt|folgt|folgen|kommen) (?:gleich|sofort|direkt|danach|anschlie(?:ss|ß)end|als n(?:ae|ä)chstes|im anschluss|in k(?:ue|ü)rze|im n(?:ae|ä)chsten schritt|noch heute|umgehend|sp(?:ae|ä)ter|jetzt|nun)\b
\b(?:gleich|sofort|jetzt|nun|danach|anschlie(?:ss|ß)end|direkt|als n(?:ae|ä)chstes|im anschluss|in k(?:ue|ü)rze|umgehend) (?:mehr|folgt|folgen|kommt|geht)\b
\b(?:wird|werden)\s+(?:\S+\s+){0,5}?(?:gleich|jetzt|sofort|als n(?:ae|ä)chstes|anschlie(?:ss|ß)end|im anschluss|in k(?:ue|ü)rze|direkt|umgehend)\b
\bweiter (?:mit|gehts|geht's|geht es)\b|\bgeht (?:es )?weiter\b|\bweiter geht
\bmelde mich\b|\bgebe bescheid\b|\bsage bescheid\b|\bgeb gleich bescheid\b|\bmelde ich\b
^(?:nun|jetzt|gleich|danach|dann|anschlie(?:ss|ß)end|zuerst|zun(?:ae|ä)chst|als n(?:ae|ä)chstes|n(?:ae|ä)chster schritt)\b
\b(?:i'll|i will|i'm going to|i am going to|i shall|i'm about to|let me|let's|we'll|will do|on it|moving on|up next|next up|going to)\b
^(?:next|now|then|first|after that|afterwards|finally)\b[^.!?\n]*
\bwill (?:be )?\w+(?:ed)?\b[^.!?\n;]*\b(?:next|after that|shortly|soon|straight away|right away|momentarily|later|afterwards)\b
\b(?:next|shortly|soon|straight away|right away|momentarily|afterwards|after that) i\b
\bwill (?:check|fix|start|measure|merge|clean|read|open|write|do|run|send|push|commit|build|handle|review|look|update|post|file|continue|follow)\b
\b(?:ich )?(?:schau|guck|sehe?) (?:ich )?(?:mir )?(?:das|es|die|den|dem|ihn|sie)\b[^.!?\n;]*\b(?:an|durch|nach)\b
\bdran bin ich\b|\bnehme ich mir\b|\bnehm ich mir\b|\bich nehme mir\b|\bich lege los\b|\blege los\b
ANN
ann="${ann//\$\{V\}/$V}"
ann="${ann//\$\{ADV\}/$ADV}"
ann="${ann//\'/[\'’]}" # the typographic apostrophe too: "I’ll"
cond='\b(bis|erst|noch(?! heute)|ohnehin|ende|laufen|l(?:ae|ä)uft(?! gleich)|weckt|per (?:meldung|benachrichtigung)|ist er|wird es|h(?:ae|ä)lt|alle \d+ minuten|in etwa|ab etwa|wie [a-z ]*angek|nach #|beim merge|nur noch|sp(?:ae|ä)testens|dann sag|hatte|darum habe|sobald|wenn|falls|nachdem|bevor|solange|sofern|ob|once|when|whenever|if|unless|until|before|as soon as|after (?:the|it|he|she|they|you|that has)|bei (?:gr(?:ue|ü)n|rot|ende|fehler|erfolg|bedarf|abschluss|treffer|freigabe|ja|nein)|auf (?:dein|deine|deinen|ihr|sein|seine|dein) (?:go|ja|ok|freigabe|signal|antwort|entscheidung)|nach (?:dem|der|deinem|deiner|eurem|seinem|ihrem) (?:merge|go|ja|ok|freigabe|ende|abschluss|antwort|entscheidung|lauf|review|ergebnis)|wartet|warte|abwarten|warten|solange|falls)\b'
neg='\b(?:nicht|kein|keine|keinen|keinem|keiner|nichts|niemals|nie|never|not|nothing|no longer)\b'
past_report='(?:^|\b)(?:ich habe|hab ich|habe ich|ich hatte|i have|i'"'"'ve|i had|i did|i was)\b'
# shellcheck disable=SC2016 # a regex: the backticks are inline-code quotes, not command substitution
quote='"[^"\n]*"|„[^“”"\n]*[“”"]|“[^”\n]*”|«[^»\n]*»|`[^`\n]*`'

# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
hits_jq='
    $text
  | gsub("```[\\s\\S]*?(```|$)"; "\n")
  | [ split("\n")[] | select(test("^\\s*>") | not) ] | join("\n")
  | gsub($quote; " ")
  | [ splits("(?<=[.!?])\\s+|\\n+") | gsub("^\\s+|\\s+$"; "") | select(length > 0 and length <= 500)
      | select((test("\\?\\s*[\"'\'')\\]*_]*$") or test("\\blet me know\\b"; "i")) | not)
      | . as $full | test($neg; "i") as $wholeneg
      | splits(";\\s*|:\\s+")
      | . as $s | (gsub("[*_#>\\-\\s]+"; " ") | gsub("^\\s+|\\s+$"; "")) as $t
      | select(($t | test(":$")) or ($full | test("^\\s*#")) | not)
      | select($t | test("^(?:jetzt|nun|gerade|soeben|eben|inzwischen|mittlerweile)\\s+(?:ge\\w+(?:t|en)|\\w+iert)$"; "i") | not)
      | $s
      | select(test($ann; "i"))
      | select(test($cond; "i") | not)
      | select((test($neg; "i") or ($wholeneg and test("^ich\\b"; "i"))) | not)
      | select(test($report; "i") | not)
      | gsub("^\\s+|\\s+$"; "") ]
  | .[0:3][] | .[0:160]
'
hits="$(jq -nr --arg text "$text" --arg ann "$ann" --arg cond "$cond" --arg neg "$neg" --arg report "$past_report" \
  --arg quote "$quote" "$hits_jq" 2>/dev/null || true)"
hits="${hits//$'\r'/}"
[ -n "$hits" ] || exit 0

if [ "$stop_hook_active" = "true" ]; then
  jq -cn '{
    systemMessage: ("The turn still ends on an announcement without the act; the Stop hook blocked "
      + "this stop once already and now lets the turn end.")
  }' || true
  exit 0
fi

# The hits go in as an argument: a native Windows jq cannot open the /proc/<pid>/fd path of a process substitution.
jq -cn --arg h "$hits" '{
  decision: "block",
  reason: ("A turn ends with a tool call, a hand-back or a question, never with an announcement "
    + "(.agents/rules/pr.md, section \"Session Traffic\"). Announced without the act: "
    + ($h | split("\n") | map(select(length > 0) | "\"" + . + "\"") | join(" | "))
    + " - tu es jetzt mit einem Werkzeugaufruf, oder schreib nur diesen einen Satz neu bzw. nenne, worauf du"
    + " wartest. Der Mensch hat deine Antwort schon gesehen: nie die ganze Antwort wiederholen."),
  systemMessage: "Turn end blocked: an announcement without the act."
}' || true
exit 0
