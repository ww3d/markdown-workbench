# shellcheck shell=bash
# shellcheck disable=SC2034 # cut_* globals are read by session-state.sh
# Sourced by session-state.sh, never run: the report after each cut (ww3d/playbook#487, decision log
# docs/decisions/2026-11-12T2316Z-playbook-487-meldung-decisions.md, decisions 24-30). One JSON line per compaction
# of the main thread with what only the session's hooks know - saved before, boxes at the restore, lock denials,
# seconds and tokens until free - to <project>/.agent/state/cuts.jsonl and to PLAYBOOK_CARRIER_TEXT_CMD report.
# It never blocks: `alarm` is a field and nothing else.
#
# The marker <gate>/<session>-cut-pending (restore-compact-state.sh) holds "key=value" lines: cut, at, from (the
# transcript's line count at the hook - the main thread's boundary is written only after it), transcript, restore,
# need=<name> per need of the lock, stopHolds (require-receipt.sh counts its holds).

cut_gate="${TMPDIR:-/tmp}/claude-rule-gate"
cut_now() { TZ=UTC0 printf -v cut_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1; } # the time now in cut_ts, no process
cut_epoch() { date -u -d "$1" +%s 2>/dev/null; } # ISO time -> seconds, empty where unreadable

# The main thread's boundaries, from one grep over the transcript: arrays cut_bl (line), cut_bb (byte offset of the
# line), cut_bu (uuid), cut_bt (timestamp). Reads start at a byte offset, so a long transcript costs no extra pass.
cut_index() { # transcript
  cut_bl=(); cut_bb=(); cut_bu=(); cut_bt=()
  local l b u t
  while read -r l b u t; do
    [[ $l =~ ^[0-9]+$ ]] || continue
    cut_bl+=("$l"); cut_bb+=("$b"); cut_bu+=("$u"); cut_bt+=("$t")
  done <<< "$(grep -n -b -F '"subtype":"compact_boundary"' "$1" 2>/dev/null | grep -v -F '"isSidechain":true' \
    | awk -F: '{ u = "-"; t = "-"
        if (match($0, /"uuid":"[^"]*"/)) u = substr($0, RSTART + 8, RLENGTH - 9)
        if (match($0, /"timestamp":"[^"]*"/)) t = substr($0, RSTART + 13, RLENGTH - 14)
        print $1, $2, u, t }')"
}

# One pass from a boundary to the end of the transcript, one line per main boundary in it. Per window (boundary to
# the next): tokens once per message.id up to $cutoff (the last entry of an id carries the full output), lock
# denials, whether a turn saw the third, the restore hook's trace; in replay also the save before the boundary (a
# `session-state.sh save` call whose result printed its check line) and the version of the newest read receipt up
# to 40 lines after it. live: the boundary $muuid is the marker's (extras in $mk), the others from line $minLine on
# are silent cuts unless the restore hook's trace follows them; saved means checkedAt between the boundary before and
# this one.
# shellcheck disable=SC2016 # jq text, not shell
cut_scan_jq='def flat: if type == "string" then . elif type == "array" then [.[] | objects | (.text? // (.content? | flat)) // ""] | join("\n") else "" end;
def flat1: if type == "string" then . elif type == "array" then [.[] | objects | .text? // ""] | join("\n") else "" end;
def t19: (. // "")[0:19];
def tokens: [.[]] | {input: (map(.input_tokens // 0) | add // 0), cacheWrite: (map(.cache_creation_input_tokens // 0) | add // 0),
  cacheRead: (map(.cache_read_input_tokens // 0) | add // 0), output: (map(.output_tokens // 0) | add // 0)};
def line($s; $prevAt):
  ($mode == "live" and $muuid != "" and $s.uuid == $muuid) as $m
  | if $mode == "live" and ($m | not) and $s.line < $minLine then empty else
    (if $mode == "replay" then $s.saved != null
     else $checked != "" and $s.at != null and ($checked | t19) < ($s.at | t19) and ($prevAt == "" or ($checked | t19) > ($prevAt | t19)) end) as $saved
    | (if $mode == "replay" then (if $saved then $s.line - $s.saved else null end)
       elif $saved and $cursor != null then $s.line - $cursor else null end) as $gap
    | (if $m or $s.restore then "ran" else "none" end) as $hook
    | (if $m then $mk.free else "" end) as $free
    | ($free != "" and $s.at != null) as $timed
    | {v: 1, at: $now, playbookVersion: (if $mode == "replay" then $s.ver else $ver end | if . == "" then null else . end),
       repo: (if $mode == "replay" or $repo == "" then null else $repo end), session: $session, kind: $kind, place: $place,
       cut: "compact", boundaryUuid: $s.uuid, boundaryAt: $s.at, freeAt: (if $free == "" then null else $free end),
       trigger: $s.trigger, preTokens: $s.preTokens, postTokens: $s.postTokens, saved: $saved, cursorGap: $gap,
       boxes: (if $m then $mk.boxes else null end),
       lock: {denials: $s.denials, valve: $s.valve, stopHolds: (if $m then $mk.holds else 0 end), needs: (if $m then $mk.needs else {} end)},
       secondsToFree: (if $timed then ($free | t19 + "Z" | fromdate) - ($s.at | t19 + "Z" | fromdate) else null end),
       tokens: (if $timed then ($s.ids | tokens) else null end), hook: $hook, done: (if $m then $mk.done else false end),
       alarm: ((if $saved then [] else ["not-saved"] end) + (if $hook == "none" then ["silent-cut"] else [] end)
         + (if $s.valve then ["valve"] else [] end)),
       notChecked: (if $m then $mk.nc else ["restore"] end)}
    | if $mode == "replay" then . + {cwd: $s.cwd} else . end
  end;
reduce inputs as $raw ({n: ($start - 1), cur: null, prevAt: $prevAt, out: [], tool: {}, saved: null, ver: ""};
  .n += 1
  | (if $mode == "replay" and .cur and .cur.since <= 40 then .cur.since += 1 else . end)
  | (if $mode == "replay" and ($raw | contains("| Core")) then
       ([$raw | match("Playbook ([0-9][0-9A-Za-z.+-]*) \\| Core"; "g") | .captures[0].string] | last) as $v
       | if $v then .ver = $v | (if .cur and .cur.since <= 40 then .cur.ver = $v else . end) else . end
     else . end)
  # Only the lines that can count are parsed: boundaries, denials, the restore trace, usage in the timed window,
  # and in replay the save calls and their results.
  | (.cur.timed // false) as $timed
  | if ($raw | contains("compact_boundary") or contains("After the compaction this session is locked") or contains("Restore written")
         or contains("Compact state restored") or ($timed and contains("\"usage\"")) or ($mode == "replay" and (contains("session-state.sh") or contains("cursor:")))) | not
    then . else
    ($raw | fromjson? // null) as $e
    | if ($e | type) != "object" or $e.isSidechain == true then .
      elif $e.type == "system" and $e.subtype == "compact_boundary" then
        (if .cur then .out += [line(.cur; .prevAt)] | .prevAt = (.cur.at // "") else . end)
        | .cur = {line: .n, uuid: ($e.uuid // null), at: ($e.timestamp // null), trigger: ($e.compactMetadata.trigger // null),
            preTokens: ($e.compactMetadata.preTokens // null), postTokens: ($e.compactMetadata.postTokens // null),
            cwd: ($e.cwd // null), ids: {}, denials: 0, valve: false, restore: false, saved: .saved, ver: .ver, since: 0,
            timed: ($mode == "live" and $muuid != "" and ($e.uuid // "") == $muuid)}
        | .saved = null | .ver = ""
      else
        (if .cur and ($cutoff == "" or ($e.timestamp | t19) <= ($cutoff | t19)) then
           (if $timed and $e.type == "assistant" and ($e.message.id | type) == "string" and ($e.message.usage | type) == "object"
              then .cur.ids[$e.message.id] = $e.message.usage else . end)
           | (if $raw | contains("After the compaction this session is locked") then
                # A denial is an error result that starts with the lock text; a quote of it (a grep) is none.
                ([$e.message.content? | arrays | .[] | objects | select(.type == "tool_result" and .is_error == true) | .content | flat
                  | select(test("^(PreToolUse:[A-Za-z_]+ hook error: )?After the compaction this session is locked"))]) as $d
                | .cur.denials += ($d | length) | .cur.valve = (.cur.valve or ($d | any(test("denial 3 of 3"))))
              else . end)
           # The restore hook line: "Restore written" since ww3d/playbook#620, "Compact state restored" before it.
           | (if $e.type == "attachment" and (($e.attachment.hookName? // "") | startswith("SessionStart"))
                and ($raw | contains("Restore written") or contains("Compact state restored")) then .cur.restore = true else . end)
         else . end)
        | if $mode != "replay" then .
          elif $e.type == "assistant" and ($raw | contains("session-state.sh")) then
            reduce ($e.message.content? | arrays | .[] | objects | select(.type == "tool_use")
              | select((.input.command? // "" | tostring) | test("session-state\\.sh\"?\\s+save"))) as $u (.; .tool[$u.id] = true)
          elif $e.type == "user" and ($raw | contains("cursor:")) then
            . as $acc
            | reduce ($e.message.content? | arrays | .[] | objects | select(.type == "tool_result" and .is_error != true)
                | select($acc.tool[.tool_use_id // ""] == true)) as $r (.;
                ([$r.content | flat1 | match("checked: [0-9TZ-]+ · cursor: .* L([0-9]+)") | .captures[0].string] | last) as $l
                | if $l then .saved = ($l | tonumber) else . end)
          else . end
      end
    end)
| (if .cur then .out += [line(.cur; .prevAt)] else . end) | .out[]'

# Where the session runs: web in a cloud session, local otherwise.
cut_where() { cut_place=local; [ "${CLAUDE_CODE_REMOTE:-}" != true ] || cut_place=web; }

# A line without jq: what the marker's existence says, everything else not checked. The session id is checked by its
# caller ([A-Za-z0-9_-]+), so it needs no escaping.
cut_bare() { # session, done -> one JSON line on stdout
  cut_where
  printf '{"v":1,"at":"%s","session":"%s","place":"%s","cut":"compact","hook":"ran","done":%s,"alarm":[],"notChecked":["jq"],"sent":false}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$cut_place" "$2"
}

# The project's facts for every line: version, repo, kind, place.
cut_facts() { # project root, session -> globals cut_version, cut_repo, cut_kind, cut_place
  local root="$1" f url m
  cut_version=""
  m="$(cat "$root/.agents/manifest.json" 2>/dev/null)" || m=""
  [[ $m =~ \"playbookVersion\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && cut_version="${BASH_REMATCH[1]//[[:space:]]/}"
  [ -n "$cut_version" ] || for f in .playbook-version VERSION; do
    [ -f "$root/$f" ] || continue
    IFS= read -r cut_version < "$root/$f" || true; cut_version="${cut_version//[[:space:]]/}"; break
  done
  cut_repo=""
  url="$(git -C "$root" remote get-url origin 2>/dev/null)" || url=""
  url="${url%$'\r'}"
  [[ $url =~ (://[^/]+/|^[^/@:]+@[^:]+:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]] && cut_repo="${BASH_REMATCH[2]%.git}"
  cut_kind_of "$2"
  cut_where
  return 0
}

# The boxes of the restore file, per section: open, carried (a proof after the last "->" naming owner/repo#N, #N or a
# link), struck (any other tick). The box text itself may carry "->" and links.
cut_boxes() { # restore file -> JSON on stdout
  awk '{ sub(/\r$/, "") }
    /^## / { s = ($0 == "## History without a carrier") ? "history" : ($0 == "## Carriers changed since checked") ? "changed" : ""; next }
    s == "" { next }
    /^- \[ \]/ { o[s]++ }
    /^- \[[xX]\]/ { p = $0; f = 0; while ((i = index(p, "->")) > 0) { p = substr(p, i + 2); f = 1 }
      if (f && p ~ /#[0-9]+|https:\/\//) c[s]++; else x[s]++ }
    END { printf "{\"history\":{\"open\":%d,\"carried\":%d,\"struck\":%d},\"changed\":{\"open\":%d,\"carried\":%d,\"struck\":%d}}\n",
      o["history"], c["history"], x["history"], o["changed"], c["changed"], x["changed"] }' "$1"
}

# The seconds from the boundary until each need of the lock was read in full (its read marker's time).
cut_needs() { # marker, boundary ISO, session -> JSON on stdout
  local k n s be m out=""
  be="$(cut_epoch "$2")"
  while IFS= read -r k || [ -n "$k" ]; do
    case "$k" in need=*) ;; *) continue ;; esac
    n="${k#need=}"; n="${n%$'\r'}"; [[ $n =~ ^[A-Za-z0-9._-]+$ ]] || continue
    s=null
    if [ -n "$be" ] && m="$(date -r "$cut_gate/$3-read-main-$n" +%s 2>/dev/null)" && [ "$m" -ge "$be" ]; then s=$((m - be)); fi
    out+="${out:+,}\"$n\":$s"
  done < "$1"
  printf '{%s}\n' "$out"
}
cut_marker_get() { # marker, key -> the value of its last "key=" line
  local l v=""
  while IFS= read -r l || [ -n "$l" ]; do [[ $l == "$2="* ]] && v="${l#*=}"; done < "$1" 2>/dev/null
  printf '%s' "${v%$'\r'}"
}

# Known token shapes masked, the same expression as restore-compact-state.sh.
cut_mask() {
  sed -E -e 's/(gh[pousr]_)[A-Za-z0-9]{20,}/\1[masked]/g' -e 's/github_pat_[A-Za-z0-9_]{20,}/github_pat_[masked]/g' \
    -e 's/(sk-(ant-)?)[A-Za-z0-9_-]{20,}/\1[masked]/g' -e 's/(xox[abprs]-)[A-Za-z0-9-]{10,}/\1[masked]/g' \
    -e 's/AKIA[0-9A-Z]{16}/AKIA[masked]/g' -e 's/(glpat-)[A-Za-z0-9_-]{20,}/\1[masked]/g' \
    -e 's/([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[A-Za-z0-9._~+\/=-]{20,}/\1[masked]/g'
}

# Appends lines to the local file, each with sent false, unless one with the same session and boundary stands there.
cut_append() { # cuts file, lines (one JSON object a line)
  [ -n "$2" ] || return 0
  local -A seen=()
  local l k s u ch=false keep=""
  if [ -r "$1" ]; then
    while IFS= read -r k; do [ -z "$k" ] || seen["$k"]=1; done <<< "$(awk '{ s = ""; u = ""
        if (match($0, /"session":"[^"]*"/)) s = substr($0, RSTART + 11, RLENGTH - 12)
        if (match($0, /"boundaryUuid":"[^"]*"/)) u = substr($0, RSTART + 16, RLENGTH - 17)
        if (u != "") print s " " u }' "$1" 2>/dev/null)"
  fi
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    s=""; u=""
    [[ $l =~ \"session\":\"([^\"]*)\" ]] && s="${BASH_REMATCH[1]}"
    [[ $l =~ \"boundaryUuid\":\"([^\"]*)\" ]] && u="${BASH_REMATCH[1]}"
    if [ -n "$u" ]; then [ -z "${seen["$s $u"]:-}" ] || continue; seen["$s $u"]=1; fi
    keep+="$l"$'\n'
  done <<< "$2"
  [ -n "$keep" ] || return 0
  [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ] || ch=true
  printf '%s' "$keep" | jq -c --argjson ch "$ch" '. + {sent: false} | if $ch then .notChecked = ((.notChecked // []) + ["channel"] | unique) else . end' \
    | tr -d '\r' | cut_mask >> "$1"
}

# Tenths of a second since this library was loaded; PLAYBOOK_CUT_CLOCK replaces the clock (a command printing tenths).
cut_t0="${EPOCHREALTIME/[.,]/}"
cut_clock() {
  local t
  if [ -n "${PLAYBOOK_CUT_CLOCK:-}" ]; then t="$(bash -c "$PLAYBOOK_CUT_CLOCK" 2>/dev/null | tr -d '\r')"; [[ $t =~ ^[0-9]+$ ]] || t=0
  else t="${EPOCHREALTIME/[.,]/}"; t=$(( (t - cut_t0) / 100000 )); fi
  printf '%s\n' "$t"
}

# Sends every local line with sent false to the further channel and marks the ones it took; the receiver tells a
# repeat by session + boundaryUuid. After each send it took, the file is read again and only that line is marked;
# each send has at most 3 s, and
# no send starts or runs past 8 s after the report began, inside its 10 s; the first failed send ends the sending
# for this run, the rest waits for the next.
cut_send() { # cuts file
  [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ] && [ -r "$1" ] || return 0
  grep -q -F '"sent":false' "$1" 2>/dev/null || return 0
  local tmp="$1.tmp.$$" out q i j left lines=() fresh=()
  mapfile -t lines < "$1"; lines=("${lines[@]%$'\r'}")
  printf -v q '%q' "$tmp"
  # shellcheck disable=SC2064 # the path expands now, quoted by %q: the local is gone when an EXIT trap runs
  { trap "rm -f -- $q" EXIT; trap "rm -f -- $q; exit 143" TERM INT; }
  for i in "${!lines[@]}"; do
    [[ ${lines[i]} == *'"sent":false'* ]] || continue
    left=$(( 80 - $(cut_clock) )); [ "$left" -gt 0 ] || break; [ "$left" -le 30 ] || left=30
    out="$(jq -c 'del(.sent) | .notChecked -= ["channel"]' <<< "${lines[i]}" | tr -d '\r')"
    # shellcheck disable=SC2016 # $@ belongs to the inner bash
    if [ -z "$out" ] || ! timeout "$((left / 10)).$((left % 10))" bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ report "$out" >/dev/null 2>&1; then
      break
    fi
    out="$(jq -c '. + {sent: true}' <<< "$out" | tr -d '\r')"
    # The file as it stands now, with what another report appended meanwhile; only the sent line changes.
    mapfile -t fresh < "$1"; fresh=("${fresh[@]%$'\r'}")
    for j in "${!fresh[@]}"; do [ "${fresh[j]}" != "${lines[i]}" ] || { fresh[j]="$out"; break; }; done
    if ! printf '%s\n' "${fresh[@]}" > "$tmp" || ! mv -f "$tmp" "$1" 2>/dev/null; then
      rm -f "$tmp"; break
    fi
  done
  trap - EXIT TERM INT
}

# A line without the transcript: what the marker and the project say, the rest not checked.
cut_unreadable() { # session, done
  cut_now; jq -n -c --arg at "$cut_ts" --arg s "$1" --arg ver "${cut_version:-}" --arg repo "${cut_repo:-}" --arg kind "${cut_kind:-unknown}" \
    --arg place "${cut_place:-local}" --argjson "done" "$2" '{v: 1, at: $at, playbookVersion: (if $ver == "" then null else $ver end),
    repo: (if $repo == "" then null else $repo end), session: $s, kind: $kind, place: $place, cut: "compact",
    boundaryUuid: null, boundaryAt: null, freeAt: null, hook: "ran", done: $done, alarm: ["transcript-unreadable"],
    notChecked: ["silent-cuts", "transcript"]}' | tr -d '\r'
}

# The session's kind as remind-before-compact.sh wrote it (third field of its state).
cut_kind_of() { # session -> global cut_kind, unknown where none stands
  local _a _b k=""
  [ ! -r "$cut_gate/$1-remind-state" ] || read -r _a _b k _ < "$cut_gate/$1-remind-state" 2>/dev/null || true
  cut_kind=unknown; [[ ! $k =~ ^[a-z]+$ ]] || cut_kind="$k"
}

# The marker's line (done true with freeAt now; undone: false) and every main boundary since the last reported one
# without a line (hook none), from one pass over the transcript; then lastCutUuid/lastCutLine in the state
# file, then the channel. Needs jq.
cut_report() { # mode (done|undone|scan), transcript, session, state file, cuts file
  local mode="$1" tx="$2" session="$3" state="$4" cuts="$5" marker="$cut_gate/$3-cut-pending"
  local free="" d=false u="" c="" ca="" k n s mi=-1 b start mk=null nc
  command -v jq >/dev/null 2>&1 || return 2
  cut_now; [ "$mode" != "done" ] || { free="$cut_ts"; d=true; }
  if [ -z "$tx" ] || [ ! -r "$tx" ]; then
    [ "$mode" = scan ] || [ ! -r "$marker" ] || cut_append "$cuts" "$(cut_unreadable "$session" "$d")"
    cut_send "$cuts"
    return 0
  fi
  cut_index "$tx"; n=${#cut_bl[@]}
  [ ! -r "$state" ] || { IFS= read -r u; IFS= read -r c; IFS= read -r ca; } \
    <<< "$(jq -r '(.lastCutUuid // ""), (.cursor.line // "" | tostring), (.checkedAt // "")' "$state" 2>/dev/null | tr -d '\r')" || true
  # Silent cuts: after the last reported boundary, else after the cursor, else from the first.
  s=-1
  if [ -n "$u" ]; then for k in "${!cut_bu[@]}"; do [ "${cut_bu[$k]}" != "$u" ] || s=$((k + 1)); done; fi
  local reported=$(( s < 0 ? 0 : s )) # boundaries before this index are reported already
  if [ "$s" -lt 0 ]; then
    s=0
    if [[ $c =~ ^[0-9]+$ ]]; then s=$n; for k in "${!cut_bl[@]}"; do [ "${cut_bl[$k]}" -le "$c" ] || { s=$k; break; }; done; fi
  fi
  if [ "$mode" != scan ] && [ -r "$marker" ]; then
    # The marker's boundary: the first main one not reported yet, after its line count `from` (20 lines of slack)
    # and not older than the marker. The hook runs before the harness writes and stamps the boundary (held by the
    # test `marker: an older boundary is not its own`), so a boundary before `at` is an earlier cut.
    b="$(cut_marker_get "$marker" from)"; [[ $b =~ ^[0-9]+$ ]] || b=0; b=$((b > 20 ? b - 19 : 1))
    local mat; mat="$(cut_marker_get "$marker" at)"; mat="${mat:0:19}"
    for k in "${!cut_bl[@]}"; do
      if [ "$k" -ge "$reported" ] && [ "${cut_bl[$k]}" -ge "$b" ] && { [ -z "$mat" ] || [[ ! ${cut_bt[$k]:0:19} < $mat ]]; }; then mi=$k; break; fi
    done
    if [ "$mi" -ge 0 ]; then
      local rf h=0 boxes=null needs
      rf="$(cut_marker_get "$marker" restore)"; h="$(cut_marker_get "$marker" stopHolds)"; [[ $h =~ ^[0-9]+$ ]] || h=0
      needs="$(cut_needs "$marker" "${cut_bt[$mi]}" "$session")"
      nc='[]'; if [ -n "$rf" ] && [ -r "$rf" ]; then boxes="$(cut_boxes "$rf")"; else nc='["restore"]'; fi
      mk="{\"free\":\"$free\",\"done\":$d,\"boxes\":$boxes,\"holds\":$h,\"needs\":$needs,\"nc\":$nc}"
    else
      cut_append "$cuts" "$(cut_unreadable "$session" "$d" | jq -c '.alarm = [] | .notChecked = ["boundary"]' | tr -d '\r')"
    fi
  fi
  start=$s; [ "$mi" -lt 0 ] || [ "$mi" -ge "$start" ] || start=$mi
  if [ "$start" -lt "$n" ]; then
    local min=$(( s < n ? cut_bl[s] : cut_bl[n - 1] + 1 )) prev="" muuid="" cursor=null
    [ "$mi" -lt 0 ] || muuid="${cut_bu[$mi]}"; [[ ! $c =~ ^[0-9]+$ ]] || cursor=$c
    [ "$start" -eq 0 ] || prev="${cut_bt[$((start - 1))]}"
    # The range goes through a file: a pipe into a native jq for Windows costs ten times the read.
    local out part="$cuts.part.$$" q
    # The part is the unmasked transcript: it goes on every way out, the TERM of `timeout 10` included.
    printf -v q '%q' "$part"
    # shellcheck disable=SC2064 # the path expands now, quoted by %q: the local is gone when an EXIT trap runs
    { trap "rm -f -- $q" EXIT; trap "rm -f -- $q; exit 143" TERM INT; }
    tail -c +$((cut_bb[start] + 1)) "$tx" > "$part" 2>/dev/null || { rm -f "$part"; trap - EXIT TERM INT; return 2; }
    out="$(jq -R -n -c --arg mode live --argjson start "${cut_bl[$start]}" \
      --arg prevAt "$prev" --argjson minLine "$min" --arg muuid "$muuid" --argjson mk "$mk" \
      --arg checked "$ca" --argjson cursor "$cursor" --arg cutoff "$free" \
      --arg ver "${cut_version:-}" --arg repo "${cut_repo:-}" --arg session "$session" --arg kind "${cut_kind:-unknown}" \
      --arg place "${cut_place:-local}" --arg now "$cut_ts" "$cut_scan_jq" "$part" | tr -d '\r')" || { rm -f "$part"; trap - EXIT TERM INT; return 2; }
    rm -f "$part"; trap - EXIT TERM INT
    cut_append "$cuts" "$out"
    if [ "${cut_bu[$((n - 1))]}" != "$u" ]; then
      local cur='{}'; [ ! -r "$state" ] || cur="$(< "$state")"
      if jq -c --arg u "${cut_bu[$((n - 1))]}" --argjson l "${cut_bl[$((n - 1))]}" \
        '. + {lastCutUuid: $u, lastCutLine: $l}' <<< "$cur" > "$state.tmp" 2>/dev/null; then mv -f "$state.tmp" "$state"; fi
    fi
  fi
  cut_send "$cuts"
  return 0
}

# Replay: one line per main boundary of each transcript, from the transcript alone in one pass; nothing written.
cut_replay() { # transcripts...
  local tx s out cwd map
  cut_where
  for tx in "$@"; do
    [ -r "$tx" ] || { echo "transcript not readable: $tx" >&2; continue; }
    s="${tx##*/}"; s="${s%.jsonl}"; cut_kind_of "$s"; cut_now
    out="$(jq -R -n -c --arg mode replay --argjson start 1 --arg prevAt "" --argjson minLine 0 --arg muuid "" --argjson mk null \
      --arg checked "" --argjson cursor null --arg cutoff "" --arg ver "" --arg repo "" --arg session "$s" \
      --arg kind "$cut_kind" --arg place "${cut_place:-local}" --arg now "$cut_ts" "$cut_scan_jq" < "$tx" | tr -d '\r')" \
      || { echo "transcript not read: $tx" >&2; continue; }
    [ -n "$out" ] || continue
    # The repo of each working directory the session ran in.
    map='{}'
    while IFS= read -r cwd; do
      if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then continue; fi
      cut_facts "$cwd" "$s"
      [ -z "$cut_repo" ] || map="$(jq -c --arg k "$cwd" --arg v "$cut_repo" '. + {($k): $v}' <<< "$map" | tr -d '\r')"
    done <<< "$(jq -r '.cwd // empty' <<< "$out" | tr -d '\r' | sort -u)"
    jq -c --argjson map "$map" '.repo = ($map[.cwd // ""] // null) | del(.cwd)' <<< "$out" | tr -d '\r'
  done
}
