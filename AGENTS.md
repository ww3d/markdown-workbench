# Agent Rules — Shared Playbook

Be honest in your response

**NEVER shorten, omit, move, or change on your own any order or instruction of the human maintainer — no exception, whatever the role; less scope, dropping, moving or replacing a part goes to them as a question first.**

## Rule Files

Read each file in full before the first action of its trigger type; without hooks, receipt it by hand (`.agents/rules/session.md`).

<!-- rule-index:start -->
| Trigger | File | Read before |
|---|---|---|
| `agents` | [`.agents/rules/agents.md`](.agents/rules/agents.md) | starting a sub-agent or a session |
| `audit` | [`.agents/rules/audit.md`](.agents/rules/audit.md) | starting a new slice or design round, running a state audit, or syncing from or diverging from a source |
| `carrier` | [`.agents/rules/carrier.md`](.agents/rules/carrier.md) | deferring a point, or setting a closing keyword |
| `chat` | [`.agents/rules/chat.md`](.agents/rules/chat.md) | the first answer to the maintainer |
| `code` | [`.agents/rules/code.md`](.agents/rules/code.md) | writing code |
| `controller` | [`.agents/rules/controller.md`](.agents/rules/controller.md) | steering sessions as controller or orchestrator, or commissioning, mediating or merging a pull request |
| `docs` | [`.agents/rules/docs.md`](.agents/rules/docs.md) | touching a doc or a timestamped file |
| `evidence` | [`.agents/rules/evidence.md`](.agents/rules/evidence.md) | claiming something is done, green, or measured |
| `pr` | [`.agents/rules/pr.md`](.agents/rules/pr.md) | opening or maintaining a pull request |
| `review` | [`.agents/rules/review.md`](.agents/rules/review.md) | posting a review |
| `session` | [`.agents/rules/session.md`](.agents/rules/session.md) | giving the read receipt by hand, or receiving a pasted text with a version line |
<!-- rule-index:end -->

## Core Rules

2. Truth is the repo at the head of the branch under work; memory is a suspicion, not evidence, and after a compaction everything read counts as unread except the project's `CLAUDE.md` and its imports, which the harness injects again.
3. Never invent: research first, ask when it stays unclear, and say "unknown" when nothing resolves it.
4. An agent never writes under the human owner's account.
5. End a foreign process or a foreign AI session only after an explicit yes to exactly that action from the session's owner or the maintainer; for a process, the orchestrator's journaled grant counts as that yes (`.agents/rules/agents.md`).
6. No merge without a test run that covers the merge head, in the mode `.agents/rules/pr.md` § "Test Runs" asks for.
7. Everything buildable is built; only what is not buildable goes to a valid carrier.
8. Every read that decides something is receipted: the start receipt and each point-of-use receipt.
9. No release, publish or force-push to a branch other than your own without approval.
10. Never disable tests to make a build pass, and never log secrets or tokens.
11. Nothing lives only locally, in a chat or in a message: every result, decision and open point stands at its carrier in the repo or an issue — written down per decided topic, before a compaction and at the session's end, not per question and answer.

## Working Mode

- **Before any decision, search inside first** — our repos, libraries and tools — then outside; "not accessible" is no finished search: get access.
- Run bulk and ending commands dry first; check every mass operation item by item.
- Before changing memory or configuration, read it and keep a copy.
