# shellcheck shell=bash
# shellcheck disable=SC2034 # hook_tmp is the result the sourcing hook reads
#
# The one temp folder of every hook file (ww3d/playbook#703, Frage 1755 a). Git Bash's own /tmp is the TEMP of
# whichever msys process made the shared region first, so it wanders between clones and the markers a hook left there
# vanish; a session's own folder is the one its environment names.
#
#   hook_tmpdir      sets hook_tmp: TMPDIR, else TMP, else TEMP; in Git Bash as a `D:/...` path (`cygpath -m`, never
#                    `/tmp/...`). None set: /tmp in a cloud session (CLAUDE_CODE_REMOTE=true), otherwise status 1,
#                    hook_tmp empty and one line on stderr per process - the caller skips its step and never blocks.
#   hook_mktemp [-d] <prefix>   mktemp inside that folder (`mktemp -p`): prints the path; status 1 without a folder.
#
# Callers: `hook_tmpdir || exit 0` in a hook, `hook_tmpdir || <skip the step>` where the step is one among others.
hook_tmpdir() {
  [ -z "${hook_tmp:-}" ] || return 0
  local d="${TMPDIR:-${TMP:-${TEMP:-}}}" drv why=""
  if [ -z "$d" ]; then
    if [ "${CLAUDE_CODE_REMOTE:-}" = true ]; then d=/tmp # tmp-ok: the cloud session has no TMPDIR, its /tmp is its own
    else why="no TMPDIR, TMP or TEMP set"
    fi
  elif [ "$OSTYPE" = msys ] || [ "$OSTYPE" = cygwin ]; then
    # Git Bash: the `D:/...` form. The common spellings by string, as the hooks start thousands of times and a
    # `cygpath` start costs; only a mount path such as /tmp needs it. No result: no folder, never the mount path.
    case "$d" in
      [A-Za-z]:*) d="${d//\\//}" ;;
      /[A-Za-z]) d="${d:1:1}"; d="${d^^}:/" ;;
      /[A-Za-z]/*) drv="${d:1:1}"; d="${drv^^}:${d:2}" ;;
      *) d="$(cygpath -m -- "$d" 2>/dev/null)" || d=""
         case "$d" in [A-Za-z]:*) ;; *) d=""; why="the temp folder cannot be written as a Windows path" ;; esac ;;
    esac
  fi
  if [ -n "$why" ] || [ -z "$d" ]; then
    if [ -z "${_hook_tmp_said:-}" ]; then
      _hook_tmp_said=1
      echo "hook ${BASH_SOURCE[-1]##*/}: ${why:-no temp folder}, a step that needs a temp folder is skipped" >&2
    fi
    return 1
  fi
  hook_tmp="${d%/}"
  return 0
}

hook_mktemp() { # [-d] prefix -> path
  local dflag=""
  if [ "${1:-}" = -d ]; then dflag=-d; shift; fi
  hook_tmpdir || return 1
  # shellcheck disable=SC2086 # dflag is empty or the one switch
  mktemp $dflag -p "$hook_tmp" "${1:-tmp}.XXXXXX"
}
