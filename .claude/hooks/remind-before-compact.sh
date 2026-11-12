#!/usr/bin/env bash
#
# PostToolUse hook - tells the model at most twice per run to save (session-state.sh save,
# ww3d/playbook#487): at the mark of its session kind, and when the context nears its compaction limit.
# Generic, byte-identical across consumers.
#
# The fill comes from the transcript's last message.usage (input + cache creation + cache read
# tokens). The window, in this order: CLAUDE_CODE_AUTO_COMPACT_WINDOW; else the preTokens of the last
# automatic compaction in the transcript are the limit itself; else the autoCompactWindow of the project
# settings; 1,000,000 tokens where the settings or ANTHROPIC_MODEL name a [1m] model; the bare model id of
# the transcript (a list by the vendor's model-config page: 1,000,000 for the models that run with 1M from
# the start, 200,000 for older ones). CLAUDE_CODE_DISABLE_1M_CONTEXT=1 caps every window at 200,000. With
# none of these the window is unknown (an id not on the list too) and the hook stays silent. The limit is
# CLAUDE_AUTOCOMPACT_PCT_OVERRIDE percent of the window, else 84 percent: measured, a compaction starts at
# 80-84 percent of the window; the percentage only lowers that point (the vendor's variable cannot raise
# it), so a value above 84 counts as none. The second notice comes at 85 percent of the limit.
#
# The session kind (.agents/session-kinds.json, ww3d/playbook#487 decision 11): PLAYBOOK_SESSION_KIND where
# it names a kind; else the first slash command the human typed, through "skills"; else "defaultKind". Its
# "rotateAt" is the mark of the first notice: tokens ("400000", "400k") or a percentage of the window ("70%",
# silent where only preTokens name the limit); "0" or a mark at or past 85 percent of the limit: no first
# notice. Its "atMark" picks the text. Without the file, a readable form of it or jq: no kind, no mark.
#
# A run is the stretch between two compactions. In ${TMPDIR:-/tmp}/claude-rule-gate/:
#   <session>-remind-sent   the run was reported; the rest of the run costs one file test
#   <session>-remind-mark   the mark was reported in this run
#   <session>-remind-state  "<epoch> <limit> <kind> <atMark> <mark>": at most one look every 15 seconds,
#                           limit and kind found once; a call with a payload over 4,000 characters always looks
#   <session>-remind-pend   "<fill> <characters>" per large payload since the answer with that fill
# save-compact-state.sh removes all four at every compaction. Sub-agents are left alone: their
# context is not measured.
#
# Fail-open and never a block: bash builtins plus tail, grep and awk, jq once a run for the kind; whatever goes
# wrong, no output, exit 0.
#
# Stdin:  the PostToolUse event JSON. Stdout: the additionalContext JSON, or nothing.
set -uo pipefail

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
read_hook_payload
input="$hook_input"

field() { # key -> global val, the first string value of "key" in the raw payload
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  val=""
  if [[ $input =~ $re ]]; then val="${BASH_REMATCH[1]}"; fi
}

field session_id; session="$val"
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
sent="${gate_dir}/${session}-remind-sent"
marked="${gate_dir}/${session}-remind-mark"
state="${gate_dir}/${session}-remind-state"
# The usual call of the rest of a run: reported already, nothing to say - before any scan of the payload.
[ ! -e "$sent" ] || exit 0
agent_re='"agent_id"[[:space:]]*:[[:space:]]*"[^"]'
[[ ! $input =~ $agent_re ]] || exit 0

emit() { # text without quotes or backslashes
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$1"
}
field transcript_path; transcript="${val//\\\\//}"
# SICHERN against the own carriers (ww3d/playbook#487), with this session's transcript and id, so the
# save reads this run wherever the session runs; then "Gesichert" with the next event of its atMark.
steps() { # atMark (empty: no kind), "again" for the second notice of a run -> global steps
  local report lead='zuerst SICHERN'
  [ "${2:-}" != again ] || lead='erneut sichern'
  case "$1" in
    compact) report="Gesichert <Link> compact an den Besitzer melden, wenn das Session-Werkzeug sichern geschickt hat und danach /compact ausloest; sonst Gesichert <Link> net melden und weiterarbeiten (.agents/rules/pr.md, Session Traffic; .agents/rules/controller.md, Controller Sessions)." ;;
    rotate) report="Gesichert <Link> successor an den Besitzer melden und uebergeben (.agents/rules/controller.md, Controller Sessions)." ;;
    *) report="Gesichert <Link> net an den Besitzer melden und weiterarbeiten (.agents/rules/pr.md, Session Traffic)." ;;
  esac
  local pairs=""
  # Only a kind that compacts checks its pairs: a helper on the pair file, never on the history (ww3d/playbook#487).
  [ "$1" != compact ] || pairs="; dann einen Helfer mit .claude/skills/chat-handoff/reference/pair-check.md ueber .agent/state/$session-pairs.md starten, jeden Befund veraltet oder falsch am Traeger berichtigen und save erneut laufen lassen bis Exit 0"
  steps="$lead: bash .claude/hooks/session-state.sh save --transcript '$transcript' --session $session mit --carrier <owner/repo#N> je eigenem Traeger laufen lassen; jeden offenen Kasten der Arbeitsliste an einen Traeger bringen oder als - [x] <Kasten> -> <Beleg> abhaken; wiederholen bis Exit 0$pairs; die Check-Zeile an den Traeger schreiben; dann $report"
}


# At most one look every 15 seconds: the fill and the point change slowly, and this runs after every tool call.
now=0; printf -v now '%(%s)T' -1
last=0; point=0; kind=-; at_mark=-; mark=0
if [ -r "$state" ]; then read -r last point kind at_mark mark < "$state" 2>/dev/null || true; fi
[[ $last =~ ^[0-9]+$ ]] || last=0
[[ $point =~ ^[0-9]+$ ]] || point=0
[[ $mark =~ ^[0-9]+$ ]] || mark=0
[[ $kind =~ ^[a-z]+$ ]] || kind=-
[[ $at_mark =~ ^(compact|rotate|notice)$ ]] || at_mark=-
# A large tool result can carry the fill past the limit before the next answer measures it: it always looks.
big=0; [ "${#input}" -le 4000 ] || big=1
[ $((now - 10#$last)) -ge 15 ] || [ "$big" = 1 ] || exit 0
point=$((10#$point)); mark=$((10#$mark))
{ [ -d "$gate_dir" ] || mkdir -p "$gate_dir"; } 2>/dev/null || exit 0
save_state() { printf '%s %s %s %s %s\n' "$now" "$point" "$kind" "$at_mark" "$mark" > "$state" 2>/dev/null || true; }
save_state

[ -n "$transcript" ] && [ -r "$transcript" ] || exit 0

usage_re='^"input_tokens":([0-9]+),"cache_creation_input_tokens":([0-9]+),"cache_read_input_tokens":([0-9]+)$'
usage=""
# A transcript line runs to 500 KB: the last 300 KB first, then the last 3 MB where that held no usage.
for span in 300000 3000000; do
  usage="$(tail -c "$span" "$transcript" 2>/dev/null | grep -o '"input_tokens":[0-9]*,"cache_creation_input_tokens":[0-9]*,"cache_read_input_tokens":[0-9]*\|"subtype":"compact_boundary"' | tail -n 1)" || usage=""
  # A boundary after the last usage: that fill is from before the compaction,
  # and a reading of it would spend this run's notice.
  [ "$usage" != '"subtype":"compact_boundary"' ] || exit 0
  [[ $usage =~ $usage_re ]] && break
done
[[ $usage =~ $usage_re ]] || exit 0
fill=$((10#${BASH_REMATCH[1]} + 10#${BASH_REMATCH[2]} + 10#${BASH_REMATCH[3]}))
# The large tool results since that answer are not in its fill yet: each payload's length, kept under the fill it
# came after, about 4 characters a token (ww3d/playbook#487). A new answer measures them, so its fill starts anew.
# Append only: the hooks of one parallel turn may run at once, and a rewrite would drop a sibling's line.
pend="${gate_dir}/${session}-remind-pend"
[ "$big" = 0 ] || printf '%s %s\n' "$fill" "${#input}" >> "$pend" 2>/dev/null || true
if [ -r "$pend" ]; then
  extra="$(awk -v f="$fill" '$1 == f { s += $2 } END { print int(s / 4) }' "$pend" 2>/dev/null)" || extra=0
  [[ $extra =~ ^[0-9]+$ ]] && fill=$((fill + extra))
fi

root="${CLAUDE_PROJECT_DIR:-}"
# The session kind, once a run: its name, atMark and rotateAt -> globals kind, at_mark, rotate_at.
find_kind() {
  local f="$root/.agents/session-kinds.json" cmd="" out
  [ -n "$root" ] && [ -r "$f" ] && command -v jq >/dev/null 2>&1 || return 0
  if ! jq -e --arg e "${PLAYBOOK_SESSION_KIND:-}" '.kinds[$e] | type == "object"' "$f" >/dev/null 2>&1; then
    # The first slash command the human typed that `skills` maps (/model, /effort and the like do not count);
    # a plugin's "/<plugin>:<skill>" also counts as "/<skill>".
    cmd="$(jq -nRr --slurpfile k "$f" '($k[0].skills // {}) as $s | first(inputs | fromjson? | objects
      | select(.type == "user" and .isSidechain != true and .isMeta != true) | .message.content
      | if type == "array" then [.[] | objects | select(.type == "text") | .text] | join(" ") elif type == "string" then . else "" end
      | select(test("^\\s*<command-")) | capture("<command-name>/(?<n>[^<]+)</command-name>").n
      | select($s["/" + .] != null or $s["/" + sub("^[^:]*:"; "")] != null))' "$transcript" 2>/dev/null)" || cmd=""
  fi
  # The command goes to jq without its slash: Git Bash turns an argument "/x" into a Windows path.
  out="$(jq -r --arg e "${PLAYBOOK_SESSION_KIND:-}" --arg c "${cmd%$'\r'}" '.kinds as $k | (.skills // {}) as $s
    | [$e, ($s["/" + $c] // ""), ($s["/" + ($c | sub("^[^:]*:"; ""))] // ""), (.defaultKind // "")]
    | map(select(. != "" and ($k[.] | type) == "object")) | first as $n
    | "\($n) \($k[$n].atMark) \($k[$n].rotateAt)"' "$f" 2>/dev/null)" || return 0
  read -r kind at_mark rotate_at <<< "${out%$'\r'}"
  if ! [[ $kind =~ ^[a-z]+$ && $at_mark =~ ^(compact|rotate|notice)$ ]]; then kind=-; at_mark=-; rotate_at=0; fi
}
limit_of() { # window -> global point: the percentage override where it lies in 1-84, else 84 percent
  local pct="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}"
  if [[ $pct =~ ^[0-9]+$ ]] && [ $((10#$pct)) -ge 1 ] && [ $((10#$pct)) -le 84 ]; then point=$(($1 * 10#$pct / 100)); else point=$(($1 * 84 / 100)); fi
}

# The point at which Claude Code compacts, in tokens, and the kind's mark; found once per run, kept in the state file.
if [ "$point" -le 0 ]; then
  win=0
  env_win="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
  if [[ $env_win =~ ^[0-9]+$ ]] && [ $((10#$env_win)) -gt 0 ]; then win=$((10#$env_win)); fi
  if [ "$win" -le 0 ]; then
    # An automatic compaction states the point it started at; a manual one says nothing about it.
    pre="$(grep -o '"trigger":"auto","preTokens":[0-9]*' "$transcript" 2>/dev/null | tail -n 1)" || pre=""
    pre="${pre##*:}"
    if [[ $pre =~ ^[0-9]+$ ]] && [ $((10#$pre)) -gt 0 ]; then point=$((10#$pre)); fi
  fi
  if [ "$win" -le 0 ] && [ "$point" -le 0 ]; then
    setting_re='"autoCompactWindow"[[:space:]]*:[[:space:]]*"?([0-9]+)'
    model_re='"model"[[:space:]]*:[[:space:]]*"[^"]*\[1m\]'
    for f in "$root/.claude/settings.local.json" "$root/.claude/settings.json"; do
      if [ -z "$root" ] || [ ! -r "$f" ]; then continue; fi
      body="$(<"$f")"
      if [[ $body =~ $setting_re ]] && [ $((10#${BASH_REMATCH[1]})) -gt 0 ]; then win=$((10#${BASH_REMATCH[1]})); break; fi
      if [[ $body =~ $model_re ]]; then win=1000000; break; fi
    done
    # A [1m] suffix never shows in the transcript, only in what the user chose: the environment or the settings.
    if [ "$win" -le 0 ] && [[ ${ANTHROPIC_MODEL:-} == *'[1m]'* ]]; then win=1000000; fi
    if [ "$win" -le 0 ]; then
      # The bare model id of the transcript, by the vendor's model-config page: from Fable 5 / 5.1, Sonnet 5,
      # Haiku 5.5 and Opus 4.7 on the window is 1M; the older models of these families are 200K; other ids are unknown.
      mid="$(tail -c 300000 "$transcript" 2>/dev/null | grep -o '"model":"claude-[^"]*"' | tail -n 1)" || mid=""
      mid="${mid#\"model\":\"}"
      mid="${mid%\"}"
      # anchored at the end: with an open end the minor version dropped out of the match
      id_re='^claude-(opus|sonnet|haiku|fable)-([0-9]+)(-([0-9]{1,2}))?(-[0-9]{8}|-latest)?$'
      if [[ $mid =~ $id_re ]]; then
        fam="${BASH_REMATCH[1]}"; maj=$((10#${BASH_REMATCH[2]})); min=$((10#${BASH_REMATCH[4]:-0}))
        case "$fam" in
          fable) if [ "$maj" -eq 5 ] && [ "$min" -le 1 ]; then win=1000000; fi ;;
          sonnet) if [ "$maj" -ge 5 ]; then win=1000000; elif [ "$maj" -le 4 ]; then win=200000; fi ;;
          opus) if [ "$maj" -ge 5 ] || { [ "$maj" -eq 4 ] && [ "$min" -ge 7 ]; }; then win=1000000; elif [ "$maj" -le 4 ]; then win=200000; fi ;;
          haiku) if [ "$maj" -eq 5 ] && [ "$min" -eq 5 ]; then win=1000000; elif [ "$maj" -le 4 ]; then win=200000; fi ;;
        esac
      elif [[ $mid =~ ^claude-[0-9]-[0-9]*-?(opus|sonnet|haiku) ]]; then
        win=200000
      fi
    fi
  fi
  # CLAUDE_CODE_DISABLE_1M_CONTEXT=1 holds the session at 200K, whatever a window names above it.
  if [ "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}" = 1 ] && [ "$win" -gt 200000 ]; then win=200000; fi
  if [ "$win" -gt 0 ]; then limit_of "$win"; fi
  # No source names the window: stay silent rather than warn at the wrong fill.
  [ "$point" -gt 0 ] || exit 0
  rotate_at=0
  find_kind
  case "$rotate_at" in
    *%) pct="${rotate_at%\%}"; if [[ $pct =~ ^[0-9]+$ ]]; then mark=$((win * 10#$pct / 100)); fi ;;
    *k) n="${rotate_at%k}"; if [[ $n =~ ^[0-9]+$ ]]; then mark=$((10#$n * 1000)); fi ;;
    *) if [[ $rotate_at =~ ^[0-9]+$ ]]; then mark=$((10#$rotate_at)); fi ;;
  esac
fi
save_state

[ "$at_mark" != - ] || at_mark=""
if [ $((fill * 100)) -lt $((point * 85)) ]; then
  [ "$mark" -gt 0 ] && [ "$fill" -ge "$mark" ] && [ ! -e "$marked" ] || exit 0
  : > "$marked" 2>/dev/null || exit 0
  steps "$at_mark"
  emit "Der Kontext hat die Marke der Session-Art $kind erreicht ($fill von $mark Tokens). Jetzt $steps"
  exit 0
fi
: > "$sent" 2>/dev/null || exit 0
if [ -e "$marked" ]; then steps "$at_mark" again; else steps "$at_mark"; fi
emit "Der Kontext ist bei $((fill * 100 / point)) Prozent der Verdichtungsgrenze. Jetzt $steps"
exit 0
