# shellcheck shell=bash
# Sourced by the generic hooks, never run: reads the hook payload from stdin the one way that works on
# every platform, and says once per Claude Code session when it came back empty (ww3d/playbook#488).
#
# `$(</dev/stdin)` cannot open the Windows named pipe Claude Code hands a hook under Git Bash ("No such
# file or directory"), so every hook that used it read nothing and ended fail-open, silently. `cat` reads
# fd 0 itself and works for a pipe, a file redirect, a socket (cloud session) and a named pipe alike. The `read`
# builtin reads fd 0 as well and starts no process, but takes a pipe byte by byte: it reads the first 4 KB, `cat`
# only the rest of a longer payload (ww3d/playbook#734, decision 3).
#
# Usage:  read_hook_payload    then read "$hook_input"; settings are variables set on the call:
#   hook_payload_quiet=1      the warning goes to stderr only: for a hook whose stdout is its own JSON, a
#                             second object would break it.
#   hook_payload_timeout=N    one bounded builtin read of the whole payload, for a hand call whose stdin may stay
#                             open (read-confirm.sh).
# A terminal on stdin (a hand call such as /read-check) leaves the payload empty without a warning.

# Every hook sources this file before its first program call, so it also drops Git Bash's path-conversion switches a
# caller may have exported (ww3d/playbook#507): with MSYS_NO_PATHCONV=1 the native jq opens no /d/... or /tmp path.
# A hook that needs a switch for one call sets it inline on that call.
unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL
# shellcheck source=SCRIPTDIR/tempdir.sh
. "${BASH_SOURCE[0]%/*}/tempdir.sh" 2>/dev/null || true

read_hook_payload() {
  hook_input=""
  [ -t 0 ] && return 0
  # Bytes, not characters: in a UTF-8 locale a broken sequence would make the count below disagree with the read.
  local LC_ALL=C
  if [ -n "${hook_payload_timeout:-}" ]; then
    IFS= read -r -t "$hook_payload_timeout" -d '' hook_input || true
  else
    IFS= read -r -N 4096 hook_input || true
    [ "${#hook_input}" -lt 4096 ] || hook_input+="$(cat)" || true
    # Trailing newlines go, as they did with `$(cat)` alone.
    while [ "${hook_input: -1}" = $'\n' ]; do hook_input="${hook_input%?}"; done
  fi
  [ -n "$hook_input" ] || _hook_noinput_once
  return 0
}

# One warning per hook and Claude Code session: the marker is keyed by the hook's file name and the parent
# process (Claude Code itself; there is no session id to key on when the payload is the thing missing). A
# marker folder that cannot be written costs only a repeated warning, never the fail-open exit.
_hook_noinput_once() {
  local hook="${BASH_SOURCE[-1]##*/}" dir msg
  hook_tmpdir && dir="$hook_tmp/claude-rule-gate" || dir=/dev/null/claude-rule-gate
  local marker="${dir}/noinput-pid${PPID}-${hook}"
  [ -e "$marker" ] && return 0
  { mkdir -p "$dir" && : > "$marker"; } 2>/dev/null || true
  msg="warning: hook ${hook} read no input, running fail-open (platform=$(uname -s 2>/dev/null || echo unknown))"
  printf '%s\n' "$msg" >&2
  if [ "${hook_payload_quiet:-0}" != 1 ]; then printf '{"systemMessage":"%s"}\n' "$msg"; fi
  return 0
}
