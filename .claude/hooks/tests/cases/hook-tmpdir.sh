#!/usr/bin/env bash
# Hook suite section: the one temp folder of the hook files (ww3d/playbook#703, Frage 1755 a)
# Run alone: bash .claude/hooks/tests/cases/hook-tmpdir.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

tmplib="$hooks/lib/tempdir.sh"
td="$fix/tmpdir"; mkdir -p "$td/a" "$td/b" "$td/c"
# What the helper must say for a folder: the `D:/...` form under Git Bash, the path itself elsewhere.
want() { if command -v cygpath >/dev/null 2>&1; then cygpath -m -- "$1"; else printf '%s' "$1"; fi; }
tmp_of() { # env assignments... -> "status|hook_tmp|stderr" of one hook_tmpdir call
  env -u TMPDIR -u TMP -u TEMP -u CLAUDE_CODE_REMOTE "$@" bash -c '. "$1"; hook_tmpdir; echo "$?|$hook_tmp"' _ "$tmplib" 2>"$td/err"
}

echo "== hook_tmpdir: TMPDIR, else TMP, else TEMP, as a D:/ path under Git Bash =="
expect 'TMPDIR comes before TMP and TEMP' "0|$(want "$td/a")" "$(tmp_of TMPDIR="$td/a" TMP="$td/b" TEMP="$td/c")"
expect 'TMP comes before TEMP' "0|$(want "$td/b")" "$(tmp_of TMP="$td/b" TEMP="$td/c")"
expect 'TEMP is the last variable' "0|$(want "$td/c")" "$(tmp_of TEMP="$td/c")"
if command -v cygpath >/dev/null 2>&1; then
  got="$(tmp_of TMPDIR=/tmp)"
  case "$got" in
    0'|'[A-Za-z]:/*) ok 'a /tmp value is turned into a D:/ path' "$got" ;; # tmp-ok: the value under test
    *) bad 'a /tmp value is turned into a D:/ path' "$got" 'D:/...' ;; # tmp-ok: the value under test
  esac
fi

echo "== hook_tmpdir: nothing set =="
expect 'no variable, no cloud: status 1, no folder' '1|' "$(tmp_of)"
case "$(cat "$td/err")" in *"no TMPDIR, TMP or TEMP set"*) ok 'it says so on stderr' stderr ;; *) bad 'it says so on stderr' "$(cat "$td/err")" 'the line' ;; esac
expect 'a cloud session falls back to /tmp' '0|/tmp' "$(tmp_of CLAUDE_CODE_REMOTE=true)" # tmp-ok: under test
expect 'CLAUDE_CODE_REMOTE other than true is no cloud' '1|' "$(tmp_of CLAUDE_CODE_REMOTE=1)"

# A failing or empty `cygpath` never gives back the mount path (review round 1, R1-1): no folder, one line on stderr.
mount_tmp=/tmp # tmp-ok: the mount path under test
cyg_run() { # body of the fake cygpath -> "status|hook_tmp", the stderr in $td/err
  env -u TMP -u TEMP -u CLAUDE_CODE_REMOTE TMPDIR="$mount_tmp" \
    bash -c "OSTYPE=msys; cygpath() { $1; }; . \"\$1\"; hook_tmpdir; echo \"\$?|\$hook_tmp\"" _ "$tmplib" 2>"$td/err"
}
got="$(cyg_run 'return 1')"
expect 'a failing cygpath leaves no folder, not /tmp' '1|' "$got"
case "$(cat "$td/err")" in *"cannot be written as a Windows path"*) ok 'a failing cygpath says so on stderr' stderr ;; *) bad 'a failing cygpath says so on stderr' "$(cat "$td/err")" 'the line' ;; esac
got="$(cyg_run 'return 0')"
expect 'an empty cygpath answer leaves no folder' '1|' "$got"

# The spellings of a Windows temp folder under Git Bash are turned by string (review round 2, R2-1), cygpath stays out.
msys_of() { # variable, value -> "status|hook_tmp" with a cygpath that must not be called
  env -u TMPDIR -u TMP -u TEMP -u CLAUDE_CODE_REMOTE "$1=$2" bash -c 'OSTYPE=msys; cygpath() { return 1; }; . "$1"; hook_tmpdir; echo "$?|$hook_tmp"' _ "$tmplib" 2>/dev/null
}
for var in TMPDIR TMP TEMP; do
  expect "$var=D:/x/y stays D:/x/y" '0|D:/x/y' "$(msys_of "$var" 'D:/x/y')"
  expect "$var=D:/rc-work/x keeps its slashes" '0|D:/rc-work/x' "$(msys_of "$var" 'D:/rc-work/x')"
  expect "$var=C:\Users\a\Temp becomes C:/Users/a/Temp" '0|C:/Users/a/Temp' "$(msys_of "$var" 'C:\Users\a\Temp')"
  expect "$var=/c/Users/a becomes C:/Users/a" '0|C:/Users/a' "$(msys_of "$var" '/c/Users/a')"
  expect "$var=D:/x/ loses the trailing slash" '0|D:/x' "$(msys_of "$var" 'D:/x/')"
done

echo "== hook_mktemp makes its file and folder inside that folder (mktemp -p) =="
got="$(env -u TMP -u TEMP TMPDIR="$td/a" bash -c '. "$1"; f="$(hook_mktemp probe)"; d="$(hook_mktemp -d probe)"; echo "$f"; echo "$d"' _ "$tmplib")"
f1="${got%%$'\n'*}"; d1="${got#*$'\n'}"
mk_in="$(want "$td/a")"
if [ "${f1#"$mk_in"/probe.}" != "$f1" ] && [ -f "$f1" ]; then ok 'hook_mktemp: a file in the folder' "$f1"; else bad 'hook_mktemp: a file in the folder' "$f1" "$mk_in/probe.* as a file"; fi
if [ "${d1#"$mk_in"/probe.}" != "$d1" ] && [ -d "$d1" ]; then ok 'hook_mktemp -d: a folder in the folder' "$d1"; else bad 'hook_mktemp -d: a folder in the folder' "$d1" "$mk_in/probe.* as a folder"; fi
got="$(env -u TMPDIR -u TMP -u TEMP -u CLAUDE_CODE_REMOTE bash -c '. "$1"; hook_mktemp x 2>/dev/null; echo "rc=$?"' _ "$tmplib")"
expect 'hook_mktemp without a folder: status 1, no path' 'rc=1' "$got"

echo "== a hook without any temp variable never blocks the session =="
for h in require-rule-read record-rule-read require-receipt save-compact-state restore-compact-state remind-before-compact block-announce-end guard-shared-tmp; do
  out="$(printf '{"session_id":"tmpdir-x","tool_name":"Bash","tool_input":{"command":"gh issue create --title x"},"transcript_path":"/x/y.jsonl"}' \
    | env -u TMPDIR -u TMP -u TEMP -u CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR="$repo_root" bash "$hooks/$h.sh" 2>"$td/err-$h")"; rc=$?
  expect "$h.sh without a temp folder: exit 0, nothing denied" '0|' "$rc|$(case "$out" in *deny*|*block*) echo "$out" ;; esac)"
  if [ "$h" != require-receipt ] && [ "$h" != guard-shared-tmp ]; then # these two end before they need the folder
    case "$(cat "$td/err-$h")" in *"no TMPDIR, TMP or TEMP set"*) ok "$h.sh says so on stderr" stderr ;; *) bad "$h.sh says so on stderr" "$(cat "$td/err-$h")" "the line" ;; esac
  fi
done
# The line stays when the payload is empty too (review round 1, R1-2): the no-input warning must not swallow it.
out="$(printf '' | env -u TMPDIR -u TMP -u TEMP -u CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR="$repo_root" bash "$hooks/require-rule-read.sh" 2>&1)"
case "$out" in *"no TMPDIR, TMP or TEMP set"*) ok 'an empty payload without a temp folder still says so' stderr ;; *) bad 'an empty payload without a temp folder still says so' "$out" 'the line' ;; esac
out="$(printf '{"session_id":"tmpdir-rc","source":"startup"}' | env -u TMPDIR -u TMP -u TEMP -u CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR="$repo_root" READ_CONFIRM_REMOTE=/nonexistent bash "$hooks/read-confirm.sh" 2>/dev/null)"
case "$out" in *'[hooks ok]'*|*'additionalContext'*) ok 'read-confirm.sh still gives its report without a temp folder' report ;; *) bad 'read-confirm.sh still gives its report without a temp folder' "$out" 'the report' ;; esac

echo "== the hook files hold no bare /tmp and no bare mktemp (the number may only fall) =="
# A line counts unless it is a comment or carries `tmp-ok: <reason>`; the reason stands in the line itself.
bare_limit=0
bare="$(grep -nE '(^|[^A-Za-z0-9_.-])/tmp([^A-Za-z0-9_.-]|$)' "$hooks"/*.sh "$hooks"/lib/*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'tmp-ok:' || true)"
n_bare=0; [ -z "$bare" ] || n_bare="$(printf '%s\n' "$bare" | wc -l)"
if [ "$n_bare" -le "$bare_limit" ]; then ok 'bare /tmp lines in the hook files' "$n_bare of at most $bare_limit"; else bad 'bare /tmp lines in the hook files' "$bare" "at most $bare_limit"; fi
raw="$(grep -nE 'mktemp' "$hooks"/*.sh "$hooks"/lib/*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'tmp-ok:' | sed -E 's/hook_mktemp//g' | grep 'mktemp' | grep -vE 'mktemp[^|;)]* -p ' || true)"
if [ -z "$raw" ]; then ok 'mktemp calls without -p in the hook files' 0; else bad 'mktemp calls without -p in the hook files' "$raw" 0; fi
unused="$(grep -nE '\$\{TMPDIR:-/tmp\}|\$\{TMPDIR:-\}' "$hooks"/*.sh "$hooks"/lib/*.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v 'tmp-ok:' || true)"
if [ -z "$unused" ]; then ok 'no hook file reads TMPDIR on its own' 0; else bad 'no hook file reads TMPDIR on its own' "$unused" 0; fi

finish
