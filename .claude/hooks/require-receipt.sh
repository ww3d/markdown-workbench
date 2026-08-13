#!/usr/bin/env bash
#
# Stop hook — read-confirmation gate. Generic, byte-identical across consumers.
#
# The SessionStart read-confirm.sh hook injects the read-confirmation receipt via
# hookSpecificOutput.additionalContext, which goes *silently* into the model's
# context — the user never sees it and the agent can skip surfacing it. This Stop
# hook turns that silent injection into a visible, non-ignorable gate: it refuses
# to let a turn end until the agent has actually emitted the receipt.
#
# Compliance signal: an assistant message whose text carries the receipt H1
# "# Session-Read-Confirmation" at the start of a line (the title read-confirm.sh /
# the /read-check command produce). The H1 is matched anchored to a line start, so
# a mere prose mention of the term mid-sentence does not falsely count as a receipt.
#
# Semantics: block iff the newest SessionStart injection in the transcript has no
# such assistant receipt after it. Keyed on the SessionStart event, the gate
# re-arms on resume and compact too (SessionStart fires again), not just on a cold
# startup.
#
# Fail-open by design: a missing field, missing file, or any jq error exits 0
# (allow), so a malformed transcript can never wedge every turn of a session. The
# gate enforces only when it can read the transcript with confidence.
#
# Schema-drift vs. empty transcript: a non-empty transcript in which none of the
# fields the gate depends on (type / attachment.hookEvent / message.content[].type)
# can be found is treated as a sign that the CC transcript schema has shifted under
# us. The gate still fails open (allow), but emits a systemMessage warning that it
# no longer recognizes its schema, so silent drift does not pass unnoticed. An
# empty, unreadable, or missing transcript stays a silent fail-open as before.
#
# Stdin:  the Stop hook event JSON ({ transcript_path, stop_hook_active, ... }).
# Stdout: only when blocking — { decision: "block", reason, systemMessage }.

set -euo pipefail

input="$(cat)"

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Index of the last SessionStart injection vs. the last assistant receipt. Block
# only when a SessionStart is newer than the most recent receipt (or none exists).
# Alongside the verdict, probe the fields the gate reads so a non-empty transcript
# with an unrecognized schema can be told apart from an empty one (see header).
verdict="$(jq -rs '
    (length) as $entries
  | ([ to_entries[]
       | select(.value.type == "attachment"
                and (.value.attachment.hookEvent? != null)) ] | length) as $att
  | ([ to_entries[]
       | select(.value.type == "assistant"
                and ((.value.message.content? // []) | any(.type? != null))) ]
       | length) as $asst
  | ([ to_entries[]
       | select(.value.type == "attachment"
                and (.value.attachment.hookEvent? == "SessionStart"))
       | .key ] | last) as $ss
  | ([ to_entries[]
       | select(.value.type == "assistant")
       | select([ .value.message.content[]?
                  | select(.type == "text") | .text ]
                | any(test("(^|\\n)# Session-Read-Confirmation")))
       | .key ] | last) as $rc
  | if ($entries == 0) then "ALLOW"
    elif (($att + $asst) == 0) then "DRIFT"
    elif (($ss // -1) > ($rc // -1)) then "BLOCK"
    else "ALLOW"
    end
' "$transcript" 2>/dev/null || true)"

case "$verdict" in
  BLOCK)
    jq -cn '{
      decision: "block",
      reason: ("Read-confirmation receipt missing for this session start. Before ending "
        + "this turn, output the session receipt: an H1 \"# Session-Read-Confirmation\" "
        + "followed by the three groups Konventionen / Profil / Memory, each closed with "
        + "OK. Reproduce it from the /read-check command or the "
        + ".claude/hooks/read-confirm.sh output. Do not end the turn without it."),
      systemMessage: "Session-Receipt fehlt - die Read-Confirmation muss vor dem Turn-Ende ausgegeben werden (/read-check)."
    }'
    ;;
  DRIFT)
    jq -cn '{
      systemMessage: ("Receipt-Gate: Transkript-Schema nicht wiedererkannt (moegliche "
        + "CC-Schema-Drift) - das Read-Confirmation-Gate greift derzeit nicht und sollte "
        + "geprueft werden.")
    }'
    ;;
esac
exit 0
