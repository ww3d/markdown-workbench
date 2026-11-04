#!/usr/bin/env bash
# Hook suite section: run-folder.sh, the sweep of finished runs
# Run alone: bash .claude/hooks/tests/cases/run-folder-sweep.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"
# The harness loads run-folder.sh only when a section runs alone; the sweep is this section's subject.
# shellcheck source=SCRIPTDIR/../run-folder.sh
. "$here/run-folder.sh"

echo "== run-folder.sh: the sweep removes finished runs and keeps live ones =="
age() { touch -d '5 minutes ago' "$@"; }
present() { if [ -d "$2" ]; then ok "$1" kept; else bad "$1" removed kept; fi; }
absent() { if [ -d "$2" ]; then bad "$1" kept removed; else ok "$1" removed; fi; }
sweep_base="$fix/sweep-pid"
mkdir -p "$sweep_base"/run.dead "$sweep_base"/run.live "$sweep_base"/run.fresh "$sweep_base"/run.cur
true & dead_pid=$!; wait "$dead_pid"
echo "$dead_pid" >"$sweep_base/run.dead/.pid"
# A process that lives until its stdin pipe closes: a signal, not a timer.
# shellcheck disable=SC2034 # bash uses LIVE for the coproc's pipes and sets LIVE_PID; shellcheck does not model it.
coproc LIVE { read -r _; }
# shellcheck disable=SC2153 # LIVE_PID is set by bash for the coproc above.
live_pid=$LIVE_PID
echo "$live_pid" >"$sweep_base/run.live/.pid"
# A dead PID: only the age limit may keep this one.
echo "$dead_pid" >"$sweep_base/run.fresh/.pid"
echo "$dead_pid" >"$sweep_base/run.cur/.pid"
age "$sweep_base"/run.dead "$sweep_base"/run.live "$sweep_base"/run.cur
sweep_run_folders "$sweep_base" "$sweep_base/run.cur" 0
absent 'without flock: a run whose PID is gone' "$sweep_base/run.dead"
present 'without flock: a run whose PID still lives' "$sweep_base/run.live"
present 'without flock: a run younger than a minute' "$sweep_base/run.fresh"
present 'without flock: the current run' "$sweep_base/run.cur"
kill "$live_pid" 2>/dev/null; wait "$live_pid" 2>/dev/null
if command -v flock >/dev/null 2>&1; then
  sweep_base="$fix/sweep-flock"
  mkdir -p "$sweep_base"/run.held "$sweep_base"/run.free "$sweep_base"/run.young
  : >"$sweep_base/run.free/.lock"
  : >"$sweep_base/run.young/.lock"
  # The holder says "ready" once it holds the lock, then lives until its stdin pipe closes.
  coproc HOLD { exec 8>"$sweep_base/run.held/.lock"; flock 8; echo ready; read -r _; }
  holder=$HOLD_PID
  read -r -u "${HOLD[0]}" _
  age "$sweep_base"/run.held "$sweep_base"/run.free
  sweep_run_folders "$sweep_base" "$sweep_base/run.none" 1
  present 'with flock: a run whose lock is held' "$sweep_base/run.held"
  absent 'with flock: a run whose lock is free' "$sweep_base/run.free"
  present 'with flock: a free run younger than a minute' "$sweep_base/run.young"
  kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
else
  echo '  skip with flock: flock is not installed here'
fi

finish
