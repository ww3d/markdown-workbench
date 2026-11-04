#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, tool calls, process starts and fail-open
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-tool-calls.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-rule-read.sh: Windows tool calls are classified like the others (ww3d/playbook#276) =="
# Bash, PowerShell, backslash paths and the claude.ai connector names alike.
chk_tool 'Bash gh issue close'                       DENY  Bash       '{"command":"gh issue close 5"}'
chk_tool 'PowerShell gh issue create'                DENY  PowerShell '{"command":"gh issue create --title x"}'
chk_tool 'PowerShell gh pr create'                   DENY  PowerShell '{"command":"gh pr create --draft"}'
chk_tool 'PowerShell without gh'                     ALLOW PowerShell '{"command":"Get-ChildItem"}'
path_json() { js "$2"; printf '{"%s":%s}' "$1" "$REPLY"; } # key, path -> the tool input
# A comment is evidence, as mcp__*__add_issue_comment already was (review
# round 1 of ww3d/playbook#289).
chk_tool 'Bash gh pr comment'                        DENY  Bash       '{"command":"gh pr comment 5 --body x"}'
chk_tool 'PowerShell gh issue comment'               DENY  PowerShell '{"command":"gh issue comment 5 --body x"}'
chk_tool 'mcp__claude_ai_GitHub_MCP__add_issue_comment' DENY mcp__claude_ai_GitHub_MCP__add_issue_comment '{}'
chk_tool 'NotebookEdit, notebook in the repo'        DENY  NotebookEdit "$(path_json notebook_path "$repo_root/x.ipynb")"
chk_tool 'mcp__github__issue_write'                  DENY  mcp__github__issue_write '{}'
chk_tool 'mcp__claude_ai_GitHub_MCP__issue_write'    DENY  mcp__claude_ai_GitHub_MCP__issue_write '{}'
chk_tool 'mcp__claude_ai_GitHub_MCP__create_pull_request' DENY mcp__claude_ai_GitHub_MCP__create_pull_request '{}'
chk_tool 'mcp__claude_ai_GitHub_MCP__issue_read'     ALLOW mcp__claude_ai_GitHub_MCP__issue_read '{}'
chk_tool 'a non-GitHub MCP server with the same verb' ALLOW mcp__tracker__issue_write '{}'

# Backslash paths run everywhere: a POSIX project root, the file path spelled
# with backslashes.
bs_root="${repo_root//\//\\}"
chk_tool 'Write, backslash path to a .md in the repo'  DENY  Write "$(path_json file_path "$bs_root\\docs\\x.md")"
chk_tool 'Edit, backslash path to code in the repo'    DENY  Edit  "$(path_json file_path "$bs_root\\scripts\\x.ps1")"
chk_tool 'Write, backslash path outside the repo'      ALLOW Write "$(path_json file_path "\\tmp\\x.md")"
chk_tool 'Write, forward-slash path in the repo (unchanged)' DENY Write "$(path_json file_path "$repo_root/docs/x.md")"
# A state audit file owes the audit rule, under the new name and the old one (read until
# playbook 26.0.0, ww3d/playbook#356), at the new place docs/audit/ and the old one audit/ (read
# until playbook 26.0.0, the first MAJOR after the move).
for audit_dir in docs/audit audit; do
  for audit_name in state-2026-01-01T0000Z.md ist-stand-2026-01-01T0000Z.md; do
    out="$(tool_event "$fix/rule-no-receipt.jsonl" Write "$(path_json file_path "$repo_root/$audit_dir/$audit_name")" "$(next_sid)" \
      | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"
    if has_text '.agents/rules/audit.md' "$out"; then ok "Write $audit_dir/$audit_name owes the audit rule" found
    else bad "Write $audit_dir/$audit_name owes the audit rule" "$out" '.agents/rules/audit.md'; fi
  done
done
# Drive letters need a real Windows path to exist, so this pair runs only
# where cygpath can produce one (Git Bash, MSYS, Cygwin).
if command -v cygpath >/dev/null 2>&1; then
  win_root="$(cygpath -w "$repo_root")"
  lower_root="$(printf '%s' "${win_root:0:1}" | tr '[:upper:]' '[:lower:]')${win_root:1}"
  chk_tool 'Windows root, drive-letter path in the repo'   DENY  Write "$(path_json file_path "$win_root\\docs\\x.md")" "$win_root"
  chk_tool 'Windows root, lower-case drive letter'         DENY  Write "$(path_json file_path "$lower_root\\docs\\x.md")" "$win_root"
  chk_tool 'Windows root, Git Bash spelling of the path'   DENY  Write "$(path_json file_path "$repo_root/docs/x.md")" "$win_root"
  chk_tool 'Windows root, drive-letter path outside'       ALLOW Write "$(path_json file_path "${win_root:0:2}\\elsewhere\\x.md")" "$win_root"
else
  printf '  skip %-52s %s\n' 'drive-letter cases' '(no cygpath: not a Windows bash)'
fi

echo "== require-rule-read.sh: no transcript read where no trigger can apply (ww3d/playbook#276) =="
# Shadow jq and grep with loggers. A call that cannot map to a trigger starts
# neither (decided on the raw payload with builtins alone); a call that maps
# to nothing after parsing starts jq once and never reads the transcript; a
# trigger whose receipt was already found in this session is not read again.
for helper in jq grep; do
  real="$(command -v "$helper")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$real" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
count_calls() { # label, expected jq/grep counts as "jq=N grep=M", event json
  local got
  : > "$calls"
  printf '%s' "$3" | TMPDIR="$gate_tmp" CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" >/dev/null 2>&1
  local n_jq=0 n_grep=0 l
  while IFS= read -r l; do case "$l" in jq) n_jq=$((n_jq + 1)) ;; grep) n_grep=$((n_grep + 1)) ;; esac; done < "$calls"
  got="jq=$n_jq grep=$n_grep"
  if [ "$got" = "$2" ]; then ok "$1" "$got"; else bad "$1" "$got" "$2"; fi
}
count_calls 'Read: no process at all'           'jq=0 grep=0' "$(tool_event "$nr" Read '{"file_path":"/x/docs/a.md"}' "$(next_sid)")"
count_calls 'Bash without gh: no process at all' 'jq=0 grep=0' "$(tool_event "$nr" Bash '{"command":"git status"}' "$(next_sid)")"
mkdir -p "$gate_tmp/claude-rule-gate"
: > "$gate_tmp/claude-rule-gate/foreign-session-audit-owed"
count_calls 'Bash without gh, a marker of another session stands: no process at all' 'jq=0 grep=0' "$(tool_event "$nr" Bash '{"command":"git status"}' "$(next_sid)")"
rm -f "$gate_tmp/claude-rule-gate/foreign-session-audit-owed"
own_sid="$(next_sid)"
: > "$gate_tmp/claude-rule-gate/${own_sid}-audit-owed"
count_calls 'Bash without gh, the own marker stands: judged' 'jq=3 grep=1' "$(tool_event "$nr" Bash '{"command":"git status"}' "$own_sid")"
rm -f "$gate_tmp/claude-rule-gate/${own_sid}-audit-owed"
count_calls 'a non-GitHub MCP tool: no process at all' 'jq=0 grep=0' "$(tool_event "$nr" mcp__claude_ai_Claude_Docs__read '{}' "$(next_sid)")"
count_calls 'the GitHub connector: judged' 'jq=1 grep=0' "$(tool_event "$nr" mcp__claude_ai_GitHub_MCP__issue_read '{}' "$(next_sid)")"
count_calls 'Write outside the repo: no transcript read' 'jq=1 grep=0' "$(tool_event "$nr" Write '{"file_path":"/elsewhere/a.md"}' "$(next_sid)")"
count_calls 'triggered call: one grep, one jq pass' 'jq=3 grep=1' "$(tool_event "$nr" Bash '{"command":"gh issue create"}' "$(next_sid)")"
cache_sid="$(next_sid)"
count_calls 'receipt found: read once'          'jq=2 grep=1' "$(tool_event "$fix/rule-receipt-text.jsonl" Bash '{"command":"gh issue create"}' "$cache_sid")"
count_calls 'receipt found before: not read again' 'jq=1 grep=0' "$(tool_event "$fix/rule-receipt-text.jsonl" Bash '{"command":"gh issue create"}' "$cache_sid")"
rm -f "$stub/jq" "$stub/grep"

echo "== require-rule-read.sh: a missing helper degrades to allow, never to block =="
# Only jq: the hook guards it explicitly (`command -v jq >/dev/null 2>&1 ||
# exit 0`, line ~44) precisely because it is the one dependency that is not
# guaranteed to exist everywhere bash does. The payload read (`$(</dev/stdin)`)
# is a bash builtin and needs no helper, so there is nothing else to lose.
printf '#!/usr/bin/env bash\nexit 127\n' > "$stub/jq"
chmod +x "$stub/jq"
out="$(printf '%s' "$(rule_event "$fix/rule-no-receipt.jsonl" Bash 'gh issue create --title x' "$(next_sid)")" \
  | CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! has_text deny "$out"; then
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
if [ "$rc" = 0 ] && ! has_text deny "$out"; then
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
if [ "$rc" = 0 ] && ! has_text deny "$out"; then
  ok "read_receipts() grep read error" "ALLOW rc=0"
else
  bad "read_receipts() grep read error" "rc=$rc out=$out" "ALLOW rc=0"
fi
rm -f "$stub/grep"

finish
