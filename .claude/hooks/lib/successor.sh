# shellcheck shell=bash
# shellcheck disable=SC2034 # rs_* globals are read by state_restore_render
# shellcheck disable=SC2154 # root, session, state_dir, state_step_jq, state_start*, cut_gate:
#   set by session-state.sh, lib/state.sh and lib/cut.sh
# Sourced by session-state.sh, never run: EINLESEN of a successor after a switch (ww3d/playbook#487, #485). The
# predecessor's check line at its carrier names its transcript, its cursor and its check time; from them the
# successor's restore file is written like the one after a compaction (lib/state.sh), plus the lock and the marker
# the hooks know from a compaction. Needs lib/state.sh and lib/cut.sh loaded, jq and gh.
# shellcheck source=SCRIPTDIR/tempdir.sh
. "${BASH_SOURCE[0]%/*}/tempdir.sh"
hook_tmpdir || true # the temp folder is made known once, a subshell inherits it

succ_check_re='checked: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z · (cursor: .* L[0-9]+( [0-9A-Fa-f-]+)?|transcript: not readable)'
# The newest check line of a carrier body: in its section "## Hand-back" where it has one, else anywhere.
succ_check_line() { # body file -> the line on stdout, nothing where none stands
  { awk '{ sub(/\r$/, "") } /^## / { s = ($0 == "## Hand-back") } s' "$1" | grep -o -E "$succ_check_re" \
    || grep -o -E "$succ_check_re" "$1"; } 2>/dev/null | tail -n 1
}

# Every check line of a carrier body with the section it stands in: "<section><TAB><line>" a line, in order.
succ_check_lines() { # body file
  local heads l n s h
  heads="$(grep -n '^## ' "$1" 2>/dev/null | tr -d '\r')"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    n="${l%%:*}"; l="${l#*:}"; s="before any section"
    while IFS= read -r h; do [ -z "$h" ] || [ "${h%%:*}" -ge "$n" ] || { s="${h#*:}"; s="${s#'## '}"; }; done <<< "$heads"
    printf '%s\t%s\n' "$s" "$l"
  done <<< "$(grep -n -o -E "$succ_check_re" "$1" 2>/dev/null | tr -d '\r')"
}

succ_id_of() { local id="${1##*[/\\]}"; id="${id%.jsonl}"; [[ $id =~ ^[A-Za-z0-9_-]+$ ]] && printf '%s' "$id"; } # path
succ_posix() { # path -> the form bash reads
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1" 2>/dev/null || printf '%s' "$1"; else printf '%s' "$1"; fi
}

# The file the starting tool leaves (.agent/succession.json): globals succ_fpred (predecessor
# name), succ_ftask, succ_fwd (the folder that holds its .agent, bash form), succ_ftxs and succ_fids (its transcripts,
# oldest first, bash form, and their session ids). Exit 2 where it is no readable file of version 1.
succ_file_read() { # path
  local raw t lines=()
  raw="$(jq -r 'select(.v == 1) | (.predecessor.name // "" | tostring), (.task // "" | tostring), (.workDir // "" | tostring),
    ((.transcripts // [])[] | strings)' "$1" 2>/dev/null | tr -d '\r')" || return 2
  [ -n "$raw" ] || return 2
  mapfile -t lines <<< "$raw"
  succ_fpred="${lines[0]}"; succ_ftask="${lines[1]}"; succ_fwd=""; succ_ftxs=(); succ_fids=()
  [ -z "${lines[2]}" ] || succ_fwd="$(succ_posix "${lines[2]}")"
  for t in "${lines[@]:3}"; do
    if [ -z "$t" ] || ! succ_id_of "$t" > /dev/null; then continue; fi
    succ_ftxs+=("$(succ_posix "$t")"); succ_fids+=("$(succ_id_of "$t")")
  done
}

# The check line that counts where the file stands: one whose transcript is one of the file's (by its session id),
# the newest in "## Hand-back", else the newest anywhere. Globals succ_cline and succ_csect ('' where none counts),
# succ_cnote (what the restore file's head says about it).
succ_check_pick() { # body file ('' none), carrier
  local s l id total=0 hb="" any="" hs="" as=""
  succ_cline=""; succ_csect=""
  if [ -n "$1" ]; then
    while IFS=$'\t' read -r s l; do
      [ -n "$l" ] || continue
      total=$((total + 1)); succ_parse "$l" || continue
      id="$(succ_id_of "$succ_tx")" || continue
      [[ " ${succ_fids[*]} " == *" $id "* ]] || continue
      any="$l"; as="$s"; [ "$s" != Hand-back ] || { hb="$l"; hs="$s"; }
    done <<< "$(succ_check_lines "$1")"
  fi
  if [ -n "$hb" ]; then succ_cline="$hb"; succ_csect="$hs"; elif [ -n "$any" ]; then succ_cline="$any"; succ_csect="$as"; fi
  if [ -n "$succ_cline" ]; then succ_cnote="Check line taken: \`$succ_cline\` (section \"$succ_csect\" of $2)."
  elif [ -z "$1" ]; then succ_cnote="No check line counts: no carrier to read it from."
  elif [ "$total" -gt 0 ]; then succ_cnote="No check line counts: none of the $total at $2 names a transcript of the predecessor (${succ_fids[*]:-none in the succession file})."
  else succ_cnote="No check line counts: none stands at $2."; fi
}

# Without a check line that counts: the predecessor's bookmark, the cursor of its last save in
# <workDir>/.agent/state/<id>.json of its newest run that has one, else its first run from line 1. Globals
# succ_from_i (the run to start in, -1 where none is readable) and succ_mark ('' where there is no bookmark).
succ_bookmark() {
  local i
  succ_from_i=-1; succ_mark=""
  for ((i = ${#succ_fids[@]} - 1; i >= 0; i--)); do
    if [ -z "$succ_fwd" ] || [ ! -r "${succ_ftxs[i]}" ]; then continue; fi
    if jq -e '(.cursor.uuid // "") != "" or (.cursor.line // null) != null' "$succ_fwd/.agent/state/${succ_fids[i]}.json" > /dev/null 2>&1; then
      succ_from_i=$i; succ_mark="$succ_fwd/.agent/state/${succ_fids[i]}.json"; return 0
    fi
  done
  for ((i = 0; i < ${#succ_ftxs[@]}; i++)); do [ -r "${succ_ftxs[i]}" ] && { succ_from_i=$i; return 0; }; done
}

# The runs read as one, from run i on: the file itself where it is one, else their lines in one file of the folder.
succ_join() { # first run, folder -> global succ_read
  local i files=()
  for ((i = $1; i < ${#succ_ftxs[@]}; i++)); do [ ! -r "${succ_ftxs[i]}" ] || files+=("${succ_ftxs[i]}"); done
  if [ ${#files[@]} -le 1 ]; then succ_read="${files[0]:-}"; return 0; fi
  succ_read="${files[0]}"
  if cat "${files[@]}" > "$2/predecessor.jsonl" 2>/dev/null; then succ_read="$2/predecessor.jsonl"; fi
  succ_joined=" (its runs read as one: ${files[*]})"
}

# The predecessor's check line parsed into globals succ_checked (YYYY-MM-DDTHHMMZ), succ_checked_at (ISO),
# succ_tx (its transcript path), succ_line, succ_uuid; succ_tx stays empty where the line says it was not readable.
succ_parse() { # check line
  succ_checked=""; succ_checked_at=""; succ_tx=""; succ_line=""; succ_uuid=""
  [[ $1 =~ ^checked:\ ([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2})Z ]] || return 1
  succ_checked="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}${BASH_REMATCH[3]}Z"
  succ_checked_at="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:00Z"
  if [[ $1 =~ \ ·\ cursor:\ (.*)\ L([0-9]+)(\ ([0-9A-Fa-f-]+))?$ ]]; then
    succ_tx="${BASH_REMATCH[1]}"; succ_line="${BASH_REMATCH[2]}"; succ_uuid="${BASH_REMATCH[4]}"
  fi
}

# The predecessor's transcript: the path of the check line, else <id>.jsonl under this machine's projects folder,
# the id being the path's file name. Sets succ_read (the readable path) or succ_why (why none).
succ_find_tx() {
  local id f
  succ_read=""; succ_why=""
  if [ -z "$succ_tx" ]; then succ_why="the predecessor's check line says its transcript was not readable"; return 0; fi
  if [ -r "$succ_tx" ]; then succ_read="$succ_tx"; return 0; fi
  id="${succ_tx##*[/\\]}"; id="${id%.jsonl}"
  if [[ $id =~ ^[A-Za-z0-9_-]+$ ]]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$id".jsonl; do [ -r "$f" ] && { succ_read="$f"; return 0; }; done
  fi
  succ_why="the predecessor's transcript $succ_tx is not on this machine (another machine or a cloud session)"
}

# The folder the predecessor's transcript names as its cwd, bash form: nothing where it names none.
succ_pred_cwd() {
  local cwd
  cwd="$(jq -r 'select(.cwd != null) | .cwd' "$succ_read" 2>/dev/null | head -n 1 | tr -d '\r')"
  ! command -v cygpath >/dev/null 2>&1 || [ -z "$cwd" ] || cwd="$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")"
  printf '%s' "$cwd"
}

# The predecessor's last list of a cut (ww3d/playbook#727): in the clone its transcript names as cwd, under its
# session. Globals out: succ_plist (its side list, '' where none is readable), succ_pnote (why not).
succ_pred_list() {
  local id cwd d v i
  succ_plist=""; succ_pnote=""
  if [ -n "${succ_file:-}" ]; then
    # With the succession file: its folder, the newest run that left a list.
    for ((i = ${#succ_fids[@]} - 1; i >= 0; i--)); do
      d="$succ_fwd/.agent/state/ticks/${succ_fids[i]}"; v="$(cutlist_latest_in "$d")"
      if [ -n "$succ_fwd" ] && [ -n "$v" ] && [ -r "$(ticks_side "$v")" ]; then succ_plist="$(ticks_side "$v")"; return 0; fi
    done
    succ_pnote="the predecessor's list was not read: no list under ${succ_fwd:-(no workDir)}/.agent/state/ticks for ${succ_fids[*]:-its runs}"
    return 0
  fi
  id="${succ_tx##*[/\\]}"; id="${id%.jsonl}"
  if [ -z "$succ_read" ] || ! [[ $id =~ ^[A-Za-z0-9_-]+$ ]]; then succ_pnote="the predecessor's list was not read: its transcript was not read"; return 0; fi
  cwd="$(succ_pred_cwd)"
  d="$cwd/.agent/state/ticks/$id"; v="$(cutlist_latest_in "$d")"
  if [ -n "$cwd" ] && [ -n "$v" ] && [ -r "$(ticks_side "$v")" ]; then succ_plist="$(ticks_side "$v")"
  else succ_pnote="the predecessor's list was not read: no list in ${cwd:+$d}${cwd:-a folder its transcript names}"; fi
}

# The line of succ_read up to which reports counted its unexamined sentences already (ww3d/playbook#727): the furthest
# uuid of the marks the predecessor's saves with open boxes and compactions left in its clone, and of an earlier restore
# of the predecessor or of this session; 0 without one. By uuid, as runs read as one count their lines anew.
succ_counted() { # -> the line on stdout
  local m u l max=0 i cwd id dirs=()
  m="$(state_unexamined_mark "$state_dir" "$session")"; dirs=("${m%/*}")
  if [ -n "${succ_file:-}" ]; then
    for i in ${succ_fids[@]+"${succ_fids[@]}"}; do
      [ -z "$succ_fwd" ] || { m="$(state_unexamined_mark "$succ_fwd/.agent/state" "$i")"; dirs+=("${m%/*}"); }
    done
  else
    cwd="$(succ_pred_cwd)"
    if [ -n "$cwd" ] && id="$(succ_id_of "$succ_tx")"; then m="$(state_unexamined_mark "$cwd/.agent/state" "$id")"; dirs+=("${m%/*}"); fi
  fi
  for i in "${dirs[@]}"; do
    for m in "$i/unexamined.json" "$i/restored.json"; do
      [ -r "$m" ] || continue
      u="$(jq -r '.uuid // empty' "$m" 2>/dev/null | tr -d '\r')"; [ -n "$u" ] || continue
      l="$(grep -n -F "\"uuid\":\"$u\"" "$succ_read" | tail -n 1 | cut -d: -f1)"
      [ -z "$l" ] || [ "$l" -le "$max" ] || max=$l
    done
  done
  printf '%s' "$max"
}

# Writes <state>/<session>-restore.md for the successor, then the lock and the marker. Globals in: session, root,
# state_dir, state_tx (the successor's own transcript, may be empty), win() not needed: paths go as they are.
# With the succession file, after the check line that counts is parsed: what is read and from where. Globals
# succ_read, succ_hs (the session id of the first run read), succ_cfile (the cursor's file, '' = from line 1),
# succ_why where nothing is readable.
succ_from_file() { # folder
  local i id=""
  succ_cfile=""; succ_hs=""; succ_joined=""
  if [ -n "$succ_cline" ] && [ -n "$succ_line" ]; then
    id="$(succ_id_of "$succ_tx")"
    for i in "${!succ_fids[@]}"; do [ "${succ_fids[i]}" != "$id" ] || break; done
    jq -n --argjson l "$succ_line" --arg u "$succ_uuid" '{cursor: {line: $l, uuid: $u}}' > "$1/cursor.json"
    succ_hs="$id"; succ_cfile="$1/cursor.json"
    if [ -r "${succ_ftxs[i]}" ]; then succ_join "$i" "$1"; return 0; fi
    [ -z "$succ_read" ] || return 0
  fi
  # The check line's transcript is not readable, or none counts: the bookmark of the last save.
  succ_line=""; succ_uuid=""; succ_cfile=""
  succ_bookmark
  if [ "$succ_from_i" -lt 0 ]; then
    succ_read=""; succ_why="none of the predecessor's transcripts is readable on this machine (${succ_ftxs[*]:-the succession file names none})"
    return 0
  fi
  succ_hs="${succ_fids[succ_from_i]}"; succ_cfile="$succ_mark"
  succ_join "$succ_from_i" "$1"
}

# Writes <state>/<session>-restore.md for the successor, then the lock and the marker. Globals in: session, root,
# state_dir, state_tx (the successor's own transcript, may be empty), succ_file (the succession file, '' none; read
# by succ_file_read before).
succ_restore() { # carrier of the hand-back ('' none), predecessor name ('' = from the check line), carriers...
  local from="$1" pred="$2" work body="" line="" n open parts stamp chat="" lines=0 saved=false history=read cs=()
  shift 2
  work="$(hook_mktemp -d restore-from)" || { echo "no temp folder" >&2; return 2; }
  # shellcheck disable=SC2064 # the path expands now
  trap "rm -rf '$work'" RETURN
  if [ -n "$from" ]; then
    state_body "$from" "$work"
    body="$work/$(state_key "$from").md"
    if [ -e "$body" ]; then cs=("$from")
    elif [ -n "${succ_file:-}" ]; then
      # At the start the lock matters more than the carrier: the restore stands without it, and its head says so.
      succ_nocarrier="the carrier $from was not readable ($(head -c 200 "$work/$(state_key "$from").err" 2>/dev/null | tr '\r\n' '  '))"
      from=""; body=""
    else echo "carrier not readable: $from ($(head -c 200 "$work/$(state_key "$from").err" 2>/dev/null))" >&2; return 2; fi
  fi
  cs+=("$@")
  rs_txnote=""; rs_start_note=""; rs_steps=""; succ_joined=""; succ_cnote=""
  if [ -n "${succ_file:-}" ]; then succ_check_pick "$body" "$from"; line="$succ_cline"; else line="$(succ_check_line "$body")"; fi
  if succ_parse "$line"; then
    [ -z "$succ_line" ] || saved=true
    succ_find_tx
  else
    succ_checked=""; succ_checked_at=""; succ_tx=""; succ_read=""
    succ_why="no check line at $from: the predecessor did not save before the switch"
  fi
  if [ -n "${succ_file:-}" ]; then succ_from_file "$work"; pred="${pred:-$succ_fpred}"
  elif [ -n "$succ_read" ]; then
    jq -n --argjson l "${succ_line:-0}" --arg u "$succ_uuid" '{cursor: {line: $l, uuid: $u}}' > "$work/cursor.json"
    succ_cfile="$work/cursor.json"; succ_hs="$(succ_id_of "$succ_tx")"
  fi
  if [ -z "$pred" ]; then pred="$(succ_id_of "$succ_tx")" || pred=""; fi
  local start=1
  if [ -n "$succ_read" ]; then
    if [ -n "$succ_cfile" ]; then state_cursor "$succ_cfile" "$succ_read"
    else state_start=1; state_start_note="no bookmark of the predecessor (no cursor in ${succ_fwd:-its workDir}/.agent/state/<id>.json of ${succ_fids[*]}): from line 1"; fi
    [ -z "${succ_mark:-}" ] || [ "$succ_cfile" != "$succ_mark" ] || state_start_note="bookmark $succ_mark: $state_start_note"
    if ! state_extract_bounded "$succ_read" "$work/cand.jsonl" "$(succ_counted)"; then
      succ_why="the predecessor's transcript $succ_read was not read: $state_read_note"; succ_read=""
    fi
    start="$state_start"; rs_start_note="$state_start_note$succ_joined"
  fi
  [ -n "$succ_read" ] || { rs_txnote="$succ_why"; history=unreadable; : > "$work/cand.jsonl"; }
  state_posts_of="$pred"
  state_restore_gather "$work" "$succ_read" "$start" "$succ_checked" "$succ_checked_at" ${cs[@]+"${cs[@]}"}
  [ -z "$succ_read" ] || rs_steps="$(timeout 20 jq -nRr "$state_step_jq" < "$succ_read" 2>/dev/null | tr -d '\r')" || rs_steps=""
  stamp="$(date -u +%Y-%m-%dT%H%MZ)"
  rs_title="Restore after the switch - $stamp"
  if [ -n "${succ_file:-}" ]; then
    rs_lead="Written by the start from $succ_file: the predecessor ${pred:-(not named)} from the cursor of its check line, else of its last save, else from the start of its transcripts to their end, every entry whole, and the carriers changed since its check line. $succ_cnote"
    [ -n "$from" ] || rs_lead="$rs_lead No carrier: ${succ_nocarrier:-the task of the succession file \"${succ_ftask:-none}\" is no owner/repo#N}, so nothing was held against a carrier."
  else
    rs_lead="Written by session-state.sh restore --from $from: the predecessor ${pred:-(not named)} from the cursor of its last save to the end of its transcript, every entry whole, and the carriers changed since its check line${line:+ ($line)}."
  fi
  rs_lead="$rs_lead Carry each open box to a carrier or close it with the tool (bash .claude/hooks/ticks.sh close, the line below)."
  succ_pred_list
  [ -z "$succ_pnote" ] || rs_lead="$rs_lead"$'\n\n'"$succ_pnote."
  rs_note=""; rs_posts=1; rs_checked="$succ_checked"; rs_checked_at="$succ_checked_at"; rs_carriers=(${cs[@]+"${cs[@]}"})
  rs_rules="_none: a successor reads its start and its rule files as at any start_"
  local restore="$state_dir/$session-restore.md" hs="${succ_hs:-$session}"
  state_unexamined="$(jq -r 'select(has("end")) | .unexaminedNew // 0' < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
  if ! { state_restore_render "$work" | cut_mask > "$work/restore.md" && CLAUDE_PROJECT_DIR="$root" TICKS_LOCK_WAIT=10 \
    state_restore_list "$work/restore.md" "$restore" "$session" switch "$hs" "$work/open.jsonl" "$work" "$succ_plist"; }; then
    echo "cannot write $restore" >&2; return 2
  fi
  # The report of this restore counted up to the end of the reading: a later restore starts there. Its own file, as
  # a save of this session moves unexamined.json to its own transcript.
  if [ -n "$succ_read" ]; then
    local mark; mark="$(state_unexamined_mark "$state_dir" "$session")"
    state_unexamined_new "$work/cand.jsonl" "${mark%/*}/restored.json" "$succ_read" > /dev/null
  fi
  n="$(wc -l < "$restore" | tr -d ' ')"; open="$(state_restore_open "$restore")"; parts="$(state_read_parts "$restore")"
  # The restore file stands: the lock of /controller-mode (require-rule-read.sh) is lifted.
  rm -f "$cut_gate/$session-restore-owed"

  # The lock and the marker of a compaction, without its net: no boundary follows a switch, so the lock carries no
  # line count and holds until both files are read (or the valve of require-rule-read.sh).
  mkdir -p "$cut_gate" || { echo "cannot write $cut_gate" >&2; return 2; }
  [ ! -f "$root/.agents/rules/chat.md" ] || chat="$root/.agents/rules/chat.md"
  if command -v cygpath >/dev/null 2>&1; then
    restore="$(cygpath -w "$restore" 2>/dev/null || printf '%s' "$restore")"
    [ -z "$chat" ] || chat="$(cygpath -w "$chat" 2>/dev/null || printf '%s' "$chat")"
  fi
  # A marker an earlier cut left is reported first, with done false.
  if [ -f "$cut_gate/$session-cut-pending" ]; then
    cut_report undone "$state_tx" "$session" "$state_dir/$session.json" "$state_dir/cuts.jsonl" && rm -f "$cut_gate/$session-cut-pending"
  fi
  [ -z "$state_tx" ] || lines="$(wc -l < "$state_tx" | tr -d ' ')"
  # cut=switch lets a lone restore --none through the lock (require-rule-read.sh); the transcript keys its valve
  # per turn.
  printf 'cut=switch\ntranscript=%s\nneed=compact.restore %s\n%s' "$state_tx" "$restore" "${chat:+need=chat $chat$'\n'}" > "$cut_gate/$session-compact-lock" \
    || { echo "cannot write the lock" >&2; return 2; }
  printf 'cut=switch\npredecessor=%s\nat=%s\nfrom=%s\ntranscript=%s\nrestore=%s\nneed=compact.restore\n%ssaved=%s\nhistory=%s\nstopHolds=0\n' \
    "$pred" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$lines" "$state_tx" "$state_dir/$session-restore.md" "${chat:+need=chat$'\n'}" \
    "$saved" "$history" > "$cut_gate/$session-cut-pending" || { echo "cannot write the marker" >&2; return 2; }
  echo "restore: $restore ($n lines, $open open boxes)${rs_txnote:+; not read: $rs_txnote}"
  [ -z "$parts" ] || echo "It is above 25,000 tokens: read it in these parts, each with the Read tool's offset and limit - $parts."
  echo "Read it${chat:+ and $chat} in full with the Read tool before the next step; until then require-rule-read.sh holds the tool calls, and pb-hook stop warns at the turn end while a box is open. Carry each box to a carrier or close it with bash .claude/hooks/ticks.sh close <id> erledigt <reference> | gelesen <change ids> <sentence why nothing is to do> | ungeprueft <reason> --list $restore; a tick written by hand counts as open."
}

# A first start without a predecessor (ww3d/playbook#672, decision 3): the lock of /controller-mode goes, and the
# reason stands as a line cut "no-predecessor" in cuts.jsonl, which the report after the cut sends on.
succ_none() { # reason, cuts file
  local line
  cut_now
  line="$(jq -n -c --arg at "$cut_ts" --arg ver "${cut_version:-}" --arg repo "${cut_repo:-}" --arg s "$session" \
    --arg kind "${cut_kind:-unknown}" --arg place "${cut_place:-local}" --arg why "$1" \
    '{v: 1, at: $at, playbookVersion: (if $ver == "" then null else $ver end), repo: (if $repo == "" then null else $repo end),
      session: $s, kind: $kind, place: $place, cut: "no-predecessor", reason: $why, hook: "ran", done: true, alarm: [],
      notChecked: []}' | tr -d '\r')" || { echo "jq failed" >&2; return 2; }
  cut_append "$2" "$line" || { echo "cannot write $2" >&2; return 2; }
  cut_send "$2"
  echo "restore --none: no predecessor ($1); the lock of /controller-mode is lifted, the reason stands in $2"
}

# restore --none while the lock of a switch stands (the start found a stale succession file): the lock goes, and the
# switch's marker becomes its report line now, with the reason and done false.
succ_none_switch() { # reason, cuts file
  local mk="$cut_gate/$session-cut-pending"
  printf 'none=%s\n' "$(printf '%s' "$1" | tr '\r\n\t' '   ')" >> "$mk" || { echo "cannot write $mk" >&2; return 2; }
  cut_report undone "$state_tx" "$session" "$state_dir/$session.json" "$2" || { echo "report failed" >&2; return 2; }
  rm -f "$mk"
  echo "restore --none: $1; the lock of the switch is lifted, the switch and the reason stand in $2"
}
