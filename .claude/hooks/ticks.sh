#!/usr/bin/env bash
#
# The tick tool: a list whose boxes only this tool closes, each closing checked against the server, and the guard
# that holds a turn end while a registered list has a box open (ww3d/playbook#688, decision log
# docs/decisions/2026-11-21T0002Z-playbook-688-tick-guard-decisions.md). A command the session runs, and the guard
# require-receipt.sh calls; no hook of its own. Generic: it names no repository and no machine.
#
# Usage:  bash ticks.sh open <list.md> <spec.json>
#         bash ticks.sh close <id> erledigt <reference> [--list <list.md>]
#         bash ticks.sh close <id> gelesen <change ids> <sentence why nothing is to do> [--list <list.md>]
#         bash ticks.sh close <id> ungeprueft <reason> [--list <list.md>]
#         bash ticks.sh check [<list.md>]   (exit 3 when a source was not reachable)
#         bash ticks.sh guard
#         bash ticks.sh legacy-check <list.md>
#   open          a new list from a spec (lib/ticks.sh, ticks_open); registered for the guard while a box is open
#   close         the only way to close a box; at most three per tool call of the session; the reference is
#                 owner/repo#N, its URL, a comment URL, owner/repo@sha or qNNN
#   check         evidence edited or deleted after the tick, and comments of others the own account edited or
#                 deleted at a carrier, reopen their box
#   guard         the Stop check: the block JSON on stdout while a registered list has an open box, else nothing
#   legacy-check  a list in the old "- [x] <box> -> <evidence>" form against the same rules
#   --list        the list when more than one is registered; default: the one registered list
# Exit:   0 done, 1 refused or open, 2 usage or unreadable, 3 a box set to "[u] nicht pruefbar".
# Env:    TICKS_NOW (the clock, ISO), TICKS_TIMEOUT (seconds per forge or channel call, default 20),
#         TICKS_TRANSCRIPT (the session transcript), PLAYBOOK_CARRIER_TEXT_CMD (the channel: status qNNN).
#         TICKS_LOCK_WAIT (seconds to wait for a list another call holds, default 120).
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
# shellcheck source=SCRIPTDIR/lib/resolve.sh
. "$here/lib/resolve.sh"
# shellcheck source=SCRIPTDIR/lib/ticks.sh
. "$here/lib/ticks.sh"

usage() { sed -n '8,26p' "$0" | sed 's/^# \{0,1\}//'; }

# The one registered list, when no --list names one.
pick_list() {
  local reg f found=()
  reg="$(ticks_registry)"
  for f in "$reg"/*; do [ -f "$f" ] && found+=("$(head -n 1 "$f" | tr -d '\r')"); done
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
    # A Stop payload may come on stdin; the guard reads the registry, not the payload.
    [ -t 0 ] || cat > /dev/null
    ticks_guard ;;
  legacy-check)
    if [ ${#args[@]} -ne 1 ] || [ ! -r "${args[0]}" ]; then usage >&2; exit 2; fi
    ticks_legacy_check "${args[0]}" ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
