#!/usr/bin/env bash
#
# Stop hook - a turn never ends on an announcement without the act (.agents/rules/pr.md, section
# "Session Traffic"; ww3d/playbook#502). Generic, byte-identical across consumers.
#
# Blocks the turn end when the last assistant message carries no tool_use and one of its sentences,
# or a part of it between ";" and ": ", announces an act (ANN below: "ich werde ...", "ich pruefe
# jetzt ...", "als Naechstes ...", "Bericht folgt", "I'll ...", "let me ..."). Free stay a part with
# a condition, a wait or a Konjunktiv II (COND), a negation (NEG), a report of what was done (REPORT),
# a sentence that ends on "?" - a turn may end on a question -, a bare heading ("Als Naechstes:",
# "## Danach"), a report head of time word and past participle ("Jetzt geprueft: ..."), and
# text that cites: double quotes, inline code, a code fence, a quote line (">"). Free too
# (ww3d/playbook#515): a part with a sequence word right after a part with a condition, and after any
# earlier part with a wait ("Ich warte auf X; danach ...") also a part without a first-person word; a
# Konjunktiv II without an own act beside it; a report with evidence, a past or a state plus a link, a
# commit hash or a #N, without a present first-person verb. A passive or a modal part stays blocked; a
# sentence about a third person gets no rule of its own. The patterns follow the instance hook the
# maintainer switched on (in the playbook, docs/provenance.md); no model judges.
#
# No second message and no filler: the reason asks for the act as a tool call, or else for the next real step or a
# question - never for a character or a rewritten answer (order 6 of ww3d/playbook#515).
#
# Late wake (ww3d/playbook#515): where a resting session can be woken - an interactive terminal session
# (CLAUDE_CODE_ENTRYPOINT=cli, CLAUDE_CODE_REMOTE not true) with a session id, a transcript and a writable log -
# a hit does not block. The synchronous entry only logs it (mode "rewake"); the same script as the asyncRewake
# entry ("--rewake") waits ANNOUNCE_REWAKE_SECONDS (default 600), ends silently as soon as the transcript moved
# on, and else wakes the session with exit 2 and the same message. A hit wakes at most once; the answer to the
# wake is labelled and not checked for waking again. Headless and web runs block at once, as before.
#
# Self-measurement: every hit appends a line to ${TMPDIR:-/tmp}/claude-rule-gate/announce-log.jsonl
# (stamp, session, mode, hit sentences with their ANN line numbers, outcome "pending"); the next stop of
# that session labels it "woken" (mode rewake: the session went on by itself), or after a block or a wake
# "real" (a tool_use followed) or "false" (none did: a false block, counted once for learning); the wake sets
# "rewoken" before. A pending line older than a day becomes "stale", the oldest lines go past 2,000.
# A turn aborted by the user never reaches a Stop hook, so its hit is labelled by the next stop.
# "--stats" counts the outcomes per ANN line.
# "--learn" switches off, in announce-off.txt beside the log, every ANN line with at least 5 labelled hits
# (real, false, text) and no real one, at most half of the lines; a real hit switches a line on again at the
# next pass. The hook runs it at every 25th logged hit, after its decision; "--learn --report" lists the
# switched-off lines as a proposal to strike them for good. Logging and learning are fail-open and never change
# the decision of the stop that runs them.
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
# Stdin:  the Stop hook event JSON ({ session_id, transcript_path, last_assistant_message,
#         stop_hook_active }).
# Stdout: when blocking { decision: "block", reason, systemMessage }; on the loop guard
#         { systemMessage } only; otherwise nothing. With --stats the counts per ANN line.

set -uo pipefail

gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
ann_log="$gate_dir/announce-log.jsonl"
ann_off="$gate_dir/announce-off.txt"       # the numbers of the ANN lines --learn switched off on this machine
ann_cnt="$gate_dir/announce-learn.count"   # hits logged since the last learning pass
learn_min=5                                # labelled hits a line needs before it can be switched off
learn_every=25                             # a learning pass at every 25th logged hit
rewake_wait="${ANNOUNCE_REWAKE_SECONDS:-600}" # N: seconds the --rewake entry waits before it wakes the session
rewake_poll="${ANNOUNCE_REWAKE_POLL:-30}"        # seconds between two looks at the transcript while it waits
[[ $rewake_wait =~ ^[0-9]+$ ]] || rewake_wait=600
[[ $rewake_poll =~ ^[1-9][0-9]*$ ]] || rewake_poll=30
# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
stale_jq='if (.outcome == "pending" or .outcome == "rewoken") and ((.ts | fromdateiso8601? // 0) < now - 86400) then .outcome = "stale" else . end'

mode=block
case "${1:-}" in
  --stats) mode=stats ;;
  --learn) mode=learn ;;
  --rewake) mode=rewake ;;
esac

# Waking a resting session works in an interactive terminal session; a headless run (sdk-cli) and a web session block.
rewake_capable() { [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ "${CLAUDE_CODE_REMOTE:-}" != true ]; }

ann_write() { # jq args over the log's lines as raw input -> the log rewritten, at most 2,000 lines; fail-open
  local tmp="$ann_log.$$"
  { [ ! -f "$ann_log" ] || cat -- "$ann_log"; } 2>/dev/null | jq -Rnc "$@" 2>/dev/null | tail -n 2000 > "$tmp" 2>/dev/null \
    && mv -f -- "$tmp" "$ann_log" 2>/dev/null
  rm -f -- "$tmp" 2>/dev/null
  return 0
}

# The patterns, one alternative per line; ${V} is a first-person verb, ${ADV} a time word.
V='(?:starte|mache|pr(?:ue|ü)fe|schaue|schau|lese|baue|schicke|gebe|setze|hole|trage|frage|kl(?:ae|ä)re|lege|melde|gehe|r(?:ae|ä)ume|merge|committe|pushe|dokumentiere|messe|st(?:oe|ö)(?:ss|ß)e|fange|beginne|(?:ue|ü)bernehme|erledige|erg(?:ae|ä)nze|sende|rufe|suche|ziehe|bringe|schreibe|lasse|stelle|f(?:ue|ü)hre|fixe|checke|beantworte|antworte|sage|teile|lade|kopiere|aktualisiere|kuemmere|k(?:ue|ü)mmere|nehme|gleiche|erstelle|poste|(?:oe|ö)ffne|schlie(?:ss|ß)e|ordne|vermerke|lösche|loesche|l(?:oe|ö)se|stoppe|stosse|beende|wiederhole|wechsle|pflege|bereite|verschiebe|schiebe|kontrolliere|entferne|ersetze|sichere|stelle|spiele|teste|probiere|verfolge|vergleiche|analysiere|werte|zähle|zaehle|notiere|lies|sehe|hole|nutze|verwende|liefere|korrigiere|repariere|bessere|rolle|fahre|(?:ue|ü)berpr(?:ue|ü)fe|(?:ue|ü)bertrage|(?:ue|ü)berarbeite|mach|leg|pack|geh|fang|bau|trag|start|schick|komm|pruef|prüf)'
ADV='(?:noch heute|zuerst|zun(?:ae|ä)chst|als erste[sn]|erste[sn]|im anschluss|jetzt|gleich|nun|sofort|danach|dann|anschlie(?:ss|ß)end|zuerst|zun(?:ae|ä)chst|direkt|umgehend|im anschluss|als n(?:ae|ä)chstes|in k(?:ue|ü)rze|sp(?:ae|ä)ter|erst mal|erstmal|nachher|noch heute|gleich mal|im n(?:ae|ä)chsten schritt|n(?:ae|ä)chstens|zuallererst|vorher)'

ann_lines=()
while IFS= read -r alt; do ann_lines+=("$alt"); done <<'ANN'
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
# The patterns of the file: the {V} and {ADV} placeholders and the typographic apostrophe resolved per line.
for ((i = 0; i < ${#ann_lines[@]}; i++)); do
  l="${ann_lines[i]//\$\{V\}/$V}"; l="${l//\$\{ADV\}/$ADV}"; ann_lines[i]="${l//\'/[\'’]}"
done
# The lines --learn switched off stay numbered for the log but out of the pattern.
off=" "
if [ -s "$ann_off" ]; then
  while IFS= read -r n; do n="${n%$'\r'}"; [[ $n =~ ^[0-9]+$ ]] && off+="$n "; done < "$ann_off"
fi
ann=''
for ((i = 0; i < ${#ann_lines[@]}; i++)); do
  case "$off" in *" $((i + 1)) "*) continue ;; esac
  ann="${ann:+${ann}|}${ann_lines[i]}"
done

if [ "$mode" = stats ]; then
  if [ ! -s "$ann_log" ]; then echo "No announce log at $ann_log."; exit 0; fi
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  jq -Rnr '
      [ inputs | fromjson? | objects | '"$stale_jq"' ] as $l
    | def n($o): map(select(.o == $o)) | length;
      "\($l | length) hits in the announce log; per ANN line: hits, real, false, text, woken, rewoken, pending, stale",
      ( [ $l[] | .outcome as $o | [ .hits[]?.lines[]? ] | unique[] | {p: ., o: $o} ]
        | group_by(.p)[] | "line \(.[0].p): \(length) \(n("real")) \(n("false")) \(n("text")) \(n("woken")) \(n("rewoken")) \(n("pending")) \(n("stale"))" )
  ' "$ann_log" 2>/dev/null || echo "The announce log at $ann_log could not be read."
  exit 0
fi

# Learning: a line with at least $learn_min labelled hits (real, false, text) and no real one is switched off, at
# most half of the lines; a real hit on it later switches it on again at the next pass, since the file is recomputed.
learn_rows=''
learn() { # recompute $ann_off from the log; $learn_rows holds "line labelled real false text" per switched-off line
  learn_rows=''
  if [ -s "$ann_log" ]; then
    # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
    learn_rows="$(jq -Rnr --argjson min "$learn_min" --argjson cap "$(( ${#ann_lines[@]} / 2 ))" '
        [ inputs | fromjson? | objects | select(.outcome == "real" or .outcome == "false" or .outcome == "text")
          | .outcome as $o | [ .hits[]?.lines[]? ] | unique[] | {p: ., o: $o} ]
        | group_by(.p)
        | map({p: .[0].p, n: length, r: (map(select(.o == "real")) | length),
               f: (map(select(.o == "false")) | length), t: (map(select(.o == "text")) | length)})
        | map(select(.n >= $min and .r == 0)) | sort_by(-.n, .p) | .[0:$cap][]
        | "\(.p) \(.n) \(.r) \(.f) \(.t)"' "$ann_log" 2>/dev/null)" || return 0
    learn_rows="${learn_rows//$'\r'/}"
  fi
  if [ -n "$learn_rows" ]; then
    { mkdir -p "$gate_dir" && while read -r p _; do printf '%s\n' "$p"; done <<<"$learn_rows" > "$ann_off.$$" \
        && mv -f -- "$ann_off.$$" "$ann_off"; } 2>/dev/null
    rm -f -- "$ann_off.$$" 2>/dev/null
  else
    rm -f -- "$ann_off" 2>/dev/null
  fi
  return 0
}
if [ "$mode" = learn ]; then
  learn
  n_off=0; [ -z "$learn_rows" ] || n_off="$(printf '%s\n' "$learn_rows" | wc -l | tr -d '[:space:]')"
  echo "$n_off of ${#ann_lines[@]} pattern lines switched off on this machine (file $ann_off)."
  if [ "${2:-}" = "--report" ] && [ -n "$learn_rows" ]; then
    echo "Proposal to strike for good by a PR - lines with at least $learn_min labelled hits and no real one:"
    while read -r p n r f t; do
      printf 'line %s: %s labelled, real %s, false %s, text %s: %s\n' "$p" "$n" "$r" "$f" "$t" "${ann_lines[p - 1]:0:100}"
    done <<<"$learn_rows"
  fi
  exit 0
fi

[ "$mode" != rewake ] || rewake_capable || exit 0

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
hook_payload_quiet=1 read_hook_payload
input="$hook_input"

stop_hook_active="$(printf '%s' "$input" | jq -r '.stop_hook_active == true' 2>/dev/null || true)"
stop_hook_active="${stop_hook_active%$'\r'}" # jq for Windows ends its lines with CRLF
session="$(printf '%s' "$input" | jq -r '.session_id | strings' 2>/dev/null || true)"
session="${session%$'\r'}"
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || session=""
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
transcript="${transcript%$'\r'}"
# The text of the last assistant message of a transcript, empty when it called a tool. With $strict the last
# conversational entry must be that message (a user entry after it means the session went on).
# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
last_text_jq='
    [ split("\n")[] | select(length > 0) | (fromjson? // empty)
      | select(.type == "assistant" or ($strict and .type == "user")) ] as $e
  | if ($e | length) == 0 or ($e | last | .type) != "assistant" then empty else
    ($e | last | .message.id?) as $id
  | [ $e[] | select(.type == "assistant" and (if $id == null then false else .message.id? == $id end)) ] as $msg
  | (if ($msg | length) > 0 then $msg else [$e | last] end) as $msg
  | [ $msg[] | .message.content? | if type == "array" then .[] else empty end ] as $blocks
  | if ($blocks | any(.type? == "tool_use")) then empty
    else [ $blocks[] | select(.type? == "text") | .text | strings ] | join("\n") end
  end
'
text="$(printf '%s' "$input" | jq -r '.last_assistant_message | strings' 2>/dev/null || true)"
if [ -z "$text" ]; then
  [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  text="$(tail -n 200 -- "$transcript" 2>/dev/null | grep -F '"type":"assistant"' \
    | jq -Rrs --argjson strict false "$last_text_jq" 2>/dev/null || true)"
fi

# The answer after a block labels that block - cheap greps first: this runs at every turn end. A hit that did not
# block (mode "rewake") is labelled "woken" by the next stop: the session went on by itself. The answer to a wake
# ("rewoken") is labelled like the answer to a block and then not checked for waking again.
bare="${text//[[:space:]]/}"
answered_wake=0
if [ "$mode" != rewake ] && [ -n "$session" ] && [ -s "$ann_log" ] \
  && grep -F "\"session_id\":\"$session\"" "$ann_log" 2>/dev/null | grep -qE '"outcome":"(pending|rewoken)"'; then
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  last="$(grep -F "\"session_id\":\"$session\"" "$ann_log" 2>/dev/null | grep -E '"outcome":"(pending|rewoken)"' \
    | jq -r "$stale_jq"' | select(.outcome == "pending" or .outcome == "rewoken") | "\(.ts // "") \(.outcome) \(.mode // "block")"' \
    2>/dev/null | tail -n 1 || true)"
  last="${last%$'\r'}"
  read -r since prior lmode <<<"$last"
  if [ -n "$since" ]; then
    outcome=false
    if [ "$prior" = pending ] && [ "$lmode" = rewake ]; then
      outcome=woken
    elif [ -n "$transcript" ] && [ -f "$transcript" ]; then
      # The transcript stamps carry milliseconds, the log's whole seconds.
      acted="$(tail -n 400 -- "$transcript" 2>/dev/null | grep -F '"tool_use"' | jq -Rn --arg ts "$since" '
          [ inputs | fromjson? | select(.type? == "assistant" and ((.timestamp // "") | sub("\\.[0-9]+Z$"; "Z")) >= $ts)
            | select(any(.message.content[]?; .type? == "tool_use")) ] | length > 0' 2>/dev/null || true)"
      [ "${acted%$'\r'}" != "true" ] || outcome=real
    fi
    [ "$prior" != rewoken ] || answered_wake=1
    # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
    ann_write --arg sid "$session" --arg out "$outcome" '
        [ inputs | fromjson? | objects | '"$stale_jq"' ] as $l
      | ([ $l | to_entries[] | select(.value.session_id == $sid and (.value.outcome == "pending" or .value.outcome == "rewoken")) | .key ] | last) as $k
      | ($l | if $k == null then . else .[$k].outcome = $out end)[]'
  fi
fi
[ "$answered_wake" = 0 ] || exit 0

[ -n "$text" ] || exit 0

cond='\b(bis|erst|noch(?! heute)|ohnehin|ende|laufen|l(?:ae|ä)uft(?! gleich)|weckt|per (?:meldung|benachrichtigung)|ist er|wird es|h(?:ae|ä)lt|alle \d+ minuten|in etwa|ab etwa|wie [a-z ]*angek|nach #|beim merge|nur noch|sp(?:ae|ä)testens|dann sag|hatte|darum habe|sobald|wenn|falls|nachdem|bevor|solange|sofern|ob|once|when|whenever|if|unless|until|before|as soon as|after (?:the|it|he|she|they|you|that has)|bei (?:gr(?:ue|ü)n|rot|ende|fehler|erfolg|bedarf|abschluss|treffer|freigabe|ja|nein)|auf (?:dein|deine|deinen|ihr|sein|seine|dein) (?:go|ja|ok|freigabe|signal|antwort|entscheidung)|nach (?:dem|der|deinem|deiner|eurem|seinem|ihrem) (?:merge|go|ja|ok|freigabe|ende|abschluss|antwort|entscheidung|lauf|review|ergebnis)|wartet|warte|abwarten|warten|solange|falls)\b'
# Konjunktiv II counts as a condition, but not beside a first-person act in the same part.
konj='\b(?:k(?:oe|ö)nnten?|w(?:ue|ü)rden?|sollten?|d(?:ue|ü)rften?|m(?:ue|ü)ssten?|h(?:ae|ä)tten?|w(?:ae|ä)ren?|could|would|might|should)\b'
neg='\b(?:nicht|kein|keine|keinen|keinem|keiner|nichts|niemals|nie|never|not|nothing|no longer)\b'
past_report='(?:^|\b)(?:ich habe|hab ich|habe ich|ich hatte|i have|i'"'"'ve|i had|i did|i was)\b'
# shellcheck disable=SC2016 # a regex: the backticks are inline-code quotes, not command substitution
quote='"[^"\n]*"|„[^“”"\n]*[“”"]|“[^”\n]*”|«[^»\n]*»|`[^`\n]*`'
# A sequence word after a part with a condition (right before it) or a real wait (anywhere before it).
seq='\b(?:danach|dann|anschlie(?:ss|ß)end|im anschluss|als n(?:ae|ä)chste[sn]?|next|then|after that)\b'
# A run that goes on is a wait; "laeuft gruen" or "laeuft wieder" is a state.
wait='\b(?:warte|wartet|warten|abwarten|(?:l(?:ae|ä)uft|laufen)(?! (?:gr(?:ue|ü)n|rot|wieder|stabil|sauber|fehlerfrei|durch|gut)\b)|melde[nt] sich|sobald|nachdem|waiting|still running|until|as soon as)\b'
first='\b(?:ich|wir|mich|mir|uns|mein\w*|unser\w*|i|we|let me|let'"'"'s)\b'
# Passive (werden plus participle) and modal stay blocked, as does "geht (es) weiter";
# "wird" plus infinitive is a future.
passive='\b(?:wird|werden|worden)\b[^.!?;]*\b(?:ge[a-zäöüß]{2,}(?:t|en)|[a-zäöüß]+iert)\b|\b(?:muss|m(?:ue|ü)ssen|soll|sollen|kann|k(?:oe|ö)nnen|darf|d(?:ue|ü)rfen|will|wollen|is going to|are going to)\b|\bgeht (?:es )?weiter\b|\bweiter geht\b'
# A report with evidence: a past or a state plus a link, a #N or a commit hash - never a first-person act.
evidence='https?://|\]\(|(?:^|[\s(])(?:[\w.-]+/[\w.-]+)?#\d+\b|\b(?=[0-9a-f]*\d)[0-9a-f]{7,40}\b'
state='\b(?:ist|sind|war|waren|steht|stehen|stand|standen|ging|gingen|hat|haben|liegt|liegen|lag|lief|liefen|kam|kamen|is|are|was|were|has|have|had)\b|\bge[a-zäöüß]{2,}(?:t|en)\b|\b[a-z]{3,}ed\b|\b[a-zäöüß]+iert\b'
act="\bich (?:werde|${V})\b|\b${V} ich\b|\b(?:i|we)(?:['’]ll| will| am going to| are going to)\b|\blet me\b"
# Beside evidence any present first-person verb is an act, not only the ones in ${V}; a past report stays free.
aux='(?:habe|hatte|bin|war|wurde)'
evact="${act}|\bich (?!${aux}\b)[a-zäöüß]+e\b|\b(?!${aux}\b)[a-zäöüß]+e ich\b"
# A neighbouring condition frees a sequence word; a bare "laeuft" there is a state, not a wait.
nbcond="${cond//"|laufen|l(?:ae|ä)uft(?! gleich)"/}"

# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
hits_jq='
    $text
  | gsub("```[\\s\\S]*?(```|$)"; "\n")
  | [ split("\n")[] | select(test("^\\s*>") | not) ] | join("\n")
  | gsub($quote; " ")
  | [ splits("(?<=[.!?])\\s+|\\n+") | gsub("^\\s+|\\s+$"; "") | select(length > 0 and length <= 500)
      | select((test("\\?\\s*[\"'\'')\\]*_]*$") or test("\\blet me know\\b"; "i")) | not)
      | . as $full | test($neg; "i") as $wholeneg
      | splits(";\\s*|:\\s+") | {s: ., $full, $wholeneg} ]
  | . as $p
  | [ range(0; length) as $i | $p[$i] | .full as $full | .wholeneg as $wholeneg
      | (($i > 0 and ($p[$i - 1].s | test($nbcond; "i"))) or any($p[0:$i][]; .s | test($wait; "i"))) as $afterwait
      | .s | . as $s | (gsub("[*_#>\\-\\s]+"; " ") | gsub("^\\s+|\\s+$"; "")) as $t
      | select(($t | test(":$")) or ($full | test("^\\s*#")) | not)
      | select($t | test("^(?:jetzt|nun|gerade|soeben|eben|inzwischen|mittlerweile)\\s+(?:ge\\w+(?:t|en)|\\w+iert)$"; "i") | not)
      | $s
      | select(test($ann; "i"))
      | select(test($cond; "i") | not)
      | select(test($konj; "i") and (test($act; "i") | not) | not)
      | select((test($neg; "i") or ($wholeneg and test("^ich\\b"; "i"))) | not)
      | select(test($report; "i") | not)
      | select(($afterwait and (test($seq; "i") or (test($first; "i") | not)) and (test($passive; "i") and (test($first; "i") | not) | not)) | not)
      | select(test($evidence; "i") and test($state; "i") and (test($evact; "i") | not) | not)
      | gsub("^\\s+|\\s+$"; "") ]
  | .[0:3]
'
hits="$(jq -nc --arg text "$text" --arg ann "$ann" --arg cond "$cond" --arg neg "$neg" --arg report "$past_report" \
  --arg quote "$quote" --arg seq "$seq" --arg first "$first" --arg passive "$passive" \
  --arg evidence "$evidence" --arg state "$state" --arg act "$act" --arg wait "$wait" --arg konj "$konj" --arg nbcond "$nbcond" --arg evact "$evact" "$hits_jq" 2>/dev/null || true)"
hits="${hits//$'\r'/}"
[ -n "$hits" ] && [ "$hits" != "[]" ] || exit 0

# The message both ways to ask for the act use: the block of the synchronous entry, the wake of the --rewake entry.
reason="$(jq -nr --argjson h "$hits" '
  "A turn ends with a tool call, a hand-back or a question, never with an announcement "
    + "(.agents/rules/pr.md, section \"Session Traffic\"). Announced without the act: "
    + ($h | map("\"" + .[0:160] + "\"") | join(" | "))
    + " - Ankuendigung ohne Tat: tu sie jetzt mit dem Werkzeugaufruf; war es keine, beende den Zug mit dem naechsten echten Schritt oder einer Rueckfrage - nie mit einem Zeichen oder Fuelltext."
    + " Nie die Antwort wiederholen oder neu schreiben: der Mensch hat sie gelesen."' 2>/dev/null || true)"
reason="${reason//$'\r'/}"
[ -n "$reason" ] || exit 0

if [ "$mode" = rewake ]; then
  # The background entry (asyncRewake): wakes the resting session once, and only if nothing else did. It ends as soon
  # as the transcript moved on, and it logs nothing but the wake itself.
  # The log may not exist yet: the synchronous entry, started in parallel, writes the hit line;
  # it is checked at the wake.
  [ "$stop_hook_active" != true ] && [ -n "$session" ] && [ -f "$transcript" ] || exit 0
  still_unchanged() { # the conversation's last entry is still the assistant message that carried the hit
    local now
    [ -f "$transcript" ] || return 1
    now="$(tail -n 200 -- "$transcript" 2>/dev/null | grep -E '"type":"(assistant|user)"' \
      | jq -Rrs --argjson strict true "$last_text_jq" 2>/dev/null || true)"
    now="${now//[[:space:]]/}"
    [ "$now" = "$bare" ]
  }
  SECONDS=0
  while [ "$SECONDS" -lt "$rewake_wait" ]; do
    still_unchanged || exit 0
    nap=$((rewake_wait - SECONDS)); [ "$nap" -le "$rewake_poll" ] || nap="$rewake_poll"; [ "$nap" -ge 1 ] || nap=1
    sleep "$nap"
  done
  still_unchanged || exit 0
  grep -F "\"session_id\":\"$session\"" "$ann_log" 2>/dev/null | grep -F '"outcome":"pending"' | tail -n 1 \
    | grep -qF '"mode":"rewake"' || exit 0
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  ann_write --arg sid "$session" '
      [ inputs | fromjson? | objects | '"$stale_jq"' ] as $l
    | ([ $l | to_entries[] | select(.value.session_id == $sid and .value.outcome == "pending") | .key ] | last) as $k
    | ($l | if $k == null then . else .[$k].outcome = "rewoken" end)[]'
  printf '%s\n' "$reason" >&2
  exit 2
fi

if [ "$stop_hook_active" = "true" ]; then
  jq -cn '{
    systemMessage: ("The turn still ends on an announcement without the act; the Stop hook blocked "
      + "this stop once already and now lets the turn end.")
  }' || true
  exit 0
fi

# The log line: each hit with the ANN lines it matches; "mode" says whether the hit blocked or only waited for a wake.
# Returns 0 once the line is appended; logging never changes a block that was printed.
log_hit() { # mode (block | rewake)
  local lines_json line count
  [ -n "$session" ] || return 1
  lines_json="$(printf '%s\n' "${ann_lines[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))' 2>/dev/null || true)"
  [ -n "$lines_json" ] || return 1
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  line="$(jq -nc --arg sid "$session" --arg m "$1" --argjson h "$hits" --argjson pl "${lines_json//$'\r'/}" '
      { ts: (now | todate), session_id: $sid, outcome: "pending", mode: $m,
        hits: [ $h[] as $s | { s: $s[0:160], lines: [ range(0; $pl | length) as $k | select($s | test($pl[$k]; "i")) | $k + 1 ] } ] }' \
    2>/dev/null || true)"
  [ -n "$line" ] || return 1
  # One append per hit, so parallel sessions lose no line; the cap rewrites the log only once it is past 2,000.
  { [ -d "$gate_dir" ] || mkdir -p "$gate_dir"; } 2>/dev/null || return 1
  printf '%s\n' "${line%$'\r'}" >> "$ann_log" 2>/dev/null || return 1
  count="$(wc -l < "$ann_log" 2>/dev/null || echo 0)"
  [ "${count//[[:space:]]/}" -le 2000 ] 2>/dev/null || ann_write '[ inputs | fromjson? | objects ][]'
  return 0
}

# At every $learn_every-th logged hit the log is learned from, after the decision and fail-open.
maybe_learn() {
  local c=0
  { read -r c < "$ann_cnt"; } 2>/dev/null || c=0
  [[ $c =~ ^[0-9]+$ ]] || c=0
  c=$((c + 1))
  if [ "$c" -ge "$learn_every" ]; then c=0; learn; fi 2>/dev/null
  { printf '%s\n' "$c" > "$ann_cnt"; } 2>/dev/null
  return 0
}

# A resting session of an interactive terminal is woken after N seconds if nothing else woke it (the --rewake entry);
# anywhere else, or when the hit cannot be logged for that entry to find, the turn end is blocked now.
if rewake_capable && [ -n "$transcript" ] && [ -f "$transcript" ] && log_hit rewake; then
  maybe_learn
  exit 0
fi

# The hits go in as an argument: a native Windows jq cannot open the /proc/<pid>/fd path of a process substitution.
jq -cn --arg r "$reason" '{decision: "block", reason: $r, systemMessage: "Turn end blocked: an announcement without the act."}' || true
log_hit block || true
maybe_learn
exit 0
