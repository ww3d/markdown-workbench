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
# Compliance signal: an assistant message whose text carries BOTH the receipt H1
# "# Session-Read-Confirmation" AND the group heading "## Konventionen", each
# anchored to a line start. Both must occur in the SAME assistant message. The H1 alone
# is not proof of a receipt — an assistant text that only quotes the title (a code
# fence, an explanation, a review of this very hook) matches the H1 regex too, so
# the second, conjunctive test is what tells a real receipt from a quotation.
#
# A second compliance signal, for the same two lines: a command the session RAN
# to print the receipt - a tool_use whose .input.command carries both, and whose
# own tool_result (same tool_use_id, not is_error) shows both too. Its place in
# the transcript is the result's line. Text written between tool calls can
# leave the model as thinking and then never lands as a text block
# (ww3d/playbook#271); an echoed receipt always does. A
# command that only carries the text as data - a file write, a refused call, a
# body sent somewhere - prints nothing of it back and does not count, the same
# rule require-rule-read.sh applies to a rule receipt (ww3d/playbook#273).
#
# Semantics: block iff the newest SessionStart injection in the transcript has no
# such assistant receipt after it. Keyed on the SessionStart event, the gate
# re-arms on resume and compact too (SessionStart fires again), not just on a cold
# startup.
#
# Fail-open by design, but the direction of "fail" matters and the two failure
# modes below are NOT the same thing:
#   - transcript missing, empty, or wholly unreadable (no file, zero JSON values)
#     -> ALLOW. There is nothing to judge, so the gate stays out of the way.
#   - a SINGLE unparsable line inside an otherwise readable transcript (e.g. a
#     write in progress truncated it mid-line) -> that one line is skipped, every
#     other line is still evaluated. This is NOT the same as failing open for the
#     whole transcript: a transcript with a broken line and no real receipt still
#     BLOCKs, because the surviving lines carry no receipt either.
# Lines are parsed one at a time (jq -R + fromjson? // empty) rather than slurped
# in one jq -s call, precisely so one bad line cannot take the rest of the batch
# down with it the way a single JSON parse error would fail an entire -s slurp.
#
# Schema-drift vs. empty transcript: a non-empty transcript in which none of the
# fields the gate depends on (type / attachment.hookEvent / message.content[].type)
# can be found is treated as a sign that the CC transcript schema has shifted under
# us. The gate still fails open (allow), but emits a systemMessage warning that it
# no longer recognizes its schema, so silent drift does not pass unnoticed. An
# empty, unreadable, or missing transcript stays a silent fail-open as before.
#
# The two jq -cn calls that build this hook's OWN output (BLOCK / DRIFT below)
# carry `|| true`: without it, a jq failure there (exit 2) would end this script
# under `set -e` with a non-zero exit code, and Claude Code reads a failing Stop
# hook as BLOCKING — the exact inversion of the fail-open stance this file argues
# for above.
#
# Loop guard: the gate blocks a stop once, never twice in a row. Claude Code sets
# stop_hook_active to true when the turn is already continuing because a Stop
# hook blocked it. If the receipt is still missing on that follow-up stop, the
# hook lets the turn end and says so in a visible systemMessage (WARN below)
# instead of blocking again — an agent that cannot produce the receipt would
# otherwise be sent round the same block until the harness's own cap on
# consecutive blocks ends the turn anyway. A field that is missing or not the
# literal true counts as false, so the first stop is always gated.
#
# Stdin:  the Stop hook event JSON ({ transcript_path, stop_hook_active, ... }).
# Stdout: when blocking — { decision: "block", reason, systemMessage }; when the
#         loop guard releases or the schema drifted — { systemMessage } only.

set -euo pipefail

input="$(cat)"

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
stop_hook_active="$(printf '%s' "$input" | jq -r '.stop_hook_active == true' 2>/dev/null || true)"

# Index of the last SessionStart injection vs. the last assistant receipt. Block
# only when a SessionStart is newer than the most recent receipt (or none exists).
# Alongside the verdict, probe the fields the gate reads so a non-empty transcript
# with an unrecognized schema can be told apart from an empty one (see header).
#
# $in is built line by line (-R, raw+slurp so `.` is the whole file as one
# string, then split and re-parsed per line) rather than via a single jq -s
# slurp: a slurp fails whole on the first unparsable line, which would silently
# turn every later line — receipt included — into "nothing to judge here".
# fromjson? // empty drops exactly the broken line and keeps the rest.
verdict="$(jq -Rrs '
    [ split("\n")[] | select(length > 0) | (fromjson? // empty) ] as $in
  | ($in | length) as $entries
  | ([ $in | to_entries[]
       | select(.value.type == "attachment"
                and (.value.attachment.hookEvent? != null)) ] | length) as $att
  | ([ $in | to_entries[]
       | select(.value.type == "assistant"
                and ((.value.message.content? // []) | any(.type? != null))) ]
       | length) as $asst
  | ([ $in | to_entries[]
       | select(.value.type == "attachment"
                and (.value.attachment.hookEvent? == "SessionStart"))
       | .key ] | last) as $ss
  | def receipt: test("(^|\\n)# Session-Read-Confirmation") and test("(^|\\n)## Konventionen");
    ([ $in | to_entries[]
       | select(.value.type == "assistant")
       | ([ .value.message.content[]? | select(.type == "text") | .text ]) as $texts
       | select($texts | any(test("(^|\\n)# Session-Read-Confirmation")))
       | select($texts | any(test("(^|\\n)## Konventionen")))
       | .key ] | last) as $rc
  | ([ $in[] | select(.type == "assistant") | .message.content[]?
       | select(.type == "tool_use" and (.id | type == "string")
                and (.input.command? | type == "string"))
       | select(.input.command | receipt) | .id ]) as $echoed
  | ([ $in | to_entries[]
       | select(.value.type == "user") | .key as $k
       | .value.message.content[]?
       | select(.type == "tool_result" and .is_error != true and (.tool_use_id | type == "string"))
       | select(.tool_use_id as $id | any($echoed[]; . == $id))
       | select(.content | (if type == "string" then .
                            elif type == "array" then map(.text? // "" | strings) | join("\n")
                            else "" end) | receipt)
       | $k ] | last) as $rcmd
  | ([$rc, $rcmd] | map(. // -1) | max) as $receipt
  | if ($entries == 0) then "ALLOW"
    elif (($att + $asst) == 0) then "DRIFT"
    elif (($ss // -1) > $receipt) then "BLOCK"
    else "ALLOW"
    end
' "$transcript" 2>/dev/null || true)"

[ "$verdict" = "BLOCK" ] && [ "$stop_hook_active" = "true" ] && verdict="WARN"

case "$verdict" in
  BLOCK)
    jq -cn '{
      decision: "block",
      reason: ("Read-confirmation receipt missing for this session start. Before ending "
        + "this turn, output the session receipt: an H1 \"# Session-Read-Confirmation\" "
        + "followed by the four groups Konventionen / Skills / Profil / Memory, each "
        + "closed with OK. Reproduce it from the /read-check command or the "
        + ".claude/hooks/read-confirm.sh output. Do not end the turn without it. Emit it "
        + "as the closing text of this turn, or print it with a command of its own (e.g. "
        + "echo): text written between tool calls may never reach the transcript."),
      systemMessage: "Session-Receipt fehlt - die Read-Confirmation muss vor dem Turn-Ende ausgegeben werden (/read-check)."
    }' || true
    ;;
  WARN)
    jq -cn '{
      systemMessage: ("Session-Receipt fehlt weiterhin - das Gate hat diesen Stop schon einmal "
        + "blockiert und laesst den Turn jetzt ohne Read-Confirmation enden (/read-check).")
    }' || true
    ;;
  DRIFT)
    jq -cn '{
      systemMessage: ("Receipt-Gate: Transkript-Schema nicht wiedererkannt (moegliche "
        + "CC-Schema-Drift) - das Read-Confirmation-Gate greift derzeit nicht und sollte "
        + "geprueft werden.")
    }' || true
    ;;
esac
exit 0
