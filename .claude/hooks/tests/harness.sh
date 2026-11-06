#!/usr/bin/env bash
#
# The shared library of the hook suite: paths, verdict helpers and the event builders every section file
# under cases/ uses. A section file sources it first and calls `finish` last.
#
# Fixtures: run-tests.sh builds them once per run and hands their folder over in HOOK_TESTS_FIX; each
# section copies them into its own folder (HOOK_TESTS_OWN), so whatever a section writes stays its own
# and no section reads what another wrote. A section file started alone builds its own fixtures.
#
# Exit and result: `finish` prints the section's count and the line `HOOK-TESTS-RESULT <ok> <failed>`,
# which run-tests.sh reads; a section that ends without that line is red there.
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck disable=SC2034 # the variables below are read by the section files that source this one
set -uo pipefail
# The suite may itself run in a background session (`claude --bg` sets CLAUDE_JOB_DIR): the hooks would then
# take their background path everywhere. Cleared here; the cases for that path set it themselves.
unset CLAUDE_JOB_DIR
# block-announce-end.sh wakes late only in an interactive terminal session (ww3d/playbook#515):
# the cases that need it set the run kind themselves.
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_REMOTE ANNOUNCE_REWAKE_SECONDS ANNOUNCE_REWAKE_POLL
# Git Bash's path switches from the caller (ww3d/playbook#507) would keep the native jq and git from opening the
# suite's /d/... and /tmp paths. Cleared here; the case for a hook that inherits them sets them itself.
unset MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL
# guard-kill.sh lets an ending of the session's own process pass (ww3d/playbook#511); a suite run inside a session
# would then pass `kill <its child>`. `none` keeps the walk off; the block for the walk sets its own root.
export GUARD_KILL_ROOT_PID=none

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hooks="$(cd "$here/.." && pwd)"
repo_root="$(cd "$hooks/../.." && pwd)"
stop="$hooks/require-receipt.sh"
ruleread="$hooks/require-rule-read.sh"
readconfirm="$hooks/read-confirm.sh"
guard="$hooks/guard-kill.sh"
recorder="$hooks/record-rule-read.sh"
announce="$hooks/block-announce-end.sh"
save_cs="$hooks/save-compact-state.sh"
restore_cs="$hooks/restore-compact-state.sh"

if [ -n "${HOOK_TESTS_FIX:-}" ] && [ -n "${HOOK_TESTS_OWN:-}" ]; then
  fix="$HOOK_TESTS_OWN"
  if ! { mkdir -p "$fix" && cp -R "$HOOK_TESTS_FIX/." "$fix/"; }; then echo "cannot copy the fixtures to $fix" >&2; exit 2; fi
else
  # Started alone: one run folder under the repo's artifacts/tmp/test (run-folder.sh), fixtures built here.
  # shellcheck source=SCRIPTDIR/run-folder.sh
  . "$here/run-folder.sh"
  open_run_folder "$repo_root"
  fix="$RUN_DIR"
  trap 'rm -rf "$fix"' EXIT
  bash "$here/mkfixtures.sh" "$fix" >/dev/null || { echo "mkfixtures.sh failed" >&2; exit 2; }
fi

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$1" "$2"; }
bad() { fail=$((fail + 1)); printf '  FAIL %-52s %s (expected %s)\n' "$1" "$2" "$3"; }
expect() { if [ "$3" = "$2" ]; then ok "$1" "$3"; else bad "$1" "$3" "$2"; fi; } # label, expected, got
# The section's count, then the line run-tests.sh adds up; exit 1 on any failed case.
finish() {
  echo
  printf '%s ok, %s failed\n' "$pass" "$fail"
  printf 'HOOK-TESTS-RESULT %s %s\n' "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

# No network in the tests: the version lookup points at a repository that does not exist; an empty managed
# directory, so the machine's own policy never decides a case.
export READ_CONFIRM_REMOTE="$fix/no-such-remote"
mkdir -p "$fix/rc-managed-empty"
export READ_CONFIRM_MANAGED_DIR="$fix/rc-managed-empty"

# Stand-ins: a section shadows jq or grep in $stub to count or break their calls.
stub="$fix/stub"; mkdir -p "$stub"
real_jq="$(command -v jq)"
real_grep="$(command -v grep)"
calls="$fix/calls.log"

# Hook inputs are built here without a process (json.sh). A tool_input or other JSON argument is passed
# through as given and has to be compact JSON, as jq would print it.
# shellcheck source=SCRIPTDIR/json.sh
. "$here/json.sh"

# The permissionDecision of a hook output as `jq -r '.hookSpecificOutput.permissionDecision // "ERR"'` reads it,
# spaces around the colon included; ERR where the output is no object or names none. cases/harness-parity.sh
# holds it against jq.
decision_of() { # hook output -> REPLY
  local re='"permissionDecision"[[:space:]]*:[[:space:]]*"([a-z]*)"' t="${1#"${1%%[![:space:]]*}"}"
  if [[ $t == '{'* && $t =~ $re ]]; then REPLY="${BASH_REMATCH[1]}"; else REPLY=ERR; fi
}

# require-rule-read.sh: one PreToolUse event and its verdict.
rule_event() { # transcript, tool, command, session
  local t n s c
  js "$1"; t="$REPLY"; js "$2"; n="$REPLY"; js "$4"; s="$REPLY"
  if [ -z "$3" ]; then c='{}'; else js "$3"; c="{\"command\":$REPLY}"; fi
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":%s,"tool_input":%s}' \
    "$s" "$t" "$n" "$c"
}
# Its own TMPDIR: the hook keeps per-session markers there (stage 2, found
# receipts), and a marker left by an earlier run of this suite must not decide
# a case of this one.
gate_tmp="$fix/gate-tmp"; mkdir -p "$gate_tmp"
rule_verdict() { # event json [project dir]
  local out rc
  out="$(printf '%s' "$1" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="${2:-$repo_root}" bash "$ruleread" 2>&1)"; rc=$?
  decision_of "$out"
  if [ "$REPLY" = deny ]; then printf 'DENY'
  elif [ -z "$out" ] && [ "$rc" = 0 ]; then printf 'ALLOW'
  else printf 'ERR(rc=%s)' "$rc"; fi
}
# Every call runs in a $(...) subshell, so a counter incremented here never
# reached the caller and every case shared one session id - harmless while the
# hook kept no per-session state that could turn a later DENY into an ALLOW,
# wrong since it remembers found receipts. The subshell's own PID is unique.
next_sid() { printf 'probe-rule-%s-%s' "$BASHPID" "$RANDOM"; }
chk_rule() { # label, expected, transcript, tool, command
  local v; v="$(rule_verdict "$(rule_event "$3" "$4" "$5" "$(next_sid)")")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}
rc_sid="probe-compact-$$"
rc_event() { local s; js "$rc_sid"; s="$REPLY"; js "$1"; printf '{"session_id":%s,"hook_event_name":"SessionStart","source":%s}' "$s" "$REPLY"; }
tool_event() { # transcript, tool, tool_input json, session
  local t n
  js "$1"; t="$REPLY"; js "$2"; n="$REPLY"; js "$4"
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":%s,"tool_input":%s}' \
    "$REPLY" "$t" "$n" "$3"
}
chk_tool() { # label, expected, tool, tool_input json [project dir]
  local v; v="$(rule_verdict "$(tool_event "$fix/rule-no-receipt.jsonl" "$3" "$4" "$(next_sid)")" "${5:-}")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}
nr="$fix/rule-no-receipt.jsonl"

# Verdicts by shell match, the meaning `grep -F` / `grep -xF` gave them: a needle of several lines matches
# where any one of its lines does.
has_text() { # needle, haystack; a needle of several lines matches when any non-empty line does
  local l
  case "$1" in *$'\n'*) while IFS= read -r l; do [ -n "$l" ] && [[ $2 == *"$l"* ]] && return 0; done <<<"$1"; return 1 ;; esac
  [[ $2 == *"$1"* ]]
}
has_line() { # whole line, haystack; a CR before the line end does not count (jq on Windows writes CRLF)
  local l h="${2//$'\r\n'/$'\n'}"
  case "$1" in *$'\n'*) while IFS= read -r l; do [ -n "$l" ] && has_line "$l" "$h" && return 0; done <<<"$1"; return 1 ;; esac
  h="${h%$'\r'}"
  [[ $'\n'$h$'\n' == *$'\n'"$1"$'\n'* ]]
}
check_contains() { # label, needle, haystack
  if has_text "$2" "$3"; then ok "$1" "found"
  else bad "$1" "not found: $2" "found"; fi
}
check_line() { # label, whole line, haystack
  if has_line "$2" "$3"; then ok "$1" "found"
  else bad "$1" "no line: $2" "found"; fi
}
check_not_contains() { # label, needle, haystack
  if has_text "$2" "$3"; then bad "$1" "found: $2" "not found"
  else ok "$1" "not found"; fi
}

present_file() { if [ -e "$2" ]; then ok "$1" kept; else bad "$1" removed kept; fi; }
absent_file() { if [ -e "$2" ]; then bad "$1" kept removed; else ok "$1" removed; fi; }

# A project of its own for read-confirm.sh, built where a section needs it.
use_rc_root() {
rc_root="$fix/rc-root"
mkdir -p "$rc_root/.claude/skills/beispiel-skill" "$rc_root/.claude/skills/zweiter-skill" \
         "$rc_root/.agents/rules" "$rc_root/audit"
# Its own repository: the hook hashes against the nearest repository, and a root inside the
# checkout would resolve its paths against the checkout.
git init -q "$rc_root"
printf '# Test Project\n' > "$rc_root/CLAUDE.md"
printf '# Agents\n' > "$rc_root/AGENTS.md"
printf '1.0.0\n' > "$rc_root/VERSION"
printf -- '---\nname: beispiel-skill\n---\n# Beispiel\n' > "$rc_root/.claude/skills/beispiel-skill/SKILL.md"
printf -- '---\nname: zweiter-skill\n---\n# Zweiter\n' > "$rc_root/.claude/skills/zweiter-skill/SKILL.md"
printf '# audit a\n' > "$rc_root/audit/ist-stand-2026-01-01T0000Z.md"
printf '# audit b\n' > "$rc_root/audit/state-2026-02-02T0000Z.md"
cat > "$rc_root/.agents/rules/index.json" <<'EOF'
{
  "rules": [
    {
      "trigger": "code",
      "path": ".agents/rules/code.md"
    },
    {
      "trigger": "docs",
      "path": ".agents/rules/docs.md"
    }
  ]
}
EOF

rc_tmp="$fix/rc-tmp"; mkdir -p "$rc_tmp"
rc_config="$fix/rc-config-empty"; mkdir -p "$rc_config"
# An empty managed directory, so the machine's own policy never decides a case.
rc_managed="$fix/rc-managed-empty"; mkdir -p "$rc_managed"
export READ_CONFIRM_MANAGED_DIR="$rc_managed"
# No network in the tests: the version lookup points at a repository that does not exist.
export READ_CONFIRM_REMOTE="$fix/no-such-remote"
}
run_readconfirm() {
  CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$rc_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm"
}
version_ctx() { # remote, [version file content], [source], [TMPDIR]
  printf '%s\n' "${2:-1.0.0}" > "$rc_root/VERSION"
  printf '{"session_id":"v","source":"%s"}' "${3:-startup}" \
    | CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="${4:-$rc_tmp}" CLAUDE_CONFIG_DIR="$rc_config" READ_CONFIRM_REMOTE="$1" bash "$readconfirm" \
    | jq -r '.hookSpecificOutput.additionalContext'
}

# record-rule-read.sh: a PostToolUse Read and its recording.
read_event() { # session, file_path, [agent_id], [tool_input extra json], [tool_response file json]
  # The extra fields and the span are compact JSON objects without file_path / filePath of their own.
  local s p a="" x="${4:-}" r="${5:-}"
  js "$1"; s="$REPLY"; js "$2"; p="$REPLY"
  [ -z "${3:-}" ] || { js "$3"; a=",\"agent_id\":$REPLY,\"agent_type\":\"general-purpose\""; }
  [ -n "$x" ] && [ "$x" != '{}' ] && x=",${x#\{}" || x='}'
  [ -n "$r" ] || r='{"startLine":1,"numLines":10,"totalLines":10}'
  [ "$r" = '{}' ] && r='{' || r="${r%\}},"
  printf '{"session_id":%s,"transcript_path":"/tmp/none.jsonl","cwd":"/nonexistent","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":%s%s,"tool_response":{"type":"text","file":%s"filePath":%s}}%s}' \
    "$s" "$p" "$x" "$r" "$p" "$a"
}
record() { printf '%s' "$1" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$recorder"; }

# guard-kill.sh: one command and its verdict.
kill_event() { local t; js "$1"; t="$REPLY"; js "$2"; printf '{"session_id":"k","hook_event_name":"PreToolUse","tool_name":%s,"tool_input":{"command":%s}}' "$t" "$REPLY"; }
kill_out() { kill_event "$1" "$2" | bash "$guard" 2>&1; }
chk_kill() { # label, expected (deny|allow), tool, command [reason fragment]
  local out got
  out="$(kill_out "$3" "$4")"
  if [ -z "$out" ]; then got=allow; else decision_of "$out"; got="$REPLY"; fi
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
  if [ -n "${5:-}" ]; then check_contains "$1: reason" "$5" "$out"; fi
}

# save-compact-state.sh / restore-compact-state.sh and the lock after a compaction.
cs_tmp="$fix/cs-tmp"; cs_gate="$cs_tmp/claude-rule-gate"; mkdir -p "$cs_gate"
save_event() { # session, transcript, [cwd, default the repo root] -> a PreCompact payload
  local s t
  js "$1"; s="$REPLY"; js "$2"; t="$REPLY"; js "${3:-$repo_root}"
  printf '{"session_id":%s,"transcript_path":%s,"cwd":%s,"hook_event_name":"PreCompact","trigger":"auto"}' "$s" "$t" "$REPLY"
}
restore_event() { # session, transcript -> the SessionStart payload after a compaction
  local s
  js "$1"; s="$REPLY"; js "$2"
  printf '{"session_id":%s,"transcript_path":%s,"hook_event_name":"SessionStart","source":"compact"}' "$s" "$REPLY"
}
cs_save() { # session, transcript
  save_event "$1" "$2" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$save_cs"
}
cs_restore() { # session, transcript, [PATH], [project root; empty: none, so no standing rule file]
  restore_event "$1" "$2" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="${4:-}" PATH="${3:-$PATH}" "$BASH" "$restore_cs"
}
remind_event() { # session, transcript, [sub-agent id] -> the PostToolUse payload remind-before-compact.sh reads
  js "$1"; printf '{"session_id":%s' "$REPLY"; js "$2"
  printf ',"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PostToolUse","tool_name":"Bash"' "$REPLY"
  if [ -n "${3:-}" ]; then js "$3"; printf ',"agent_id":%s' "$REPLY"; fi
  printf '}\n'
}

# Stop payloads: require-receipt.sh reads the transcript, block-announce-end.sh the last message.
stop_in() { # transcript, [stop_hook_active JSON, default false], [session id], [event name] -> a Stop payload
  js "$1"
  printf '{"transcript_path":%s' "$REPLY"
  if [ -n "${3:-}" ]; then js "$3"; printf ',"session_id":%s' "$REPLY"; fi
  if [ -n "${4:-}" ]; then js "$4"; printf ',"hook_event_name":%s' "$REPLY"; fi
  printf ',"stop_hook_active":%s}\n' "${2:-false}"
}
announce_event() { # last message, transcript -> a Stop payload carrying last_assistant_message
  local m; js "$1"; m="$REPLY"; js "$2"
  printf '{"last_assistant_message":%s,"transcript_path":%s,"stop_hook_active":false}\n' "$m" "$REPLY"
}
use_csnojq() { # a PATH without jq: the helpers the hooks need, each a wrapper around the real one
  csnojq="$fix/cs-nojq"; mkdir -p "$csnojq"
  for helper in sed wc tr date mkdir cat head tail rm; do
    printf '#!%s\nexec "%s" "$@"\n' "$(command -v bash)" "$(command -v "$helper")" > "$csnojq/$helper"
    chmod +x "$csnojq/$helper"
  done
}
cs_proj="$fix/cs-proj"; mkdir -p "$cs_proj/.agents/rules/local"
for f in chat.md pr.md local/ci-silence.md local/naming.md; do : > "$cs_proj/.agents/rules/$f"; done
lk_out() { # session, tool, [agent_id] -> the gate's raw output
  local s n t a=""
  js "$1"; s="$REPLY"; js "$2"; n="$REPLY"; js "$fix/compact-state.jsonl"; t="$REPLY"
  [ -z "${3:-}" ] || { js "$3"; a=",\"agent_id\":$REPLY"; }
  printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":%s,"tool_input":%s%s}' \
    "$s" "$t" "$n" "${LK_INPUT:-"{\"command\":\"ls\"}"}" "$a" \
    | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1
}
lk_verdict() { # session, tool, [agent_id] -> LOCK where the lock denied, else PASS
  local out
  out="$(lk_out "$@")"
  case "$out" in *'this session is locked'*) printf 'LOCK' ;; *) printf 'PASS' ;; esac
}
# session, path, [startLine numLines [totalLines]; empty: a whole read], [project root], [agent_id] - a Read the
# recorder sees
lk_read() {
  local s p a="" off="" file='{}' part
  js "$1"; s="$REPLY"; js "$2"; p="$REPLY"
  [ -z "${5:-}" ] || { js "$5"; a=",\"agent_id\":$REPLY"; }
  if [ -n "${3:-}" ]; then
    read -r -a part <<<"$3"
    off=',"offset":1'
    file="{\"startLine\":${part[0]:-null},\"numLines\":${part[1]:-null},\"totalLines\":${part[2]:-null}}"
  fi
  printf '{"session_id":%s%s,"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":%s%s},"tool_response":{"file":%s}}' \
    "$s" "$a" "$p" "$off" "$file" \
    | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="${4:-$repo_root}" bash "$recorder" >/dev/null 2>&1
}
lk_denies() { cat "$cs_gate/$1-compact-lock-denies" 2>/dev/null; } # session -> "<turn key> <count>"
lk_need() { # session, marker -> the number of lines "need=<marker> ..." in the session's lock file
  local c=0 l
  [ -f "$cs_gate/$1-compact-lock" ] || return 2
  while IFS= read -r l || [ -n "$l" ]; do [[ $l == "need=$2 "* ]] && c=$((c + 1)); done < "$cs_gate/$1-compact-lock"
  echo "$c"; [ "$c" -gt 0 ]
}
