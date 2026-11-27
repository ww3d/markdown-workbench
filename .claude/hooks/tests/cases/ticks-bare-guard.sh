#!/usr/bin/env bash
# Hook suite section: ticks.sh guard called bare as a Stop hook (managed-settings.json, instance/README.md)
# Run alone: bash .claude/hooks/tests/cases/ticks-bare-guard.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# The guard reads the Stop payload: the same counts stay silent per session, as under require-receipt.sh
# (ww3d/playbook#734). No network: opening a list without changes calls no forge.
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

ticks="$hooks/ticks.sh"
bg="$fix/ticks-bare-guard"; rm -rf "$bg"; mkdir -p "$bg/proj" "$bg/tmp"
spec() { jq -n --argjson n "$1" '{title: "T", boxes: [range(1; $n + 1) | {key: "k\(.)", title: "Kasten \(.)",
  carriers: ["o/r#1"], lines: ["Zeile"], changes: []}]}' > "$bg/spec.json"; }
spec 3; CLAUDE_PROJECT_DIR="$bg/proj" TMPDIR="$bg/tmp" bash "$ticks" open "$bg/proj/l.md" "$bg/spec.json" > /dev/null
bare_stop() { # session, stop_hook_active -> what the hook prints
  jq -nc --arg s "$1" --argjson a "${2:-false}" '{session_id: $s, stop_hook_active: $a, hook_event_name: "Stop"}' \
    | CLAUDE_PROJECT_DIR="$bg/proj" TMPDIR="$bg/tmp" bash "$ticks" guard 2>&1
}

echo "== the guard as a bare Stop hook: one warning per count and session (ww3d/playbook#734) =="
said=no; has_text '3 offene Punkte in l.md' "$(bare_stop s1)" && said=yes
expect "the first turn end warns" "yes" "$said"
expect "the same count at the next turn end says nothing, nor anything on stderr" "" "$(bare_stop s1)"
expect "the second stop of a turn says nothing" "" "$(bare_stop s2 true)"
printf '%s\n' '- [x] K99 erfunden' >> "$bg/proj/l.md"
said=no; has_text '4 offene Punkte' "$(bare_stop s1)" && said=yes
expect "a count that changes warns again" "yes" "$said"
said=no; has_text '4 offene Punkte' "$(bare_stop s3)" && said=yes
expect "another session gets its own first warning" "yes" "$said"
mkdir -p "$bg/proj/.claude"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"bash .claude/hooks/require-receipt.sh"}]}]}}' > "$bg/proj/.claude/settings.json"
expect "where require-receipt.sh is registered, it warns and the bare hook stays silent" "" "$(bare_stop s4)"
# shellcheck disable=SC2016 # the settings file must hold ${CLAUDE_PROJECT_DIR} literally
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/bin/pb-hook","args":["stop"]}]}]}}' \
  > "$bg/proj/.claude/settings.json"
expect "where pb-hook stop is registered, it warns and the bare hook stays silent" "" "$(bare_stop s6)"
# shellcheck disable=SC2016
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"${CLAUDE_PROJECT_DIR}/.claude/hooks/bin/pb-hook","args":["post-tool"]}]}]}}' \
  > "$bg/proj/.claude/settings.json"
said=no; has_text '4 offene Punkte' "$(bare_stop s7)" && said=yes
expect "another call of pb-hook at the turn end does not silence it" "yes" "$said"
rm -f "$bg/proj/.claude/settings.json"
said=no; has_text '4 offene Punkte' "$(CLAUDE_PROJECT_DIR="$bg/proj" TMPDIR="$bg/tmp" bash "$ticks" guard < /dev/null)" && said=yes
expect "without a payload the guard warns as before" "yes" "$said"
spec 2; CLAUDE_PROJECT_DIR="$bg/proj" TMPDIR="$bg/tmp" bash "$ticks" open "$bg/proj/s9-save.md" "$bg/spec.json" > /dev/null
said=no; has_text 's9-save.md' "$(bare_stop s5)" && said=yes
expect "the save list of another session stays out of the line" "no" "$said"
said=no; has_text '2 offene Punkte in s9-save.md' "$(bare_stop s9)" && said=yes
expect "the save list warns at its own session's turn end" "yes" "$said"

echo "== the help names the inputs of the cap of three (ww3d/playbook#750) =="
help="$(bash "$ticks" 2>&1)"
for v in CLAUDE_PID TICKS_TRANSCRIPT; do
  check_contains "the help names $v" "$v" "$help"
done

finish
