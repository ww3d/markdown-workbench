---
trigger: session
read-before: giving the read receipt by hand, the next action after a compaction, ending or handing over a session, or receiving a pasted text with a version line
budgetTokens: 1300
---

Read before: giving the read receipt by hand, the next action after a compaction, ending or handing over a session, or receiving a pasted text with a version line

## Pasted Texts and Compaction

**A pasted text whose version line** (`<!-- task-template v<n> — <stamp> — Playbook <version> -->`,
generated in the playbook under `texts/`) names an older playbook version than the read receipt is
named in the answer to the message that carries it — mid-chat too —, with the current version.

**After a compaction** read again before the next action, and answer nothing about an issue or file
from the summary: (1) mandatory core but `CLAUDE.md` with its imports (the harness injects them
again; re-measure on its update); (2) running slice, decision logs, doc index; (3) each rule file
read before, before the next action of its kind; (4) running PR — body, spec file, review
threads, wave state at the head, never rebuilt from the diff; (5) role or seat — never from the
summary or a skill; (6) approvals — count as not given; (7) verification state — "green",
"checked" is rerun or read at the head; (8) a `SKILL.md` over 5,000 tokens or one the harness
dropped from its 25,000 in all (oldest first), and the skill step from the restore file, never from
the summary; (9) sub-agent ledger (`.agents/rules/agents.md` § "Sub-Agents"); (10) the start order
verbatim from the file the session tool wrote it to, where it writes one, never from the summary —
a hook's replay file read in full meets it. Where the transcript grew since the last check, a
sub-agent cross-checks the lines from the previous mark to its end against the carriers —
maintainer sentences, messages, own promises, sub-agent results — and returns the open ones
(`.claude/skills/chat-handoff/reference/cross-check.md`), which go to their carriers; first at the
reminder before the compaction, then only for what came since. With the hooks the main thread stays
locked until that file and the result are read; while the sub-agent runs, only the sending commands
the delivery tool sets in `PLAYBOOK_LOCK_SEND_RE` stay held.

## Session Receipt

The `read-confirm.sh` SessionStart hook shows the read receipt to the human as its message, with each
file's version and blob SHA, at every start and after every compaction; the session writes none.
Where no hook runs, the first answer carries the block by hand (`AGENTS.md` § "Session Start: Read
Before Anything Else"), once per session start or compaction, strictly in this form, inside a `diff`
fence:

```diff
── Read receipt ──────────────────────────────
Playbook 24.0.2 | Core
+ AGENTS.md    24.0.2   78e818b   read
+ CLAUDE.md    (repo)   04ad8f8   read
+ pr.md        24.0.2   05e9a80   read (rule)
Rules 1 of 7 read · Skills 6 · Stop hook on
Memory: 19 entries
──────────────────────────────────────────────
```

`+ … read` only for a file read in full; `CLAUDE.md`, and an `AGENTS.md` it imports, count as read
once the start loaded them, after a compaction too. A missing `AGENTS.md` reads `missing (sync error)`, a missing
`CLAUDE.md` `missing`. The audit head read before the trigger `audit` gets its line like a rule file, the file name in
brackets after `read`: `+ Audit — <sha> read (state-<stamp>.md)`, read from line 1 through its short
form. `record-rule-read.sh` records every full read with the Read tool of a file of the receipt,
`read-confirm.sh` what the start loaded, and `require-receipt.sh` refuses a turn end once while a
green line of a receipt in the transcript has no such read of the main thread (a sub-agent's read
does not count); until the record has seen a read in the session, the line passes. A missing
receipt never blocks a turn end; the second stop warns instead of looping. The version is the
playbook's; the repo's `CLAUDE.md` and a local rule carry `(repo)`, the audit `—`. `Rules` counts
the rule files read in the session (`/read-check` counts them later), `Stop hook` says `on` or
`off (<reason>)`, and what the environment cannot see reads `— (not available in this environment)`;
a newer playbook version gets a line above the closing line. A rule file read later gets only its
line (`AGENTS.md` § "Session Start: Read Before Anything Else", step 3), never the block again. The
earlier forms — the one-line receipt, `Kern` and `Gedaechtnis:`, and `rule | <path> | <sha> | read`
— are read until playbook 26.0.0. All hooks run only where the repo's `.claude/settings.json`
registers them.

## Session End: Carry What Is Still Open

Before the session ends — and before a compaction, which ends whatever lives only in the transcript —
walk it backwards once: every open point that stands nowhere (a decision without log entry, a
cleared-up misconception, a deferred point, a running order) goes to a valid carrier first (core
rule 11; `.agents/rules/carrier.md` § "Carrier Requirement"). This is the counterpart to the read
mandate, and unlike the carrier gate in a review it does not depend on a PR existing.
