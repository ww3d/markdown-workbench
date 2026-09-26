#!/usr/bin/env bash
#
# Behaviour tests for require-receipt.sh, require-rule-read.sh and
# read-confirm.sh.
#
# Ported from a consumer repo's hook-test suite (provenance: docs/herkunftsbelege.md
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
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
hooks="$(cd "$here/.." && pwd)"
repo_root="$(cd "$hooks/../.." && pwd)"
stop="$hooks/require-receipt.sh"
ruleread="$hooks/require-rule-read.sh"
readconfirm="$hooks/read-confirm.sh"

fix="$(mktemp -d)"
trap 'rm -rf "$fix"' EXIT
bash "$here/mkfixtures.sh" "$fix" >/dev/null

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$1" "$2"; }
bad() { fail=$((fail + 1)); printf '  FAIL %-52s %s (expected %s)\n' "$1" "$2" "$3"; }

echo "== require-receipt.sh agrees with the gate =="
for f in no-receipt with-receipt resumed quote-only drift trunc-no-receipt trunc-then-receipt \
         echo-receipt echo-unrun echo-redirect echo-refused echo-then-resumed; do
  out="$(jq -cn --arg t "$fix/$f.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' | bash "$stop" 2>&1)"
  if   printf '%s' "$out" | grep -q '"decision":"block"'; then v=BLOCK
  elif printf '%s' "$out" | grep -q 'systemMessage'; then v=DRIFT
  elif [ -z "$out" ]; then v=ALLOW; else v="ERR"; fi
  case "$f" in
    # quote-only: the H1 alone is quoted in a code fence, with no "## Konventionen"
    # heading anywhere in the same text - fix #1 (issue ww3d/playbook#198 pt.1) means this
    # must BLOCK, not be read as a receipt.
    no-receipt|resumed|quote-only|trunc-no-receipt) want=BLOCK ;;
    # echo-*: the receipt printed by a command counts only where the command ran
    # without error and its own result shows it (ww3d/playbook#271, same rule as ww3d/playbook#273), and
    # like a text receipt only after the newest SessionStart.
    echo-unrun|echo-redirect|echo-refused|echo-then-resumed) want=BLOCK ;;
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
  elif printf '%s' "$out" | grep -q 'schon einmal'; then printf 'WARN'
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
# only is_error tells it from a real echo - review round 1 of ww3d/playbook#289 found the
# check untested.
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
# Bash was already classified on Windows (the controller of ww3d/playbook#276 saw
# `gh issue close` blocked there); PowerShell, backslash paths and the
# claude.ai connector names were not.
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
count_calls 'Write outside the repo: no transcript read' 'jq=1 grep=0' "$(tool_event "$nr" Write '{"file_path":"/elsewhere/a.md"}' "$(next_sid)")"
count_calls 'triggered call: one grep, one jq pass' 'jq=3 grep=1' "$(tool_event "$nr" Bash '{"command":"gh issue create"}' "$(next_sid)")"
cache_sid="$(next_sid)"
count_calls 'receipt found: read once'          'jq=2 grep=1' "$(tool_event "$fix/rule-receipt-text.jsonl" Bash '{"command":"gh issue create"}' "$cache_sid")"
count_calls 'receipt found before: not read again' 'jq=1 grep=0' "$(tool_event "$fix/rule-receipt-text.jsonl" Bash '{"command":"gh issue create"}' "$cache_sid")"
rm -f "$stub/jq" "$stub/grep"

echo "== require-rule-read.sh: a missing helper degrades to allow, never to block =="
# Only jq: the hook guards it explicitly (`command -v jq >/dev/null 2>&1 ||
# exit 0`, line ~44) precisely because it is the one dependency that is not
# guaranteed to exist everywhere bash does. cat, by contrast, is not something
# this hook defends against losing - `input="$(cat)"` is a bare top-level
# assignment, so a missing cat would exit the whole script under `set -e`
# with cat's own exit code, not 0. That is outside what "fail-open by design"
# in the header claims (it names jq, not cat), so it is not asserted here.
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

echo "== read-confirm.sh: Skills / Memory / OK-per-group / SHA-cache =="
rc_root="$fix/rc-root"
mkdir -p "$rc_root/.claude/skills/beispiel-skill" "$rc_root/.claude/skills/zweiter-skill" \
         "$rc_root/docs/decisions"
printf '# Test Project\n' > "$rc_root/CLAUDE.md"
printf '# Agents\n' > "$rc_root/AGENTS.md"
printf '1.0.0\n' > "$rc_root/VERSION"
cat > "$rc_root/.claude/skills/beispiel-skill/SKILL.md" <<'EOF'
---
name: beispiel-skill
description: 'ein Testskill'
metadata:
  version: "1.2.3"
  source: test
---
# Beispiel
EOF
cat > "$rc_root/.claude/skills/zweiter-skill/SKILL.md" <<'EOF'
---
name: zweiter-skill
description: 'noch ein Testskill'
metadata:
  version: "0.1.0"
  source: test
---
# Zweiter
EOF
printf '# decisions readme\n' > "$rc_root/docs/decisions/README.md"
printf '# log a\n' > "$rc_root/docs/decisions/2026-01-01T0000-a.md"
printf '# log b\n' > "$rc_root/docs/decisions/2026-02-02T0000-b.md"
printf '# docs readme\n' > "$rc_root/docs/README.md"
# Build markers: the first "build NN" of a file wins, case-insensitive; a doc
# without one gets "OK". A second marker further down must not replace it.
printf '# Architektur\n\nStand: Build 7\n\nspaeter: build 99\n' > "$rc_root/docs/architecture.md"
printf '# Plain\n' > "$rc_root/docs/plain.md"

rc_tmp="$fix/rc-tmp"; mkdir -p "$rc_tmp"
rc_config="$fix/rc-config-empty"; mkdir -p "$rc_config"
# An empty managed directory, so the machine's own policy never decides a case.
rc_managed="$fix/rc-managed-empty"; mkdir -p "$rc_managed"
export READ_CONFIRM_MANAGED_DIR="$rc_managed"

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

check_contains 'Skills group header present'     '## Skills' "$ctx1"
check_contains 'skill beispiel-skill listed'      '- beispiel-skill v1.2.3' "$ctx1"
check_contains 'skill zweiter-skill listed'       '- zweiter-skill v0.1.0' "$ctx1"

ok_count="$(printf '%s\n' "$ctx1" | grep -c '^OK$' || true)"
if [ "${ok_count:-0}" = "4" ]; then ok 'all four groups close with their own OK' "$ok_count"
else bad 'all four groups close with their own OK' "${ok_count:-0}" "4"; fi

check_contains 'Memory honest fallback when nothing is found' \
  'Memory-Stand: — (nicht verfuegbar in dieser Umgebung)' "$ctx1"

check_contains 'a doc reports its first build marker'  '- docs/architecture.md build 7' "$ctx1"
check_contains 'a doc without a build marker gets OK'  '- docs/plain.md OK' "$ctx1"

check_contains 'docs/decisions README skipped in count and sort (already fixed, regression check)' \
  'docs/decisions/ — 2 Logs, neuestes 2026-02-02' "$ctx1"
check_not_contains 'docs/README.md not listed as an individual doc line' \
  '- docs/README.md' "$ctx1"

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

# Memory group, positive case: a MEMORY.md index this environment CAN see. Its
# own TMPDIR keeps this run's cache writes out of the cache-test sequence below.
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
check_contains 'Memory counts real MEMORY.md entries when found' 'Memory: 3 Eintraege (MEMORY.md)' "$ctx_mem"

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
  'Memory-Stand: — (nicht verfuegbar in dieser Umgebung)' "$ctx_foreign"

# SHA-cache: run 1 (above, ctx1) got the full line; run 2, file unchanged,
# must get the short line; then the file changes and run 3 gets the full line
# again. All three runs share $rc_tmp, so the cache file persists between them.
check_contains 'run 1 lists CLAUDE.md in full (nothing cached yet)' \
  '- CLAUDE.md @ projekt OK' "$ctx1"
ctx2="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'unchanged CLAUDE.md gets the short cache line on run 2' \
  '- CLAUDE.md: unveraendert seit' "$ctx2"

printf '# Test Project (geaendert)\n' > "$rc_root/CLAUDE.md"
ctx3="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'a changed CLAUDE.md gets the full line again on run 3' \
  '- CLAUDE.md @ projekt OK' "$ctx3"
check_not_contains 'a changed CLAUDE.md is not reported as unveraendert' \
  '- CLAUDE.md: unveraendert seit' "$ctx3"

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
    | jq -r '.hookSpecificOutput.additionalContext' | grep '^- Stop-Hook'
}
chk_gate() { # label, expected substring
  local got; got="$(gate_line)"
  if printf '%s' "$got" | grep -qF -- "$2"; then ok "$1" "found"
  else bad "$1" "$got" "$2"; fi
}

gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
chk_gate 'registered in the project settings'  '- Stop-Hook require-receipt.sh: registriert (Projekt), lesbar'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.local.json"
chk_gate 'registered in the local settings'    'registriert (Lokal), lesbar'
gate_setup; printf '%s' "$stop_entry" > "$g_cfg/settings.json"
chk_gate 'registered in the user settings only' 'registriert (Nutzer), lesbar'
gate_setup; mkdir -p "$g_mgd/managed-settings.d"; printf '%s' "$stop_entry" > "$g_mgd/managed-settings.d/10-gate.json"
chk_gate 'registered in a managed drop-in'     'registriert (Managed), lesbar'
gate_setup
# shellcheck disable=SC2016 # the settings file must hold $CLAUDE_PROJECT_DIR literally
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \\"$CLAUDE_PROJECT_DIR/.claude/hooks/require-receipt.sh\\""}]}]}}' \
  > "$g_root/.claude/settings.json"
chk_gate 'registered in the shell form'        'registriert (Projekt), lesbar'

gate_setup
chk_gate 'no settings file anywhere'           '— in keiner lesbaren Einstellungsdatei registriert (gelesen: keine)'
chk_gate 'not found names what it cannot see'  '/hooks zeigt alle'
gate_setup
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash","args":["x/require-receipt.sh"]}]}]}}' \
  > "$g_root/.claude/settings.json"
chk_gate 'registered under SessionStart, not Stop' '(gelesen: Projekt)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; rm "$g_root/.claude/hooks/require-receipt.sh"
chk_gate 'registered, hook file missing'       'registriert (Projekt); .claude/hooks/require-receipt.sh fehlt oder ist unlesbar'
gate_setup; printf '{"hooks": {' > "$g_root/.claude/settings.json"; printf '%s' "$stop_entry" > "$g_cfg/settings.json"
chk_gate 'broken project JSON beside a user registration' 'registriert (Nutzer); ungueltiges JSON: Projekt'

gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"disableAllHooks": true}' > "$g_root/.claude/settings.local.json"
chk_gate 'disableAllHooks in the local settings' 'abgeschaltet durch disableAllHooks (Lokal)'
gate_setup; printf '{"disableAllHooks": false, "hooks": %s}' "$(printf '%s' "$stop_entry" | jq -c .hooks)" \
  > "$g_root/.claude/settings.json"
printf '{"disableAllHooks": true}' > "$g_cfg/settings.json"
chk_gate 'a project false outranks a user true' 'registriert (Projekt), lesbar'
gate_setup; printf '%s' "$stop_entry" > "$g_mgd/managed-settings.json"
printf '{"disableAllHooks": true}' > "$g_root/.claude/settings.json"
chk_gate 'a project disableAllHooks leaves a managed hook running' 'registriert (Managed), lesbar'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.json"
chk_gate 'allowManagedHooksOnly blocks a project registration' 'gesperrt durch allowManagedHooksOnly (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_root/.claude/settings.local.json"
chk_gate 'allowManagedHooksOnly outside Managed has no effect' 'registriert (Projekt), lesbar'

# Managed files merge base first, then the drop-ins in name order; the later
# file wins a single value. Each pair contradicts itself in both directions.
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"disableAllHooks": true}' > "$g_mgd/managed-settings.d/10-a.json"
printf '{"disableAllHooks": false}' > "$g_mgd/managed-settings.d/20-b.json"
chk_gate 'a later drop-in false outranks an earlier true' 'registriert (Projekt), lesbar'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"disableAllHooks": false}' > "$g_mgd/managed-settings.d/10-a.json"
printf '{"disableAllHooks": true}' > "$g_mgd/managed-settings.d/20-b.json"
chk_gate 'a later drop-in true outranks an earlier false' 'abgeschaltet durch disableAllHooks (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.json"
printf '{"allowManagedHooksOnly": false}' > "$g_mgd/managed-settings.d/10-a.json"
chk_gate 'a drop-in outranks the managed base file' 'registriert (Projekt), lesbar'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"allowManagedHooksOnly": false}' > "$g_mgd/managed-settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.d/10-a.json"
chk_gate 'a drop-in true outranks a base false' 'gesperrt durch allowManagedHooksOnly (Managed)'

# Without jq the Stop hook itself cannot judge; the line says so rather than
# guessing. PATH then holds only what read-confirm.sh needs besides bash.
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
nojq="$fix/gate-nojq"; mkdir -p "$nojq"
for helper in git grep mv rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$(command -v bash)" "$(command -v "$helper")" > "$nojq/$helper"
  chmod +x "$nojq/$helper"
done
got="$(gate_line "$nojq")"
if printf '%s' "$got" | grep -qF 'jq fehlt'; then ok 'without jq' 'found'; else bad 'without jq' "$got" 'jq fehlt'; fi
# A failing jq must leave a valid receipt, never an aborted hook.
printf '#!/usr/bin/env bash\nexit 2\n' > "$stub/jq"; chmod +x "$stub/jq"
got="$(gate_line "$stub:$PATH")"
if printf '%s' "$got" | grep -qF 'nicht auswertbar (jq-Fehler)'; then ok 'jq failing on the settings' 'found'
else bad 'jq failing on the settings' "$got" 'nicht auswertbar (jq-Fehler)'; fi
rm -f "$stub/jq"

echo "== read-confirm.sh: process starts do not grow with the number of files (ww3d/playbook#275) =="
# Under Git Bash each process start costs tens of milliseconds; a start per
# listed file took 67-96 s on a real repository. Shadow every external command
# the hook has ever used with a logger, and hold the total to a small constant
# across a project of 40 docs, cold and warm.
many="$fix/rc-many"
mkdir -p "$many/docs" "$many/tech/common" "$fix/rc-tmp-many"
printf '# P\n' > "$many/CLAUDE.md"; printf '# A\n' > "$many/AGENTS.md"
for i in $(seq 1 40); do printf '# Doc %s\n\nbuild %s\n' "$i" "$i" > "$many/docs/d$i.md"; done
printf '# o\n' > "$many/tech/common/dotnet.md"
calls="$fix/rc-calls.log"
for helper in git grep awk sed head tr mktemp mv cat basename; do
  real="$(command -v "$helper")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$real" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
for run in cold warm; do
  : > "$calls"
  out_many="$(CLAUDE_PROJECT_DIR="$many" TMPDIR="$fix/rc-tmp-many" CLAUDE_CONFIG_DIR="$rc_config" PATH="$stub:$PATH" bash "$readconfirm")"
  n_calls="$("$real_grep" -c . "$calls" || true)"
  if [ "${n_calls:-0}" -le 3 ]; then ok "40 docs, $run: at most 3 process starts" "$n_calls"
  else bad "40 docs, $run: at most 3 process starts" "$n_calls ($(tr '\n' ' ' < "$calls"))" "<= 3"; fi
done
for helper in git grep awk sed head tr mktemp mv cat basename; do rm -f "$stub/$helper"; done
check_contains 'the warm run still reports unchanged files' '- docs/d40.md: unveraendert seit' \
  "$(printf '%s' "$out_many" | jq -r '.hookSpecificOutput.additionalContext')"

echo
printf '%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
