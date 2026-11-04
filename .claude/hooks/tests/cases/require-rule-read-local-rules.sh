#!/usr/bin/env bash
# Hook suite section: require-rule-read.sh, local rules and their gate key
# Run alone: bash .claude/hooks/tests/cases/require-rule-read-local-rules.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

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
lr_t() { # session, tool_input, markers, transcript
  local m
  mkdir -p "$gate_tmp/claude-rule-gate"
  for m in $3; do : > "$gate_tmp/claude-rule-gate/$1-read-main-$m"; done
  rule_verdict "$(tool_event "$4" Write "$2" "$1")" "$lr_root"
}
expect 'a local rule receipted as local/<name>.md'         ALLOW "$(lr_t "lr-r1-$$" "$lr_code" code "$fix/rule-new-receipt-local.jsonl")"
expect 'a local rule receipted by its bare name: refused'  DENY  "$(lr_t "lr-r2-$$" "$lr_code" code "$fix/rule-new-receipt-local-bare.jsonl")"
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
  if has_text '"permissionDecision":"deny"' "$out"; then v=DENY
  elif [ -z "$out" ] && [ ! -s "$fix/lf-err" ]; then v=ALLOW
  elif [ -z "$out" ] && has_text 'is unknown and never blocks' "$(<"$fix/lf-err")"; then v=NOTE
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

finish
