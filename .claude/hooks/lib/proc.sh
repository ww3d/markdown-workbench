# shellcheck shell=bash
#
# Process-table helpers sourced by guard-kill.sh and grant-kill.sh (ww3d/playbook#511, #516). Bash builtins only:
# guard-kill sources this on its slow path and pays no process start for it.
#
#   linux_stat <pid>   sets ls_ppid, ls_start (field 22 of /proc/<pid>/stat) and ls_flags; 1 when there is no
#                      such process
#   call_process       sets call_proc=<pid>:<start> of the running tool call: the process the agent host (CLAUDE_PID)
#                      started that this shell runs in; 1 when it cannot be told (ww3d/playbook#750)
#   msys_jumps         Git Bash on Windows: sets jump to the `child=ancestor` pairs (Windows ids) for
#                      lib/own-tree.ps1 - an MSYS process's Windows parent may be a stub that already exited, so its
#                      MSYS parent stands in for it

linux_stat() {
  local s f
  read -r s 2>/dev/null <"/proc/$1/stat" || return 1
  # The command name may hold spaces and brackets: the fields start after its last `) `.
  s="${s##*) }"; read -ra f <<<"$s"
  # shellcheck disable=SC2034 # the results are for the caller
  { ls_ppid="${f[1]:-0}"; ls_flags="${f[6]:-0}"; ls_start="${f[19]:-}"; }
}

msys_jumps() {
  local d p w pp
  local -A mwin=() mppid=()
  jump=""
  local restore_f=0
  [[ $- == *f* ]] && restore_f=1
  set +f
  for d in /proc/[0-9]*; do
    p="${d#/proc/}"
    read -r w 2>/dev/null <"$d/winpid" && read -r pp 2>/dev/null <"$d/ppid" && mwin[$p]="$w" mppid[$p]="$pp"
  done
  [ "$restore_f" = 0 ] || set -f
  for p in "${!mwin[@]}"; do
    pp="${mppid[$p]}"
    [ "$pp" = 1 ] || [ -z "${mwin[$pp]:-}" ] || jump+="${jump:+,}${mwin[$p]}=${mwin[$pp]}"
  done
}

# shellcheck disable=SC2034 # call_proc is for the caller
call_process() {
  local p=$$ i self ps=pwsh out jump="" id start
  call_proc=""
  [[ ${CLAUDE_PID:-} =~ ^[1-9][0-9]*$ ]] || return 1
  if [ -r "/proc/$$/winpid" ]; then
    # Git Bash on Windows: the host and its first child are Windows processes, read once by lib/own-tree.ps1.
    read -r self <"/proc/$$/winpid" || return 1
    msys_jumps
    command -v pwsh >/dev/null 2>&1 || ps=powershell
    command -v cygpath >/dev/null 2>&1 && command -v "$ps" >/dev/null 2>&1 || return 1
    out="$("$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
      -File "$(cygpath -w "${BASH_SOURCE[0]%/*}/own-tree.ps1")" -Self "$self" -Root "$CLAUDE_PID" -Call \
      ${jump:+-Jump "$jump"} 2>/dev/null)" || return 1
    read -r id start <<<"${out//$'\r'/}"
    [[ $id =~ ^[0-9]+$ && $start =~ ^[0-9]+$ ]] || return 1
    call_proc="$id:$start"; return 0
  fi
  for ((i = 0; i < 64 && p > 1; i++)); do
    linux_stat "$p" || return 1
    if [ "$ls_ppid" = "$CLAUDE_PID" ]; then call_proc="$p:$ls_start"; return 0; fi
    p="$ls_ppid"
  done
  return 1
}
