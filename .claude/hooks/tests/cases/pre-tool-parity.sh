#!/usr/bin/env bash
# Hook suite section: pb-hook pre-tool answers like the three bash guards (ww3d/playbook#734)
# Run alone: bash .claude/hooks/tests/cases/pre-tool-parity.sh [section ...]
#   all sections: bash .claude/hooks/tests/run-tests.sh
# The named sections (default: every case file of the three guards) run once with a recorder in each guard's
# place. Every recorded call then runs twice from the same markers: through the three guards one by one, and
# through pb-hook. PB_HOOK_BIN names another program than the checked-in one; PARITY_PART=<i>/<n> replays only
# that slice of the recorded calls, for a section too long for one run.
# PARITY_WORK=<folder> keeps the recording there: a later run replays from it without recording again, and
# PARITY_PART=0/1 records alone.
# On Windows a run that names no section replays only a share, so the whole suite stays within its limit: the
# first 20 calls of require-rule-read-review-post, and from the sections listed for it every call whose input
# holds a Windows form (drive or Git Bash path, temp folder, program name). PARITY_FULL=1 replays everything
# there too; Linux always does.
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

guards=(require-rule-read.sh guard-kill.sh guard-shared-tmp.sh)
case "${OSTYPE:-}" in
  msys* | cygwin*) program="${PB_HOOK_BIN:-$hooks/bin/win-x64/pb-hook.exe}" ;;
  *) program="${PB_HOOK_BIN:-$hooks/bin/linux-x64/pb-hook}" ;;
esac
par="${PARITY_WORK:-$fix/parity}"; real="$par/real"; mirror="$par/mirror"; corpus="$par/corpus"
mkdir -p "$real/bin" "$mirror" "$corpus" "$par/own"
cp -R "$hooks"/*.sh "$hooks/lib" "$real/"
cp -R "$real/." "$mirror/"
for g in "${guards[@]}"; do cp "$here/parity-record.sh" "$mirror/$g"; done
cp "$program" "$real/bin/${program##*/}"
# Fixtures of their own: the harness copies that folder, so it must not hold this one.
fixtures="${HOOK_TESTS_FIX:-}"
if [ -z "$fixtures" ]; then
  fixtures="$par/fixtures"; mkdir -p "$fixtures"
  bash "$here/mkfixtures.sh" "$fixtures" >/dev/null || { echo "mkfixtures.sh failed" >&2; exit 2; }
fi

echo "== pre-tool parity: record the calls of the guard sections =="
sections=("$@")
share=""
case "${OSTYPE:-}" in
  msys* | cygwin*) if [ $# -eq 0 ] && [ -z "${PARITY_FULL:-}" ]; then share=windows; fi ;;
esac
if [ -n "$share" ]; then
  sections=(guard-kill-commands guard-shared-tmp require-rule-read-review-post require-rule-read-tool-calls)
elif [ ${#sections[@]} -eq 0 ]; then
  for f in "$here"/cases/guard-kill-*.sh "$here"/cases/guard-shared-tmp*.sh "$here"/cases/require-rule-read-*.sh; do
    f="${f##*/}"; sections+=("${f%.sh}")
  done
fi
if [ -f "$par/recorded" ]; then sections=(); fi
for s in "${sections[@]}"; do
  mkdir -p "$par/own/$s" "$corpus/$s"
  # The section's own verdicts are its own run's business: here only its calls count.
  HOOK_TESTS_HOOKS="$mirror" PARITY_REAL="$real" PARITY_CORPUS="$corpus/$s" \
    HOOK_TESTS_FIX="$fixtures" HOOK_TESTS_OWN="$par/own/$s" \
    bash "$here/cases/$s.sh" > "$par/$s.log" 2>&1 &
done
wait
for s in "${sections[@]}"; do
  n=("$corpus/$s"/*/input)
  if [ -f "${n[0]}" ]; then ok "$s: calls recorded" "${#n[@]}"; else bad "$s: calls recorded" 0 'at least one'; fi
done
: > "$par/recorded"

# The tools each guard's own settings entry matched: only those started it.
matches() { # guard, tool
  case "$1" in
    require-rule-read.sh) [[ $2 =~ ^(Bash|PowerShell|Write|Edit|NotebookEdit|Agent|Task|Workflow|Skill|mcp__.*[Gg]it[Hh]ub.*)$ ]] ;;
    guard-kill.sh) [[ $2 =~ ^(Bash|PowerShell)$ ]] ;;
    *) [[ $2 =~ ^(Bash|PowerShell|Write|Edit|NotebookEdit)$ ]] ;;
  esac
}
# Both sides run from the same stage folder, so a path in an answer or a marker reads the same.
stage_run() { # box, stage, command... -> runs it on the box's input, markers and environment
  local box="$1" stage="$2"; shift 2
  rm -rf "$stage/tmp" "$stage/log"; mkdir -p "$stage/tmp" "$stage/log"
  if [ -d "$box/gate" ]; then cp -R "$box/gate" "$stage/tmp/claude-rule-gate"; fi
  (
    for v in $(compgen -e); do case "$v" in CLAUDE_* | PLAYBOOK_* | GUARD_* | TMPDIR | TMP | TEMP) unset "$v" ;; esac; done
    # shellcheck source=/dev/null
    . "$box/env" 2>/dev/null
    for v in TMPDIR TMP TEMP; do if [ -n "${!v:-}" ]; then export "$v=$stage/tmp"; fi; done
    if [ -n "${PLAYBOOK_TMP_GUARD_LOG:-}" ]; then export PLAYBOOK_TMP_GUARD_LOG="$stage/log/tmp-guard"; fi
    if [ -n "${GUARD_KILL_TRACE:-}" ]; then export GUARD_KILL_TRACE="$stage/log/trace"; fi
    # Claude Code on Windows names folders in drive form. Git Bash's own form would reach pb-hook translated and
    # the bash guards untranslated, so both sides get the drive form from the start.
    case "${OSTYPE:-}" in
      msys* | cygwin*)
        for v in $(compgen -e); do
          case "$v" in
            PLAYBOOK_* | GUARD_* | CLAUDE_* | TMPDIR | TMP | TEMP) if [[ ${!v} == /* ]]; then export "$v=$(cygpath -m "${!v}")"; fi ;;
          esac
        done
        ;;
    esac
    "$@" < "$box/input"
  )
}
# What a call left behind: every file of the stage, times and process numbers read alike.
effects() { # stage
  # One reader for all files: a stage can hold hundreds of markers, and a process per file costs seconds.
  find "$1/tmp" "$1/log" -type f 2>/dev/null | LC_ALL=C sort | awk -v root="$1/" '{
    name = substr($0, length(root) + 1); text = ""
    # The no-input marker is keyed by the parent process, which differs between the two sides.
    sub(/noinput-pid[0-9]+/, "noinput-pid", name)
    while ((getline line < $0) > 0) {
      gsub(/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?/, "T", line); gsub(/[0-9]{5,}/, "N", line)
      text = text line " "
    }
    close($0); print name ": " text
  }'
}
answer() { # output files... -> decision, reasons, hints and messages as one object
  cat "$@" | jq -s -c '{
    deny: any(.[]; .hookSpecificOutput.permissionDecision == "deny"),
    reason: [.[].hookSpecificOutput.permissionDecisionReason // empty] | join("\n\n"),
    hint: [.[].hookSpecificOutput.additionalContext // empty] | join("\n\n"),
    message: [.[].systemMessage // empty] | join("\n")}' | tr -d '\r'
}
# On Windows pb-hook is a native program that starts bash through Git's starter: the guards one by one start
# the same way, so both sides get the same environment.
starter="$BASH"
case "${OSTYPE:-}" in msys* | cygwin*) starter="$(cygpath -m /)/bin/bash.exe" ;; esac
replay() { # box, stage, program -> 0 where both sides agree, else both on stdout
  local box="$1" stage="$2" tool g rc=0 three pb
  tool="$(jq -r '.tool_name // ""' "$box/input" 2>/dev/null | tr -d '\r')"
  mkdir -p "$stage/out"; rm -f "$stage/out"/*
  : > "$stage/out/none"; : > "$stage/out/err"
  rm -rf "$stage/three"; mkdir -p "$stage/three"
  # The guards share the markers, so each starts from what the one before left, as in one session.
  cat > "$stage/chain.sh" <<'EOF'
input="$(cat; printf .)"; real="$1"; out="$2"; shift 2
for g in "$@"; do
  printf '%s' "${input%.}" | "$BASH" "$real/$g" > "$out/$g.out" 2>> "$out/err" || { c=$?; [ "$c" = 2 ] || echo "$g $c" >> "$out/failed"; echo "$c" >> "$out/codes"; }
done
EOF
  local run=()
  for g in "${guards[@]}"; do
    # An input that names no tool is no matcher's business: every guard says what it does with it.
    if [ -z "$tool" ] || matches "$g" "$tool"; then run+=("$g"); fi
  done
  stage_run "$box" "$stage" "$starter" "$stage/chain.sh" "$real" "$stage/out" "${run[@]}"
  grep -qx 2 "$stage/out/codes" 2>/dev/null && rc=2
  # In the order pb-hook joins them.
  local outs=()
  for g in "${run[@]}"; do outs+=("$stage/out/$g.out"); done
  three="rc=$rc $(answer "$stage/out/none" "${outs[@]}" 2>/dev/null)
$(cat "$stage/out/err")
$(effects "$stage")"
  stage_run "$box" "$stage" "$3" pre-tool > "$stage/pb.out" 2> "$stage/pb.err"; rc=$?
  pb="rc=$rc $(answer "$stage/pb.out")
$(cat "$stage/pb.err")
$(effects "$stage")"
  [ "$three" = "$pb" ] && return 0
  printf -- '--- %s (%s)\n%s\n< bash guards, > pb-hook\n' "$box" "$tool" "$(head -c 400 "$box/input")"
  grep -E '^export (CLAUDE_PROJECT_DIR|CLAUDE_CODE_REMOTE|PLAYBOOK_|GUARD_)' "$box/env"
  sed -n 's/^export PATH=\([^:]*\).*/PATH starts with \1/p' "$box/env"
  diff <(printf '%s\n' "$three") <(printf '%s\n' "$pb") | cut -c1-600
  return 1
}

echo "== pre-tool parity: the same answer and the same side effects =="
# Calls that differ in nothing but their random session id are one case.
cases() { # -> one folder per distinct call; with a share only the calls it holds
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
mapfile -t boxes < <(cases)
workers="${PARITY_JOBS:-$(nproc 2>/dev/null || echo 4)}"
slice="${PARITY_PART:-1/1}"; part_i="${slice%/*}"; part_n="${slice#*/}"
due=0
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
count() { cat "$@" 2>/dev/null | grep -c x; }
expect "every distinct call of the part was replayed ($slice of ${#boxes[@]})" "$due" "$(count "$par"/done-*)"
expect "calls on which pb-hook differs from the bash guards" 0 "$(count "$par"/differ-*)"
if [ -n "${PARITY_REPORT:-}" ]; then cat "$par"/diff-* > "$PARITY_REPORT" 2>/dev/null; fi
cat "$par"/diff-* 2>/dev/null | head -c 6000

# Mutation: a program that says nothing must differ on a call a guard denies.
mkdir -p "$par/mut/input.box"
printf '{"session_id":"par-mut","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"pkill -f x"}}' > "$par/mut/input.box/input"
printf 'export TMPDIR=%q\nexport PATH=%q\n' "$par/mut" "$PATH" > "$par/mut/input.box/env"
printf '#!/usr/bin/env bash\ncat >/dev/null\n' > "$par/mut/silent"; chmod +x "$par/mut/silent"
if replay "$par/mut/input.box" "$par/mut/stage" "$par/mut/silent" >/dev/null; then bad 'mutation: a silent program differs' same differs
else ok 'mutation: a silent program differs' differs; fi
if replay "$par/mut/input.box" "$par/mut/stage" "$real/bin/${program##*/}" >/dev/null; then ok 'the same call through pb-hook agrees' agrees
else bad 'the same call through pb-hook agrees' differs agrees; fi

finish
