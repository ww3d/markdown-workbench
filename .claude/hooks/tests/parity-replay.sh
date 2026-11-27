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
    for v in $(compgen -e); do case "$v" in CLAUDE_* | PLAYBOOK_* | GUARD_* | ANTHROPIC_MODEL | PB_HOOK_CALLER | TMPDIR | TMP | TEMP) unset "$v" ;; esac; done
    # shellcheck source=/dev/null
    . "$box/env" 2>/dev/null
    if [ -n "${PARITY_BASH:-}" ]; then export CLAUDE_CODE_GIT_BASH_PATH="${CLAUDE_CODE_GIT_BASH_PATH:-$PARITY_BASH}"; fi
    for v in TMPDIR TMP TEMP; do if [ -n "${!v:-}" ]; then export "$v=$stage/tmp"; fi; done
    if [ -n "${PLAYBOOK_TMP_GUARD_LOG:-}" ]; then export PLAYBOOK_TMP_GUARD_LOG="$stage/log/tmp-guard"; fi
    if [ -n "${GUARD_KILL_TRACE:-}" ]; then export GUARD_KILL_TRACE="$stage/log/trace"; fi
    # Claude Code on Windows names folders in drive form. Git Bash's own form would reach pb-hook translated and
    # the bash hooks untranslated, so both sides get the drive form from the start.
    case "${OSTYPE:-}" in
      msys* | cygwin*)
        for v in $(compgen -e); do
          case "$v" in
            PLAYBOOK_* | GUARD_* | CLAUDE_* | TMPDIR | TMP | TEMP) if [[ ${!v} == /* ]]; then export "$v=$(PATH="${PARITY_PATH:-$PATH}" cygpath -m "${!v}")"; fi ;;
          esac
        done
        ;;
    esac
    "$@" < "$box/input"
  )
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
  local box="$1" stage="$2" tool g rc=0 scripts pb
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
  stage_run "$box" "$stage" "$starter" "$stage/chain.sh" "$PARITY_REAL" "$stage/out" "${run[@]}"
  grep -qx 2 "$stage/out/codes" 2>/dev/null && rc=2
  # In the order pb-hook joins them.
  local outs=()
  for g in "${run[@]}"; do outs+=("$stage/out/$g.out"); done
  scripts="rc=$rc $(answer "$stage/out/none" "${outs[@]}" 2>/dev/null)
$(cat "$stage/out/err")
$(effects "$stage")"
  # A PostToolUse hook that fails with another code than 2 has to show.
  if [ "$PARITY_ENTRY" = post-tool ] && [ -s "$stage/out/failed" ]; then scripts+=$'\n'"$(cat "$stage/out/failed")"; fi
  # A case may narrow PATH until it holds no bash. The hooks one by one start by their full path, so pb-hook is
  # named the same one.
  rc=0; PARITY_BASH="$starter" stage_run "$box" "$stage" "$3" "$PARITY_ENTRY" > "$stage/pb.out" 2> "$stage/pb.err" || rc=$?
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
  : > "$1/done"
  rm -rf "$1/stage"
fi
