#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, the receipt in the transcript
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-receipt.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-rule-read.sh: receipt recognised in a tool_use command, not just text =="

chk_rule 'no rule receipt at all'                  DENY  "$fix/rule-no-receipt.jsonl"      Bash 'gh issue create --title x'
chk_rule 'rule receipt as its own text block'      ALLOW "$fix/rule-receipt-text.jsonl"    Bash 'gh issue create --title x'
# The receipt line never appears as a standalone assistant text entry, only
# inside a tool_use's .input.command (an echo) and that command's own result.
# Text between tool calls can leave the model as thinking and never land as
# text, so this is the dependable way to emit it.
chk_rule 'rule receipt echoed by a command that ran'  ALLOW "$fix/rule-receipt-toolcmd.jsonl" Bash 'gh issue create --title x'
chk_rule 'rule receipt echoed, result as text-block array' ALLOW "$fix/rule-receipt-toolcmd-array.jsonl" Bash 'gh issue create --title x'

echo "== require-rule-read.sh: the line form of the read-receipt block (ww3d/playbook#366) =="
chk_rule 'new line in a diff fence'                 ALLOW "$fix/rule-new-receipt-text.jsonl"    Bash 'gh issue create --title x'
chk_rule 'new line echoed by a command that ran'    ALLOW "$fix/rule-new-receipt-toolcmd.jsonl" Bash 'gh issue create --title x'
chk_rule 'new line inside a sentence'               DENY  "$fix/rule-new-receipt-midline.jsonl" Bash 'gh issue create --title x'
chk_rule 'new line, command not run yet'            DENY  "$fix/rule-new-receipt-unrun.jsonl"   Bash 'gh issue create --title x'
chk_rule 'new line inside a gh body, result a URL'  DENY  "$fix/rule-new-receipt-data.jsonl"    Bash 'gh issue create --title x'
chk_rule 'new line for another rule file'           DENY  "$fix/rule-new-receipt-other.jsonl"   Bash 'gh issue create --title x'
chk_rule 'new line with the SHA not filled in'      DENY  "$fix/rule-new-receipt-no-sha.jsonl"  Bash 'gh issue create --title x'
chk_rule 'new line echoed, result with CRLF ends'   ALLOW "$fix/rule-new-receipt-crlf.jsonl"    Bash 'gh issue create --title x'
chk_rule 'new line, SHA field no checksum'          DENY  "$fix/rule-new-receipt-not-hex.jsonl"   Bash 'gh issue create --title x'
chk_rule 'new line, "reading" instead of read'      DENY  "$fix/rule-new-receipt-reading.jsonl"   Bash 'gh issue create --title x'
chk_rule 'new line without read'                    DENY  "$fix/rule-new-receipt-no-read.jsonl"   Bash 'gh issue create --title x'
chk_rule 'new line, SHA shorter than seven'         DENY  "$fix/rule-new-receipt-short-sha.jsonl" Bash 'gh issue create --title x'
chk_rule 'new line echoed, result shows it mid-line' DENY "$fix/rule-new-receipt-echo-midline.jsonl" Bash 'gh issue create --title x'

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
compact_run() { # transcript
  local t s; js "$1"; t="$REPLY"; js "$rc_sid"; s="$REPLY"
  rule_verdict "$(printf '{"session_id":%s,"transcript_path":%s,"cwd":"/tmp","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"gh issue create"}}' "$s" "$t")"
}
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

finish
