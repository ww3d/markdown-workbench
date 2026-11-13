---
trigger: session
read-before: giving the read receipt by hand, or receiving a pasted text with a version line
budgetTokens: 1300
---

Read before: giving the read receipt by hand, or receiving a pasted text with a version line

## Pasted Texts and Compaction

**A pasted text whose version line** names an older playbook version than the read receipt is named
in the answer to it — mid-chat too —, with the current version.

**After a compaction, read the restore file in full before the next step** (`.agent/state/<session>-restore.md`,
written by the restore hook; it comes before the summary), and the session's start order where one stands
(`.agent/brief.md`); a successor after a switch reads its restore file the same way (`bash
.claude/hooks/session-state.sh restore --from <carrier>`, from the predecessor's check line). From the cursor of the last save it holds the
maintainer's sentences, the messages of other sessions and the helper results verbatim, and as boxes what no
carrier holds and the carriers another hand changed; carry each box to a carrier or tick it
`- [x] <box> -> <proof>`. A session kind with `atMark: compact` has, after each save, a helper check the pair
file `.agent/state/<session>-pairs.md` with `.claude/skills/chat-handoff/reference/pair-check.md` and corrects
every finding at its carrier.

## Session Receipt

Where no hook shows the read receipt, the first answer after a start or a compaction carries it by
hand, strictly in this form, inside a `diff` fence:

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
once the start loaded them, after a compaction too. The version is the playbook's; the repo's
`CLAUDE.md` and a local rule carry `(repo)`. `Rules` counts the rule files read in the session,
`Stop hook` says `on` or `off (<reason>)`, and what the environment cannot see reads
`— (not available in this environment)`. A rule file read later gets only its line, never the block
again. Nothing comes before the receipt, and a session whose first answer lacks it is ended there.
