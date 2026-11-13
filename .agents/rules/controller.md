---
trigger: controller
read-before: steering sessions as controller or orchestrator, or commissioning, mediating or merging a pull request
budgetTokens: 3700
---

Read before: steering sessions as controller or orchestrator, or commissioning, mediating or merging a pull request

Additive, for a controller session that orchestrates workers; no rule of `.agents/rules/pr.md` changes, only the casting.

## Controller Sessions

- **The controller is none of the three roles.** Until the merge it takes the `maintainer`'s part —
  commissioning, mediating, accepting; it writes no product code, runs no `dev` step (the draft
  switch included; pushing a clean round's ledger before the merge, `controller-mode` step 5, and the run
  `.agents/rules/pr.md` § "Test Runs" gives the merger are none) and
  posts no review: posting is a `reviewer` action, and a session that collects
  findings and posts them approves its own work.
- **Seats:** `dev` = a worker; `reviewer` = a worker of its own (`.agents/rules/pr.md` § "PR Lifecycle"); `maintainer` =
  the human, for the merge and what `.agents/rules/pr.md` § "Controller Mode" lists for it — in controller mode the
  controller holds the merge too.
- **The approval gate changes addressee, never falls away (but mode `once`):**
  the human without a controller, the controller with one. The review worker runs its skill in full, puts the report to its addressee —
  in controller mode as text, as a file the notice names — and posts to the PR itself once released.
- A research session plans or researches for its owner, writes no product code and
  opens no PR; its result goes to the issue its order names.
  A skill delivers a role's mechanics, never its casting; deriving your seat from a skill is how you
  take on someone else's.
- **The controller checks instead of waiting for a report,** at the head: the PR stands, the head
  gated under "How tested" is the head (or differs only by the `.agents/rules/pr.md` § "Test Runs" exception), and the
  review waves the mode requires are evidenced (the wave report for `hard`, the counter-wave for
  `light` and `once`). Fixed check questions per running order: done? going in circles? progress?
  next step? is the order still the one given?
- **A worker is frozen only once nothing waits for it** — freezing guards against its drifting past
  the reviewed commit, and an instruction delivered after the freeze defeats that just as surely;
  check its queue, let it drain, then freeze
  and verify at the head.
- **A controller's successor reads this file by section:** at its start this section and the
  file's `##` headings as index, receipted by section name (`.agents/rules/session.md` § "Session Receipt"); any other section before the
  step it rules, and the whole file before opening, editing or readying a PR.
- At its `rotateAt` mark a kind acts by its `atMark`. `compact`: it saves
  (`bash .claude/hooks/session-state.sh save` until exit 0, the check line at its carrier, "Gesichert" to
  its owner, `.agents/rules/pr.md` § "Session Traffic") and compacts instead of being handed over;
  where its tool does not trigger `/compact` (the places bg, hl and web), it reports `net` after
  saving, works on and saves again at the second notice. `rotate`: it saves and is handed over — a
  working session writes a handover into its PR body, the design session into its tracking issue, the
  research session into the issue of its order, the review session as a comment on the PR —; it
  starts its successor itself where its tool allows it, otherwise it reports `successor` and its owner
  starts the successor. `notice`: it only reports.
- A session's state has one place, the body of its issue or PR (`.agents/rules/pr.md` § "Dev Session");
  where the seat owns no body (the review session, the status comment) one comment, edited in place.
- **Every cut session starts its successor itself** — the same skill line, under the same owner
  where it has one (§ "Steering Messages", the tool's capabilities) —, names it at its carrier and
  hands back "Rotation ready" with the link and the successor's name; the successor holds the seat
  once it has read its start and the hand-back at the carrier (`bash .claude/hooks/session-state.sh restore
  --from <carrier>`, its restore file read in full), and then ends its predecessor,
  the maintainer's standing yes under core rule 5, through the session-delivery tool.
- **The cut of a steering session needs no handoff file — never less than a clean, complete
  handover:** the cut comes only after it. Everything open goes to its carrier
  (core rule 11); the successor starts with its start line
  alone and reads the state itself — playbook, skills, issues, PRs; no carried file, reference,
  template or summary of the predecessor's. Whatever it has to ask its predecessor is a finding: a
  point without a carrier. A handoff is written only where state would otherwise be lost: subject
  matter only (done, open, decisions, per worker branch, head and PR, next step) in the tracking
  issue — open points in its body; done, decisions, per worker branch, head and PR and the next
  step in its status comment; the `chat-handoff` skill carries the mechanics.
- **A steering session runs the completeness check before its cut** (`chat-handoff`, step 2). Each
  open point it finds goes as a checkbox under `## Open points` of its tracking issue. The section
  `## Hand-back` in that body holds only the latest cut and is replaced at each one: a check line
  (stamp, session, number of points carried, or "none"), the check line of the last save (`checked: <UTC> ·
  cursor: <transcript> L<n> <uuid>`) and the line "Rotation ready" with the successor. The status comment carries neither an open point nor the hand-back. `## Hand-back`
  holds for steering sessions only; a working session keeps its place — the PR body, the design
  session its tracking issue, the review session a comment on the PR.
- **A predecessor is cleared only after its hand-back** (§ "Steering Messages"); one cut by rotation
  is ended by its successor. Before ending a session, the controller confirms at its carrier the
  session's list of points that were open and stood nowhere (`chat-handoff`, step 2). The controller
  clears finished sessions itself — it ends them with the session-delivery tool, then clears them
  away — a session it commissioned is not foreign to it under core rule 5; design and review
  sessions stay until their decision stands, and both until the design session's second look before
  the merge ends where the controller wants one — its findings are a new review round
  (`controller-mode`). Restart after a crash is for crash victims only, never for a session stopped
  on purpose. A predecessor's sessions pass to the successor, which takes them over in the tool at
  its start (passing ownership, `controller-mode` step 1) and then clears them as its own.
- **Finish before you start:** a direct order of the maintainer always comes first; otherwise
  the controller finishes its open assigned points before commissioning anything new.
- **Status form:** Stand · Prio · Plan · offene Entscheidungen — one status comment per tracking
  issue, edited by the controller, carrying the state of every PR; a decision
  listed there is a notice, its carrier stays `## Open points`.
- A cleanup order (closing issues, removing branches or sessions) carries the protection of every
  "DO NOT CLOSE" / "DO NOT MERGE" note along.
- **Shared seat:** where two controllers work in one repo, the one that commissioned a PR's dev
  session holds that PR's body, merges it and closes its tracking issue; the other touches it only
  after a handover.
- `Seat: <seat>` (no counter) under `## Seats`: only the controller writes it.

## Steering Messages

Additive to `.agents/rules/pr.md` § "Session Traffic"; the same messages travel:

- **Start** — besides the skill line a session is created or restarted with, the start may carry what
  § "Controller Mode" says.
- **Hand-back** — "Rotation ready" with the link and the successor's name is the hand-back of a
  session that is cut (§ "Controller Sessions"); a reviewer hands back with `#N approved <sha>`;
  for a steering session the carrier is the section `## Hand-back` in the body of its tracking issue.
- **Review report and release** — the reviewer sends its report as a file to its addressee
  (§ "Controller Sessions"), the addressee sends back the release; a clean round and mode `once`
  need none (`pr-poll-review`).
- **Change of direction** — passing an order of the maintainer on verbatim needs no approval;
  whatever is added to it is put to the maintainer first.
- **Hint or halt** — to one session, and only where it changes that session's next step.
- **Review loop** — each of the two named to the other by the controller; the receiver starts on it.
- **No owner polls for states:** what is finished it reads in issues and PRs, what is running it
  asks the responsible session about, specifically. The orchestrator, where one steers the
  controllers, sends only orders and answers and asks for no confirmations or status rounds.
- **The tool's capabilities** the playbook relies on, named here once: start a session, say whether
  it runs, report its end, ask (expecting an answer), send (expecting none), say which session holds
  a seat, end a session, pass a session's ownership, and list the inputs a session received by
  origin (the maintainer, another session). Which command does what stands in the
  tool's own operating documentation and in the start (§ "Controller Mode"), never in the playbook.

## Delivery and Change of Owner

- From the successor's start to the predecessor's end the predecessor answers no message any more,
  carries it to its carrier and names the successor to the sender. Where the tool refuses the
  successor the predecessor's end, the successor reports "stuck", naming the predecessor, to its
  owner, without one to the maintainer, and tries nothing else to end it (core rule 5).
- A controller's successor takes over its predecessor's sessions (§ "Controller Sessions"); where an
  owner drops out without a successor, the questions of its sessions go to the owner above, last to
  the maintainer.

## After the End

- A hand-back holds once it stands at the carrier and, where there is an owner, is reported. Its
  form is the one of § "Steering Messages" — "Rotation ready" with the link and the successor's name for a session
  that is cut —, and a start may not set another; the session's phase in the tool (such as
  "working") does not refute it. A receiver unsure whether a message is the hand-back asks its
  sender at once, directly (`.agents/rules/pr.md` § "Session Traffic"), instead of waiting or looking later. Once
  the hand-back holds, the receiver ends the session with the tool — in controller mode a dev
  session only after the merge, since it stays for the review loop; a design or review session only
  after the second look where the controller wants one (§ "Controller Sessions"); a session cut by
  rotation is ended by its successor instead.
- A successor starts only once the handover stands at the carrier — for a session cut by rotation
  the hand-back, which names the successor, follows the start —, or on its absence after a crash
  (below), and reads it there; nobody waits idle or polls for a message.
- Where a finished session's hand-back is missing at its carrier (a crash), its state counts as
  unknown: the owner or successor reads the carrier, the branch and the git log, and asks as above
  — for an ended session, up its own owner chain — before building on it.

## Controller Mode

Started with the skill line of `controller-mode` (`lite` appended for § "Controller Lite"); the
start lines of every seat stand once, in that skill's start-line table. Besides the skill line the
start may carry the sender, the session-delivery tool's reporting commands (§ "Steering Messages"),
the maintainer's order verbatim and, for the reviewer of the review loop, the dev's name, and
nothing else. A controller started without an order of its own — the maintainer gives it in the
window — reads the playbook, gives its receipt and waits: it reads and prioritises nothing open and
starts no worker without the maintainer's order. A controller's successor takes the open orders at
its tracking issue (the body, `## Order`) and the sessions it takes over as its order, and waits
only without such. A controller works only its assigned points and takes up no old order line its
assigner has not named. Standing orders of the maintainer stand verbatim at a carrier the session
reads (the tracking issue's body or the repo's `CLAUDE.md`); one that stands at no such carrier yet
travels verbatim with the start until it does.

- The controller holds the `maintainer` seat in full, the merge included. It commissions and decides design rounds, decides
  by `.agents/rules/code.md` § "Simplicity" and `.agents/rules/chat.md` § "Working With the Maintainer", and merges — everything but the list
  in `.agents/rules/pr.md` § "Controller Mode". What goes to that list is passed on through the orchestrator where one steers the controllers.
- **The chain: design → dev → review, each a fresh session.** The design session runs the design
  round, the decision log, the tracking issue and the spec file, and pushes them on a branch linked
  in the tracking issue; its questions go to the controller. The controller starts the dev session
  and the review session with their start lines (`controller-mode`). Every mandatory step of the
  playbook and the skills stays; only the seats are cast differently.
- After three fix rounds on one PR without an approve (mode `once`: a blocked round 3 goes to the
  maintainer instead), or once the same bug class is a blocking finding in two rounds in a row (a
  circle), the review loop halts: the controller re-assesses the
  approach (the finding's search, a design question or a new cut of the task) and steers, with the
  decision noted on the tracking issue — a status alone, and carrying on, is not enough.
- At `state:merge-ready` the tracking issue gets a short guide for the maintainer: what is new, why,
  where, and the commands to try it.

## Controller Lite

With `lite`, design and review run with the maintainer in the window — every re-review round too,
each in a fresh session; the controller starts the dev session, checks and merges. Every round keeps
its ledger file as `ccweb-prompt` and `pr-poll-review` say.
