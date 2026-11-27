#!/usr/bin/env bash
# pb-hook answers like the bash hooks it takes over (ww3d/playbook#734): parity.sh <entry> [section ...]
# The entries, their bash hooks and the case files that call them stand in the list below; <entry> is also the
# pb-hook subcommand. The named sections (default: every case file of the entry) run once with a recorder in each
# hook's place. Every recorded call then runs twice from the same markers (parity-replay.sh): through the bash
# hooks one by one, and through pb-hook. PB_HOOK_BIN names another program than the checked-in one.
#   pre-tool   replays after the recording. PARITY_PART=<i>/<n> replays only that slice of the recorded calls, for
#              a section too long for one run. PARITY_WORK=<folder> keeps the recording there: a later run replays
#              from it without recording again, and PARITY_PART=0/1 records alone.
#              On Windows a run that names no section replays only a share, so the whole suite stays within its
#              limit: the first 20 calls of require-rule-read-review-post, and from the sections listed for it every
#              call whose input holds a Windows form (drive or Git Bash path, temp folder, program name).
#              PARITY_FULL=1 replays everything there too; Linux always does.
#   post-tool  compares each call as it comes: its answer comes from transcripts and project files the next case
#              rewrites. PARITY_PART=<i>/<n> compares only every nth call of a section, for one too long for one run.
#              On Windows a run that names no section compares every fifth call; PARITY_FULL=1 compares all there.
#   stop       compares as post-tool does, with the same share; a project's state folder is put back between the
#              sides, and a call whose project lies outside the run's folder and keeps a state is skipped: run it in a
#              checkout without .agent/state to compare those too.
# shellcheck source=SCRIPTDIR/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/harness.sh"

entry="${1:-}"; shift || true
at_call=""; share=""; silent=""
case "$entry" in
  pre-tool)
    files="require-rule-read.sh guard-kill.sh guard-shared-tmp.sh"
    case_files="guard-kill-*.sh guard-shared-tmp*.sh require-rule-read-*.sh"
    case "${OSTYPE:-}" in
      msys* | cygwin*)
        if [ $# -eq 0 ] && [ -z "${PARITY_FULL:-}" ]; then
          share=windows
          set -- guard-kill-commands guard-shared-tmp require-rule-read-review-post require-rule-read-tool-calls
        fi ;;
    esac
    mutation='"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"pkill -f x"}' ;;
  post-tool)
    files="record-rule-read.sh remind-before-compact.sh"
    case_files="record-rule-read.sh require-rule-read-local-rules.sh hook-stdin.sh remind-before-compact.sh remind-kind-place.sh harness-parity.sh"
    at_call=yes
    # A call compared as it came leaves nothing a later run could compare again.
    if [ -n "${PARITY_WORK:-}" ]; then echo "PARITY_WORK is for pre-tool only" >&2; exit 2; fi
    case "${OSTYPE:-}" in
      msys* | cygwin*)
        if [ $# -eq 0 ] && [ -z "${PARITY_FULL:-}" ]; then export PARITY_PART="${PARITY_PART:-1/5}"; fi ;;
    esac
    mutation='"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"x"}' ;;
  stop)
    files="require-receipt.sh"
    case_files="require-receipt.sh read-confirm.sh cut-report.sh successor-restore.sh ticks.sh ticks-bare-guard.sh \
require-rule-read-compact-lock.sh require-rule-read-receipt.sh harness-parity.sh"
    at_call=yes
    if [ -n "${PARITY_WORK:-}" ]; then echo "PARITY_WORK is for pre-tool only" >&2; exit 2; fi
    case "${OSTYPE:-}" in
      msys* | cygwin*)
        if [ $# -eq 0 ] && [ -z "${PARITY_FULL:-}" ]; then export PARITY_PART="${PARITY_PART:-1/5}"; fi ;;
    esac
    # These cases start other hooks around the check, never the check itself.
    silent="read-confirm ticks-bare-guard require-rule-read-receipt"
    # A transcript of an unknown shape, in the call's own folder: the script answers it.
    mutation='"hook_event_name":"Stop","transcript_path":"t.jsonl"' ;;
  *) echo "usage: parity.sh pre-tool|post-tool|stop [section ...]" >&2; exit 2 ;;
esac
case "${OSTYPE:-}" in
  msys* | cygwin*) program="${PB_HOOK_BIN:-$hooks/bin/win-x64/pb-hook.exe}" ;;
  *) program="${PB_HOOK_BIN:-$hooks/bin/linux-x64/pb-hook}" ;;
esac
par="${PARITY_WORK:-$fix/parity}"; real="$par/real"; mirror="$par/mirror"; corpus="$par/corpus"
mkdir -p "$real/bin" "$mirror" "$corpus" "$par/own"
cp -R "$hooks"/*.sh "$hooks/lib" "$real/"
cp -R "$real/." "$mirror/"
for g in $files; do cp "$here/parity-record.sh" "$mirror/$g"; done
cp "$program" "$real/bin/${program##*/}"
export PARITY_ENTRY="$entry" PARITY_FILES="$files" PARITY_REAL="$real" PARITY_PATH="$PATH" PARITY_SCOPE="$par"
# shellcheck source=SCRIPTDIR/parity-replay.sh
. "$here/parity-replay.sh"
# Fixtures of their own: the harness copies that folder, so it must not hold this one.
fixtures="${HOOK_TESTS_FIX:-}"
if [ -z "$fixtures" ]; then
  fixtures="$par/fixtures"; mkdir -p "$fixtures"
  bash "$here/mkfixtures.sh" "$fixtures" >/dev/null || { echo "mkfixtures.sh failed" >&2; exit 2; }
fi

echo "== $entry parity: record the calls of the hook sections =="
sections=("$@")
if [ ${#sections[@]} -eq 0 ]; then
  for pattern in $case_files; do
    # shellcheck disable=SC2231 # the pattern is meant to expand
    for f in "$here"/cases/$pattern; do f="${f##*/}"; sections+=("${f%.sh}"); done
  done
fi
if [ -f "$par/recorded" ]; then sections=(); fi
compare=()
if [ -n "$at_call" ]; then
  compare=(PARITY_COMPARE="$here/parity-replay.sh" PARITY_PROGRAM="$real/bin/${program##*/}")
fi
for s in "${sections[@]}"; do
  mkdir -p "$par/own/$s" "$corpus/$s"
  # The section's own verdicts are its own run's business: here only its calls count.
  env "${compare[@]}" HOOK_TESTS_HOOKS="$mirror" PARITY_CORPUS="$corpus/$s" \
    HOOK_TESTS_FIX="$fixtures" HOOK_TESTS_OWN="$par/own/$s" \
    bash "$here/cases/$s.sh" > "$par/$s.log" 2>&1 &
done
wait
for s in "${sections[@]}"; do
  n=("$corpus/$s"/*/input)
  [ -f "${n[0]}" ] || n=()
  case " $silent " in
    *" $s "*) expect "$s: no call of the entry's hooks" 0 "${#n[@]}" ;;
    *) if [ ${#n[@]} -gt 0 ]; then ok "$s: calls recorded" "${#n[@]}"; else bad "$s: calls recorded" 0 'at least one'; fi ;;
  esac
  if [ -e "$corpus/$s/lost" ]; then bad "$s: every call filed" lost filed; fi
done
: > "$par/recorded"

# Calls that differ in nothing but their random session id are one case.
distinct_calls() { # -> one folder per distinct call; with a share only the calls it holds
  find "$corpus" -mindepth 3 \( -name input -o -name env -o -path '*/gate/*' \) | LC_ALL=C sort |
    awk -v root="$corpus/" -v share="$share" '
      function flush() {
        # A UserPromptExpansion event is not one of pb-hook pre-tool.
        if (box != "" && !skip && !(key in seen)) {
          seen[key] = 1
          if (share == "") print box
          else if (box ~ /\/require-rule-read-review-post\/[^\/]*$/ && sampled < 20) { sampled++; print box }
          else if (windows) print box
        }
      }
      {
        split(substr($0, length(root) + 1), part, "/"); folder = root part[1] "/" part[2]
        if (folder != box) { flush(); box = folder; key = ""; skip = 0; windows = 0 }
        if (part[3] == "gate") { name = part[4]; sub(/^[^-]*-[^-]*-[^-]*-[^-]*/, "", name); key = key "\n" name; next }
        while ((getline line < $0) > 0) {
          if (part[3] == "input") {
            if (line ~ /"hook_event_name":"UserPromptExpansion"/) skip = 1
            sub(/"session_id":"[^"]*"/, "", line)
            own = line; gsub(/"(cwd|transcript_path)":"[^"]*"/, "", own)
            if (own ~ /(^|[^A-Za-z])[A-Za-z]:[\\/]|[ "=]\/[a-z]\/|AppData|TMPDIR|TEMP|TMP|[\\/]([Tt]emp|tmp)|\.exe/) windows = 1
          } else if (line ~ /^cd |TMP|TEMP/) continue
          key = key "\n" line
        }
        close($0)
      }
      END { flush() }'
}
count() { cat "$@" 2>/dev/null | grep -c x; }
replay_recorded() { # replays the distinct calls with several workers -> diffs
  local boxes workers slice part_i part_n due=0 i w
  mapfile -t boxes < <(distinct_calls)
  workers="${PARITY_JOBS:-$(nproc 2>/dev/null || echo 4)}"
  slice="${PARITY_PART:-1/1}"; part_i="${slice%/*}"; part_n="${slice#*/}"
  for ((i = 0; i < ${#boxes[@]}; i++)); do if (((i / workers) % part_n == part_i - 1)); then due=$((due + 1)); fi; done
  rm -f "$par"/done-* "$par"/differ-* "$par"/diff-*
  for ((w = 0; w < workers; w++)); do
    (
      for ((i = w; i < ${#boxes[@]}; i += workers)); do
        (((i / workers) % part_n == part_i - 1)) || continue
        replay "${boxes[i]}" "$par/stage-$w" "$real/bin/${program##*/}" >> "$par/diff-$w" || echo x >> "$par/differ-$w"
        echo x >> "$par/done-$w"
      done
    ) &
  done
  wait
  expect "every distinct call of the part was replayed ($slice of ${#boxes[@]})" "$due" "$(count "$par"/done-*)"
  expect "calls on which pb-hook differs from the bash hooks" 0 "$(count "$par"/differ-*)"
  diffs=("$par"/diff-*)
}
compared_at_call() { # the results the recorder left in each box -> diffs
  local calls compared skipped differing d
  calls=("$corpus"/*/*/input); compared=("$corpus"/*/*/done); differing=("$corpus"/*/*/differs)
  skipped=("$corpus"/*/*/skipped)
  [ -e "${calls[0]}" ] || calls=()
  [ -e "${compared[0]}" ] || compared=()
  [ -e "${differing[0]}" ] || differing=()
  [ -e "${skipped[0]}" ] || skipped=()
  expect "every recorded call of the part was compared (${PARITY_PART:-1/1} of ${#calls[@]}, ${#skipped[@]} skipped)" \
    "$((${#calls[@]} - ${#skipped[@]}))" "${#compared[@]}"
  expect "calls on which pb-hook differs from the bash hooks" 0 "${#differing[@]}"
  diffs=()
  for d in "${differing[@]}"; do diffs+=("${d%differs}diff"); done
}

echo "== $entry parity: the same answer and the same side effects =="
if [ -n "$at_call" ]; then compared_at_call; else replay_recorded; fi
if [ -n "${PARITY_REPORT:-}" ]; then cat /dev/null "${diffs[@]}" > "$PARITY_REPORT" 2>/dev/null; fi
cat /dev/null "${diffs[@]}" 2>/dev/null | head -c 6000

# Mutation: a program that says nothing must differ on a call the bash hooks answer.
mkdir -p "$par/mut/input.box"
printf '{"session_id":"par-mut",%s}' "$mutation" > "$par/mut/input.box/input"
printf 'cd %q\nexport TMPDIR=%q\nexport PATH=%q\n' "$par/mut" "$par/mut" "$PATH" > "$par/mut/input.box/env"
printf '{}\n' > "$par/mut/t.jsonl"
printf '#!/usr/bin/env bash\ncat >/dev/null\n' > "$par/mut/silent"; chmod +x "$par/mut/silent"
if replay "$par/mut/input.box" "$par/mut/stage" "$par/mut/silent" >/dev/null; then bad 'mutation: a silent program differs' same differs
else ok 'mutation: a silent program differs' differs; fi
if replay "$par/mut/input.box" "$par/mut/stage" "$real/bin/${program##*/}" >/dev/null; then ok 'the same call through pb-hook agrees' agrees
else bad 'the same call through pb-hook agrees' differs agrees; fi

finish
