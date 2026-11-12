#!/usr/bin/env bash
# Hook suite section: remind-before-compact.sh by session kind and place (ww3d/playbook#487, decisions 11-18)
# One fixture T-<kind>-<place> per cell of the table "Testfaelle Art x Ort" in docs/tasks/487-save-restore.md.
# The place is only a set of inputs: ia, bg and hl carry the window of the kind (CLAUDE_CODE_AUTO_COMPACT_WINDOW
# where its autoCompactWindow is not "0", else the model id); web carries CLAUDE_CODE_REMOTE=true and
# CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 without a window. bg also checks that no third notice comes, hl that a
# save without a kept transcript fails.
# Run alone: bash .claude/hooks/tests/cases/remind-kind-place.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== remind-before-compact.sh: the mark of the session kind and the notice at the limit, per place =="
remind_cs="$hooks/remind-before-compact.sh"
kp_root="$fix/kp-root"; mkdir -p "$kp_root/.agents"
cp "$repo_root/.agents/session-kinds.json" "$kp_root/.agents/session-kinds.json"

kp_tx() { # transcript, slash command or "", fill -> a transcript of that session
  local c=""
  if [ -n "$2" ]; then
    js "<command-message>${2#/} is running</command-message>
<command-name>$2</command-name>
<command-args>ww3d/playbook</command-args>"; c="$REPLY"
  fi
  { [ -z "$c" ] || printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$c"
    printf '{"type":"assistant","message":{"model":"claude-opus-5-5","role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":5}}}\n' "$(($3 - 2))"
  } > "$1"
}
kp_call() { # session, transcript, root, NAME=value... -> the hook's additionalContext, or nothing
  local s="$1" t="$2" r="$3"; shift 3
  mkdir -p "$cs_gate"; printf '0 0\n' > "$cs_gate/$s-remind-state"
  remind_event "$s" "$t" \
    | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u ANTHROPIC_MODEL \
      -u CLAUDE_CODE_DISABLE_1M_CONTEXT -u PLAYBOOK_SESSION_KIND -u CLAUDE_CODE_REMOTE \
      TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$r" "$@" bash "$remind_cs" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# kind -> short name, the window of ia/bg/hl ("" = model id, 1,000,000), the mark, the word after Gesichert
declare -A kp_short=([controller]=ctrl [orchestrator]=orch [design]=design [research]=research [dev]=dev [review]=review)
declare -A kp_win=([controller]=600000 [orchestrator]=600000 [design]='' [research]='' [dev]=300000 [review]=300000)
declare -A kp_mark=([controller]=400000 [orchestrator]=400000 [design]=700000 [research]=700000 [dev]=0 [review]=0)
declare -A kp_word=([controller]=compact [orchestrator]=compact [design]=successor [research]=successor [dev]=net [review]=net)
# where the kind comes from: the variable, the slash command, or defaultKind
declare -A kp_src=([controller]=/controller-mode [orchestrator]=env [design]=/ccweb-prompt [research]=env [dev]=default [review]=/pr-poll-review)

kp_cell() { # kind, place
  local k="$1" p="$2" id s t env=() limit second mark cmd="" ctx
  id="T-${kp_short[$k]}-$p"; s="kp-${kp_short[$k]}-$p"; t="$fix/$s.jsonl"
  case "${kp_src[$k]}" in env) env+=("PLAYBOOK_SESSION_KIND=$k") ;; default) ;; *) cmd="${kp_src[$k]}" ;; esac
  if [ "$p" = web ]; then
    env+=(CLAUDE_CODE_REMOTE=true CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80); limit=800000
  elif [ -n "${kp_win[$k]}" ]; then
    env+=("CLAUDE_CODE_AUTO_COMPACT_WINDOW=${kp_win[$k]}"); limit=$((kp_win[$k] * 84 / 100))
  else
    limit=840000
  fi
  second=$((limit * 85 / 100)); mark="${kp_mark[$k]}"
  [ "$mark" -lt "$second" ] || mark=0
  if [ "$mark" -gt 0 ]; then
    kp_tx "$t" "$cmd" $((mark - 1))
    expect "$id: one token below the mark $mark is silent" '' "$(kp_call "$s" "$t" "$kp_root" "${env[@]}")"
    kp_tx "$t" "$cmd" "$mark"
    ctx="$(kp_call "$s" "$t" "$kp_root" "${env[@]}")"
    check_contains "$id: the mark $mark reports the kind" "Marke der Session-Art $k" "$ctx"
    check_contains "$id: the mark says save first" 'zuerst SICHERN' "$ctx"
    check_contains "$id: the mark names --transcript and --session" "save --transcript '$t' --session $s" "$ctx"
    check_contains "$id: the mark says Gesichert ${kp_word[$k]}" "Gesichert <Link> ${kp_word[$k]}" "$ctx"
    if [ "${kp_word[$k]}" = compact ]; then
      check_contains "$id: without the tool's /compact it says Gesichert net" 'Gesichert <Link> net' "$ctx"
    fi
    kp_tx "$t" "$cmd" $((second - 1))
    expect "$id: between the mark and $second nothing more" '' "$(kp_call "$s" "$t" "$kp_root" "${env[@]}")"
  else
    kp_tx "$t" "$cmd" $((second - 1))
    expect "$id: one token below $second is silent" '' "$(kp_call "$s" "$t" "$kp_root" "${env[@]}")"
  fi
  kp_tx "$t" "$cmd" "$second"
  ctx="$(kp_call "$s" "$t" "$kp_root" "${env[@]}")"
  check_contains "$id: $second reports the limit" 'Prozent der Verdichtungsgrenze' "$ctx"
  if [ "$mark" -gt 0 ]; then
    check_contains "$id: the second notice says save again" 'erneut sichern' "$ctx"
  else
    check_contains "$id: the only notice says save first" 'zuerst SICHERN' "$ctx"
  fi
  check_contains "$id: the notice at the limit says Gesichert ${kp_word[$k]}" "Gesichert <Link> ${kp_word[$k]}" "$ctx"
  check_contains "$id: the notice at the limit names --transcript and --session" "save --transcript '$t' --session $s" "$ctx"
  if [ "${kp_word[$k]}" = compact ]; then
    check_contains "$id: a kind that compacts starts the pair check" '.claude/skills/chat-handoff/reference/pair-check.md' "$ctx"
    check_contains "$id: on its pair file" ".agent/state/$s-pairs.md" "$ctx"
  else
    check_not_contains "$id: another kind starts no pair check" 'pair-check.md' "$ctx"
  fi
  case "$p" in
    bg)
      kp_tx "$t" "$cmd" $((limit - 1))
      expect "$id: no third notice in the run" '' "$(kp_call "$s" "$t" "$kp_root" "${env[@]}")" ;;
    hl)
      local out rc
      out="$(cd "$fix" && CLAUDE_PROJECT_DIR="$fix" bash "$hooks/session-state.sh" save --transcript "$fix/$s-none.jsonl" \
        --session "$s" 2>&1)"; rc=$?
      expect "$id: a save without a kept transcript ends with 2" 2 "$rc"
      check_contains "$id: and names the transcript" "$fix/$s-none.jsonl" "$out" ;;
  esac
}

for k in controller orchestrator design research dev review; do
  for p in ia bg hl web; do kp_cell "$k" "$p"; done
done

# Where the kind comes from, past the cells: a variable that names no kind falls to the slash command; a
# plugin's slash command counts by its skill; without a readable file there is no kind and no mark.
t="$fix/kp-x1.jsonl"; kp_tx "$t" /ccweb-prompt 700000
check_contains 'kind: a variable that names no kind falls to the slash command' 'Session-Art design' \
  "$(kp_call kp-x1 "$t" "$kp_root" PLAYBOOK_SESSION_KIND=nokind)"
t="$fix/kp-x2.jsonl"; kp_tx "$t" /anthropic-skills:controller-mode 400000
check_contains 'kind: a plugin slash command counts by its skill' 'Session-Art controller' \
  "$(kp_call kp-x2 "$t" "$kp_root" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
mkdir -p "$fix/kp-broken/.agents"; printf '{"kinds": [\n' > "$fix/kp-broken/.agents/session-kinds.json"
t="$fix/kp-x3.jsonl"; kp_tx "$t" /controller-mode 400000
expect 'kind: a broken file gives no mark' '' \
  "$(kp_call kp-x3 "$t" "$fix/kp-broken" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
kp_tx "$t" /controller-mode 428400
ctx="$(kp_call kp-x3 "$t" "$fix/kp-broken" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
check_contains 'kind: a broken file still gives the notice at the limit' 'zuerst SICHERN' "$ctx"
check_contains 'kind: without a kind the notice names the call and net' \
  "save --transcript '$t' --session kp-x3" "$ctx"
check_contains 'kind: without a kind the notice says Gesichert net' 'Gesichert <Link> net' "$ctx"
t="$fix/kp-x4.jsonl"; kp_tx "$t" /controller-mode 400000
expect 'kind: without the file there is no mark' '' "$(kp_call kp-x4 "$t" "$fix/kp-none" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
# A mark in percent needs the window: where only preTokens name the limit, it stays silent.
t="$fix/kp-x5.jsonl"
{ printf '{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":840000,"postTokens":9000}}\n'
  printf '{"type":"assistant","message":{"role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":699998,"output_tokens":5}}}\n'
} > "$t"
expect 'mark: a percentage mark with only preTokens is silent' '' "$(kp_call kp-x5 "$t" "$kp_root" PLAYBOOK_SESSION_KIND=design)"
# The percentage override lowers the limit of every window source, the settings too.
mkdir -p "$fix/kp-set/.claude"; printf '{"autoCompactWindow": "100000"}\n' > "$fix/kp-set/.claude/settings.json"
t="$fix/kp-x6.jsonl"; kp_tx "$t" '' 42500
check_contains 'limit: the percentage lowers the settings window (42,500 of 50,000)' 'Prozent der Verdichtungsgrenze' \
  "$(kp_call kp-x6 "$t" "$fix/kp-set" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50)"
t="$fix/kp-x7.jsonl"; kp_tx "$t" '' 42499
expect 'limit: one token below is silent' '' "$(kp_call kp-x7 "$t" "$fix/kp-set" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50)"

# Only a slash command that `skills` maps names the kind: /model before /controller-mode does not count.
t="$fix/kp-x8.jsonl"; kp_tx "$t" /controller-mode 400000
{ js '<command-name>/model</command-name>
<command-args>opus</command-args>'; printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$REPLY"; cat "$t"; } > "$t.new"
mv "$t.new" "$t"
check_contains 'kind: a built-in command before the skill does not count' 'Session-Art controller' \
  "$(kp_call kp-x8 "$t" "$kp_root" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
# A mark in thousands ("400k").
mkdir -p "$fix/kp-k/.agents"
jq '.kinds.controller.rotateAt = "400k"' "$kp_root/.agents/session-kinds.json" > "$fix/kp-k/.agents/session-kinds.json"
t="$fix/kp-x9.jsonl"; kp_tx "$t" /controller-mode 399999
expect 'mark: 400k, one token below is silent' '' "$(kp_call kp-x9 "$t" "$fix/kp-k" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
kp_tx "$t" /controller-mode 400000
check_contains 'mark: 400k is 400,000 tokens' '400000 von 400000' \
  "$(kp_call kp-x9 "$t" "$fix/kp-k" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
# Kind and mark come back from the state of the run: no command, no variable, and still the controller's mark.
kp_keep() { # session, transcript, state line -> the hook's additionalContext, with that state
  printf '%s\n' "$3" > "$cs_gate/$1-remind-state"
  remind_event "$1" "$2" | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -u PLAYBOOK_SESSION_KIND \
    -u CLAUDE_CODE_REMOTE TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$kp_root" bash "$remind_cs" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}
t="$fix/kp-x10.jsonl"; kp_tx "$t" '' 400000
check_contains 'state: kind and mark are read back from the state of the run' 'Session-Art controller' \
  "$(kp_keep kp-x10 "$t" '0 504000 controller compact 400000')"
# The path is quoted: a transcript under a folder with a space still gives one argument.
mkdir -p "$fix/kp dir"; t="$fix/kp dir/kp-x11.jsonl"; kp_tx "$t" /controller-mode 400000
ctx="$(kp_call kp-x11 "$t" "$kp_root" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000)"
args="${ctx#*session-state.sh save }"; args="${args%% mit *}"; eval "set -- $args"
expect 'call: a path with a space stays one argument' "$t" "${2:-}"
# Without jq the kind stays unknown: no mark, only the notice at 85 percent of the limit. The PATH holds the tools
# the hook calls, each a wrapper to its own path, and no jq.
kp_nojq="$fix/kp-nojq"; mkdir -p "$kp_nojq"
for c in bash cat grep mkdir tail; do
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$c")" > "$kp_nojq/$c"; chmod +x "$kp_nojq/$c"
done
t="$fix/kp-x12.jsonl"; kp_tx "$t" /controller-mode 400000
expect 'no jq: no mark below 85 percent of the limit' '' \
  "$(kp_call kp-x12 "$t" "$kp_root" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000 PATH="$kp_nojq")"
kp_tx "$t" /controller-mode 430000
check_contains 'no jq: the notice at 85 percent of the limit stays' 'Prozent der Verdichtungsgrenze' \
  "$(kp_call kp-x12 "$t" "$kp_root" CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000 PATH="$kp_nojq")"
# The helper row: a sub-agent gets no notice at any place, and its compaction writes neither restore file nor lock;
# at web the percentage variable sets the limit of the main thread all the same.
kp_helper() { # place, NAME=value...
  local p="$1" id="T-helper-$1" s="kp-helper-$1" t="$fix/kp-helper-$1.jsonl" ctx; shift
  kp_tx "$t" /controller-mode 700000
  printf '0 0\n' > "$cs_gate/$s-remind-state"
  ctx="$(remind_event "$s" "$t" agent-h1 | env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u CLAUDE_AUTOCOMPACT_PCT_OVERRIDE \
    -u PLAYBOOK_SESSION_KIND -u CLAUDE_CODE_REMOTE TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$kp_root" "$@" bash "$remind_cs" 2>&1)"
  expect "$id: no notice in the helper" '' "$ctx"
  absent_file "$id: no run mark for the helper" "$cs_gate/$s-remind-sent"
  { cat "$t"; printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5-5","role":"assistant","content":[{"type":"tool_use","id":"toolu_h","name":"Agent","input":{"prompt":"x"}}]}}'; } > "$t.wait"
  restore_event "$s" "$t.wait" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$kp_root" "$@" bash "$restore_cs" >/dev/null 2>&1
  absent_file "$id: the helper's compaction writes no restore file" "$(cs_rfile "$s" "$kp_root")"
  absent_file "$id: the helper's compaction writes no lock" "$cs_gate/$s-compact-lock"
}
kp_helper ia CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000
kp_helper bg CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000
kp_helper hl CLAUDE_CODE_AUTO_COMPACT_WINDOW=600000
kp_helper web CLAUDE_CODE_REMOTE=true CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80
kp_tx "$fix/kp-helper-webm.jsonl" '' 680000
check_contains 'T-helper-web: the percentage variable sets the main thread limit' 'Prozent der Verdichtungsgrenze' \
  "$(kp_call kp-helper-webm "$fix/kp-helper-webm.jsonl" "$kp_root" CLAUDE_CODE_REMOTE=true CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80)"
# T-helper-ia: the helper's result is a candidate of the main thread's save.
fresh; { human 'Pruef den Export.'; agent toolu_k1 'Befund des Helfers: Spalte Reiherfeder fehlt im Export.'; } > "$fix/kp-helper-result.jsonl"
(cd "$kp_root" && TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$kp_root" bash "$hooks/session-state.sh" save \
  --transcript "$fix/kp-helper-result.jsonl" --session kp-helper-r >/dev/null 2>&1)
check_contains "T-helper-ia: the helper's result is a box of the main thread's save" 'helper: Befund des Helfers: Spalte Reiherfeder' \
  "$(cat "$kp_root/.agent/state/kp-helper-r-save.md" 2>/dev/null)"
t="$fix/kp-x13.jsonl"; kp_tx "$t" /ccweb-prompt 714000
# A compaction that goes through ends the run: each of the three files goes.
for x in sent mark state; do : > "$cs_gate/kp-x13-remind-$x"; done
save_event kp-x13 "$t" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$kp_root" bash "$save_cs" >/dev/null 2>&1
for x in sent mark state; do absent_file "compaction: removes <session>-remind-$x" "$cs_gate/kp-x13-remind-$x"; done

finish
