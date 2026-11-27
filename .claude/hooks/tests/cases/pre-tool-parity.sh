#!/usr/bin/env bash
# Hook suite section: pb-hook pre-tool answers like the three bash guards (ww3d/playbook#734)
# Run alone: bash .claude/hooks/tests/cases/pre-tool-parity.sh [section ...]
#   all sections: bash .claude/hooks/tests/run-tests.sh
# The switches (PARITY_PART, PARITY_WORK, PARITY_FULL, PB_HOOK_BIN) stand in parity.sh.
# shellcheck source=SCRIPTDIR/../parity.sh
. "$(dirname "${BASH_SOURCE[0]}")/../parity.sh" pre-tool "$@"
