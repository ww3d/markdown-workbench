#!/usr/bin/env bash
#
# Stop hook — read-receipt check. Generic, byte-identical across consumers.
#
# The SessionStart read-confirm.sh hook shows the read receipt to the human as its systemMessage;
# the model writes none. This hook never blocks a turn end; it only warns (ww3d/playbook#734). What it
# still checks is a receipt that stands in the transcript: a session without hooks writes the block
# by hand, and a session adds one line per rule file it read later. Such a line must not claim a read
# the record does not show (UNREAD below).
#
# What counts as a receipt: an assistant message whose text carries BOTH the receipt's line
# "Playbook <version> | Core" AND its "Memory:" line, each anchored to a line start (the earlier
# one-line form "Playbook <version> | Core AGENTS.md ..." and the old German words "Kern" and
# "Gedaechtnis:" are read until playbook 26.0.0, ww3d/playbook#356).
# Both must occur in the SAME assistant message. The first line alone is not proof of a receipt — an
# assistant text that only quotes it (a code fence, an explanation, a review of this
# very hook) matches that regex too, so the second, conjunctive test is what tells a
# real receipt from a quotation.
#
# A second signal, for the same two lines: a command the session RAN
# to print the receipt - a tool_use whose .input.command carries both, and whose
# own tool_result (same tool_use_id, not is_error) shows both too. Its place in
# the transcript is the result's line. Text written between tool calls can
# leave the model as thinking and then never lands as a text block
# (ww3d/playbook#271); an echoed receipt always does. A
# command that only carries the text as data - a file write, a refused call, a
# body sent somewhere - prints nothing of it back and does not count, the same
# rule require-rule-read.sh applies to a rule receipt (ww3d/playbook#273).
#
# Only a receipt after the newest compaction - a {"type":"system","subtype":"compact_boundary"}
# line or an attachment hookName "SessionStart:compact", the cut require-rule-read.sh reads - or
# /clear (hookName "SessionStart:clear") is checked: a compaction ends every rule read, so an earlier
# receipt is stale. A resume, fork or further startup does not cut (ww3d/playbook#337).
#
# Green lines: where the receipt stands, every line "+ <file> … read" in it must have a marker of
# a real read for the session (record-rule-read.sh; read-confirm.sh for the files the start
# loads); a green line without one warns at the turn end (UNREAD below), once per turn - see the
# second stop below. No session id, no sign that the read record runs, or a file that maps to no marker:
# the line passes.
#
# Fail-open by design, but the direction of "fail" matters and the two failure
# modes below are NOT the same thing:
#   - transcript missing, empty, or wholly unreadable (no file, zero JSON values)
#     -> ALLOW. There is nothing to judge, so the gate stays out of the way.
#   - a SINGLE unparsable line inside an otherwise readable transcript (e.g. a
#     write in progress truncated it mid-line) -> that one line is skipped, every
#     other line is still evaluated. This is NOT the same as failing open for the
#     whole transcript: a receipt after the broken line is still checked.
# Lines are parsed one at a time (jq -R + fromjson? // empty) rather than slurped
# in one jq -s call, precisely so one bad line cannot take the rest of the batch
# down with it the way a single JSON parse error would fail an entire -s slurp.
#
# Schema-drift vs. empty transcript: a non-empty transcript in which none of the
# fields the gate depends on (type / attachment.hookEvent / message.content[].type)
# can be found is treated as a sign that the CC transcript schema has shifted under
# us. The gate still fails open (allow), but emits a systemMessage warning that it
# no longer recognizes its schema, so silent drift does not pass unnoticed. An
# empty, unreadable, or missing transcript stays a silent fail-open as before.
#
# The jq -cn call that builds this hook's OWN output carries `|| true`: without it, a
# jq failure there (exit 2) would end this script under `set -e` with a non-zero exit
# code, and Claude Code reads a failing Stop hook as BLOCKING — the exact inversion of
# the fail-open stance this file argues for above.
#
# Second stop: Claude Code sets stop_hook_active to true when the turn is already
# continuing because another Stop hook blocked it. That stop repeats no warning of
# this hook (UNREAD_AGAIN, COMPACT_AGAIN below): the first stop had its word. A field
# that is missing or not the literal true counts as false.
#
# Stdin:  the Stop hook event JSON ({ transcript_path, stop_hook_active, ... }).
# Stdout: { systemMessage } with one line per warning, or nothing.

set -euo pipefail

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
read_hook_payload
input="$hook_input"

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
transcript="${transcript%$'\r'}" # jq for Windows ends its lines with CRLF
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
stop_hook_active="$(printf '%s' "$input" | jq -r '.stop_hook_active == true' 2>/dev/null || true)"
stop_hook_active="${stop_hook_active%$'\r'}" # jq for Windows ends its lines with CRLF

# Index of the newest compaction or clear vs. the last assistant receipt. A receipt before that
# cut is stale and not checked. Alongside the verdict, probe the fields the gate reads so a non-empty transcript
# with an unrecognized schema can be told apart from an empty one (see header).
#
# $in is built line by line (-R, raw+slurp so `.` is the whole file as one
# string, then split and re-parsed per line) rather than via a single jq -s
# slurp: a slurp fails whole on the first unparsable line, which would silently
# turn every later line — receipt included — into "nothing to judge here".
# fromjson? // empty drops exactly the broken line and keeps the rest.
#
# A transcript grows to tens of MB, and this runs at the end of every turn: `grep -F` first
# keeps only the lines the verdict can depend on (a SessionStart or compaction marker, a line
# with the receipt's first line), so jq parses a handful of lines instead of the file. With
# none of them there is nothing to block. The schema probe is a plain grep for the two fields
# a transcript always carries (an assistant entry, a hook attachment).
# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
verdict_jq='
    [ split("\n")[] | select(length > 0) | (fromjson? // empty) ] as $in
  | ($in | length) as $entries
  | ([ $in | to_entries[]
       | select((.value.type == "system" and .value.subtype? == "compact_boundary")
                or (.value.type == "attachment"
                    and (.value.attachment.hookName? == "SessionStart:compact"
                         or .value.attachment.hookName? == "SessionStart:clear")))
       | .key ] | last // -1) as $cut
  | def head_line: gsub("\\r"; "") | test("(^|\\n)Playbook [^|\\n]*\\| (Core|Kern)( |\\n|$)");
    def mem_line: test("(^|\\n)(Memory|Gedaechtnis):");
    def receipt: head_line and mem_line;
    def printed: if type == "string" then . elif type == "array" then map(.text? // "" | strings) | join("\n")
                 else "" end;
    ([ $in | to_entries[]
       | select(.value.type == "assistant")
       | ([ .value.message.content[]? | select(.type == "text") | .text ]) as $texts
       | select($texts | any(head_line))
       | select($texts | any(mem_line))
       | {k: .key, t: ($texts | join("\n"))} ] | last) as $rct
  | ($rct.k?) as $rc
  | ([ $in[] | select(.type == "assistant") | .message.content[]?
       | select(.type == "tool_use" and (.id | type == "string")
                and (.input.command? | type == "string"))
       | select(.input.command | receipt) | .id ]) as $echoed
  | ([ $in | to_entries[]
       | select(.value.type == "user") | .key as $k
       | .value.message.content[]?
       | select(.type == "tool_result" and .is_error != true and (.tool_use_id | type == "string"))
       | select(.tool_use_id as $id | any($echoed[]; . == $id))
       | select(.content | printed | receipt)
       | {k: $k, t: (.content | printed)} ] | last) as $rcmdt
  | ($rcmdt.k?) as $rcmd
  | ([$rc, $rcmd] | map(. // -1) | max) as $receipt
  | if ($entries == 0 or $receipt < 0 or $cut >= $receipt) then "ALLOW"
    else "ALLOW\n" + (if ($rc // -1) >= ($rcmd // -1) then $rct.t else $rcmdt.t end)
    end
'
lines="$(grep -F -e SessionStart -e compact_boundary -e '| Core' -e '| Kern' -- "$transcript" 2>/dev/null || true)"
if [ -s "$transcript" ] && ! grep -q -F -e '"type":"assistant"' -e '"hookEvent"' -- "$transcript" 2>/dev/null; then
  verdict="DRIFT"
elif [ -z "$lines" ]; then
  verdict="ALLOW"
else
  verdict="$(printf '%s\n' "$lines" | jq -Rrs "$verdict_jq" 2>/dev/null || true)"
fi

# The receipt text follows the verdict line, where there is one; jq for Windows ends lines with CRLF.
verdict="${verdict//$'\r'/}"
receipt_text=""
case "$verdict" in *$'\n'*) receipt_text="${verdict#*$'\n'}"; verdict="${verdict%%$'\n'*}" ;; esac

# --- every green line against the read record (.agents/rules/session.md, section "Session Receipt") ----------
# A line "+ <file> <version> <sha> read" claims a read. record-rule-read.sh and read-confirm.sh
# leave a marker per real read under <the temp folder>/claude-rule-gate/<session>-read-main-<name>; a
# green line without its marker is refused like a missing receipt. Fail-open: no session id, no
# sign that record-rule-read.sh ran for the session (its "<session>-recorder.on"), or a line whose
# file maps to no marker lets the line pass.
unread=""
session_id=""
sid_re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
if [[ $input =~ $sid_re ]]; then session_id="${BASH_REMATCH[1]}"; fi
# shellcheck source=SCRIPTDIR/lib/tempdir.sh
. "${BASH_SOURCE[0]%/*}/lib/tempdir.sh" 2>/dev/null && hook_tmpdir || exit 0
gate_dir="$hook_tmp/claude-rule-gate"
if [ "$verdict" = "ALLOW" ] && [ -n "$receipt_text" ] && [[ $session_id =~ ^[A-Za-z0-9_-]+$ ]] \
   && [ -e "${gate_dir}/${session_id}-recorder.on" ]; then
  # Every line that starts with "+" and says read is checked, whatever its columns look like.
  # Leading blanks, no blank after "+", a path in any spelling and text after the note all count.
  green_re='^[[:space:]]*\+[[:space:]]*([^[:space:]]+)[[:space:]].*[[:space:]]read([[:space:]]+\(([^)]*)\))?([[:space:]].*)?$'
  root="${CLAUDE_PROJECT_DIR:-$PWD}"
  while IFS= read -r l; do
    l="${l%$'\r'}"
    [[ $l =~ $green_re ]] || continue
    file="${BASH_REMATCH[1]//\\//}"; note="${BASH_REMATCH[3]//\\//}"; marker=""
    file="${file#./}"
    case "$file" in */.agents/rules/*) file=".agents/rules/${file##*/.agents/rules/}" ;; esac
    case "$file" in */.claude/skills/*) file=".claude/skills/${file##*/.claude/skills/}" ;; esac
    case "$file" in .agents/rules/*) file="${file#.agents/rules/}" ;; esac
    case "$file" in /*/AGENTS.md|[A-Za-z]:/*/AGENTS.md) file="AGENTS.md" ;; /*/CLAUDE.md|[A-Za-z]:/*/CLAUDE.md) file="CLAUDE.md" ;; esac
    case "$file" in
      AGENTS.md) marker="core.agents" ;;
      CLAUDE.md) marker="core.claude" ;;
      Audit)
        # The audit name is the first state-<stamp>.md / ist-stand-<stamp>.md in the brackets, whatever
        # surrounds it; brackets without one stand like a line without brackets: any audit read counts.
        audit_file="" short=""
        if [[ $note =~ (state-|ist-stand-)([A-Za-z0-9_.-]+)\.md ]]; then
          audit_file="${BASH_REMATCH[0]}"; marker="core.audit.${BASH_REMATCH[2]}"
          short="${gate_dir}/${session_id}-read-main-${marker}.short"
        else
          # A line-reached file (<marker>.short) is no read of an audit.
          marker="core.audit.(none read)"
          for m in "${gate_dir}/${session_id}-read-main-core.audit."*; do
            case "$m" in *.short) [ -z "$short" ] && short="$m"; continue ;; esac
            [ ! -e "$m" ] || marker=""; break
          done
        fi ;;
      local/*.md) marker="local-${file#local/}"; marker="${marker%.md}" ;;
      .claude/skills/*/reference/*.md)
        skill="${file#.claude/skills/}"; skill="${skill%%/*}"; f="${file##*/}"
        marker="skill-${skill}-${f%.md}" ;;
      */*) ;;
      # A bare name is a rule only where the rule file exists; any other file has no marker.
      *.md) [ ! -f "${root}/.agents/rules/${file}" ] || marker="${file%.md}" ;;
    esac
    [[ -z $marker || -e "${gate_dir}/${session_id}-read-main-${marker}" ]] && continue
    if [ "$file" = Audit ]; then
      # One short reason after the name: the furthest line reached, or that no read is recorded.
      reach="" ends=""
      [ -z "$short" ] || [ ! -r "$short" ] || read -r reach ends < "$short" 2>/dev/null || true
      if [[ $reach =~ ^[0-9]+$ && $ends =~ ^[0-9]+$ ]]; then file="Audit (read through line ${reach}, short form ends at ${ends})"
      else file="Audit (no read of ${audit_file:-an audit} recorded)"; fi
    fi
    unread="${unread:+${unread}, }${file}"
  done <<< "$receipt_text"
  [ -z "$unread" ] || verdict="UNREAD"
fi

# --- after a compaction (ww3d/playbook#487): warn at the turn end until the restore is done -------------
# The turn end warns while the restore file named by the lock is unread, once per turn and with the same fail-open
# stance: no session id or nothing readable says nothing. Its open boxes are a list of the tick tool
# (ww3d/playbook#688): the guard below warns about them, and `ticks.sh guard --list` counts them for the report
# after the cut.
compact_missing="" compact_open=0
ticks_reg="${CLAUDE_PROJECT_DIR:-$PWD}/.agent/state/ticks/open"
ticks_any=""
if [ -d "$ticks_reg" ]; then for f in "$ticks_reg"/*; do if [ -f "$f" ]; then ticks_any=1; break; fi; done; fi
if [ "$verdict" = "ALLOW" ] && [[ $session_id =~ ^[A-Za-z0-9_-]+$ ]]; then
  compact_lock_file="${gate_dir}/${session_id}-compact-lock"
  if [ -f "$compact_lock_file" ]; then
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in
        need=*)
          l="${l#need=}"; _cl_name="${l%% *}"; _cl_file="${l#* }"
          [[ $_cl_name =~ ^[A-Za-z0-9._-]+$ ]] || continue
          [ ! -e "${gate_dir}/${session_id}-read-main-${_cl_name}" ] || continue
          [ ! -f "$_cl_file" ] || compact_missing="${compact_missing:+${compact_missing}, }${_cl_file}" ;;
      esac
    done < "$compact_lock_file" 2>/dev/null || true
  fi
  compact_restore="${CLAUDE_PROJECT_DIR:-$PWD}/.agent/state/${session_id}-restore.md"
  # Without a registered list nothing is open: no process.
  if [ -n "$ticks_any" ] && [ -f "${compact_restore%.md}.json" ]; then
    compact_open="$(CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" timeout 10 bash "${BASH_SOURCE[0]%/*}/ticks.sh" guard --list "$compact_restore" < /dev/null 2>/dev/null)" || compact_open=0
    compact_open="${compact_open//[!0-9]/}"; compact_open="${compact_open:-0}"
  elif [ -f "$compact_restore" ] && [ ! -f "${compact_restore%.md}.json" ]; then
    # The plain file restore-compact-state.sh leaves when the list could not be built: its "- [ ]" count, only in the
    # two sections of boxes; a quoted line elsewhere is text.
    compact_open="$(awk '{ sub(/\r$/, "") } /^## / { s = ($0 == "## History without a carrier" || $0 == "## Carriers changed since checked"); next }
      s && /^- \[ \]/ { n++ } END { print n + 0 }' "$compact_restore" 2>/dev/null)" || compact_open=0
    [[ $compact_open =~ ^[0-9]+$ ]] || compact_open=0
    [ "$compact_open" -eq 0 ] || verdict="COMPACT"
  fi
  if [ -n "$compact_missing" ]; then verdict="COMPACT"; fi
fi
[ "$verdict" = "UNREAD" ] && [ "$stop_hook_active" = "true" ] && verdict="UNREAD_AGAIN"
[ "$verdict" = "COMPACT" ] && [ "$stop_hook_active" = "true" ] && verdict="COMPACT_AGAIN"

# --- the tick lists (ww3d/playbook#688, ticks.sh) ----------------------------------------------------------------
# A list registered under .agent/state/ticks/open/ warns at the turn end while a box is open: one line, once per turn
# (ww3d/playbook#734). Without a registered list this costs a glob, no process.
# Fail-open: a guard that fails or runs past 10 s says nothing (docs/playbook-ops.md, Abhak-Werkzeug, Fail-Verhalten).
# Without a session id the save lists and restore files of every session are skipped ("-" names none).
ticks_out=""
if [ -n "$ticks_any" ]; then
  ticks_out="$(CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" TICKS_STOP_ACTIVE="$stop_hook_active" TICKS_SESSION="${session_id:--}" \
    TICKS_WARNED="${session_id:+$gate_dir/$session_id-ticks-warned}" TICKS_PLAIN=1 timeout 10 \
    bash "${BASH_SOURCE[0]%/*}/ticks.sh" guard < /dev/null 2>/dev/null)" || ticks_out=""
  ticks_out="${ticks_out//$'\r'/}"; ticks_out="${ticks_out%%$'\n'*}"
elif [ -n "$session_id" ]; then
  rm -f "$gate_dir/$session_id-ticks-warned" 2>/dev/null
fi

# --- the report after the cut (ww3d/playbook#487, lib/cut.sh) ------------------------------------------------
# restore-compact-state.sh leaves <gate>/<session>-cut-pending. Each stop that warns about the restore counts in it; the
# first turn end with the restore read and no open box writes the line (session-state.sh report, 10 s) and drops the
# marker. A failed or timed-out report keeps the marker for the next turn end.
cut_marker="${gate_dir}/${session_id}-cut-pending"
if [[ $session_id =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "$cut_marker" ]; then
  if [ "$verdict" = COMPACT ] || [ "$verdict" = COMPACT_AGAIN ] || [ "$compact_open" -gt 0 ]; then
    if awk -F= '$1 == "stopHolds" { $0 = "stopHolds=" ($2 + 1) } { print }' "$cut_marker" > "$cut_marker.tmp" 2>/dev/null; then
      mv -f "$cut_marker.tmp" "$cut_marker" 2>/dev/null || rm -f "$cut_marker.tmp"
    fi
  elif [ "$verdict" = ALLOW ] && [ -z "$compact_missing" ]; then
    if CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}" timeout 10 bash "${BASH_SOURCE[0]%/*}/session-state.sh" report \
      --session "$session_id" --transcript "$transcript" > /dev/null 2>&1; then
      rm -f "$cut_marker" 2>/dev/null
    fi
  fi
fi

# --- the output: one short line, at most 200 characters, no box text; this hook never blocks (ww3d/playbook#734) ----
# The second stop of a turn repeats no warning: it had its word on the first. A warning of this hook that equals the
# last one of the session stays silent (<session>-receipt-warned), as the tick guard does per list count.
msg=""
case "$verdict" in
  UNREAD) msg="Quittung nennt ungelesen: $unread, ganz lesen" ;;
  DRIFT) msg="Quittungs-Pruefung: Verlaufsformat unbekannt, pruefen" ;;
  COMPACT)
    msg="${compact_missing:+Nach der Verdichtung ungelesen: $compact_missing}"
    if [ "$compact_open" -gt 0 ] && [ ! -f "${compact_restore%.md}.json" ]; then
      msg="${msg:+$msg; }$compact_open offene Punkte in ${compact_restore#"${CLAUDE_PROJECT_DIR:-$PWD}"/}, schliessen mit bash .claude/hooks/ticks.sh close"
    fi ;;
esac
if [[ $session_id =~ ^[A-Za-z0-9_-]+$ ]]; then
  warned="${gate_dir}/${session_id}-receipt-warned"
  if [ -z "$msg" ]; then
    case "$verdict" in *_AGAIN) ;; *) rm -f "$warned" 2>/dev/null ;; esac
  elif [ "$msg" = "$(tr -d '\r' < "$warned" 2>/dev/null)" ]; then msg=""
  else mkdir -p "$gate_dir" 2>/dev/null; printf '%s\n' "$msg" > "$warned" 2>/dev/null || true
  fi
fi
msg="${ticks_out}${ticks_out:+${msg:+; }}${msg}"
[ "${#msg}" -le 200 ] || msg="${msg:0:196} ..."
[ -z "$msg" ] || jq -cn --arg m "$msg" '{systemMessage: $m}' || true
exit 0
