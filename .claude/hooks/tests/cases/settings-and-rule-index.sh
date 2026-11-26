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
si_code=(); si_skill=(); si_gate=(); si_restore=""
while IFS= read -r si_l || [ -n "$si_l" ]; do
  [[ $si_l =~ ^[[:space:]]*# ]] || si_code+=("$si_l")
  [[ $si_l == 'skill_table=('* ]] && si_skill+=("$si_l")
  [[ $si_l == 'gate_actions='* ]] && si_gate+=("$si_l")
  [[ $si_l =~ ^restore_skill=([A-Za-z0-9_.-]+) ]] && si_restore="${BASH_REMATCH[1]}"
done < "$ruleread"
si_filter() { # prefix, stdin -> the lines that start with the prefix
  local l
  while IFS= read -r l; do [[ $l == "$1"* ]] && printf '%s\n' "$l"; done
}
sk_line="$(printf '%s\n' "${si_skill[@]}")"
# The skill that owes the restore of its predecessor (ww3d/playbook#672) stands in the matcher beside the table.
sk_all="${sk_line%%)*}${si_restore:+ $si_restore:restore})"
for sf in "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; do
  um="$(jq -r '[.hooks.UserPromptExpansion[]? | select(.hooks[].command? | test("require-rule-read\\.sh\"$")) | .matcher] | first // "unset"' "$sf")"
  expect "${sf#"$repo_root"/}: the matcher names the skills of the hook's table" '' "$(sk_parity "$sk_all" "$um")"
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
  g="$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].command? | select(test("guard-kill\\.sh\"$"))] | length' "$sf")"
  r="$(jq -r '[.hooks.PostToolUse[]? | select(.matcher == "Read") | .hooks[].command? | select(test("record-rule-read\\.sh\"$"))] | length' "$sf")"
  sv="$(jq -r '[.hooks.PreCompact[]? | .hooks[].command? | select(test("save-compact-state\\.sh\"$"))] | length' "$sf")"
  rs="$(jq -r '[.hooks.SessionStart[]? | select(.matcher == "compact|clear|startup") | .hooks[].command? | select(test("restore-compact-state\\.sh\"$"))] | length' "$sf")"
  rse="$(jq -r '[.hooks.SessionEnd[]? | select(.matcher == "clear") | .hooks[].command? | select(test("restore-compact-state\\.sh\"$"))] | length' "$sf")"
  rmd="$(jq -r '[.hooks.PostToolUse[]? | .hooks[].command? | select(test("remind-before-compact\\.sh\"$"))] | length' "$sf")"
  ban="$(jq -r '[.hooks.Stop[]? | .hooks[] | select(.asyncRewake != true) | .command? | select(test("block-announce-end\\.sh\"$"))] | length' "$sf")"
  brw="$(jq -r '[.hooks.Stop[]? | .hooks[] | select(.asyncRewake == true and (.command | test("block-announce-end\\.sh\" --rewake$"))) | .timeout] | first // "unset"' "$sf")"
  c="$(jq -r '.cleanupPeriodDays // "unset"' "$sf")"
  ic="$(jq -r '.idleCompaction | if . == null then "unset" else "\(type):\(.)" end' "$sf")"
  m="$(jq -r '.hooks.PreToolUse[0].matcher' "$sf")"
  expect "$label: the rule gate starts for the tools tool_re names" 'Bash|PowerShell|Write|Edit|NotebookEdit|Agent|Task|Workflow|Skill|mcp__.*[Gg]it[Hh]ub.*' "$m"
  um="$(jq -r '[.hooks.UserPromptExpansion[]? | select(.hooks[].command? | test("require-rule-read\\.sh\"$")) | .matcher] | first // "unset"' "$sf")"
  um_got=""
  for nm in ccweb-prompt state-audit chat-handoff anthropic-skills:ccweb-prompt anthropic-skills:state-audit anthropic-skills:chat-handoff dev-task anthropic-skills:dev-task ccweb-prompt-x x-state-audit chat-handoff-x my-chat-handoff; do
    if jq -e -n --arg m "$um" --arg n "$nm" '$n | test($m)' >/dev/null 2>&1; then um_got="$um_got $nm"; fi
  done
  expect "$label: the UserPromptExpansion matcher covers the three skills, plain and prefixed, and no other command (ww3d/playbook#526)" \
    ' ccweb-prompt state-audit chat-handoff anthropic-skills:ccweb-prompt anthropic-skills:state-audit anthropic-skills:chat-handoff' "$um_got"
  expect "$label registers guard-kill.sh for Bash|PowerShell" 1 "$g"
  expect "$label registers record-rule-read.sh for Read"      1 "$r"
  expect "$label registers save-compact-state.sh on PreCompact" 1 "$sv"
  expect "$label registers restore-compact-state.sh on compact, clear and startup" 1 "$rs"
  expect "$label registers restore-compact-state.sh on SessionEnd clear" 1 "$rse"
  expect "$label registers remind-before-compact.sh on PostToolUse" 1 "$rmd"
  expect "$label registers block-announce-end.sh on Stop" 1 "$ban"
  expect "$label registers the wake entry of block-announce-end.sh on Stop as asyncRewake, timeout past 600 s" 660 "$brw"
  expect "$label sets cleanupPeriodDays"                      180 "$c"
  expect "$label turns idleCompaction off"                    boolean:false "$ic"
done
if cmp -s "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; then ok 'project settings equal the template' same
else bad 'project settings equal the template' differ same; fi

echo "== settings: every entry sources its hook file in the one bash Claude Code starts (ww3d/playbook#734, decision 2) =="
# The form, file f and arguments a: `[ -f "f" ] || exit 0; [ -n "$BASH_VERSION" ] || exec bash "f" a; . "f" a`,
# the same file three times: a bash sources the hook, any other shell (/bin/sh on Linux) hands it to bash. The list
# is event/hook and its arguments, read from the sourced path; any other text is no entry of this form.
sf_form() { # settings file -> one line per entry: "<event>/<hook>[ <arguments>]", or "<event>: other form: <command>"
  jq -r '.hooks | to_entries[] | .key as $e | .value[] | .hooks[] | .command as $c
    | ($c | capture("^\\[ -f \"\\$\\{CLAUDE_PROJECT_DIR\\}/\\.claude/hooks/(?<a>[^\"]+)\" \\] \\|\\| exit 0; \\[ -n \"\\$BASH_VERSION\" \\] \\|\\| exec bash \"\\$\\{CLAUDE_PROJECT_DIR\\}/\\.claude/hooks/(?<c>[^\"]+)\"(?<cargs>( [^ \"]+)*); \\. \"\\$\\{CLAUDE_PROJECT_DIR\\}/\\.claude/hooks/(?<b>[^\"]+)\"(?<args>( [^ \"]+)*)$")? // null) as $m
    | if $m != null and $m.a == $m.b and $m.c == $m.b and $m.cargs == $m.args then "\($e)/\($m.b)\($m.args)" else "\($e): other form: \($c)" end' "$1" | tr -d '\r'
}
sf_want='SessionStart/read-confirm.sh
SessionStart/restore-compact-state.sh
SessionEnd/restore-compact-state.sh
PreCompact/save-compact-state.sh
UserPromptExpansion/require-rule-read.sh
PreToolUse/require-rule-read.sh
PreToolUse/guard-kill.sh
PreToolUse/guard-shared-tmp.sh
PostToolUse/record-rule-read.sh
PostToolUse/remind-before-compact.sh
Stop/require-receipt.sh
Stop/block-announce-end.sh
Stop/block-announce-end.sh --rewake'
for sf in "$repo_root/.claude/settings.json" "$repo_root/templates/root/.claude/settings.json"; do
  expect "${sf#"$repo_root"/}: every entry sources its hook, arguments after the file" "$sf_want" "$(sf_form "$sf")"
done
printf '%s' '{"hooks":{"Stop":[{"hooks":[{"command":"[ -f \"${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh\" ] || exit 0; exec bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh\""},{"command":"[ -f \"${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh\" ] || exit 0; . \"${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh\""}]}]}}' > "$fix/sf-old.json"
expect 'mutation: exec bash alone, and sourcing without the bash guard, are other forms' \
  'Stop: other form: [ -f "${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh" ] || exit 0; exec bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh"
Stop: other form: [ -f "${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh" ] || exit 0; . "${CLAUDE_PROJECT_DIR}/.claude/hooks/a.sh"' "$(sf_form "$fix/sf-old.json")"

# Sourced, a hook runs as the bash -c shell itself: `$0` is `bash`, and a `return` outside a function ends the file
# instead of failing on. So no hook or lib reads `$0` for its path, and no hook returns at its top level.
sf_top_returns() { # shell file -> the top-level `return` lines, from bash's own normal form of the file
  local body
  body="$(bash -c 'eval "__sf_wrap() {
$(cat "$1")
}" && declare -f __sf_wrap' _ "$1" 2>/dev/null)" || { printf 'unparsable\n'; return; }
  awk -v f="${1##*/}" 'NR <= 2 { next }
    fn == "" && /^ *function [^ ]+ \(\) *$/ { fn = substr($0, 1, index($0, "f") - 1) "}"; next }
    fn != "" { if (index($0, fn) == 1 && substr($0, length(fn) + 1) ~ /^;? *$/) fn = ""; next }
    /(^|[;&|[:space:]])return([[:space:];]|$)/ { print f ": " $0 }' <<<"$body"
}
sf_self_path() { # shell file... -> the code lines that read `$0` as the shell's own path
  grep -HnE '"\$0"|\$\{0[}%#/:]|BASH_ARGV0' "$@" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | sed 's#^.*/##'
}
sf_hooks="$(sf_form "$repo_root/.claude/settings.json" | sed -n 's#^[A-Za-z]*/\([^ ]*\).*#\1#p' | sort -u)"
sf_got=""
while IFS= read -r sf_h; do sf_got+="$(sf_top_returns "$hooks/$sf_h")"; done <<< "$sf_hooks"
expect 'no registered hook returns at its top level' '' "$sf_got"
# shellcheck disable=SC2086 # the hook names are plain file names
expect 'no registered hook and no lib reads $0 for its own path' '' "$(cd "$hooks" && sf_self_path $sf_hooks lib/*.sh)"
printf 'x=1\nf() {\n  return 1\n}\nif [ "$x" = 1 ]; then return 0; fi\n' > "$fix/sf-ret.sh"
expect 'mutation: a return in an if at the top level is found, one in a function is not' 'sf-ret.sh:         return 0;' "$(sf_top_returns "$fix/sf-ret.sh")"
printf '# "$0" in a comment\nhere="$(dirname "$0")"\nawk %s\n' "'{ print \$0 }'" > "$fix/sf-zero.sh"
expect 'mutation: a path read from $0 is found, a comment and awk are not' 'sf-zero.sh:2:here="$(dirname "$0")"' "$(sf_self_path "$fix/sf-zero.sh")"

echo "== settings: a guard with onFailure block runs its file, and passes without it (ww3d/playbook#719, q1887 a) =="
# The command text of each blocking entry, run as Claude Code runs it under "shell": "bash": with the file it is the
# guard (stdin, stdout and exit code its own), without it exit 0 and no output,
# so a missing file never locks the session.
og_dir="$fix/onfailure-guard"; mkdir -p "$og_dir/with/.claude/hooks" "$og_dir/without/.claude/hooks"
og_cmds="$(jq -r '[.hooks[][] | .hooks[] | select(.onFailure == "block") | .command] | .[]' "$repo_root/.claude/settings.json")"
og_names="$(jq -r '[.hooks | to_entries[] | .key as $e | .value[] | .hooks[] | select(.onFailure == "block")
  | "\($e)/\(.command | capture("hooks/(?<n>[^\"]+)\"$").n)"] | join(" ")' "$repo_root/.claude/settings.json")"
expect 'the four guard entries block on failure, no other entry' \
  'UserPromptExpansion/require-rule-read.sh PreToolUse/require-rule-read.sh PreToolUse/guard-kill.sh PreToolUse/guard-shared-tmp.sh' "${og_names%$'\r'}"
while IFS= read -r og_cmd; do
  og_cmd="${og_cmd%$'\r'}"; [ -n "$og_cmd" ] || continue
  og_name="${og_cmd##*/hooks/}"; og_name="${og_name%\"}"
  printf '#!/usr/bin/env bash\nprintf "ran:%%s" "$(cat)"\nexit 3\n' > "$og_dir/with/.claude/hooks/$og_name"
  out="$(printf 'payload' | CLAUDE_PROJECT_DIR="$og_dir/with" bash -c "$og_cmd" 2>&1)"; rc=$?
  expect "$og_name: with its file the guard runs on the payload, its exit code stands" '3:ran:payload' "$rc:$out"
  out="$(printf 'payload' | CLAUDE_PROJECT_DIR="$og_dir/without" bash -c "$og_cmd" 2>&1)"; rc=$?
  expect "$og_name: without its file the call passes" '0:' "$rc:$out"
done <<< "$og_cmds"
# Mutation: the bare command text of the other entries ends with 127 on a missing file,
# which onFailure block turns into a lock.
out="$(printf 'payload' | CLAUDE_PROJECT_DIR="$og_dir/without" bash -c 'bash "${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-kill.sh"' 2>/dev/null)"; rc=$?
expect 'mutation: the bare form fails without its file' 127 "$rc"

finish
