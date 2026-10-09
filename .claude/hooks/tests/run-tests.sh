#!/usr/bin/env bash
#
# Behaviour tests for require-receipt.sh, require-rule-read.sh and
# read-confirm.sh.
#
# Ported from a consumer repo's hook-test suite (provenance: docs/provenance.md
# in the playbook), which also covered a fourth hook, gate-actions.sh, that this
# repo does not carry.
# Dropped entirely: the ~30 DENY/ALLOW pairs there that classify git/gh
# "acting" commands against a single global receipt, and the parent/subagent
# transcript-redirection tests — both are specific to that hook's own
# mechanism, which require-rule-read.sh does not share (it classifies by
# tool+trigger, not by a git/gh command allowlist, and never redirects to a
# parent transcript). Reused as-is: the "require-receipt.sh agrees with the
# gate" fixture-driven block. Adapted to require-rule-read.sh's own trigger
# map and its own "rule | <path> |" receipt line: the paired-DENY/ALLOW shape,
# the fail-open-on-missing-helper mutation test, and the jq-exit-2 inversion
# mutation test that AGENTS.md § "Always" asks for (a test that forces the
# success path of a silent catch-and-degrade).
#
# Every case states its expected verdict, and the ones that matter come in
# pairs: a command that must be refused next to one that must not. A gate is
# only as good as its counter-case — a suite of nothing but DENY/BLOCK lines
# passes just as well when the gate refuses everything.
#
# Usage:  bash .claude/hooks/tests/run-tests.sh
# Exit:   0 when every case holds, 1 otherwise.
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
set -uo pipefail
# The suite may itself run in a background session (`claude --bg` sets CLAUDE_JOB_DIR): the hooks would then
# take their background path everywhere. Cleared here; the cases for that path set it themselves.
unset CLAUDE_JOB_DIR

here="$(cd "$(dirname "$0")" && pwd)"
hooks="$(cd "$here/.." && pwd)"
repo_root="$(cd "$hooks/../.." && pwd)"
stop="$hooks/require-receipt.sh"
ruleread="$hooks/require-rule-read.sh"
readconfirm="$hooks/read-confirm.sh"
guard="$hooks/guard-kill.sh"
recorder="$hooks/record-rule-read.sh"

# One run folder under the repo's artifacts/tmp/test (run-folder.sh).
# shellcheck source=SCRIPTDIR/run-folder.sh
. "$here/run-folder.sh"
open_run_folder "$repo_root"
fix="$RUN_DIR"
trap 'rm -rf "$fix"' EXIT
bash "$here/mkfixtures.sh" "$fix" >/dev/null

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$1" "$2"; }
bad() { fail=$((fail + 1)); printf '  FAIL %-52s %s (expected %s)\n' "$1" "$2" "$3"; }

echo "== require-receipt.sh agrees with the gate =="
for f in no-receipt with-receipt with-old-receipt resumed quote-only drift trunc-no-receipt trunc-then-receipt \
         echo-receipt echo-unrun echo-redirect echo-refused echo-then-resumed \
         receipt-ss-receipt receipt-resume-turn receipt-fork-turn receipt-startup-turn \
         receipt-then-compact receipt-then-compact-hook echo-then-compact compact-then-receipt \
         receipt-then-clear clear-then-receipt mem-only split-messages old-format \
         compact-no-sessionstart other-hook-no-sessionstart; do
  out="$(jq -cn --arg t "$fix/$f.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' | bash "$stop" 2>&1)"
  if   printf '%s' "$out" | grep -q '"decision":"block"'; then v=BLOCK
  elif printf '%s' "$out" | grep -q 'systemMessage'; then v=DRIFT
  elif [ -z "$out" ]; then v=ALLOW; else v="ERR"; fi
  case "$f" in
    # quote-only: the H1 alone is quoted in a code fence, with no "## Konventionen"
    # heading anywhere in the same text - fix #1 (issue ww3d/playbook#198 pt.1) means this
    # must BLOCK, not be read as a receipt.
    no-receipt|quote-only|trunc-no-receipt) want=BLOCK ;;
    # The memory line alone, the two lines in two messages and the old H1 format are no receipt.
    mem-only|split-messages|old-format) want=BLOCK ;;
    # echo-*: the receipt printed by a command counts only where the command ran
    # without error and its own result shows it (ww3d/playbook#271, same rule as ww3d/playbook#273).
    echo-unrun|echo-redirect|echo-refused) want=BLOCK ;;
    # A compaction or /clear ends the receipt before it; a further start (resume, fork,
    # startup) in the same transcript does not (ww3d/playbook#337).
    receipt-then-compact|receipt-then-compact-hook|echo-then-compact|receipt-then-clear) want=BLOCK ;;
    drift) want=DRIFT ;;
    # trunc-then-receipt: a broken line sits between the session start and a
    # real, full receipt - fix #2 (issue ww3d/playbook#198 pt.2) means the broken line is
    # skipped and the receipt after it still counts.
    *) want=ALLOW ;;
  esac
  if [ "$v" = "$want" ]; then ok "stop hook on $f" "$v"; else bad "stop hook on $f" "$v" "$want"; fi
done

echo "== require-receipt.sh: a single broken line never voids the whole transcript =="
# trunc-no-receipt is the case that demonstrates the actual bug: before fix #2,
# jq -rs (slurp) fails whole on the one unparsable line, the verdict comes back
# empty, matches no case in the BLOCK/DRIFT case statement, and the hook exits
# 0 with no output at all - i.e. ALLOW, even though no real receipt exists
# anywhere in the transcript. Re-asserted here by name (in addition to the loop
# above) since it is the fix's actual red/green case, not merely the shape the
# imported suite already asked for.
out="$(jq -cn --arg t "$fix/trunc-no-receipt.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' | bash "$stop" 2>&1)"
if printf '%s' "$out" | grep -q '"decision":"block"'; then
  ok "a broken line does not silently allow an unreceipted transcript" "BLOCK"
else
  bad "a broken line does not silently allow an unreceipted transcript" "not BLOCK" "BLOCK"
fi

echo "== require-receipt.sh: stop_hook_active releases a repeated block (issue ww3d/playbook#171 (c)) =="
# The loop guard: on a stop that already follows a Stop-hook block, a still
# missing receipt must not block again but end the turn with a warning. Paired
# with the same transcript on a first stop (must still BLOCK), a receipted
# transcript on a follow-up stop (must stay a silent ALLOW, no stray warning),
# and a non-boolean field value (must not count as true).
stop_verdict() { # transcript, stop_hook_active as a jq literal
  local out
  out="$(jq -cn --arg t "$1" --argjson a "$2" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: $a}' | bash "$stop" 2>&1)"
  if   printf '%s' "$out" | grep -q '"decision":"block"'; then printf 'BLOCK'
  elif printf '%s' "$out" | grep -q 'blocked this stop once already'; then printf 'WARN'
  elif [ -z "$out" ]; then printf 'ALLOW'; else printf 'ERR'; fi
}
chk_stop() { # label, expected, transcript, stop_hook_active
  local v; v="$(stop_verdict "$3" "$4")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}
chk_stop 'no receipt, first stop'                   BLOCK "$fix/no-receipt.jsonl"   false
chk_stop 'no receipt, stop after a block'           WARN  "$fix/no-receipt.jsonl"   true
chk_stop 'receipt present, stop after a block'      ALLOW "$fix/with-receipt.jsonl" true
chk_stop 'no receipt, stop_hook_active as a string' BLOCK "$fix/no-receipt.jsonl"   '"true"'
out="$(jq -cn --arg t "$fix/no-receipt.jsonl" '{transcript_path: $t, stop_hook_active: false}' | bash "$stop" 2>&1)"
if printf '%s' "$out" | grep -qF 'do not repeat it unprompted in later turns'; then
  ok 'block text says once, not per turn (ww3d/playbook#337)' found
else
  bad 'block text says once, not per turn (ww3d/playbook#337)' 'not found' found
fi

echo "== require-receipt.sh: a jq failure while building the verdict output must still exit 0 =="
# Issue ww3d/playbook#198 pt.3: the two jq -cn calls that build this hook's own BLOCK/DRIFT
# output had no `|| true`. Shadow jq so that only a `-cn` invocation fails (exit
# 2, like a real jq system error) while every other call (the -Rrs verdict
# computation) still runs for real - found by mutation: removing `|| true` from
# either call leaves this red.
stub="$fix/stub"; mkdir -p "$stub"
real_jq="$(command -v jq)"
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-cn" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
chmod +x "$stub/jq"
out="$(jq -cn --arg t "$fix/no-receipt.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' \
  | PATH="$stub:$PATH" bash "$stop" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then
  ok "BLOCK-branch jq failure still exits 0" "rc=0"
else
  bad "BLOCK-branch jq failure still exits 0" "rc=$rc" "rc=0"
fi
rm -f "$stub/jq"

echo "== require-rule-read.sh: receipt recognised in a tool_use command, not just text =="
rule_event() { # transcript, tool, command, session
  jq -cn --arg t "$1" --arg n "$2" --arg c "$3" --arg s "$4" \
    '{session_id: $s, transcript_path: $t, cwd: "/tmp", hook_event_name: "PreToolUse",
      tool_name: $n, tool_input: ({command: $c} | if $c == "" then {} else . end)}'
}
# Its own TMPDIR: the hook keeps per-session markers there (stage 2, found
# receipts), and a marker left by an earlier run of this suite must not decide
# a case of this one.
gate_tmp="$fix/gate-tmp"; mkdir -p "$gate_tmp"
rule_verdict() { # event json [project dir]
  local out rc
  out="$(printf '%s' "$1" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="${2:-$repo_root}" bash "$ruleread" 2>&1)"; rc=$?
  if   printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then printf 'DENY'
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

chk_rule 'no rule receipt at all'                  DENY  "$fix/rule-no-receipt.jsonl"      Bash 'gh issue create --title x'
chk_rule 'rule receipt as its own text block'      ALLOW "$fix/rule-receipt-text.jsonl"    Bash 'gh issue create --title x'
# The receipt line never appears as a standalone assistant text entry, only
# inside a tool_use's .input.command (an echo) and that command's own result.
# Text between tool calls can leave the model as thinking and never land as
# text, so this is the dependable way to emit it.
chk_rule 'rule receipt echoed by a command that ran'  ALLOW "$fix/rule-receipt-toolcmd.jsonl" Bash 'gh issue create --title x'
chk_rule 'rule receipt echoed, result as text-block array' ALLOW "$fix/rule-receipt-toolcmd-array.jsonl" Bash 'gh issue create --title x'

echo "== require-rule-read.sh: a receipt a command only carries as data does not count (ww3d/playbook#273) =="
# Each DENY below has the line in a tool_use command; the ALLOW pair above is
# the same line in a command whose result printed it.
chk_rule 'command not run yet (no result)'          DENY "$fix/rule-receipt-unrun.jsonl"    Bash 'gh issue create --title x'
chk_rule 'command refused (result is_error)'        DENY "$fix/rule-receipt-refused.jsonl"  Bash 'gh issue create --title x'
chk_rule 'line written to a file (cat > f <<EOF)'   DENY "$fix/rule-receipt-redirect.jsonl" Bash 'gh issue create --title x'
chk_rule 'line inside a gh body, result is a URL'   DENY "$fix/rule-receipt-data.jsonl"     Bash 'gh issue create --title x'
# Refused although the result shows the line (the stage-2 denial's own shape):
# only is_error tells it from a real echo (ww3d/playbook#289).
chk_rule 'refused, result shows the line (is_error)' DENY "$fix/rule-receipt-refused-echo.jsonl" Bash 'gh issue create --title x'

echo "== require-rule-read.sh: a compaction ends every receipt before it =="
chk_rule 'receipt, then compact_boundary'             DENY  "$fix/rule-receipt-then-compact.jsonl"      Bash 'gh issue create --title x'
chk_rule 'receipt, then SessionStart:compact only'    DENY  "$fix/rule-receipt-then-compact-hook.jsonl" Bash 'gh issue create --title x'
chk_rule 'compaction, then a new receipt'             ALLOW "$fix/rule-compact-then-receipt.jsonl"      Bash 'gh issue create --title x'
# The marker file must not outlive the compaction either: a receipt found
# before it is remembered, read-confirm.sh on source "compact" clears the
# session's markers, and the same transcript - now with the compaction at its
# end - is read again and DENYs. On source "startup" the marker stays.
rc_sid="probe-compact-$$"
rc_event() { jq -cn --arg s "$rc_sid" --arg src "$1" '{session_id: $s, hook_event_name: "SessionStart", source: $src}'; }
compact_run() { # transcript
  rule_verdict "$(jq -cn --arg t "$1" --arg s "$rc_sid" \
    '{session_id: $s, transcript_path: $t, cwd: "/tmp", hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "gh issue create"}}')"
}
expect() { if [ "$3" = "$2" ]; then ok "$1" "$3"; else bad "$1" "$3" "$2"; fi; } # label, expected, got
expect 'marker: receipt found and remembered' ALLOW "$(compact_run "$fix/rule-receipt-text.jsonl")"
rc_event startup | CLAUDE_PROJECT_DIR="$repo_root" TMPDIR="$gate_tmp" bash "$readconfirm" >/dev/null
expect 'marker survives a startup SessionStart' ALLOW "$(compact_run "$fix/rule-receipt-then-compact.jsonl")"
rc_event compact | CLAUDE_PROJECT_DIR="$repo_root" TMPDIR="$gate_tmp" bash "$readconfirm" >/dev/null
expect 'marker cleared by a compact SessionStart' DENY "$(compact_run "$fix/rule-receipt-then-compact.jsonl")"

echo "== require-rule-read.sh: fail-open on a missing transcript, like require-receipt.sh =="
chk_rule 'transcript missing'   ALLOW "$fix/nope.jsonl"  Bash 'gh issue create --title x'
# An EMPTY transcript is different from a missing one: the file reads as a
# valid, empty jq input (`[]`), so the hook can positively determine "no
# receipt anywhere" rather than merely failing to read - and DENYs on that
# evidence, same as any other transcript with no receipt in it. This is
# existing, untouched behaviour (receipt_present() unchanged for this case by
# task 2's fix); asserted here so a future change to that fail-open boundary
# does not slip past unnoticed.
chk_rule 'transcript empty (no receipt to find, not a read failure)' DENY "$fix/empty.jsonl" Bash 'gh issue create --title x'
chk_rule 'read-only command, no trigger mapped' ALLOW "$fix/rule-no-receipt.jsonl" Bash 'git status --short'

echo "== require-rule-read.sh: Windows tool calls are classified like the others (ww3d/playbook#276) =="
# Bash, PowerShell, backslash paths and the claude.ai connector names alike.
tool_event() { # transcript, tool, tool_input json, session
  jq -cn --arg t "$1" --arg n "$2" --argjson i "$3" --arg s "$4" \
    '{session_id: $s, transcript_path: $t, cwd: "/tmp", hook_event_name: "PreToolUse", tool_name: $n, tool_input: $i}'
}
chk_tool() { # label, expected, tool, tool_input json [project dir]
  local v; v="$(rule_verdict "$(tool_event "$fix/rule-no-receipt.jsonl" "$3" "$4" "$(next_sid)")" "${5:-}")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}
chk_tool 'Bash gh issue close'                       DENY  Bash       '{"command":"gh issue close 5"}'
chk_tool 'PowerShell gh issue create'                DENY  PowerShell '{"command":"gh issue create --title x"}'
chk_tool 'PowerShell gh pr create'                   DENY  PowerShell '{"command":"gh pr create --draft"}'
chk_tool 'PowerShell without gh'                     ALLOW PowerShell '{"command":"Get-ChildItem"}'
# A comment is evidence, as mcp__*__add_issue_comment already was (review
# round 1 of ww3d/playbook#289).
chk_tool 'Bash gh pr comment'                        DENY  Bash       '{"command":"gh pr comment 5 --body x"}'
chk_tool 'PowerShell gh issue comment'               DENY  PowerShell '{"command":"gh issue comment 5 --body x"}'
chk_tool 'mcp__claude_ai_GitHub_MCP__add_issue_comment' DENY mcp__claude_ai_GitHub_MCP__add_issue_comment '{}'
chk_tool 'NotebookEdit, notebook in the repo'        DENY  NotebookEdit "$(jq -cn --arg p "$repo_root/x.ipynb" '{notebook_path: $p}')"
chk_tool 'mcp__github__issue_write'                  DENY  mcp__github__issue_write '{}'
chk_tool 'mcp__claude_ai_GitHub_MCP__issue_write'    DENY  mcp__claude_ai_GitHub_MCP__issue_write '{}'
chk_tool 'mcp__claude_ai_GitHub_MCP__create_pull_request' DENY mcp__claude_ai_GitHub_MCP__create_pull_request '{}'
chk_tool 'mcp__claude_ai_GitHub_MCP__issue_read'     ALLOW mcp__claude_ai_GitHub_MCP__issue_read '{}'
chk_tool 'a non-GitHub MCP server with the same verb' ALLOW mcp__tracker__issue_write '{}'

# Backslash paths run everywhere: a POSIX project root, the file path spelled
# with backslashes.
bs_root="${repo_root//\//\\}"
chk_tool 'Write, backslash path to a .md in the repo'  DENY  Write "$(jq -cn --arg p "$bs_root\\docs\\x.md" '{file_path: $p}')"
chk_tool 'Edit, backslash path to code in the repo'    DENY  Edit  "$(jq -cn --arg p "$bs_root\\scripts\\x.ps1" '{file_path: $p}')"
chk_tool 'Write, backslash path outside the repo'      ALLOW Write "$(jq -cn --arg p "\\tmp\\x.md" '{file_path: $p}')"
chk_tool 'Write, forward-slash path in the repo (unchanged)' DENY Write "$(jq -cn --arg p "$repo_root/docs/x.md" '{file_path: $p}')"
# A state audit file owes the audit rule, under the new name and the old one (read until
# playbook 25.0.0, ww3d/playbook#356).
for audit_name in state-2026-01-01T0000Z.md ist-stand-2026-01-01T0000Z.md; do
  out="$(tool_event "$fix/rule-no-receipt.jsonl" Write "$(jq -cn --arg p "$repo_root/audit/$audit_name" '{file_path: $p}')" "$(next_sid)" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
  if printf '%s' "$out" | grep -qF '.agents/rules/audit.md'; then ok "Write audit/$audit_name owes the audit rule" found
  else bad "Write audit/$audit_name owes the audit rule" "$out" '.agents/rules/audit.md'; fi
done
# Drive letters need a real Windows path to exist, so this pair runs only
# where cygpath can produce one (Git Bash, MSYS, Cygwin).
if command -v cygpath >/dev/null 2>&1; then
  win_root="$(cygpath -w "$repo_root")"
  lower_root="$(printf '%s' "${win_root:0:1}" | tr '[:upper:]' '[:lower:]')${win_root:1}"
  chk_tool 'Windows root, drive-letter path in the repo'   DENY  Write "$(jq -cn --arg p "$win_root\\docs\\x.md" '{file_path: $p}')" "$win_root"
  chk_tool 'Windows root, lower-case drive letter'         DENY  Write "$(jq -cn --arg p "$lower_root\\docs\\x.md" '{file_path: $p}')" "$win_root"
  chk_tool 'Windows root, Git Bash spelling of the path'   DENY  Write "$(jq -cn --arg p "$repo_root/docs/x.md" '{file_path: $p}')" "$win_root"
  chk_tool 'Windows root, drive-letter path outside'       ALLOW Write "$(jq -cn --arg p "${win_root:0:2}\\elsewhere\\x.md" '{file_path: $p}')" "$win_root"
else
  printf '  skip %-52s %s\n' 'drive-letter cases' '(no cygpath: not a Windows bash)'
fi

echo "== require-rule-read.sh: no transcript read where no trigger can apply (ww3d/playbook#276) =="
# Shadow jq and grep with loggers. A call that cannot map to a trigger starts
# neither (decided on the raw payload with builtins alone); a call that maps
# to nothing after parsing starts jq once and never reads the transcript; a
# trigger whose receipt was already found in this session is not read again.
real_grep="$(command -v grep)"
calls="$fix/calls.log"
for helper in jq grep; do
  real="$(command -v "$helper")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$real" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
count_calls() { # label, expected jq/grep counts as "jq=N grep=M", event json
  local got
  : > "$calls"
  printf '%s' "$3" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" >/dev/null 2>&1
  got="jq=$("$real_grep" -c '^jq$' "$calls") grep=$("$real_grep" -c '^grep$' "$calls")"
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
}
nr="$fix/rule-no-receipt.jsonl"
count_calls 'Read: no process at all'           'jq=0 grep=0' "$(tool_event "$nr" Read '{"file_path":"/x/docs/a.md"}' "$(next_sid)")"
count_calls 'Bash without gh: no process at all' 'jq=0 grep=0' "$(tool_event "$nr" Bash '{"command":"git status"}' "$(next_sid)")"
count_calls 'a non-GitHub MCP tool: no process at all' 'jq=0 grep=0' "$(tool_event "$nr" mcp__claude_ai_Claude_Docs__read '{}' "$(next_sid)")"
count_calls 'the GitHub connector: judged' 'jq=1 grep=0' "$(tool_event "$nr" mcp__claude_ai_GitHub_MCP__issue_read '{}' "$(next_sid)")"
count_calls 'Write outside the repo: no transcript read' 'jq=1 grep=0' "$(tool_event "$nr" Write '{"file_path":"/elsewhere/a.md"}' "$(next_sid)")"
count_calls 'triggered call: one grep, one jq pass' 'jq=3 grep=1' "$(tool_event "$nr" Bash '{"command":"gh issue create"}' "$(next_sid)")"
cache_sid="$(next_sid)"
count_calls 'receipt found: read once'          'jq=2 grep=1' "$(tool_event "$fix/rule-receipt-text.jsonl" Bash '{"command":"gh issue create"}' "$cache_sid")"
count_calls 'receipt found before: not read again' 'jq=1 grep=0' "$(tool_event "$fix/rule-receipt-text.jsonl" Bash '{"command":"gh issue create"}' "$cache_sid")"
rm -f "$stub/jq" "$stub/grep"

echo "== require-receipt.sh: jq judges only the lines that can matter =="
# A transcript without a SessionStart or compaction line holds nothing to block, so the verdict
# jq never starts (two starts read the event); with such a line it starts once more.
printf '#!/usr/bin/env bash\nprintf "jq\\n" >> "%s"\nexec "%s" "$@"\n' "$calls" "$real_jq" > "$stub/jq"
chmod +x "$stub/jq"
noise="$fix/stop-noise.jsonl"
for i in $(seq 1 200); do
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Arbeit %s"}]}}\n' "$i"
done > "$noise"
stop_jq_starts() { # transcript
  : > "$calls"
  jq -cn --arg t "$1" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' | PATH="$stub:$PATH" bash "$stop" >/dev/null 2>&1
  "$real_grep" -c '^jq$' "$calls" || true
}
expect 'a transcript without markers: the verdict jq does not start' 2 "$(stop_jq_starts "$noise")"
expect 'a transcript with a SessionStart: the verdict jq starts'      3 "$(stop_jq_starts "$fix/with-receipt.jsonl")"
rm -f "$stub/jq"

echo "== require-rule-read.sh: a missing helper degrades to allow, never to block =="
# Only jq: the hook guards it explicitly (`command -v jq >/dev/null 2>&1 ||
# exit 0`, line ~44) precisely because it is the one dependency that is not
# guaranteed to exist everywhere bash does. The payload read (`$(</dev/stdin)`)
# is a bash builtin and needs no helper, so there is nothing else to lose.
printf '#!/usr/bin/env bash\nexit 127\n' > "$stub/jq"
chmod +x "$stub/jq"
out="$(printf '%s' "$(rule_event "$fix/rule-no-receipt.jsonl" Bash 'gh issue create --title x' "$(next_sid)")" \
  | CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'deny'; then
  ok "without jq" "ALLOW rc=0"
else
  bad "without jq" "rc=$rc out=$out" "ALLOW rc=0"
fi
rm -f "$stub/jq"

echo "== require-rule-read.sh: a jq failure in receipt_present() must still allow, never block =="
# read_receipts() judges the grep-narrowed lines in one `jq -nRr` pass (the
# only call with that flag set); any exit other than 0 there counts as "every
# receipt present" (fail-open). Shadow jq so that call fails (exit 2) while the
# field extraction and the `command -v jq` probe still work. The DENY cases
# above are the success path of the same code.
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-nRr" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
chmod +x "$stub/jq"
out="$(printf '%s' "$(rule_event "$fix/rule-no-receipt.jsonl" Bash 'gh issue create --title x' "$(next_sid)")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'deny'; then
  ok "read_receipts() jq failure" "ALLOW rc=0"
else
  bad "read_receipts() jq failure" "rc=$rc out=$out" "ALLOW rc=0"
fi
rm -f "$stub/jq"

# The same for grep: exit 2 is a read error, not "no line matched" (exit 1,
# which is the evidence the DENY cases rest on), and must allow.
printf '#!/usr/bin/env bash\nexit 2\n' > "$stub/grep"
chmod +x "$stub/grep"
out="$(printf '%s' "$(rule_event "$fix/rule-no-receipt.jsonl" Bash 'gh issue create --title x' "$(next_sid)")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'deny'; then
  ok "read_receipts() grep read error" "ALLOW rc=0"
else
  bad "read_receipts() grep read error" "rc=$rc out=$out" "ALLOW rc=0"
fi
rm -f "$stub/grep"

echo "== read-confirm.sh: the short receipt =="
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

run_readconfirm() {
  CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$rc_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm"
}

check_contains() { # label, needle, haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1" "found"
  else bad "$1" "not found: $2" "found"; fi
}
check_not_contains() { # label, needle, haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "found: $2" "not found"
  else ok "$1" "not found"; fi
}

ctx1="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
n_lines="$(printf '%s\n' "$ctx1" | grep -c . || true)"
if [ "${n_lines:-0}" -le 6 ]; then ok 'the receipt has at most six lines' "$n_lines"; else bad 'the receipt has at most six lines' "$n_lines" '<= 6'; fi
check_contains 'heading says once per start (ww3d/playbook#337)' \
  'give it once per session start or compaction, never repeat it unprompted per turn' "$ctx1"
sha_agents="$(git hash-object "$rc_root/AGENTS.md")"; sha_claude="$(git hash-object "$rc_root/CLAUDE.md")"
sha_audit="$(git hash-object "$rc_root/audit/state-2026-02-02T0000Z.md")"
check_contains 'first line: version and the core SHAs, the newest audit' \
  "Playbook 1.0.0 | Core AGENTS.md ${sha_agents:0:7} · CLAUDE.md ${sha_claude:0:7} · Audit state-2026-02-02T0000Z.md ${sha_audit:0:7}" "$ctx1"
check_contains 'rule index: count and triggers'  'Rules 2: code docs' "$ctx1"
check_contains 'skills counted'                   'Skills 2 · Stop hook require-receipt.sh' "$ctx1"
check_contains 'Memory honest fallback when nothing is found' \
  'Memory: — (not available in this environment)' "$ctx1"
check_not_contains 'no newer-version line without a network answer' 'Newer playbook version' "$ctx1"
# The old audit name is read until playbook 25.0.0 (ww3d/playbook#356): the newest stamp wins
# across both names.
printf '# audit c\n' > "$rc_root/audit/ist-stand-2026-03-03T0000Z.md"
check_contains 'a newer audit under the old name is still the newest' \
  'Audit ist-stand-2026-03-03T0000Z.md' "$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
rm "$rc_root/audit/ist-stand-2026-03-03T0000Z.md"

# A changed core file shows its new SHA.
printf '# Test Project (geaendert)\n' > "$rc_root/CLAUDE.md"
ctx2="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
sha_claude2="$(git hash-object "$rc_root/CLAUDE.md")"
check_contains 'a changed CLAUDE.md shows its new SHA' "CLAUDE.md ${sha_claude2:0:7}" "$ctx2"
check_not_contains 'the old CLAUDE.md SHA is gone' "CLAUDE.md ${sha_claude:0:7}" "$ctx2"

# No rule index, no audit, no skills: every absent piece is named, none dropped.
bare="$fix/rc-bare"; mkdir -p "$bare"; git init -q "$bare"
ctx_bare="$(CLAUDE_PROJECT_DIR="$bare" TMPDIR="$fix/rc-tmp-bare" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'bare project: version unknown'   'Playbook unknown | Core AGENTS.md — not found · CLAUDE.md — not found · Audit — (none)' "$ctx_bare"
check_contains 'bare project: index missing'      'Rules — (index.json not found)' "$ctx_bare"
check_contains 'bare project: no skills'          'Skills 0 · Stop hook' "$ctx_bare"

# slugify() itself, in isolation: a backslash must become '-' like every other
# separator it lists (':', '/', '.'). GNU tr treats an unescaped '\/' in its
# SET1 as an escape for a bare '/', silently dropping the backslash CHARACTER
# from the set entirely - measured before this fix: 'D:\a.b/c:d' came out as
# 'D-\a-b-c-d' (an untranslated backslash still in the result), not
# 'D--a-b-c-d'. The two-cache-key collision this class of bug risks (two
# different project roots slugifying to the same cache file) is exactly what
# read-confirm.sh's own comment above the function promises does not happen.
slug_out="$(printf '%s' 'D:\a.b/c:d' | tr ':\\/.' '----')"
if [ "$slug_out" = 'D--a-b-c-d' ]; then ok 'slugify translates a backslash like every other separator' "$slug_out"
else bad 'slugify translates a backslash like every other separator' "$slug_out" 'D--a-b-c-d'; fi

# Memory group, positive case: a MEMORY.md index this environment CAN see.
rc_config_hit="$fix/rc-config-hit"
mem_slug="$(printf '%s' "$rc_root" | tr ':\\/.' '----')"
mem_dir="$rc_config_hit/projects/$mem_slug/memory"
mkdir -p "$mem_dir"
cat > "$mem_dir/MEMORY.md" <<'EOF'
# Memory Index
- [Eins](eins.md) — hook
- [Zwei](zwei.md) — hook
- [Drei](drei.md) — hook
EOF
ctx_mem="$(CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$fix/rc-tmp-mem" CLAUDE_CONFIG_DIR="$rc_config_hit" bash "$readconfirm" \
  | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'Memory counts real MEMORY.md entries when found' 'Memory: 3 entries (MEMORY.md)' "$ctx_mem"

# Negative case (review round 1 of ww3d/playbook#233): only a FOREIGN project's memory
# exists under this CLAUDE_CONFIG_DIR - the own slug never matches, so the
# honest "not available" line is expected, not the fallback that used to pick
# up whichever memory/MEMORY.md it found first regardless of whose it was.
rc_config_foreign="$fix/rc-config-foreign"
foreign_dir="$rc_config_foreign/projects/some-other-project/memory"
mkdir -p "$foreign_dir"
printf '# Memory Index\n- [Eins](eins.md) — hook\n' > "$foreign_dir/MEMORY.md"
ctx_foreign="$(CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$fix/rc-tmp-foreign" CLAUDE_CONFIG_DIR="$rc_config_foreign" bash "$readconfirm" \
  | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'a foreign project memory is never reported as this one'"'"'s own' \
  'Memory: — (not available in this environment)' "$ctx_foreign"

echo "== read-confirm.sh: a newer playbook version, only where the network answers =="
# A local repository stands in for the playbook's: three version tags and a non-version tag.
remote="$fix/remote"; git init -q "$remote"
git -C "$remote" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
for tag in v0.9.0 v1.0.0 v1.2.0 v1.10.0 nightly; do git -C "$remote" tag "$tag"; done
version_ctx() { # remote, [version file content], [source], [TMPDIR]
  printf '%s\n' "${2:-1.0.0}" > "$rc_root/VERSION"
  printf '{"session_id":"v","source":"%s"}' "${3:-startup}" \
    | CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="${4:-$rc_tmp}" CLAUDE_CONFIG_DIR="$rc_config" READ_CONFIRM_REMOTE="$1" bash "$readconfirm" \
    | jq -r '.hookSpecificOutput.additionalContext'
}
check_contains 'the newest tag is compared numerically (1.10.0 beats 1.2.0)' \
  'Newer playbook version: v1.10.0' "$(version_ctx "$remote")"
check_not_contains 'an equal version is silent'  'Newer playbook version' "$(version_ctx "$remote" 1.10.0)"
check_not_contains 'a newer local version is silent' 'Newer playbook version' "$(version_ctx "$remote" 2.0.0)"
check_not_contains 'an unreachable remote is silent' 'Newer playbook version' "$(version_ctx "$fix/no-such-remote")"
slow="$fix/slow-git"; mkdir -p "$slow"
printf '#!/usr/bin/env bash\ncase "$*" in *ls-remote*) exec sleep 8 ;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$slow/git"
chmod +x "$slow/git"
t0=$SECONDS
slow_ctx="$(PATH="$slow:$PATH" version_ctx "$remote" 1.0.0 startup "$fix/rc-tmp-slow")"
if [ $((SECONDS - t0)) -lt 4 ]; then ok 'a hanging lookup is cut off after about a second' "$((SECONDS - t0)) s"
else bad 'a hanging lookup is cut off after about a second' "$((SECONDS - t0)) s" '< 4 s'; fi
check_not_contains 'a hanging lookup is silent' 'Newer playbook version' "$slow_ctx"
# Only a fresh start asks; a resume, clear or compaction does not, though the remote answers.
for src in resume clear compact; do
  check_not_contains "source $src: no lookup" 'Newer playbook version' "$(version_ctx "$remote" 1.0.0 "$src" "$fix/rc-tmp-$src")"
done
# The answer is kept for a day: the same start with the remote gone still shows the line,
# a cache older than a day is asked again, and a failed lookup is not kept.
vc_tmp="$fix/rc-tmp-cache"
check_contains 'the first start asks and keeps the answer' 'Newer playbook version: v1.10.0' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
mv "$remote" "$remote.gone"
check_contains 'a second start within a day reads the kept answer' \
  'Newer playbook version: v1.10.0' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
for cache_file in "$vc_tmp"/claude-rule-gate/newer-*; do sed -i '1s/.*/1/' "$cache_file"; done
check_not_contains 'a cache older than a day is asked again (remote gone: silent)' \
  'Newer playbook version' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
mv "$remote.gone" "$remote"
check_contains 'the failed lookup was not kept: the next start asks again' \
  'Newer playbook version: v1.10.0' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
# The receipt stays within six lines even with the newer-version line.
n_with_newer="$(version_ctx "$remote" 1.0.0 startup "$fix/rc-tmp-lines" | grep -c . || true)"
if [ "${n_with_newer:-0}" -le 6 ]; then ok 'six lines at most, the newer-version line included' "$n_with_newer"
else bad 'six lines at most, the newer-version line included' "$n_with_newer" '<= 6'; fi
printf '1.0.0\n' > "$rc_root/VERSION"

echo "== read-confirm.sh: markers of ended sessions are swept on a fresh start =="
sweep_tmp="$fix/rc-tmp-sweep"; mkdir -p "$sweep_tmp/claude-rule-gate"
: > "$sweep_tmp/claude-rule-gate/old-session-read-main-code"; touch -d '10 days ago' "$sweep_tmp/claude-rule-gate/old-session-read-main-code"
: > "$sweep_tmp/claude-rule-gate/fresh-session-read-main-code"
version_ctx "$fix/no-such-remote" 1.0.0 resume "$sweep_tmp" >/dev/null
present_file() { if [ -e "$2" ]; then ok "$1" kept; else bad "$1" removed kept; fi; }
absent_file() { if [ -e "$2" ]; then bad "$1" kept removed; else ok "$1" removed; fi; }
present_file 'a resume leaves a week-old marker alone' "$sweep_tmp/claude-rule-gate/old-session-read-main-code"
version_ctx "$fix/no-such-remote" 1.0.0 startup "$sweep_tmp" >/dev/null
absent_file 'a fresh start removes a marker older than a week' "$sweep_tmp/claude-rule-gate/old-session-read-main-code"
present_file 'a fresh start keeps a recent marker' "$sweep_tmp/claude-rule-gate/fresh-session-read-main-code"

echo "== read-confirm.sh: reports whether the Stop hook is wired (ww3d/playbook#171 (b)) =="
# Each case builds its own project, user and managed directory. The pairs: a
# registration at every level the hook can read is found (the false-alarm
# direction), and each way a registration is present but inert is reported.
# shellcheck disable=SC2016 # the settings file must hold ${CLAUDE_PROJECT_DIR} literally
stop_entry='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash","args":["${CLAUDE_PROJECT_DIR}/.claude/hooks/require-receipt.sh"]}]}]}}'
gate_case=0
bash_bin="$(command -v bash)"
gate_setup() { # sets g_root, g_cfg, g_mgd: empty project with the hook file, empty user and managed dirs
  gate_case=$((gate_case + 1))
  g_root="$fix/gate-$gate_case/root"; g_cfg="$fix/gate-$gate_case/cfg"; g_mgd="$fix/gate-$gate_case/mgd"
  mkdir -p "$g_root/.claude/hooks" "$g_cfg" "$g_mgd"
  printf '#!/usr/bin/env bash\n' > "$g_root/.claude/hooks/require-receipt.sh"
}
gate_line() { # [PATH override] - the receipt's Stop-Hook line for the current case
  CLAUDE_PROJECT_DIR="$g_root" TMPDIR="$fix/gate-$gate_case" CLAUDE_CONFIG_DIR="$g_cfg" \
    READ_CONFIRM_MANAGED_DIR="$g_mgd" PATH="${1:-$PATH}" "$bash_bin" "$readconfirm" \
    | jq -r '.hookSpecificOutput.additionalContext' | grep '^Skills'
}
chk_gate() { # label, expected substring
  local got; got="$(gate_line)"
  if printf '%s' "$got" | grep -qF -- "$2"; then ok "$1" "found"
  else bad "$1" "$got" "$2"; fi
}

gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
chk_gate 'registered in the project settings'  'Stop hook require-receipt.sh registered (Project)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.local.json"
chk_gate 'registered in the local settings'    'registered (Local)'
gate_setup; printf '%s' "$stop_entry" > "$g_cfg/settings.json"
chk_gate 'registered in the user settings only' 'registered (User)'
gate_setup; mkdir -p "$g_mgd/managed-settings.d"; printf '%s' "$stop_entry" > "$g_mgd/managed-settings.d/10-gate.json"
chk_gate 'registered in a managed drop-in'     'registered (Managed)'
gate_setup
# shellcheck disable=SC2016 # the settings file must hold $CLAUDE_PROJECT_DIR literally
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \\"$CLAUDE_PROJECT_DIR/.claude/hooks/require-receipt.sh\\""}]}]}}' \
  > "$g_root/.claude/settings.json"
chk_gate 'registered in the shell form'        'registered (Project)'

gate_setup
chk_gate 'no settings file anywhere'           '— registered in no readable settings file (read: none)'
chk_gate 'not found names what it cannot see'  '/hooks shows them all'
gate_setup
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash","args":["x/require-receipt.sh"]}]}]}}' \
  > "$g_root/.claude/settings.json"
chk_gate 'registered under SessionStart, not Stop' '(read: Project)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; rm "$g_root/.claude/hooks/require-receipt.sh"
chk_gate 'registered, hook file missing'       'registered (Project); .claude/hooks/require-receipt.sh missing or unreadable'
gate_setup; printf '{"hooks": {' > "$g_root/.claude/settings.json"; printf '%s' "$stop_entry" > "$g_cfg/settings.json"
chk_gate 'broken project JSON beside a user registration' 'registered (User); invalid JSON: Project'

gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"disableAllHooks": true}' > "$g_root/.claude/settings.local.json"
chk_gate 'disableAllHooks in the local settings' 'turned off by disableAllHooks (Local)'
gate_setup; printf '{"disableAllHooks": false, "hooks": %s}' "$(printf '%s' "$stop_entry" | jq -c .hooks)" \
  > "$g_root/.claude/settings.json"
printf '{"disableAllHooks": true}' > "$g_cfg/settings.json"
chk_gate 'a project false outranks a user true' 'registered (Project)'
gate_setup; printf '%s' "$stop_entry" > "$g_mgd/managed-settings.json"
printf '{"disableAllHooks": true}' > "$g_root/.claude/settings.json"
chk_gate 'a project disableAllHooks leaves a managed hook running' 'registered (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.json"
chk_gate 'allowManagedHooksOnly blocks a project registration' 'blocked by allowManagedHooksOnly (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_root/.claude/settings.local.json"
chk_gate 'allowManagedHooksOnly outside Managed has no effect' 'registered (Project)'

# Managed files merge base first, then the drop-ins in name order; the later
# file wins a single value. Each pair contradicts itself in both directions.
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"disableAllHooks": true}' > "$g_mgd/managed-settings.d/10-a.json"
printf '{"disableAllHooks": false}' > "$g_mgd/managed-settings.d/20-b.json"
chk_gate 'a later drop-in false outranks an earlier true' 'registered (Project)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"disableAllHooks": false}' > "$g_mgd/managed-settings.d/10-a.json"
printf '{"disableAllHooks": true}' > "$g_mgd/managed-settings.d/20-b.json"
chk_gate 'a later drop-in true outranks an earlier false' 'turned off by disableAllHooks (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.json"
printf '{"allowManagedHooksOnly": false}' > "$g_mgd/managed-settings.d/10-a.json"
chk_gate 'a drop-in outranks the managed base file' 'registered (Project)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"allowManagedHooksOnly": false}' > "$g_mgd/managed-settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.d/10-a.json"
chk_gate 'a drop-in true outranks a base false' 'blocked by allowManagedHooksOnly (Managed)'

# Without jq the Stop hook itself cannot judge; the line says so rather than
# guessing. PATH then holds only what read-confirm.sh needs besides bash.
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
nojq="$fix/gate-nojq"; mkdir -p "$nojq"
for helper in git grep mv rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$(command -v bash)" "$(command -v "$helper")" > "$nojq/$helper"
  chmod +x "$nojq/$helper"
done
got="$(gate_line "$nojq")"
if printf '%s' "$got" | grep -qF 'jq missing'; then ok 'without jq' 'found'; else bad 'without jq' "$got" 'jq missing'; fi
# A failing jq must leave a valid receipt, never an aborted hook.
printf '#!/usr/bin/env bash\nexit 2\n' > "$stub/jq"; chmod +x "$stub/jq"
got="$(gate_line "$stub:$PATH")"
if printf '%s' "$got" | grep -qF 'settings not readable (jq error)'; then ok 'jq failing on the settings' 'found'
else bad 'jq failing on the settings' "$got" 'settings not readable (jq error)'; fi
rm -f "$stub/jq"

echo "== read-confirm.sh: process starts do not grow with the number of files (ww3d/playbook#275) =="
# Under Git Bash each process start costs tens of milliseconds; a start per
# listed file took 67-96 s on a real repository. Shadow every external command
# the hook has ever used with a logger, and hold the total to a small constant
# across a project of 40 docs, cold and warm.
many="$fix/rc-many"
mkdir -p "$many/docs" "$many/tech/common" "$fix/rc-tmp-many"
git init -q "$many"
printf '# P\n' > "$many/CLAUDE.md"; printf '# A\n' > "$many/AGENTS.md"
for i in $(seq 1 40); do printf '# Doc %s\n\nbuild %s\n' "$i" "$i" > "$many/docs/d$i.md"; done
printf '1.0.0\n' > "$many/VERSION"
calls="$fix/rc-calls.log"
for helper in git grep awk sed head tr mktemp mv cat basename; do
  real="$(command -v "$helper")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$real" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
for run in cold warm; do
  : > "$calls"
  CLAUDE_PROJECT_DIR="$many" TMPDIR="$fix/rc-tmp-many" CLAUDE_CONFIG_DIR="$rc_config" PATH="$stub:$PATH" bash "$readconfirm" >/dev/null
  n_calls="$("$real_grep" -c . "$calls" || true)"
  if [ "${n_calls:-0}" -le 3 ]; then ok "40 docs, $run: at most 3 process starts" "$n_calls"
  else bad "40 docs, $run: at most 3 process starts" "$n_calls ($(tr '\n' ' ' < "$calls"))" "<= 3"; fi
done
for helper in git grep awk sed head tr mktemp mv cat basename; do rm -f "$stub/$helper"; done

echo "== record-rule-read.sh + require-rule-read.sh: the real read is the state =="
# A PostToolUse payload for Read, shaped like the one measured with Claude Code 2.1.293
# (tool_input.file_path, tool_response.file.{startLine,numLines,totalLines}, agent_id only inside a sub-agent).
read_event() { # session, file_path, [agent_id], [tool_input extra json], [tool_response file json]
  local extra='{}' span='{"startLine":1,"numLines":10,"totalLines":10}'
  jq -cn --arg s "$1" --arg p "$2" --arg a "${3:-}" --argjson x "${4:-$extra}" \
    --argjson r "${5:-$span}" \
    '{session_id: $s, transcript_path: "/tmp/none.jsonl", cwd: "/nonexistent", hook_event_name: "PostToolUse",
      tool_name: "Read", tool_input: ({file_path: $p} + $x), tool_response: {type: "text", file: ($r + {filePath: $p})}}
     + (if $a == "" then {} else {agent_id: $a, agent_type: "general-purpose"} end)'
}
record() { printf '%s' "$1" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$recorder"; }
# `gh issue create` maps to the carrier rule alone; the project root is this checkout, whose rule file exists.
gate_for() { # session, [agent_id] -> verdict of a carrier-triggering call
  local ev
  ev="$(jq -cn --arg s "$1" --arg a "${2:-}" '{session_id: $s, transcript_path: "/nonexistent.jsonl", cwd: "/tmp",
      hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "gh issue create --title x"}}
      + (if $a == "" then {} else {agent_id: $a} end)')"
  rule_verdict "$ev"
}
rule_abs="$repo_root/.agents/rules/carrier.md"
# A missing transcript would fail open; the receipt source is exercised elsewhere, so give the gate an empty one.
gate_for_empty() { # session, [agent_id]
  local ev
  ev="$(jq -cn --arg s "$1" --arg a "${2:-}" --arg t "$fix/empty.jsonl" '{session_id: $s, transcript_path: $t, cwd: "/tmp",
      hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "gh issue create --title x"}}
      + (if $a == "" then {} else {agent_id: $a} end)')"
  rule_verdict "$ev"
}
sid="read-a-$$"
expect 'before any read: the first action is refused' DENY "$(gate_for_empty "$sid")"
record "$(read_event "$sid" "$rule_abs")"
expect 'after a whole-file Read of the rule: allowed, no receipt line needed' ALLOW "$(gate_for_empty "$sid")"

sid="read-b-$$"
record "$(read_event "$sid" "$rule_abs" "" '{"offset":5,"limit":3}' '{"startLine":5,"numLines":3,"totalLines":40}')"
expect 'a partial range does not count' DENY "$(gate_for_empty "$sid")"
record "$(read_event "$sid" "$rule_abs" "" '{"offset":1,"limit":2000}' '{"startLine":1,"numLines":40,"totalLines":40}')"
expect 'an explicit range that covers the whole file counts' ALLOW "$(gate_for_empty "$sid")"

sid="read-c-$$"
record "$(read_event "$sid" "$repo_root/docs/overview.md")"
record "$(read_event "$sid" "$repo_root/.agents/rules/local/carrier.md")"
record "$(read_event "$sid" "$repo_root/.agents/rules/not-a-trigger.md")"
expect 'reading some other file does not count' DENY "$(gate_for_empty "$sid")"
bs_path="${rule_abs//\//\\}"
record "$(read_event "$sid" "$bs_path")"
expect 'a backslash path counts like a slash path' ALLOW "$(gate_for_empty "$sid")"

sid="read-d-$$"
record "$(read_event "$sid" "$rule_abs")"
rc_sid="$sid"
rc_event compact | CLAUDE_PROJECT_DIR="$repo_root" TMPDIR="$gate_tmp" bash "$readconfirm" >/dev/null
expect 'a compaction ends the read state' DENY "$(gate_for_empty "$sid")"

echo "== require-rule-read.sh: a sub-agent has to read the file itself =="
sid="read-e-$$"
record "$(read_event "$sid" "$rule_abs")"
expect 'the main thread read it: the sub-agent still is refused' DENY "$(gate_for_empty "$sid" agent-1)"
record "$(read_event "$sid" "$rule_abs" agent-1)"
expect 'the sub-agent read it itself: it passes' ALLOW "$(gate_for_empty "$sid" agent-1)"
expect 'another sub-agent is not covered by it' DENY "$(gate_for_empty "$sid" agent-2)"
sid="read-f-$$"
record "$(read_event "$sid" "$rule_abs" agent-1)"
expect 'a read inside a sub-agent does not unlock the main thread' DENY "$(gate_for_empty "$sid")"
# The typed receipt stays a second source, read from the sub-agent's own transcript.
sa="$fix/sa"; mkdir -p "$sa/main/subagents"
cp "$fix/rule-no-receipt.jsonl" "$sa/main.jsonl"
cp "$fix/rule-receipt-text.jsonl" "$sa/main/subagents/agent-A1.jsonl"
sa_event() { # agent id
  jq -cn --arg t "$sa/main.jsonl" --arg a "$1" --arg s "$(next_sid)" '{session_id: $s, transcript_path: $t, cwd: "/tmp",
    hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "gh issue create --title x"}}
    + (if $a == "" then {} else {agent_id: $a} end)'
}
expect 'a receipt in the sub-agent'"'"'s own transcript counts for it' ALLOW "$(rule_verdict "$(sa_event A1)")"
expect 'the same receipt does not count for the main thread' DENY "$(rule_verdict "$(sa_event "")")"

echo "== require-rule-read.sh: the denial names path and blob SHA, never the file =="
sid="deny-$$"
deny_out="$(printf '%s' "$(jq -cn --arg s "$sid" --arg t "$fix/empty.jsonl" '{session_id: $s, transcript_path: $t, cwd: "/tmp",
    hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "gh issue create --title x"}}')" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread")"
want_sha="$(git hash-object "$rule_abs")"
check_contains 'the denial carries the path'     '.agents/rules/carrier.md' "$deny_out"
check_contains 'the denial carries the blob SHA' "$want_sha" "$deny_out"
body_line="$(grep -m1 -E '^[A-Za-z].{40,}' "$rule_abs" | cut -c1-60)"
check_not_contains 'the denial holds no line of the file' "$body_line" "$deny_out"
deny_out2="$(printf '%s' "$(jq -cn --arg s "$sid" --arg t "$fix/empty.jsonl" '{session_id: $s, transcript_path: $t, cwd: "/tmp",
    hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "gh issue create --title x"}}')" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread")"
check_not_contains 'a second denial still holds no file text (no stage 2)' 'BEGIN' "$deny_out2"
check_not_contains 'a second denial still holds no line of the file' "$body_line" "$deny_out2"

echo "== record-rule-read.sh: no process for a Read of any other file, fail-open on junk =="
for helper in jq grep git; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$(command -v "$helper")" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
: > "$calls"
printf '%s' "$(read_event "x-$$" "/work/src/Program.cs")" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$recorder"
printf '%s' "$(read_event "x-$$" "$rule_abs")" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$recorder"
if [ ! -s "$calls" ]; then ok 'no jq, grep or git start, for a rule read either' 'none'; else bad 'no process start' "$(tr '\n' ' ' < "$calls")" 'none'; fi
rm -f "$stub/jq" "$stub/grep" "$stub/git"
out="$(printf 'not json at all' | TMPDIR="$gate_tmp" bash "$recorder" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok 'a junk payload records nothing and exits 0' 'rc=0'; else bad 'a junk payload' "rc=$rc $out" 'rc=0'; fi

echo "== record-rule-read.sh: a skill reference file is recorded like a rule file =="
marker_dir="$gate_tmp/claude-rule-gate"
skill_ref="$repo_root/.claude/skills/pr-poll-review/reference/gates.md"
n_markers() { find "$marker_dir" -type f 2>/dev/null | wc -l | tr -d ' '; }
sid="ref-a-$$"
record "$(read_event "$sid" "$skill_ref")"
present_file 'a whole-file Read leaves the marker named for skill and file' "$marker_dir/${sid}-read-main-skill-pr-poll-review-gates"
sid="ref-b-$$"
record "$(read_event "$sid" "$skill_ref" "" '{"offset":5,"limit":3}' '{"startLine":5,"numLines":3,"totalLines":40}')"
absent_file 'a partial range leaves no marker' "$marker_dir/${sid}-read-main-skill-pr-poll-review-gates"
record "$(read_event "$sid" "$skill_ref" "" '{"offset":1,"limit":2000}' '{"startLine":1,"numLines":40,"totalLines":40}')"
present_file 'a range covering the whole file leaves it' "$marker_dir/${sid}-read-main-skill-pr-poll-review-gates"
sid="ref-c-$$"
record "$(read_event "$sid" "$skill_ref" agent-7)"
present_file 'a read inside a sub-agent is named for the sub-agent' "$marker_dir/${sid}-read-agent-7-skill-pr-poll-review-gates"
before="$(n_markers)"
sid="ref-d-$$"
for odd in "$repo_root/.claude/skills/pr poll/reference/gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/reference/sub/gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/reference/../gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/reference/data.json" \
           "$repo_root/.claude/skills/pr-poll-review/reference/a b.md" \
           "$repo_root/docs/reference/gates.md" \
           "$repo_root/.claude/skills/pr-poll-review/SKILL.md"; do
  record "$(read_event "$sid" "$odd")"
done
record "$(read_event "bad/session id" "$skill_ref")"
record "$(read_event "$sid" "$skill_ref" "bad agent")"
expect 'odd paths, names and ids record nothing' "$before" "$(n_markers)"

echo "== record-rule-read.sh: only a file inside the project counts =="
sid="bind-$$"
record "$(read_event "$sid" "/elsewhere/.agents/rules/pr.md")"
absent_file 'a rule file of another checkout leaves no marker' "$marker_dir/${sid}-read-main-pr"
record "$(read_event "$sid" "$repo_root/../elsewhere/.agents/rules/pr.md")"
absent_file 'a path climbing out through .. leaves no marker' "$marker_dir/${sid}-read-main-pr"
record "$(read_event "$sid" "$repo_root/.agents/rules/pr.md")"
present_file 'the same rule file inside the project leaves it' "$marker_dir/${sid}-read-main-pr"
sid="bind-cwd-$$"
printf '%s' "$(read_event "$sid" "$repo_root/.agents/rules/pr.md" | jq -c --arg c "$repo_root" '.cwd = $c')" \
  | TMPDIR="$gate_tmp" env -u CLAUDE_PROJECT_DIR bash "$recorder"
present_file 'without CLAUDE_PROJECT_DIR the payload cwd is the root' "$marker_dir/${sid}-read-main-pr"
sid="bind-cwd2-$$"
printf '%s' "$(read_event "$sid" "$repo_root/.agents/rules/pr.md")" | TMPDIR="$gate_tmp" env -u CLAUDE_PROJECT_DIR bash "$recorder"
absent_file 'without CLAUDE_PROJECT_DIR a cwd elsewhere refuses it' "$marker_dir/${sid}-read-main-pr"

echo "== require-rule-read.sh: a local rule blocks the action its frontmatter names (ww3d/playbook#356) =="
lr_root="$fix/lr-root"
mkdir -p "$lr_root/.agents/rules/local" "$lr_root/docs"
printf -- '---\ntrigger: docs\nread-before: touching a doc\n---\n' > "$lr_root/.agents/rules/docs.md"
printf -- '---\ntrigger: terminology\nread-before: touching a doc\ngate: docs\n---\n\ngate: code\n' > "$lr_root/.agents/rules/local/terminology.md"
printf -- '---\ntrigger: deploy\nread-before: deploying\n---\n' > "$lr_root/.agents/rules/local/deploy.md"
printf -- '---\ntrigger: naming\nread-before: writing code\ngate: "code"\n---\n' > "$lr_root/.agents/rules/local/naming.md"
printf -- '---\r\ntrigger: both\r\nread-before: a doc or a PR\r\ngate: PR, Docs\r\n---\r\n' > "$lr_root/.agents/rules/local/both.md"
lr_doc="{\"file_path\":\"$lr_root/docs/x.md\",\"content\":\"x\"}"
lr_code="{\"file_path\":\"$lr_root/src/x.ps1\",\"content\":\"x\"}"
lr() { # session, tool_input, [markers]
  local m
  mkdir -p "$gate_tmp/claude-rule-gate"
  for m in ${3:-}; do : > "$gate_tmp/claude-rule-gate/$1-read-main-$m"; done
  rule_verdict "$(tool_event "$fix/empty.jsonl" Write "$2" "$1")" "$lr_root"
}
lr_out() { printf '%s' "$(tool_event "$fix/empty.jsonl" Write "$2" "$1")" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$lr_root" bash "$ruleread" 2>&1; }
sid="lr-a-$$"
expect 'docs read, the local docs rule not: refused'       DENY  "$(lr "$sid" "$lr_doc" docs)"
check_contains 'the denial names the local rule'           '.agents/rules/local/' "$(lr_out "$sid" "$lr_doc")"
check_contains 'the denial names the blocked action'       "the first 'docs' action" "$(lr_out "$sid" "$lr_doc")"
check_not_contains 'not the local rule'"'"'s trigger name'     "the first 'both' action" "$(lr_out "$sid" "$lr_doc")"
expect 'all docs rules read (state): allowed'              ALLOW "$(lr "$sid" "$lr_doc" 'local-terminology local-both')"
sid="lr-b-$$"
record_lr() { printf '%s' "$1" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$lr_root" bash "$recorder"; }
record_lr "$(read_event "$sid" "$lr_root/.agents/rules/docs.md")"
record_lr "$(read_event "$sid" "$lr_root/.agents/rules/local/terminology.md")"
expect 'one of two local docs rules read: still refused'   DENY  "$(lr "$sid" "$lr_doc")"
record_lr "$(read_event "$sid" "$lr_root/.agents/rules/local/both.md")"
expect 'the real Reads of both local rules: allowed'       ALLOW "$(lr "$sid" "$lr_doc")"
sid="lr-c-$$"
expect 'a local rule without gate never blocks'            ALLOW "$(lr "$sid" "$lr_code" 'code local-naming')"
expect 'a quoted gate value counts'                        DENY  "$(lr "lr-d-$$" "$lr_code" code)"
expect 'a gate line below the frontmatter is prose'        ALLOW "$(lr "lr-e-$$" "$lr_code" 'code local-naming')"
expect 'a local marker never stands in for the playbook'   DENY  "$(lr "lr-f-$$" "$lr_doc" 'local-docs local-terminology local-both')"
# The frontmatter is read like the rule index reads it: BOM, blanks around a line, outer quotes, a trailing comment.
lf_root="$fix/lf-root"; mkdir -p "$lf_root/.agents/rules/local"
printf -- '---\ntrigger: code\nread-before: writing code\n---\n' > "$lf_root/.agents/rules/code.md"
lf_run() { # frontmatter (printf format) -> the hook's stdout and stderr for a code write, code.md read
  local s; s="$(next_sid)"
  # shellcheck disable=SC2059 # the case is the format: its \xef, \r and \n escapes are the bytes under test
  printf -- "$1" > "$lf_root/.agents/rules/local/x.md"
  mkdir -p "$gate_tmp/claude-rule-gate"; : > "$gate_tmp/claude-rule-gate/${s}-read-main-code"
  printf '%s' "$(tool_event "$fix/empty.jsonl" Write "{\"file_path\":\"$lf_root/a.ps1\"}" "$s")" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$lf_root" bash "$ruleread" 2>"$fix/lf-err"
}
lf() { # label, expected (DENY|ALLOW|NOTE: no block, the unknown action said on stderr), frontmatter
  local out v
  out="$(lf_run "$3")"
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then v=DENY
  elif [ -z "$out" ] && [ ! -s "$fix/lf-err" ]; then v=ALLOW
  elif [ -z "$out" ] && grep -q 'is unknown and never blocks' "$fix/lf-err"; then v=NOTE
  else v="ERR($(cat "$fix/lf-err"))"; fi
  expect "$1" "$2" "$v"
}
lf 'a BOM before the opening ---'                 DENY  '\xef\xbb\xbf---\ngate: code\n---\n'
lf 'a BOM and CRLF line ends'                     DENY  '\xef\xbb\xbf---\r\ngate: code\r\n---\r\n'
lf '--- with a trailing blank, an indented gate'  DENY  '--- \n  gate: code\n  ---  \n'
lf 'a blank before the colon'                     DENY  '---\ngate : code\n---\n'
lf 'single quotes around the value'               DENY  "---\ngate: 'code'\n---\n"
# The generator keeps a trailing comment in the value and throws on the unknown action; the hook never blocks on it.
lf 'a trailing comment is part of the value'      NOTE  '---\ngate: code # the code rule\n---\n'
lf 'a quoted value with a trailing comment'       NOTE  '---\ngate: "docs, code"  # both\n---\n'
lf 'a comment as the whole value'                 NOTE  '---\ngate: # not yet\n---\n'
lf 'a blank inside an action'                     NOTE  '---\ngate: co de\n---\n'
lf 'blanks around the actions'                    DENY  '---\ngate:  docs ,  code  \n---\n'
lf 'a commented-out gate line'                    ALLOW '---\n# gate: code\n---\n'
# Keys compare without case and the last one wins, as in the generator's hashtable.
lf 'a gate key of another case is the gate'       DENY  '---\nGate: code\n---\n'
lf 'GATE in capitals is the gate'                 DENY  '---\nGATE: code\n---\n'
lf 'the last gate key wins (code)'                DENY  '---\ngate: docs\nGate: code\n---\n'
lf 'the last gate key wins (docs, a code write)'  ALLOW '---\ngate: code\ngate: docs\n---\n'
lf 'a gate after the closing --- is prose'        ALLOW '---\ntrigger: x\n --- \ngate: code\n'
lf 'no opening --- on line 1'                     ALLOW 'trigger: x\n---\ngate: code\n---\n'
out="$(lf_run '---\ngate: kode\n---\n')"
expect 'an unknown action does not block'         ''    "$out"
check_contains 'an unknown action is said on stderr' "gate action 'kode' is unknown" "$(cat "$fix/lf-err")"
check_contains 'the note names the file'          '.agents/rules/local/x.md' "$(cat "$fix/lf-err")"
out="$(lf_run '---\ngate: kode, code\n---\n')"
check_contains 'an unknown next to a known action: blocks' '"permissionDecision":"deny"' "$out"
check_contains 'and still says the unknown one'   "gate action 'kode' is unknown" "$(cat "$fix/lf-err")"
lf_run '---\ngate: docs, code\n---\n' >/dev/null
expect 'known actions only: no note'              ''    "$(cat "$fix/lf-err")"
# A file other than *.md in local/ is no rule: ignored, and named on stderr (ww3d/playbook#356, N19).
printf 'allowed_terms:\n  - x\n' > "$lf_root/.agents/rules/local/terminology.yml"
out="$(lf_run '---\ntrigger: x\n---\n')"
expect 'a settings file in local/ blocks nothing'  ''    "$out"
check_contains 'and is named as no rule file' '.agents/rules/local/terminology.yml is no rule file (*.md) and is ignored' "$(cat "$fix/lf-err")"
rm -f "$lf_root/.agents/rules/local/terminology.yml"
lr_nolocal="$fix/lr-nolocal"; mkdir -p "$lr_nolocal/.agents/rules"
cp "$lr_root/.agents/rules/docs.md" "$lr_nolocal/.agents/rules/"
: > "$gate_tmp/claude-rule-gate/lr-g-$$-read-main-docs"
expect 'no local directory: the playbook rule alone'       ALLOW "$(rule_verdict "$(tool_event "$fix/empty.jsonl" Write "{\"file_path\":\"$lr_nolocal/a.md\"}" "lr-g-$$")" "$lr_nolocal")"

echo "== require-rule-read.sh: the review post needs /pr-poll-review for the current head =="
rv_root="$fix/rv-root"
mkdir -p "$rv_root/.agents/rules" "$rv_root/.claude/skills/pr-poll-review"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rv_root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rv_root/.claude/skills/pr-poll-review/SKILL.md"
ghstub="$fix/ghstub"; mkdir -p "$ghstub"
cat > "$ghstub/gh" <<'STUB'
#!/usr/bin/env bash
[ -z "${STUB_GH_LOG:-}" ] || printf '%s\n' "$*" >> "$STUB_GH_LOG"
[ -z "${STUB_GH_FAIL:-}" ] || exit 1
printf '%s\n' "${STUB_GH_OUT:-}"
STUB
chmod +x "$ghstub/gh"
head_a="$(printf 'a%.0s' {1..40})"; head_b="$(printf 'b%.0s' {1..40})"
rv_last="$fix/rv-last.out"
rv_verdict() { # transcript, tool, tool_input json, gh stdout, [gh fails] [project dir] [extra markers] [gh log file]
  local sid out rc root="${6:-$rv_root}" m
  sid="$(next_sid)"
  mkdir -p "$gate_tmp/claude-rule-gate"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-review"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-evidence"
  for m in ${7:-}; do : > "$gate_tmp/claude-rule-gate/${sid}-read-main-${m}"; done
  out="$(printf '%s' "$(tool_event "$1" "$2" "$3" "$sid")" \
    | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$root" PATH="${RV_PATH:+$RV_PATH:}$ghstub:$PATH" STUB_GH_OUT="$4" STUB_GH_FAIL="${5:-}" STUB_GH_LOG="${8:-}" bash "$ruleread" 2>&1)"; rc=$?
  printf '%s' "$out" > "$rv_last"
  if   printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then printf 'DENY'
  elif [ -z "$out" ] && [ "$rc" = 0 ]; then printf 'ALLOW'
  elif printf '%s' "$out" | grep -q 'systemMessage' && [ "$rc" = 0 ]; then printf 'WARN'
  else printf 'ERR(rc=%s)' "$rc"; fi
}
gh_cmd='{"command":"gh pr review 5 -R o/r --approve --body ok"}'
gh_url="${head_a}" # what the stub prints for `gh api repos/o/r/pulls/5 --jq .head.sha`
expect 'no skill line at all'                              DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'skill line for the current head'                   ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'skill line, the PR head moved since'               DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "${head_b}")"
expect 'skill line for another PR'                         DENY  "$(rv_verdict "$fix/review-head-other-pr.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'the line only carried as data does not count'      DENY  "$(rv_verdict "$fix/review-head-data.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'a refused command does not count'                  DENY  "$(rv_verdict "$fix/review-head-refused.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'a compaction ends the skill run'                   DENY  "$(rv_verdict "$fix/review-head-then-compact.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'the repo name compares without case'               ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review 5 -R O/R --approve"}' "${head_a}")"
expect 'gh cannot answer, the PR is named, a line exists'  WARN  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "" 1)"
expect 'gh cannot answer, the PR is named, no line'        DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$gh_cmd" "" 1)"
expect 'gh cannot answer, another PR has the line'         DENY  "$(rv_verdict "$fix/review-head-other-pr.jsonl" Bash "$gh_cmd" "" 1)"
expect 'a PowerShell call is gated like a Bash call'       DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" PowerShell "$gh_cmd" "$gh_url")"
expect 'the PR given as a URL'                             ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review https://github.com/o/r/pull/5 --comment -b 7"}' "$gh_url")"
mcp_in='{"owner":"o","repo":"r","pullNumber":5,"method":"create","event":"APPROVE"}'
expect 'the connector: no skill line'                      DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write "$mcp_in" "$gh_url")"
expect 'the connector: skill line for the current head'    ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write "$mcp_in" "$gh_url")"
expect 'the connector: deleting a pending review is free'  ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write '{"owner":"o","repo":"r","pullNumber":5,"method":"delete_pending"}' "$gh_url")"
expect 'a comment on a pending review is not the post'     ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" mcp__claude_ai_GitHub_MCP__add_comment_to_pending_review '{"owner":"o","repo":"r","pullNumber":5}' "$gh_url")"
expect 'gh pr comment is not a review post'                ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh pr comment 5 --body x"}' "$gh_url")"
no_skill="$fix/rv-no-skill"; mkdir -p "$no_skill/.agents/rules"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$no_skill/.agents/rules/$r.md"; done
expect 'a repository without the skill demands nothing'    ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$gh_cmd" "$gh_url" "" "$no_skill")"

echo "== require-rule-read.sh: the reviews endpoint through gh api is the same post =="
api_post='{"command":"gh api repos/o/r/pulls/5/reviews -f event=APPROVE -f body=ok"}'
expect 'gh api POST to the reviews endpoint: no skill line'   DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash "$api_post" "$gh_url")"
expect 'gh api POST: skill line for the current head'         ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$api_post" "$gh_url")"
expect 'gh api POST: the PR head moved since'                 DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$api_post" "${head_b}")"
expect 'gh api with -X POST and an input file'                DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api -X POST repos/o/r/pulls/5/reviews --input r.json"}' "$gh_url")"
expect 'gh api through PowerShell'                            DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" PowerShell "$api_post" "$gh_url")"
expect 'a submit of a pending review (events)'                DENY  "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api repos/o/r/pulls/5/reviews/77/events -f event=COMMENT"}' "$gh_url")"
expect 'gh api GET of the reviews is a read'                  ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api repos/o/r/pulls/5/reviews"}' "$gh_url")"
expect 'gh api GET with a query field stays a read'           ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api --method GET repos/o/r/pulls/5/reviews -f per_page=1"}' "$gh_url")"
expect 'gh api to another endpoint is no review post'         ALLOW "$(rv_verdict "$fix/rule-no-receipt.jsonl" Bash '{"command":"gh api repos/o/r/pulls/5/comments -f body=x"}' "$gh_url")"
sid_api="$(next_sid)"
expect 'gh api also owes the review rule (unread: refused)'   DENY  "$(rule_verdict "$(tool_event "$fix/rule-no-receipt.jsonl" Bash "$api_post" "$sid_api")" "$rv_root")"
gh_log="$fix/gh-args.log"
gh_args() { # tool_input json -> the first gh call of the hook (the forge is asked for a PR with a skill line only)
  : > "$gh_log"
  rv_verdict "$fix/review-head-5-and-352.jsonl" Bash "$1" "$gh_url" "" "" "" "$gh_log" >/dev/null
  head -n1 "$gh_log"
}
expect 'gh api: the PR is read from the endpoint'             'api repos/o/r/pulls/5 --jq .head.sha' \
  "$(gh_args "$api_post")"

# A post that names no repository takes the one of the origin remote (https and ssh spelling).
rv_git="$fix/rv-git"
mkdir -p "$rv_git/.agents/rules" "$rv_git/.claude/skills/pr-poll-review"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rv_git/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rv_git/.claude/skills/pr-poll-review/SKILL.md"
git -C "$rv_git" init -q
git -C "$rv_git" remote add origin https://github.com/o/r.git
: > "$gh_log"
expect 'no -R: the repo comes from origin (https)'            ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review 5 --approve"}' "$gh_url" "" "$rv_git" "" "$gh_log")"
expect 'no -R: gh is asked for the origin repo'               'api repos/o/r/pulls/5 --jq .head.sha' "$(head -n1 "$gh_log")"
git -C "$rv_git" remote set-url origin git@github.com:o/r.git
: > "$gh_log"
rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review 5 --approve"}' "$gh_url" "" "$rv_git" "" "$gh_log" >/dev/null
expect 'no -R: the repo comes from origin (ssh)'              'api repos/o/r/pulls/5 --jq .head.sha' "$(head -n1 "$gh_log")"

echo "== require-rule-read.sh: gh pr review counts at a command position only =="
nr="$fix/rule-no-receipt.jsonl"
expect 'a commit message that names it'                  ALLOW "$(rv_verdict "$nr" Bash '{"command":"git commit -m \"docs: the gh pr review gate\""}' "$gh_url")"
expect 'a pr comment that names it'                      ALLOW "$(rv_verdict "$nr" Bash '{"command":"gh pr comment 5 --body \"see gh pr review 5\""}' "$gh_url")"
expect 'a single-quoted text that names it'              ALLOW "$(rv_verdict "$nr" Bash '{"command":"echo '"'"'gh pr review 5'"'"'"}' "$gh_url")"
expect 'an escaped quote does not end the text early'    ALLOW "$(rv_verdict "$nr" Bash '{"command":"git commit -m \"fix \\\"x\\\" gh pr review y\""}' "$gh_url")"
expect 'the post at the start, several spaces'           DENY  "$(rv_verdict "$nr" Bash '{"command":"gh   pr  review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post after &&'                               DENY  "$(rv_verdict "$nr" Bash '{"command":"cd x && gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post on a line of its own'                   DENY  "$(rv_verdict "$nr" Bash '{"command":"cd x\ngh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post behind an environment assignment'       DENY  "$(rv_verdict "$nr" Bash '{"command":"GH_TOKEN=x gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post with a path and .exe'                   DENY  "$(rv_verdict "$nr" Bash '{"command":"/usr/bin/gh.exe pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the post inside bash -c'                         DENY  "$(rv_verdict "$nr" Bash '{"command":"bash -c \"gh pr review 5 -R o/r --approve\""}' "$gh_url")"
expect 'the post inside a command substitution'          DENY  "$(rv_verdict "$nr" Bash '{"command":"echo \"$(gh pr review 5 -R o/r --approve)\""}' "$gh_url")"
expect 'the shell flag in capitals, quoted'              DENY  "$(rv_verdict "$nr" Bash '{"command":"pwsh -Command \"gh pr review 5 -R o/r --approve\""}' "$gh_url")"
expect 'the shell flag in capitals, unquoted'            DENY  "$(rv_verdict "$nr" Bash '{"command":"powershell -Command gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'cmd /c, quoted'                                  DENY  "$(rv_verdict "$nr" Bash '{"command":"cmd /c \"gh pr review 5 -R o/r --approve\""}' "$gh_url")"
expect 'cmd /c, unquoted'                                DENY  "$(rv_verdict "$nr" Bash '{"command":"cmd /c gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'cmd /K, unquoted'                                DENY  "$(rv_verdict "$nr" Bash '{"command":"CMD /K gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'bash -lc, unquoted'                              DENY  "$(rv_verdict "$nr" Bash '{"command":"bash -lc gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'the verb in capitals'                            DENY  "$(rv_verdict "$nr" Bash '{"command":"GH PR REVIEW 5 -R o/r --approve"}' "$gh_url")"
expect 'behind sudo with an option'                      DENY  "$(rv_verdict "$nr" Bash '{"command":"sudo -u x gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'behind env with an option'                       DENY  "$(rv_verdict "$nr" Bash '{"command":"env -i gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'behind timeout with a number'                    DENY  "$(rv_verdict "$nr" Bash '{"command":"timeout 5 gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'behind xargs'                                    DENY  "$(rv_verdict "$nr" Bash '{"command":"echo 5 | xargs gh pr review"}' "$gh_url")"
expect 'behind a wrapper with a path'                    DENY  "$(rv_verdict "$nr" Bash '{"command":"/usr/bin/env gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'options between gh and pr'                       DENY  "$(rv_verdict "$nr" Bash '{"command":"gh -R o/r pr review 5 --approve"}' "$gh_url")"
expect 'options between pr and review'                   DENY  "$(rv_verdict "$nr" Bash '{"command":"gh pr -R x review 5 --approve"}' "$gh_url")"
expect 'a switch before pr'                              DENY  "$(rv_verdict "$nr" Bash '{"command":"gh --paginate pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'options in the middle, behind sudo'              DENY  "$(rv_verdict "$nr" Bash '{"command":"sudo gh -R o/r pr review 5 --approve"}' "$gh_url")"
expect 'options in the middle: a skill line for the PR'  ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh -R o/r pr review 5 --approve"}' "$gh_url")"
expect 'options in the middle: the line is for another PR' DENY "$(rv_verdict "$fix/review-head-other-pr.jsonl" Bash '{"command":"gh pr -R o/r review 5 --approve"}' "$gh_url")"
expect 'gh -R ... pr view is no review'                  ALLOW "$(rv_verdict "$nr" Bash '{"command":"gh -R o/r pr view 5"}' "$gh_url")"
expect 'a quoted mention with options is no review'      ALLOW "$(rv_verdict "$nr" Bash '{"command":"git commit -m \"gh -R o/r pr review 5\""}' "$gh_url")"
# The target repo is read from the `gh` TOKEN: a "gh" inside a slug or a path is no `gh` word, and an attached
# `-Ro/r`, a `GH_REPO=` assignment and quoted values name the repo too. The line is for o/r#5 and the origin
# remote is o/r, so a lost repo option would fall back to o/r and ALLOW.
chk_target() { expect "$1" "$2" "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$3" "$gh_url" "" "$rv_git")"; }
chk_target 'slug with gh: -R ghost/x'                     DENY  '{"command":"gh -R ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: -R o/ghx'                       DENY  '{"command":"gh -R o/ghx pr review 5 --approve"}'
chk_target 'slug with gh: --repo ghost/x'                 DENY  '{"command":"gh --repo ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: --repo=ghost/x'                 DENY  '{"command":"gh --repo=ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: -R after pr'                    DENY  '{"command":"gh pr --repo ghost/x review 5 --approve"}'
chk_target 'slug with gh: gh behind a path'               DENY  '{"command":"/usr/bin/gh -R ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: a gh folder before the command' DENY  '{"command":"cd /tmp/gh && gh -R ghost/x pr review 5 --approve"}'
chk_target 'slug with gh: gh.exe'                         DENY  '{"command":"gh.exe -R ghost/x pr review 5 --approve"}'
chk_target '-R with the value attached'                   DENY  '{"command":"gh -Rghost/x pr review 5 --approve"}'
chk_target '-R with the value attached: the right repo'   ALLOW '{"command":"gh -Ro/r pr review 5 --approve"}'
chk_target 'quoted -R value'                              DENY  '{"command":"gh -R \"ghost/x\" pr review 5 --approve"}'
chk_target 'GH_REPO names another repo'                   DENY  '{"command":"GH_REPO=ghost/x gh pr review 5 --approve"}'
chk_target 'GH_REPO quoted'                               DENY  '{"command":"GH_REPO=\"ghost/x\" gh pr review 5 --approve"}'
chk_target 'GH_REPO behind env'                           DENY  '{"command":"env GH_REPO=ghost/x gh pr review 5 --approve"}'
chk_target 'GH_REPO names the repo of the line'           ALLOW '{"command":"GH_REPO=o/r gh pr review 5 --approve"}'
chk_target '-R beats GH_REPO'                             ALLOW '{"command":"GH_REPO=ghost/x gh -R o/r pr review 5 --approve"}'
# Any earlier `GH_REPO=` assignment is the target, exported or not (a later `export GH_REPO`, `declare -x`, `set -a`
# and `export A=1 GH_REPO=...` are not parsed: a plain one blocks too); `-R=o/r` is the repo o/r; `env -u` clears it.
chk_target 'GH_REPO set apart by ; counts as the target'  DENY  '{"command":"GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'GH_REPO, then export GH_REPO'                 DENY  '{"command":"GH_REPO=ghost/x; export GH_REPO; gh pr review 5 --approve"}'
chk_target 'declare -x GH_REPO='                          DENY  '{"command":"declare -x GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'export A=1 GH_REPO='                          DENY  '{"command":"export A=1 GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'export -- GH_REPO='                           DENY  '{"command":"export -- GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'set -a, then GH_REPO='                        DENY  '{"command":"set -a; GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'export GH_REPO with a quoted value'           DENY  '{"command":"export GH_REPO=\"ghost/x\"; gh pr review 5 --approve"}'
chk_target 'GH_REPO= of the repo of the line'             ALLOW '{"command":"GH_REPO=o/r; gh pr review 5 --approve"}'
chk_target 'an earlier GH_REPO= of another repo blocks'      DENY  '{"command":"GH_REPO=ghost/x; GH_REPO=o/r; gh pr review 5 --approve"}'
chk_target '-R=o/r'                                       ALLOW '{"command":"gh -R=o/r pr review 5 --approve"}'
chk_target '-R=ghost/x'                                   DENY  '{"command":"gh -R=ghost/x pr review 5 --approve"}'
chk_target 'env -u GH_REPO clears the target'             ALLOW '{"command":"GH_REPO=ghost/x env -u GH_REPO gh pr review 5 --approve"}'
chk_target 'env --unset=GH_REPO clears the target'        ALLOW '{"command":"GH_REPO=ghost/x env --unset=GH_REPO gh pr review 5 --approve"}'
chk_target 'env -u of another name keeps the target'      DENY  '{"command":"GH_REPO=ghost/x env -u FOO gh pr review 5 --approve"}'
# Every post of a command is checked, the target of an earlier `export` counts, a heredoc text does not hide the
# real call, and a `#` comment holds no command and no option. Any earlier `GH_REPO=` that differs from the checked
# target blocks, a prefix of another command too (fail-closed).
chk_target 'export GH_REPO earlier in the command'        DENY  '{"command":"export GH_REPO=ghost/x; gh pr review 5 --approve"}'
chk_target 'GH_REPO= as the prefix of another command'      DENY  '{"command":"export GH_REPO=ghost/x; GH_REPO=o/r gh pr view 5; gh pr review 5 --approve"}'
chk_target 'export GH_REPO of the line'                   ALLOW '{"command":"export GH_REPO=o/r; gh pr review 5 --approve"}'
chk_target 'export GH_REPO, then env -u (fail-closed)'      DENY  '{"command":"export GH_REPO=ghost/x; env -u GH_REPO gh pr review 5 --approve"}'
chk_target 'two posts, the second for another PR'         DENY  '{"command":"gh pr review 5 -R o/r --approve; gh pr review 6 -R o/r --approve"}'
chk_target 'two posts, both for the PR of the line'       ALLOW '{"command":"gh pr review 5 -R o/r --comment; gh pr review 5 -R o/r --approve"}'
chk_target 'a heredoc text before the real post'          DENY  '{"command":"cat <<EOF\ngh -R o/r pr review 5\nEOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a comment with -R is no option'               ALLOW '{"command":"gh pr review 5 --approve # -R ghost/x"}'
expect 'a comment that holds a post is no post'          ALLOW "$(rv_verdict "$nr" Bash '{"command":"echo hi # ; gh pr review 5 -R o/r --approve"}' "$gh_url")"
expect 'a # inside a word starts no comment'             DENY  "$(rv_verdict "$nr" Bash '{"command":"echo a#b; gh pr review 5 -R o/r --approve"}' "$gh_url")"
# Fail-closed: a `gh pr review` quoted in a heredoc body counts as a post, so a body that quotes one for a PR
# without a line blocks (a wanted false block) until the gate reads commands with a shell parser.
chk_target 'a heredoc text after the real post'           DENY '{"command":"gh pr review 5 -R o/r --approve; cat <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a body file by heredoc before the post'       DENY  '{"command":"cat > b.md <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF\ngh pr review 5 -R o/r --approve --body-file b.md"}'
chk_target 'a <<- heredoc with a tab-indented end'        DENY  '{"command":"cat <<-EOF\n\tgh pr review 6 -R o/r --approve\n\tEOF\ngh pr review 5 -R o/r --approve"}'
chk_target 'a heredoc body with an apostrophe'            DENY  '{"command":"cat <<EOF\nit'"'"'s fine\nEOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a heredoc read by bash holds a post'          DENY  '{"command":"bash <<'"'EOF'"'\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a heredoc piped to a shell holds a post'      DENY  '{"command":"cat <<EOF | sh\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'a heredoc without a closing line is kept'     DENY  '{"command":"cat <<EOF\ngh pr review 6 -R o/r --approve"}'
chk_target 'a here-string is no heredoc'                  DENY  '{"command":"cat <<<x\ngh pr review 6 -R o/r --approve\nEOF"}'
chk_target 'export GH_REPO inside a quoted text'          ALLOW '{"command":"echo \"export GH_REPO=ghost/x\"; gh pr review 5 --approve"}'
chk_target 'export GH_REPO in a subshell that ended'      ALLOW '{"command":"(export GH_REPO=ghost/x); gh pr review 5 --approve"}'
chk_target 'export GH_REPO in the same subshell'          DENY  '{"command":"(export GH_REPO=ghost/x; gh pr review 5 --approve)"}'
# A `#` starts a comment only behind an unescaped blank and outside `${...}`; a quote in a comment hides nothing.
chk_target 'an escaped blank before # is no comment'      DENY  '{"command":"echo \\ #; gh pr review 6 -R o/r --approve"}'
chk_target 'a # inside ${...} is no comment'              DENY  '{"command":"echo ${v:- #}; gh pr review 6 -R o/r --approve"}'
chk_target 'an apostrophe in a comment hides nothing'     DENY  '{"command":"echo hi # don'"'"'t\ngh pr review 6 -R o/r --approve\n# it'"'"'s"}'
chk_target 'a comment with an apostrophe after the post'  ALLOW '{"command":"gh pr review 5 -R o/r --approve # don'"'"'t worry"}'
chk_target 'a comment after a quoted span'                ALLOW '{"command":"echo \"x\" # ; gh pr review 6 -R o/r --approve"}'
expect 'several spaces: the PR is still read'            'api repos/o/r/pulls/5 --jq .head.sha' \
  "$(gh_args '{"command":"gh   pr  review 5 -R o/r --approve"}')"

echo "== require-rule-read.sh: the lines are checked offline first, the forge is asked once per PR =="
# The forge calls of one command share a 15 s deadline and the hook has 30 s: so a post without a line is refused
# before any call, and the posts of one PR share one call.
posts_5_6='{"command":"gh pr review 5 -R o/r --comment; gh pr review 5 -R o/r --comment; gh pr review 5 -R o/r --approve; gh pr review 6 -R o/r --approve"}'
: > "$gh_log"
expect 'a post on a PR without a line is refused'         DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$posts_5_6" "$gh_url" "" "" "" "$gh_log")"
check_contains 'the denial names the PR without a line'   'o/r#6' "$(cat "$rv_last")"
expect 'no gh call before that refusal'                  0     "$(wc -l < "$gh_log" | tr -d ' ')"
: > "$gh_log"
expect 'lines for both PRs, both heads current'           ALLOW "$(rv_verdict "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "$gh_url" "" "" "" "$gh_log")"
expect 'four posts on two PRs: one gh call per PR'       2     "$(wc -l < "$gh_log" | tr -d ' ')"
: > "$gh_log"
expect 'lines for both PRs, the heads moved'              DENY  "$(rv_verdict "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "${head_b}" "" "" "" "$gh_log")"
expect 'a stale head ends the hook after one gh call'     1     "$(wc -l < "$gh_log" | tr -d ' ')"

echo "== require-rule-read.sh: digits in a review body never replace the PR number =="
expect 'a body with a bare number'            'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review 352 -R o/r --approve -b \"LGTM, 2 nits fixed\""}')"
expect 'a body with a number, -R before the number'  'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r 352 --comment -b \"Siehe Punkt 3 unten\""}')"
expect 'a long body option, the number last'  'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r --approve --body \"3 nits, 4 questions\" 352"}')"
expect 'a body given with ='                 'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r 352 --body=\"fixes 7 of 9\""}')"
expect 'the first number wins over a later one' 'api repos/o/r/pulls/352 --jq .head.sha' \
  "$(gh_args '{"command":"gh pr review -R o/r 352 --approve 9"}')"

echo "== require-rule-read.sh: a review post needs gates.md and checks.md read (read state or receipt) =="
rf_root="$fix/rf-root"
mkdir -p "$rf_root/.agents/rules" "$rf_root/.claude/skills/pr-poll-review/reference"
for r in review evidence; do printf -- '---\ntrigger: %s\n---\n' "$r" > "$rf_root/.agents/rules/$r.md"; done
printf -- '---\nname: pr-poll-review\n---\n' > "$rf_root/.claude/skills/pr-poll-review/SKILL.md"
printf '# gates\n' > "$rf_root/.claude/skills/pr-poll-review/reference/gates.md"
printf '# checks\n' > "$rf_root/.claude/skills/pr-poll-review/reference/checks.md"
rf() { rv_verdict "$1" Bash "$gh_cmd" "$gh_url" "" "$rf_root" "${2:-}"; }
expect 'neither reference read, a current skill line'      DENY  "$(rf "$fix/review-head-a.jsonl")"
check_contains 'the denial names the first missing file'   '.claude/skills/pr-poll-review/reference/gates.md' "$(cat "$rv_last")"
check_contains 'the denial carries the blob SHA'           "$(git hash-object "$rf_root/.claude/skills/pr-poll-review/reference/gates.md")" "$(cat "$rv_last")"
expect 'gates.md read, checks.md not'                      DENY  "$(rf "$fix/review-head-a.jsonl" skill-pr-poll-review-gates)"
check_contains 'the denial now names checks.md'            '.claude/skills/pr-poll-review/reference/checks.md' "$(cat "$rv_last")"
expect 'both read (state)'                                 ALLOW "$(rf "$fix/review-head-a.jsonl" 'skill-pr-poll-review-gates skill-pr-poll-review-checks')"
expect 'both receipted (second source)'                    ALLOW "$(rf "$fix/review-refs-both.jsonl")"
expect 'only gates.md receipted'                           DENY  "$(rf "$fix/review-refs-gates-only.jsonl")"
expect 'a compaction ends the receipts'                    DENY  "$(rf "$fix/review-refs-then-compact.jsonl")"
expect 'a reader of another name does not count'           DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "$gh_url" "" "$rf_root" 'skill-pr-poll-review-gates skill-other-checks')"
expect 'the connector post owes the references too'        DENY  "$(rv_verdict "$fix/review-head-a.jsonl" mcp__claude_ai_GitHub_MCP__pull_request_review_write "$mcp_in" "$gh_url" "" "$rf_root")"
expect 'gh api post owes the references too'               DENY  "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$api_post" "$gh_url" "" "$rf_root")"
expect 'a missing reference file demands nothing'          ALLOW "$(rv_verdict "$fix/review-head-a.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'a transcript that cannot be read fails open'       ALLOW "$(rf "$fix/nope.jsonl")"

echo "== require-rule-read.sh: the review gate where it cannot decide =="
expect 'transcript missing: allowed'                       ALLOW "$(rv_verdict "$fix/nope.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'PR not named and gh silent: allowed with a note'   WARN  "$(rv_verdict "$fix/review-head-a.jsonl" Bash '{"command":"gh pr review --approve"}' "")"
expect 'an old and a current line for the PR'              ALLOW "$(rv_verdict "$fix/review-head-old-and-new.jsonl" Bash "$gh_cmd" "$gh_url")"
expect 'an old and a current line, the head moved on'      DENY  "$(rv_verdict "$fix/review-head-old-and-new.jsonl" Bash "$gh_cmd" "$(printf 'c%.0s' {1..40})")"

echo "== require-rule-read.sh: a review post needs the run for the head, no release word (ww3d/playbook#359) =="
rr() { rv_verdict "$fix/$1.jsonl" Bash "$gh_cmd" "${2:-$gh_url}" "${3:-}"; }
expect 'the run for the current head is enough'            ALLOW "$(rr review-head-a)"
expect 'a run before a compaction and one after it'        ALLOW "$(rr review-compact-then-run)"

echo "== require-rule-read.sh: only a real compaction cuts, and a broken pipe step fails open =="
expect 'a compaction named in a later message'             ALLOW "$(rr review-compact-text-user)"
expect 'a compaction named in a tool result'               ALLOW "$(rr review-compact-text-result)"
# A step of the transcript pipe that fails is a read error, never "no skill ran": the post is let through.
# grep fails with 2 (1 only means "no line matched"); jq is not stubbed, the hook needs it before the pipe.
for t in tail grep; do
  code=1; [ "$t" = grep ] && code=2
  st="$fix/fail-$t"; mkdir -p "$st"; printf '#!/usr/bin/env bash\nexit %s\n' "$code" > "$st/$t"; chmod +x "$st/$t"
  expect "a failing $t: fails open"                        ALLOW \
    "$(RV_PATH="$st" rv_verdict "$fix/review-head-refused.jsonl" Bash "$gh_cmd" "$gh_url")"
done
expect 'the same transcript, every step ok: refused'       DENY  "$(rr review-head-refused)"
echo "== require-rule-read.sh: the forge calls of one command share one deadline =="
# A stand-in `timeout` logs the seconds it is given; the stand-in gh takes 2 s, so the second PR gets less.
tostub="$fix/tostub"; mkdir -p "$tostub"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "$STUB_TO_LOG"; shift; sleep 2; exec "$@"\n' > "$tostub/timeout"
chmod +x "$tostub/timeout"
to_log="$fix/to.log"; : > "$to_log"
sid="$(next_sid)"
: > "$gate_tmp/claude-rule-gate/${sid}-read-main-review"; : > "$gate_tmp/claude-rule-gate/${sid}-read-main-evidence"
printf '%s' "$(tool_event "$fix/review-head-5-and-6.jsonl" Bash "$posts_5_6" "$sid")" \
  | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$rv_root" PATH="$tostub:$ghstub:$PATH" STUB_GH_OUT="$gh_url" \
    STUB_TO_LOG="$to_log" bash "$ruleread" >/dev/null 2>&1
to_first="$(sed -n 1p "$to_log")"; to_second="$(sed -n 2p "$to_log")"
if [ -n "$to_first" ] && [ "$to_first" -ge 14 ] && [ "$to_first" -le 15 ]; then ok 'the first call gets the whole budget' "$to_first"
else bad 'the first call gets the whole budget' "${to_first:-none}" '14-15'; fi
if [ -n "$to_second" ] && [ "$to_second" -lt "$to_first" ]; then ok 'the second call gets what is left' "$to_second"
else bad 'the second call gets what is left' "${to_second:-none}" "less than $to_first"; fi

echo "== guard-kill.sh: process-ending commands =="
# MSYS_NO_PATHCONV: Git Bash would rewrite an argument that starts with a slash (/bin/kill) into a Windows path.
kill_event() { MSYS_NO_PATHCONV=1 jq -cn --arg c "$2" --arg t "$1" '{session_id: "k", hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}}'; }
kill_out() { printf '%s' "$(kill_event "$1" "$2")" | bash "$guard" 2>&1; }
chk_kill() { # label, expected (ask|deny|allow), tool, command [reason fragment]
  local out got
  out="$(kill_out "$3" "$4")"
  if [ -z "$out" ]; then got=allow
  else got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "ERR"' 2>/dev/null)"; fi
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
  if [ -n "${5:-}" ]; then check_contains "$1: reason" "$5" "$out"; fi
}
# one named target -> ask, the reason names it and the rule
chk_kill 'kill one PID'                        ask   Bash       'kill 1234'                                  '1234'
chk_kill 'kill -9 one PID'                     ask   Bash       'kill -9 1234'                               '1234'
chk_kill 'taskkill /PID'                       ask   Bash       'taskkill /PID 1234 /F'                      '1234'
chk_kill 'taskkill, Git Bash spelling'         ask   Bash       'taskkill //PID 1234 //F'                    '1234'
chk_kill 'taskkill one exact image'            ask   Bash       'taskkill /IM notepad.exe'                   'notepad.exe'
chk_kill 'Stop-Process -Id'                    ask   PowerShell 'Stop-Process -Id 4242'                      '4242'
chk_kill 'Stop-Process -Name, no wildcard'     ask   PowerShell 'Stop-Process -Name notepad -Force'          'notepad'
chk_kill 'spps alias'                          ask   PowerShell 'spps -Id 12'                                '12'
chk_kill 'kill alias in PowerShell'            ask   PowerShell 'kill 12'                                    '12'
chk_kill 'wmic, one process id'                ask   Bash       'wmic process where processid=77 delete'     '77'
chk_kill 'the reason names rule K5'            ask   Bash       'kill 1234'                                  'Core rule K5'
# nested ways
chk_kill 'powershell -Command'                 ask   Bash       'powershell -Command "Stop-Process -Id 4242"' '4242'
chk_kill 'pwsh -c'                             ask   Bash       'pwsh -NoProfile -c "Stop-Process -Id 4242"'  '4242'
chk_kill 'cmd /c'                              ask   Bash       'cmd /c taskkill /PID 99'                    '99'
chk_kill 'bash -c'                             ask   PowerShell "bash -c 'kill 55'"                          '55'
chk_kill 'after && in a longer line'           ask   Bash       'cd x && kill 77 && echo done'               '77'
chk_kill 'sudo kill'                           ask   Bash       'sudo kill 31'                               '31'
enc="$(printf 'Stop-Process -Id 4242' | sed 's/./&\x00/g' | base64 -w0)"
chk_kill 'pwsh -EncodedCommand, decoded'       ask   Bash       "pwsh -EncodedCommand $enc"                  '4242'
enc_bulk="$(printf 'Stop-Process -Name a*' | sed 's/./&\x00/g' | base64 -w0)"
chk_kill 'encoded broad ending'                deny  Bash       "pwsh -enc $enc_bulk"
# broad ending -> deny
chk_kill 'taskkill /IM *'                      deny  Bash       'taskkill /IM *'
chk_kill 'taskkill /FI'                        deny  Bash       'taskkill /FI "imagename eq a.exe"'
chk_kill 'taskkill two images'                 deny  Bash       'taskkill /IM a.exe /IM b.exe'
chk_kill 'pkill -f'                            deny  Bash       'pkill -f node'
chk_kill 'pkill, a wildcard in the name'       deny  Bash       'pkill "node*"'
chk_kill 'pkill, two names'                    deny  Bash       'pkill node npm'
chk_kill 'killall, a wildcard in the name'     deny  Bash       "killall 'a*'"
chk_kill 'killall -r, a regular expression'    deny  Bash       'killall -r node'
chk_kill 'skill, two names'                    deny  Bash       'skill node npm'
chk_kill 'kill several PIDs'                   deny  Bash       'kill -9 1 2'
chk_kill 'kill 0, the process group'           deny  Bash       'kill 0'
chk_kill 'kill -1, every process'              deny  Bash       'kill -9 -1'
chk_kill 'kill a computed list'                deny  Bash       'kill $(pgrep node)'
chk_kill 'xargs kill'                          deny  Bash       'ps aux | xargs kill'
chk_kill 'two kills in one line'               deny  Bash       'kill 3; kill 4'
chk_kill 'Stop-Process -Name with wildcard'    deny  PowerShell 'Stop-Process -Name foo*'
chk_kill 'Stop-Process several ids'            deny  PowerShell 'Stop-Process -Id 12,13'
chk_kill 'Get-Process | Stop-Process'          deny  PowerShell 'Get-Process foo | Stop-Process'
chk_kill 'Get-Process | kill'                  deny  PowerShell 'Get-Process notepad | kill'
chk_kill 'pwsh -c with a pipeline'             deny  Bash       'pwsh -NoProfile -Command "Get-Process foo | Stop-Process"'
chk_kill 'wmic by condition'                   deny  Bash       "wmic process where \"name like '%a%'\" call terminate"
chk_kill 'the deny reason names rule K5'       deny  Bash       "killall 'a*'"                               'Core rule K5'
# by name, one verdict whatever the verb: one name without a wildcard asks (the names above deny)
chk_kill 'pkill, one name'                     ask   Bash       'pkill node'                                 'pkill node'
chk_kill 'killall, one name'                   ask   Bash       'killall node'                               'killall node'
chk_kill 'killall, one name behind a signal'   ask   Bash       'killall -9 node'                            'killall node'
chk_kill 'skill, one name'                     ask   Bash       'skill -9 node'                              'skill node'
chk_kill 'pkill with the user option'          ask   Bash       'pkill -u root node'                         'pkill node'
chk_kill 'pkill -l lists signals'              allow Bash       'pkill -l'
# a selector without a name ends every process it matches: blocked, one case per form
chk_kill 'pkill -u, no name'                   deny  Bash       'pkill -u me'                                'by selector'
chk_kill 'pkill -U, no name'                   deny  Bash       'pkill -U 1000'                              'by selector'
chk_kill 'pkill -g, no name'                   deny  Bash       'pkill -g 5'                                 'by selector'
chk_kill 'pkill -G, no name'                   deny  Bash       'pkill -G staff'                             'by selector'
chk_kill 'pkill -P, no name'                   deny  Bash       'pkill -P 1'                                 'by selector'
chk_kill 'pkill -s, no name'                   deny  Bash       'pkill -s 100'                               'by selector'
chk_kill 'pkill -t, no name'                   deny  Bash       'pkill -t pts/1'                             'by selector'
chk_kill 'pkill --user, no name'               deny  Bash       'pkill --user me'                            'by selector'
chk_kill 'pkill --parent, no name'             deny  Bash       'pkill --parent 1'                           'by selector'
chk_kill 'pkill --pgroup, no name'             deny  Bash       'pkill --pgroup 5'                           'by selector'
chk_kill 'pkill --session, no name'            deny  Bash       'pkill --session 5'                          'by selector'
chk_kill 'pkill --terminal, no name'           deny  Bash       'pkill --terminal pts/1'                     'by selector'
chk_kill 'pkill --group, no name'              deny  Bash       'pkill --group staff'                        'by selector'
chk_kill 'killall -u, no name'                 deny  Bash       'killall -u me'                              'by selector'
chk_kill 'pkill -u5, value attached'           deny  Bash       'pkill -u5'                                  'by selector'
chk_kill 'pkill -uroot, value attached'        deny  Bash       'pkill -uroot'                               'by selector'
chk_kill 'pkill -P1, value attached'           deny  Bash       'pkill -P1'                                  'by selector'
chk_kill 'pkill --uid=5, value attached'       deny  Bash       'pkill --uid=5'                              'by selector'
chk_kill 'pkill -fu me, bundled flags'         deny  Bash       'pkill -fu me'
chk_kill 'pkill -xu me, bundled selector'      deny  Bash       'pkill -xu me'                               'by selector'
chk_kill 'pkill -u5 with a name still asks'    ask   Bash       'pkill -u5 node'                             'pkill node'
chk_kill 'pkill -HUP node, a signal name'      ask   Bash       'pkill -HUP node'                            'pkill node'
chk_kill 'pkill -P with a name still asks'     ask   Bash       'pkill -P 1 node'                            'pkill node'
chk_kill 'killall -s is a signal, no selector' ask   Bash       'killall -s TERM'                            'without a readable name'
chk_kill 'taskkill /IM, one image'             ask   Bash       'taskkill /IM chrome.exe'                    'chrome.exe'
chk_kill 'Stop-Process -Name, one name'        ask   PowerShell 'Stop-Process -Name claude'                  'claude'
chk_kill 'the same name through pkill'         ask   Bash       'pkill claude'                               'claude'
# every verb of the list reaches its classifier
chk_kill 'pskill'                              ask   Bash       'pskill 1234'                                '1234'
chk_kill 'tskill'                              ask   Bash       'tskill 1234'                                '1234'
chk_kill 'xkill'                               ask   Bash       'xkill'                                      'xkill'
chk_kill 'skill with a pid'                    ask   Bash       'skill 1234'                                 'skill 1234'
chk_kill 'upper case verb'                     ask   Bash       'KILL 5'                                     '5'
# a command position after a single `&`, a keyword or a wrapper with options
chk_kill 'after a single &'                    ask   Bash       'sleep 1 & kill 5'                           '5'
chk_kill 'after ;; without a space'            ask   Bash       'echo a;; kill 5'                            '5'
chk_kill 'after &; without a space'            ask   Bash       'echo a&; kill 5'                            '5'
chk_kill 'after |& (pipe with stderr)'         deny  Bash       'echo a |& kill 5'                           'pipeline'
chk_kill 'PowerShell call operator'            ask   PowerShell '& taskkill /PID 1'                          'pid 1'
chk_kill 'after a background &'                ask   Bash       'echo a & taskkill /F /IM x.exe'             'x.exe'
chk_kill 'after then'                          ask   Bash       'if true; then kill 5; fi'                   '5'
chk_kill 'after do'                            ask   Bash       'for p in $(pgrep x); do kill $p; done'      'variable'
chk_kill 'after else'                          ask   Bash       'if false; then :; else kill 5; fi'          '5'
chk_kill 'after !'                             ask   Bash       '! kill 5'                                   '5'
chk_kill 'xargs -r kill'                       deny  Bash       'pgrep claude | xargs -r kill'
chk_kill 'xargs kill reading a file'           deny  Bash       'xargs -r kill < pids.txt'
chk_kill 'xargs -n1 kill -9'                   deny  Bash       'pgrep claude | xargs -n1 kill -9'
chk_kill 'xargs -n 1 kill -9'                  deny  Bash       'pgrep claude | xargs -n 1 kill -9'
chk_kill 'timeout 5 kill'                      ask   Bash       'timeout 5 kill 1234'                        '1234'
chk_kill 'sudo -u x kill'                      ask   Bash       'sudo -u x kill 1'                           'kill 1'
chk_kill 'nohup kill in the background'        ask   Bash       'nohup kill 5 &'                             '5'
chk_kill 'env assignment before kill'          ask   Bash       'FOO=1 kill 5'                               '5'
chk_kill 'two assignments before pkill'        deny  Bash       'A=1 B=x pkill -f claude'                    'pkill'
chk_kill 'cmd /k'                              ask   Bash       'cmd /k taskkill /PID 4'                     'pid 4'
# the verb with a path before it, `.exe` behind it, or behind another wrapper
chk_kill 'a path before the verb'              ask   Bash       '/bin/kill 1234'                             'kill 1234'
chk_kill 'a longer path before the verb'       ask   Bash       '/usr/bin/kill -9 1234'                      'kill 1234'
chk_kill 'a Windows path and .exe'             ask   Bash       'C:\Windows\System32\taskkill.exe /PID 4'    'pid 4'
chk_kill 'a backslash before the verb'         ask   Bash       '\kill 1234'                                 'kill 1234'
chk_kill 'busybox kill'                        ask   Bash       'busybox kill 1234'                          'kill 1234'
chk_kill 'a path before busybox'               ask   Bash       '/bin/busybox kill 5'                        'kill 5'
chk_kill 'a path before env'                   ask   Bash       '/usr/bin/env kill 5'                        'kill 5'
chk_kill 'a path before sudo'                  ask   Bash       '/usr/bin/sudo kill 5'                       'kill 5'
chk_kill 'a path before timeout'               ask   Bash       '/usr/bin/timeout 5 kill 1'                  'kill 1'
chk_kill 'a path before xargs'                 deny  Bash       'ls | /usr/bin/xargs kill'                   'pipeline'
chk_kill 'a path before find'                  deny  Bash       '/usr/bin/find . -name x -exec kill {} \;'   'pipeline'
chk_kill 'taskkill.exe'                        ask   Bash       'taskkill.exe /F /IM node.exe'               'node.exe'
chk_kill 'kill.exe'                            ask   Bash       'kill.exe 12'                                'kill 12'
chk_kill 'find -exec kill'                     deny  Bash       'find . -name x -exec kill {} \;'            'pipeline'
chk_kill 'find -execdir pkill'                 deny  Bash       'find . -execdir pkill x \;'
chk_kill 'xargs -I{} kill'                     deny  Bash       'echo 1234 | xargs -I{} kill {}'             'pipeline'
chk_kill 'xargs -I <str> kill'                 deny  Bash       'echo 1234 | xargs -I % kill %'              'pipeline'
chk_kill 'a path in a commit message'          allow Bash       'git commit -m "kill the /bin/kill"'
chk_kill 'a path to a file that is no verb'    allow Bash       'cat /tmp/kill.exe.txt'
chk_kill 'ls of the kill binary'               allow Bash       'ls /bin/kill'
chk_kill 'ssh host "kill"'                     ask   Bash       'ssh host "kill 5"'                          '5'
chk_kill 'a substitution inside double quotes' ask   Bash       'echo "$(kill 5)"'                           '5'
# the argument branches of the classifiers
chk_kill 'kill -s TERM'                        ask   Bash       'kill -s TERM 1234'                          '1234'
chk_kill 'kill -- -1, every process'           deny  Bash       'kill -- -1'
chk_kill 'Stop-Process -InputObject'           ask   PowerShell 'Stop-Process -InputObject $p'               'cannot read'
chk_kill 'Stop-Process -Id:12'                 ask   PowerShell 'Stop-Process -Id:12'                        '12'
chk_kill 'taskkill two PIDs'                   deny  Bash       'taskkill /PID 1 /PID 2'
chk_kill 'Invoke-CimMethod ... Terminate'      ask   PowerShell 'Invoke-CimMethod -Query "select * from win32_process" -MethodName Terminate'
chk_kill 'wmic delete by like'                 deny  Bash       "wmic process where \"name like '%a%'\" delete"
# a verb behind a long text is still found, and one inside it still is not
# (600 lines: jq --arg takes at most about 32 KB under Windows)
long_text="$(printf 'line of text %s\n' $(seq 1 600))"
chk_kill 'a verb after a long heredoc'         ask   Bash       "cat > f <<EOF
$long_text
EOF
kill 5"                                        '5'
chk_kill 'the word kill inside a long heredoc' allow Bash       "cat > f <<EOF
$long_text
please do not kill the process
EOF"
# Many words that hold "kill" in one statement: the scan matches the pattern once per statement, not once
# per word, so its cost grows in step with the text. The long-path cases compare two timings (4x the words
# must cost under 8x), which does not depend on the machine's speed; the short-path case counts the pattern
# runs the hook reports under GUARD_KILL_TRACE instead, because a fixed factor (a missing stop costs ~5x)
# hides in a ratio and wall time wobbles. A real kill behind the words is still found.
# `timeout` and the absolute cap only keep a regression from hanging the suite.
guard_ms() { # prefix, count, path template (N = number) -> globals ms, out
  local c t0 t1 i
  c="$1 $(for i in $(seq 1 "$2"); do printf '%s ' "${3//N/$i}"; done); kill 1234"
  c="$(kill_event Bash "$c")"
  t0=$EPOCHREALTIME
  out="$(printf '%s' "$c" | timeout 25 bash "$guard" 2>&1)"
  t1=$EPOCHREALTIME
  ms="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')"
}
best_ms() { # prefix, count, template -> global ms: the faster of two runs (a CPU burst hits one), one run when slow
  local first
  guard_ms "$@"; first=$ms
  if [ "$first" -lt 10000 ]; then guard_ms "$@"; [ "$ms" -le "$first" ] || ms=$first; fi
}
scaled_kill() { # label, prefix, small count, template (N = number), hang cap in ms for 4x the count
  local small big got ratio
  best_ms "$2" "$3" "$4"; small=$ms
  best_ms "$2" "$(($3 * 4))" "$4"; big=$ms
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  if [ "$got" = ask ] && printf '%s' "$out" | grep -q '1234'; then ok "$1: the real kill is found" "$got"; else bad "$1: the real kill is found" "$got" 'ask 1234'; fi
  ratio="$(awk -v a="$small" -v b="$big" 'BEGIN { if (a < 20) a = 20; printf "%.1f", b / a }')"
  # A run that hit the 25 s `timeout` ends at the same time whatever its size, which would read as a flat ratio.
  if [ "$small" -lt 20000 ] && [ "$big" -lt 20000 ] && awk -v r="$ratio" 'BEGIN { exit !(r < 8) }'; then ok "$1: 4x the words cost under 8x" "${small} ms -> ${big} ms, ratio ${ratio}"
  else bad "$1: 4x the words cost under 8x" "${small} ms -> ${big} ms, ratio ${ratio}" 'ratio < 8, no timeout'; fi
  if [ "$big" -lt "$5" ]; then ok "$1: under $5 ms" "${big} ms"; else bad "$1: under $5 ms" "${big} ms" "< $5 ms"; fi
}
long_path='/usr/local/bin/something/kill-switch-config-N.yaml'
scaled_kill '400 long paths after echo'        'echo'      100  "$long_path"   15000
scaled_kill '400 long paths after sudo echo'   'sudo echo' 100  "$long_path"   15000
# 2000 short paths: counted, not timed. Without a separator the words are one statement, which the first failed
# match settles (2 runs: that statement and the real kill); with a `&` behind each word every path is a
# statement of its own and the runs grow with the words, over about the text's length in characters.
trace_file="$fix/guard-trace"
guard_trace() { # label, joiner between the paths, max runs
  local c i r ch runs=-1 chars=-1 bytes got
  c="sudo echo $(for i in $(seq 1 2000); do printf '%s%s' "/tmp/kill-$i" "$2"; done) ; kill 1234"
  c="$(kill_event Bash "$c")"; bytes=${#c}
  rm -f "$trace_file"
  out="$(printf '%s' "$c" | GUARD_KILL_TRACE="$trace_file" timeout 25 bash "$guard" 2>&1)"
  if [ -s "$trace_file" ]; then read -r r ch < "$trace_file"; runs=${r#runs=}; chars=${ch#chars=}; fi
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  if [ "$got" = ask ] && printf '%s' "$out" | grep -q '1234'; then ok "$1: the real kill is found" "$got"; else bad "$1: the real kill is found" "$got" 'ask 1234'; fi
  if [ "$runs" -ge 0 ] && [ "$runs" -le "$3" ]; then ok "$1: at most $3 pattern runs" "$runs"; else bad "$1: at most $3 pattern runs" "$runs" "<= $3"; fi
  if [ "$chars" -ge 0 ] && [ "$chars" -le $((bytes * 2)) ]; then ok "$1: pattern text within twice the input" "${chars} of ${bytes}"; else bad "$1: pattern text within twice the input" "${chars} of ${bytes}" "<= $((bytes * 2))"; fi
}
guard_trace '2000 short paths, no separator'    ' ' 5
guard_trace '2000 short paths, one per statement' '&' 2010
# wrappers that carry a value option: `-c` is a value here, not the code flag of a shell
chk_kill 'ionice -c 3 kill'                    ask   Bash       'ionice -c 3 kill 1'                         'kill 1'
chk_kill 'env -C / kill'                       ask   Bash       'env -C / kill 5'                            'kill 5'
chk_kill 'env -i -C / kill'                    ask   Bash       'env -i -C / kill 5'                         'kill 5'
chk_kill 'watch kill'                          ask   Bash       'watch kill 1'                               'kill 1'
chk_kill 'watch -n 5 kill'                     ask   Bash       'watch -n 5 kill 1'                          'kill 1'
# a quoted argument that runs as a command line is code, like the one behind `ssh host`
chk_kill 'watch with a quoted command'         ask   Bash       "watch 'kill 1'"                             'kill 1'
chk_kill 'watch -n1 with a double-quoted one'  ask   Bash       'watch -n1 "kill 1"'                         'kill 1'
chk_kill 'watch -n 2 with a quoted command'    ask   Bash       "watch -n 2 'kill 1'"                        'kill 1'
chk_kill 'nice watch with a quoted command'    ask   Bash       "nice watch 'kill 1'"                        'kill 1'
chk_kill 'env -S with a quoted command line'   deny  Bash       "env -S 'pkill -f node'"                     'full command line'
chk_kill 'env --split-string, quoted'          ask   Bash       "env --split-string 'kill 1'"                'kill 1'
chk_kill 'env -i -S, quoted'                   ask   Bash       "env -i -S 'kill 1'"                         'kill 1'
chk_kill 'env --split-string=, quote attached' ask   Bash       "env --split-string='kill 1'"                'kill 1'
chk_kill 'env -S, quote attached'              ask   Bash       "env -S'kill 1'"                             'kill 1'
chk_kill 'env -S, quote attached, harmless'    allow Bash       "env -S'echo kill-switch'"
chk_kill 'a path before watch'                 ask   Bash       "/usr/bin/watch 'kill 1'"                    'kill 1'
chk_kill 'a path before env -S'                ask   Bash       "/usr/bin/env -S 'kill 1'"                   'kill 1'
chk_kill 'a path before env -S, quote attached' ask  Bash       "/usr/bin/env -S'kill 1'"                    'kill 1'
chk_kill 'a relative path before env -S, attached' ask Bash     "./env -S'kill 1'"                           'kill 1'
chk_kill 'env -u X -S'                         ask   Bash       "env -u X -S 'kill 1'"                       'kill 1'
chk_kill 'env -C dir -S'                       ask   Bash       "env -C /tmp -S 'kill 1'"                    'kill 1'
chk_kill 'env --unset X -S'                    ask   Bash       "env --unset X -S 'kill 1'"                  'kill 1'
chk_kill 'env --chdir dir -S, quote attached'  ask   Bash       "env --chdir /tmp -S'kill 1'"                'kill 1'
chk_kill 'env -u X -S around a harmless text'  allow Bash       "env -u X -S 'echo kill-switch'"
chk_kill 'a path before ssh'                   ask   Bash       "/usr/bin/ssh h 'kill 1'"                    'kill 1'
chk_kill 'watch around a harmless quoted text' allow Bash       "watch 'echo kill-switch'"
chk_kill 'ssh host quoted is code too'         ask   Bash       "ssh h 'kill 1'"                             'kill 1'
chk_kill 'taskset -c cpu list, then kill'      ask   Bash       'taskset -c 0 kill 1'                        'kill 1'
chk_kill 'taskset with a mask, then kill'      ask   Bash       'taskset 0x1 kill 1'                         'kill 1'
chk_kill 'chrt -i 0 kill'                      ask   Bash       'chrt -i 0 kill 1'                           'kill 1'
chk_kill 'chrt priority kill'                  ask   Bash       'chrt -f 10 kill 1'                          'kill 1'
chk_kill 'flock file kill'                     ask   Bash       'flock /tmp/l kill 1'                        'kill 1'
chk_kill 'runuser -u x -- kill'                ask   Bash       'runuser -u x -- kill 1'                     'kill 1'
chk_kill 'systemd-run kill'                    ask   Bash       'systemd-run kill 1'                         'kill 1'
chk_kill 'systemd-run with options, kill'      ask   Bash       'systemd-run --scope -p MemoryMax=1G kill 1' 'kill 1'
chk_kill 'taskset around a harmless command'   allow Bash       'taskset -c 0 ls /tmp/kill'
chk_kill 'bash -c still opens code'            ask   Bash       'bash -c "kill 5"'                           'kill 5'
chk_kill 'env bash -c still opens code'        ask   Bash       'env -i bash -c "kill 5"'                    'kill 5'
chk_kill 'ionice around a harmless command'    allow Bash       'ionice -c 3 ls /tmp/kill'
# bundled short flags and a signal without a name
chk_kill 'pkill -fx, bundled full match'       deny  Bash       'pkill -fx node'                             'full command line'
chk_kill 'pkill -rx, bundled regexp'           deny  Bash       'pkill -rx node'                             'regular expression'
chk_kill 'pkill -x alone is a name match'      ask   Bash       'pkill -x node'                              'pkill node'
chk_kill 'pkill -HUP, a signal and no name'    ask   Bash       'pkill -HUP'                                 'without a readable name'
chk_kill 'pkill -HUP node'                     ask   Bash       'pkill -HUP node'                            'pkill node'
# a short encoded command: the same length decides in step 1 and step 2
chk_kill 'short encoded kill (16 characters)'  ask   Bash       'pwsh -enc awBpAGwAbAAgADEA'                 '1'
chk_kill 'shortest encoded verb (12 characters)' ask  Bash       'pwsh -enc awBpAGwAbAA='                     'without a readable target'
# unclear -> ask
chk_kill 'kill a variable'                     ask   Bash       'kill $PID'                                  'variable'
chk_kill 'Stop-Process with a variable'        ask   PowerShell 'Stop-Process -Name $n'                      'variable'
chk_kill 'taskkill without a target'           ask   Bash       'taskkill /F'
chk_kill 'an undecodable encoded command'      ask   Bash       'pwsh -enc AAAAAAAAAAAAAAAAAAAAA'
chk_kill 'a kill in inline code'               ask   Bash       'python -c "import os; os.kill(5, 9)"'
# everything else passes
chk_kill 'kill -l lists signals'               allow Bash       'kill -l'
chk_kill 'kill -0 only probes'                 allow Bash       'kill -0 1234'
chk_kill 'a plain command'                     allow Bash       'git status --short'
chk_kill 'a plain PowerShell command'          allow PowerShell 'Get-ChildItem -Recurse'
chk_kill '"skills" in a path'                  allow Bash       'ls .claude/skills/pr-poll-review'
chk_kill 'the word in a commit message'        allow Bash       'git commit -m "fix: kill guard for skills"'
chk_kill 'a commit message that starts with a verb' allow Bash  'git commit -m "kill the flaky test"'
chk_kill 'a single-quoted message with a verb' allow Bash       "git commit -m 'kill the flaky test'"
chk_kill 'a message with & and a verb'         allow Bash       'git commit -m "a & kill"'
chk_kill 'a message with ; and a verb'         allow Bash       "git commit -m 'done; kill 5'"
chk_kill 'a search for pkill'                  allow Bash       'rg -n "pkill|killall" .claude/hooks'
chk_kill 'a search for kill'                   allow Bash       'grep -n "kill" x'
chk_kill 'a verb at the start of a heredoc line quoted' allow Bash 'echo "line one
kill 5"'
chk_kill 'ls of a skill folder'                allow Bash       'ls .claude/skills'
chk_kill 'the word skill inside a path'        allow Bash       'cat .claude/skill-notes.md'
chk_kill 'wmic reading something else'         allow Bash       'wmic cpu get name'
chk_kill 'an encoded command without a verb'   allow Bash       'pwsh -enc QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo='
chk_kill 'a tool this hook does not guard'     allow Read       'kill 1234'

echo "== guard-kill.sh: a background session gets deny where it would get ask (ww3d/playbook#356) =="
# An `ask` parks a `claude --bg` session as waiting (measured with Claude Code 2.1.294): there it is a hard block.
bg_kill() { # label, expected, command, [reason fragment]
  local out got
  out="$(printf '%s' "$(kill_event Bash "$3")" | CLAUDE_JOB_DIR="$fix/job" bash "$guard" 2>&1)"
  if [ -z "$out" ]; then got=allow
  else got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "ERR"' 2>/dev/null)"; fi
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
  if [ -n "${4:-}" ]; then check_contains "$1: reason" "$4" "$out"; fi
}
bg_kill 'background: one named PID is denied'      deny  'kill 1234'        'owner of this session'
bg_kill 'background: the reason still names it'    deny  'kill 1234'        '1234'
# The reason must not send the session into a retry loop: no confirmation here, the owner or the maintainer runs it.
bg_kill 'background: no confirmation possible'     deny  'kill 1234'        'a background session cannot get a confirmation'
bg_kill 'background: someone else runs it'         deny  'kill 1234'        'the owner or the maintainer runs the command themselves'
# The session's own background task is not a dead end: the harness stops it without a kill command.
bg_kill 'background: its own task goes by TaskStop'  deny  'kill 1234'        "A background task this session started itself is stopped with the harness's task stop (TaskStop), not with a kill command."
bg_kill 'background: a broad ending stays denied'  deny  'pkill -f node'    'Blocked, broad ending'
bg_kill 'background: a call without a verb passes' allow 'git log --oneline'
chk_kill 'foreground: one named PID still asks'    ask   Bash 'kill 1234'
out="$(printf '%s' "$(kill_event Bash 'kill 1234')" | CLAUDE_JOB_DIR="" bash "$guard" 2>&1)"
if printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then ok 'an empty CLAUDE_JOB_DIR is no background session' ask
else bad 'an empty CLAUDE_JOB_DIR is no background session' "$out" ask; fi

echo "== guard-kill.sh: fail-open and cost =="
out="$(printf 'not json at all kill 5' | bash "$guard" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok 'junk payload: allow, rc=0' 'rc=0'; else bad 'junk payload' "rc=$rc $out" 'rc=0'; fi
# A trace file that cannot be written must not cost the verdict an exit code or a line on stderr.
errf="$fix/guard-trace.err"
out="$(printf '%s' "$(kill_event Bash 'kill 1234')" | GUARD_KILL_TRACE="$fix/no-such-dir/trace" bash "$guard" 2>"$errf")"; rc=$?
if [ "$rc" = 0 ] && [ ! -s "$errf" ] && printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then
  ok 'an unwritable GUARD_KILL_TRACE: verdict intact, rc=0, no stderr' 'rc=0'
else bad 'an unwritable GUARD_KILL_TRACE' "rc=$rc err=$(cat "$errf") out=$out" 'rc=0, no stderr, ask'; fi
printf '#!/usr/bin/env bash\nexit 127\n' > "$stub/jq"; chmod +x "$stub/jq"
out="$(printf '%s' "$(kill_event Bash 'killall node')" | PATH="$stub:$PATH" bash "$guard" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'deny'; then ok 'without jq: allow, rc=0' 'rc=0'; else bad 'without jq' "rc=$rc $out" 'rc=0'; fi
# A failing jq while building the answer must not turn into a blocking exit code.
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-cn" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
out="$(printf '%s' "$(kill_event Bash 'killall node')" | PATH="$stub:$PATH" bash "$guard" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then ok 'answer-building jq failure still exits 0' 'rc=0'; else bad 'answer-building jq failure' "rc=$rc" 'rc=0'; fi
rm -f "$stub/jq"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "jq" >> "%s"\nexec "%s" "$@"\n' "$calls" "$(command -v jq)" > "$stub/jq"
chmod +x "$stub/jq"
: > "$calls"
printf '%s' "$(kill_event Bash 'git log --oneline -5')" | PATH="$stub:$PATH" bash "$guard"
printf '%s' "$(kill_event Bash 'ls .claude/skills')" | PATH="$stub:$PATH" bash "$guard"
if [ ! -s "$calls" ]; then ok 'a call without a verb starts no jq' 'none'; else bad 'a call without a verb' "$(tr '\n' ' ' < "$calls")" 'none'; fi
rm -f "$stub/jq"

echo "== settings: the new hooks are registered, template and project alike =="
for sf in "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; do
  label="${sf#"$repo_root"/}"
  g="$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].args[]? | select(test("guard-kill\\.sh$"))] | length' "$sf")"
  r="$(jq -r '[.hooks.PostToolUse[]? | select(.matcher == "Read") | .hooks[].args[]? | select(test("record-rule-read\\.sh$"))] | length' "$sf")"
  c="$(jq -r '.cleanupPeriodDays // "unset"' "$sf")"
  m="$(jq -r '.hooks.PreToolUse[0].matcher' "$sf")"
  expect "$label: the rule gate starts for GitHub MCP tools only" 'Bash|PowerShell|Write|Edit|NotebookEdit|mcp__.*[Gg]it[Hh]ub.*' "$m"
  expect "$label registers guard-kill.sh for Bash|PowerShell" 1 "$g"
  expect "$label registers record-rule-read.sh for Read"      1 "$r"
  expect "$label sets cleanupPeriodDays"                      90 "$c"
done
if cmp -s "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; then ok 'project settings equal the template' same
else bad 'project settings equal the template' differ same; fi

echo "== run-folder.sh: the sweep removes finished runs and keeps live ones =="
age() { touch -d '5 minutes ago' "$@"; }
present() { if [ -d "$2" ]; then ok "$1" kept; else bad "$1" removed kept; fi; }
absent() { if [ -d "$2" ]; then bad "$1" kept removed; else ok "$1" removed; fi; }
sweep_base="$fix/sweep-pid"
mkdir -p "$sweep_base"/run.dead "$sweep_base"/run.live "$sweep_base"/run.fresh "$sweep_base"/run.cur
sleep 0 & dead_pid=$!; wait "$dead_pid"
echo "$dead_pid" >"$sweep_base/run.dead/.pid"
sleep 60 >/dev/null 2>&1 & live_pid=$!
echo "$live_pid" >"$sweep_base/run.live/.pid"
# A dead PID: only the age limit may keep this one.
echo "$dead_pid" >"$sweep_base/run.fresh/.pid"
echo "$dead_pid" >"$sweep_base/run.cur/.pid"
age "$sweep_base"/run.dead "$sweep_base"/run.live "$sweep_base"/run.cur
sweep_run_folders "$sweep_base" "$sweep_base/run.cur" 0
absent 'without flock: a run whose PID is gone' "$sweep_base/run.dead"
present 'without flock: a run whose PID still lives' "$sweep_base/run.live"
present 'without flock: a run younger than a minute' "$sweep_base/run.fresh"
present 'without flock: the current run' "$sweep_base/run.cur"
kill "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null
if command -v flock >/dev/null 2>&1; then
  sweep_base="$fix/sweep-flock"
  mkdir -p "$sweep_base"/run.held "$sweep_base"/run.free "$sweep_base"/run.young
  : >"$sweep_base/run.free/.lock"
  : >"$sweep_base/run.young/.lock"
  ( exec 8>"$sweep_base/run.held/.lock"; flock 8; exec sleep 60 ) >/dev/null 2>&1 & holder=$!
  for _ in $(seq 50); do flock -n "$sweep_base/run.held/.lock" true || break; sleep 0.1; done
  age "$sweep_base"/run.held "$sweep_base"/run.free
  sweep_run_folders "$sweep_base" "$sweep_base/run.none" 1
  present 'with flock: a run whose lock is held' "$sweep_base/run.held"
  absent 'with flock: a run whose lock is free' "$sweep_base/run.free"
  present 'with flock: a free run younger than a minute' "$sweep_base/run.young"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
else
  echo '  skip with flock: flock is not installed here'
fi

echo
printf '%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
