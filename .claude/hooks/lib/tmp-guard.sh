# shellcheck shell=bash
# shellcheck disable=SC2034 # tg_hits, tg_escape and tg_scratch are the results the sourcing script reads
#
# Detection of the shared-temp guard (ww3d/playbook#619), sourced by guard-shared-tmp.sh and by the replay script
# tests/replay-tmp-guard.sh, so both run the same code. Needs bash 5; lib/heredoc.sh and lib/segments.awk are read
# from $tg_lib (default: the folder of this file).
#
#   tg_init <session_id> <scratchpad_dir>   the session's own area
#   tg_detect <tool> <file_path|command>    sets tg_hits: the writes onto a fixed path under a shared root and
#                                           outside the own area, one resolved path each; status 1 = the splitter failed
#   tg_find_scratch                         sets tg_scratch: the session's scratchpad, empty where none is known
#   tg_escape_for <path>                    sets tg_escape: the way out for one hit
#
# A hit is a write (never a read) to a fixed path (no changing part) under a shared root, outside the own area.
# A write in a shell command is one of the places in tg_record, read from the command's words (a quoted text, a
# comment and a heredoc body are no words). All forms are compared as lower-case Git Bash paths (`D:\tmp\x` and
# `/d/tmp/x` meet); a doubt lets the call pass.

tg_lib="${tg_lib:-${BASH_SOURCE[0]%/*}}"
# shellcheck source=SCRIPTDIR/heredoc.sh
. "$tg_lib/heredoc.sh" 2>/dev/null || { strip_heredocs() { hd_out="$1"; }; strip_herestrings() { hd_out="$1"; }; }

tg_mentions() { # text -> 0 where it holds a shared root or a temp variable: only then is a call worth a closer look
  local rc=1
  shopt -s nocasematch
  # shellcheck disable=SC2016 # `$TMP` and the like are searched for as text
  case "$1" in
    */tmp[!A-Za-z0-9]*|*\\tmp[!A-Za-z0-9]*|*/temp[!A-Za-z0-9]*|*\\temp[!A-Za-z0-9]*|*'$TMP'*|*'$TEMP'*|*'${TMP'*|*'${TEMP'*|*'$env:TMP'*|*'$env:TEMP'*|*%TMP%*|*%TEMP%*) rc=0 ;;
  esac
  shopt -u nocasematch
  return "$rc"
}

tg_form() { # path -> tg_f: slashes, Git Bash drive form, lower case, no trailing slash
  local p="${1//\\//}"
  case "$p" in [A-Za-z]:/*) p="/${p:0:1}${p:2}" ;; esac
  p="${p,,}"
  while [[ $p == ?*/ ]]; do p="${p%/}"; done
  tg_f="$p"
}

tg_under() { # root, path (both tg_form results) -> 0 when path is the root or below it
  [ -n "$1" ] && { [ "$2" = "$1" ] || [[ $2 == "$1"/* ]]; }
}

tg_init() { # session_id, scratchpad_dir
  tg_sid="${1,,}"; tg_pad="$2"; tg_own=(); tg_ps=0
  local v sep=: item
  if [ -n "$tg_pad" ]; then tg_form "$tg_pad"; tg_own+=("$tg_f"); fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then tg_form "$CLAUDE_PROJECT_DIR"; tg_own+=("$tg_f"); fi
  if [ -n "${PLAYBOOK_TMP_GUARD_OWN:-}" ]; then
    # The list separator is the one of PATH on the platform: `;` where drive letters carry a colon.
    case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) sep=';' ;; esac
    v="${PLAYBOOK_TMP_GUARD_OWN}$sep"
    while [ -n "$v" ]; do
      item="${v%%"$sep"*}"; v="${v#*"$sep"}"
      if [ -n "$item" ]; then tg_form "$item"; tg_own+=("$tg_f"); fi
    done
  fi
}

tg_is_own() { # tg_form result -> 0 when inside the own area
  local o
  if [ -n "$tg_sid" ] && [[ $1 == *"$tg_sid"* ]]; then return 0; fi
  for o in "${tg_own[@]}"; do if tg_under "$o" "$1"; then return 0; fi; done
  return 1
}

tg_is_shared() { # tg_form result -> 0 when under a shared root with a name below it
  case "$1" in /tmp/?*|/?/tmp/?*|*/appdata/local/temp/?*|/?/windows/temp/?*) return 0 ;; esac
  return 1
}

# A word that starts with a temp variable, resolved with the value in this process (tg_w); status 1 where the
# variable has no value, so the path cannot be known. Every other word passes unchanged.
tg_expand() { # word -> tg_w
  local w="$1" name rest val def="" has_def=0
  tg_w="$w"
  # `$TEMP` and `${TMP}` name the environment in bash only, and only in capitals (`$tmp` is the script's own variable);
  # `$env:TEMP` is PowerShell's environment, `%TEMP%` cmd's.
  if [ "$tg_ps" != 1 ] && [[ $w =~ ^\$\{(TMPDIR|TEMP|TMP)(:-([^\}]*))?\}(.*)$ ]]; then
    name="${BASH_REMATCH[1]}"; def="${BASH_REMATCH[3]}"; rest="${BASH_REMATCH[4]}"
    [ -z "${BASH_REMATCH[2]}" ] || has_def=1
  elif [ "$tg_ps" != 1 ] && [[ $w =~ ^\$(TMPDIR|TEMP|TMP)([^A-Za-z0-9_].*)?$ ]]; then
    name="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
  else
    shopt -s nocasematch
    if [[ $w =~ ^\$env:(TEMP|TMP|TMPDIR)([^A-Za-z0-9_].*)?$ ]]; then
      name="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    elif [[ $w =~ ^%(TEMP|TMP)%(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
    else
      shopt -u nocasematch; return 0
    fi
    shopt -u nocasematch
  fi
  name="${name^^}"
  case "$name" in TMPDIR) val="${TMPDIR:-}" ;; TEMP) val="${TEMP:-}" ;; TMP) val="${TMP:-}" ;; esac
  if [ -z "$val" ] && [ "$has_def" = 1 ]; then val="$def"; fi
  [ -n "$val" ] || return 1
  tg_w="${val%[/\\]}${rest}"
  return 0
}

tg_classify() { # word -> 0 and tg_hit_path when the word is a hit
  local w="$1"
  case "$w" in ''|*/|*\\) return 1 ;; esac
  tg_expand "$w" || return 1
  w="$tg_w"
  # A changing part, a glob, a name made by mktemp or a step up is no fixed name.
  case "$w" in *'$'*|*'`'*|*'*'*|*'?'*|*mktemp*|*..*) return 1 ;; esac
  tg_form "$w"
  tg_is_shared "$tg_f" || return 1
  tg_is_own "$tg_f" && return 1
  tg_hit_path="$w"
  return 0
}

# --- the write places of a shell command ---------------------------------------------------------------------------
# `-o` names a file for most programs; for these it is a switch or an option of another kind.
tg_o_other=" grep egrep fgrep rg ag ack ls ps find ssh scp sftp sed cut tar xargs "
# PowerShell switches take no value: the word behind one is not its value.
tg_switches=" -append -force -noclobber -nonewline -whatif -confirm -passthru -recurse -container -usetransaction -wait -nonewwindow "

tg_add() { tg_cands+=("$1"); }

# Splits the words behind a command word: tg_args are the words that are no flag and no value of one, tg_flags the
# lower-cased `flag=value` entries (`flag=` where it has no value).
tg_split_args() { # words...
  local w lw
  tg_args=(); tg_flags=()
  while [ $# -gt 0 ]; do
    w="$1"; lw="${w,,}"; shift
    case "$w" in
      --) tg_args+=("$@"); return 0 ;;
      -?*:*) tg_flags+=("${lw%%:*}=${w#*:}") ;;
      -?*=*) tg_flags+=("${lw%%=*}=${w#*=}") ;;
      -?*)
        if [[ $tg_switches == *" $lw "* ]] || [ $# -eq 0 ] || [[ $1 == -* ]]; then tg_flags+=("$lw=")
        else tg_flags+=("$lw=$1"); shift; fi ;;
      *) tg_args+=("$w") ;;
    esac
  done
}

tg_flag() { # flag names (lower case)... -> tg_fv: the value of the first one that has one; status 1 when none does
  local f n
  tg_fv=""
  for n in "$@"; do
    for f in "${tg_flags[@]}"; do
      if [ "${f%%=*}" = "$n" ] && [ -n "${f#*=}" ]; then tg_fv="${f#*=}"; return 0; fi
    done
  done
  return 1
}

tg_redirects() { # words... -> the targets of `>`, `>>`, `&>`, `2>`, `>|`, stuck to the operator or the next word
  local i w rest
  for ((i = 1; i <= $#; i++)); do
    w="${!i}"
    if [[ $w =~ ^(\&\>\>?|\*\>\>?|[0-9]*\>\||[0-9]*\>\>?)(.*)$ ]]; then
      rest="${BASH_REMATCH[2]}"
      if [ -z "$rest" ]; then local j=$((i + 1)); rest="${!j:-}"; fi
      case "$rest" in ''|'&'*|'('*|' '*|'	'*) continue ;; esac
      tg_add "$rest"
    fi
  done
}

tg_record() { # one record of segments.awk -> the write targets of its command in tg_cands
  local -a f words args
  local name idx w n last lw path
  IFS=$'\037' read -r -a f <<<"${1%$'\r'}"
  name="${f[1]:-}"; idx="${f[8]:-0}"
  words=("${f[@]:10}")
  [ "${#words[@]}" -gt 0 ] || return 0
  tg_redirects "${words[@]}"
  [ "$idx" -ge 1 ] 2>/dev/null || return 0
  args=("${words[@]:idx}")
  tg_split_args "${args[@]}"
  # `--output`, `--output-document`, `-OutFile`, `-FilePath` (not where it names a program to start) and `-o`.
  case "$name" in start-process|start|saps|invoke-item|ii) ;; *)
    for n in --output --output-document -outfile -filepath; do
      if tg_flag "$n"; then tg_add "$tg_fv"; fi
    done ;;
  esac
  if [[ $tg_o_other != *" $name "* ]] && tg_flag -o; then tg_add "$tg_fv"; fi
  case "$name" in
    tee) for w in "${args[@]}"; do case "$w" in -*) ;; *) tg_add "$w" ;; esac; done ;;
    out-file|set-content|add-content)
      if tg_flag -path -literalpath -pspath; then tg_add "$tg_fv"
      elif [ ${#tg_args[@]} -gt 0 ]; then tg_add "${tg_args[0]}"; fi ;;
    new-item)
      lw=""
      if tg_flag -itemtype -type; then lw="${tg_fv,,}"; fi
      case "$lw" in directory|dir|d|junction|symboliclink|hardlink) ;; *)
        path=""
        if tg_flag -path -literalpath; then path="$tg_fv"
        elif [ ${#tg_args[@]} -gt 0 ]; then path="${tg_args[0]}"; fi
        if [ -n "$path" ] && tg_flag -name; then tg_add "${path%[/\\]}/$tg_fv"
        elif [ -n "$path" ]; then tg_add "$path"
        elif tg_flag -name; then tg_add "$tg_fv"; fi ;;
      esac ;;
    cp|mv|install)
      # `install -d` makes folders: a folder alone is no hit.
      for w in "${args[@]}"; do case "$w" in -d|--directory) return 0 ;; esac; done
      last=""
      for w in "${args[@]}"; do case "$w" in -*) ;; *) last="$w" ;; esac; done
      [ -z "$last" ] || tg_add "$last" ;;
    copy-item|move-item)
      if tg_flag -destination; then tg_add "$tg_fv"
      elif [ ${#tg_args[@]} -ge 2 ]; then tg_add "${tg_args[1]}"; fi ;;
  esac
  return 0
}

# A superset of the write places tg_record reads: without one of these words or signs in the text the splitter
# has nothing to find. Bash builtins only.
tg_may_write() { # command text -> 0 where it may hold a write place
  local t="${1,,}" nul=/dev/null
  t="${t//2>&1/}"; t="${t//>&2/}"; t="${t//&> $nul/}"; t="${t//&>$nul/}"; t="${t//> $nul/}"; t="${t//>$nul/}"
  [[ $t == *'>'* ]] && return 0
  [[ $t =~ (^|[^[:alnum:]_-])(tee|cp|mv|install|out-file|set-content|add-content|new-item|copy-item|move-item)([^[:alnum:]_-]|$) ]] && return 0
  [[ $t =~ (^|[[:space:]])-(o|outfile|filepath)([^[:alnum:]_]|$) ]] && return 0
  [[ $t == *--output* ]] && return 0
  return 1
}

tg_shell_targets() { # command, powershell(0|1) -> tg_cands; status 1 where the splitter failed
  local rec out
  tg_cands=(); tg_ps="$2"
  tg_may_write "$1" || return 0
  if [ "$2" = 1 ]; then strip_herestrings "$1"; else strip_heredocs "$1"; fi
  out="$(SEG_PS="$2" LC_ALL=C ${tg_timeout:+timeout "$tg_timeout"} awk -f "$tg_lib/segments.awk" <<<"$hd_out" 2>/dev/null)" || return 1
  while IFS= read -r rec; do
    [ -n "$rec" ] || continue
    tg_record "$rec"
  done <<<"$out"
  return 0
}

tg_detect() { # tool, file_path|command
  local c seen=" "
  tg_hits=(); tg_cands=()
  case "$1" in
    Write|Edit|NotebookEdit) tg_cands=("$2") ;;
    Bash) tg_shell_targets "$2" 0 || return 1 ;;
    PowerShell) tg_shell_targets "$2" 1 || return 1 ;;
    *) return 0 ;;
  esac
  for c in "${tg_cands[@]}"; do
    if tg_classify "$c"; then
      case "$seen" in *" $tg_hit_path "*) ;; *) seen+="$tg_hit_path "; tg_hits+=("$tg_hit_path") ;; esac
    fi
  done
  return 0
}

# The scratchpad is the envelope's field, else `<temp>/claude/*/<session_id>/scratchpad` where that folder exists.
tg_find_scratch() { # sets tg_scratch
  local root d
  tg_scratch="$tg_pad"
  [ -z "$tg_scratch" ] || return 0
  [ -n "$tg_sid" ] || return 0
  for root in "${TMPDIR:-}" "${TEMP:-}" "${TMP:-}" /tmp; do
    [ -n "$root" ] || continue
    root="${root//\\//}"
    for d in "${root%/}"/claude/*/"$tg_sid"/scratchpad; do
      if [ -d "$d" ]; then tg_scratch="$d"; return 0; fi
    done
  done
  return 0
}

tg_escape_for() { # hit path -> tg_escape: the file name inside the scratchpad, else a name of the session's own
  local name="${1//\\//}"
  name="${name##*/}"
  if [ -n "$tg_scratch" ]; then tg_escape="${tg_scratch%[/\\]}/$name"
  else tg_escape="a name with your session id (${tg_sid:-<session_id>}-$name) or one from mktemp"; fi
}

tg_js() { # string -> tg_j: the JSON string literal
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"
  case "$s" in *[$'\001'-$'\037\177']*) s="${s//[$'\001'-$'\037\177']/ }" ;; esac
  tg_j="\"$s\""
}
