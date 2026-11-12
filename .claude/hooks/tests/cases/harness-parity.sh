#!/usr/bin/env bash
# Hook suite section: parity of the harness with the real hook call
# Run alone: bash .claude/hooks/tests/cases/harness-parity.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

# The harness builds every hook input in bash (json.sh) instead of `jq -cn` (ww3d/playbook#427). This block
# holds that it changes nothing: per hook one case, its input once built by jq and once by the harness, both
# piped into the real `bash <hook>` from the same empty state; input, output, exit and the state left behind
# must match. HOOK_PARITY_MUTATE=1 is the mutation probe: the harness then writes every string one character
# longer, and this block has to turn red.
echo "== parity: harness against jq, the real hook call per hook (ww3d/playbook#427) =="
if [ -n "${HOOK_PARITY_MUTATE:-}" ]; then
  eval "js_real() $(declare -f js | tail -n +2)"
  js() { js_real "$1"; REPLY="${REPLY%\"}x\""; }
fi

pd="$fix/parity"
covered=()
norm() { # text -> REPLY with timestamps and the state folder replaced, so two runs a moment apart compare
  local s="${1//$'\r'/}"
  s="${s//"$pd/"/<dir>/}"
  while [[ $s =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z ]]; do s="${s//"${BASH_REMATCH[0]}"/<T>}"; done
  while [[ $s =~ (^|[^0-9<])(1[0-9]{9})([^0-9]|$) ]]; do s="${s//"${BASH_REMATCH[2]}"/<E>}"; done # epoch seconds
  REPLY="$s"
}
state() { # every file under the state folder with its content
  local f
  while IFS= read -r f; do printf '== %s\n' "${f#"$pd"}"; cat "$f"; done < <(find "$pd" -type f | sort)
}
run_once() { # input, hook, env... -> REPLY "<exit>:<output>", PAR_STATE the state left behind
  local in="$1" hook="$2" out rc; shift 2
  rm -rf "$pd"; mkdir -p "$pd/claude-rule-gate"
  if [ -n "${PAR_SETUP:-}" ]; then eval "$PAR_SETUP"; fi
  out="$(printf '%s' "$in" | env "$@" TMPDIR="$pd" bash "$hook" 2>&1)"; rc=$?
  norm "$(state)"; PAR_STATE="$REPLY"
  norm "$out"; REPLY="$rc:$REPLY"
}
parity() { # label, hook, input by jq, input by the harness, env...
  local label="$1" hook="$2" ref="${3//$'\r'/}" own="$4" a sa; shift 4
  covered+=("${hook##*/}")
  expect "parity $label: input" "$ref" "$own"
  run_once "$ref" "$hook" "$@"; a="$REPLY"; sa="$PAR_STATE"
  run_once "$own" "$hook" "$@"
  expect "parity $label: output and exit" "$a" "$REPLY"
  expect "parity $label: state left behind" "$sa" "$PAR_STATE"
  [ "${a%%:*}" != 0 ] || [ -n "${a#*:}" ] || [ -n "$sa" ] || bad "parity $label: the case shows nothing" empty 'output or state'
}
# The reference builder. Git Bash turns a /d/... argument of a native program into D:/...; the harness keeps a
# path as given, as jq does under Linux, so the reference is built without that conversion.
jqc() { MSYS2_ARG_CONV_EXCL='*' jq -cn "$@"; }

# require-receipt.sh: a Stop whose receipt marks files read that the record does not show (a missing
# receipt alone leaves no output, ww3d/playbook#435).
t="$fix/c1-receipt.jsonl"
PAR_SETUP='mkdir -p "$pd/claude-rule-gate"; : > "$pd/claude-rule-gate/par-rc-recorder.on"' \
parity require-receipt "$stop" \
  "$(jqc --arg t "$t" '{transcript_path: $t, session_id: "par-rc", hook_event_name: "Stop", stop_hook_active: false}')" \
  "$(stop_in "$t" false par-rc Stop)" \
  CLAUDE_PROJECT_DIR="$repo_root"

# require-rule-read.sh: a command whose rule file was not read.
c='gh issue create --title "a \"b\"" --body $(cat x)'
parity require-rule-read "$ruleread" \
  "$(jqc --arg s par-rr --arg t "$nr" --arg c "$c" \
    '{session_id: $s, transcript_path: $t, cwd: "/tmp", hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}')" \
  "$(rule_event "$nr" Bash "$c" par-rr)" \
  CLAUDE_PROJECT_DIR="$repo_root"

# read-confirm.sh: the read-receipt block at a session start.
use_rc_root
parity read-confirm "$readconfirm" \
  "$(jqc --arg s "$rc_sid" '{session_id: $s, hook_event_name: "SessionStart", source: "startup"}')" \
  "$(rc_event startup)" \
  CLAUDE_PROJECT_DIR="$rc_root" CLAUDE_CONFIG_DIR="$rc_config"

# record-rule-read.sh: a whole Read of a rule file.
p="$repo_root/.agents/rules/code.md"
parity record-rule-read "$recorder" \
  "$(jqc --arg s par-rec --arg p "$p" '{session_id: $s, transcript_path: "/tmp/none.jsonl", cwd: "/nonexistent",
      hook_event_name: "PostToolUse", tool_name: "Read", tool_input: {file_path: $p},
      tool_response: {type: "text", file: {startLine: 1, numLines: 10, totalLines: 10, filePath: $p}}}')" \
  "$(read_event par-rec "$p")" \
  CLAUDE_PROJECT_DIR="$repo_root"

# guard-kill.sh: ending an agent host.
c='taskkill /F /IM claude.exe'
parity guard-kill "$guard" \
  "$(jqc --arg c "$c" '{session_id: "k", hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}}')" \
  "$(kill_event Bash "$c")"

# block-announce-end.sh: a turn that ends on an announcement.
m='Als Naechstes baue ich die Tests.'; t="$fix/none.jsonl"
parity block-announce-end "$announce" \
  "$(jqc --arg m "$m" --arg t "$t" '{last_assistant_message: $m, transcript_path: $t, stop_hook_active: false}')" \
  "$(announce_event "$m" "$t")"

# remind-before-compact.sh: past 85 percent of the limit.
t="$fix/remind-parity.jsonl"
printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":149998,"output_tokens":5}}}\n' > "$t"
PAR_SETUP='printf "0 0\n" > "$pd/claude-rule-gate/par-rm-remind-state"' \
parity remind-before-compact "$hooks/remind-before-compact.sh" \
  "$(jqc --arg s par-rm --arg t "$t" '{session_id: $s, transcript_path: $t, cwd: "/tmp", hook_event_name: "PostToolUse", tool_name: "Bash"}')" \
  "$(remind_event par-rm "$t")" \
  -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u ANTHROPIC_MODEL -u CLAUDE_CODE_DISABLE_1M_CONTEXT CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000

# save-compact-state.sh: the state before a compaction.
t="$fix/compact-state.jsonl"
parity save-compact-state "$save_cs" \
  "$(jqc --arg s par-cs --arg t "$t" --arg c "$repo_root" '{session_id: $s, transcript_path: $t, cwd: $c, hook_event_name: "PreCompact", trigger: "auto"}')" \
  "$(save_event par-cs "$t")" \
  CLAUDE_PROJECT_DIR="$repo_root"

# restore-compact-state.sh: the replay after it, from a state saved the same way for both paths.
# shellcheck disable=SC2034 # read by the PAR_SETUP text below, which run_once evaluates
save_in="$(save_event par-cs "$t" /tmp)"
PAR_SETUP='printf "%s" "$save_in" | TMPDIR="$pd" CLAUDE_PROJECT_DIR="$repo_root" bash "$save_cs" >/dev/null 2>&1' \
parity restore-compact-state "$restore_cs" \
  "$(jqc --arg s par-cs --arg t "$t" '{session_id: $s, transcript_path: $t, hook_event_name: "SessionStart", source: "compact"}')" \
  "$(restore_event par-cs "$t")" \
  CLAUDE_PROJECT_DIR=

# js against jq where the escaping is tricky: quotes, backslashes, control characters, DEL and UTF-8.
for v in 'a"b\c' $'tab\there\nnew\rcr' $'\001\002\037\177' $'\b\f' 'ü → 😀' '' 'A $x `y`'; do
  js "$v"; expect "parity js: $(printf '%q' "$v")" "$(jq -cn --arg v "$v" '$v' | tr -d '\r')" "$REPLY"
done

# The verdict side: decision_of reads a hook's permissionDecision as jq does, spaced or pretty-printed too.
for o in '{"hookSpecificOutput":{"permissionDecision":"deny"}}' '{ "hookSpecificOutput": { "permissionDecision" : "allow" } }' \
         $'{\n  "hookSpecificOutput": {\n    "permissionDecision": "ask"\n  }\n}' '{"systemMessage":"x"}' 'not json'; do
  ref="$(printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision // "ERR"' 2>/dev/null | tr -d '\r')"
  decision_of "$o"; expect "parity decision_of: $(printf '%q' "$o")" "${ref:-ERR}" "$REPLY"
done

# Every hook has its case here: a new hook without one turns this block red. session-state.sh is a command the
# session runs, no hook: no payload to build two ways.
for h in "$hooks"/*.sh; do
  [ "${h##*/}" != session-state.sh ] || continue
  if [[ " ${covered[*]} " == *" ${h##*/} "* ]]; then ok "parity covers ${h##*/}" yes; else bad "parity covers ${h##*/}" no yes; fi
done
finish
