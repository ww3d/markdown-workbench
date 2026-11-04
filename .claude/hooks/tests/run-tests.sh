#!/usr/bin/env bash
#
# Behaviour tests for the hooks under .claude/hooks/: the one entry. The cases live in section files under
# cases/, one per hook and topic; this script builds the fixtures once, runs the sections in parallel and adds
# up their results (README.md beside it).
#
# Ported from a consumer repo's hook-test suite (provenance: docs/provenance.md in the playbook), which also
# covered a fourth hook, gate-actions.sh, that this repo does not carry. Every case states its expected
# verdict, and the ones that matter come in pairs: a command that must be refused next to one that must not.
# A gate is only as good as its counter-case — a suite of nothing but DENY/BLOCK lines passes just as well
# when the gate refuses everything.
#
# Usage:  bash .claude/hooks/tests/run-tests.sh [--jobs N] [section ...]
#   --jobs N   sections at once; default: the cores this process may use (nproc)
#   section    the name of a file under cases/ without .sh; default: every section
# Exit:   0 when every case holds and every section ended with its result, 1 otherwise, 2 on a usage error.
set -uo pipefail
# EPOCHREALTIME here and EPOCHSECONDS in the hooks need bash 5
[ "${BASH_VERSINFO[0]}" -ge 5 ] || { echo "bash 5 or newer needed, this is $BASH_VERSION" >&2; exit 2; }

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"

usage() { sed -n '13,16p' "$0" | sed 's/^# \{0,1\}//'; }
jobs=""; jobs_given=""; names=()
while [ $# -gt 0 ]; do
  case "$1" in
    -j|--jobs) jobs="${2:-}"; jobs_given=1; shift 2 || { usage >&2; exit 2; } ;;
    --jobs=*) jobs="${1#*=}"; jobs_given=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) names+=("$1"); shift ;;
  esac
done
[ -n "$jobs_given" ] || jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
case "$jobs" in ''|*[!0-9]*|0) echo "--jobs takes a whole number from 1: '$jobs'" >&2; exit 2 ;; esac

files=()
if [ ${#names[@]} -eq 0 ]; then
  for f in "$here"/cases/*.sh; do files+=("$f"); done
else
  for n in "${names[@]}"; do
    [ -f "$here/cases/${n%.sh}.sh" ] || { echo "no section cases/${n%.sh}.sh" >&2; exit 2; }
    # a section named twice would run twice on the same output paths; NTFS ignores case
    n="${n%.sh}"; n="${n,,}"
    [[ " ${files[*]} " != *" $here/cases/$n.sh "* ]] || { echo "section named twice: $n" >&2; exit 2; }
    files+=("$here/cases/$n.sh")
  done
fi

us() { local t="${1//[.,]/}"; printf '%s' "$((10#$t))"; } # EPOCHREALTIME -> microseconds
secs() { printf '%d.%01d' "$(($1 / 1000000))" "$(($1 % 1000000 / 100000))"; } # microseconds -> "s.d"

# One run folder under the repo's artifacts/tmp/test (run-folder.sh); TMPDIR points into it for every section.
# shellcheck source=SCRIPTDIR/run-folder.sh
. "$here/run-folder.sh"
open_run_folder "$repo_root"
run="$RUN_DIR"
trap 'rm -rf "$run"' EXIT
mkdir -p "$run/fixtures" "$run/out" "$run/own"

t_start="$(us "$EPOCHREALTIME")"
if ! bash "$here/mkfixtures.sh" "$run/fixtures" >"$run/out/mkfixtures.log" 2>&1; then
  cat "$run/out/mkfixtures.log"; echo "FAIL mkfixtures.sh: no fixtures, no run"; exit 1
fi
t_fix="$(us "$EPOCHREALTIME")"

# Larger files first: the longest sections start early, so the last job to finish is a short one.
# (arithmetic drops the blanks BSD wc pads its count with)
mapfile -t files < <(for f in "${files[@]}"; do printf '%s %s\n' "$(($(wc -c < "$f")))" "$f"; done | sort -rn | cut -d' ' -f2-)

section() { # file: runs one section, its log and its exit to the out folder
  local name t0
  name="$(basename "$1" .sh)"; t0="$EPOCHREALTIME"
  HOOK_TESTS_FIX="$run/fixtures" HOOK_TESTS_OWN="$run/own/$name" bash "$1" >"$run/out/$name.log" 2>&1
  printf '%s %s %s\n' "$?" "$t0" "$EPOCHREALTIME" >"$run/out/$name.rc"
}
# A section that measures wall time says so in its head and runs after the others, on an idle machine.
runs_alone() { # file: the marker within its first ten lines, read without a process
  local l i=0
  while ((i++ < 10)) && IFS= read -r l; do [[ $l == '# hook-tests: run alone'* ]] && return 0; done < "$1"
  return 1
}
alone=()
running=0
for f in "${files[@]}"; do
  if runs_alone "$f"; then alone+=("$f"); continue; fi
  if [ "$running" -ge "$jobs" ]; then wait -n; running=$((running - 1)); fi
  section "$f" &
  running=$((running + 1))
done
wait
for f in "${alone[@]}"; do section "$f"; done
t_end="$(us "$EPOCHREALTIME")"

pass=0; fail=0; red=(); table=()
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)
for f in "${files[@]}"; do
  name="$(basename "$f" .sh)"
  log="$run/out/$name.log"
  cat "$log" 2>/dev/null
  p=""; q=""
  while IFS=' ' read -r tag a b; do [ "$tag" = HOOK-TESTS-RESULT ] && { p="$a"; q="$b"; }; done < "$log"
  rc=""; t0=""; t1=""
  [ -f "$run/out/$name.rc" ] && read -r rc t0 t1 < "$run/out/$name.rc"
  dur="?"; [ -n "$t1" ] && dur="$(secs $(( $(us "$t1") - $(us "$t0") )))"
  if [ -z "$p" ]; then
    red+=("$name: ended without its result (exit ${rc:-none})"); table+=("$(printf '  %-40s %8s s   no result' "$name" "$dur")")
    continue
  fi
  pass=$((pass + p)); fail=$((fail + q))
  if [ "$q" -eq 0 ] && [ "${rc:-1}" != 0 ]; then red+=("$name: an error of its own (exit ${rc:-none}, no failed case)"); fi
  table+=("$(printf '  %-40s %8s s   %s ok, %s failed' "$name" "$dur" "$p" "$q")")
done

echo
echo "== time per section (jobs $jobs; fixtures $(secs $((t_fix - t_start))) s) =="
printf '%s\n' "${table[@]}"
for r in "${red[@]}"; do echo "FAIL section $r"; done
echo
printf '%s ok, %s failed, %s sections, %s red sections, %s s\n' "$pass" "$fail" "${#files[@]}" "${#red[@]}" \
  "$(secs $((t_end - t_start)))"
[ "$fail" -eq 0 ] && [ ${#red[@]} -eq 0 ]
