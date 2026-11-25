#!/usr/bin/env bash
# Hook suite section: ticks.sh, the tick tool and its guard (ww3d/playbook#688)
# Run alone: bash .claude/hooks/tests/cases/ticks.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# No network and no real clock: gh is gh-double.sh over a world file, the channel a script over a JSON file, the
# clock TICKS_NOW, the session's tool call a transcript file.
# shellcheck disable=SC2016 # jq text, not shell
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

ticks="$hooks/ticks.sh"
t="$fix/ticks"; mkdir -p "$t/bin" "$t/proj"
printf '#!/usr/bin/env bash\nexec bash "%s/tests/gh-double.sh" "$@"\n' "$hooks" > "$t/bin/gh"; chmod +x "$t/bin/gh"
# The time limit: a stand-in for timeout that logs its seconds and command; with "$GH_DOUBLE_WORLD.slow" it ends a gh
# call as the limit would (exit 124), without waiting.
printf '#!/usr/bin/env bash\necho "$1 $2" >> "%s/timeout.log"\nif [ "$2" = gh ] && [ -e "$GH_DOUBLE_WORLD.slow" ]; then exit 124; fi\nshift; exec "$@"\n' \
  "$t" > "$t/bin/timeout"; chmod +x "$t/bin/timeout"
export PATH="$t/bin:$PATH" GH_DOUBLE_WORLD="$t/world.json" CLAUDE_PROJECT_DIR="$t/proj" TICKS_TRANSCRIPT="$t/transcript.jsonl"
export TICKS_NOW="2026-11-20T12:00:00Z" TICKS_TIMEOUT=5
# The channel: status qNNN from channel.json.
printf '#!/usr/bin/env bash\n[ "$1" = status ] && jq -e --arg q "$2" ".[\\$q] // empty" "%s/channel.json" || exit 1\n' "$t" > "$t/channel.sh"
export PLAYBOOK_CARRIER_TEXT_CMD="bash $t/channel.sh"

tool_call() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Bash"}]}}\n' "$1" >> "$TICKS_TRANSCRIPT"; }
comment() { # databaseId, author, createdAt, body [, lastEditedAt, editor]
  jq -nc --arg i "$1" --arg a "$2" --arg c "$3" --arg b "$4" --arg e "${5:-}" --arg ed "${6:-}" '{databaseId: ($i | tonumber), id: "C\($i)",
    url: "https://github.com/o/r/issues/1#issuecomment-\($i)", createdAt: $c, lastEditedAt: (if $e == "" then null else $e end),
    author: {login: $a}, editor: (if $ed == "" then null else {login: $ed} end), body: $b}'
}
issue() { # ref, createdAt, updatedAt, title, comments JSON array, timeline JSON array [, type]
  jq -nc --arg r "$1" --arg c "$2" --arg u "$3" --arg t "$4" --argjson cs "$5" --argjson tl "$6" --arg ty "${7:-Issue}" '{
    __typename: $ty, id: "I\($r)", url: ($r | capture("^(?<o>[^#]+)#(?<n>[0-9]+)$") | "https://github.com/\(.o)/\(if $ty == "PullRequest" then "pull" else "issues" end)/\(.n)"),
    author: {login: "alice"}, createdAt: $c, updatedAt: $u, title: $t, state: "OPEN", body: "Text des Traegers\n- [ ] Punkt",
    userContentEdits: {nodes: []}, comments: {nodes: $cs}, timelineItems: {nodes: $tl}}'
}
world_set() { jq "$1" "$GH_DOUBLE_WORLD" > "$GH_DOUBLE_WORLD.tmp" && mv "$GH_DOUBLE_WORLD.tmp" "$GH_DOUBLE_WORLD"; }

# The world: o/r#1 is the carrier, alice commented at 10:00 (the change), bot answered at 11:00 there; o/r#2 is real
# but foreign; pull request o/r#3 (11:30) referenced o/r#1 at 11:31; commit abc1234 was referenced at o/r#1 at 11:40,
# commit bad1234 at 09:00, before the change, whatever its git date says.
new_world() {
  local c1 tl1
  c1="[$(comment 100 alice 2026-11-20T10:00:00Z "Bitte X pruefen"), $(comment 101 bot 2026-11-20T11:00:00Z "X geprueft, passt")]"
  tl1='[{"__typename":"CrossReferencedEvent","id":"E1","createdAt":"2026-11-20T11:31:00Z","actor":{"login":"bot"},"source":{"__typename":"PullRequest","url":"https://github.com/o/r/pull/3"}},
        {"__typename":"ReferencedEvent","id":"E2","createdAt":"2026-11-20T11:40:00Z","actor":{"login":"bot"},"commit":{"oid":"abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},
        {"__typename":"ReferencedEvent","id":"E3","createdAt":"2026-11-20T09:00:00Z","actor":{"login":"bot"},"commit":{"oid":"bad1234bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}]'
  jq -n --argjson i1 "$(issue 'o/r#1' 2026-11-19T08:00:00Z 2026-11-20T11:40:00Z 'Traeger' "$c1" "$tl1")" \
        --argjson i2 "$(issue 'o/r#2' 2026-11-20T11:00:00Z 2026-11-20T11:00:00Z 'Fremd' '[]' '[]')" \
        --argjson i3 "$(issue 'o/r#3' 2026-11-20T11:30:00Z 2026-11-20T11:30:00Z 'Fix fuer X' '[]' '[]' PullRequest)" '{
    user: "bot", issues: {"o/r#1": $i1, "o/r#2": $i2, "o/r#3": $i3},
    commits: {"abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": {sha: "abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", commit: {message: "fix: X"}, author: {login: "bot"}, html_url: "https://github.com/o/r/commit/abc1234", pulls: []},
              "bad1234bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": {sha: "bad1234bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", commit: {message: "fix: X, rueckdatiert", author: {date: "2026-11-20T11:50:00Z"}, committer: {date: "2026-11-20T11:50:00Z"}}, author: {login: "bot"}, html_url: "https://github.com/o/r/commit/bad1234", pulls: []}},
    search: []}' > "$GH_DOUBLE_WORLD"
  rm -f "$GH_DOUBLE_WORLD.down" "$GH_DOUBLE_WORLD.calls" "$GH_DOUBLE_WORLD.patched" "$GH_DOUBLE_WORLD.down-path" "$GH_DOUBLE_WORLD.slow"
  jq -n '{q900: {status: "beantwortet", erstelltAm: "2026-11-20T10:30:00Z", issue: "o/r#1", nachrichten: [{at: "2026-11-20T11:05:00Z", von: "Mensch", text: "ja"}]},
          q901: {status: "offen", erstelltAm: "2026-11-20T10:30:00Z", issue: "o/r#2", nachrichten: []},
          q902: {status: "offen", erstelltAm: "2026-11-20T08:00:00Z", issue: "o/r#1", nachrichten: []}}' > "$t/channel.json"
}
# A list of n boxes, each on o/r#1 with alice's comment at 10:00 as its change.
new_list() { # name, n -> view path
  local v="$t/$1.md" n="$2" i boxes=()
  rm -f "$t/$1.md" "$t/$1.json"; rm -rf "$t/proj/.agent"
  for ((i = 1; i <= n; i++)); do
    boxes+=("$(jq -nc --arg i "$i" '{key: "k\($i)", title: "Kasten \($i)", carriers: ["o/r#1"], lines: ["Zeile \($i)"],
      changes: [{carrier: "o/r#1", kind: "comment", serverId: "100", at: "2026-11-20T10:00:00Z", author: "alice", first: "Bitte X pruefen"}]}')")
  done
  printf '%s\n' "${boxes[@]}" | jq -s '{title: "Testliste", boxes: .}' > "$t/$1.spec.json"
  bash "$ticks" open "$v" "$t/$1.spec.json" >/dev/null
  printf '%s' "$v"
}
close() { bash "$ticks" close "$@" 2>&1; }
guard_says() { bash "$ticks" guard < /dev/null; }
mark_of() { grep -oE "^- \[.\] $2 " "$1" | sed -E 's/^- \[(.)\].*/\1/'; } # view, box id -> mark

echo "== ticks.sh close: only evidence the server shows counts =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_A
v="$(new_list honest 6)"
out="$(close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v")"; rc=$?
expect "honest tick: own comment after the change at the carrier" "0 x" "$rc $(mark_of "$v" K1)"
if grep -qE '^- \[x\] K1 Kasten 1 -> comment o/r#1#issuecomment-101 von bot 2026-11-20T11:00:00Z: X geprueft, passt$' "$v"; then
  ok "the view shows the evidence text the tool wrote" "x"; else bad "the view shows the evidence text the tool wrote" "$(grep 'K1 ' "$v" | head -1)" "tool text"; fi
out="$(close K2 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v")"; rc=$?
expect "the same reference for a second box is refused" "1 ' '" "$rc '$(mark_of "$v" K2)'"
out="$(close K2 erledigt o/r#2 --list "$v")"; rc=$?
expect "a real but foreign issue is refused" "1" "$rc"
if has_text 'stands at no carrier' "$out"; then ok "  it says why" "no carrier"; else bad "  it says why" "$out" "no carrier"; fi
out="$(close K2 erledigt o/r#3 --list "$v")"; rc=$?
expect "a pull request that referenced the carrier after the change counts" "0 x" "$rc $(mark_of "$v" K2)"
out="$(close K3 erledigt o/r@0000000 --list "$v")"; rc=$?
expect "an invented commit is refused" "1" "$rc"
tool_call toolu_B
out="$(close K3 erledigt o/r@bad1234 --list "$v")"; rc=$?
expect "a commit referenced only before the change is refused, its git date unread" "1" "$rc"
if grep -q 'repos/o/r/commits/bad1234 ' "$GH_DOUBLE_WORLD.calls" && ! grep -q 'commit.committer\|commit.author.date' "$hooks/lib/resolve.sh"; then
  ok "  the git date is never asked for" "server events only"
else
  bad "  the git date is never asked for" "read" "unread"
fi
out="$(close K3 erledigt o/r@abc1234 --list "$v")"; rc=$?
expect "a commit referenced at the carrier after the change counts" "0 x" "$rc $(mark_of "$v" K3)"
out="$(close K4 erledigt q901 --list "$v")"; rc=$?
expect "a question of a foreign issue is refused" "1" "$rc"
out="$(close K4 erledigt q902 --list "$v")"; rc=$?
expect "a question older than the change is refused" "1" "$rc"
out="$(close K4 erledigt q900 --list "$v")"; rc=$?
expect "a question answered after the change at the carrier counts" "0 x" "$rc $(mark_of "$v" K4)"
tool_call toolu_C
out="$(close K5 gelesen K5.2 "nur eine Rueckfrage" --list "$v")"; rc=$?
expect "gelesen with ids that are not the box's changes is refused" "1" "$rc"
out="$(close K5 gelesen K5.1 "Die Rueckfrage   betrifft X, X ist erledigt" --list "$v")"; rc=$?
expect "gelesen with exactly the box's changes counts" "0 x" "$rc $(mark_of "$v" K5)"
out="$(close K6 gelesen K6.1 "Die Rueckfrage betrifft X, X ist erledigt" --list "$v")"; rc=$?
expect "the same gelesen sentence (whitespace aside) in a second box is refused" "1" "$rc"
out="$(close K6 ungeprueft "Traeger ist privat" --list "$v")"; rc=$?
expect "ungeprueft closes with its reason" "0 u" "$rc $(mark_of "$v" K6)"
if grep -qE '^- \[u\] K6 Kasten 6 -> ungeprueft: Traeger ist privat$' "$v"; then ok "  the view shows [u] with the reason" "u"; else bad "  the view shows [u] with the reason" "$(grep 'K6 ' "$v")" "[u]"; fi
expect "every box closed: the guard lets the turn end, ungeprueft included" "" "$(guard_says)"
if [ -z "$(ls -A "$t/proj/.agent/state/ticks/open" 2>/dev/null)" ]; then ok "  the list is no longer registered" "dropped"; else bad "  the list is no longer registered" "registered" "dropped"; fi

echo "== at most three closings per tool call, none without the transcript =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_D
v="$(new_list four 4)"
for k in K1 K2 K3; do close "$k" ungeprueft "Grund $k" --list "$v" >/dev/null; done
out="$(close K4 ungeprueft "Grund K4" --list "$v")"; rc=$?
expect "the fourth closing in one tool call is refused" "1 ' '" "$rc '$(mark_of "$v" K4)'"
if has_text 'at most three' "$out"; then ok "  it says at most three per call" "said"; else bad "  it says at most three per call" "$out" "said"; fi
tool_call toolu_E
out="$(close K4 ungeprueft "Grund K4" --list "$v")"; rc=$?
expect "the next tool call may close it" "0" "$rc"
v="$(new_list notranscript 1)"
out="$(TICKS_TRANSCRIPT="$t/none.jsonl" bash "$ticks" close K1 ungeprueft "Grund" --list "$v" 2>&1)"; rc=$?
expect "without a readable transcript nothing closes" "1 ' '" "$rc '$(mark_of "$v" K1)'"

# Helpers share the session id: each counts its own three, from its own transcript under <sid>/subagents/; the call is
# the newest tool_use whose command closes the box (ww3d/playbook#734).
hp="$t/cfg/projects/p"; mkdir -p "$hp/sid-h/subagents"
helper_call() { # file, tool_use id, box ids -> a Bash call whose command closes those boxes
  jq -nc --arg id "$2" --arg c "$(printf 'bash .claude/hooks/ticks.sh close %s ungeprueft Grund; ' "${@:3}")" \
    '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Bash", input: {command: $c}}]}}' >> "$1"
}
: > "$hp/sid-h/subagents/agent-a.jsonl"; : > "$hp/sid-h/subagents/agent-b.jsonl"
helper_call "$hp/sid-h/subagents/agent-a.jsonl" toolu_HA K1 K2 K3 K7
helper_call "$hp/sid-h/subagents/agent-b.jsonl" toolu_HB K4 K5 K6 K8
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_HM","name":"Agent","input":{}}]}}\n' > "$hp/sid-h.jsonl"
v="$(new_list helpers 8)"
hclose() { TICKS_TRANSCRIPT='' CLAUDE_CONFIG_DIR="$t/cfg" CLAUDE_CODE_SESSION_ID=sid-h bash "$ticks" close "$1" ungeprueft "Grund $1" --list "$v" 2>&1; }
n=0; for k in K1 K2 K3 K4 K5 K6; do hclose "$k" >/dev/null && n=$((n + 1)); done
expect "two helpers: three closings each are taken" 6 "$n"
expect "  each journal entry names the helper's own call" "toolu_HA toolu_HA toolu_HA toolu_HB toolu_HB toolu_HB" \
  "$(jq -r '[.journal[].toolUse // empty] | join(" ")' "${v%.md}.json" | tr -d '\r')"
out="$(hclose K7)"; rc=$?
expect "two helpers: the fourth of the first helper is refused" "1 ' '" "$rc '$(mark_of "$v" K7)'"
out="$(hclose K8)"; rc=$?
expect "two helpers: the fourth of the second helper is refused" "1 ' '" "$rc '$(mark_of "$v" K8)'"
# The session writes on while a helper runs, and closed the same box earlier: its answered call is not the running one.
v="$(new_list helpers-late 1)"
jq -nc '{type: "assistant", timestamp: "2026-11-25T15:00:00Z", message: {content: [{type: "tool_use", id: "toolu_HC", name: "Bash",
  input: {command: "bash .claude/hooks/ticks.sh close K1 ungeprueft Grund"}}]}}' > "$hp/sid-h/subagents/agent-c.jsonl"
jq -nc '{type: "assistant", timestamp: "2026-11-25T14:00:00Z", message: {content: [{type: "tool_use", id: "toolu_PO", name: "Bash",
  input: {command: "bash .claude/hooks/ticks.sh close K1 ungeprueft Grund"}}]}}' >> "$hp/sid-h.jsonl"
jq -nc '{type: "user", timestamp: "2026-11-25T14:00:01Z", message: {content: [{type: "tool_result", tool_use_id: "toolu_PO", content: "K1 ungeprueft"}]}}' \
  >> "$hp/sid-h.jsonl"
touch -d '+1 minute' "$hp/sid-h.jsonl" 2>/dev/null || touch "$hp/sid-h.jsonl"
out="$(hclose K1)"; rc=$?
expect "a newer session transcript with an answered close of the same box: the helper's running call counts" "0 toolu_HC" \
  "$rc $(jq -r '[.journal[].toolUse // empty] | last' "${v%.md}.json" | tr -d '\r')"

echo "== the guard: open boxes and hand ticks warn in one line, they never hold (ww3d/playbook#734) =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_F
v="$(new_list guard 10)"
out="$(guard_says)"
expect "an open list only warns" "null" "$(printf '%s' "$out" | jq -r .decision | tr -d '\r')"
if has_text "10 offene Punkte in" "$out" && has_text "${v##*/}" "$out" && ! has_text 'Kasten 1' "$out"; then
  ok "  one line with the count and the path, no box text" "line"
else
  bad "  one line with the count and the path, no box text" "$out" "line"
fi
if has_text 'schliessen mit bash .claude/hooks/ticks.sh close' "$out"; then ok "  it names the next command" "close"; else bad "  it names the next command" "$out" "close"; fi
sed -i 's/^- \[ \] K1 /- [x] K1 /' "$v"
out="$(guard_says)"
if has_text '10 offene Punkte' "$out"; then ok "a tick by hand counts as open" "open"; else bad "a tick by hand counts as open" "$out" "open"; fi
printf '%s\n' '- [x] K99 erfunden' >> "$v"
out="$(guard_says)"
if has_text '11 offene Punkte' "$out"; then ok "a box the side list does not know is open" "open"; else bad "a box the side list does not know is open" "$out" "open"; fi
# require-receipt.sh carries the warning on the first stop of a turn only, and never holds.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"x"}}' > "$t/stop.jsonl"
for active in false true; do
  out="$(jq -nc --arg p "$t/stop.jsonl" --argjson a "$active" '{transcript_path: $p, stop_hook_active: $a, session_id: "ticks-t", hook_event_name: "Stop"}' \
    | CLAUDE_PROJECT_DIR="$t/proj" bash "$stop" 2>/dev/null)"
  said=no; has_text '11 offene Punkte' "$out" && said=yes
  dec="$(printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null | tr -d '\r')"
  expect "require-receipt.sh never holds the turn end (stop_hook_active $active)" "none $([ "$active" = false ] && echo yes || echo no)" \
    "${dec:-none} $said"
done
# The next turn end with the same count says nothing; a count that rises or falls warns again.
stop_once() { jq -nc --arg p "$t/stop.jsonl" '{transcript_path: $p, stop_hook_active: false, session_id: "ticks-t", hook_event_name: "Stop"}' \
  | CLAUDE_PROJECT_DIR="$t/proj" bash "$stop" 2>/dev/null; }
out="$(stop_once)"
expect "the same count at the next turn end: no output" "" "$out"
printf '%s\n' '- [x] K98 erfunden' >> "$v"
out="$(stop_once)"
said=no; has_text '12 offene Punkte' "$out" && said=yes
expect "a count that rises warns again" "yes" "$said"
msg="$(printf '%s' "$out" | jq -r .systemMessage | tr -d '\r')"
expect "  in one line of at most 200 characters" "1 yes" "$(printf '%s\n' "$msg" | grep -c .) $([ "${#msg}" -le 200 ] && echo yes || echo no)"
sed -i '/K98 erfunden/d' "$v"
out="$(stop_once)"
said=no; has_text '11 offene Punkte' "$out" && said=yes
expect "a count that falls warns again" "yes" "$said"
rm -rf "$t/proj/.agent"
out="$(jq -nc --arg p "$t/stop.jsonl" '{transcript_path: $p, stop_hook_active: false, session_id: "ticks-t", hook_event_name: "Stop"}' \
  | CLAUDE_PROJECT_DIR="$t/proj" bash "$stop" 2>/dev/null)"
if has_text 'offene Punkte' "$out"; then
  bad "without a registered list require-receipt.sh says nothing of ticks" "$out" "silent"
else
  ok "without a registered list require-receipt.sh says nothing of ticks" "silent"
fi

echo "== no network: the box becomes [u] nicht pruefbar, never [x] =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_G
v="$(new_list down 2)"; touch "$GH_DOUBLE_WORLD.down"
out="$(close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v")"; rc=$?
expect "forge unreachable: exit 3 and [u]" "3 u" "$rc $(mark_of "$v" K1)"
if grep -qE '^- \[u\] K1 Kasten 1 -> nicht pruefbar: ' "$v"; then ok "  the view says nicht pruefbar with the reason" "u"; else bad "  the view says nicht pruefbar with the reason" "$(grep 'K1 ' "$v")" "u"; fi
out="$(PLAYBOOK_CARRIER_TEXT_CMD="" bash "$ticks" close K2 erledigt q900 --list "$v" 2>&1)"; rc=$?
expect "no channel for a question: [u], never [x]" "3 u" "$rc $(mark_of "$v" K2)"

echo "== changes: what counts and what does not =="
new_world
. "$hooks/lib/resolve.sh"
resolve_snapshot "" "o/r#1" > "$t/s0.json"
expect "first sight of a carrier is no change" "0" "$(resolve_changes "$t/s0.json" "$t/s0.json" '[]' | jq '.["o/r#1"] | length' | tr -d '\r')"
world_set '.issues["o/r#1"].comments.nodes += [{databaseId: 102, id: "C102", url: "u", createdAt: "2026-11-20T12:30:00Z", lastEditedAt: null, author: {login: "bot"}, editor: null, body: "Beleg"}]
  | .issues["o/r#1"].updatedAt = "2026-11-20T12:30:00Z"'
resolve_snapshot "$t/s0.json" "o/r#1" > "$t/s1.json"
expect "a new comment is one change" "comment" "$(resolve_changes "$t/s0.json" "$t/s1.json" '[]' | jq -r '[.["o/r#1"][].kind] | join(",")' | tr -d '\r')"
expect "own evidence is no change" "0" "$(resolve_changes "$t/s0.json" "$t/s1.json" '["102"]' | jq '.["o/r#1"] | length' | tr -d '\r')"
world_set '.issues["o/r#1"].comments.nodes[0].body = "Bitte  X\n pruefen" | .issues["o/r#1"].comments.nodes[0].lastEditedAt = "2026-11-20T12:40:00Z"
  | .issues["o/r#1"].body = "Text des Traegers\n- [x] Punkt" | .issues["o/r#1"].userContentEdits.nodes = [{editedAt: "2026-11-20T12:41:00Z", editor: {login: "alice"}}]
  | .issues["o/r#1"].timelineItems.nodes += [{__typename: "LabeledEvent", id: "E9", createdAt: "2026-11-20T12:42:00Z", actor: {login: "alice"}}]
  | .issues["o/r#1"].updatedAt = "2026-11-20T12:42:00Z"'
resolve_snapshot "$t/s1.json" "o/r#1" > "$t/s2.json"
expect "whitespace, a switched tick box and a label make no change" "0" "$(resolve_changes "$t/s1.json" "$t/s2.json" '[]' | jq '.["o/r#1"] | length' | tr -d '\r')"
world_set '.issues["o/r#1"].updatedAt = "2026-11-20T13:00:00Z"'
resolve_snapshot "$t/s2.json" "o/r#1" > "$t/s3.json"
expect "updatedAt moved without a detail is one change without detail" "without detail" "$(resolve_changes "$t/s2.json" "$t/s3.json" '[]' | jq -r '[.["o/r#1"][].kind] | join(",")' | tr -d '\r')"
world_set '.issues["o/r#1"].comments.nodes |= map(select(.databaseId != 100)) | .issues["o/r#1"].updatedAt = "2026-11-20T13:10:00Z"'
resolve_snapshot "$t/s3.json" "o/r#1" > "$t/s4.json"
expect "a comment seen before and gone now is deleted" "deleted" "$(resolve_changes "$t/s3.json" "$t/s4.json" '[]' | jq -r '[.["o/r#1"][].kind] | join(",")' | tr -d '\r')"
touch "$GH_DOUBLE_WORLD.down"; resolve_snapshot "$t/s4.json" "o/r#1" > "$t/s5.json"; rm -f "$GH_DOUBLE_WORLD.down"
if has_text 'not reachable' "$(jq -r '.["o/r#1"].error' "$t/s5.json")"; then ok "an unreachable forge gives an error, never a stand" "error"; else bad "an unreachable forge gives an error, never a stand" "$(cat "$t/s5.json")" "error"; fi

echo "== check: evidence edited or deleted after the tick, the own account at foreign comments =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_H
v="$(new_list check 2)"
close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v" >/dev/null
close K2 erledigt o/r#3 --list "$v" >/dev/null
bash "$ticks" check "$v" >/dev/null; rc=$?
expect "nothing moved: check finds every box closed" "0 x x" "$rc $(mark_of "$v" K1) $(mark_of "$v" K2)"
world_set '.issues["o/r#1"].comments.nodes |= map(if .databaseId == 101 then .lastEditedAt = "2026-11-20T12:30:00Z" else . end)'
TICKS_NOW="2026-11-20T13:00:00Z" bash "$ticks" check "$v" >/dev/null; rc=$?
expect "evidence edited after the tick reopens its box" "1 ' '" "$rc '$(mark_of "$v" K1)'"
if grep -q 'Beleg nach dem Haken geaendert' "$v"; then ok "  and says so" "said"; else bad "  and says so" "$(grep -A3 'K1 ' "$v")" "said"; fi
world_set 'del(.issues["o/r#3"])'
TICKS_NOW="2026-11-20T13:00:00Z" bash "$ticks" check "$v" >/dev/null
expect "evidence deleted reopens its box" "' '" "'$(mark_of "$v" K2)'"
if grep -q 'Beleg geloescht' "$v"; then ok "  and says so" "said"; else bad "  and says so" "$(grep -A3 'K2 ' "$v")" "said"; fi
new_world; v="$(new_list foreign 1)"; tool_call toolu_I
close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v" >/dev/null
world_set '.issues["o/r#1"].comments.nodes |= map(if .databaseId == 100 then .lastEditedAt = "2026-11-20T12:30:00Z" | .editor = {login: "bot"} else . end)'
TICKS_NOW="2026-11-20T13:00:00Z" bash "$ticks" check "$v" >/dev/null
expect "the own account edited a foreign comment at a carrier: the box reopens" "' '" "'$(mark_of "$v" K1)'"
if grep -q 'foreign comment edited by bot: o/r#1 100 of alice' "$v"; then ok "  the line for the human names it" "named"; else bad "  the line for the human names it" "$(cat "$v")" "named"; fi

echo "== one server object, one box; the evidence text from the server =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_J
v="$(new_list ident 3)"
close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v" >/dev/null
out="$(close K2 erledigt https://github.com/o/r/issues/2#issuecomment-101 --list "$v")"; rc=$?
expect "the same comment under another issue number closes no second box" "1 ' '" "$rc '$(mark_of "$v" K2)'"
out="$(close K3 erledigt https://github.com/o/r/pull/77#issuecomment-101 --list "$v")"; rc=$?
expect "nor under a pull request URL" "1 ' '" "$rc '$(mark_of "$v" K3)'"
tool_call toolu_K
close K2 erledigt o/r@abc1234 --list "$v" >/dev/null
out="$(close K3 erledigt o/r@abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --list "$v")"; rc=$?
expect "the long sha of a commit that closed a box already closes no second" "1 ' '" "$rc '$(mark_of "$v" K3)'"
if grep -qE '^- \[x\] K2 .*abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$v"; then ok "  the view names the commit by its full sha" "full"
else bad "  the view names the commit by its full sha" "$(grep 'K2 ' "$v")" "full"; fi
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_J2
v="$(new_list ident2 1)"
close K1 erledigt https://github.com/o/r/pull/9#issuecomment-101 --list "$v" >/dev/null
if grep -qE '^- \[x\] K1 Kasten 1 -> comment o/r#1#issuecomment-101 ' "$v"; then ok "the evidence text names the comment's issue as the server gives it" "o/r#1"
else bad "the evidence text names the comment's issue as the server gives it" "$(grep 'K1 ' "$v")" "o/r#1"; fi

echo "== time checks: evidence, journal, cross-reference, git date; the limit on every forge call =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_L; : > "$t/timeout.log"
v="$(new_list times 3)"
out="$(close K1 erledigt https://github.com/o/r/issues/1#issuecomment-100 --list "$v")"; rc=$?
expect "evidence as old as the change is refused" "1" "$rc"
world_set '.issues["o/r#4"] = (.issues["o/r#3"] | .id = "Io/r#4" | .url = "https://github.com/o/r/pull/4")
  | .issues["o/r#1"].timelineItems.nodes += [{__typename: "CrossReferencedEvent", id: "E4", createdAt: "2026-11-20T09:59:00Z",
      actor: {login: "bot"}, source: {__typename: "PullRequest", url: "https://github.com/o/r/pull/4"}}]'
out="$(close K1 erledigt o/r#4 --list "$v")"; rc=$?
expect "a pull request that referenced the carrier only before the change is refused" "1" "$rc"
if grep -q '^5 gh$' "$t/timeout.log" && ! grep -v '^5 gh$' "$t/timeout.log" | grep -q ' gh$'; then
  ok "every forge call runs under the limit of TICKS_TIMEOUT" "timeout 5 gh"
else bad "every forge call runs under the limit of TICKS_TIMEOUT" "$(sort -u "$t/timeout.log" | tr '\n' ' ')" "timeout 5 gh"; fi
touch "$GH_DOUBLE_WORLD.slow"
out="$(close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v")"; rc=$?
rm -f "$GH_DOUBLE_WORLD.slow"
expect "a call past the limit sets [u], never [x]" "3 u" "$rc $(mark_of "$v" K1)"
if has_text 'no answer within 5 s' "$(grep 'K1 ' "$v")"; then ok "  and names the limit" "5 s"; else bad "  and names the limit" "$(grep 'K1 ' "$v")" "5 s"; fi
# shellcheck source=SCRIPTDIR/../../lib/ticks.sh
. "$hooks/lib/ticks.sh"
jq '.journal += [{seq: 99, box: "K2", how: "done", evidence: {ok: true, at: "2026-11-20T09:00:00Z"}, at: "2026-11-20T09:00:00Z", text: "von Hand"}]' \
  "${v%.md}.json" > "$t/j.json"
expect "a journal entry whose evidence is older than the change does not close its box" "open" \
  "$(jq -r "$ticks_state_jq"' with_state | .boxes[] | select(.id == "K2") | .state' "$t/j.json" | tr -d '\r')"
out="$(close K3 erledigt o/r@bad1234 --list "$v")"; rc=$?
expect "a commit with a git date after the change, referenced only before it, stays refused" "1" "$rc"

echo "== check without network, and after it =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_M
v="$(new_list offline 1)"
close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v" >/dev/null
touch "$GH_DOUBLE_WORLD.down"; out="$(bash "$ticks" check "$v" 2>&1)"; rc=$?; rm -f "$GH_DOUBLE_WORLD.down"
expect "check with the forge down: exit 3 and [u], never [x]" "3 u" "$rc $(mark_of "$v" K1)"
bash "$ticks" check "$v" >/dev/null; rc=$?
expect "the next check that reaches the evidence restores the tick" "0 x" "$rc $(mark_of "$v" K1)"

echo "== the own account edits a foreign comment twice =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_N
v="$(new_list twice 1)"
close K1 erledigt https://github.com/o/r/issues/1#issuecomment-101 --list "$v" >/dev/null
world_set '.issues["o/r#1"].comments.nodes |= map(if .databaseId == 100 then .lastEditedAt = "2026-11-20T12:30:00Z" | .editor = {login: "bot"} else . end)'
TICKS_NOW="2026-11-20T13:00:00Z" bash "$ticks" check "$v" >/dev/null
tool_call toolu_O
TICKS_NOW="2026-11-20T13:05:00Z" bash "$ticks" close K1 ungeprueft "Bearbeitung von Hand geprueft" --list "$v" >/dev/null 2>&1
expect "  closed again after the first edit" "u" "$(mark_of "$v" K1)"
world_set '.issues["o/r#1"].comments.nodes |= map(if .databaseId == 100 then .lastEditedAt = "2026-11-20T13:30:00Z" else . end)'
TICKS_NOW="2026-11-20T14:00:00Z" bash "$ticks" check "$v" >/dev/null; rc=$?
expect "a second edit of the same foreign comment reopens the box again" "1 ' '" "$rc '$(mark_of "$v" K1)'"

echo "== own pull request and own commit at a carrier are no change; real edits are =="
new_world
resolve_snapshot "" "o/r#1" > "$t/o0.json"
world_set '.issues["o/r#1"].timelineItems.nodes += [
    {__typename: "CrossReferencedEvent", id: "E20", createdAt: "2026-11-20T12:10:00Z", actor: {login: "bot"}, source: {__typename: "PullRequest", url: "https://github.com/o/r/pull/3"}},
    {__typename: "ReferencedEvent", id: "E21", createdAt: "2026-11-20T12:11:00Z", actor: {login: "bot"}, commit: {oid: "abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}]
  | .issues["o/r#1"].updatedAt = "2026-11-20T12:11:00Z"'
resolve_snapshot "$t/o0.json" "o/r#1" > "$t/o1.json"
expect "foreign: both events are changes" "2" "$(resolve_changes "$t/o0.json" "$t/o1.json" '[]' | jq '.["o/r#1"] | length' | tr -d '\r')"
expect "own pull request and own commit: none" "0" \
  "$(resolve_changes "$t/o0.json" "$t/o1.json" '["o/r#3", "abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]' | jq '.["o/r#1"] | length' | tr -d '\r')"
world_set '.issues["o/r#1"].body = "Ganz anderer Text"
  | .issues["o/r#1"].comments.nodes |= map(if .databaseId == 101 then .body = "Neue Aussage" | .lastEditedAt = "2026-11-20T12:20:00Z" else . end)
  | .issues["o/r#1"].userContentEdits.nodes = [{editedAt: "2026-11-20T12:21:00Z", editor: {login: "alice"}}] | .issues["o/r#1"].updatedAt = "2026-11-20T12:21:00Z"'
resolve_snapshot "$t/o1.json" "o/r#1" > "$t/o2.json"
expect "a real edit of text and comment is a change each" "comment edited,text edited" \
  "$(resolve_changes "$t/o1.json" "$t/o2.json" '[]' | jq -r '[.["o/r#1"][].kind] | sort | join(",")' | tr -d '\r')"

echo "== a time with offset, an empty sentence, the pull request of a commit not reachable =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_P
jq '.q903 = {status: "offen", erstelltAm: "2026-11-20T10:30:00+01:00", issue: "o/r#1", nachrichten: []}' "$t/channel.json" > "$t/c.json" && mv "$t/c.json" "$t/channel.json"
v="$(new_list misc 3)"
out="$(close K1 erledigt q903 --list "$v")"; rc=$?
expect "a question created 10:30+01:00 is older than the change at 10:00Z" "1" "$rc"
out="$(close K1 gelesen K1.1 "" --list "$v")"; rc=$?
expect "gelesen without a sentence is a usage error" "2" "$rc"
out="$(close K1 ungeprueft "  " --list "$v")"; rc=$?
expect "ungeprueft without a reason is a usage error" "2" "$rc"
world_set '.commits["abc1234aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].pulls = [5] | .issues["o/r#1"].timelineItems.nodes |= map(select(.id != "E2"))'
echo "issues/5" > "$GH_DOUBLE_WORLD.down-path"
out="$(close K2 erledigt o/r@abc1234 --list "$v")"; rc=$?
rm -f "$GH_DOUBLE_WORLD.down-path"
expect "the pull request of a commit not reachable: [u], not refused" "3 u" "$rc $(mark_of "$v" K2)"

echo "== closings at the same time lose none =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_Q
v="$(new_list parallel 3)"
for k in K1 K2 K3; do close "$k" ungeprueft "Grund $k" --list "$v" >/dev/null & done; wait
expect "three closings at once: three journal entries, three [u]" "3 u u u" \
  "$(jq '.journal | length' "${v%.md}.json" | tr -d '\r') $(mark_of "$v" K1) $(mark_of "$v" K2) $(mark_of "$v" K3)"

echo "== registration: any path, any folder, a lost side list =="
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_R
rm -rf "$t/proj/.agent"; mkdir -p "$t/proj/.agent/state" "$t/sub"
jq -n '{title: "x", boxes: [{key: "a", title: "A", carriers: ["o/r#1"], changes: []}]}' > "$t/dot.spec.json"
(cd "$t/proj" && bash "$ticks" open .agent/state/x.md "$t/dot.spec.json" >/dev/null)
out="$(cd "$t/sub" && guard_says)"
if has_text '1 offene Punkte in' "$out" && has_text '/x.md' "$out"; then ok "a list under a dot folder, opened by a relative path, warns from another folder" "warned"
else bad "a list under a dot folder, opened by a relative path, warns from another folder" "$out" "warned"; fi
mkdir -p "$t/proj/.agent/state/ticks/open/0dir"
out="$(jq -nc --arg p "$t/stop.jsonl" '{transcript_path: $p, stop_hook_active: false, session_id: "ticks-t", hook_event_name: "Stop"}' \
  | CLAUDE_PROJECT_DIR="$t/proj" bash "$stop" 2>/dev/null)"
if has_text 'offene Punkte' "$out"; then ok "a folder in the registry does not hide the lists beside it" "warned"; else bad "a folder in the registry does not hide the lists beside it" "$out" "warned"; fi
rm -rf "$t/proj/.agent/state/ticks/open/0dir" "$t/proj/.agent/state/x.json"
out="$(guard_says)"
if has_text '1 offene Punkte in' "$out"; then ok "a registered list without its side list still warns" "warned"; else bad "a registered list without its side list still warns" "$out" "warned"; fi

echo "== after a compaction the unread restore and its open box warn together, nothing holds =="
printf '%s\n' '{"type":"user","message":{"role":"user","content":"x"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"x"}]}}' > "$t/stop2.jsonl"
rv="$t/proj/.agent/state/ticks-t-restore.md"
printf '# Restore\n\n## History without a carrier\n\n- [ ] L1 2026-11-20T1000Z promise: Ich baue den Zaehler neu.\n' > "$t/restore.in"
# The arguments expand in the inner shell; a shell of its own keeps shellcheck out of the library.
# shellcheck disable=SC2016
bash -c '. "$1/lib/state.sh" && state_restore_list "$2" "$3"' _ "$hooks" "$t/restore.in" "$rv"
printf 'need=compact.restore %s\n' "$rv" > "$cs_gate/ticks-t-compact-lock"
stop_out() { jq -nc --arg p "$t/stop2.jsonl" --argjson a false '{transcript_path: $p, stop_hook_active: $a, session_id: "ticks-t", hook_event_name: "Stop"}' \
  | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$t/proj" bash "$stop" 2>/dev/null; }
out="$(stop_out)"
if [ "$(printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null | tr -d '\r')" = none ] && has_text 'Nach der Verdichtung ungelesen' "$out" \
   && has_text '1 offene Punkte in' "$out"; then
  ok "restore unread: one message with both warnings, no block" "warned"; else bad "restore unread: one message with both warnings, no block" "$out" "warned"; fi
rm -f "$cs_gate/ticks-t-compact-lock"
rm -f "$cs_gate/ticks-t-ticks-warned" # same count as the last warning; a fresh memory shows the list still counts it
out="$(stop_out)"
if has_text '1 offene Punkte in' "$out" && ! has_text 'Nach der Verdichtung ungelesen' "$out"; then
  ok "restore read: its open box still warns through the list" "list"; else bad "restore read: its open box still warns through the list" "$out" "list"; fi

echo "== a box without a carrier: the reference must hold its core =="
# The save list and the restore file (ww3d/playbook#688, PR 2): a box with rule core closes only by a reference
# whose text holds the core; a comment, commit or question also needs server time after the box.
core_list() { # name, gate -> view path; K1 and K2 with their own core, made at 10:30
  local v="$t/$1.md"
  rm -f "$v" "${v%.md}.json"; rm -rf "$t/proj/.agent"
  jq -n --arg g "$2" '{title: "Kernliste", gate: $g, boxes: [
    {key: "a", title: "L1 promise: Ich baue den Zaehler fuer die Liste neu", rule: "core", core: "Ich baue den Zaehler fuer die Liste neu", at: "2026-11-20T10:30:00Z", kind: "promise"},
    {key: "b", title: "L2 human: Bitte den Lauf vor dem Merge wiederholen", rule: "core", core: "Bitte den Lauf vor dem Merge wiederholen", at: "2026-11-20T10:30:00Z", kind: "human"}]}' > "$t/$1.spec.json"
  bash "$ticks" open "$v" "$t/$1.spec.json" >/dev/null
  printf '%s' "$v"
}
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_C
v="$(core_list core warn)"
out="$(close K1 erledigt o/r#2 --list "$v")"; rc=$?
expect "core: a reference without the core is refused" "1 ' '" "$rc '$(mark_of "$v" K1)'"
if has_text 'the core of K1 is not in' "$out"; then ok "  it names the missing core" "core"; else bad "  it names the missing core" "$out" "core"; fi
world_set '.issues["o/r#2"].comments.nodes += [{databaseId: 300, id: "C300", url: "https://github.com/o/r/issues/2#issuecomment-300",
  createdAt: "2026-11-20T11:00:00Z", author: {login: "bot"}, body: "Offen: Ich baue den Zaehler fuer die Liste neu, morgen. Bitte den Lauf vor dem Merge wiederholen."}]'
out="$(close K1 erledigt o/r#2 --list "$v")"; rc=$?
expect "core: an issue whose comment holds the core closes the box" "0 x" "$rc $(mark_of "$v" K1)"
tool_call toolu_C2; out="$(close K2 erledigt o/r#2 --list "$v")"; rc=$?
expect "core: the same issue closes a second box with its own core" "0 x" "$rc $(mark_of "$v" K2)"
# A core of 200 KB is too long for a command argument: it is still compared, and a foreign reference stays refused.
big="$(printf 'wort%05d ' $(seq 1 20000))"
rm -f "$t/bigcore.md" "$t/bigcore.json"
printf '%s' "$big" | jq -Rs '{title: "Grosser Kern", boxes: [{key: "a", title: "L1 human: grosser Kern", rule: "core", core: .,
  at: "2026-11-20T10:30:00Z", kind: "human"}]}' > "$t/bigcore.spec.json"
bash "$ticks" open "$t/bigcore.md" "$t/bigcore.spec.json" >/dev/null
tool_call toolu_C9; out="$(close K1 erledigt o/r#2 --list "$t/bigcore.md")"; rc=$?
expect "core of 200 KB: a reference without it is refused, never taken" "1 ' '" "$rc '$(mark_of "$t/bigcore.md" K1)'"
v="$(core_list core-c warn)"; tool_call toolu_D
world_set '.issues["o/r#2"].comments.nodes += [{databaseId: 301, id: "C301", url: "https://github.com/o/r/issues/2#issuecomment-301",
  createdAt: "2026-11-20T09:00:00Z", author: {login: "bot"}, body: "Ich baue den Zaehler fuer die Liste neu."}]'
out="$(close K1 erledigt https://github.com/o/r/issues/2#issuecomment-301 --list "$v")"; rc=$?
expect "core: a comment older than the box is refused, though it holds the core" "1" "$rc"
out="$(close K1 erledigt https://github.com/o/r/issues/2#issuecomment-300 --list "$v")"; rc=$?
expect "core: a comment after the box that holds the core closes it" "0 x" "$rc $(mark_of "$v" K1)"
# The comments of an issue go to jq on stdin: as an argument, over 32 KB of them broke the close under Windows
# (over 128 KB under Linux).
v="$(core_list core-big warn)"; tool_call toolu_E
world_set '.issues["o/r#2"].comments.nodes += [{databaseId: 302, id: "C302", url: "https://github.com/o/r/issues/2#issuecomment-302",
  createdAt: "2026-11-20T11:00:00Z", author: {login: "bot"}, body: ("y" * 140000)}]'
out="$(close K1 erledigt o/r#2 --list "$v")"; rc=$?
expect "core: an issue with over 128 KB of comments is still read, the core found" "0 x" "$rc $(mark_of "$v" K1)"
v="$(core_list core-r warn)"; tool_call toolu_F
out="$(close K1 erledigt o/r@abc1234 --list "$v")"; rc=$?
expect "core: a commit without a pull request after the box is refused" "1 ' '" "$rc '$(mark_of "$v" K1)'"
if has_text 'no pull request of it was opened after the box at 2026-11-20T10:30:00Z' "$out"; then ok "  it says why" "no pull request"; else bad "  it says why" "$out" "no pull request"; fi
out="$(close K1 erledigt q902 --list "$v")"; rc=$?
expect "core: a question made before the box and without a message since is refused" "1 ' '" "$rc '$(mark_of "$v" K1)'"
if has_text 'q902: neither created nor a message after the box at 2026-11-20T10:30:00Z' "$out"; then ok "  it says why" "neither"; else bad "  it says why" "$out" "neither"; fi

echo "== a stand box of the restore file closes where the stand check no longer finds it =="
# q1889 a, point 1: the carrier's open box "PR o/r#3 laeuft noch" against the merged pull request o/r#3; the fix
# removes the very line a core would need, so the box closes at a carrier of the last save once the check is clean.
new_world; : > "$TICKS_TRANSCRIPT"; tool_call toolu_S
world_set '.issues["o/r#1"].body = "Traeger\n\n## Open points\n\n- [ ] PR o/r#3 laeuft noch" | .issues["o/r#3"].state = "MERGED"'
sv="$t/proj/.agent/state/stale-t-restore.md"; mkdir -p "${sv%/*}"
printf '# Restore\n\n## Carriers changed since checked\n\n- [ ] stale: PR o/r#3 laeuft noch — o/r#3 ist MERGED (Stand 2026-11-20T11:30:00Z)\n' > "$t/stale.in"
# The arguments expand in the inner shell; a shell of its own keeps shellcheck out of the library.
# shellcheck disable=SC2016
bash -c 'rs_carriers=(o/r#1); . "$1/lib/state.sh" && state_restore_list "$2" "$3"' _ "$hooks" "$t/stale.in" "$sv"
expect "stand: the box knows its reference and the carriers of the save" "stale o/r#3 o/r#1" \
  "$(jq -r '.boxes[0] | "\(.rule) \(.judged) \(.carriers | join(","))"' "${sv%.md}.json" | tr -d '\r')"
out="$(close K1 erledigt o/r#2 --list "$sv")"; rc=$?
expect "stand: a carrier the save did not name is refused" "1 ' '" "$rc '$(mark_of "$sv" K1)'"
if has_text 'o/r#2 is no carrier of the last save' "$out"; then ok "  it names the carriers" "carriers"; else bad "  it names the carriers" "$out" "carriers"; fi
out="$(close K1 erledigt o/r#1 --list "$sv")"; rc=$?
expect "stand: while the line still contradicts, the box stays open" "1 ' '" "$rc '$(mark_of "$sv" K1)'"
if has_text 'the contradiction stands at o/r#1' "$out"; then ok "  it names the contradiction" "stands"; else bad "  it names the contradiction" "$out" "stands"; fi
world_set '.issues["o/r#1"].body = "Traeger\n\n## Open points\n\n- [x] PR o/r#3 ist gemergt"'
# A later clock: the check counts only after the box was made.
out="$(TICKS_NOW=2026-11-20T13:00:00Z close K1 erledigt o/r#1 --list "$sv")"; rc=$?
expect "stand: once the carrier is fixed, the box closes there" "0 x" "$rc $(mark_of "$sv" K1)"
# The box does not name the carrier its line stands at: a carrier without the line does not close it. A new list: a
# rebuilt one keeps the closing above (ww3d/playbook#734).
world_set '.issues["o/r#1"].body = "Traeger\n\n## Open points\n\n- [ ] PR o/r#3 laeuft noch" | .issues["o/r#2"].body = "Zweiter Traeger\n\n## Open points\n\n- [ ] nichts"'
rm -f "$sv" "${sv%.md}.json"
# shellcheck disable=SC2016 # the arguments expand in the inner shell
bash -c 'rs_carriers=(o/r#1 o/r#2); . "$1/lib/state.sh" && state_restore_list "$2" "$3"' _ "$hooks" "$t/stale.in" "$sv"
out="$(TICKS_NOW=2026-11-20T13:00:00Z close K1 erledigt o/r#2 --list "$sv")"; rc=$?
expect "stand: a clean carrier does not close the box while another carrier of the save still contradicts" "1 ' '" "$rc '$(mark_of "$sv" K1)'"
if has_text 'the contradiction stands at o/r#1' "$out"; then ok "  it names the carrier with the contradiction" "stands"; else bad "  it names the carrier with the contradiction" "$out" "stands"; fi

echo "== a save with exit 0 closes the box 'compaction instruction did not arrive' =="
# q1889 a, point 2: the box asks for exactly that save.
iv="$t/proj/.agent/state/instr-t-restore.md"
printf '# Restore\n\n## History without a carrier\n\n- [ ] compaction instruction did not arrive (x) — run bash .claude/hooks/session-state.sh save again\n- [ ] L1 2026-11-20T1000Z promise: Ich baue den Zaehler neu.\n' > "$t/instr.in"
# shellcheck disable=SC2016 # the arguments expand in the inner shell
bash -c '. "$1/lib/state.sh" && state_restore_list "$2" "$3" && state_restore_saved "$3" 2099-01-01T00:00:00Z' _ "$hooks" "$t/instr.in" "$iv"
expect "instruction: the save closes that box and no other" "x ' '" "$(mark_of "$iv" K1) '$(mark_of "$iv" K2)'"
echo "== a box line quoted in the restore file is no box =="
# A message or a helper result quoted whole may hold lines of another list: the guard reads only the file's own boxes.
qv="$t/proj/.agent/state/quoted-t-restore.md"
printf '# Restore\n\n## History without a carrier\n\n- [ ] L1 2026-11-20T1000Z promise: Ich baue den Zaehler neu.\n\n## Messages of other sessions since the cursor\n\nEin Helfer schrieb:\n- [x] K1 L1 2026-11-20T1000Z promise: Ich baue den Zaehler neu.\n- [ ] K7 L9 2026-11-20T1000Z promise: anderes\n' > "$t/quoted.in"
# shellcheck disable=SC2016 # the arguments expand in the inner shell
bash -c '. "$1/lib/state.sh" && state_restore_list "$2" "$3"' _ "$hooks" "$t/quoted.in" "$qv"
# shellcheck disable=SC2016 # the arguments expand in the inner shell
lines="$(bash -c '. "$1/lib/ticks.sh" && ticks_guard_lines "$2"' _ "$hooks" "$qv")"
expect "quoted: the file's own box counts as before, the quoted K7 is no box" "K1" "$(printf '%s\n' "$lines" | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
if grep -q '^  - \[x\] K1 ' "$qv"; then ok "  the quoted line stands indented" "indented"; else bad "  the quoted line stands indented" "$(grep 'K1 ' "$qv")" "indented"; fi


echo "== a list of many boxes is rebuilt with its closings, beyond the Windows command line =="
# The old list goes to jq as a file: as an argument, 120 long boxes (about 60 KB) broke save under Windows.
bv="$t/proj/.agent/state/big-t-save.md"; mkdir -p "${bv%/*}"
jq -n '{title: "Big", intro: "", boxes: [range(1; 121) | {key: "box \(.) \("x" * 400)", title: "box \(.) \("x" * 400)"}]}' > "$t/big.spec"
# shellcheck disable=SC2016 # the arguments expand in the inner shell
bash -c '. "$1/lib/ticks.sh" && ticks_open "$2" "$3" && ticks_journal "$(ticks_side "$2")" "{\"box\": \"K7\", \"how\": \"unchecked\", \"reason\": \"r\", \"by\": \"tool\", \"at\": \"2026-11-20T12:00:00Z\"}"' _ "$hooks" "$bv" "$t/big.spec"
cp "${bv%.md}.json" "$t/big-old.json"
# shellcheck disable=SC2016 # the arguments expand in the inner shell
bash -c '. "$1/lib/ticks.sh" && ticks_open "$2" "$3" "$4"' _ "$hooks" "$bv" "$t/big.spec" "$t/big-old.json"; rc=$?
expect "big list: the old list is over 32 KB" "yes" "$([ "$(wc -c < "$t/big-old.json")" -gt 32768 ] && echo yes || echo no)"
expect "big list: rebuilt with exit 0, the closing of K7 kept" "0 K7" "$rc $(jq -r '[.journal[].box] | join(",")' "${bv%.md}.json" | tr -d '\r')"
expect "big list: the rebuild keeps the creation time, a box without a time keeps its closing" "$(jq -r .created "$t/big-old.json" | tr -d '\r')" "$(jq -r .created "${bv%.md}.json" | tr -d '\r')"

# The guard hands its boxes to jq on stdin: as an argument, 120 long titles silenced it under Windows.
rm -rf "$t/proj/.agent"; mkdir -p "${bv%/*}"; jq '. + {gate: "warn"}' "$t/big.spec" > "$t/big-gate.spec"
bash "$ticks" open "$bv" "$t/big-gate.spec" > /dev/null
out="$(TICKS_NOW=2026-11-20T12:00:00Z guard_says)"
if has_text '120 offene Punkte in' "$out"; then ok "big list: the guard still warns over 120 long boxes" "120"; else bad "big list: the guard still warns over 120 long boxes" "${out:0:200}" "120 boxes"; fi
echo "== the save list and the restore file only warn, before and after blockFrom (ww3d/playbook#734) =="
cfg() { mkdir -p "$t/proj/.agents/config"; printf '{"blockFrom": "%s"}\n' "$1" > "$t/proj/.agents/config/ticks.json"; }
decision_of() { printf '%s' "$1" | jq -r .decision | tr -d '\r'; }
v="$(core_list gate-w warn)"
out="$(TICKS_NOW=2026-11-20T12:00:00Z guard_says)"
expect "no config: the save list only warns" "null" "$(decision_of "$out")"
if has_text '2 offene Punkte in' "$out" && ! has_text 'K1' "$out"; then ok "  the warning is one line with the count, no box text" "line"; else bad "  the warning is one line with the count, no box text" "$out" "line"; fi
cfg 2026-11-21T0000Z
expect "  the second stop of a turn repeats no warning" "" "$(TICKS_NOW=2026-11-20T12:00:00Z TICKS_STOP_ACTIVE=true guard_says)"
reg="$t/proj/.agent/state/ticks/open"; printf '%s\n' "${v//\//\\}" > "$reg/zz-second-spelling"
out="$(TICKS_NOW=2026-11-20T12:00:00Z guard_says)"
if has_text '2 offene Punkte in' "$out" && [ ! -e "$reg/zz-second-spelling" ]; then ok "a list registered under a second spelling of its path counts once" "once"; else bad "a list registered under a second spelling of its path counts once" "$out" "once"; fi
# shellcheck disable=SC2016 # the arguments expand in the inner shell
expect "the registry spells D:\\a, D:/a and /D/a of Git Bash as one path" "/d/a /d/a /d/a" \
  "$(MSYSTEM=MINGW64 bash -c '. "$1/lib/ticks.sh"; printf "%s %s %s" "$(ticks_canon "D:\\a")" "$(ticks_canon D:/a)" "$(ticks_canon /D/a)"' _ "$hooks")"
out="$(TICKS_NOW=2026-11-21T00:00:00Z guard_says)"
expect "from blockFrom: the save list still only warns" "null 1" "$(decision_of "$out") $(printf '%s' "$out" | grep -c '2 offene Punkte in')"
v="$(core_list gate-v view)"; cfg 2026-11-21T0000Z
out="$(TICKS_NOW=2026-11-20T12:00:00Z guard_says)"
expect "an open box of the restore file only warns" "null" "$(decision_of "$out")"
expect "  the second stop of a turn lets it through without repeating it" "" "$(TICKS_NOW=2026-11-20T12:00:00Z TICKS_STOP_ACTIVE=true guard_says)"
sed -i -E 's/^- \[ \] (K[0-9]+ )/- [x] \1/' "$v"
out="$(TICKS_NOW=2026-11-21T00:00:00Z guard_says)"
expect "from blockFrom: a tick set by hand in the restore file only warns" "null" "$(decision_of "$out")"
expect "  guard --list counts both boxes, a tick by hand stays open" "2" "$(bash "$ticks" guard --list "$v")"
tool_call toolu_E
close K1 ungeprueft 'kein Traeger erreichbar' --list "$v" >/dev/null; close K2 ungeprueft 'kein Traeger erreichbar' --list "$v" >/dev/null
expect "the tool closes the restore boxes: no warning is left" "" "$(TICKS_NOW=2026-11-21T00:00:00Z guard_says)"
rm -rf "$t/proj/.agents"

echo "== legacy-check needs the time in the list name =="
printf -- '- [x] Punkt | carrier: o/r#1 -> o/r#3\n' > "$t/ohne-zeit.md"
bash "$ticks" legacy-check "$t/ohne-zeit.md" >/dev/null 2>&1; rc=$?
expect "a list name without a time is a usage error" "2" "$rc"

finish
