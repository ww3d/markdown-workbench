# shellcheck shell=bash
# shellcheck disable=SC2034 # rs_* globals are read by state_restore_render
# shellcheck disable=SC2154 # root, session, state_dir, state_step_jq, state_start*, cut_gate:
#   set by session-state.sh, lib/state.sh and lib/cut.sh
# Sourced by session-state.sh, never run: EINLESEN of a successor after a switch (ww3d/playbook#487, #485). The
# predecessor's check line at its carrier names its transcript, its cursor and its check time; from them the
# successor's restore file is written like the one after a compaction (lib/state.sh), plus the lock and the marker
# the hooks know from a compaction. Needs lib/state.sh and lib/cut.sh loaded, jq and gh.

# The newest check line of a carrier body: in its section "## Hand-back" where it has one, else anywhere.
succ_check_line() { # body file -> the line on stdout, nothing where none stands
  local re='checked: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z · (cursor: .* L[0-9]+( [0-9A-Fa-f-]+)?|transcript: not readable)'
  { awk '{ sub(/\r$/, "") } /^## / { s = ($0 == "## Hand-back") } s' "$1" | grep -o -E "$re" \
    || grep -o -E "$re" "$1"; } 2>/dev/null | tail -n 1
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

# Writes <state>/<session>-restore.md for the successor, then the lock and the marker. Globals in: session, root,
# state_dir, state_tx (the successor's own transcript, may be empty), win() not needed: paths go as they are.
succ_restore() { # carrier of the hand-back, predecessor name ('' = from the check line), carriers...
  local from="$1" pred="$2" work body line n open stamp chat="" lines=0 saved=false history=read
  shift 2
  work="$(mktemp -d "${TMPDIR:-/tmp}/restore-from.XXXXXX")" || { echo "no temp folder" >&2; return 2; }
  # shellcheck disable=SC2064 # the path expands now
  trap "rm -rf '$work'" RETURN
  state_body "$from" "$work"
  body="$work/$(state_key "$from").md"
  [ -e "$body" ] || { echo "carrier not readable: $from ($(head -c 200 "$work/$(state_key "$from").err" 2>/dev/null))" >&2; return 2; }
  line="$(succ_check_line "$body")"
  rs_txnote=""; rs_start_note=""; rs_steps=""
  if succ_parse "$line"; then
    [ -z "$succ_line" ] || saved=true
    succ_find_tx
  else
    succ_checked=""; succ_checked_at=""; succ_tx=""; succ_read=""
    succ_why="no check line at $from: the predecessor did not save before the switch"
  fi
  if [ -z "$pred" ]; then pred="${succ_tx##*[/\\]}"; pred="${pred%.jsonl}"; [[ $pred =~ ^[A-Za-z0-9_-]+$ ]] || pred=""; fi
  local start=1
  if [ -n "$succ_read" ]; then
    jq -n --argjson l "${succ_line:-0}" --arg u "$succ_uuid" '{cursor: {line: $l, uuid: $u}}' > "$work/cursor.json"
    state_cursor "$work/cursor.json" "$succ_read"; start="$state_start"; rs_start_note="$state_start_note"
    if ! state_extract "$succ_read" "$start" > "$work/cand.jsonl" 2>/dev/null; then
      succ_why="the predecessor's transcript $succ_read was not parsed"; succ_read=""
    fi
  fi
  [ -n "$succ_read" ] || { rs_txnote="$succ_why"; history=unreadable; : > "$work/cand.jsonl"; }
  state_posts_of="$pred"
  state_restore_gather "$work" "$succ_read" "$start" "$succ_checked" "$succ_checked_at" "$from" "$@"
  [ -z "$succ_read" ] || rs_steps="$(timeout 20 jq -nRr "$state_step_jq" < "$succ_read" 2>/dev/null | tr -d '\r')" || rs_steps=""
  stamp="$(date -u +%Y-%m-%dT%H%MZ)"
  rs_title="Restore after the switch - $stamp"
  rs_lead="Written by session-state.sh restore --from $from: the predecessor ${pred:-(not named)} from the cursor of its last save to the end of its transcript, every entry whole, and the carriers changed since its check line${line:+ ($line)}. Carry each open box to a carrier or tick it \"- [x] <box> -> <proof>\"."
  rs_note=""; rs_posts=1; rs_checked="$succ_checked"; rs_checked_at="$succ_checked_at"; rs_carriers=("$from" "$@")
  rs_rules="_none: a successor reads its start and its rule files as at any start_"
  local restore="$state_dir/$session-restore.md"
  if ! { state_restore_render "$work" | cut_mask > "$work/restore.md" && mv -f "$work/restore.md" "$restore"; }; then
    echo "cannot write $restore" >&2; return 2
  fi
  n="$(wc -l < "$restore" | tr -d ' ')"; open="$(state_restore_open "$restore")"

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
  printf 'need=compact.restore %s\n%s' "$restore" "${chat:+need=chat $chat$'\n'}" > "$cut_gate/$session-compact-lock" \
    || { echo "cannot write the lock" >&2; return 2; }
  printf 'cut=switch\npredecessor=%s\nat=%s\nfrom=%s\ntranscript=%s\nrestore=%s\nneed=compact.restore\n%ssaved=%s\nhistory=%s\nstopHolds=0\n' \
    "$pred" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$lines" "$state_tx" "$state_dir/$session-restore.md" "${chat:+need=chat$'\n'}" \
    "$saved" "$history" > "$cut_gate/$session-cut-pending" || { echo "cannot write the marker" >&2; return 2; }
  echo "restore: $restore ($n lines, $open open boxes)${rs_txnote:+; not read: $rs_txnote}"
  echo "Read it${chat:+ and $chat} in full with the Read tool before the next step; until then require-rule-read.sh holds the tool calls, and require-receipt.sh holds the turn end while a box is open. Carry each box to a carrier or tick it '- [x] <box> -> <proof>'."
}
