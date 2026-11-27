#!/usr/bin/env bash
#
# Stop hook — places a missing copy of pb-hook beside the checked-in programs (ww3d/playbook#734, decision 29).
# Generic, byte-identical across consumers. The turn end's check runs in that copy, so a session that started
# without it is healed here. Says nothing and never blocks.

# shellcheck source=SCRIPTDIR/lib/pb-copy.sh
if . "${BASH_SOURCE[0]%/*}/lib/pb-copy.sh" 2>/dev/null; then pb_copy_if_missing || true; fi
exit 0
