#!/usr/bin/env bash
#
# The tick tool: a list whose boxes only this tool closes, each closing checked against the server, and the guard
# that warns at a turn end while a registered list has a box open (ww3d/playbook#688, decision log
# docs/decisions/2026-11-21T0002Z-playbook-688-tick-guard-decisions.md). A command the session runs, and the guard
# require-receipt.sh calls; no hook of its own. Generic: it names no repository and no machine.
#
# Usage:  bash ticks.sh open <list.md> <spec.json>
#         bash ticks.sh close <id> erledigt <reference> [--list <list.md>]
#         bash ticks.sh close <id> gelesen <change ids> <sentence why nothing is to do> [--list <list.md>]
#         bash ticks.sh close <id> ungeprueft <reason> [--list <list.md>]
#         bash ticks.sh check [<list.md>]   (exit 3 when a source was not reachable)
#         bash ticks.sh guard [--list <list.md>]
#         bash ticks.sh legacy-check <list.md>
#   open          a new list from a spec (lib/ticks.sh, ticks_open); registered for the guard while a box is open
#   close         the only way to close a box; at most three per tool call of the session or a helper; the ref is
#                 owner/repo#N, its URL, a comment URL, owner/repo@sha or qNNN
#   check         evidence edited or deleted after the tick, and comments of others the own account edited or
#                 deleted at a carrier, reopen their box
#   guard         the Stop check: one warning line while a registered list has an open box, never a block
#                 (ww3d/playbook#734), else nothing; with --list the number of open boxes of that list; bare as a
#                 Stop hook it takes session and stop_hook_active from the payload
#   legacy-check  a list in the old "- [x] <box> -> <evidence>" form against the same rules
#   --list        the list when more than one is registered; default: the one registered list
# Exit:   0 done, 1 refused or open, 2 usage or unreadable, 3 a box set to "[u] nicht pruefbar".
# Env:    TICKS_NOW (the clock, ISO), TICKS_TIMEOUT (seconds per forge or channel call, default 20),
#         TICKS_STOP_ACTIVE (true on the second stop of a turn), TICKS_SESSION (the guard skips save lists and
#         restore files of other sessions), TICKS_WARNED (the counts of the guard's last warning; same counts: silent),
#         TICKS_PLAIN (the guard prints its bare line instead of the JSON),
#         TICKS_TRANSCRIPT (the session transcript), PLAYBOOK_CARRIER_TEXT_CMD (the channel: status qNNN).
#         TICKS_LOCK_WAIT (seconds to wait for a list another call holds, default 120).
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
# shellcheck source=SCRIPTDIR/lib/resolve.sh
. "$here/lib/resolve.sh"
# shellcheck source=SCRIPTDIR/lib/ticks.sh
. "$here/lib/ticks.sh"

usage() { sed -n '8,29p' "$0" | sed 's/^# \{0,1\}//'; }

# The one registered list, when no --list names one; a list registered under two spellings of its path is one.
pick_list() {
  local reg f v found=()
  reg="$(ticks_registry)"
  for f in "$reg"/*; do
    [ -f "$f" ] || continue
    v="$(ticks_canon "$(head -n 1 "$f" | tr -d '\r')")"
    case " ${found[*]} " in *" $v "*) ;; *) found+=("$v") ;; esac
  done
  case "${#found[@]}" in
    1) printf '%s' "${found[0]}" ;;
    0) echo "no registered list: name it with --list <list.md>" >&2; return 2 ;;
    *) echo "several lists registered, name one with --list: ${found[*]}" >&2; return 2 ;;
  esac
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
list=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list="${2:-}"; shift 2 || { usage >&2; exit 2; } ;;
    *) args+=("$1"); shift ;;
  esac
done

trap 'ticks_unlock; resolve_cleanup 2>/dev/null' EXIT
# The list by its absolute path: the guard finds it from any folder; one writer at a time.
locked() { list="$(ticks_abs "$list")"; ticks_lock "$(ticks_side "$list")" || exit 2; }

case "$cmd" in
  open)
    [ ${#args[@]} -eq 2 ] || { usage >&2; exit 2; }
    list="${args[0]}"; locked
    ticks_open "$list" "${args[1]}" ;;
  close)
    [ ${#args[@]} -ge 3 ] || { usage >&2; exit 2; }
    [ -n "$list" ] || list="$(pick_list)" || exit 2
    locked
    ticks_close "$list" "${args[@]}" ;;
  check)
    [ -n "$list" ] || list="${args[0]:-}"
    [ -n "$list" ] || list="$(pick_list)" || exit 2
    locked
    ticks_check "$list" ;;
  guard)
    # --list is a script's call, not the hook's: it reads nothing, so an open stdin cannot hold it.
    if [ -n "$list" ]; then ticks_guard_count "$(ticks_abs "$list")"; exit; fi
    payload=""; [ -t 0 ] || payload="$(cat)"
    # Called bare as a Stop hook (managed-settings.json, instance/README.md), not by require-receipt.sh, which sets
    # TICKS_WARNED: the payload names the session, so the same counts stay silent here too (ww3d/playbook#734).
    if [ -z "${TICKS_WARNED+x}" ] && [ -n "$payload" ]; then
      # Where require-receipt.sh is registered, it carries the warning; a second hook would say it twice.
      grep -qs 'require-receipt\.sh' "$(ticks_project)/.claude/settings.json" && exit 0
      if [[ $payload =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9_-]+)\" ]]; then
        export TICKS_SESSION="${TICKS_SESSION:-${BASH_REMATCH[1]}}"
        [ -z "${hook_tmp:-}" ] || export TICKS_WARNED="$hook_tmp/claude-rule-gate/${BASH_REMATCH[1]}-ticks-warned"
      fi
      [[ ! $payload =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] || export TICKS_STOP_ACTIVE=true
    fi
    ticks_guard ;;
  legacy-check)
    if [ ${#args[@]} -ne 1 ] || [ ! -r "${args[0]}" ]; then usage >&2; exit 2; fi
    ticks_legacy_check "${args[0]}" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
