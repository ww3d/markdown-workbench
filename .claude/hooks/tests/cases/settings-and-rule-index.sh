#!/usr/bin/env bash
# Hook suite section: the skill table, the rule index and the hook registration
# Run alone: bash .claude/hooks/tests/cases/settings-and-rule-index.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== skill table and UserPromptExpansion matcher name the same skills (follow-up to ww3d/playbook#526) =="
# $1 = the `skill_table=(...)` line of the hook, $2 = a matcher; prints the names only one of them holds.
sk_parity() {
  local tbl="$1" matcher="$2" names entries=()
  matcher="${matcher%$'\r'}"; tbl="${tbl%$'\r'}"
  tbl="${tbl#skill_table=(}"; tbl="${tbl%%)*}"
  read -ra entries <<<"$tbl"
  names="$(printf '%s\n' "${entries[@]}" | sed 's/:.*//' | sort)"
  matcher="${matcher#*)?(}"; matcher="${matcher%)\$}"
  local d l out=""
  d="$(diff <(printf '%s\n' "$names") <(printf '%s\n' "$matcher" | tr '|' '\n' | sort))"
  while IFS= read -r l; do case "$l" in '<'* | '>'*) out+="$l " ;; esac; done <<<"$d"
  printf '%s' "$out"
}
# The hook's lines the checks below read: its code (no comment lines) and its `skill_table=(` line, read once.
si_code=(); si_skill=(); si_gate=()
while IFS= read -r si_l || [ -n "$si_l" ]; do
  [[ $si_l =~ ^[[:space:]]*# ]] || si_code+=("$si_l")
  [[ $si_l == 'skill_table=('* ]] && si_skill+=("$si_l")
  [[ $si_l == 'gate_actions='* ]] && si_gate+=("$si_l")
done < "$ruleread"
si_filter() { # prefix, stdin -> the lines that start with the prefix
  local l
  while IFS= read -r l; do [[ $l == "$1"* ]] && printf '%s\n' "$l"; done
}
sk_line="$(printf '%s\n' "${si_skill[@]}")"
for sf in "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; do
  um="$(jq -r '[.hooks.UserPromptExpansion[]? | select(.hooks[].args[]? | test("require-rule-read\\.sh$")) | .matcher] | first // "unset"' "$sf")"
  expect "${sf#"$repo_root"/}: the matcher names the skills of the hook's table" '' "$(sk_parity "$sk_line" "$um")"
done
expect 'mutation: a skill only in the table is red'   '< chat-handoff ' "$(sk_parity "$sk_line" '^([A-Za-z0-9_.-]+:)?(ccweb-prompt|state-audit)$')"
expect 'mutation: a skill only in the matcher is red' '> extra-skill '  "$(sk_parity "$sk_line" '^([A-Za-z0-9_.-]+:)?(ccweb-prompt|state-audit|chat-handoff|extra-skill)$')"

echo "== rule index: every trigger has an action that raises it, or a reasoned exception (ww3d/playbook#526) =="
# The triggers come from the index of the rule table; an action is an `add_trigger <trigger>` of the hook. An exception
# names its reason; one that the hook maps by now is stale. A trigger of the skill table counts as mapped.
cov_exceptions='chat|the first answer is text; no hook event blocks text'
cov_check() { # exception list -> lines "trigger: problem" for each trigger that breaks the rule, empty when it holds
  local t mapped exc reason re_code re_skill l
  while IFS= read -r t; do
    t="${t%$'\r'}"; mapped=0; exc=0; reason=""
    re_code="add_trigger ${t}([^A-Za-z0-9_-]|\$)"; re_skill=":${t}([ )]|\$)"
    for l in "${si_code[@]}"; do [[ $l =~ $re_code ]] && { mapped=1; break; }; done
    for l in "${si_skill[@]}"; do [[ $l =~ $re_skill ]] && { mapped=1; break; }; done
    while IFS= read -r l; do
      if [[ $l == "${t}|"* ]]; then exc=1; reason="${l#*|}"; break; fi
    done <<<"$1"
    if   [ "$exc" = 1 ] && [ "$mapped" = 1 ]; then printf '%s: excepted but mapped (stale exception)\n' "$t"
    elif [ "$exc" = 1 ] && [ -z "$reason" ];  then printf '%s: exception without a reason\n' "$t"
    elif [ "$exc" = 0 ] && [ "$mapped" = 0 ]; then printf '%s: no action raises it and no exception\n' "$t"; fi
  done < <(jq -r '.rules[].trigger' "$repo_root/.agents/rules/index.json")
}
expect 'every trigger of the rule table has an action or a reasoned exception' '' "$(cov_check "$cov_exceptions")"
expect 'the exception list holds chat alone' 'chat' "$(printf '%s\n' "$cov_exceptions" | cut -d'|' -f1)"
expect 'mutation: an exception without a reason fails' 'chat: exception without a reason' "$(cov_check 'chat|
zzz|x' | si_filter chat)"
expect 'mutation: a stale exception (audit is mapped) fails' 'audit: excepted but mapped (stale exception)' "$(cov_check "$cov_exceptions"$'\naudit|why' | si_filter audit)"
expect 'mutation: an unmapped trigger without exception fails' 'chat: no action raises it and no exception' "$(cov_check 'zzz|x' | si_filter chat)"
expect 'mutation: a stale exception (session is mapped by the skill table) fails' 'session: excepted but mapped (stale exception)' "$(cov_check "$cov_exceptions"$'\nsession|why' | si_filter session)"
# The actions a local rule may gate (gate_actions of the hook) are exactly the triggers the hook raises.
raised="$({ printf '%s\n' "${si_code[@]}" | grep -oE 'add_trigger [a-z]+' | sed 's/^add_trigger //'
  printf '%s\n' "${si_skill[@]}" | tr -d '\r' | sed 's/^skill_table=(//; s/).*//' | tr ' ' '\n' | sed 's/.*://'; } | grep -v '^$' | sort -u | paste -sd,)"
listed="$(printf '%s\n' "${si_gate[@]}" | tr -d '\r' | sed 's/^gate_actions="//; s/"$//; s/^,//; s/,$//')"
expect 'gate_actions of the hook are the triggers it raises (add_trigger and skill table)' "$raised" "$listed"

echo "== settings: the new hooks are registered, template and project alike =="
for sf in "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; do
  label="${sf#"$repo_root"/}"
  g="$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].args[]? | select(test("guard-kill\\.sh$"))] | length' "$sf")"
  r="$(jq -r '[.hooks.PostToolUse[]? | select(.matcher == "Read") | .hooks[].args[]? | select(test("record-rule-read\\.sh$"))] | length' "$sf")"
  sv="$(jq -r '[.hooks.PreCompact[]? | .hooks[].args[]? | select(test("save-compact-state\\.sh$"))] | length' "$sf")"
  rs="$(jq -r '[.hooks.SessionStart[]? | select(.matcher == "compact") | .hooks[].args[]? | select(test("restore-compact-state\\.sh$"))] | length' "$sf")"
  rmd="$(jq -r '[.hooks.PostToolUse[]? | .hooks[].args[]? | select(test("remind-before-compact\\.sh$"))] | length' "$sf")"
  ban="$(jq -r '[.hooks.Stop[]? | .hooks[] | select(.asyncRewake != true) | .args[]? | select(test("block-announce-end\\.sh$"))] | length' "$sf")"
  brw="$(jq -r '[.hooks.Stop[]? | .hooks[] | select(.asyncRewake == true and .args[1] == "--rewake" and (.args[0] | test("block-announce-end\\.sh$"))) | .timeout] | first // "unset"' "$sf")"
  c="$(jq -r '.cleanupPeriodDays // "unset"' "$sf")"
  ic="$(jq -r '.idleCompaction | if . == null then "unset" else "\(type):\(.)" end' "$sf")"
  m="$(jq -r '.hooks.PreToolUse[0].matcher' "$sf")"
  expect "$label: the rule gate starts for the tools tool_re names" 'Bash|PowerShell|Write|Edit|NotebookEdit|Agent|Task|Workflow|Skill|mcp__.*[Gg]it[Hh]ub.*' "$m"
  um="$(jq -r '[.hooks.UserPromptExpansion[]? | select(.hooks[].args[]? | test("require-rule-read\\.sh$")) | .matcher] | first // "unset"' "$sf")"
  um_got=""
  for nm in ccweb-prompt state-audit chat-handoff anthropic-skills:ccweb-prompt anthropic-skills:state-audit anthropic-skills:chat-handoff dev-task anthropic-skills:dev-task ccweb-prompt-x x-state-audit chat-handoff-x my-chat-handoff; do
    if jq -e -n --arg m "$um" --arg n "$nm" '$n | test($m)' >/dev/null 2>&1; then um_got="$um_got $nm"; fi
  done
  expect "$label: the UserPromptExpansion matcher covers the three skills, plain and prefixed, and no other command (ww3d/playbook#526)" \
    ' ccweb-prompt state-audit chat-handoff anthropic-skills:ccweb-prompt anthropic-skills:state-audit anthropic-skills:chat-handoff' "$um_got"
  expect "$label registers guard-kill.sh for Bash|PowerShell" 1 "$g"
  expect "$label registers record-rule-read.sh for Read"      1 "$r"
  expect "$label registers save-compact-state.sh on PreCompact" 1 "$sv"
  expect "$label registers restore-compact-state.sh on compact" 1 "$rs"
  expect "$label registers remind-before-compact.sh on PostToolUse" 1 "$rmd"
  expect "$label registers block-announce-end.sh on Stop" 1 "$ban"
  expect "$label registers the wake entry of block-announce-end.sh on Stop as asyncRewake, timeout past 600 s" 660 "$brw"
  expect "$label sets cleanupPeriodDays"                      180 "$c"
  expect "$label turns idleCompaction off"                    boolean:false "$ic"
done
if cmp -s "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; then ok 'project settings equal the template' same
else bad 'project settings equal the template' differ same; fi

finish
