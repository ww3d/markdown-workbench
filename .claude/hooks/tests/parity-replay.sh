#!/usr/bin/env bash
# One recorded hook call, run twice from the same markers (parity.sh): through the entry's bash hooks one by
# one, and through pb-hook. Sourced by parity.sh; parity-record.sh also runs it as a program for an entry that
# compares at the call.
# Takes from the environment: PARITY_ENTRY (the pb-hook subcommand), PARITY_FILES (its bash hooks, in order),
# PARITY_REAL (their folder), PARITY_PATH (the PATH of the run, for the programs of the comparison itself).

# The tools each bash hook's settings entry matched: only those started it.
matches() { # hook, tool
  case "$1" in
    require-rule-read.sh) [[ $2 =~ ^(Bash|PowerShell|Write|Edit|NotebookEdit|Agent|Task|Workflow|Skill|mcp__.*[Gg]it[Hh]ub.*)$ ]] ;;
    guard-kill.sh) [[ $2 =~ ^(Bash|PowerShell)$ ]] ;;
    guard-shared-tmp.sh) [[ $2 =~ ^(Bash|PowerShell|Write|Edit|NotebookEdit)$ ]] ;;
    record-rule-read.sh) [[ $2 == Read ]] ;;
    remind-before-compact.sh) true ;;
    *) false ;;
  esac
}
# Both sides run from the same stage folder, so a path in an answer or a marker reads the same.
stage_run() { # box, stage, command... -> runs it on the box's input, markers and environment
  local box="$1" stage="$2"; shift 2
  rm -rf "$stage/tmp" "$stage/log"; mkdir -p "$stage/tmp" "$stage/log"
  if [ -d "$box/gate" ]; then cp -R "$box/gate" "$stage/tmp/claude-rule-gate"; fi
  (
    for v in $(compgen -e); do case "$v" in CLAUDE_* | PLAYBOOK_* | GUARD_* | SS_* | STATE_CACHE_DIR | TICKS_* | GH_DOUBLE_WORLD | ANTHROPIC_MODEL | PB_HOOK_CALLER | TMPDIR | TMP | TEMP) unset "$v" ;; esac; done
    # shellcheck source=/dev/null
    . "$box/env" 2>/dev/null
    if [ -n "${PARITY_BASH:-}" ]; then export CLAUDE_CODE_GIT_BASH_PATH="${CLAUDE_CODE_GIT_BASH_PATH:-$PARITY_BASH}"; fi
    for v in TMPDIR TMP TEMP; do if [ -n "${!v:-}" ]; then export "$v=$stage/tmp"; fi; done
    if [ -n "${PLAYBOOK_TMP_GUARD_LOG:-}" ]; then export PLAYBOOK_TMP_GUARD_LOG="$stage/log/tmp-guard"; fi
    if [ -n "${GUARD_KILL_TRACE:-}" ]; then export GUARD_KILL_TRACE="$stage/log/trace"; fi
    # A report keeps a cache; without a folder of the case's own it would be the user's.
    [ "$PARITY_ENTRY" != stop ] || export STATE_CACHE_DIR="${STATE_CACHE_DIR:-$stage/log/state-cache}"
    # Claude Code on Windows names folders in drive form. Git Bash's own form would reach pb-hook translated and
    # the bash hooks untranslated, so both sides get the drive form from the start.
    case "${OSTYPE:-}" in
      msys* | cygwin*)
        for v in $(compgen -e); do
          case "$v" in
            PLAYBOOK_* | GUARD_* | CLAUDE_* | STATE_CACHE_DIR | TMPDIR | TMP | TEMP) if [[ ${!v} == /* ]]; then export "$v=$(PATH="${PARITY_PATH:-$PATH}" cygpath -m "${!v}")"; fi ;;
          esac
        done
        ;;
    esac
    "$@" < "$box/input"
  )
}
# Both sides of a stop call write the project's state folder, and the real hook runs after them: only a project
# inside the test run's folder is compared, never a checkout.
project_state() { # box -> its state folder; 1 where nothing is to keep, 2 where the project lies outside
  [ "$PARITY_ENTRY" = stop ] || return 1
  (
    # shellcheck source=/dev/null
    . "$1/env" 2>/dev/null
    root="$(cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null && pwd -P)" || exit 1
    scope="$(cd "$PARITY_SCOPE" && pwd -P)" || exit 2
    case "$root/" in "$scope"/*) printf '%s' "$root/.agent/state" ;; *) [ ! -d "$root/.agent/state" ] || exit 2; exit 1 ;; esac
  )
}
# The folder as the call found it: kept before the first side, put back after each.
keep_state() { # state, stage
  rm -rf "$2/kept"; mkdir -p "$2/kept"
  if [ -d "$1" ]; then cp -Rp "$1" "$2/kept/state"; fi
}
put_back_state() { # state, stage -> what the side left there lies under the stage's log
  if [ -d "$1" ]; then cp -R "$1" "$2/log/project"; fi
  rm -rf "$1"
  if [ -d "$2/kept/state" ]; then cp -Rp "$2/kept/state" "$1"; fi
}
# What a call left behind: every file of the stage, times and process numbers read alike, in the order of the
# names read that way.
effects() { # stage
  # One reader for all files: a stage can hold hundreds of markers, and a process per file costs seconds.
  # post-tool writes token counts that have to agree: there only the time of a look reads alike.
  local numbers='[0-9]{5,}'
  [ "$PARITY_ENTRY" != post-tool ] || numbers='1[789][0-9]{8}'
  find "$1/tmp" "$1/log" -type f 2>/dev/null | awk -v root="$1/" -v numbers="$numbers" '{
    name = substr($0, length(root) + 1); text = ""
    # The no-input marker is keyed by the parent process, which differs between the two sides.
    sub(/noinput-pid[0-9]+/, "noinput-pid", name)
    while ((getline line < $0) > 0) {
      # A report counts seconds up to now, and the second side runs later than the first. Before the other
      # numbers: mawk may leave the last digits of a long one standing.
      gsub(/"(secondsToFree|compact\.restore|chat)":[0-9]+/, "\"seconds\":N", line)
      gsub(/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?/, "T", line); gsub(numbers, "N", line)
      text = text line " "
    }
    close($0); print name ": " text
  }' | LC_ALL=C sort
}
answer() { # output files... -> event, decision, reasons, hints and messages as one object
  cat "$@" | jq -s -c '{
    events: ([.[].hookSpecificOutput | objects | .hookEventName] | unique),
    said: any(.[]; has("systemMessage")),
    deny: any(.[]; .hookSpecificOutput.permissionDecision == "deny"),
    reason: [.[].hookSpecificOutput.permissionDecisionReason // empty] | join("\n\n"),
    hint: [.[].hookSpecificOutput.additionalContext // empty] | join("\n\n"),
    message: [.[].systemMessage // empty] | join("\n")}' | tr -d '\r'
}
# On Windows pb-hook is a native program that starts bash through Git's starter: the hooks one by one start
# the same way, so both sides get the same environment.
starter="$BASH"
case "${OSTYPE:-}" in msys* | cygwin*) starter="$(cygpath -m /)/bin/bash.exe" ;; esac
replay() { # box, stage, program -> 0 where both sides agree, else both on stdout
  local box="$1" stage="$2" tool g rc=0 scripts pb state kind=0
  state="$(project_state "$box")" || kind=$?
  # A project outside with a state folder of its own: running it twice more would write into it.
  # A case marks a call that pb-hook cannot answer alike: it tests a program only the script starts.
  if [ "$kind" = 2 ] || grep -q '^export PLAYBOOK_PARITY_SKIP=' "$box/env"; then : > "$box/skipped"; return 0; fi
  tool="$(jq -r '.tool_name // ""' "$box/input" 2>/dev/null | tr -d '\r')"
  mkdir -p "$stage/out"; rm -f "$stage/out"/*
  : > "$stage/out/none"; : > "$stage/out/err"
  # The hooks share the markers, so each starts from what the one before left, as in one session.
  cat > "$stage/chain.sh" <<'EOF'
input="$(cat; printf .)"; real="$1"; out="$2"; shift 2
for g in "$@"; do
  printf '%s' "${input%.}" | "$BASH" "$real/$g" > "$out/$g.out" 2>> "$out/err" || { c=$?; [ "$c" = 2 ] || echo "$g $c" >> "$out/failed"; echo "$c" >> "$out/codes"; }
done
EOF
  local run=()
  for g in $PARITY_FILES; do
    # An input that names no tool is no matcher's business: every hook says what it does with it.
    if [ -z "$tool" ] || matches "$g" "$tool"; then run+=("$g"); fi
  done
  [ -z "$state" ] || keep_state "$state" "$stage"
  stage_run "$box" "$stage" "$starter" "$stage/chain.sh" "$PARITY_REAL" "$stage/out" "${run[@]}"
  [ -z "$state" ] || put_back_state "$state" "$stage"
  grep -qx 2 "$stage/out/codes" 2>/dev/null && rc=2
  # In the order pb-hook joins them.
  local outs=()
  for g in "${run[@]}"; do outs+=("$stage/out/$g.out"); done
  scripts="rc=$rc $(answer "$stage/out/none" "${outs[@]}" 2>/dev/null)
$(cat "$stage/out/err")
$(effects "$stage")"
  # A PostToolUse or Stop hook that fails with another code than 2 has to show.
  if [ "$PARITY_ENTRY" != pre-tool ] &&[ -s "$stage/out/failed" ]; then scripts+=$'\n'"$(cat "$stage/out/failed")"; fi
  # A case may narrow PATH until it holds no bash. The hooks one by one start by their full path, so pb-hook is
  # named the same one.
  rc=0; PARITY_BASH="$starter" stage_run "$box" "$stage" "$3" "$PARITY_ENTRY" > "$stage/pb.out" 2> "$stage/pb.err" || rc=$?
  [ -z "$state" ] || put_back_state "$state" "$stage"
  pb="rc=$rc $(answer "$stage/pb.out")
$(cat "$stage/pb.err")
$(effects "$stage")"
  [ "$scripts" = "$pb" ] && return 0
  printf -- '--- %s (%s)\n%s\n< bash hooks, > pb-hook\n' "$box" "$tool" "$(head -c 400 "$box/input")"
  grep -E '^export (CLAUDE_|ANTHROPIC_|PLAYBOOK_|GUARD_)' "$box/env"
  sed -n 's/^export PATH=\([^:]*\).*/PATH starts with \1/p' "$box/env"
  diff <(printf '%s\n' "$scripts") <(printf '%s\n' "$pb") | cut -c1-600
  return 1
}

# Run as a program: compare the one box now, while the files its input names still stand as the hook sees them.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  replay "$1" "$1/stage" "$PARITY_PROGRAM" > "$1/diff" 2>&1 || : > "$1/differs"
  [ -e "$1/skipped" ] || : > "$1/done"
  rm -rf "$1/stage"
fi
