# shellcheck shell=bash
# shellcheck disable=SC2034 # state_* globals are the results session-state.sh reads
# Sourced by session-state.sh, never run: the core of SICHERN (save) - what a session said, was told and
# promised since its cursor, held against the texts of its carriers (ww3d/playbook#487, decision log
# docs/decisions/2026-11-12T0458Z-playbook-487-save-restore-decisions.md, decisions 2-4).
#
# Needs bash, jq and gh; no model call. Every function reports a read error on stderr and returns 2.

# The normal form both sides of the comparison take: lower case, umlauts written out, every run of
# anything but a-z and 0-9 one blank. The haystack goes through sed and tr (fast on megabytes); a candidate
# through state_norm_jq, which must give the same result.
state_norm_sh() {
  LC_ALL=C sed -e 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/Ä/ae/g; s/Ö/oe/g; s/Ü/ue/g; s/ß/ss/g' \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' ' ' | LC_ALL=C tr -s ' '
}
# shellcheck disable=SC2016 # jq text, not shell
state_norm_jq='def norm: gsub("[äÄ]"; "ae") | gsub("[öÖ]"; "oe") | gsub("[üÜ]"; "ue") | gsub("ß"; "ss")
  | ascii_downcase | gsub("[^a-z0-9]+"; " ") | ltrimstr(" ") | rtrimstr(" ");'

# The transcript of the session: the given path, else <session>.jsonl under the projects folder.
state_transcript() { # given path, session -> global state_tx
  state_tx="$1"
  if [ -z "$state_tx" ]; then
    local f
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$2".jsonl; do
      [ -r "$f" ] && { state_tx="$f"; break; }
    done
  fi
  if [ -z "$state_tx" ] || [ ! -r "$state_tx" ]; then
    echo "transcript not readable: ${state_tx:-no <session>.jsonl under ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}" >&2; return 2
  fi
}

# Where save starts: after the line whose uuid the state file names, else after its line number, else at 1.
state_cursor() { # state file, transcript -> globals state_start, state_start_note
  local uuid="" line="" hit total
  state_start=1; state_start_note="no cursor: from line 1"
  [ -r "$1" ] || return 0
  # One field a line: an empty uuid stays empty (tab-separated fields collapse in read).
  { IFS= read -r uuid; IFS= read -r line; } <<< "$(jq -r '(.cursor.uuid // ""), (.cursor.line // "" | tostring)' < "$1" 2>/dev/null)" || true
  # A jq for Windows ends its lines with CR LF.
  uuid="${uuid%$'\r'}"; line="${line%$'\r'}"
  if [[ $uuid =~ ^[0-9a-fA-F-]{8,}$ ]]; then
    hit="$(grep -n -m 1 -F "\"uuid\":\"$uuid\"" "$2" 2>/dev/null)" && hit="${hit%%:*}"
    if [[ $hit =~ ^[0-9]+$ ]]; then
      state_start=$((hit + 1)); state_start_note="cursor: after L$hit (uuid $uuid)"; return 0
    fi
  fi
  total="$(wc -l < "$2" | tr -d ' ')"
  if [[ $line =~ ^[0-9]+$ ]] && [ "$line" -le "$total" ]; then
    state_start=$((line + 1)); state_start_note="cursor: uuid not found, after L$line by line number"
  else
    state_start_note="cursor not found in the transcript: from line 1"
  fi
}

# One jq pass over the transcript from the start line: the candidates as JSON lines, and last a line
# {"end":..} with the last line that carries a uuid. Side threads (isSidechain) are skipped.
# shellcheck disable=SC2016 # jq text, not shell
state_extract_jq='
def ts: (.timestamp // "") | if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}") then .[0:10] + "T" + .[11:13] + .[14:16] + "Z" else "-" end;
def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;
def one: gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");
# A slash command the maintainer typed is an input like any other: "/<name> <args>".
def slash: if test("<command-name>") then
    ([capture("<command-name>(?<n>[^<]*)</command-name>").n] | first // "") + " "
    + ([capture("<command-args>(?<a>[^<]*)</command-args>").a] | first // "") | one
  else . end;
def sentences: one | [splits("(?<=[.!?])\\s+")] | map(select(length > 0));
def low: ascii_downcase | gsub("ä"; "ae") | gsub("ö"; "oe") | gsub("ü"; "ue") | gsub("ß"; "ss");
def kind_of: low as $s
  | if test("\\?\\s*$") then "question"
    elif ($s | test("\\b(doch nicht|nehme [^.]*zurueck|zurueckgezogen|widerrufe?n?|stattdessen|statt dessen|nicht mehr)\\b")) then "revoke"
    elif ($s | test("\\b(entschieden|entscheide|entscheidung|beschlossen|wir nehmen|ich nehme|bleibt bei|decided|going with)\\b")) then "decision"
    elif ($s | test("\\b(erledigt|fertig|gemergt|gemerged|gepusht|geschlossen|abgehakt|eingetragen|nachgetragen|behoben|gefixt|steht jetzt|ist drin|done|merged|pushed|fixed|closed)\\b")) then "done"
    elif ($s | test("\\b(ich|wir) [a-z]+(e|en)\\b|\\bbescheid\\b|\\b(i|we)(.ll| will| am going to)\\b|\\b(als naechstes|danach|sobald|vorschlag|empfehlung|schlage vor|next step)\\b|^(mache|baue|melde|pruefe|trage|raeume|starte|schicke|schreibe|hole|setze) ")) then "promise"
    else empty end;
def sender($c): (.origin.name // "") as $n | (.origin.from // "") as $f
  | if $n != "" then $n
    elif $f != "" and $f != "unknown" and ($f | test("^uds:") | not) then $f
    else ($c | capture("from-name=\"(?<n>[^\"]+)\"").n
      // capture("\\[rc · from (?<n>[^ ·\\]]+)").n
      // capture("\\[rc-delivery: (?<n>[A-Za-z0-9_]+)").n
      // ($c | one | split(" ") | map(select(length > 0)) | .[0] // "-" | rtrimstr(":"))) end;
# A message or input that arrives while a turn runs stands as an attachment "queued_command": read it as the
# user line it is. Fields read below are objects or null from here on: a "?" that yields nothing would empty
# the whole reduce step (a failed tool call carries toolUseResult as a string).
def obj: if type == "object" then . else null end;
def origin_obj: if type == "string" then (fromjson? // null) else . end | obj;
def as_user: (.attachment | obj) as $a
  | if .type == "attachment" and ($a.type // null) == "queued_command" then
      {type: "user", uuid, timestamp, isSidechain, isMeta: $a.isMeta,
       origin: ($a.origin | origin_obj), message: {content: $a.prompt}}
    else .origin |= origin_obj | .toolUseResult |= obj end;
def is_message($c): (.isCompactSummary != true) and (.origin.kind == "peer" or ($c | test("^\\[rc · from |\\[rc-delivery: |^<cross-session-message|^Another Claude session sent a message")));
def human_text($c): (.isMeta != true) and ($c | length > 0)
  and ($c | test("^\\s*<local-command-|^\\s*<command-message>|^\\s*<task-notification>|^Caveat:|^This session is being continued") | not)
  and (.isCompactSummary != true);
reduce (inputs | (fromjson? // null) | if type == "object" then as_user else . end) as $j (
  {n: ($start - 1), out: [], tools: {}, lastq: null, openq: [], end: null};
  .n += 1
  # A line of a shape no branch expects is skipped, never the end of the run: the step falls back to the
  # state before it.
  | . as $before
  | first((try (if $j == null or ($j | type) != "object" or $j.isSidechain == true then .
    else
      .n as $n | ($j | ts) as $t
      | (if ($j.uuid // "") != "" then .end = {line: $n, uuid: $j.uuid} else . end)
      | if $j.type == "assistant" then
          reduce (($j.message.content // []) | if type == "array" then .[] | objects else empty end) as $b (.;
            if $b.type == "tool_use" and (["Agent", "Task", "Workflow"] | index($b.name)) then .tools[$b.id] = true
            elif $b.type == "text" then
              ($b.text | sentences) as $ss
              | .openq = []
              | .lastq as $prev | .lastq = (([$ss[] | select(test("\\?\\s*$"))] | last) // $prev)
              | reduce ($ss[] | {s: ., k: kind_of}) as $c (.; .out += [{l: $n, ts: $t, art: $c.k, text: $c.s}])
            else . end)
        elif $j.type == "user" then
          ($j.message.content // "") as $raw_c | ($raw_c | flat | slash) as $c
          | if ($raw_c | type) == "array" and ($raw_c | any(.type? == "tool_result")) then
              reduce ($raw_c[] | select(.type? == "tool_result")) as $r (.;
                if .tools[$r.tool_use_id] and ($r.is_error != true) and ($j.toolUseResult.isAsync != true) then
                  .out += [{l: $n, ts: $t, art: "helper", text: ($r.content | flat | one)}]
                else . end)
            elif $j.origin.kind == "task-notification" or ($c | test("^<task-notification>")) then
              if ($c | test("<summary>Background command")) then .
              else .out += [{l: $n, ts: $t, art: "helper", text: ($c | one)}] end
            elif ($j | is_message($c)) then
              .out += [{l: $n, ts: $t, art: "message", text: (($j | sender($c)) + ": " + (($j.origin.body // $c) | one))}]
            elif ($j | human_text($c)) then
              ($c | one) as $h
              | (if .lastq then $h + " (auf: " + .lastq + ")" else $h end) as $txt
              | .lastq = null
              | (if ($h | test("\\?")) then .openq += [.out | length] else . end)
              | .out += [{l: $n, ts: $t, art: "human", text: $txt}]
            else . end
        else . end
    end) catch $before), $before))
| . as $s
| reduce $s.openq[] as $i ($s; .out[$i].art = "open-question")
| (.out[] | select(.text != "")), {end: .end}
'

state_extract() { # transcript, start line -> candidates as JSON lines on stdout
  tail -n "+$2" "$1" | jq -R -n -c --argjson start "$2" "$state_extract_jq"
}

# The haystack: the bodies of the named carriers, of every issue or PR they link (one level), and the text
# of PLAYBOOK_CARRIER_TEXT_CMD. Bodies are fetched in parallel, each once.
state_key() { # owner/repo#N -> owner_repo_N
  local k="${1//\//_}"; printf '%s' "${k/\#/_}"
}
state_body() { # owner/repo#N, folder -> the body in <folder>/<key>.md, an error text in <folder>/<key>.err
  local k; k="$(state_key "$1")"
  local rc=0
  timeout 30 gh api "repos/${1%%#*}/issues/${1##*#}" --jq '.body // ""' > "$2/$k.md" 2>"$2/$k.err" || rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$2/$k.err"
  elif [ "$rc" -eq 124 ]; then
    echo "gh timed out after 30 s" > "$2/$k.err"; rm -f "$2/$k.md"
  else
    [ -s "$2/$k.err" ] || echo "gh exit $rc" > "$2/$k.err"
    rm -f "$2/$k.md"
  fi
}
# Eight at a time (ww3d/playbook docs/provenance.md: all at once was several times slower).
state_fetch() { # folder < owner/repo#N per line
  export -f state_body state_key
  # shellcheck disable=SC2016 # $1 and $2 belong to the inner bash
  [ "$#" -eq 1 ] && xargs -r -P 8 -I{} bash -c 'state_body "$1" "$2"' _ {} "$1"
}
state_refs() { # default repo < body -> owner/repo#N per line
  grep -oE 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|(^|[^A-Za-z0-9_/&])#[0-9]+' \
    | sed -E -e 's#github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+)#\1/\2\#\4#' -e "s@^[^A-Za-z0-9_.#-]?#([0-9]+)\$@$1#\\1@" -e 's@^[^A-Za-z0-9_.-]@@'
}
# Globals: state_hay_note, state_bodies (the named carriers).
state_haystack() { # folder, carriers... -> <folder>/hay.txt normalised
  local dir="$1" c f; shift
  state_hay_note=""; state_bodies=()
  [ "$#" -eq 0 ] || printf '%s\n' "$@" | state_fetch "$dir"
  for c in "$@"; do
    f="$dir/$(state_key "$c")"
    [ -e "$f.md" ] || { echo "carrier not readable: $c ($(head -c 200 "$f.err" 2>/dev/null))" >&2; return 2; }
    state_bodies+=("$f.md")
  done
  for c in "$@"; do state_refs "${c%%#*}" < "$dir/$(state_key "$c").md"; done | sort -u \
    | while IFS= read -r c; do
        [[ $c =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] && [ ! -e "$dir/$(state_key "$c").md" ] && printf '%s\n' "$c"
      done | state_fetch "$dir"
  for f in "$dir"/*.err; do
    [ -e "$f" ] && state_hay_note="${state_hay_note}linked not read: $(basename "${f%.err}") ($(head -c 120 "$f"))"$'\n'
  done
  if [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then
    local rc=0
    timeout 60 bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ text > "$dir/channel.md" 2>"$dir/channel.err" || rc=$?
    if [ "$rc" -eq 124 ]; then
      state_hay_note="${state_hay_note}further channel: not checked (PLAYBOOK_CARRIER_TEXT_CMD timed out after 60 s)"$'\n'
      : > "$dir/channel.md"
    elif [ "$rc" -ne 0 ]; then
      state_hay_note="${state_hay_note}further channel: not checked (PLAYBOOK_CARRIER_TEXT_CMD failed: $(head -c 200 "$dir/channel.err"))"$'\n'
      : > "$dir/channel.md"
    fi
  else
    state_hay_note="${state_hay_note}further channel: not checked"$'\n'
  fi
  { printf ' '; cat "$dir"/*.md 2>/dev/null | state_norm_sh; printf ' '; } > "$dir/hay.txt"
}

# The candidates no carrier holds: up to six words as a whole, longer ones by at least half of their 6-word
# shingles. jq gives each candidate its normal form, awk holds the haystack's shingles in one hash (a jq
# object instead took far longer, ww3d/playbook docs/provenance.md).
# shellcheck disable=SC2016 # jq text, not shell
state_match_jq="$state_norm_jq"'select(has("art")) | .text | norm'
state_match() { # haystack file, candidates file -> the unmatched candidates
  jq -r "$state_match_jq" < "$2" > "$2.norm" || return 2
  # A jq for Windows ends its lines with CR LF; both inputs drop it.
  awk '{ sub(/\r$/, "") }
       NR == FNR { hay = $0; n = split($0, w, " ")
                   for (i = 1; i + 5 <= n; i++) set[w[i] " " w[i+1] " " w[i+2] " " w[i+3] " " w[i+4] " " w[i+5]] = 1
                   next }
       { k = split($0, c, " "); if (k == 0) next
         if (k <= 6) { if (index(hay, " " $0 " ") == 0) print FNR; next }
         hit = 0; for (i = 1; i + 5 <= k; i++) if ((c[i] " " c[i+1] " " c[i+2] " " c[i+3] " " c[i+4] " " c[i+5]) in set) hit++
         if (hit * 2 < k - 5) print FNR }' "$1" "$2.norm" > "$2.open" || return 2
  jq -c 'select(has("art"))' < "$2" | awk '{ sub(/\r$/, "") } NR == FNR { keep[$1] = 1; next } FNR in keep' "$2.open" -
}

# The work list: open boxes "- [ ] L<line> <UTC> <art>: <text>"; a box of the previous list ticked
# "- [x] <the whole box text> -> <proof>" stays ticked; unanswered questions of the maintainer first.
state_worklist() { # unmatched candidates file, old list, new list -> global state_open
  local old="$2" new="$3" line box rest proof='^ -> *[^[:space:]]'
  local -a ticks=()
  if [ -r "$old" ]; then
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ $line == "- [x] "* ]] && ticks+=("${line#- \[x\] }")
    done < "$old"
  fi
  # One box a line: a tab or newline in the text becomes a space.
  jq -r -s 'sort_by(if .art == "open-question" then 0 else 1 end, .l)[]
    | "L\(.l) \(.ts) \(.art): \(.text | gsub("[\t\r\n]"; " ") | if length > 400 then .[0:397] + "..." else . end)"' \
    < "$1" > "$new.box" || return 2
  while IFS= read -r box; do
    box="${box%$'\r'}"; line="- [ ] $box"
    for rest in "${ticks[@]}"; do
      # Ticked only with the whole box text, then " -> " and a proof that is not blank.
      [[ ${rest:0:${#box}} == "$box" && ${rest:${#box}} =~ $proof ]] && { line="- [x] $rest"; break; }
    done
    printf '%s\n' "$line"
  done < "$new.box" > "$new"
  rm -f "$new.box"
  state_open="$(grep -c '^- \[ \]' "$new")" || state_open=0
}

# Boxes under "## Open points" of a named carrier that run over 600 characters or append history outside
# quotes: a warning each, the exit stays.
state_open_point_warnings() { # body files...
  local f
  for f in "$@"; do
    awk -v src="$(basename "${f%.md}")" '
      function flush() { if (box != "") { t = box; gsub(/"[^"]*"|„[^“]*“|`[^`]*`/, "", t)
          if (length(box) > 600) print "warning: " src " open point over 600 characters: " substr(box, 1, 80)
          else if (t ~ /(^|[^A-Za-z])(Stand|Nachtrag|nachgetragen|Rest aus)([^A-Za-z]|$)/) print "warning: " src " open point appends history: " substr(box, 1, 80) }
        box = "" }
      /^## / { flush(); inside = ($0 ~ /^## Open points/); next }
      !inside { next }
      /^[[:space:]]*>/ { next }
      /^- \[ \]/ { flush(); box = $0; next }
      /^- \[x\]/ { flush(); next }
      /^[[:space:]]+[^[:space:]]/ { if (box != "") box = box " " $0; next }
      { flush() }
      END { flush() }' "$f"
  done
}
