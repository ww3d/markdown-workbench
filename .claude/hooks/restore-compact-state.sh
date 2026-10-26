#!/usr/bin/env bash
#
# SessionStart hook (matcher "compact") - writes what a compaction summary can lose into a file
# and points the session at it. Generic, byte-identical across consumers.
#
# The summary of a compaction shortens; the maintainer's wording, the start order and the step are
# what it drops first. This hook reads the transcript - which keeps every line across compactions -
# and writes, verbatim and only for the part since the previous compaction:
#
#   ${TMPDIR:-/tmp}/claude-rule-gate/<session>-compact-restore.md
#     Start order           the file PLAYBOOK_START_ORDER_FILE names, else the maintainer's first input
#     Messages              of other sessions, with their sender, newest first
#     The maintainer        every input, newest first
#     Own answers           the text blocks of every turn the maintainer started, newest first
#     Step, todos           the last skill call or slash command; the last todo state
#     Rule files            the list save-compact-state.sh saved plus every standing rule file
#                           (chat.md, local/*.md), read or not, to read again - not their content
#     Loss check            the inputs whose key words the summary lacks
#
# The part runs from the previous compact_boundary to the line count save-compact-state.sh saved
# (without a save: to the newest boundary); the save is used once and then removed. A hint under
# 2,000 characters goes into the context - above 10,000 the context gets a 2,000-character preview
# only, so the content goes to the file -, and one visible line says that the state was restored;
# nothing blocks. Each section that grows with the session keeps its newest entries up to a
# character budget, so the file stays bounded; what is left out is counted there. The hint says to
# read the file in parts where it is too large for one read.
#
# jq reads the transcript, at most 20 s where `timeout` exists; without jq, or when it fails, the
# file carries the start order from the variable's file and the rule list, and the hint says what
# is missing. Known token shapes are masked in the file. Whatever goes wrong, the hook exits 0.
#
# Stdin:  the SessionStart event JSON. Stdout: the hook's JSON output.
set -uo pipefail

if [ -S /dev/stdin ]; then input="$(cat)" || true; else input="$(</dev/stdin)" || true; fi

field() { # key -> global val, the first string value of "key" in the raw payload
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  val=""
  if [[ $input =~ $re ]]; then val="${BASH_REMATCH[1]}"; fi
}

# The same expression as in save-compact-state.sh.
mask() {
  sed -E \
    -e 's/(gh[pousr]_)[A-Za-z0-9]{20,}/\1[masked]/g' \
    -e 's/github_pat_[A-Za-z0-9_]{20,}/github_pat_[masked]/g' \
    -e 's/(sk-(ant-)?)[A-Za-z0-9_-]{20,}/\1[masked]/g' \
    -e 's/(xox[abprs]-)[A-Za-z0-9-]{10,}/\1[masked]/g' \
    -e 's/AKIA[0-9A-Z]{16}/AKIA[masked]/g' \
    -e 's/(glpat-)[A-Za-z0-9_-]{20,}/\1[masked]/g' \
    -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[A-Za-z0-9._~+\/=-]{20,}/\1[masked]/g'
}
esc() { # JSON string body: other control characters dropped, then backslash, quote, \n \r \t
  local s
  s="$(printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037')"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

field session_id; session="$val"
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
field transcript_path; transcript="${val//\\\\//}"

gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
{ [ -d "$gate_dir" ] || mkdir -p "$gate_dir"; } 2>/dev/null || exit 0
restore="${gate_dir}/${session}-compact-restore.md"
tmp="${restore}.tmp"

# The save belongs to this compaction only: a stale one would cut the part at an older line.
saved=-1; rules=""; save_file="${gate_dir}/${session}-compact-rules"
if [ -r "$save_file" ]; then
  saved=0
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in lines=*) [[ ${l#lines=} =~ ^[0-9]+$ ]] && saved="${l#lines=}" ;; "") ;; *) rules="$rules$l"$'\n' ;; esac
  done < "$save_file"
  rm -f "$save_file" 2>/dev/null
fi

# Standing rules bind without a tool action, so no gate asks for them: listed whether read or not.
root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then field cwd; root="${val//\\\\//}"; fi
root="${root%/}"
if [ -n "$root" ]; then
  for f in "$root/.agents/rules/chat.md" "$root"/.agents/rules/local/*.md; do
    [ -f "$f" ] || continue
    rel="${f#"$root"/}"
    case $'\n'"$rules" in *$'\n'"$rel"$'\n'*) ;; *) rules="$rules$rel"$'\n' ;; esac
  done
fi

order_file="${PLAYBOOK_START_ORDER_FILE:-}"
# Only an absolute path counts, as in the XDG base directories: a relative one depends on the cwd.
if [[ $order_file =~ ^(/|[A-Za-z]:[\\/]) ]] && [ -r "$order_file" ]; then
  order_arg=(--rawfile order "$order_file") # a file, not an argument: the command line has a length cap
else
  order_file=""; order_arg=(--arg order "")
fi
limit=(); if command -v timeout >/dev/null 2>&1; then limit=(timeout 20); fi

stamp="$(date -u +%Y-%m-%dT%H%MZ 2>/dev/null)" || stamp=""

# The transcript part since the previous compaction, as the restore file's body. Line 1 of the
# output is the loss check, the rest the file.
read -r -d '' program <<'JQ'
def ctext:
  if (.message.content | type) == "string" then .message.content
  elif (.message.content | type) == "array" then [.message.content[] | select(.type? == "text") | .text] | join("\n")
  else "" end;
def is_result: (.message.content | type) == "array" and any(.message.content[]; .type? == "tool_result");
def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n")
  elif . == null then "" else tostring end;
def peer_text: test("^(Another Claude session sent a message:|<cross-session-message)");
def command: # a slash command as "/name args", else null
  (ctext) as $t
  | ([$t | match("<command-name>([^<]*)</command-name>") | .captures[0].string] | first) as $n
  | if $n == null then null
    else ([$t | match("<command-args>([\\s\\S]*?)</command-args>") | .captures[0].string] | first // "") as $a
    | ($n | if startswith("/") then . else "/" + . end) + (if $a == "" then "" else " " + $a end) end;
# One input of the session: {kind: human|peer|other, text, ts}, or null for anything else.
def input_of:
  . as $x
  | (if .type == "user" and (.isMeta | not) and (.isCompactSummary | not) and (.isSidechain | not) and (is_result | not) then
       (ctext) as $t | (.origin.kind? // "") as $k | (command) as $cmd
       | if $cmd != null then
           if ($cmd | test("^/(compact|clear|model|config|context|cost|status|help|resume|rewind|permissions|hooks|memory|login|logout|exit)\\b"))
           then null else {kind: "human", text: $cmd} end
         elif $k == "peer" or ($t | peer_text) then {kind: "peer", text: $t}
         elif $k == "human" then {kind: "human", text: $t}
         elif $k != "" or $t == "" or ($t | test("^\\s*(<|\\[SYSTEM NOTIFICATION|Caveat:)")) then {kind: "other", text: $t}
         else {kind: "human", text: $t} end
     elif .type == "attachment" and .attachment.type? == "queued_command" then
       (.attachment.prompt | flat) as $t | (.attachment.origin.kind? // "") as $k
       | if $k == "peer" or ($t | peer_text) then {kind: "peer", text: $t}
         elif $k == "human" or ($k == "" and ($t | test("^\\s*<") | not)) then {kind: "human", text: $t}
         else {kind: "other", text: $t} end
     else null end)
  | if . == null then null else . + {ts: ($x.timestamp // "")} end;
def dedup: reduce .[] as $i ([]; if any(.[]; .text == $i.text) then . else . + [$i] end);
def keys_of: ascii_downcase | [scan("[\\p{L}\\p{N}_]{5,}")] | unique;
def oneline($n): gsub("\\s+"; " ") | if length > $n then .[0:$n - 3] + "..." else . end;
# Newest first in, the newest entries that fit $n characters out (the first one cut to fit), plus a count line.
def budget($n):
  (reduce .[] as $s ({out: [], len: 0, left: 0};
     if .left == 0 and .len + ($s | length) <= $n then .out += [$s] | .len += ($s | length)
     elif .left == 0 and (.out | length) == 0 then .out += [$s[0:$n] + " [cut at \($n) characters]"] | .len = $n
     else .left += 1 end))
  | .out + (if .left > 0 then ["_\(.left) older entries left out to keep this file bounded; the transcript holds them._"] else [] end);
def block($h): if length == 0 then "_none_" else join("\n\n") end | "## " + $h + "\n\n" + .;

[inputs | (fromjson? // null)] as $e
| ($e | length) as $len
| [$e[] | if . == null then null else input_of end] as $ins
| [range(0; $len) | select($e[.].type? == "system" and $e[.].subtype? == "compact_boundary")] as $b
# $stop, not $end: jq 1.6 takes `end` for the keyword.
| (if $saved > 0 and ([$b[] | select(. >= $saved)] | length) <= 1 then [$saved, $len] | min
   elif ($b | length) > 0 then
     # The newest boundary may not be written yet: real work after it means the hook runs first.
     $b[-1] as $lb
     | if any(range($lb + 1; $len);
            ($e[.].type? == "assistant" and ($e[.].isSidechain | not)) or $ins[.].kind? == "human")
       then $len else $lb end
   else $len end) as $stop
# Parenthesized: jq before 1.8 binds `as` to the last term only, so `X + 1 as $v` adds a string and fails.
| ((([$b[] | select(. < $stop)] | last) // -1) + 1) as $start
| ([$e[$stop:][] | select(. != null and .isCompactSummary == true) | ctext] | first // "") as $summary
| [$ins[$start:$stop][] | select(. != null)] as $inputs
| ([$inputs[] | select(.kind == "human")] | dedup) as $humans
| ([$inputs[] | select(.kind == "peer")] | dedup) as $peers
# own answers: the text blocks of every turn the maintainer started, also one begun before $start
| ((first(range($start - 1; -1; -1) | $ins[.] | select(. != null)) // {}) | .kind == "human") as $open
| (reduce range($start; $stop) as $k ({inh: $open, turns: (if $open then [[]] else [] end)};
     $ins[$k] as $i | $e[$k] as $x
     | if $i != null then (if $i.kind == "human" then .inh = true | .turns += [[]] else .inh = false end)
       elif $x != null and $x.type == "assistant" and ($x.isSidechain | not) and .inh then
         ([$x.message.content[]? | select(.type? == "text") | .text] | join("\n")) as $t
         | if $t == "" then . else .turns[(.turns | length) - 1] += [$t] end
       else . end)
   | [.turns[] | select(length > 0) | join("\n\n")]) as $answers
| ($order | if . != "" then {src: "the start order file", text: .}
   else (first($ins[] | select(. != null and .kind == "human")) // null) as $f
   | if $f == null then {src: "none found", text: ""} else {src: "the maintainer's first input", text: $f.text} end end) as $start_order
| ((first(range($stop - 1; -1; -1) as $k
     | ([$e[$k] | select(. != null and .type == "assistant") | .message.content[]?
         | select(.type? == "tool_use" and .name == "Skill")
         | "skill " + (.input.skill // "?" | tostring) + (if (.input.args // "") != "" then " " + (.input.args | tostring) else "" end)]
        + [$ins[$k] | select(. != null and .kind == "human" and (.text | startswith("/"))) | .text])
     | last // empty) // "none found") | oneline(500)) as $step
| ([$e[0:$stop][] | select(. != null and .type == "assistant") | .message.content[]?
    | select(.type? == "tool_use" and (.name == "TodoWrite" or .name == "TaskCreate" or .name == "TaskUpdate"))] as $tu
   | if ($tu | length) == 0 then []
     elif ($tu | last | .name) == "TodoWrite" then [($tu | last | .input.todos // [])[] | "- [\(.status // "?")] \(.content // .subject // "")"]
     else (reduce ($e[0:$stop][] | select(. != null and .type == "user") | .message.content[]? | select(.type? == "tool_result"))
             as $r ({}; .[$r.tool_use_id // ""] = ($r.content | flat))) as $res
       | (reduce $tu[] as $u ({};
            if $u.name == "TaskCreate" then
              ([($res[$u.id // ""] // "") | match("Task #([0-9]+)") | .captures[0].string] | first) as $n
              | if $n == null then . else .[$n] = {s: ($u.input.subject // ""), st: "pending"} end
            elif $u.name == "TaskUpdate" and ($u.input.taskId // null) != null then
              ($u.input.taskId | tostring) as $n
              | .[$n] = ((.[$n] // {s: "", st: "pending"}) | .st = ($u.input.status // .st) | .s = ($u.input.subject // .s))
            else . end))
          | to_entries | map(select(.value.st != "deleted")) | sort_by(.key | tonumber? // 0)
          | map("- [\(.value.st)] #\(.key) \(.value.s)") end) as $todos
| ($summary | ascii_downcase) as $sum
| [$humans[] | .text as $t | ($t | keys_of) as $k | select(($k | length) > 0)
   | select(([$k[] | select(. as $w | $sum | contains($w))] | length) * 2 < ($k | length))
   | $t | oneline(120)] as $lost
| (if $summary == "" then "Loss check: no compaction summary found in the transcript."
   elif ($lost | length) == 0 then "Loss check: every input of the maintainer since the previous compaction has its key words in the summary."
   else "Missing from the summary (\($lost | length)): " + ($lost | map("\"" + . + "\"") | join(" | ")) end) as $loss
| $loss,
  ([ "# Compact state" + (if $stamp != "" then " - " + $stamp else "" end),
     "Written by restore-compact-state.sh after the compaction: verbatim, and only what is new since the previous compaction. It comes before the summary.",
     ("## Start order\n\nSource: " + $start_order.src + "\n\n"
      + (if $start_order.text == "" then "_none_" else [$start_order.text] | budget(24000) | join("\n\n") end)),
     ([$peers | reverse[] | "### " + ([.text | match("from[ =]\"?([A-Za-z0-9_.@-]+)") | .captures[0].string] | first // "unknown")
        + (if .ts != "" then " - " + .ts else "" end) + "\n\n" + .text] | budget(12000) | block("Messages of other sessions (newest first)")),
     ([$humans | reverse[] | (if .ts != "" then "### " + .ts + "\n\n" else "" end) + .text] | budget(24000)
        | block("The maintainer's inputs (newest first)")),
     ([$answers | reverse[]] | budget(16000) | block("Own answers to the maintainer (newest first)")),
     ("## Step\n\n" + $step),
     ($todos | if length == 0 then "_none_" else budget(4000) | join("\n") end | "## Todos\n\n" + .),
     ("## Rule files to reread\n\n" + ($rules
        | if . != "" then "The read record ended with the compaction; read each file again in full before its next use.\n\n"
            + (split("\n") | map(select(. != "") | "- " + .) | join("\n"))
            + (if $saved < 0 then "\n\n_no save found: the PreCompact hook did not run; the standing rule files only_" else "" end)
          elif $saved < 0 then "_no save found: the PreCompact hook did not run_"
          else "_none: no rule file was read before the compaction_" end)),
     ("## Loss check\n\n" + (if $summary == "" or ($lost | length) == 0 then $loss
        else "Missing from the summary (\($lost | length), newest first):\n\n"
          + ([$lost | reverse[] | "- \"" + . + "\""] | budget(6000) | join("\n")) end)) ] | join("\n\n"))
JQ

# The jq output goes through a file: bash pattern substitution on a string of megabytes is quadratic.
loss=""; note=""
if command -v jq >/dev/null 2>&1 && [ -n "$transcript" ] && [ -r "$transcript" ] \
   && ${limit[@]+"${limit[@]}"} jq -nRr --argjson saved "$saved" "${order_arg[@]}" --arg rules "$rules" \
        --arg stamp "$stamp" "$program" < "$transcript" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
  loss="$(head -n 1 "$tmp" | tr -d '\r')" # jq on Windows ends its lines with CRLF
  tail -n +2 "$tmp" | tr -d '\r' | mask > "$restore" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; exit 0; }
else
  if ! command -v jq >/dev/null 2>&1; then note="jq is missing, so the transcript was not read"
  elif [ -z "$transcript" ] || [ ! -r "$transcript" ]; then note="the transcript was not found"
  else note="jq could not read the transcript within 20 s"; fi
  if [ -n "$rules" ]; then
    rule_list="$(printf '%s' "$rules" | sed 's/^/- /')"
    [ "$saved" -ge 0 ] || rule_list="$rule_list

_no save found: the PreCompact hook did not run; the standing rule files only_"
  elif [ "$saved" -lt 0 ]; then rule_list="_no save found: the PreCompact hook did not run_"
  else rule_list="_none: no rule file was read before the compaction_"; fi
  order=""; src="none found"
  if [ -n "$order_file" ]; then
    order="$(head -c 24000 "$order_file" 2>/dev/null)" || order=""; src="the start order file"
    [ "$(wc -c < "$order_file" 2>/dev/null)" -le 24000 ] 2>/dev/null || order="$order [cut at 24000 bytes]"
  fi
  body="# Compact state${stamp:+ - $stamp}

Written by restore-compact-state.sh after the compaction; $note: only the start order file and the
rule list are here.

## Start order

Source: $src

${order:-_none_}

## Rule files to reread

$rule_list"
  printf '%s\n' "$body" | mask > "$restore" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; exit 0; }
fi
rm -f "$tmp" 2>/dev/null
n="$(wc -l < "$restore" 2>/dev/null | tr -d ' ')" || n="?"
shown="$restore"
if command -v cygpath >/dev/null 2>&1; then shown="$(cygpath -w "$restore" 2>/dev/null)" || shown="$restore"; fi

[ ${#loss} -le 1200 ] || loss="${loss:0:1197}..."
hint="After the compaction: read $shown ($n lines) in full with the Read tool before the next step, in parts with offset and limit where it is too large for one read. It holds verbatim what the summary can lose - the start order, messages of other sessions, the maintainer's inputs, your answers to them, the step, the todos and the rule files to read again - and it comes before the summary."
[ -z "$note" ] || hint="$hint Only partly written: $note."
[ -z "$loss" ] || hint="$hint $loss"
loss_masked="$(printf '%s' "$hint" | mask)" && hint="$loss_masked"

printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(esc "Compact state restored: $shown ($n lines)")" "$(esc "$hint")"
exit 0
