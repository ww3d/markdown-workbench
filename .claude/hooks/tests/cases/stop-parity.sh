#!/usr/bin/env bash
# Hook suite section: pb-hook stop answers like require-receipt.sh (ww3d/playbook#734)
# Run alone: bash .claude/hooks/tests/cases/stop-parity.sh [section ...]
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../parity.sh
. "$(dirname "${BASH_SOURCE[0]}")/../parity.sh" stop "$@"
