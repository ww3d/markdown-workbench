#!/usr/bin/env bash
#
# Builds the transcript fixtures the require-receipt.sh / require-rule-read.sh
# tests run against.
#
# Synthetic, not copied: the fixtures reproduce the *shape* of a CC transcript —
# the SessionStart attachment, an assistant text block, a tool_use — but carry
# no content from a real session. That keeps them small, reviewable and free of
# whatever a real transcript happens to contain, and it is the reason the tests
# are reproducible on any machine rather than only where such a transcript sits.
#
# Ported from ww3d/rc-control@3de127c (.claude/hooks/tests/mkfixtures.sh), whose
# fixtures already carried the anticipated "## Skills" group in RECEIPT. Kept:
# the JSONL-shape fixtures used by require-receipt.sh. Dropped: the gate-actions
# subagent fixtures (sub/SID.jsonl, sub/SID/subagents/agent-a.jsonl) — that
# hook's parent/subagent transcript redirection has no counterpart in either
# hook this repo carries.
#
# The shape is the load-bearing part, so it is worth stating what was checked
# against a real transcript when these were written: an assistant message is
# written as one line per content block, text before tool_use, so a receipt is in
# the file before the tool call it precedes; the SessionStart injection appears
# as type "attachment" with attachment.hookEvent "SessionStart"; and its stdout
# field contains the receipt text itself, which is why the classifier must test
# the attachment case before the assistant case.
#
# Usage: mkfixtures.sh <dir>
set -euo pipefail

dir="${1:?usage: mkfixtures.sh <dir>}"
mkdir -p "$dir"

RECEIPT='# Session-Read-Confirmation (Playbook 5.0.0)

## Konventionen
- CLAUDE.md @ projekt OK
OK

## Skills
- beispiel-skill v1.0.0
OK

## Profil
- Claude-Profil / User-Preferences: — (nicht verfuegbar in dieser Umgebung)
OK

## Memory
- Memory-Stand: — (nicht verfuegbar in dieser Umgebung)
OK'

# carrier.md: chosen because "gh issue create" maps to exactly that one trigger
# (pr/review both drag in "evidence" too, which would need a second receipt).
RULE_LINE='rule | .agents/rules/carrier.md | abc1234 | read'

# A SessionStart injection. Its stdout carries the receipt text, exactly as the
# real hook produces it — that is what makes it a trap for a classifier that
# looks for the H1 before it looks at the entry type.
sessionstart() {
  jq -cn --arg r "$RECEIPT" '{
    parentUuid: null, isSidechain: false, type: "attachment",
    attachment: { type: "hook_success", hookName: "SessionStart:startup",
                  hookEvent: "SessionStart", content: "",
                  stdout: ({hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $r}} | tojson) }
  }'
}
assistant_text() { jq -cn --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'; }
assistant_thinking() { jq -cn --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "thinking", thinking: $t}]}}'; }
assistant_tool() { jq -cn '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", name: "Bash", input: {command: "ls"}}]}}'; }
assistant_tool_cmd() { jq -cn --arg c "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", name: "Bash", input: {command: $c}}]}}'; }
user_result() { jq -cn --arg t "$1" '{type: "user", message: {role: "user", content: [{type: "tool_result", content: $t}]}}'; }

# --- the fixtures -----------------------------------------------------------
# no receipt: a session start and ordinary work, no receipt anywhere
{ sessionstart; assistant_text "Ich lese zuerst die Grundlagen."; assistant_tool
  user_result "$RECEIPT"; } > "$dir/no-receipt.jsonl"

# receipt given after the session start
{ sessionstart; assistant_text "Bevor ich weiterarbeite, die Quittung.

$RECEIPT"; } > "$dir/with-receipt.jsonl"

# resume / compact: a second injection after the receipt re-arms the gate
{ cat "$dir/with-receipt.jsonl"; sessionstart; } > "$dir/resumed.jsonl"

# a receipt before and after the newest session start -> the newer one counts
{ cat "$dir/with-receipt.jsonl"; sessionstart; assistant_text "$RECEIPT"; } > "$dir/receipt-ss-receipt.jsonl"

# the H1 quoted in a code fence, without a group heading -> not a real receipt
{ sessionstart
  assistant_text 'Der Marker lautet:
```
# Session-Read-Confirmation
```
Das war alles.'; } > "$dir/quote-only.jsonl"

# a receipt that never was an assistant text block
{ sessionstart; assistant_thinking "$RECEIPT"; } > "$dir/thinking-only.jsonl"

# schema drift: valid JSON, none of the fields the gate reads
{ jq -cn '{kind: "turn", who: "assistant", blocks: [{kind: "prose", body: "hallo"}]}'
  jq -cn '{kind: "turn", who: "user", blocks: [{kind: "prose", body: "welt"}]}'; } > "$dir/drift.jsonl"

: > "$dir/empty.jsonl"

# a half-written line, followed by ordinary work and no real receipt: the
# broken line must be skipped, not taken as a reason to stop judging the rest
# of the transcript. Still no receipt anywhere good -> still BLOCK.
{ sessionstart | cut -c1-120; sessionstart; assistant_text "Normale Arbeit ohne Quittung."; } > "$dir/trunc-no-receipt.jsonl"

# the same broken line, but a real receipt follows it -> the receipt must
# still be found; a corrupted line must not swallow a good one that comes after.
{ sessionstart | cut -c1-120; assistant_text "$RECEIPT"; } > "$dir/trunc-then-receipt.jsonl"

# require-rule-read.sh fixtures: the "rule | <path> | <sha> | read" receipt line,
# once as its own assistant text block (the documented case) and once only
# inside a tool_use command (a receipt echoed via Bash rather than emitted as a
# turn-closing text block).
{ sessionstart; assistant_text "Lese die Regel.

$RULE_LINE"; } > "$dir/rule-receipt-text.jsonl"

{ sessionstart; assistant_tool_cmd "echo '$RULE_LINE'"; } > "$dir/rule-receipt-toolcmd.jsonl"

{ sessionstart; assistant_text "Normale Arbeit ohne Regel-Quittung."; } > "$dir/rule-no-receipt.jsonl"

printf 'fixtures in %s\n' "$dir"
