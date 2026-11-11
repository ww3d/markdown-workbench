---
trigger: agents
read-before: starting a sub-agent or a session
budgetTokens: 1200
---

Read before: starting a sub-agent or a session

## Models

The default per session kind stands as data in
[`.agents/session-kinds.json`](https://github.com/ww3d/playbook/blob/main/.agents/session-kinds.json),
held equal to the first point below.

- Design, research, controller, review and orchestrator sessions run Opus; a dev session runs Sonnet, Opus
  only where the controller judges the change critical, intricate or sensitive — the design names
  the dev model in the spec, the controller confirms or overrides it.
- Review waves: the critical focus runs Opus, every other focus Sonnet; a wave of one agent runs Opus.
- Haiku only for mechanical work that checks nothing (a search, a count, a reformat), never as a
  reviewer.
- Fable only with the maintainer's release, for exactly the purpose named.
- **Effort** (default per kind: the field `effort`): `low` for mechanical sub-agents; `medium` for
  everything else; `high` only for design and the critical focus of a review wave. Nothing above
  `high` without a dated order of the maintainer.
- A dated order of the maintainer overrides this until lifted.

## Sub-Agents

- Extended `Glob`/`Grep`/`WebSearch`/`Bash` goes to Explore agents, extended `Edit`/`Bash` to
  general-purpose sub-agents. What a statement of yours rests on you read yourself, in full:
  delegate only the exploring, never the reading that decides something. A sub-agent's result is
  checked before it is used.
- Use sub-agents wherever they speed the task up.

## Never: Ending Processes and Sessions

- Only the orchestrator grants a foreign process (`.claude/hooks/lib/grant-kill.sh`), per number,
  for one ending of that process: a process of a session clone or in a folder named by the asking
  session's id; on the maintainer's word that they are away (at
  most 12 h, journaled), any but the kept programs; never an AI-agent host or a process above one,
  the granter's own chain, the system's core.
