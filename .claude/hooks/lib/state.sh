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

# Where save and restore start: after the line whose uuid the state file names, else after its line number, else
# at 1 - but never before the main thread's last compaction boundary once the restore file has no open box: what
# lies before it went through that restore. A boundary in the last 20 lines does not count, as it may be the
# compaction now running.
state_cursor() { # state file, transcript -> globals state_start, state_start_note
  local uuid="" line="" hit total cb
  state_start=1; state_start_note="no cursor: from line 1"
  total="$(wc -l < "$2" | tr -d ' ')"
  cb="$(grep -n -F '"subtype":"compact_boundary"' "$2" 2>/dev/null | grep -v -F '"isSidechain":true' | cut -d: -f1 \
    | awk -v max=$((total - 20)) '$1 <= max { b = $1 } END { print b + 0 }')" || cb=0
  [[ $cb =~ ^[0-9]+$ ]] || cb=0
  if [ -r "$1" ]; then
    # One field a line: an empty uuid stays empty (tab-separated fields collapse in read).
    { IFS= read -r uuid; IFS= read -r line; } <<< "$(jq -r '(.cursor.uuid // ""), (.cursor.line // "" | tostring)' < "$1" 2>/dev/null)" || true
    # A jq for Windows ends its lines with CR LF.
    uuid="${uuid%$'\r'}"; line="${line%$'\r'}"
    if [[ $uuid =~ ^[0-9a-fA-F-]{8,}$ ]]; then
      hit="$(grep -n -m 1 -F "\"uuid\":\"$uuid\"" "$2" 2>/dev/null)" && hit="${hit%%:*}"
      [[ $hit =~ ^[0-9]+$ ]] && { state_start=$((hit + 1)); state_start_note="cursor: after L$hit (uuid $uuid)"; }
    fi
    if [ "$state_start" -eq 1 ]; then
      if [[ $line =~ ^[0-9]+$ ]] && [ "$line" -le "$total" ]; then
        state_start=$((line + 1)); state_start_note="cursor: uuid not found, after L$line by line number"
      elif [ -n "$uuid$line" ]; then
        # A state file without a cursor (only the report's lastCut fields) is no cursor, not a lost one.
        state_start_note="cursor not found in the transcript: from line 1"
      fi
    fi
  fi
  # A restore with an open box was not worked off (a compaction came before it was read): its start holds.
  local rf="${1%.json}-restore.md" open prev
  open="$(awk '{ sub(/\r$/, "") } /^## / { s = ($0 == "## History without a carrier" || $0 == "## Carriers changed since checked"); next }
    s && /^- \[ \]/ { n++ } END { print n + 0 }' "$rf" 2>/dev/null)" || open=0
  if [[ $open =~ ^[1-9][0-9]*$ ]]; then
    prev="$(grep -m 1 '^Since the cursor: ' "$rf" 2>/dev/null)" || prev=""
    # Each start form written here: "after L<n>" begins one line on, "from L<n>," at that line.
    if [[ $prev =~ after\ (the\ compaction\ boundary\ )?L([0-9]+) ]]; then prev=$((BASH_REMATCH[2] + 1))
    elif [[ $prev =~ from\ L([0-9]+), ]]; then prev=$((BASH_REMATCH[1]))
    else prev=1; fi
    if [ "$prev" -lt "$state_start" ]; then
      state_start=$prev; state_start_note="${state_start_note%%: *}: from L$prev, where the last restore began ($open open boxes)"
    fi
  elif [ "$cb" -ge "$state_start" ]; then
    state_start=$((cb + 1)); state_start_note="${state_start_note%%: *}: after the compaction boundary L$cb"
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
# An own sentence that reports a done action - pushed, sent to a session, commented at an issue or PR - as
# {claim: ..}; state_claims holds it against the own tool calls of its turn (ww3d/playbook#621). Quoted text,
# questions, negations, future and conditions, and sentences about a third party (an auxiliary without
# "ich/wir/I/we") and received ones ("mir", "bekommen") are no claim, so a miss stays silent rather than raising a
# box on a true sentence. A session named after "von/from" is the source, not a receiver.
def unquote: ([39] | implode) as $a | gsub("(^|\\s)" + $a + "[^" + $a + "]*" + $a + "(?=[\\s.,;:!?)]|$)"; " ") | gsub("\"[^\"]*\"|„[^“”]*[“”]|“[^”]*”|`[^`]*`"; " ");
def claim_of($n; $t; $turn; $ins): . as $orig | (unquote | one) as $u | ($u | low) as $s
  | select(($u | test("\\?\\s*$")) | not)
  | select(($s | test("\\b(nicht|kein|keine|keinen|keiner|nichts|nie|not|never|nothing|no)\\b")) | not)
  | select(($s | test("\\b(wird|werde|werden|wuerde|wuerden|soll|sollen|sollte|muss|muessen|kann|koennen|will|wollen|sobald|wenn|falls|nachdem|bevor|once|if|when|after|before|should|would|must|shall|going to)\\b")) | not)
  | select(($s | test("\\b(ich|wir|i|we)\\b")) or ($s | test("\\b(hat|haben|ist|sind|has|have|is|are|was|were|wurde|wurden)\\b") | not))
  | ($s | test("\\b(alle|allen|jede[mnrs]?|everyone|everybody|all)\\b")) as $all
  | (if ($s | test("\\b(gepusht|pushed)\\b")) and ($s | test("pushed back") | not) then "push"
     elif ($s | test("\\b(kommentiert|gepostet|commented|posted)\\b")) and ($s | test("#[0-9]+|\\b(issue|issues|pr|prs|pull request|github)\\b")) then "comment"
     elif (($s | test("\\b(geschickt|gesendet|zugestellt|weitergeleitet|weitergegeben|sent|delivered|forwarded)\\b"))
           or ($all and ($s | test("\\b(bekam|bekamen|bekommen|erhielt|erhielten|erhalten|received|got)\\b"))
               and ($s | test("\\b(ich|wir|i|we)\\b") | not)))
          and (($s | test("\\b(mir|uns|me|us)\\b"))
               or (($all | not) and ($s | test("\\b(bekam|bekamen|bekommen|erhielt|erhielten|erhalten|received|got)\\b"))) | not)
       then "send"
     else empty end) as $cat
  | {claim: {l: $n, ts: $t, turn: $turn, ins: $ins, cat: $cat, all: $all, text: ($orig | one),
      names: ([$s | gsub("\\b(von|from) [a-z][a-z0-9]*(?:-[a-z0-9]+)*-[0-9]+\\b"; " ")
               | scan("\\b[a-z][a-z0-9]*(?:-[a-z0-9]+)*-[0-9]+\\b")] | unique),
      refs: ([$s | scan("#([0-9]+)") | .[0]] | unique)}};
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
def is_message($c): (.isCompactSummary != true) and ($c | test("^This session is being continued") | not) and (.origin.kind == "peer" or ($c | test("^\\[rc · from |\\[rc-delivery: |^<cross-session-message|^Another Claude session sent a message")));
def human_text($c): (.isMeta != true) and ($c | length > 0)
  and ($c | test("^\\s*<local-command-|^\\s*<command-message>|^\\s*<task-notification>|^\\s*<system-reminder>|^Caveat:|^This session is being continued") | not)
  and (.isCompactSummary != true);
reduce (inputs | (fromjson? // null) | if type == "object" then as_user else . end) as $j (
  {n: ($start - 1), out: [], tools: {}, lastq: null, openq: [], end: null, turn: 0, ins: [], claims: []};
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
              | .turn as $turn | .ins as $ins | .claims += [$ss[] | claim_of($n; $t; $turn; $ins)]
            else . end)
        elif $j.type == "user" then
          ($j.message.content // "") as $raw_c | ($raw_c | flat | slash) as $c
          | if ($raw_c | type) == "array" and ($raw_c | any(.type? == "tool_result")) then
              reduce ($raw_c[] | select(.type? == "tool_result")) as $r (.;
                if .tools[$r.tool_use_id] and ($r.is_error != true) and ($j.toolUseResult.isAsync != true) then
                  .out += [{l: $n, ts: $t, art: "helper", text: ($r.content | flat | one), full: ($r.content | flat)}]
                else . end)
            elif $j.origin.kind == "task-notification" or ($c | test("^<task-notification>")) then
              if ($c | test("<summary>Background command")) then .
              else .out += [{l: $n, ts: $t, art: "helper", text: ($c | one), full: $c}] end
            elif ($j | is_message($c)) then
              ($j | sender($c)) as $from | ($j.origin.body // $c) as $body
              | .out += [{l: $n, ts: $t, art: "message", text: ($from + ": " + ($body | one)), from: $from, full: $body}]
              | .ins += [{l: $n, from: ($from | ascii_downcase)}]
            elif ($j | human_text($c)) then
              ($c | one) as $h
              | (if .lastq then $h + " (auf: " + .lastq + ")" else $h end) as $txt
              | .lastq = null
              | (if ($h | test("\\?")) then .openq += [.out | length] else . end)
              | .out += [{l: $n, ts: $t, art: "human", text: $txt, full: $c}]
              | .turn = $n | .ins = []
            else . end
        else . end
    end) catch $before), $before))
| . as $s
| reduce $s.openq[] as $i ($s; .out[$i].art = "open-question")
| (.out[] | select(.text != "")), .claims[], {end: .end}
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
  timeout "${STATE_GH_TIMEOUT:-30}" gh api "repos/${1%%#*}/issues/${1##*#}" --jq '.body // ""' > "$2/$k.md" 2>"$2/$k.err" || rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$2/$k.err"
  elif [ "$rc" -eq 124 ]; then
    echo "gh timed out after ${STATE_GH_TIMEOUT:-30} s" > "$2/$k.err"; rm -f "$2/$k.md"
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
# Globals: state_hay_note, state_bodies (the named carriers). <folder>/refs.tsv maps each fetched file to its
# carrier ("<key><TAB>owner/repo#N", "channel<TAB>further channel").
state_haystack() { # folder, carriers... -> <folder>/<key>.md per text, <folder>/refs.tsv
  local dir="$1" c f; shift
  state_hay_note=""; state_bodies=()
  [ "$#" -eq 0 ] || printf '%s\n' "$@" | state_fetch "$dir"
  : > "$dir/refs.tsv"
  for c in "$@"; do
    f="$dir/$(state_key "$c")"
    [ -e "$f.md" ] || { echo "carrier not readable: $c ($(head -c 200 "$f.err" 2>/dev/null))" >&2; return 2; }
    state_bodies+=("$f.md"); printf '%s\t%s\n' "$(state_key "$c")" "$c" >> "$dir/refs.tsv"
  done
  for c in "$@"; do state_refs "${c%%#*}" < "$dir/$(state_key "$c").md"; done | sort -u \
    | while IFS= read -r c; do
        [[ $c =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] && [ ! -e "$dir/$(state_key "$c").md" ] && printf '%s\n' "$c"
      done > "$dir/linked.txt"
  state_fetch "$dir" < "$dir/linked.txt"
  while IFS= read -r c; do printf '%s\t%s\n' "$(state_key "$c")" "$c"; done < "$dir/linked.txt" >> "$dir/refs.tsv"
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
    printf 'channel\tfurther channel\n' >> "$dir/refs.tsv"
  else
    state_hay_note="${state_hay_note}further channel: not checked"$'\n'
  fi
}

# The candidates no carrier holds: up to six words as a whole, longer ones by at least half of their 6-word
# shingles (across line ends, as one stream). jq gives each candidate its normal form, awk holds the haystack's
# shingles in one hash (a jq object instead took far longer, ww3d/playbook docs/provenance.md). A carried
# candidate becomes a pair with the carrier line that holds it, or the most of its shingles.
# shellcheck disable=SC2016 # jq text, not shell
state_match_jq="$state_norm_jq"'select(has("art")) | .text | norm'
# shellcheck disable=SC2016 # awk text, not shell
state_match_find='
  function at(p,   lo, hi, mid) { lo = 1; hi = nl; while (lo < hi) { mid = int((lo + hi + 1) / 2); if (start[mid] <= p) lo = mid; else hi = mid - 1 }; return lo }
  BEGIN { nk = split(keys, key, " ") }
  FILENAME == ARGV[1] { sub(/\r$/, ""); hay = $0; next }
  FILENAME == ARGV[2] { sub(/\r$/, "")
    if ($0 ~ /^ ?qqsrcqq [0-9]+ ?$/) { split($0, m, " "); src = key[m[2]]; ln = 0 } else ln++
    nl++; start[nl] = pos + 2; pos += length($0) + 1; loc[nl] = src SUBSEP ln
    n = split($0, w, " ")
    for (i = 1; i <= n; i++) { r[rn % 6] = w[i]; rn++
      if (rn >= 6) { s = r[(rn - 6) % 6] " " r[(rn - 5) % 6] " " r[(rn - 4) % 6] " " r[(rn - 3) % 6] " " r[(rn - 2) % 6] " " r[(rn - 1) % 6]
                     if (!(s in set)) set[s] = loc[nl] } }
    next }
  { sub(/\r$/, ""); k = split($0, c, " "); if (k == 0) next
    if (k <= 6) { p = index(hay, " " $0 " "); if (p == 0) print "O\t" FNR; else print "P\t" FNR "\t" loc[at(p + 1)]; next }
    hit = 0; best = ""; top = 0; split("", cnt)
    for (i = 1; i + 5 <= k; i++) { s = c[i] " " c[i+1] " " c[i+2] " " c[i+3] " " c[i+4] " " c[i+5]
      if (s in set) { hit++; if (++cnt[set[s]] > top) { top = cnt[set[s]]; best = set[s] } } }
    if (hit * 2 < k - 5) print "O\t" FNR; else print "P\t" FNR "\t" best }'
state_match() { # folder, candidates file -> the unmatched candidates on stdout; the pairs in <folder>/pairs.txt
  local dir="$1" f i=0 keys=""
  jq -r "$state_match_jq" < "$2" > "$2.norm" || return 2
  # Every text once, each behind a marker line that survives the normal form, so a line maps back to its carrier.
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    i=$((i + 1)); keys="$keys $(basename "${f%.md}")"
    printf 'qqsrcqq %s\n' "$i"; cat "$f"; printf '\n'
  done > "$dir/all.raw"
  LC_ALL=C sed -e 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/Ä/ae/g; s/Ö/oe/g; s/Ü/ue/g; s/ß/ss/g' "$dir/all.raw" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9\n' ' ' | LC_ALL=C tr -s ' ' > "$dir/all.lines" || return 2
  { printf ' '; LC_ALL=C tr '\n' ' ' < "$dir/all.lines"; printf ' \n'; } > "$dir/hay.txt"
  awk -F '\t' -v keys="$keys" "$state_match_find" "$dir/hay.txt" "$dir/all.lines" "$2.norm" > "$2.hits" || return 2
  jq -c 'select(has("art"))' < "$2" | awk -F '\t' '{ sub(/\r$/, "") } NR == FNR { if ($1 == "O") keep[$2] = 1; next } FNR in keep' "$2.hits" -
  jq -r 'select(has("art")) | "L\(.l) \(.art): \(.text | gsub("[\t\r\n]"; " ") | if length > 400 then .[0:397] + "..." else . end)"' \
    < "$2" > "$2.boxes" || return 2
  awk -F '\t' -v keys="$keys" '
    function cut(s) { gsub(/[\t\r]/, " ", s); sub(/^[ ]+/, "", s); return length(s) > 400 ? substr(s, 1, 397) "..." : s }
    BEGIN { nk = split(keys, key, " ") }
    FILENAME == ARGV[1] { sub(/\r$/, ""); ref[$1] = $2; next }
    FILENAME == ARGV[2] { sub(/\r$/, ""); if ($1 == "P") { pair[$2] = $3; want[$3] = 1 }; next }
    FILENAME == ARGV[3] { if ($0 ~ /^qqsrcqq [0-9]+$/) { split($0, m, " "); src = key[m[2]]; ln = 0; next }
                          ln++; if ((src SUBSEP ln) in want) text[src SUBSEP ln] = $0; next }
    (FNR in pair) { sub(/\r$/, ""); split(pair[FNR], a, SUBSEP)
                    print $0 " => " (a[1] in ref ? ref[a[1]] : a[1]) ": " cut(text[pair[FNR]]) }' \
    "$dir/refs.tsv" "$2.hits" "$dir/all.raw" "$2.boxes" > "$dir/pairs.txt" || return 2
}

# A forge write call: gh with a writing method or subcommand, or a GitHub MCP tool that is no read.
# shellcheck disable=SC2016 # jq text, not shell
state_gh_write_jq='def gh_write: (.input | tostring) as $s
  | (((.name == "Bash" or .name == "PowerShell") and ($s | test("\\bgh\\b"))
      and ($s | test("-X ?(POST|PATCH|PUT|DELETE)|--method[ =](POST|PATCH|PUT|DELETE)| -[fF] |--field|--raw-field|--input|gh (issue|pr) (comment|edit|close|reopen|create|ready|review|merge|lock)")))
     or ((.name | test("github"; "i")) and (.name | test("get|list|search|read"; "i") | not)));
def numbered: (capture("^(?<n>[0-9]+):(?<j>.*)$") // null) as $m | select($m != null)
  | ($m.j | fromjson? // null) | objects | select(.isSidechain != true) | {l: ($m.n | tonumber), j: .};'
# The own tool calls a claim can rest on, from the whole transcript: git push, rc send/report/ask, a forge write.
# shellcheck disable=SC2016 # jq text, not shell
state_uses_jq="$state_gh_write_jq"'numbered | select(.j.type == "assistant") | .l as $l
  | .j.message.content[]? | objects | select(.type == "tool_use") | (.input | tostring) as $s
  | {id, l: $l, write: gh_write, s: $s,
     push: ((((.name == "Bash" or .name == "PowerShell") and ($s | test("\\bgit\\b[^\\n;&|]*\\bpush\\b")))) or (.name | test("push_files|create_or_update_file"))),
     rc: ((.name == "Bash" or .name == "PowerShell") and ($s | test("\\brc(\\.exe)?\\s+(send|report|ask)\\b")))}
  | select(.push or .rc or .write)'
# shellcheck disable=SC2016 # jq text, not shell
state_results_jq="$state_gh_write_jq"'def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;
  numbered | select(.j.type == "user") | .l as $l | .j.message.content | arrays | .[] | objects | select(.type == "tool_result")
  | (.content | flat) as $x
  | {id: .tool_use_id, l: $l, text: $x, ok: ((.is_error != true) and ($x | test("\\[rejected\\]|failed to push|^(fatal|error):"; "m") | not))}'
# shellcheck disable=SC2016 # jq text, not shell
state_claims_jq='($r | map({key: .id, value: .}) | from_entries) as $res
| $c[] as $k
| (reduce ($k.ins[] | select(.l < $k.l)) as $i ($k.turn; . as $w
    | if ($i.from | length) > 0
         and ([$u[] | select(.rc and .l > $w and .l < $i.l) | .s | ascii_downcase] | join(" ")
              | test("(^|[^a-z0-9-])" + ($i.from | gsub("[^a-z0-9-]"; "")) + "([^a-z0-9-]|$)"))
      then $w else $i.l end)) as $w
| [$u[] | select(.l > $w and .l < $k.l) | . as $x
   | if .exec then $x else $res[$x.id] | select(. != null and .ok and .l < $k.l) | $x + {text: .text} end] as $ev
| (if $k.cat == "push" then (if any($ev[]; .push) then empty else "no successful git push in this turn" end)
   elif $k.cat == "comment" then
     [$ev[] | select(.write)] as $w
     | if ($w | length) == 0 then "no forge write call in this turn"
       elif ($k.refs | length) > 0 and ([$k.refs[] as $n | $w[] | select(.s | test("(^|[^0-9])" + $n + "([^0-9]|$)"))] | length) == 0
         then "no forge write call naming #" + ($k.refs | join(", #")) + " in this turn"
       else empty end
   else
     ([$ev[] | select(.rc) | if .exec then .to else .text | scan("(?:dlv|msg)_[0-9A-Za-z]{10,}[ \\t]+([A-Za-z0-9_.-]+)") | .[0] end
       | ascii_downcase] | unique) as $to
     | ([$u[] | select(.rc and .l < $k.l) | .s | ascii_downcase] | join(" ")) as $addr
     | [$k.names[] | select(. as $n | $addr | test("(^|[^a-z0-9-])" + $n + "([^a-z0-9-]|$)"))] as $named
     | if ($named | length) > 0 then
         [$named[] | select(. as $n | any($to[]; . == $n) | not)] as $miss
         | if ($miss | length) > 0 then "no delivery to " + ($miss | join(", ")) + " in this turn" else empty end
       elif ($to | length) == 0 then "no delivery in this turn"
       elif $k.all then "delivered in this turn only to " + ($to | join(", ")) + "; tick it if that is everyone"
       else empty end
   end) as $why
| {l: $k.l, ts: $k.ts, art: "claim", text: ($k.text + " (no proof: " + $why + ")")}'
# A web session calls rc through a call line "<tool>-exec:v1:<key>:<n>:<mac>:<argv base64>" in a shell command
# (as the argument of ":") or alone on a line of a tool's output; its result comes later as a message, so the line
# itself stands as the delivery to the receiver its argv names.
# shellcheck disable=SC2016 # jq text, not shell
state_exec_jq="$state_gh_write_jq"'def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;
  def call: "[a-z][a-z0-9]*(?:-[a-z0-9]+)*-exec:v[0-9]+:[0-9a-f]{32}:[0-9]+:[0-9a-f]{64}:([A-Za-z0-9+/=]+)";
  numbered | .l as $l | .j
  | (if .type == "assistant" then .message.content[]? | objects | select(.type == "tool_use" and (.name == "Bash" or .name == "PowerShell"))
       | (.input.command // "" | strings) | scan("(?:^|[\\n;&|(])[ \\t]*:[ \\t]+[\u0027\"]?" + call)
     elif .type == "user" then .message.content | arrays | .[] | objects | select(.type == "tool_result")
       | (.content | flat) | scan("(?:^|\\n)(?:: \u0027)?" + call + "\u0027?[ \\t\\r]*(?=\\n|$)")
     else empty end) | .[0]
  | ((@base64d? // "") | split("\u0000") | map(select(length > 0))) as $a
  | select(($a[0] // "") | test("^(send|report|ask)$"))
  | ($a | index("--to")) as $i
  | {id: ("exec:" + ($l | tostring)), l: $l, exec: true, rc: true, push: false, write: false, s: ($a | join(" ")),
     to: (if $i != null then $a[$i + 1] // "" elif $a[0] == "send" then ([$a[1:][] | select(startswith("-") | not)][0] // "")
          else "owner" end)}'
# The claims of the candidates file without proof among the own tool calls of their turn - from the last input of the
# maintainer or another session before it, where a reply of a session addressed with rc in the turn opens none: a
# session named in the claim that the session addressed with rc needs a delivery to it (rc prints the delivery id
# before the receiver), "alle" without names lists who got one.
state_claims() { # transcript, candidates file, folder -> the claims without proof as candidates on stdout
  local t="$1" d="$3"
  jq -c 'select(has("claim")) | .claim' < "$2" > "$d/claims.jsonl" || return 2
  [ -s "$d/claims.jsonl" ] || return 0
  { grep -n -F '"type":"tool_use"' "$t" | grep -E 'push|gh|github|rc'; } > "$d/uses.txt"
  jq -R -c "$state_uses_jq" < "$d/uses.txt" > "$d/uses.jsonl" || return 2
  jq -r '.id' < "$d/uses.jsonl" | tr -d '\r' > "$d/ids.txt" || return 2
  : > "$d/results.txt"
  [ ! -s "$d/ids.txt" ] || { grep -n -F -f "$d/ids.txt" "$t" | grep -F '"tool_result"'; } > "$d/results.txt"
  jq -R -c "$state_results_jq" < "$d/results.txt" > "$d/results.jsonl" || return 2
  { grep -n -F -- '-exec:v' "$t" || true; } | jq -R -c "$state_exec_jq" >> "$d/uses.jsonl" || return 2
  jq -n -c --slurpfile c "$d/claims.jsonl" --slurpfile u "$d/uses.jsonl" --slurpfile r "$d/results.jsonl" "$state_claims_jq"
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

# --- EINLESEN (restore) -------------------------------------------------------------------------------------
# The carriers changed since checkedAt that another hand changed: one forge call per repo of the carriers
# (issues?since=), then the comments since then of each changed carrier. A change counts as the session's own
# where its time falls into one of the session's own write calls on that carrier (tool_use to tool_result, one
# second either side), told by the transcript, not the account: every session writes as the same bot.
# shellcheck disable=SC2016 # jq text, not shell
state_writes_jq='def ep: if type == "string" and length >= 19 then (.[0:19] + "Z" | fromdateiso8601) else null end;
$ARGS.positional as $refs
| [inputs | fromjson? | objects | select(.isSidechain != true)] as $e
| (reduce ($e[] | select(.type == "user") | .timestamp as $t | .message.content[]? | objects | select(.type == "tool_result") | {id: (.tool_use_id // ""), t: $t})
     as $r ({}; .[$r.id] = $r.t)) as $done
| [$e[] | select(.type == "assistant") | .timestamp as $t | .message.content[]? | objects | select(.type == "tool_use")
   | . as $u | ($u.input | tostring) as $s
   | select((($u.name == "Bash" or $u.name == "PowerShell") and ($s | test("\\bgh\\b"))
             and ($s | test("-X ?(POST|PATCH|PUT|DELETE)|--method[ =](POST|PATCH|PUT|DELETE)| -[fF] |--field|--raw-field|--input|gh (issue|pr) (comment|edit|close|reopen|create|ready|review|merge|lock)")))
            or (($u.name | test("github"; "i")) and ($u.name | test("get|list|search|read"; "i") | not)))
   | $refs[] as $c | ($c | capture("^(?<o>[^/]+)/(?<r>[^#]+)#(?<n>[0-9]+)$")) as $p
   | select(($s | contains("repos/\($p.o)/\($p.r)/issues/\($p.n)")) or ($s | contains("repos/\($p.o)/\($p.r)/pulls/\($p.n)"))
            or ($s | contains($c)) or (($s | contains("\($p.o)/\($p.r)")) and ($s | test("(^|[^0-9])\($p.n)([^0-9]|$)")))
            # A call without owner/repo writes to the checkout'"'"'s own repo ($home).
            or (($home == "\($p.o)/\($p.r)")
                and (($s | test("repos/\\{owner\\}/\\{repo\\}/(issues|pulls)/\($p.n)([^0-9]|$)"))
                     or (($s | test("gh (issue|pr) [a-z]+ #?\($p.n)([^0-9]|$)")) and ($s | test("--repo|-R ") | not))))
            or ((($u.input.owner? // "") == $p.o) and (($u.input.repo? // "") == $p.r)
                and ([$u.input.issue_number?, $u.input.pullNumber?, $u.input.pull_number?, $u.input.number?]
                     | map(select(. != null) | tostring) | index($p.n))))
   | {ref: $c, from: (($t | ep) - 1), to: ((($done[$u.id] // $t) | ep) + 1)}]'
# The checkout's own repo as owner/repo, from its origin; empty where there is none.
state_home() {
  git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null | tr -d '\r' \
    | sed -E -n 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's#\.git$##'
}
# shellcheck disable=SC2016 # jq text, not shell
state_changed_jq='def ep: if type == "string" and length >= 19 then (.[0:19] + "Z" | fromdateiso8601) else null end;
$ARGS.positional as $refs | ($w[0] // []) as $w | ($at | ep) as $since
| [$refs[] as $c | ($c | capture("^(?<o>[^/]+)/(?<r>[^#]+)#(?<n>[0-9]+)$")) as $p
   | ($issues[] | select(.repo == "\($p.o)/\($p.r)") | .items[]? | select((.number | tostring) == $p.n)) as $i
   | ([$i.updated_at] + [($comments[] | select(.ref == $c) | .items[]? | .created_at, .updated_at)]
      | map(ep) | map(select(. != null and . > $since)) | unique) as $times
   | [$times[] | select(. as $x | [$w[] | select(.ref == $c and .from <= $x and $x <= .to)] | length == 0)] as $foreign
   | select($foreign | length > 0)
   | "- [ ] \($c) changed since \($at): \($i.title // "" | gsub("[\r\n\t]"; " ")) (changes at \($foreign | map(todate) | join(", ")))"]
| .[]'
state_changed() { # folder, checkedAt (ISO), transcript, start line, carriers... -> section text on stdout
  local dir="$1" at="$2" t="$3" from="$4" c r k repos=() rc
  shift 4
  mapfile -t repos <<< "$(printf '%s\n' "$@" | sed 's/#.*//' | sort -u)"
  for r in "${repos[@]}"; do
    ( k="${r//\//_}"; rc=0
      timeout 10 gh api "repos/$r/issues?since=$at&state=all&per_page=100" > "$dir/since-$k.json" 2> "$dir/since-$k.err" || rc=$?
      [ "$rc" -eq 0 ] || { [ "$rc" -ne 124 ] || echo "timed out after 10 s" > "$dir/since-$k.err"; rm -f "$dir/since-$k.json"; } ) &
  done
  wait
  for r in "${repos[@]}"; do
    k="${r//\//_}"
    if [ -s "$dir/since-$k.json" ]; then jq -c --arg r "$r" '{repo: $r, items: (if type == "array" then . else [] end)}' "$dir/since-$k.json" 2>/dev/null
    else echo "carriers changed: not checked for $r ($(head -c 200 "$dir/since-$k.err" 2>/dev/null | tr '\r\n' '  '))" >&2; fi
  done > "$dir/issues.jsonl" 2> "$dir/changed.note"
  # The comments of each carrier the forge names as changed.
  for c in "$@"; do
    jq -e --arg r "${c%%#*}" --argjson n "${c##*#}" 'select(.repo == $r) | .items[] | select(.number == $n)' "$dir/issues.jsonl" >/dev/null 2>&1 || continue
    ( k="$(state_key "$c")"
      timeout 10 gh api "repos/${c%%#*}/issues/${c##*#}/comments?since=$at&per_page=100" > "$dir/comments-$k.json" 2>/dev/null \
        || rm -f "$dir/comments-$k.json" ) &
  done
  wait
  for c in "$@"; do
    k="$(state_key "$c")"
    [ -s "$dir/comments-$k.json" ] && jq -c --arg c "$c" '{ref: $c, items: (if type == "array" then . else [] end)}' "$dir/comments-$k.json" 2>/dev/null
  done > "$dir/comments.jsonl"
  tail -n "+$from" "$t" 2>/dev/null | jq -nRc --arg home "$(state_home)" --args "$state_writes_jq" "$@" 2>/dev/null > "$dir/writes.json" || echo '[]' > "$dir/writes.json"
  cat "$dir/changed.note"
  jq -nr --arg at "$at" --slurpfile w "$dir/writes.json" --slurpfile issues "$dir/issues.jsonl" \
    --slurpfile comments "$dir/comments.jsonl" --args "$state_changed_jq" "$@" 2>/dev/null
}
