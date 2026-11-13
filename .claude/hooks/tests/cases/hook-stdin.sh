#!/usr/bin/env bash
# Hook suite section: how the hooks read their payload: a socket, lib/stdin.sh, an empty stdin
# Run alone: bash .claude/hooks/tests/cases/hook-stdin.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== the hooks read a socket on stdin (Claude Code in a cloud session) =="
# The case is the cloud session's (Linux); it needs a python3 that really starts - on Windows the
# name can be the Store placeholder - and a POSIX socket, which a Windows bash does not hand over.
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) sock_skip="a Windows bash: no POSIX socket on stdin" ;; *) sock_skip="" ;; esac
[ -n "$sock_skip" ] || python3 -c '' >/dev/null 2>&1 || sock_skip="python3 does not start"
if [ -z "$sock_skip" ]; then
  sock_tmp="$fix/sock-tmp"; mkdir -p "$sock_tmp"
  sock_run() { # hook, payload -> "rc|stdout|stderr"
    python3 -c '
import socket, subprocess, sys
a, b = socket.socketpair()
b.sendall(sys.argv[2].encode()); b.shutdown(socket.SHUT_WR)
r = subprocess.run(["bash", sys.argv[1]], stdin=a, capture_output=True, text=True)
print(f"{r.returncode}|{r.stdout.strip()}|{r.stderr.strip()}")' "$hooks/$1.sh" "$2"
  }
  got="$(TMPDIR="$sock_tmp" CLAUDE_PROJECT_DIR="$repo_root" sock_run record-rule-read \
    "$(js "sock-$$"; sk_s="$REPLY"; js "$repo_root/.agents/rules/pr.md"
      printf '{"session_id":%s,"cwd":"/x","tool_name":"Read","tool_input":{"file_path":%s},"tool_response":{"file":{"filePath":%s}}}' "$sk_s" "$REPLY" "$REPLY")")"
  if [ "${got%%|*}" = 0 ] && [ -e "$sock_tmp/claude-rule-gate/sock-$$-read-main-pr" ]; then ok 'record-rule-read.sh records from a socket' marker
  else bad 'record-rule-read.sh records from a socket' "$got" 'marker'; fi
  got="$(sock_run guard-kill '{"tool_name":"Bash","tool_input":{"command":"kill -9 1"}}')"
  case "$got" in 0*'"permissionDecision":"deny"'*) ok 'guard-kill.sh judges a command from a socket' deny ;;
    *) bad 'guard-kill.sh judges a command from a socket' "$got" deny ;; esac
  got="$(TMPDIR="$sock_tmp" CLAUDE_PROJECT_DIR="$repo_root" sock_run require-rule-read \
    "$(js "$fix/rule-no-receipt.jsonl"; printf '{"session_id":"sock-r-1","transcript_path":%s,"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"gh issue create --title x"}}' "$REPLY")")"
  case "$got" in 0*'"permissionDecision":"deny"'*) ok 'require-rule-read.sh judges a call from a socket' deny ;;
    *) bad 'require-rule-read.sh judges a call from a socket' "$got" deny ;; esac
else
  echo "  skip socket cases                                       ($sock_skip)"
fi

echo "== the hooks read stdin through lib/stdin.sh and say once when it came back empty (ww3d/playbook#488) =="
# Pipe, file redirect and a terminal are the stdin kinds a hand call or Claude Code hands over; the Windows named
# pipe is what `$(</dev/stdin)` could not read. An empty payload is a hook that read nothing: one warning per
# hook and Claude Code session (the parent process), stderr plus a systemMessage, and still exit 0.
n_tmp="$fix/noinput-tmp"; mkdir -p "$n_tmp"
# The hooks write their state under the project (restore file, report line): a project of its own, never the repo.
n_proj="$fix/noinput-proj"; mkdir -p "$n_proj"
n_probe="$fix/probe-stdin.sh"
printf '%s\n' '. "$1"' 'read_hook_payload' 'printf "[%s]" "$hook_input"' > "$n_probe"
n_lib="$hooks/lib/stdin.sh"
n_json='{"session_id":"n488","tool_name":"Read"}'
printf '%s' "$n_json" > "$fix/noinput-payload.json"
# Both calls of a pair run in one subshell, so both have the same parent process, as two hook calls of one session do.
n_twice() { # stdin file, command... -> stdout of both runs, then "|", then stderr of both
  local in="$1"; shift
  ( "$@" < "$in" 2>"$fix/n-err1"; "$@" < "$in" 2>"$fix/n-err2" ) 2>/dev/null
}
n_marker() { local f; for f in "$n_tmp"/claude-rule-gate/noinput-pid*-"$1".sh; do [ -e "$f" ] && return 0; done; return 1; }
n_count() { local c=0 l; while IFS= read -r l; do case "$l" in *"read no input"*) c=$((c + 1)) ;; esac; done < "$1"; printf '%s' "$c"; }

got="$(printf '%s' "$n_json" | bash "$n_probe" "$n_lib" 2>"$fix/n-err1")"
if [ "$got" = "[$n_json]" ] && [ "$(n_count "$fix/n-err1")" = 0 ]; then ok 'stdin.sh: a pipe is read whole' piped; else bad 'stdin.sh: a pipe is read whole' "$got" "[$n_json]"; fi
got="$(bash "$n_probe" "$n_lib" < "$fix/noinput-payload.json" 2>"$fix/n-err1")"
if [ "$got" = "[$n_json]" ] && [ "$(n_count "$fix/n-err1")" = 0 ]; then ok 'stdin.sh: a file redirect is read whole' redirected; else bad 'stdin.sh: a file redirect is read whole' "$got" "[$n_json]"; fi
got="$(printf '%s' "$n_json" | hook_payload_timeout=2 bash "$n_probe" "$n_lib" 2>"$fix/n-err1")"
if [ "$got" = "[$n_json]" ]; then ok 'stdin.sh timeout: a bounded read returns the payload' bounded; else bad 'stdin.sh timeout: a bounded read returns the payload' "$got" "[$n_json]"; fi

: > "$fix/noinput-empty"; rm -rf "$n_tmp/claude-rule-gate"
got="$(TMPDIR="$n_tmp" n_twice "$fix/noinput-empty" bash "$n_probe" "$n_lib")"
if [ "$(n_count "$fix/n-err1")" = 1 ] && [ "$(n_count "$fix/n-err2")" = 0 ]; then ok 'stdin.sh: an empty payload warns once per session' 1/0; else bad 'stdin.sh: an empty payload warns once per session' "$(n_count "$fix/n-err1")/$(n_count "$fix/n-err2")" '1/0'; fi
case "$got" in *'{"systemMessage":"warning: hook probe-stdin.sh read no input, running fail-open (platform='*'"}'*) ok 'stdin.sh: the warning is also a systemMessage' json ;;
  *) bad 'stdin.sh: the warning is also a systemMessage' "$got" systemMessage ;; esac
rm -rf "$n_tmp/claude-rule-gate"
got="$(TMPDIR="$n_tmp" n_twice "$fix/noinput-empty" env hook_payload_quiet=1 bash "$n_probe" "$n_lib")"
case "$got" in *systemMessage*) bad 'stdin.sh quiet: stdout stays free of a second JSON object' "$got" 'no systemMessage' ;; *) ok 'stdin.sh quiet: stdout stays free of a second JSON object' quiet ;; esac
if [ "$(n_count "$fix/n-err1")" = 1 ]; then ok 'stdin.sh quiet: stderr still warns' warned; else bad 'stdin.sh quiet: stderr still warns' "$(n_count "$fix/n-err1")" 1; fi
# A marker folder that cannot be made: the warning repeats and nothing aborts.
: > "$fix/n-afile"
TMPDIR="$fix/n-afile/sub" n_twice "$fix/noinput-empty" bash "$n_probe" "$n_lib" >/dev/null
if [ "$(n_count "$fix/n-err1")" = 1 ] && [ "$(n_count "$fix/n-err2")" = 1 ]; then ok 'stdin.sh: an unwritable marker folder repeats the warning' 1/1; else bad 'stdin.sh: an unwritable marker folder repeats the warning' "$(n_count "$fix/n-err1")/$(n_count "$fix/n-err2")" '1/1'; fi

TMPDIR="$fix/n-afile/sub" bash "$hooks/guard-kill.sh" < "$fix/noinput-empty" >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ]; then ok 'guard-kill.sh: an unwritable marker folder still ends fail-open' rc=0; else bad 'guard-kill.sh: an unwritable marker folder still ends fail-open' "rc=$rc" rc=0; fi

n_hooks="guard-kill record-rule-read remind-before-compact require-receipt require-rule-read restore-compact-state save-compact-state read-confirm"
for h in $n_hooks; do
  rm -rf "$n_tmp/claude-rule-gate"
  run_h() { TMPDIR="$n_tmp" CLAUDE_PROJECT_DIR="$n_proj" bash "$hooks/$h.sh"; }
  got="$(TMPDIR="$n_tmp" n_twice "$fix/noinput-empty" run_h)"
  if [ "$(n_count "$fix/n-err1")" = 1 ] && [ "$(n_count "$fix/n-err2")" = 0 ] && n_marker "$h"; then
    ok "$h.sh: no input warns once, then stays quiet" 1/0
  else bad "$h.sh: no input warns once, then stays quiet" "$(n_count "$fix/n-err1")/$(n_count "$fix/n-err2")" '1/0'; fi
  case "$h" in
    read-confirm) # its stdout is its own receipt object per run, never joined by a second one
      if [ "$(printf '%s' "$got" | jq -s 'map(select(has("hookSpecificOutput") and has("systemMessage"))) | length' 2>/dev/null)" = 2 ] \
         && [ "$(printf '%s' "$got" | jq -s 'length' 2>/dev/null)" = 2 ]; then ok "$h.sh: its stdout carries the receipt only" 2; else bad "$h.sh: its stdout carries the receipt only" "$got" 2; fi ;;
    *) if has_text '"systemMessage":"warning: hook '"$h"'.sh read no input' "$got"; then ok "$h.sh: the warning reaches the session as a systemMessage" json; else bad "$h.sh: the warning reaches the session as a systemMessage" "$got" systemMessage; fi ;;
  esac
  rm -rf "$n_tmp/claude-rule-gate"
  printf '%s' "$n_json" | run_h >/dev/null 2>"$fix/n-err1"
  if [ "$(n_count "$fix/n-err1")" = 0 ]; then ok "$h.sh: a piped payload is no empty read" none; else bad "$h.sh: a piped payload is no empty read" warned none; fi
  run_h < "$fix/noinput-payload.json" >/dev/null 2>"$fix/n-err1"
  if [ "$(n_count "$fix/n-err1")" = 0 ]; then ok "$h.sh: a redirected payload is no empty read" none; else bad "$h.sh: a redirected payload is no empty read" warned none; fi
done
if [ ! -e "$repo_root/.agent/state/n488-restore.md" ] && ! grep -qs '"session":"n488"' "$repo_root/.agent/state/cuts.jsonl"; then
  ok 'hooks: the state of the payload session stays out of the repo' clean
else bad 'hooks: the state of the payload session stays out of the repo' "$repo_root/.agent/state" 'nothing of n488'; fi

# A terminal on stdin is a hand call (/read-check): no payload, no warning. Needs a pty and python3.
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) tty_skip="a Windows bash: no pty" ;; *) tty_skip="" ;; esac
[ -n "$tty_skip" ] || python3 -c 'import pty' >/dev/null 2>&1 || tty_skip="python3 has no pty"
if [ -z "$tty_skip" ]; then
  for h in $n_hooks; do
    got="$(TMPDIR="$n_tmp" CLAUDE_PROJECT_DIR="$n_proj" python3 -c '
import pty, sys
sys.exit(pty.spawn(["bash", sys.argv[1]]) >> 8)' "$hooks/$h.sh" 2>&1 < /dev/null)"
    case "$got" in *"read no input"*) bad "$h.sh: a terminal on stdin is a hand call" "$got" 'no warning' ;; *) ok "$h.sh: a terminal on stdin is a hand call" quiet ;; esac
  done
else
  echo "  skip terminal cases                                     ($tty_skip)"
fi

# Without its lib a hook still reads its payload (plain `cat`) instead of passing on an empty one.
mkdir -p "$fix/nolib"; cp "$hooks/guard-kill.sh" "$fix/nolib/guard-kill.sh"
got="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"kill -9 1"}}' | bash "$fix/nolib/guard-kill.sh" 2>&1)"
case "$got" in *'"permissionDecision":"deny"'*) ok 'guard-kill.sh without lib/stdin.sh still judges the call' deny ;; *) bad 'guard-kill.sh without lib/stdin.sh still judges the call' "$got" deny ;; esac

finish
