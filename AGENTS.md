# Agent Rules — Shared Playbook

Be honest in your response

Read on every session; imported by each consuming repo's `CLAUDE.md` via `@AGENTS.md`, which adds the
project's own material below the import. This file is the **core**: what holds in every session.
Tech overlays (`.agents/tech/<stack>.md`) are imported per stack; the rule files below are read at
their point of use.

**NEVER shorten, omit, move, or change on your own any order or instruction of the human maintainer — no exception, whatever the role; less scope, dropping, moving or replacing a part goes to them as a question first.**

## Rule Files

Each file is read **in full** and receipted before the first action of its trigger type in a session
(§ "Session Start: Read Before Anything Else"); the one exception, a controller's successor reading
`pr.md` by section, stands in that file. A rule not in this table stands in this core.
The table is generated, never hand-kept.

<!-- rule-index:start -->
| Trigger | File | Read before |
|---|---|---|
| `agents` | [`.agents/rules/agents.md`](.agents/rules/agents.md) | starting a sub-agent or a session |
| `audit` | [`.agents/rules/audit.md`](.agents/rules/audit.md) | starting a new slice or design round, running a state audit, or syncing from or diverging from a source |
| `carrier` | [`.agents/rules/carrier.md`](.agents/rules/carrier.md) | deferring a point, or closing an issue |
| `chat` | [`.agents/rules/chat.md`](.agents/rules/chat.md) | the first answer to the maintainer |
| `code` | [`.agents/rules/code.md`](.agents/rules/code.md) | writing code |
| `docs` | [`.agents/rules/docs.md`](.agents/rules/docs.md) | touching a doc or a timestamped file |
| `evidence` | [`.agents/rules/evidence.md`](.agents/rules/evidence.md) | claiming something is done, green, or measured |
| `pr` | [`.agents/rules/pr.md`](.agents/rules/pr.md) | opening or maintaining a pull request |
| `review` | [`.agents/rules/review.md`](.agents/rules/review.md) | posting a review |
| `session` | [`.agents/rules/session.md`](.agents/rules/session.md) | giving the read receipt by hand, the next action after a compaction, ending or handing over a session, or receiving a pasted text with a version line |
<!-- rule-index:end -->

## Core Rules

The eleven rules below are kept as data in `.agents/core-rules.json` and checked against this file.

1. The bold NEVER rule at the top of this file (K1).
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

## Session Start: Read Before Anything Else

The head — of the branch under work, `main` where there is none — is the local `HEAD` with a working
copy, otherwise the remote head via `gh` or the GitHub MCP — never the prompt. Whatever you believe
about a document, issue, log or rule is a lead to check there; these four steps move reading to the
moment it decides something. The form of the read receipt stands in `.agents/rules/session.md`.
1. **Mandatory core**, read in full and receipted with blob SHA: this file, `CLAUDE.md`, and the
   **audit head** of the latest state audit (metadata block plus its leading short-form section,
   `.agents/rules/audit.md` § "State Audit"). Report one as "not found" only after a search.
2. **State, selectively:** the index of the remaining docs (`docs/**` and root `*.md` as path +
   purpose, without `docs/overview/`) and the **running slice** (open tracking issue body plus its
   `roadmap.md` lines). Roadmap, backlog and architecture doc are not read in full up front; any
   source a statement or decision touches — a document, a decision log, an issue, a dependency or
   model-template repo — is read **in full first**. The running phase's decision logs always.
3. **Point of use:** before the first action of a trigger type, read its rule file in full. In
   Claude Code `.claude/hooks/record-rule-read.sh` records the real read — per session and per
   sub-agent, a sub-agent reads for itself — and `.claude/hooks/require-rule-read.sh` blocks the
   action until it happened, naming only path and blob SHA. Each rule file read gets one line in
   the form of the read receipt (`.agents/rules/session.md` § "Session Receipt"), named relative
   to `.agents/rules/` (any other file by its path); without hooks the skills carry it as their
   entry step. Neither replaces reading the file:

   ```diff
   + pr.md        24.1.0   4f2a1c9   read (rule)
   ```
4. **Too large for one read:** read section by section; where even that fails, receipt
   `partial: <path> - sections 1-4 of 11, <limit>` instead of a silent gap.

**Without hooks** (Claude Web, or a repo without that registration) the first answer of every working session is the same block, written by hand, plus the skill carrying the task, or "none"; nothing comes before it, and a session whose first answer lacks it is ended there — the operator checks one answer, not forty. Discipline still produces the receipt; what changes is that its absence shows at the first answer instead of in the damage.

## Working Mode

- **Before any decision, search inside first** — our repos, libraries and tools, how they already
  do it — then outside per skill and playbook; "not accessible" is no finished search: get access.
- **No block without measured evidence:** a block, an omission or a "rejected as risky" rests on a
  measurement, not an assumption — measure first; every block has a named way past (an explicit
  switch, set from above, journaled); limits the maintainer set stay, and a review checks each new block.
- Before acting, check whether a skill covers the task; if one does, follow it.
- What will likely take longer than 15 s — a command, a search — runs in the background, so the
  channel stays open for interjections.
- Run bulk and ending commands dry first; check the outcome of every mass operation item by item.
- Build nothing an open issue or PR already builds — check first.
- Before changing memory or configuration, read it and keep a copy.
- Edit only inside the repository; never `bin/`, `obj/`, `dist/`, `_build/`, `_buildtools/`,
  `node_modules/`, `.git/`, or anything above the root.

## Never

- Act on a rule from memory instead of from its file.
- Shut down or reboot the machine, stop, restart or disable services, uninstall software, or remove
  machine-wide configuration.
