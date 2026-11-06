# shellcheck shell=bash
# shellcheck disable=SC2034 # hd_out and sub_out are the results the sourcing hook reads
#
# Heredoc recognition sourced by guard-kill.sh and require-rule-read.sh (ww3d/playbook#511, #544). Bash builtins only.
#
#   strip_heredocs <text>   sets hd_out: the text with each heredoc body that only data takes blanked
#   subst_only <text>       sets sub_out: the text with all but its command substitutions blanked
#   only_listed <text>      0 when every command in the text is one of listed_re

# Text the shell does not run (ww3d/playbook#511). A here-document's body is data for its command: a quoted one
# (`<<'EOF'`) is dropped, an unquoted one keeps only its command substitutions. Where a command outside the
# bodies is not on the list below (`bash <<EOF`, `cat <<EOF | sh`), every body is code and stays; a delimiter that
# never comes leaves the text as it is.
# shellcheck disable=SC2016 # `$(` is searched for as text
subst_only() { # text -> global sub_out: what lies outside $(...) and backticks blanked, each substitution a statement
  local rest="$1" out="" pre s c i depth
  local blank='[[:space:];|&(){}"'"'"']'
  while :; do
    pre="${rest%%[\$\`]*}"
    if [ "$pre" = "$rest" ]; then out+="${rest//$blank/_}"; break; fi
    out+="${pre//$blank/_}"; rest="${rest:${#pre}}"
    if [ "${rest:0:1}" = '`' ]; then
      s="${rest:1}"; pre="${s%%\`*}"
      if [ "$pre" = "$s" ]; then out+="$rest"; break; fi
      out+=" ; ${pre} ; "; rest="${s:${#pre}+1}"
    elif [ "${rest:0:2}" = '$(' ]; then
      # The closing bracket is found by jumping from bracket to bracket, not character by character.
      depth=1; i=2; s="${rest:2}"
      while [ "$depth" -gt 0 ]; do
        pre="${s%%[()]*}"; [ "$pre" != "$s" ] || break
        c="${s:${#pre}:1}"; s="${s:${#pre}+1}"; i=$((i + ${#pre} + 1))
        if [ "$c" = '(' ]; then depth=$((depth + 1)); else depth=$((depth - 1)); fi
      done
      if [ "$depth" -gt 0 ]; then out+="$rest"; break; fi
      out+=" ; ${rest:2:i-3} ; "; rest="${rest:i}"
    else
      out+='$'; rest="${rest:1}"
    fi
  done
  sub_out="$out"
}
# A body stays text only where every command outside the bodies is one of a fixed list that takes it as data or
# never reads it (ww3d/playbook#511, decision 6511373160): any other word at a command position - a variable, a
# substitution, a wrapper, an unlisted name with `<` or `>` stuck to it - may run a body, so all of them stay code.
# A statement of assignments alone runs nothing either (ww3d/playbook#544). Names compare without case.
listed_re='^[[:space:]]*([a-z_][a-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:]]*/)?(cat|tee|echo|printf|git|gh|jq|true|cd|pushd|popd|mkdir|ls|pwd|touch|cp|mv|test|\[)([[:space:]<>]|$)'
hd_assign_re='^[[:space:]]*([a-z_][a-z0-9_]*=[^[:space:]]*[[:space:]]*)+$'
only_listed() { # text outside the bodies -> 0 when every command in it is a listed one
  local s="${1,,}" out="" pre q span seg
  s="${s//\\$'\r\n'/ }"
  s="${s//\\$'\n'/ }"
  # An escaped character is no quote; a quoted span holds no command, a double-quoted one only its substitutions.
  s="${s//\\?/_}"
  while :; do
    pre="${s%%[\"\']*}"
    if [ "$pre" = "$s" ]; then out+="$s"; break; fi
    out+="$pre"; q="${s:${#pre}:1}"; s="${s:${#pre}+1}"
    span="${s%%"$q"*}"
    if [ "$span" = "$s" ]; then out+="${q}${s}"; break; fi
    if [ "$q" = '"' ] && [[ $span == *[\$\`]* ]]; then out+=" ${span} "; else out+=_; fi
    s="${s:${#span}+1}"
  done
  # A redirection (`2>&1`, `&>f`) and `${x}` are no separators; every other one starts a command.
  out="${out//>&/>_}"; out="${out//<&/<_}"; out="${out//&>/_>}"; out="${out//\$\{/\$_}"
  out="${out//\$(/$'\n'}"; out="${out//[;|&(){\}\`]/$'\n'}"
  while IFS= read -r seg; do
    seg="${seg%$'\r'}"
    [[ $seg == *[![:space:]]* ]] || continue
    [[ $seg =~ $listed_re || $seg =~ $hd_assign_re ]] || return 1
  done <<<"$out"
}
# The operators of a line, read where the shell reads them: a quoted span and a comment hold none, but the quoted
# word right after `<<` is the delimiter and stays, and in a double-quoted span only its substitutions stay readable,
# even when one closes on a later line. Any other unterminated quote ends the search (its body stays code).
keep_substs() { # text -> global ks_out: all but its $(...) and backtick substitutions blanked
  local s="$1" out="" pre c rest depth i
  while :; do
    pre="${s%%[\$\`]*}"
    if [ "$pre" = "$s" ]; then out+="${s//?/_}"; break; fi
    out+="${pre//?/_}"; s="${s:${#pre}}"
    if [ "${s:0:2}" = '$(' ]; then
      depth=1; i=2; rest="${s:2}"
      while [ "$depth" -gt 0 ]; do
        pre="${rest%%[()]*}"; [ "$pre" != "$rest" ] || break
        c="${rest:${#pre}:1}"; rest="${rest:${#pre}+1}"; i=$((i + ${#pre} + 1))
        if [ "$c" = '(' ]; then depth=$((depth + 1)); else depth=$((depth - 1)); fi
      done
      if [ "$depth" -gt 0 ]; then out+="$s"; break; fi
      out+="${s:0:i}"; s="${s:i}"
    elif [ "${s:0:1}" = '`' ]; then
      rest="${s:1}"; pre="${rest%%\`*}"
      if [ "$pre" = "$rest" ]; then out+="$s"; break; fi
      out+="\`${pre}\`"; s="${rest:${#pre}+1}"
    else
      out+=_; s="${s:1}"
    fi
  done
  ks_out="$out"
}
ops_text() { # line -> global ops_out
  local s="$1" out="" pre c span
  local dq_re='^(([^"\\]|\\.)*)"'
  while :; do
    pre="${s%%[\"\'#\\]*}"
    if [ "$pre" = "$s" ]; then out+="$s"; break; fi
    out+="$pre"; c="${s:${#pre}:1}"; s="${s:${#pre}+1}"
    case "$c" in
      \\) out+="\\${s:0:1}"; s="${s:1}" ;;
      '#')
        if [ -z "$out" ] || [[ ${out: -1} == [[:space:]] ]]; then break; fi
        out+='#' ;;
      *)
        if [ "$c" = '"' ]; then
          if ! [[ $s =~ $dq_re ]]; then
            if [[ $s == *'$('* || $s == *\`* ]]; then keep_substs "$s"; out+="\"$ks_out"; fi
            break
          fi
          span="${BASH_REMATCH[1]}"
        else span="${s%%"$c"*}"; [ "$span" != "$s" ] || break; fi
        if [[ $out =~ \<\<-?[[:space:]]*$ ]]; then out+="${c}${span}${c}"
        elif [ "$c" = '"' ] && [[ $span == *'$('* || $span == *\`* ]]; then keep_substs "$span"; out+="\"${ks_out}\""
        else out+=_; fi
        s="${s:${#span}+1}" ;;
    esac
  done
  ops_out="$out"
}
strip_heredocs() { # text -> global hd_out
  hd_out="$1"
  [[ $1 == *'<<'* ]] || return 0
  local -a lines dash quoted delim
  local line out="" outside="" rest body cmp j k=0 n found
  local op_re='(^|[^<])<{2}(-?)[[:space:]]*(\\?)(["'"'"']?)([^][:space:];|&<>()"'"'"'\\]+)(["'"'"']?)'
  mapfile -t lines <<<"$1"
  n=${#lines[@]}
  while [ "$k" -lt "$n" ]; do
    line="${lines[k]}"; k=$((k + 1))
    out+="${line}"$'\n'; outside+="${line}"$'\n'
    # A trailing backslash continues the command: the bodies start only after its last line.
    while [[ ${line%$'\r'} == *\\ ]] && [ "$k" -lt "$n" ]; do
      line="${line%$'\r'}"; line="${line%\\} ${lines[k]}"
      out+="${lines[k]}"$'\n'; outside+="${lines[k]}"$'\n'; k=$((k + 1))
    done
    ops_text "$line"; rest="$ops_out"; dash=(); quoted=(); delim=()
    while [[ $rest =~ $op_re ]]; do
      dash+=("${BASH_REMATCH[2]}"); delim+=("${BASH_REMATCH[5]}")
      if [ -n "${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[6]}" ]; then quoted+=(1); else quoted+=(0); fi
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    [ "${#delim[@]}" -gt 0 ] || continue
    for ((j = 0; j < ${#delim[@]}; j++)); do
      body=""; found=0
      while [ "$k" -lt "$n" ]; do
        line="${lines[k]}"; k=$((k + 1))
        cmp="${line%$'\r'}"
        if [ -n "${dash[j]}" ]; then cmp="${cmp#"${cmp%%[!$'\t']*}"}"; fi
        if [ "$cmp" = "${delim[j]}" ]; then found=1; break; fi
        body+="${line}"$'\n'
      done
      [ "$found" = 1 ] || return 0
      if [ "${quoted[j]}" = 1 ]; then out+=$'\n'
      else subst_only "$body"; out+="${sub_out}"$'\n'; fi
    done
  done
  # A command outside the bodies that is not on the list may run one of them, however the lines are joined.
  only_listed "$outside" || return 0
  hd_out="${out%$'\n'}"
}
