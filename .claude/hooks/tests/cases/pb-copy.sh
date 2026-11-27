#!/usr/bin/env bash
# Hook suite section: the guards and the turn-end hook place a missing copy of pb-hook (ww3d/playbook#734)
# Run alone: bash .claude/hooks/tests/cases/pb-copy.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# A session that started before the program was checked in has no copy; the next entry that names the program
# would block every call. Each of these hooks runs anyway and places it on the side.
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== pb-hook: a hook places the missing copy beside the checked-in programs =="
pc="$fix/pb-copy"; pcbin="$pc/bin"; mkdir -p "$pcbin/win-x64" "$pcbin/linux-x64" "$pc/tmp"
printf 'windows program\n' > "$pcbin/win-x64/pb-hook.exe"
printf 'linux program\n' > "$pcbin/linux-x64/pb-hook"
pc_run() { # hook, OSTYPE the hook sees
  printf '{"session_id":"pb-copy","tool_name":"Read","tool_input":{}}' |
    OSTYPE="$2" PLAYBOOK_PB_BIN="$pcbin" TMPDIR="$pc/tmp" CLAUDE_PROJECT_DIR="$pc" bash "$hooks/$1" 2>&1
}
pc_names() { ( cd "$pcbin" && printf '%s ' pb-hook* ) }
# What a hook says about the other platform (its temp folder has the host's form) is not judged here.
case "$OSTYPE" in msys* | cygwin*) pc_host=msys ;; *) pc_host=linux-gnu ;; esac
for h in require-rule-read.sh guard-kill.sh guard-shared-tmp.sh require-receipt.sh place-pb-copy.sh; do
  for os in msys linux-gnu; do
    if [ "$os" = msys ]; then file=pb-hook.exe from=win-x64; else file=pb-hook from=linux-x64; fi
    rm -f "$pcbin/pb-hook" "$pcbin/pb-hook.exe"
    out="$(pc_run "$h" "$os")"; rc=$?
    if [ "$os" = "$pc_host" ]; then expect "$h, $os: the call passes without output" '0:' "$rc:$out"
    else expect "$h, $os: the call passes" 0 "$rc"; fi
    # By the names in the folder: Git Bash answers -e pb-hook with yes where only pb-hook.exe lies.
    expect "$h, $os: the platform's copy lies beside the programs" "$file " "$(pc_names)"
    expect "$h, $os: it is the checked-in program" "$(< "$pcbin/$from/$file")" "$(cat "$pcbin/$file" 2>/dev/null)"
  done
done

echo "== pb-hook: a copy that is there stays, whatever it holds; without a program nothing happens =="
rm -f "$pcbin/pb-hook" "$pcbin/pb-hook.exe"; printf 'older copy\n' > "$pcbin/pb-hook"
pc_run guard-kill.sh linux-gnu >/dev/null
expect 'an older copy is left to the session start and the program itself' 'older copy' "$(< "$pcbin/pb-hook")"
rm -f "$pcbin/pb-hook" "$pcbin/linux-x64/pb-hook"
out="$(pc_run guard-kill.sh linux-gnu)"; rc=$?
expect 'no checked-in program: the call passes' '0:' "$rc:$out"
expect 'no checked-in program: no copy and no leftover' 'pb-hook* ' "$(pc_names)"

finish
