# shellcheck shell=bash
# The session's own copy of pb-hook beside the hooks, ignored by git. The checked-in programs lie in a folder
# per platform: with a file without extension beside a .exe of the same name, Claude Code starts neither on
# Windows (docs/playbook-ops.md, bullet pb-hook).

pb_copy_paths() { # folder -> pb_copy and pb_source for this platform
  case "${OSTYPE:-}" in
    msys*|cygwin*) pb_copy="$1/pb-hook.exe" pb_source="$1/win-x64/pb-hook.exe" ;;
    *) pb_copy="$1/pb-hook" pb_source="$1/linux-x64/pb-hook" ;;
  esac
}

# Through a second name: the program is never there half written. A failure leaves things as they were (a running
# copy cannot be replaced on Windows).
pb_copy_write() {
  { cp "$pb_source" "$pb_copy.$$" && mv -f "$pb_copy.$$" "$pb_copy"; } 2>/dev/null || rm -f "$pb_copy.$$" 2>/dev/null || true
}

# For a hook that runs anyway: places a missing copy, with builtins only while it is there (ww3d/playbook#734,
# decision 26). PLAYBOOK_PB_BIN names another folder than the checkout's.
pb_copy_if_missing() {
  local dir="${PLAYBOOK_PB_BIN:-}"
  if [ -z "$dir" ]; then
    [ -n "${CLAUDE_PROJECT_DIR:-}" ] || return 0
    dir="$CLAUDE_PROJECT_DIR/.claude/hooks/bin"
  fi
  pb_copy_paths "$dir"
  if [ ! -f "$pb_copy" ] && [ -f "$pb_source" ]; then pb_copy_write; fi
}
