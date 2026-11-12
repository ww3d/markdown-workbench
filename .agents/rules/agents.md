---
trigger: agents
read-before: starting a sub-agent or a session
budgetTokens: 1200
---

Read before: starting a sub-agent or a session

## Models

Model and effort stand once, as data, in
[`.agents/session-kinds.json`](https://github.com/ww3d/playbook/blob/main/.agents/session-kinds.json):
per session kind under `kinds`, per sub-agent class under `subAgents` (`waveCritical`, `waveOther`,
`mechanical`). Rules, skills, specs and scripts read the file and name no model or effort of their
own.

- A dev session runs another model or more effort than its kind only where the controller judges
  the change critical, intricate or sensitive, never above the file's `maxEffort` — the design names
  either in the spec with one sentence of reason, the controller confirms or overrides it.
- A review wave runs its critical focus as `waveCritical` and every other focus as `waveOther`; a
  wave of one agent is the critical focus. Mechanical work that checks nothing (a search, a count,
  a reformat) runs as `mechanical`, never as a reviewer.
- Fable only with the maintainer's release, for exactly the purpose named.
- Nothing above the file's effort without a dated order of the maintainer, bar the dev session's up to
  `maxEffort`.
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
