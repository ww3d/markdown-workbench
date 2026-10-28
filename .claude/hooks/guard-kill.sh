#!/usr/bin/env bash
#
# PreToolUse hook - kill guard. Generic, byte-identical across consumers.
#
# Core rule K5: "End a foreign process or a foreign AI session only after the
# maintainer's explicit yes to exactly that action." This hook is what turns the
# rule into a gate for the two shell tools (Bash, PowerShell). It recognises
# process-ending commands, nested ones included (`powershell -Command "..."`,
# `pwsh -c`, `cmd /c`, `bash -c`, a decoded `-EncodedCommand`), and answers:
#
#   ask   an ending by process number, one or several in the call (`kill 1234`, `kill 1 2`,
#         `Stop-Process -Id 1,2`, `taskkill /PID 1 /PID 2`, `kill 1; kill 2`, a CIM/WMI filter
#         on one process id) - the reason names each number. Also an ending verb whose target
#         the hook cannot read (a variable, an expression, an encoded command it cannot decode,
#         `.Kill()` in code) while the call holds no process list.
#   deny  broad ending: by name, one or several (`pkill x`, `taskkill /IM x.exe`,
#         `Stop-Process -Name x`), by pattern or filter (`pkill -f x`, `killall 'a*'`, `/IM *`,
#         `taskkill /FI`, a CIM/WMI filter on a name or command line), `kill 0` / `kill -1` / a
#         negative PID, a computed target list (`kill $(pgrep x)`), a loop or pipeline over a
#         process list (`Get-Process ... | Stop-Process`, `... | % { kill $_.Id }`,
#         `... | xargs kill`). A name hits every process of it; the reason points at the number.
#   allow anything else, silently (`kill -l`, `kill -0 1234`, every command without a verb).
#
# In a background session (CLAUDE_JOB_DIR set) every `ask` becomes `deny`: no one answers a confirmation there. The
# reason sends the question to the maintainer through the session's owner, who (or the maintainer) runs the command.
#
# A verb counts where a command can stand: at the start, after a separator (`;`, `&`, `&&`,
# `||`, `|`, an opening bracket, a backtick), after a keyword (`then`, `do`, `else`, `!`) or
# after a wrapper with its options (`sudo -u x`, `timeout 5`, `xargs -r`, `cmd /c`, `-Command`).
# Quoted text is an argument: a word inside it (`git commit -m "kill the flaky test"`,
# `rg "pkill"`) is not a command. Only the text after a shell flag (`-c`, `-Command`, `/c`,
# `eval`, `-e`) or an `ssh <host>` is code and stays readable.
#
# Limits, by design: the guard reads the command text and runs nothing. A target held in a
# variable is "ask", never resolved; a script file that kills is not opened.
#
# Fail-open like the other hooks: no jq, an unparsable payload or an empty command all exit 0.
#
# Cost. Registered for Bash and PowerShell, so it starts on every shell call. The payload is
# read with `cat` through lib/stdin.sh, one process start, where a byte-by-byte `read` costs about
# 4.5 ms per KB and `$(</dev/stdin)` fails under Git Bash on Windows (ww3d/playbook#488). Step 1 then decides on the raw payload with bash builtins alone and exits for a
# call that holds no verb; only a call that might end a process pays for the jq start.
#
# Stdin:  the PreToolUse event JSON ({ tool_name, tool_input.command, ... }).
# Stdout: only when asking or blocking - hookSpecificOutput with permissionDecision.

set -euo pipefail
set -f # no pathname expansion: a `*` in the command text is data, never a file list

# Test hook: with GUARD_KILL_TRACE=<file> the run leaves how often the statement pattern ran and over how
# many characters, so the tests count the work instead of timing it.
trace_runs=0 trace_chars=0
if [ -n "${GUARD_KILL_TRACE:-}" ]; then
  trap '{ printf "runs=%s chars=%s\n" "$trace_runs" "$trace_chars" >"$GUARD_KILL_TRACE"; } 2>/dev/null || :' EXIT
fi

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
read_hook_payload
input="$hook_input"

tool_re='"tool_name"[[:space:]]*:[[:space:]]*"(Bash|PowerShell)"'
[[ $input =~ $tool_re ]] || exit 0

# --- step 1: can this payload hold a verb at all? ---------------------------
# Raw JSON, case-insensitive. A false positive costs the jq start, a false negative
# is impossible for a verb written in clear text; an encoded command is caught by its
# flag plus a base64 run. "skills" (as in .claude/skills/) is not "kill": the word must
# not follow an "s", except as `pskill`, `tskill` and the standalone command `skill`.
shopt -s nocasematch
hint_re='([^s]|^)kill|(ps|ts)kill|stop-process|spps|wmic|terminate|(^|[^a-z0-9/_.-])skill[[:space:]]|-e(nc[a-z]*|c)?[[:space:]]+[a-z0-9+/=]{8,}'
[[ $input =~ $hint_re ]] || exit 0
shopt -u nocasematch

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -j '.tool_input.command // ""' <<<"$input" 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# --- step 2: normalise the text -----------------------------------------------
# Lower case; quoted arguments blanked of their separators; one space kind, newlines as
# `;`; the flags that introduce nested code as separators, so the verb behind them stands at
# a command position.
t="${cmd,,}"
# A backslash-escaped double quote (`powershell -Command "... \"x\" ..."`) does not close a span: it is set
# aside as \x01 while the quotes are masked and restored after. An escaped backslash (`"C:\\"`) goes first
# (\x02), so the quote behind it still closes the span.
t="${t//\\\\/$'\x02'}"
t="${t//\\\"/$'\x01'}"

# Blank the separators and spaces inside a quoted span, so no word in it reaches a command
# position. Left alone: the span after a code flag or `ssh <host>`, a double-quoted span that
# substitutes (`$(`, backtick), and an unterminated quote.
# The options of `env` before `-S`: a switch, or `-u`/`-C`/`--unset`/`--chdir` with its value (the text is lower case).
env_opts='([[:space:]]+(-[uc]|--unset|--chdir)[[:space:]]+[^[:space:];|&]+|[[:space:]]+-[^[:space:];|&]+)*'
mask_quotes() { # text -> global masked
  local rest="$1" out="" pre q body span len
  local blank='[[:space:];|&(){}]' # a `}` inside ${...//...} would end the expansion: hence the variable
  local code_re='(^|[[:space:]])(-[a-z]*c|-command|-e|/c|/k|eval)[[:space:]]*$'
  local ssh_re='(^|[[:space:]])([^[:space:]]*[/\])?ssh([[:space:]]+-[a-z]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+[^[:space:]]+[[:space:]]*$'
  # `watch '...'` and `env -S '...'` run their quoted argument as a command line, as `ssh host '...'` does.
  local watch_re='(^|[[:space:]])([^[:space:]]*[/\])?watch([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]*$'
  local envs_re="(^|[[:space:]])([^[:space:]]*[/\\])?env${env_opts}[[:space:]]+(-[a-z]*s|--split-string=?)[[:space:]]*\$"
  while :; do
    pre="${rest%%[\"\']*}"
    if [ "$pre" = "$rest" ]; then out+="$rest"; break; fi
    q="${rest:${#pre}:1}"
    body="${rest:${#pre}+1}"
    span="${body%%"$q"*}"
    if [ "$span" = "$body" ]; then out+="$rest"; break; fi
    len=${#span}
    out+="$pre"
    # shellcheck disable=SC2016 # `$(` and a backtick are searched for as text
    if [[ $out =~ $code_re || $out =~ $ssh_re || $out =~ $watch_re || $out =~ $envs_re ]] || { [ "$q" = '"' ] && [[ $span == *'$('* || $span == *'`'* ]]; }; then
      out+="${q}${span}${q}"
    else
      out+="${q}${span//$blank/_}${q}"
    fi
    rest="${body:len+1}"
  done
  masked="$out"
}
mask_quotes "$t"
t="${masked//$'\x01'/\"}"
t="${t//$'\x02'/\\\\}"
# `env -S'kill 1'` and `env --split-string='kill 1'` glue the quote to the option: split it off, so the
# option is a word of its own and the command line behind it stands at a command position.
t="${t//--split-string=/--split-string }"
split_re="(^|[[:space:];|&(])(([^[:space:];|&]*[/\\\\])?env${env_opts}[[:space:]]+-[a-z]*s)([\"'])"
while [[ $t =~ $split_re ]]; do
  m="${BASH_REMATCH[0]}"
  t="${t/"$m"/"${m%?} ${m: -1}"}"
done
# `{}` is the placeholder of find and xargs; its brace would end the statement scan.
t="${t//\{\}/__}"
t="${t//$'\r'/ }"; t="${t//$'\t'/ }"; t="${t//$'\n'/ ; }"
t=" ${t}"

# An encoded PowerShell command hides its verbs: decode what is cheap to decode
# (UTF-16LE of ASCII text), and ask when it cannot be read. Eight base64 characters
# are enough for the shortest verb command, and step 1 admits the same length.
unreadable=""
enc_re='(powershell|pwsh)[^;|&]*[[:space:]]-e(nc[a-z]*|c)?[[:space:]]+([A-Za-z0-9+/=]{8,})'
shopt -s nocasematch
if [[ $cmd =~ $enc_re ]]; then
  decoded="$(printf '%s' "${BASH_REMATCH[3]}" | base64 -d 2>/dev/null | tr -d '\000' 2>/dev/null || true)"
  if [ -n "$decoded" ]; then
    decoded="${decoded,,}"
    t+=" ; ${decoded//$'\n'/ ; }"
  else
    unreadable="an encoded PowerShell command the guard cannot decode"
  fi
fi
shopt -u nocasematch

# `-c` introduces code for a shell (`bash -c`), but `ionice -c 3`, `taskset -c 0` and `env -C /` (the text is
# lower case) carry a value: those are renamed first, so the verb behind them keeps its command position.
valopt_re='(^|[[:space:];|&(])(ionice|env|taskset)(([[:space:]]+-[^[:space:];|&]+([[:space:]]+[^[:space:];|&-][^[:space:];|&]*)?)*)[[:space:]]+-c[[:space:]]'
while [[ $t =~ $valopt_re ]]; do
  m="${BASH_REMATCH[0]}"
  t="${t/"$m"/"${m%-c }--c-value "}"
done
for w in -command -lc -c /c /k; do t="${t// $w / ; }"; done

# --- step 3: classify every verb occurrence -------------------------------
# Result: `named` (targets by number), `denies` / `asks` (reasons).
named=(); denies=(); asks=()
[ -z "$unreadable" ] || asks+=("$unreadable")

# A process list in the call (Get-Process, a CIM/WMI query on processes) means a target held in a variable
# or an object comes from a filter, not from a number the session knows: that ending is broad.
list_src=0
list_re='(^|[^a-z0-9_-])(get-process|gps)([^a-z0-9_-]|$)|(get-ciminstance|gcim|get-wmiobject|gwmi)[^;|&]*process'
if [[ $t =~ $list_re ]]; then list_src=1; fi
ask_var() { # reason: a target the guard cannot read
  if [ "$list_src" = 1 ]; then denies+=("$1, taken from a process list (targets chosen by a filter)"); else asks+=("$1"); fi
}

# Tokens of an argument string: quotes dropped, a leading `//` (Git Bash spelling of `/`) folded.
tokenize() { # args -> global tok
  local a="${1//[\"\'\`]/}" x
  tok=()
  for x in $a; do
    case "$x" in //*) x="${x#/}" ;; esac
    tok+=("$x")
  done
}

classify_kill() { # verb pipeline args
  local verb="$1" piped="$2" tk skip=0 seen=0 sig=0 count=0 found=()
  if [ "$piped" = 1 ]; then denies+=("'${verb}' fed by a pipeline (targets chosen by pattern)"); return; fi
  tokenize "$3"
  for tk in ${tok[@]+"${tok[@]}"}; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    # The first dash word is the signal; a second one made of digits is a negative PID.
    if [ "$seen" = 0 ] && [[ $tk == -* ]] && { [ "$sig" = 0 ] || ! [[ $tk =~ ^-[0-9]+$ ]]; }; then
      case "$tk" in
        -l*|-0) return ;;       # list signals / existence check: ends nothing
        -s|-n) skip=1 ;;
      esac
      sig=1
      continue
    fi
    seen=1
    if [[ $tk == -* ]]; then denies+=("kill of a process group (${tk})"); return; fi
    # shellcheck disable=SC2016 # `$(` is searched for as text
    if [[ $tk == *'$('* || $tk == '('* ]]; then denies+=("kill of a computed target list (${tk})"); return; fi
    if [ "$tk" = 0 ]; then denies+=("kill of a process group (0)"); return; fi
    if [[ $tk == *[\*\?]* ]]; then denies+=("kill by pattern (${tk})"); return; fi
    count=$((count + 1))
    if [[ $tk == '$'* ]]; then ask_var "kill of a target held in a variable (${tk})"; continue; fi
    # pskill and tskill take a name as well as a number; `\\host` names the machine.
    if [[ $verb == @(pskill|tskill) ]]; then
      if [[ $tk == \\* ]]; then count=$((count - 1)); continue; fi
      if ! [[ $tk =~ ^[0-9]+$ ]]; then denies+=("ending by name (${verb} ${tk})"); continue; fi
    fi
    found+=("${verb} ${tk}")
  done
  if [ "$count" = 0 ]; then asks+=("'${verb}' without a readable target"); return; fi
  named+=(${found[@]+"${found[@]}"})
}

classify_taskkill() { # args
  local tk i=0 count=0 target="" n
  tokenize "$1"
  n=${#tok[@]}
  while [ "$i" -lt "$n" ]; do
    tk="${tok[$i]}"
    case "$tk" in
      /fi|-fi) denies+=("taskkill by filter (/FI)"); return ;;
      /pid|-pid|/im|-im)
        i=$((i + 1)); target="${tok[$i]:-}"
        if [[ $target == *[\*\?]* ]]; then denies+=("taskkill by pattern (${target})"); return; fi
        count=$((count + 1))
        case "$tk" in
          /im|-im) denies+=("ending by name (taskkill ${target})") ;;
          *)
            # shellcheck disable=SC2016 # `$` is matched as text
            if [[ $target == '$'* ]]; then ask_var "taskkill of a target held in a variable (${target})"
            else named+=("taskkill pid ${target}"); fi ;;
        esac ;;
      /s|/u|/p|-s|-u|-p) i=$((i + 1)) ;;
    esac
    i=$((i + 1))
  done
  if [ "$count" = 0 ]; then asks+=("taskkill without a readable target"); fi
}

classify_stop_process() { # verb pipeline args
  local verb="$1" tk i=0 n count=0 val kind v parts
  if [ "$2" = 1 ]; then denies+=("${verb} fed by a pipeline (targets chosen by pattern)"); return; fi
  tokenize "$3"
  n=${#tok[@]}
  while [ "$i" -lt "$n" ]; do
    tk="${tok[$i]}"; val=""; kind=id
    case "$tk" in
      -id|-i)
        i=$((i + 1)); val="${tok[$i]:-}" ;;
      -name|-n|-processname)
        kind=name; i=$((i + 1)); val="${tok[$i]:-}" ;;
      -id:*) val="${tk#*:}" ;;
      -name:*|-processname:*) kind=name; val="${tk#*:}" ;;
      -inputobject|-in|-inputobject:*) ask_var "${verb} of an object the guard cannot read"; return ;;
      -*) ;;                       # -Force, -PassThru, -WhatIf, -Confirm...
      *) val="$tk" ;;              # positional: the Id
    esac
    if [ -n "$val" ]; then
      count=$((count + 1))
      # shellcheck disable=SC2016 # `$(` and `$` are matched as text, not expanded
      case "$val" in
        '$('*|'('*) denies+=("${verb} of a computed target list"); return ;;
        *[\*\?\[]*) denies+=("${verb} by pattern (${val})"); return ;;
      esac
      if [ "$kind" = name ]; then
        # shellcheck disable=SC2016 # `$` is matched as text
        if [[ $val == '$'* ]]; then denies+=("${verb} by a name held in a variable (${val})")
        else denies+=("ending by name (${verb} ${val})"); fi
      else
        IFS=, read -ra parts <<<"$val"
        for v in "${parts[@]}"; do
          # shellcheck disable=SC2016 # `$` is matched as text
          if [[ $v == '$'* ]]; then ask_var "${verb} of a target held in a variable (${v})"
          else named+=("${verb} ${v}"); fi
        done
      fi
    fi
    i=$((i + 1))
  done
  if [ "$count" = 0 ]; then asks+=("${verb} without a readable target"); fi
}

classify_wmic() { # args
  local a="${1//[\"\'\`]/}"
  case "$a" in
    *process*delete*|*process*terminate*) ;;
    *) return ;;                 # wmic reading something else ends nothing
  esac
  if [[ $a =~ (^|[^a-z0-9_])processid=([0-9]+)([^0-9]|$) && $a != *like* && $a != *%* ]]; then
    named+=("wmic process ${BASH_REMATCH[2]}")
  else
    denies+=("wmic process delete/terminate by condition")
  fi
}

classify_byname() { # verb args: pkill, killall, skill end every process of a name: always a deny
  local verb="$1" tk skip=0 count=0 target="" sel="" flags c val i
  tokenize "$2"
  for tk in ${tok[@]+"${tok[@]}"}; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    # shellcheck disable=SC2016 # `$(` and `$` are matched as text, not expanded
    case "$tk" in
      -l|--list) return ;;       # lists signal names: ends nothing
      -f|-r|--full|--regexp) denies+=("'${verb}' matches the full command line or a regular expression"); return ;;
      # A selector (user, group, parent, session, terminal) picks processes without a name; with no
      # name beside it, it ends every process it matches. The text is lower case: `-P` reads `-p`.
      # `killall -s` is a signal, not a selector; `-y` and `--signal` take a value too.
      -s) skip=1; [ "$verb" = killall ] || sel="$tk" ;;
      -u|-g|-p|-t|--user|--uid|--euid|--group|--pgroup|--parent|--session|--terminal) skip=1; sel="$tk" ;;
      -y|--signal|--pidfile) skip=1 ;;
      # A selector with its value attached (`--uid=5`).
      --user=*|--uid=*|--euid=*|--group=*|--pgroup=*|--parent=*|--session=*|--terminal=*) sel="${tk%%=*}" ;;
      --*|-[0-9]*) ;;            # a long flag or a numeric signal
      # A signal name (`-hup`, `-quit`, `-sigterm`) is not a bundle of flags.
      -hup|-int|-quit|-ill|-trap|-abrt|-bus|-fpe|-kill|-usr1|-segv|-usr2|-pipe|-alrm|-term|-chld|-cont|-stop|\
-tstp|-ttin|-ttou|-urg|-xcpu|-xfsz|-vtalrm|-prof|-winch|-io|-pwr|-sys|-sig*) ;;
      # Bundled short flags (`-fu me`, `-u5`, `-uroot`): read letter by letter. A selector letter
      # takes the rest of the token as its value, or the next token when nothing follows it.
      -??*)
        flags="${tk#-}"
        for ((i = 0; i < ${#flags}; i++)); do
          c="${flags:i:1}"; val="${flags:i+1}"
          case "$c" in
            f|r) denies+=("'${verb}' matches the full command line or a regular expression"); return ;;
            u|g|p|t) sel="-${c}"; [ -n "$val" ] || skip=1; break ;;
            s) if [ "$verb" != killall ]; then sel="-s"; fi; [ -n "$val" ] || skip=1; break ;;
            y) [ -n "$val" ] || skip=1; break ;;
          esac
        done ;;
      -*) ;;                     # a signal or a flag
      *'$('*|'('*) denies+=("'${verb}' of a computed name list (${tk})"); return ;;
      '$'*) denies+=("'${verb}' of a name held in a variable (${tk})"); return ;;
      *[\*\?\[]*) denies+=("'${verb}' by pattern (${tk})"); return ;;
      *) count=$((count + 1)); target="$tk" ;;
    esac
  done
  case "$count" in
    0) if [ -n "$sel" ]; then
         denies+=("'${verb}' by selector (${sel}) without a name: ends every process it matches")
       else
         asks+=("'${verb}' without a readable name")
       fi ;;
    1) denies+=("ending by name (${verb} ${target})") ;;
    *) denies+=("'${verb}' of ${count} names in one command") ;;
  esac
}

# The prefix of a verb: keywords, and wrappers with their options (`sudo -u x`, `timeout 5`,
# `xargs -n 1`). A quote right after the prefix opens the code a flag or keyword introduced.
sep_re='(^|;|&&|&|\|\||\||\(|\{|`)'
opt_re='([[:space:]]+-[^[:space:];|&]+([[:space:]]+[^[:space:];|&-][^[:space:];|&]*)?)*'
# A path may stand before a wrapper as well as before the verb (`/usr/bin/env kill 5`, `\kill`),
# and `.exe` after the verb.
path_re='([^[:space:];|&(){}"'"'"'`]*[/\\])?'
wrap_re='(sudo|doas|busybox|xargs|timeout|nice|ionice|stdbuf|setsid|env|nohup|exec|time|command|builtin|start|eval|watch|chrt|taskset|runuser|systemd-run|then|do|else|elif|!)'
one_re="${path_re}${wrap_re}${opt_re}([[:space:]]+[0-9][0-9a-fx.]*[smhd]?)?[[:space:]]+[\"']?"
# `ssh host`, `flock file`: a wrapper whose first plain word is no command.
ssh_one_re="${path_re}(ssh|flock)${opt_re}[[:space:]]+[^[:space:];|&-][^[:space:];|&]*[[:space:]]+[\"']?"
# An environment assignment before a command (`FOO=1 kill 5`) is part of the prefix too.
assign_re="[a-z_][a-z0-9_]*=[^[:space:];|&]*[[:space:]]+"
# `find ... -exec kill {} \;` hands the verb the names find chose.
find_re="${path_re}find[[:space:]]+[^;|&]*[[:space:]]-exec(dir)?[[:space:]]+"
verbs='taskkill|killall|pkill|pskill|tskill|xkill|skill|kill|stop-process|spps|wmic'
re="${sep_re}[[:space:]]*[\"']?[[:space:]]*(${one_re}|${ssh_one_re}|${assign_re}|${find_re})*${path_re}(${verbs})(\.exe)?([[:space:]]|\$|[;|&)\"'\`])"
verb_re="(${verbs})(\.exe)?(.?)\$"
# The full pattern is slow on a long text (seconds for a 50 KB heredoc), so each verb word is
# found with a plain scan and only its own statement - from the separator before it - is matched.
anchored_re="^[^;|&({\`]?${re}"
verb_any="(${verbs})"
# The statement runs from the separator before the word, across words skipped earlier too. The text
# already passed is not rebuilt per word: `st_stmt` (its last statement) and `st_head` (the two characters
# before that statement) carry over, so the scan stays linear in the number of verb words.
st_stmt="" st_head="" st_tail="" st_dead=0
advance() { # appended text -> updates st_stmt, st_head, st_tail
  local x="$1" last all
  all="${st_tail}${x}"
  if [[ $x == *[\;\|\&\(\{\`]* ]]; then
    last="${x##*[;|&(\{\`]}"
    st_head="${st_tail}${x%"$last"}"; st_head="${st_head: -2}"
    # Two separators that form no operator (`;;`, `&;`): only the last one opens the statement.
    # `|&` pipes stderr along, so it reads as `|`.
    case "$st_head" in
      '&&'|'||') ;;
      '|&') st_head='|' ;;
      [\;\|\&\(\{\`][\;\|\&\(\{\`]) st_head="${st_head: -1}" ;;
    esac
    st_stmt="$last"; st_dead=0
  else
    st_stmt+="$x"
  fi
  st_tail="${all: -2}"
}
# What ends the arguments of a verb: a separator, a closing bracket or the brace that closes a script block
# (`& { Stop-Process -Id 5 }`); the brace is no target.
stmt_end='[;|&)}]'
rest="$t"
while [[ $rest =~ $verb_any ]]; do
  word="${BASH_REMATCH[0]}"
  pre="${rest%%"$word"*}"
  after_word="${rest:${#pre}+${#word}}"
  advance "$pre"
  # The window of a verb word reaches to the end of its statement, so a failed match means no verb of
  # this statement stands at a command position (one that did would have matched here): the later verb
  # words of it (`echo /tmp/kill-1 /tmp/kill-2 ...`) skip the pattern. That keeps the scan linear.
  if [ "$st_dead" = 1 ]; then advance "$word"; rest="$after_word"; continue; fi
  stmt_len=$(( ${#st_head} + ${#st_stmt} + ${#word} ))
  # Only the statement up to its first separator (and that one character) is matched, not the whole rest.
  # shellcheck disable=SC2295 # $stmt_end is a pattern on purpose
  seg="${after_word%%$stmt_end*}"
  if [ "$seg" != "$after_word" ]; then seg="${seg}${after_word:${#seg}:1}"; fi
  window="${st_head}${st_stmt}${word}${seg}"
  advance "$word"
  trace_runs=$((trace_runs + 1)); trace_chars=$((trace_chars + ${#window}))
  if ! [[ $window =~ $anchored_re ]]; then
    # The window stops at `)`; a `)` in the rest of the statement hides what follows it from this match.
    [[ $seg == *')' ]] || st_dead=1
    rest="$after_word"; continue
  fi
  full="${BASH_REMATCH[0]}"; lead="${BASH_REMATCH[1]}"
  [[ $full =~ $verb_re ]] || break
  verb="${BASH_REMATCH[1]}"; tail_ch="${BASH_REMATCH[3]}"
  after="${window#"$full"}"
  extra="${full:stmt_len}"
  piped=0; { [ "$lead" = "|" ] || [[ $full == *xargs* || $full == *" -exec"* ]]; } && piped=1
  args=""
  # shellcheck disable=SC2295 # $stmt_end is a pattern on purpose
  case "$tail_ch" in
    ' '|'') args="${after%%$stmt_end*}"; rest="${after_word:${#extra}+${#args}}"; advance "${extra}${args}" ;;
    *) rest="${after_word:${#extra}-1}"; advance "${extra%?}" ;;
  esac
  case "$verb" in
    killall|pkill|skill) classify_byname "$verb" "$args" ;;
    xkill) asks+=("xkill (ends the window you click)") ;;
    kill) classify_kill "$verb" "$piped" "$args" ;;
    pskill|tskill) classify_kill "$verb" "$piped" "$args" ;;
    taskkill) classify_taskkill "$args" ;;
    stop-process|spps) classify_stop_process "$verb" "$piped" "$args" ;;
    wmic) classify_wmic "$args" ;;
  esac
done

# A CIM / WMI query ended by Terminate: a filter on one process id is a target by number, every other query
# picks by name, command line or nothing at all.
cim_end_re='invoke-(cim|wmi)method[^;|&]*terminate|\.terminate\('
cim_src_re='get-ciminstance|gcim|get-wmiobject|gwmi|-query'
cim_flt_re='-(filter|query)[[:space:]]+("[^"]*"|[^[:space:];|&)]+)'
cim_pid_re='(^|[^a-z0-9_])(processid|handle)[[:space:]]*=[[:space:]]*([0-9]+)([^0-9]|$)'
cim_mix_re='like|[ _](or|and)[ _]'
cim_done=0
if [[ $t =~ $cim_end_re && $t =~ $cim_src_re ]]; then
  cim_done=1; cim_pid=""
  if [[ $t =~ $cim_flt_re ]]; then
    cim_flt="${BASH_REMATCH[2]}"
    if ! [[ $cim_flt =~ $cim_mix_re ]] && [[ $cim_flt =~ $cim_pid_re ]]; then cim_pid="${BASH_REMATCH[3]}"; fi
  fi
  if [ -n "$cim_pid" ]; then
    named+=("cim process ${cim_pid}")
  else
    denies+=("a CIM/WMI query ended by Terminate, chosen by a filter other than one process id")
  fi
fi

# Ending written as a method call in code run inline (python -c, node -e, pwsh).
if [ "${#named[@]}${#denies[@]}${#asks[@]}" = "000" ] || [ "$list_src" = 1 ]; then
  code_re='\.(kill|terminate)\(|os\.killpg?|invoke-cimmethod[^;|&]*terminate'
  # The CIM branch above judged its own Terminate; only a kill call beside it is left to find.
  if [ "$cim_done" = 1 ]; then code_re='\.kill\(|os\.killpg?'; fi
  if [[ $t =~ $code_re ]]; then ask_var "a process-ending call in inline code (${BASH_REMATCH[0]})"; fi
fi

# --- step 4: the verdict ------------------------------------------------------
decision="" detail=""
join() { local out="" x; for x in "$@"; do out+="${out:+; }${x}"; done; printf '%s' "$out"; }
if [ "${#denies[@]}" -gt 0 ]; then
  decision="deny"; detail="$(join "${denies[@]}")"
elif [ "${#asks[@]}" -gt 0 ] || [ "${#named[@]}" -gt 0 ]; then
  decision="ask"
  all=()
  if [ "${#named[@]}" -gt 0 ]; then all+=("${named[@]}"); fi
  if [ "${#asks[@]}" -gt 0 ]; then all+=("${asks[@]}"); fi
  detail="$(join "${all[@]}")"
else
  exit 0
fi

rule="Core rule K5: end a foreign process or a foreign AI session only after the maintainer's explicit yes to exactly that action."
# A background session (`claude --bg`) has no one at its terminal. Measured with Claude Code 2.1.294, with and
# without `--permission-mode bypassPermissions` (ww3d/playbook#356): an `ask` parks the session as waiting, the
# command never runs, and CLAUDE_JOB_DIR is set. Reported by the controller, not measured: the question shows as a
# permission prompt in the maintainer's app. So it is a hard block there, and the question goes to the maintainer
# through the session's owner instead. CLAUDE_JOB_DIR is the signal: Claude Code sets it in each background
# session, and the hook inherits it (code.claude.com/docs/en/env-vars).
background=0
[ -z "${CLAUDE_JOB_DIR:-}" ] || background=1
if [ "$decision" = "ask" ] && [ "$background" = 1 ]; then
  reason="${rule} Blocked: a background session cannot get a confirmation (${detail}). Do not retry it here in another form. Ask the maintainer through the owner of this session; the owner or the maintainer runs the command themselves. A background task this session started itself is stopped with the harness's task stop (TaskStop), not with a kill command."
  decision="deny"
elif [ "$decision" = "deny" ]; then
  reason="${rule} Blocked, broad ending: ${detail}. End a single process by its number (kill <pid>, Stop-Process -Id <pid>, taskkill /PID <pid>): that asks the maintainer, a name, pattern or filter does not."
else
  reason="${rule} Target: ${detail}. Confirm only if it is a process you started in this session or the maintainer said yes to exactly this."
fi

jq -cn --arg d "$decision" --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: $d,
    permissionDecisionReason: $r
  }
}' || true
exit 0
