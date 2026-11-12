# shellcheck shell=bash
# Sourced by the compaction hooks (save-compact-state.sh, restore-compact-state.sh, read-confirm.sh), never run:
# whose compaction this is. A sub-agent that compacts fires PreCompact and SessionStart "compact" with the main
# thread's session_id and transcript_path and without agent_id (anthropics/claude-code#91910); its compaction must
# neither restore nor lock the main thread (ww3d/playbook#487, decision log
# docs/decisions/2026-10-28T1640Z-playbook-487-compact-crosscheck-decisions.md, decision 5).
#
# Signals: (1) the newest main-thread entry is a foreground Agent/Task tool_use without its result - the main
# thread waits and cannot compact itself; (2) a subagents/agent-*.jsonl beside the transcript carries a
# compact_boundary younger than 60 s; (3) the payload's model differs from the main thread's newest assistant
# model. "helper" on (1), on (2) and (3) together, or on SessionStart on (2) alone with 10 s; otherwise "main" -
# a main thread taken for a helper would
# lose its restore, so the doubtful case stays "main". Each verdict is a line in
# <gate>/<session>-compaction-owner. Needs jq for (1) and (3); without it, or on any error: "main".

# shellcheck disable=SC2016 # jq text, not shell
compaction_jq='[inputs | fromjson? | objects | select((.type == "user" or .type == "assistant") and .isSidechain != true)] as $m
  | ($m | last) as $l
  | (if ($l.type // "") == "assistant" then [$l.message.content[]? | objects
       | select(.type == "tool_use" and (.name == "Agent" or .name == "Task") and (.input.run_in_background? != true))] | length > 0
     else false end) as $wait
  | ([$m[] | select(.type == "assistant") | .message.model // empty] | last // "") as $model
  | "\($wait) \($model)"'

compaction_owner() { # session, transcript, payload model, gate folder -> global compaction_by: main|helper
  local sid="$1" t="$2" model="$3" gate="$4" wait=false main_model="" s2=0 s3=0 since f signals=""
  compaction_by=main
  if [ -r "$t" ] && command -v jq >/dev/null 2>&1; then
    read -r wait main_model <<< "$(tail -n 200 "$t" 2>/dev/null | jq -nRr "$compaction_jq" 2>/dev/null | tr -d '\r')" || true
  fi
  [ "$wait" = true ] && signals="1"
  # On SessionStart a helper's boundary already stands (0.1-0.6 s before the hook, measured 2026-11-12), the main
  # thread's only after it (3 s): there a boundary of the last 10 s is enough on its own.
  local event="" win=60
  [[ ${hook_input:-} =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"SessionStart\" ]] && { event=start; win=10; }
  if since="$(date -u -d "-$win seconds" +%Y-%m-%dT%H:%M:%S 2>/dev/null)"; then
    for f in "${t%.jsonl}"/subagents/agent-*.jsonl; do
      [ -r "$f" ] || continue
      # The newest boundary of the file; ISO timestamps compare as strings.
      local b
      b="$(tail -n 50 "$f" 2>/dev/null | grep -F '"compact_boundary"' | grep -o '"timestamp":"[^"]*"' | tail -n 1)" || b=""
      b="${b#\"timestamp\":\"}"
      [ -z "$b" ] || [[ ${b:0:19} < $since ]] || { s2=1; break; }
    done
  fi
  [ "$s2" = 1 ] && signals="$signals 2"
  [ -n "$model" ] && [ -n "$main_model" ] && [ "$model" != "$main_model" ] && { s3=1; signals="$signals 3"; }
  if [ "$wait" = true ] || { [ "$s2" = 1 ] && { [ "$s3" = 1 ] || [ "$event" = start ]; }; }; then compaction_by=helper; fi
  # The payload's shape beside the verdict: whether a helper's event names itself is measured, not assumed.
  local shape=""
  if [ -n "${hook_input:-}" ] && command -v jq >/dev/null 2>&1; then
    shape="$(printf '%s' "$hook_input" | jq -c '{event: .hook_event_name, keys: keys, agent_id, agent_type, transcript_path}' 2>/dev/null | tr -d '\r')" || shape=""
  fi
  printf '%s signals=%s %s %s\n' "$compaction_by" "${signals# }" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$shape" \
    >> "$gate/$sid-compaction-owner" 2>/dev/null || true
}
