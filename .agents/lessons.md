# Lessons

Lessons from past sessions, each standing once, numbered, with the roles it holds for. A skill loads
its role's entries: `pwsh scripts/common/get-lessons.ps1 -Role <role>`; without pwsh, read the
entries whose `gilt fuer` names the role or `alle`. Where a lesson became a rule, its entry names the
place and the rule stands there alone. Stack lessons stand in the tech overlays
(`tech/common/powershell.md`, `tech/common/dotnet.md`); where a lesson came from is recorded in the
playbook's provenance file.

## L04 — Test windows stay invisible

gilt fuer: dev, review

A test that opens a window or console starts it without focus and off the visible desktop — the
maintainer works at the same machine.

## L05 — Questions are answered where they stand

gilt fuer: alle

Comments of the maintainer in issues, PRs and shared pages are inputs: read them regularly and answer
them where they stand, at once.

## L08 — Gate commands are checked on main first

gilt fuer: design, controller

A gate command named in an order is run against `main` before the order goes out — a command already
red on `main` blocks the worker.

## L09 — No long remaining work for a full session

gilt fuer: controller

A worker past ~70 % context gets no long remaining work; it is relieved before, not in the middle of a
review wave.

## L12 — A background run wakes nobody

gilt fuer: alle

A session waiting on its own background run follows it actively to its end and acts then — the end
of a background run does not wake an idle session.

## L14/29 — Time from the clock

gilt fuer: alle

Time from `date -u` stands in `AGENTS.md` § "Talking to the Maintainer" and `.agents/rules/docs.md`
§ "Timestamps in File Names". Beyond it: never take the environment's date hint, nor estimate or
compute a time by hand; numbers are counted, not estimated.

## L15 — Full SHA for head-matched merges

gilt fuer: controller

Stands in `.agents/rules/pr.md` § "Merge".

## L19 — Open decisions in one place

gilt fuer: alle

Stands in `AGENTS.md` § "Talking to the Maintainer".

## L20 — A green build is not the real run

gilt fuer: alle

Stands in `AGENTS.md` § "Working Mode".

## L21 — "Verified" only with quoted code lines

gilt fuer: alle

Stands in `AGENTS.md` § "Working Mode".

## L22 — Model choice against the issue body

gilt fuer: controller

Stands in `AGENTS.md` § "Models" (a dated order of the maintainer overrides).

## L23 — A delayed run contains main, and runs alone

gilt fuer: dev, controller

Before a delayed run, check that its head contains the current `main`; a run script is never chained
automatically to publish or other follow-up steps.

## L24/63/67 — Watchers end, and lose what they do not track

gilt fuer: alle

A background waiter ends at the harness's deadline — re-arm it consciously for long runs, or use a
schedule. A watch that ends at the first hit loses later events: remember seen ids and keep running.
A stopped or expired monitor may leave its shell loop running on Windows: build watches with an owner
file that ends older instances, and with a deadline of their own.

## L26 — Cheap checks before push and full run

gilt fuer: dev

Format, comment length and class size run in the filtered set before every push and before the full
run, and again at once after a merge of `main` that touches the same class. A split follows the
subject, not only the line count.

## L32 — Pull main before the gate run

gilt fuer: dev

`main` is merged in before the gate run, not after it; the repo's guard classes join every class run
(`.agents/rules/pr.md` § "Test Runs").

## L34 — Sub-agent files go to the scratchpad

gilt fuer: alle

Stands in `AGENTS.md` § "Sub-Agents".

## L36 — Sub-agents outlive their parent

gilt fuer: alle

Stands in `AGENTS.md` § "Sub-Agents".

## L38 — A push after the approve dismisses it

gilt fuer: review, controller

Stands in `.agents/rules/review.md` § "Review Comments".

## L40 — One agent per tree for runs and probes

gilt fuer: review, dev

Stands in `AGENTS.md` § "Sub-Agents".

## L46/50 — Research before closing, run every probe

gilt fuer: alle

The research before closing an issue stands in `.agents/rules/carrier.md` § "Carrier Requirement".
An expected mutation probe is run, never assumed: a probe that should turn red and stays green finds
the real fault.

## L47 — A restarted watcher keeps its last position

gilt fuer: controller

A watcher on PR comments that restarts continues from the time of its last find, never from "now" —
whatever came in between is lost otherwise.

## L48 — Draft PR early

gilt fuer: alle

Stands in `.agents/rules/pr.md` § "PR Lifecycle", step 1.

## L54 — Report branches go after the report stands

gilt fuer: controller

A reviewer's report branch is deleted only once its report stands at the PR.

## L57 — Nothing only in an artifact

gilt fuer: alle

Stands in `AGENTS.md` § "Core Rules", rule 11: content sessions need stands in the repo or an issue —
a shared page from an account can become unreadable after an account change.

## L59 — A merge request from above is checked first

gilt fuer: controller

A merge request from a steering session is checked at the PR before it is carried out; locations are
never passed on from memory — `git grep` first.

## L60 — Changing red tests are not load

gilt fuer: dev, review

Red tests that change from run to run at the same head without load are a finding with an open
cause, never explained away as load.

## L62 — Issue bodies are changed with UTF-8 set

gilt fuer: alle

Change issue bodies from PowerShell with UTF-8 set and compare the length before the PATCH; `sed`
from Git Bash breaks UTF-8.

## L65 — Issue bodies have a length limit

gilt fuer: alle

Stands in `.agents/rules/carrier.md` § "Tracking Issue".

## L66 — ID ranges for parallel PRs

gilt fuer: design, controller

Stands in `.agents/rules/audit.md` § "Design Round".

## L69 — `gh api --jq` has no `--arg`

gilt fuer: alle

`gh api --jq` takes no jq variables; a filter built on `--arg` stays silently empty — build the
comparison without jq variables.

## L74 — Prepared orders are re-addressed

gilt fuer: controller

An order a predecessor prepared names its controller: before it starts, the current controller is
set as addressee and the order is checked against the current playbook.

## L75 — The ruleset wants a current branch

gilt fuer: review, controller

Stands in `.agents/rules/review.md` § "Review Comments".

## L76 — Dead required checks

gilt fuer: controller

Stands in `.agents/rules/pr.md` § "Merge" (`--admin` with a reason on the PR).

## L77 — Platform claims are checked before agreement

gilt fuer: design, review, controller

Stands in `.agents/rules/audit.md` § "Design Round".

## L79 — `|| true` swallows the failure

gilt fuer: alle

A command guarded with `|| true` — or with a wrong flag — fails silently: read the result at its
target (the comment at the PR, the label at the issue), never from the exit code.

## L80 — Linux run after a clean delta review

gilt fuer: controller

A Linux or other long platform run starts only after a clean delta review — started in parallel it is
burnt by the next suggestion. Same-kind cases at the same place are taken along in the dev order.

## L83 — `gh` output is read as UTF-8

gilt fuer: alle

On Windows, set `[Console]::OutputEncoding` to UTF-8 before reading `gh` output, otherwise
PowerShell decodes it with the console's OEM code page and dashes turn into mojibake in the next
PATCH; this holds for `pwsh` too.
