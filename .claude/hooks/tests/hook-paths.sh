# shellcheck shell=bash
# The paths of a tool call or turn end through the hooks, as decision 1 of ww3d/playbook#734 names them: payload,
# state before the call and the entries Claude Code starts for it, read from settings.json. Sourced by
# measure-hooks.sh (time) and cases/hook-budget.sh (programs and processes), never run.
#
# Usage:  hp_fixtures <work folder> <project root>   payloads and transcripts under <work>, gate under <work>/tmp
#         hp_paths                                    one line per path: name, event, tool, payload, setup, entries
#         hp_entries <settings> <event> <tool> <sync|rewake>   the entries Claude Code starts for it, a line each
#         hp_argv <entry>                             -> hp_cmd, the words that start the entry
#         hp_entry_name <entry>                       the entry's hook file or program, short
#         hp_native <path>                            the path as the hooks' native tools take it
#         hp_shims <folder> <log>                     shims that log each program a hook starts
#         hp_open_lists <project root>                says whether the checkout holds open tick lists

hp_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# Open tick lists under .agent/state/ticks/open start the tick guard at every turn end of that checkout, a cost of
# the checkout's state rather than of the hooks. (The project cannot be copied into the run folder instead: its
# path holds `/tmp/`, which wakes guard-shared-tmp.sh on every Write and Read.)
hp_open_lists() { local f; for f in "$1"/.agent/state/ticks/open/*; do [ -f "$f" ] && return 0; done; return 1; }

hp_fixtures() { # work folder, project root -> files and the globals hp_gate, hp_root
  local work="$1" line_a line_u tr_file stop_tr pad t
  hp_root="$(hp_native "$2")"; hp_gate="$work/tmp"
  # A transcript of about 1 MB with usage lines, as remind-before-compact.sh reads it.
  tr_file="$work/transcript.jsonl"
  line_a="$(jq -cn --arg t "$(printf 'Arbeit %.0s' {1..60})" \
    '{type:"assistant",message:{role:"assistant",model:"claude-opus-5-5",content:[{type:"text",text:$t}],
      usage:{input_tokens:3,cache_creation_input_tokens:100,cache_read_input_tokens:40000}}}')"
  line_u="$(jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t",content:"M file.txt"}]}}')"
  for _ in $(seq 1 1500); do printf '%s\n%s\n' "$line_a" "$line_u"; done > "$tr_file"
  # Stop: a turn end on a plain report (no announcement), with a receipt and a start marker in the transcript.
  stop_tr="$work/stop-transcript.jsonl"
  { cat "$tr_file"
    jq -cn '{type:"attachment",attachment:{hookEvent:"SessionStart",hookName:"SessionStart:startup"}}'
    jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Playbook 32.0.0 | Core AGENTS.md\nMemory: none"}]}}'
    printf '%s\n' "$line_a"
  } > "$stop_tr"
  mkdir -p "$work/scratchpad"; pad="$(hp_native "$work/scratchpad")"; t="$(hp_native "$tr_file")"
  hp_event() { # event, tool, tool_input json -> the envelope Claude Code hands a hook
    jq -cn --arg e "$1" --arg n "$2" --argjson i "$3" --arg t "$t" --arg c "$hp_root" --arg p "$pad" \
      '{session_id:"measure-734", transcript_path:$t, cwd:$c, permission_mode:"bypassPermissions",
        hook_event_name:$e, tool_name:$n, tool_input:$i, scratchpad_dir:$p}
       + (if $e == "PostToolUse" then {tool_response:{stdout:"M file.txt",stderr:"",interrupted:false}} else {} end)'
  }
  hp_event PreToolUse Bash '{"command":"git status --short","description":"Show working tree status"}' > "$work/pre-bash.json"
  hp_event PreToolUse PowerShell '{"command":"Get-ChildItem -Name","description":"List files"}' > "$work/pre-ps.json"
  hp_event PreToolUse Bash '{"command":"gh pr create --draft --title x --body y","description":"Open draft PR"}' > "$work/pre-gh.json"
  hp_event PreToolUse Write "$(jq -cn --arg p "$hp_root/docs/x.md" '{file_path:$p, content:"# x\n"}')" > "$work/pre-write.json"
  hp_event PostToolUse Bash '{"command":"git status --short","description":"Show working tree status"}' > "$work/post-bash.json"
  hp_event PostToolUse Read "$(jq -cn --arg p "$hp_root/docs/x.md" '{file_path:$p}')" > "$work/post-read.json"
  jq -cn --arg t "$(hp_native "$stop_tr")" --arg c "$hp_root" \
    '{session_id:"measure-734", transcript_path:$t, cwd:$c, hook_event_name:"Stop", stop_hook_active:false,
      last_assistant_message:"Gemessen: 97 ms je Aufruf, Beleg im Bericht."}' > "$work/stop.json"
}

# The state before a call; every setup starts from an empty gate folder.
hp_fresh() { rm -rf "$hp_gate"; mkdir -p "$hp_gate/claude-rule-gate"; }
hp_docs_read() { hp_fresh; : > "$hp_gate/claude-rule-gate/measure-734-read-main-docs"; }   # the rule of a Write read
hp_remind_sent() { hp_fresh; : > "$hp_gate/claude-rule-gate/measure-734-remind-sent"; }     # the run already reported
hp_remind_state() { # epoch of the last look -> the state of a dev run: the fields remind-before-compact.sh writes
  hp_fresh; printf '%s 840000 dev notice 0 0 %(%s)T\n' "$1" -1 > "$hp_gate/claude-rule-gate/measure-734-remind-state"
}
hp_remind_quiet() { local now; printf -v now '%(%s)T' -1; hp_remind_state "$now"; }
hp_remind_look() { hp_remind_state 0; }

hp_paths() { # name event tool payload setup kind - the paths of decision 1, in its order
  cat <<'EOF'
pre-bash PreToolUse Bash pre-bash.json hp_fresh sync
pre-powershell PreToolUse PowerShell pre-ps.json hp_fresh sync
pre-write PreToolUse Write pre-write.json hp_docs_read sync
pre-gh PreToolUse Bash pre-gh.json hp_fresh sync
post-quiet PostToolUse Bash post-bash.json hp_remind_quiet sync
post-look PostToolUse Bash post-bash.json hp_remind_look sync
post-read PostToolUse Read post-read.json hp_fresh sync
stop Stop - stop.json hp_fresh sync
stop-rewake Stop - stop.json hp_fresh rewake
EOF
}

# An entry in the args form is one line "exec<TAB>program<TAB>argument...": Claude Code starts it without a shell.
# Its program is the checked-in one of this platform beside the settings file, which answers as the session's own
# copy does and is there before a session placed one.
hp_entries() { # settings file, event, tool (- for none), sync|rewake -> one entry per line, in file order
  local bin program
  bin="$(hp_native "${1%/*}/hooks/bin")"
  case "${OSTYPE:-}" in msys* | cygwin*) program="$bin/win-x64/pb-hook.exe" ;; *) program="$bin/linux-x64/pb-hook" ;; esac
  jq -r --arg e "$2" --arg t "$3" --arg k "$4" --arg p "$program" '.hooks[$e][]? | (.matcher // "") as $m | select($m == ""
      or ($t != "-" and ($t | test("^(" + $m + ")$")))) | .hooks[]
    | select((.asyncRewake == true) == ($k == "rewake"))
    | if has("args") then ["exec", (if (.command | endswith("/pb-hook")) then $p else .command end)] + .args | join("\t")
      else .command end' "$1" | tr -d '\r'
}
hp_argv() { # entry -> global hp_cmd: a command text runs in bash -c, an args entry as it is
  # shellcheck disable=SC2034 # the caller reads hp_cmd
  if [[ $1 == $'exec\t'* ]]; then IFS=$'\t' read -r -a hp_cmd <<< "${1#*$'\t'}"
  else hp_cmd=(bash -c "$1"); fi
}
hp_entry_name() { # entry -> "pb-hook pre-tool", or the hook file with its arguments
  local n
  if [[ $1 == $'exec\t'* ]]; then n="${1#*$'\t'}"; n="${n##*/}"; n="${n/.exe/}"; printf '%s' "${n//$'\t'/ }"
  else n="${1##*/hooks/}"; printf '%s' "${n//\"/}"; fi
}

hp_shims() { # shim folder, log file: a shim per program a hook may start, logging its name, then exec'ing the real one
  local p real
  mkdir -p "$1"
  for p in cat jq awk gawk sed grep git tail head date timeout sleep mkdir rm tr cygpath uname mktemp base64 wc \
           sort uniq cut ls stat touch mv cp find xargs env dirname basename realpath readlink sha1sum sha256sum gh \
           pwsh powershell; do
    real="$(type -P "$p" 2>/dev/null)" || continue
    printf '#!/bin/sh\nprintf "%%s\n" %s >> "%s"\nexec "%s" "$@"\n' "$p" "$2" "$real" > "$1/$p"
    chmod +x "$1/$p"
  done
}
