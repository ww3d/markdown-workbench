#!/usr/bin/env bash
#
# PreToolUse hook - shared temp guard (ww3d/playbook#619). Generic, byte-identical across consumers.
#
# All sessions of a machine share one temp folder, and a model writes fixed names there (`D:/tmp/prbody.md`):
# sessions overwrite each other's files, and a stale file gets published. This hook meets a write to a fixed path
# under a shared root (`/tmp/`, `<drive>:/tmp/`, `.../AppData/Local/Temp/`, `<Windows>/Temp/`, the temp variables)
# outside the session's own area with the way out: the same file name in the session's scratchpad.
#
# What counts (lib/tmp-guard.sh): Write, Edit, NotebookEdit by their path; Bash and PowerShell by the words at the
# write places of a command (redirection, tee, -o / --output / -OutFile / -FilePath, Out-File, Set-Content,
# Add-Content, New-Item, cp / mv / install, Copy-Item / Move-Item -Destination). Reading never counts, text,
# heredoc bodies and comments never count, a name with a changing part (`$$`, `mktemp`) and a folder alone never count.
#
# Switch PLAYBOOK_TMP_GUARD: off | warn | block; empty or unknown = warn.
#   warn   additionalContext with the path and the way out, no decision.
#   block  permissionDecision deny with the same text. Without a scratchpad known (no scratchpad_dir in the
#          envelope, none derived) there is no way out to name, so it stays at warn.
# Own area, never a hit: scratchpad_dir, a path with the session's id, CLAUDE_PROJECT_DIR, the folders in
# PLAYBOOK_TMP_GUARD_OWN (separated like PATH on the platform). Web sessions (CLAUDE_CODE_REMOTE=true): silent.
# Every hit adds a line to <the temp folder>/claude-rule-gate/tmp-guard-log.jsonl (stamp, session, tool, path, level).
#
# Cost: the raw envelope is checked with bash builtins first; without a shared root or a temp variable in it the
# hook ends with no further process. Fail-open: no jq, no awk, a broken envelope or a timeout
# (PLAYBOOK_TMP_GUARD_TIMEOUT seconds, default 10, per program) let the call pass without output.
#
# Stdin:  the PreToolUse event JSON ({ tool_name, session_id, scratchpad_dir, tool_input, ... }).
# Stdout: nothing, or hookSpecificOutput.

set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" != true ] || exit 0
mode="${PLAYBOOK_TMP_GUARD:-warn}"
case "$mode" in off) exit 0 ;; warn|block) ;; *) mode=warn ;; esac

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
hook_payload_quiet=1 read_hook_payload
[ -n "$hook_input" ] || exit 0

# Step 1, no process: a shared root or a temp variable somewhere in the call's own fields. The envelope's folders
# (scratchpad_dir, cwd, transcript_path) are cut out first - they hold `tmp` on every call.
tg_lib="${BASH_SOURCE[0]%/*}/lib"
# shellcheck source=SCRIPTDIR/lib/tmp-guard.sh
. "$tg_lib/tmp-guard.sh" 2>/dev/null || exit 0
# Each field is found by a regex and removed as fixed text: a pattern of no fixed length (`*([!\"])`) costs the
# square of the envelope's length and runs a Write of 8 KB past the hook's 30 s limit (ww3d/playbook#719).
raw="$hook_input"
for tg_key in scratchpad_dir transcript_path cwd; do
  tg_re="\"$tg_key\":\"[^\"]*\""
  [[ $raw =~ $tg_re ]] && raw="${raw/"${BASH_REMATCH[0]}"/}"
done
tg_mentions "$raw" || exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v awk >/dev/null 2>&1 || exit 0
to="${PLAYBOOK_TMP_GUARD_TIMEOUT:-10}"
case "$to" in ''|*[!0-9]*|0) to=10 ;; esac
tmo=()
if command -v timeout >/dev/null 2>&1; then tmo=(timeout "$to"); fi

# shellcheck disable=SC2016 # a jq program
fields="$("${tmo[@]}" jq -j '[.tool_name, .session_id, .scratchpad_dir, (.tool_input.file_path // .tool_input.notebook_path), .tool_input.command] | map(. // "" | tostring) | join("\u001f")' <<<"$hook_input" 2>/dev/null)" || exit 0
us=$'\037'
tool="${fields%%"$us"*}"; fields="${fields#*"$us"}"
session="${fields%%"$us"*}"; fields="${fields#*"$us"}"
pad="${fields%%"$us"*}"; fields="${fields#*"$us"}"
fpath="${fields%%"$us"*}"; command_line="${fields#*"$us"}"
case "$tool" in Bash|PowerShell|Write|Edit|NotebookEdit) ;; *) exit 0 ;; esac

tg_timeout=""
[ "${#tmo[@]}" -eq 0 ] || tg_timeout="$to"
tg_init "$session" "$pad"
case "$tool" in Bash|PowerShell) subject="$command_line" ;; *) subject="$fpath" ;; esac
[ -n "$subject" ] || exit 0
tg_detect "$tool" "$subject" || exit 0
[ "${#tg_hits[@]}" -gt 0 ] || exit 0

tg_find_scratch
[ -n "$tg_scratch" ] || mode=warn

lines=""
for h in "${tg_hits[@]}"; do
  tg_escape_for "$h"
  lines+="${lines:+; }$h -> $tg_escape"
done
text="Shared temp folder: this ${tool} call writes to a fixed path every session shares (${lines}). Another session can overwrite the file, or you publish its stale one; write inside your own scratchpad instead (ww3d/playbook#619)."

# The log beside the state files of the other hooks; the replay and the live run count it. A failure never matters.
# shellcheck source=SCRIPTDIR/lib/tempdir.sh
. "${BASH_SOURCE[0]%/*}/lib/tempdir.sh" 2>/dev/null && hook_tmpdir || exit 0
gate_dir="$hook_tmp/claude-rule-gate"
log_file="${PLAYBOOK_TMP_GUARD_LOG:-$gate_dir/tmp-guard-log.jsonl}"
if [ -n "${PLAYBOOK_TMP_GUARD_LOG:-}" ] || mkdir -p "$gate_dir" 2>/dev/null; then
  TZ=UTC0 printf -v stamp '%(%Y-%m-%dT%H:%M:%SZ)T' -1
  for h in "${tg_hits[@]}"; do
    tg_js "$session"; j_s="$tg_j"; tg_js "$tool"; j_t="$tg_j"; tg_js "$h"; j_p="$tg_j"
    printf '{"ts":"%s","session":%s,"tool":%s,"path":%s,"level":"%s"}\n' "$stamp" "$j_s" "$j_t" "$j_p" "$mode" >>"$log_file" 2>/dev/null
  done
fi

tg_js "$text"
if [ "$mode" = block ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$tg_j"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$tg_j"
fi
exit 0
