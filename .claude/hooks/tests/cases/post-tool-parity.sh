#!/usr/bin/env bash
# Hook suite section: pb-hook post-tool answers like record-rule-read.sh and remind-before-compact.sh
# (ww3d/playbook#734)
# Run alone: bash .claude/hooks/tests/cases/post-tool-parity.sh [section ...]
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../parity.sh
. "$(dirname "${BASH_SOURCE[0]}")/../parity.sh" post-tool "$@"
