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
# Ported from a consumer repo's hook-test suite (provenance: docs/provenance.md
# in the playbook), whose fixtures already carried the anticipated "## Skills"
# group in RECEIPT. Kept:
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

RECEIPT='Session receipt: give it once per session start or compaction, never repeat it unprompted per turn:
Playbook 5.0.0 | Core AGENTS.md 1a2b3c4 · CLAUDE.md 5d6e7f8 · Audit — (none)
Rules 1: carrier
Skills 1 · Stop hook require-receipt.sh registered (Project)
Memory: — (not available in this environment)'

# The receipt in its old German words, read until playbook 25.0.0 (ww3d/playbook#356).
OLD_RECEIPT='Session-Quittung, einmal je Sessionstart bzw. Kompaktierung ausgeben, ungefragt nie je Zug wiederholen:
Playbook 5.0.0 | Kern AGENTS.md 1a2b3c4 · CLAUDE.md 5d6e7f8 · Audit — (keiner)
Regeln 1: carrier
Skills 1 · Stop-Hook require-receipt.sh registriert (Projekt)
Gedaechtnis: — (nicht verfuegbar in dieser Umgebung)'

# carrier.md: chosen because "gh issue create" maps to exactly that one trigger
# (pr/review both drag in "evidence" too, which would need a second receipt).
RULE_LINE='rule | .agents/rules/carrier.md | abc1234 | read'

# A SessionStart injection. Its stdout carries the receipt text, exactly as the
# real hook produces it — that is what makes it a trap for a classifier that
# looks for the receipt line before it looks at the entry type.
# Optional $1: the source (startup, resume, fork, ...); default startup.
sessionstart() {
  jq -cn --arg r "$RECEIPT" --arg s "${1:-startup}" '{
    parentUuid: null, isSidechain: false, type: "attachment",
    attachment: { type: "hook_success", hookName: ("SessionStart:" + $s),
                  hookEvent: "SessionStart", content: "",
                  stdout: ({hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $r}} | tojson) }
  }'
}
assistant_text() { jq -cn --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'; }
assistant_thinking() { jq -cn --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "thinking", thinking: $t}]}}'; }
assistant_tool() { jq -cn '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", name: "Bash", input: {command: "ls"}}]}}'; }
assistant_tool_cmd() { jq -cn --arg c "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", name: "Bash", input: {command: $c}}]}}'; }
user_result() { jq -cn --arg t "$1" '{type: "user", message: {role: "user", content: [{type: "tool_result", content: $t}]}}'; }
# A tool call and its result, paired by id the way a real transcript pairs them
# (tool_use.id <-> tool_result.tool_use_id, is_error on the result).
tool_call() { # id, tool name, command
  jq -cn --arg i "$1" --arg n "$2" --arg c "$3" '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: $i, name: $n, input: {command: $c}}]}}'
}
tool_output() { # id, output, is_error
  jq -cn --arg i "$1" --arg t "$2" --argjson e "$3" '{type: "user", message: {role: "user", content: [{tool_use_id: $i, type: "tool_result", content: $t, is_error: $e}]}}'
}
# A typed message of the user, as measured in a Claude Code 2.1.294 transcript; only the review fixtures that
# name a compaction as text use it.
user_text() { jq -cn --arg t "$1" '{type: "user", message: {role: "user", content: $t}, origin: {kind: "human"}}'; }
# --- the fixtures -----------------------------------------------------------
# no receipt: a session start and ordinary work, no receipt anywhere
{ sessionstart; assistant_text "Ich lese zuerst die Grundlagen."; assistant_tool
  user_result "$RECEIPT"; } > "$dir/no-receipt.jsonl"

# receipt given after the session start
{ sessionstart; assistant_text "Bevor ich weiterarbeite, die Quittung.

$RECEIPT"; } > "$dir/with-receipt.jsonl"
{ sessionstart; assistant_text "$OLD_RECEIPT"; } > "$dir/with-old-receipt.jsonl"

# a second start in the same transcript after the receipt: the context still
# holds the receipt, so it does not re-arm the gate (ww3d/playbook#337)
{ cat "$dir/with-receipt.jsonl"; sessionstart resume; } > "$dir/resumed.jsonl"
{ cat "$dir/with-receipt.jsonl"; sessionstart resume
  assistant_text "Weiter mit der Arbeit."; } > "$dir/receipt-resume-turn.jsonl"
{ cat "$dir/with-receipt.jsonl"; sessionstart fork
  assistant_text "Weiter mit der Arbeit."; } > "$dir/receipt-fork-turn.jsonl"
{ cat "$dir/with-receipt.jsonl"; sessionstart startup
  assistant_text "Weiter mit der Arbeit."; } > "$dir/receipt-startup-turn.jsonl"

# a receipt, a further session start and a second receipt -> repeating does no harm
{ cat "$dir/with-receipt.jsonl"; sessionstart; assistant_text "$RECEIPT"; } > "$dir/receipt-ss-receipt.jsonl"

# the first line quoted in a code fence, without the Memory line -> not a real receipt
{ sessionstart
  assistant_text 'Der Marker lautet:
```
Playbook 5.0.0 | Core AGENTS.md 1a2b3c4
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

# The session receipt printed by a command (issue ww3d/playbook#271): the text between tool
# calls can leave the model as thinking and never land as a text block, an
# echo always lands. Counts only where the command's own result shows it; the
# counter-cases carry it as data only, or print it before a newer SessionStart.
{ sessionstart; tool_call t1 Bash "cat <<'EOF'
$RECEIPT
EOF"
  tool_output t1 "$RECEIPT" false; } > "$dir/echo-receipt.jsonl"
{ sessionstart; tool_call t1 Bash "cat <<'EOF'
$RECEIPT
EOF"; } > "$dir/echo-unrun.jsonl"
{ sessionstart; tool_call t1 Bash "cat > receipt.md <<'EOF'
$RECEIPT
EOF"
  tool_output t1 "" false; } > "$dir/echo-redirect.jsonl"
{ sessionstart; tool_call t1 Bash "cat <<'EOF'
$RECEIPT
EOF"
  tool_output t1 "$RECEIPT" true; } > "$dir/echo-refused.jsonl"
{ cat "$dir/echo-receipt.jsonl"; sessionstart resume; } > "$dir/echo-then-resumed.jsonl"

# require-rule-read.sh fixtures: the "rule | <path> | <sha> | read" receipt line,
# once as its own assistant text block (the documented case) and once only
# inside a tool_use command (a receipt echoed via Bash rather than emitted as a
# turn-closing text block).
{ sessionstart; assistant_text "Lese die Regel.

$RULE_LINE"; } > "$dir/rule-receipt-text.jsonl"

{ sessionstart; tool_call t1 Bash "echo '$RULE_LINE'"; tool_output t1 "$RULE_LINE" false; } > "$dir/rule-receipt-toolcmd.jsonl"

# The same echo through the PowerShell tool, its result as an array of text
# blocks rather than a plain string - both shapes occur in tool_result.content.
{ sessionstart; tool_call t1 PowerShell "Write-Output '$RULE_LINE'"
  jq -cn --arg t "$RULE_LINE" '{type: "user", message: {role: "user", content: [{tool_use_id: "t1", type: "tool_result", content: [{type: "text", text: $t}], is_error: false}]}}'
} > "$dir/rule-receipt-toolcmd-array.jsonl"

# Issue ww3d/playbook#273: a receipt line a command merely CARRIES must not count - only one
# it printed. Each of these has the line in .input.command and nowhere else
# that counts:
#   unrun    - the tool_use with no result yet (the PreToolUse moment of a
#              command that quotes the line and would unlock itself);
#   refused  - the result is an error (a denied call stays in the transcript);
#   redirect - the line written to a file, the result prints nothing of it;
#   data     - the line inside a gh body, the result is the comment's URL.
{ sessionstart; tool_call t1 Bash "echo '$RULE_LINE'"; } > "$dir/rule-receipt-unrun.jsonl"
{ sessionstart; tool_call t1 Bash "gh pr comment 1 --body '$RULE_LINE'"
  tool_output t1 "Permission denied by PreToolUse hook" true; } > "$dir/rule-receipt-refused.jsonl"
{ sessionstart; tool_call t1 Bash "cat > notes.md <<'EOF'
$RULE_LINE
EOF"
  tool_output t1 "" false; } > "$dir/rule-receipt-redirect.jsonl"
{ sessionstart; tool_call t1 Bash "gh pr comment 1 --body 'Gelesen: $RULE_LINE'"
  tool_output t1 "https://github.com/o/r/pull/1#issuecomment-1" false; } > "$dir/rule-receipt-data.jsonl"

# Refused, but the result shows the line - the shape of the hook's own stage-2
# denial, which quotes the receipt line in an is_error result
# (ww3d/playbook#289). is_error alone must decide.
{ sessionstart; tool_call t1 Bash "echo '$RULE_LINE'"
  tool_output t1 "$RULE_LINE" true; } > "$dir/rule-receipt-refused-echo.jsonl"

# A compaction ends every rule receipt before it (AGENTS.md, "Session Start:
# Read Before Anything Else"). Claude Code marks it with a system line
# subtype "compact_boundary", always, and - where a SessionStart hook ran - an
# attachment hookName "SessionStart:compact"; both shapes as measured on real
# Windows transcripts. Either one cuts; a receipt after it counts again.
compact_boundary() { jq -cn '{type: "system", subtype: "compact_boundary", content: "Conversation compacted", level: "info", compactMetadata: {trigger: "auto"}}'; }
compact_hook() {
  jq -cn '{type: "attachment", attachment: {type: "hook_success", hookName: "SessionStart:compact", hookEvent: "SessionStart", content: ""}}'
}
{ sessionstart; assistant_text "$RULE_LINE"; compact_boundary; } > "$dir/rule-receipt-then-compact.jsonl"
{ sessionstart; assistant_text "$RULE_LINE"; compact_hook; } > "$dir/rule-receipt-then-compact-hook.jsonl"
{ sessionstart; assistant_text "$RULE_LINE"; compact_boundary; compact_hook
  assistant_text "$RULE_LINE"; } > "$dir/rule-compact-then-receipt.jsonl"

# The session receipt lapses at the same cut, and at /clear (ww3d/playbook#337): a receipt
# before it no longer counts, one after it does; without any SessionStart
# nothing is owed.
{ cat "$dir/with-receipt.jsonl"; compact_boundary; } > "$dir/receipt-then-compact.jsonl"
{ cat "$dir/with-receipt.jsonl"; compact_hook; } > "$dir/receipt-then-compact-hook.jsonl"
# /clear empties the context like a compaction does
{ cat "$dir/with-receipt.jsonl"; sessionstart clear
  assistant_text "Weiter."; } > "$dir/receipt-then-clear.jsonl"
{ cat "$dir/with-receipt.jsonl"; sessionstart clear
  assistant_text "$RECEIPT"; } > "$dir/clear-then-receipt.jsonl"
{ cat "$dir/echo-receipt.jsonl"; compact_boundary; } > "$dir/echo-then-compact.jsonl"
{ cat "$dir/with-receipt.jsonl"; compact_boundary; compact_hook
  assistant_text "$RECEIPT"; } > "$dir/compact-then-receipt.jsonl"
{ assistant_text "Normale Arbeit."; compact_boundary
  assistant_text "Weiter."; } > "$dir/compact-no-sessionstart.jsonl"
# another hook's attachment is no session start
{ jq -cn '{type: "attachment", attachment: {type: "hook_success", hookName: "PreToolUse:Bash",
            hookEvent: "PreToolUse", content: ""}}'
  assistant_text "Normale Arbeit."; } > "$dir/other-hook-no-sessionstart.jsonl"

{ sessionstart; assistant_text "Normale Arbeit ohne Regel-Quittung."; } > "$dir/rule-no-receipt.jsonl"

# The line /pr-poll-review prints at its gate step: the same four shapes as the rule
# receipt - printed by a command that ran (counts), carried as data, refused, before a compaction.
HEAD_A="$(printf 'a%.0s' {1..40})"
REVIEW_LINE="review-head | o/r#5 | $HEAD_A"
{ sessionstart; tool_call t1 Bash "echo '$REVIEW_LINE'"; tool_output t1 "$REVIEW_LINE" false; } > "$dir/review-head-a.jsonl"
# A compaction only named as text - in a later message or a tool result - is no compaction: the run stands.
{ cat "$dir/review-head-a.jsonl"
  user_text 'Kompaktiert? {"type":"system","subtype":"compact_boundary"} und "hookName":"SessionStart:compact"'
} > "$dir/review-compact-text-user.jsonl"
{ cat "$dir/review-head-a.jsonl"; tool_call t2 Bash "cat old.jsonl"
  tool_output t2 '{"type":"system","subtype":"compact_boundary"}
{"type":"attachment","attachment":{"type":"hook_success","hookName":"SessionStart:compact"}}' false
} > "$dir/review-compact-text-result.jsonl"
# a run before a compaction and one after it: the newest compaction is the cut, the later run counts
{ sessionstart; tool_call t0 Bash "echo '$REVIEW_LINE'"; tool_output t0 "$REVIEW_LINE" false
  compact_boundary; compact_hook; tool_call t1 Bash "echo '$REVIEW_LINE'"; tool_output t1 "$REVIEW_LINE" false
} > "$dir/review-compact-then-run.jsonl"
{ sessionstart; tool_call t1 Bash "echo 'review-head | o/r#6 | $HEAD_A'"
  tool_output t1 "review-head | o/r#6 | $HEAD_A" false; } > "$dir/review-head-other-pr.jsonl"
{ sessionstart; tool_call t1 Bash "gh pr comment 5 --body '$REVIEW_LINE'"
  tool_output t1 "https://github.com/o/r/pull/5#issuecomment-1" false; } > "$dir/review-head-data.jsonl"
{ sessionstart; tool_call t1 Bash "echo '$REVIEW_LINE'"; tool_output t1 "$REVIEW_LINE" true; } > "$dir/review-head-refused.jsonl"
{ cat "$dir/review-head-a.jsonl"; compact_boundary; } > "$dir/review-head-then-compact.jsonl"
# lines for two PRs of one repo: a command that posts on both is checked for each
{ sessionstart; tool_call t1 Bash "echo '$REVIEW_LINE'"; tool_output t1 "$REVIEW_LINE" false
  tool_call t2 Bash "echo 'review-head | o/r#6 | $HEAD_A'"; tool_output t2 "review-head | o/r#6 | $HEAD_A" false
} > "$dir/review-head-5-and-6.jsonl"
# and one for the PR the body-number cases name (352): the gh call is made only for a PR with a line
{ cat "$dir/review-head-a.jsonl"
  tool_call t2 Bash "echo 'review-head | o/r#352 | $HEAD_A'"; tool_output t2 "review-head | o/r#352 | $HEAD_A" false
} > "$dir/review-head-5-and-352.jsonl"
# an older line for the same PR next to the current one: the current head decides
HEAD_B="$(printf 'b%.0s' {1..40})"
{ sessionstart; tool_call t1 Bash "echo 'review-head | o/r#5 | $HEAD_B'"; tool_output t1 "review-head | o/r#5 | $HEAD_B" false
  tool_call t2 Bash "echo '$REVIEW_LINE'"; tool_output t2 "$REVIEW_LINE" false; } > "$dir/review-head-old-and-new.jsonl"
# The two reference files a review post rests on, receipted like a rule file; the first
# fixture holds both, the second only gates.md.
REF_DIR='.claude/skills/pr-poll-review/reference'
REF_GATES="rule | $REF_DIR/gates.md | abc1234 | read"
REF_CHECKS="rule | $REF_DIR/checks.md | abc1234 | read"
{ sessionstart; assistant_text "$REF_GATES
$REF_CHECKS"; cat "$dir/review-head-a.jsonl"; } > "$dir/review-refs-both.jsonl"
{ sessionstart; assistant_text "$REF_GATES"; cat "$dir/review-head-a.jsonl"; } > "$dir/review-refs-gates-only.jsonl"
{ cat "$dir/review-refs-both.jsonl"; compact_boundary; } > "$dir/review-refs-then-compact.jsonl"

# Receipt shapes that must not count (the Stop hook): the memory line alone, the two lines in
# two messages, and the old format whose first line was an H1 with a Konventionen group.
{ sessionstart; assistant_text 'Memory: — (not available in this environment)'; } > "$dir/mem-only.jsonl"
{ sessionstart
  assistant_text 'Playbook 5.0.0 | Core AGENTS.md 1a2b3c4 · CLAUDE.md 5d6e7f8 · Audit — (none)'
  assistant_text 'Memory: — (not available in this environment)'; } > "$dir/split-messages.jsonl"
{ sessionstart
  assistant_text '# Session-Quittung
## Konventionen
- AGENTS.md OK
## Memory
- Gedaechtnis: leer'; } > "$dir/old-format.jsonl"

printf 'fixtures in %s\n' "$dir"
