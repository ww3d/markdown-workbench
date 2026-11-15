#!/usr/bin/env bash
# Hook suite section: guard-shared-tmp.sh, a write to a fixed path in the shared temp folder (ww3d/playbook#619)
# Run alone: bash .claude/hooks/tests/cases/guard-shared-tmp.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-shared-tmp.sh: writes to fixed paths in the shared temp folder (ww3d/playbook#619) =="
gtguard="$hooks/guard-shared-tmp.sh"
gt_dir="$fix/tmpguard"; mkdir -p "$gt_dir/gate"
gt_log="$gt_dir/log.jsonl"
gt_pad='D:\tmp\claude-sessions\claude\h\gt-sid-1\scratchpad'
gt_pad_j='D:\\tmp\\claude-sessions\\claude\\h\\gt-sid-1\\scratchpad' # as it stands inside JSON
gt_real_awk="$(command -v awk)"
unset PLAYBOOK_TMP_GUARD PLAYBOOK_TMP_GUARD_OWN PLAYBOOK_TMP_GUARD_TIMEOUT CLAUDE_CODE_REMOTE CLAUDE_PROJECT_DIR

gt_ev() { # tool, input key, value, [session id], [scratchpad_dir] -> a PreToolUse envelope
  local t k v s p=""
  js "$1"; t="$REPLY"; js "$2"; k="$REPLY"; js "$3"; v="$REPLY"; js "${4-gt-sid-1}"; s="$REPLY"
  if [ -n "${5:-}" ]; then js "$5"; p=",\"scratchpad_dir\":$REPLY"; fi
  printf '{"session_id":%s,"hook_event_name":"PreToolUse","tool_name":%s%s,"tool_input":{%s:%s}}' "$s" "$t" "$p" "$k" "$v"
}
gt_hook() { # envelope, [NAME=value | -u NAME]... -> the hook output (the log of the run: $gt_log)
  local ev="$1" unset_args=() assigns=(); shift
  while [ $# -gt 0 ]; do
    if [ "$1" = -u ]; then unset_args+=(-u "$2"); shift 2; else assigns+=("$1"); shift; fi
  done
  printf '%s' "$ev" | env "${unset_args[@]}" TMPDIR="$gt_dir/gate" PLAYBOOK_TMP_GUARD_LOG="$gt_log" "${assigns[@]}" "$BASH" "$gtguard" 2>/dev/null
}
gt_verdict() { # output -> PASS | WARN | DENY | ERR
  if [ -z "$1" ]; then echo PASS
  elif has_text '"permissionDecision":"deny"' "$1"; then echo DENY
  elif has_text '"additionalContext"' "$1" && ! has_text 'permissionDecision' "$1"; then echo WARN
  else echo ERR; fi
}
# needle, haystack -> how often the haystack holds it
gt_count() { local r="$2" n=0; while [[ $r == *"$1"* ]]; do r="${r#*"$1"}"; n=$((n + 1)); done; echo "$n"; }
gt_chk() { # label, want, tool, input, [env]... -> the verdict of one call (key: command for the shells, file_path else)
  local label="$1" want="$2" tool="$3" input="$4" key=command; shift 4
  case "$tool" in Write|Edit) key=file_path ;; NotebookEdit) key=notebook_path ;; esac
  expect "$label" "$want" "$(gt_verdict "$(gt_hook "$(gt_ev "$tool" "$key" "$input")" "$@")")"
}
gt_b() { gt_chk "bash: $1" "$2" Bash "$3" "${@:4}"; }
gt_p() { gt_chk "powershell: $1" "$2" PowerShell "$3" "${@:4}"; }

echo "-- Write, Edit, NotebookEdit: the path --"
gt_chk 'Write: /tmp name'                       WARN Write '/tmp/prbody.md'
gt_chk 'Write: D:/tmp name'                     WARN Write 'D:/tmp/prbody.md'
gt_chk 'Write: D:\tmp name'                     WARN Write 'D:\tmp\prbody.md'
gt_chk 'Write: /d/tmp name (Git Bash)'          WARN Write '/d/tmp/prbody.md'
gt_chk 'Write: AppData Local Temp'              WARN Write 'C:\Users\u\AppData\Local\Temp\a.md'
gt_chk 'Write: Windows Temp'                    WARN Write 'C:\Windows\Temp\a.md'
gt_chk 'Edit: /tmp name'                        WARN Edit '/tmp/a.md'
gt_chk 'NotebookEdit: /tmp notebook'            WARN NotebookEdit '/tmp/n.ipynb'
gt_chk 'Write: a file in the project passes'    PASS Write './docs/a.md'
gt_chk 'Write: a folder alone passes'           PASS Write '/tmp/'
gt_chk 'Write: the root itself passes'          PASS Write '/tmp'
gt_chk 'Write: a name that only holds tmp'      PASS Write '/home/u/tmpfiles/a.md'
gt_chk 'Write: a glob is no fixed name'         PASS Write '/tmp/*.md'
gt_chk 'Read is never a hit'                    PASS Read '/tmp/a.md'
gt_chk 'Grep is never a hit'                    PASS Grep '/tmp/a.md'

echo "-- the own area --"
gt_expect_own() { # label, want, path, [session], [pad], [env]...
  local l="$1" w="$2" p="$3" s="$4" pd="$5"; shift 5
  expect "$l" "$w" "$(gt_verdict "$(gt_hook "$(gt_ev Write file_path "$p" "$s" "$pd")" "$@")")"
}
gt_expect_own 'scratchpad_dir passes'                  PASS 'D:/tmp/claude-sessions/claude/h/gt-sid-1/scratchpad/x.md' gt-sid-1 "$gt_pad"
gt_expect_own 'scratchpad_dir, backslash spelling'     PASS 'D:\tmp\claude-sessions\claude\h\gt-sid-1\scratchpad\x.md' gt-sid-1 "$gt_pad"
gt_expect_own 'scratchpad_dir, Git Bash spelling'      PASS '/d/tmp/claude-sessions/claude/h/gt-sid-1/scratchpad/x.md' gt-sid-1 "$gt_pad"
gt_expect_own 'scratchpad_dir, other case of the drive' PASS 'd:/TMP/claude-sessions/claude/h/gt-sid-1/scratchpad/x.md' gt-sid-1 "$gt_pad"
gt_expect_own "another session's scratchpad is a hit"  WARN 'D:/tmp/claude-sessions/claude/h/other-sid/scratchpad/x.md' gt-sid-1 "$gt_pad"
gt_expect_own 'a name with the own session id passes'  PASS '/tmp/gt-sid-1-prbody.md' gt-sid-1 ''
gt_expect_own "a name with another session's id"       WARN '/tmp/other-sid-prbody.md' gt-sid-1 ''
gt_expect_own 'CLAUDE_PROJECT_DIR passes'              PASS '/tmp/proj-x/a.md' gt-sid-1 '' CLAUDE_PROJECT_DIR=/tmp/proj-x
gt_expect_own 'a folder next to the project is a hit'  WARN '/tmp/proj-xy/a.md' gt-sid-1 '' CLAUDE_PROJECT_DIR=/tmp/proj-x
case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) gt_sep=';' ;; *) gt_sep=':' ;; esac
gt_expect_own 'PLAYBOOK_TMP_GUARD_OWN, first folder'   PASS '/tmp/own1/a.md' gt-sid-1 '' "PLAYBOOK_TMP_GUARD_OWN=/tmp/own1${gt_sep}/tmp/own2"
gt_expect_own 'PLAYBOOK_TMP_GUARD_OWN, second folder'  PASS '/tmp/own2/a.md' gt-sid-1 '' "PLAYBOOK_TMP_GUARD_OWN=/tmp/own1${gt_sep}/tmp/own2"
gt_expect_own 'PLAYBOOK_TMP_GUARD_OWN, a third folder' WARN '/tmp/own3/a.md' gt-sid-1 '' "PLAYBOOK_TMP_GUARD_OWN=/tmp/own1${gt_sep}/tmp/own2"

echo "-- Bash: the write places and their reads --"
gt_b 'redirect >'                       WARN 'echo hi > /tmp/a.md'
gt_b 'redirect >>'                      WARN 'echo hi >> /tmp/a.md'
gt_b 'redirect &>'                      WARN 'make &> /tmp/a.log'
gt_b 'redirect 2>'                      WARN 'make 2> /tmp/e.log'
gt_b 'redirect >|'                      WARN 'echo hi >| /tmp/a.md'
gt_b 'redirect, target stuck to >'      WARN 'echo hi >/tmp/a.md'
gt_b 'redirect stuck to the word before: not seen, the gap is ww3d/playbook#648' PASS 'echo hi>/tmp/a.md'
gt_b 'redirect, quoted target'          WARN 'echo hi > "/tmp/a b.md"'
gt_b 'redirect behind a pipe'           WARN 'ls | sort > /tmp/a.md'
gt_b 'redirect in a nested bash -c'     WARN "bash -c 'echo x > /tmp/n.md'"
gt_b 'redirect after another command'   WARN 'cd x && echo hi > D:/tmp/a.md'
gt_b 'tee'                              WARN 'echo hi | tee /tmp/t.md'
gt_b 'tee -a'                           WARN 'echo hi | tee -a /tmp/t.md'
gt_b 'curl -o'                          WARN 'curl -o /tmp/o.bin http://x'
gt_b 'curl -sS -o: a switch before -o'    WARN 'curl -sS -o /tmp/r.json http://x'
gt_b 'curl -L -o: a switch before -o'     WARN 'curl -L -o /tmp/r.json http://x'
gt_b 'wget -q --output-document'          WARN 'wget -q --output-document /tmp/r.json http://x'
gt_b 'curl --output'                    WARN 'curl --output /tmp/o.bin http://x'
gt_b 'wget --output-document'           WARN 'wget --output-document /tmp/o.html http://x'
gt_b 'wget --output-document='          WARN 'wget --output-document=/tmp/o.html http://x'
gt_b 'gcc -o'                           WARN 'gcc -o /tmp/a.out x.c'
gt_b 'cp: the last word'                WARN 'cp a.md /tmp/c.md'
gt_b 'mv: the last word'                WARN 'mv a.md /tmp/m.md'
gt_b 'install: the last word'           WARN 'install -m 644 a /tmp/i'
gt_b 'cp behind sudo'                   WARN 'sudo cp a /tmp/c.md'
gt_b 'read: cat'                        PASS 'cat /tmp/a.md'
gt_b 'read: the source of cp'           PASS 'cp /tmp/a.md ./b.md'
gt_b 'read: the source of mv'           PASS 'mv /tmp/a.md ./b.md'
gt_b 'read: gh --body-file'             PASS 'gh pr edit 1 --body-file /tmp/b.md'
gt_b 'read: a redirect from the file'   PASS 'wc -l < /tmp/a.md'
gt_b 'read: ls of the folder'           PASS 'ls /tmp > ./list.txt'
gt_b 'read: tee to the project'         PASS 'echo hi | tee ./a.md'
gt_b 'read: 2>&1 is no file'            PASS 'make 2>&1'
gt_b 'read: grep -o is no output file'  PASS 'grep -o /tmp/x file'
gt_b 'a folder alone: mkdir'            PASS 'mkdir -p /tmp/dir'
gt_b 'a folder alone: cp to a folder'   PASS 'cp a /tmp/'
gt_b 'a folder alone: install -d'       PASS 'install -d /tmp/dir'
gt_b 'outside the list: touch'          PASS 'touch /tmp/a.md'
gt_b 'outside the list: rm'             PASS 'rm /tmp/a.md'
gt_b 'outside the list: sed -i'         PASS 'sed -i s/a/b/ /tmp/a.md'

echo "-- Bash: text, heredocs, comments and changing names --"
gt_b 'text in quotes'                   PASS 'echo "see > /tmp/a.md"'
gt_b 'text in single quotes'            PASS "git commit -m 'write to > /tmp/a.md'"
gt_b 'text after a flag of another cmd' PASS 'gh issue comment 1 --body "cp x /tmp/a.md"'
gt_b 'a path as plain text'             PASS 'echo see /tmp/a.md'
gt_b 'a comment'                        PASS 'echo x # > /tmp/a.md'
gt_b 'a quoted heredoc body'            PASS $'cat <<\'EOF\' > ./out.md\n> /tmp/x\ntee /tmp/y\nEOF'
gt_b 'an unquoted heredoc body'         PASS $'cat <<EOF > ./out.md\n> /tmp/x\nEOF'
gt_b 'a heredoc, the command after it'  WARN $'cat <<\'EOF\' > ./out.md\ntext\nEOF\necho x > /tmp/a.md'
gt_b 'a name with $$'                   PASS 'echo x > /tmp/f.$$'
gt_b 'a name with $RANDOM'              PASS 'echo x > /tmp/f.$RANDOM'
gt_b 'a name from mktemp'               PASS 'echo x > $(mktemp /tmp/x.XXXX)'
gt_b 'a name with a substitution'       PASS 'echo x > /tmp/f.$(date +%s)'
gt_b 'a name with backticks'            PASS 'echo x > /tmp/f.`date`'
gt_b 'a path with the session id'       PASS 'echo x > /tmp/gt-sid-1.md'
gt_b 'a path with the session id (cp)'  PASS 'cp a /tmp/gt-sid-1/b.md'

echo "-- PowerShell: the write places and their reads --"
gt_p 'Out-File -FilePath'               WARN 'Get-Date | Out-File -FilePath D:\tmp\o.txt'
gt_p 'Out-File positional'              WARN '"x" | Out-File D:\tmp\o.txt'
gt_p 'Set-Content -Path'                WARN 'Set-Content -Path D:\tmp\s.txt -Value x'
gt_p 'Set-Content positional'           WARN 'Set-Content D:\tmp\s.txt x'
gt_p 'Add-Content'                      WARN 'Add-Content D:\tmp\a.txt x'
gt_p 'New-Item -ItemType File'          WARN 'New-Item -ItemType File -Path D:\tmp\n.txt'
gt_p 'New-Item, no type'                WARN 'New-Item D:\tmp\n.txt'
gt_p 'New-Item -Path -Name'             WARN 'New-Item -Path D:\tmp -Name n.txt -ItemType File'
gt_p 'Copy-Item -Destination'           WARN 'Copy-Item a.txt -Destination D:\tmp\c.txt'
gt_p 'Move-Item -Destination'           WARN 'Move-Item -Path a.txt -Destination D:\tmp\m.txt'
gt_p 'Copy-Item, second positional'     WARN 'Copy-Item a.txt D:\tmp\c.txt'
gt_p 'Invoke-WebRequest -OutFile'       WARN 'Invoke-WebRequest http://x -OutFile D:\tmp\w.zip'
gt_p 'redirect >'                       WARN 'Get-Date > D:\tmp\r.txt'
gt_p 'redirect >>'                      WARN 'Get-Date >> D:\tmp\r.txt'
gt_p 'cp alias, last word'              WARN 'cp a.txt D:\tmp\c.txt -Force'
gt_p 'AppData Temp'                     WARN 'Set-Content C:\Users\u\AppData\Local\Temp\s.txt x'
gt_p 'read: Get-Content'                PASS 'Get-Content D:\tmp\a.txt'
gt_p 'read: the source of Copy-Item'    PASS 'Copy-Item D:\tmp\a.txt -Destination .\b.txt'
gt_p 'read: the source of Move-Item'    PASS 'Move-Item -Path D:\tmp\a.txt -Destination .\b.txt'
gt_p 'read: Out-File in the project'    PASS 'Get-Date | Out-File .\o.txt'
gt_p 'a folder alone: New-Item dir'     PASS 'New-Item -ItemType Directory -Path D:\tmp\d'
gt_p 'a program to start, -FilePath'    PASS 'Start-Process -FilePath D:\tmp\x.exe'
gt_p 'text in quotes'                   PASS 'Write-Output "Set-Content D:\tmp\x v"'
gt_p 'a single-quoted here-string body' PASS $'Set-Content .\\a.txt @\'\nSet-Content D:\\tmp\\x v\n> D:\\tmp\\y\n\'@'
gt_p 'a comment'                        PASS 'Get-Date # > D:\tmp\x'
gt_p 'a name with $PID'                 PASS 'Set-Content D:\tmp\f-$PID.txt x'
gt_p 'a name with a subexpression'      PASS 'Set-Content "D:\tmp\f-$(Get-Date -f s).txt" x'

echo "-- the temp variables --"
gt_b 'bash: $TEMP at the start'          WARN 'echo x > $TEMP/f.md'                 TEMP=/tmp/fake-temp
gt_b 'bash: $TMP at the start'           WARN 'echo x > $TMP/f.md'                  TMP=/tmp/fake-tmp
gt_b 'bash: ${TMPDIR}'                   WARN 'echo x > ${TMPDIR}/f.md'             TMPDIR=/tmp/fake-dir PLAYBOOK_TMP_GUARD_LOG="$gt_log"
gt_b 'bash: ${TMPDIR:-/tmp}, empty'      WARN 'echo x > ${TMPDIR:-/tmp}/f.md'       TMPDIR=
gt_b 'bash: $TEMP, no value'             PASS 'echo x > $TEMP/f.md'                 -u TEMP
gt_b 'bash: $TEMPFILE is another name'   PASS 'echo x > $TEMPFILE/f.md'             TEMP=/tmp/fake-temp
gt_b 'bash: $tmp is a script variable'   PASS 'tmp=$(mktemp); echo hi > "$tmp"'            TEMP=/tmp/fake-temp TMP=/tmp/fake-temp
gt_b 'bash: ${tmp} lower case'           PASS 'echo hi > ${tmp}/f.md'                    TMP=/tmp/fake-temp
gt_b 'bash: the value in the own area'   PASS 'echo x > $TEMP/f.md'                 TEMP=/tmp/proj-x CLAUDE_PROJECT_DIR=/tmp/proj-x
gt_b 'bash: a value outside the roots'   PASS 'echo x > $TEMP/f.md'                 TEMP=/home/u/work
gt_p 'powershell: $env:TEMP'             WARN 'Set-Content $env:TEMP\f.txt x'       TEMP=/tmp/fake-temp
gt_p 'powershell: $env:TMP'              WARN 'Set-Content $env:TMP\f.txt x'        TMP=/tmp/fake-tmp
gt_p 'powershell: %TEMP%'                WARN 'Set-Content %TEMP%\f.txt x'          TEMP=/tmp/fake-temp
gt_p 'powershell: $env:TEMP with $PID'   PASS 'Set-Content $env:TEMP\f-$PID.txt x'  TEMP=/tmp/fake-temp
gt_p 'powershell: read from $env:TEMP'   PASS 'Get-Content $env:TEMP\f.txt'         TEMP=/tmp/fake-temp
gt_p 'powershell: $tmp is a script variable' PASS '$tmp = Join-Path $x "f.md"; Set-Content -Path $tmp -Value 1' TEMP=/tmp/fake-temp TMP=/tmp/fake-temp
gt_p 'powershell: bare $TEMP is no environment' PASS 'Set-Content $TEMP.txt x'    TEMP=/tmp/fake-temp

echo "-- the switch, the answers and the way out --"
gt_ev_w() { gt_ev Write file_path "$1" gt-sid-1 "${2:-}"; } # path, [scratchpad_dir]
o="$(gt_hook "$(gt_ev_w '/tmp/prbody.md' "$gt_pad")")"
expect 'warn is the default'                     WARN "$(gt_verdict "$o")"
check_contains 'warn names the path'             '/tmp/prbody.md' "$o"
check_contains 'warn names the way out'          "$gt_pad_j/prbody.md" "$o"
check_not_contains 'warn rewrites nothing'       'updatedInput' "$o"
check_not_contains 'warn takes no decision'      'permissionDecision' "$o"
check_contains 'warn answers as PreToolUse'      '"hookEventName":"PreToolUse"' "$o"
expect 'PLAYBOOK_TMP_GUARD=warn'                 WARN "$(gt_verdict "$(gt_hook "$(gt_ev_w /tmp/a.md "$gt_pad")" PLAYBOOK_TMP_GUARD=warn)")"
expect 'PLAYBOOK_TMP_GUARD=off'                  PASS "$(gt_verdict "$(gt_hook "$(gt_ev_w /tmp/a.md "$gt_pad")" PLAYBOOK_TMP_GUARD=off)")"
expect 'an unknown value is warn'                WARN "$(gt_verdict "$(gt_hook "$(gt_ev_w /tmp/a.md "$gt_pad")" PLAYBOOK_TMP_GUARD=maybe)")"
expect 'an empty value is warn'                  WARN "$(gt_verdict "$(gt_hook "$(gt_ev_w /tmp/a.md "$gt_pad")" PLAYBOOK_TMP_GUARD=)")"
o="$(gt_hook "$(gt_ev_w '/tmp/prbody.md' "$gt_pad")" PLAYBOOK_TMP_GUARD=block)"
expect 'block denies'                            DENY "$(gt_verdict "$o")"
check_contains 'block gives the same way out'    "$gt_pad_j/prbody.md" "$o"
expect 'block leaves a clean write alone'        PASS "$(gt_verdict "$(gt_hook "$(gt_ev_w ./a.md "$gt_pad")" PLAYBOOK_TMP_GUARD=block)")"
expect 'block on a shell write'                  DENY "$(gt_verdict "$(gt_hook "$(gt_ev Bash command 'echo x > /tmp/a.md' gt-sid-1 "$gt_pad")" PLAYBOOK_TMP_GUARD=block)")"
# No scratchpad_dir and none derived: it stays at warn, and the way out is a name with the session id.
o="$(gt_hook "$(gt_ev_w '/tmp/prbody.md')" PLAYBOOK_TMP_GUARD=block)"
expect 'block without a scratchpad stays warn'   WARN "$(gt_verdict "$o")"
check_contains 'without a scratchpad: own id'    'gt-sid-1-prbody.md' "$o"
check_contains 'without a scratchpad: mktemp'    'mktemp' "$o"
# A scratchpad derived from the temp folder where it exists.
gt_der="$gt_dir/derived"; mkdir -p "$gt_der/claude/h/gt-sid-1/scratchpad"
o="$(gt_hook "$(gt_ev_w '/tmp/prbody.md')" PLAYBOOK_TMP_GUARD=block TMPDIR="$gt_der")"
expect 'a derived scratchpad lets block deny'    DENY "$(gt_verdict "$o")"
check_contains 'the derived scratchpad is named' "claude/h/gt-sid-1/scratchpad/prbody.md" "$o"
o="$(gt_hook "$(gt_ev Write file_path /tmp/a.md other-sid '')" PLAYBOOK_TMP_GUARD=block TMPDIR="$gt_der")"
expect "another session's scratchpad is no way out" WARN "$(gt_verdict "$o")"
expect 'CLAUDE_CODE_REMOTE=true is silent'       PASS "$(gt_verdict "$(gt_hook "$(gt_ev_w /tmp/a.md "$gt_pad")" CLAUDE_CODE_REMOTE=true PLAYBOOK_TMP_GUARD=block)")"
expect 'CLAUDE_CODE_REMOTE=false is not'         WARN "$(gt_verdict "$(gt_hook "$(gt_ev_w /tmp/a.md "$gt_pad")" CLAUDE_CODE_REMOTE=false)")"
o="$(gt_hook "$(gt_ev Bash command 'echo a > /tmp/a.md; echo b > /tmp/a.md; cp x D:/tmp/c.md' gt-sid-1 "$gt_pad")")"
check_contains 'several hits: the first named'   '/tmp/a.md ->' "$o"
check_contains 'several hits: the second named'  'D:/tmp/c.md ->' "$o"
expect 'one hit is named once'                   1 "$(gt_count '/tmp/a.md ->' "$o")"

echo "-- the log of the hits --"
rm -f "$gt_log"
gt_hook "$(gt_ev_w /tmp/log-a.md "$gt_pad")" >/dev/null
gt_hook "$(gt_ev_w ./clean.md "$gt_pad")" >/dev/null
gt_hook "$(gt_ev Bash command 'echo x > /tmp/log-b.md' gt-sid-1 "$gt_pad")" PLAYBOOK_TMP_GUARD=block >/dev/null
gt_hook "$(gt_ev_w /tmp/log-c.md "$gt_pad")" PLAYBOOK_TMP_GUARD=off >/dev/null
expect 'a hit is a line, a clean call none'      2 "$(jq -s 'length' "$gt_log" | tr -d '\r')"
expect 'the line holds session, tool, path, level' 'gt-sid-1 Write /tmp/log-a.md warn' "$(jq -rs '.[0] | "\(.session) \(.tool) \(.path) \(.level)"' "$gt_log" | tr -d '\r')"
expect 'the second line is the block'            'Bash /tmp/log-b.md block' "$(jq -rs '.[1] | "\(.tool) \(.path) \(.level)"' "$gt_log" | tr -d '\r')"
expect 'the stamp is UTC'                        1 "$(jq -rs '.[0].ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") | if . then 1 else 0 end' "$gt_log" | tr -d '\r')"
rm -f "$gt_log"
gt_hook "$(gt_ev_w /tmp/log-d.md)" PLAYBOOK_TMP_GUARD=block >/dev/null
expect 'block without scratchpad logs as warn'   warn "$(jq -rs '.[0].level' "$gt_log" | tr -d '\r')"
# Without PLAYBOOK_TMP_GUARD_LOG the line lies beside the other hooks' state files.
printf '%s' "$(gt_ev_w /tmp/log-e.md "$gt_pad")" | env -u PLAYBOOK_TMP_GUARD_LOG TMPDIR="$gt_dir/gate" "$BASH" "$gtguard" >/dev/null 2>&1
expect 'the default log is in claude-rule-gate'  1 "$([ -s "$gt_dir/gate/claude-rule-gate/tmp-guard-log.jsonl" ] && echo 1 || echo 0)"

echo "-- no process where nothing is to check, fail-open everywhere else --"
gt_wrap() { # dir, name, real path: a stand-in that logs its start, then runs the real one
  printf '#!%s\necho %s >> "%s"\nexec "%s" "$@"\n' "$BASH" "$2" "$calls" "$3" > "$1/$2"; chmod +x "$1/$2"
}
gt_cnt="$gt_dir/count"; mkdir -p "$gt_cnt"
gt_wrap "$gt_cnt" jq "$real_jq"; gt_wrap "$gt_cnt" awk "$gt_real_awk"
gt_calls() { # envelope [env...] -> the programs the hook started (jq, awk) as one line
  : > "$calls"; gt_hook "$1" "${@:2}" PATH="$gt_cnt:$PATH" >/dev/null
  tr -d '\r' < "$calls" | tr '\n' ' '
}
expect 'a call with no temp path starts nothing'    '' "$(gt_calls "$(gt_ev Bash command 'git status' gt-sid-1 "$gt_pad")")"
expect 'a Write in the project starts nothing'      '' "$(gt_calls "$(gt_ev Write file_path './docs/a.md' gt-sid-1 "$gt_pad")")"
expect 'a template folder starts nothing'           '' "$(gt_calls "$(gt_ev Bash command 'cat docs/templates-x.md' gt-sid-1 "$gt_pad")")"
expect 'the envelope folders alone start nothing'   '' "$(gt_calls "$(gt_ev Bash command 'ls' gt-sid-1 "$gt_pad")")"
expect 'a read of a temp path starts no awk'        'jq ' "$(gt_calls "$(gt_ev Bash command 'cat /tmp/a.md' gt-sid-1 "$gt_pad")")"
expect 'a read with 2>/dev/null starts no awk'       'jq ' "$(gt_calls "$(gt_ev Bash command 'cat /tmp/a.md 2>/dev/null; ls /tmp 2>&1' gt-sid-1 "$gt_pad")")"
expect 'a shell hit starts jq once, awk once'       'jq awk ' "$(gt_calls "$(gt_ev Bash command 'echo x > /tmp/a.md' gt-sid-1 "$gt_pad")")"
expect 'a Write hit starts jq only'                 'jq ' "$(gt_calls "$(gt_ev Write file_path '/tmp/a.md' gt-sid-1 "$gt_pad")")"
expect 'PLAYBOOK_TMP_GUARD=off starts nothing'      '' "$(gt_calls "$(gt_ev Write file_path '/tmp/a.md' gt-sid-1 "$gt_pad")" PLAYBOOK_TMP_GUARD=off)"
expect 'a web session starts nothing'               '' "$(gt_calls "$(gt_ev Write file_path '/tmp/a.md' gt-sid-1 "$gt_pad")" CLAUDE_CODE_REMOTE=true)"
# Fail-open: each way ends without output and with status 0.
gt_bin() { # name, [tools to leave out] -> a PATH folder with wrappers of the tools the hook needs
  local d="$gt_dir/bin-$1" t; shift; mkdir -p "$d"
  for t in cat mkdir uname jq awk timeout; do
    case " $* " in *" $t "*) continue ;; esac
    command -v "$t" >/dev/null 2>&1 || continue
    printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$(command -v "$t")" > "$d/$t"; chmod +x "$d/$t"
  done
  printf '%s' "$d"
}
gt_status() { # envelope, PATH -> the exit status and whether anything was printed
  local o rc
  o="$(printf '%s' "$1" | env TMPDIR="$gt_dir/gate" PLAYBOOK_TMP_GUARD_LOG="$gt_log" PATH="$2" "$BASH" "$gtguard" 2>/dev/null)"; rc=$?
  printf '%s %s' "$rc" "$([ -n "$o" ] && echo out || echo none)"
}
gt_hit="$(gt_ev Bash command 'echo x > /tmp/a.md' gt-sid-1 "$gt_pad")"
expect 'the same call warns with every program' '0 out'  "$(gt_status "$gt_hit" "$(gt_bin all)")"
expect 'no jq: through'                         '0 none' "$(gt_status "$gt_hit" "$(gt_bin nojq jq)")"
expect 'no awk: through'                        '0 none' "$(gt_status "$gt_hit" "$(gt_bin noawk awk)")"
expect 'a broken envelope: through'             '0 none' "$(gt_status '{"tool_name":"Bash","tool_input":{"command":"echo x > /tmp/a.md"' "$(gt_bin all)")"
expect 'an envelope that is no JSON: through'   '0 none' "$(gt_status 'echo x > /tmp/a.md' "$(gt_bin all)")"
expect 'an empty envelope: through'             '0 none' "$(gt_status '' "$(gt_bin all)")"
gt_to="$(gt_bin tmo timeout)"; printf '#!%s\nexit 124\n' "$BASH" > "$gt_to/timeout"; chmod +x "$gt_to/timeout"
expect 'a timeout of jq and awk: through'       '0 none' "$(gt_status "$gt_hit" "$gt_to")"
gt_bad="$(gt_bin badawk awk)"; printf '#!%s\nexit 3\n' "$BASH" > "$gt_bad/awk"; chmod +x "$gt_bad/awk"
expect 'an awk that fails: through'             '0 none' "$(gt_status "$gt_hit" "$gt_bad")"
gt_badjq="$(gt_bin badjq jq)"; printf '#!%s\nexit 3\n' "$BASH" > "$gt_badjq/jq"; chmod +x "$gt_badjq/jq"
expect 'a jq that fails: through'               '0 none' "$(gt_status "$gt_hit" "$gt_badjq")"
expect 'no timeout program: it still works'     '0 out'  "$(gt_status "$gt_hit" "$(gt_bin notmo timeout)")"
expect 'a write with no file_path: through'     '0 none' "$(gt_status '{"tool_name":"Write","session_id":"s","tool_input":{"content":"/tmp/x"}}' "$(gt_bin all)")"
expect 'a command that is no string: through'   '0 none' "$(gt_status '{"tool_name":"Bash","session_id":"s","tool_input":{"command":["/tmp/x"]}}' "$(gt_bin all)")"

echo "-- the replay over transcripts --"
gt_rp="$gt_dir/replay/proj"; mkdir -p "$gt_rp"
printf -v gt_now '%(%Y-%m-%dT%H:%M:%S)T.000Z' -1
gt_call() { # time, session, tool, key, value -> one assistant line with one tool call
  local k v; js "$4"; k="$REPLY"; js "$5"; v="$REPLY"
  printf '{"type":"assistant","timestamp":"%s","sessionId":"%s","message":{"content":[{"type":"tool_use","name":"%s","input":{%s:%s}}]}}\n' "$1" "$2" "$3" "$k" "$v"
}
{
  gt_call "$gt_now" sess-a Write file_path '/tmp/replay-a.md'
  gt_call "$gt_now" sess-a Bash command 'echo x > /tmp/replay-b.md'
  gt_call "$gt_now" sess-a Bash command 'cat /tmp/replay-c.md'
  gt_call "$gt_now" sess-a Bash command 'echo x > /tmp/sess-a-own.md'
  gt_call "$gt_now" sess-b PowerShell command 'Set-Content D:\tmp\replay-d.txt x'
  gt_call "$gt_now" sess-b Read file_path '/tmp/replay-e.md'
  gt_call "$gt_now" sess-b Write file_path 'D:\tmp\claude-sessions\claude\abc123\01a1b8fe-9acd-7f48-be72-c936ad92f266\scratchpad\resumed.md'
  gt_call "$gt_now" sess-b Bash command 'echo x > /tmp/claude-0/-home-user-proj/web-own.txt'
  gt_call '2020-01-01T00:00:00.000Z' sess-b Write file_path '/tmp/replay-old.md'
  printf '%s\n' '{"type":"user","message":{"content":"/tmp/replay-f.md"}}'
} > "$gt_rp/s.jsonl"
gt_replay="$hooks/tests/replay-tmp-guard.sh"
o="$(bash "$gt_replay" --days 7 --root "$gt_dir/replay" 2>&1 | tr -d '\r')"
check_line 'replay: the calls of the five tools'  'CALLS 7' "$o"
check_line 'replay: the hits'                     'HITS 3' "$o"
check_line 'replay: the sessions with a hit'      'HIT-SESSIONS 2' "$o"
check_line 'replay: the distinct paths'           'HIT-PATHS 3' "$o"
check_line 'replay: own scratchpad and web area left out'  'OWN-AREA 2' "$o"
check_contains 'replay: a hit line names the path and the call' 'HIT ' "$o"
check_contains 'replay: the write is named'       '/tmp/replay-b.md' "$o"
check_not_contains 'replay: a read is no hit'     'replay-c.md' "$o"
check_not_contains 'replay: the own id is no hit' 'sess-a-own' "$o"
check_not_contains 'replay: a call past the window' 'replay-old' "$o"
o="$(bash "$gt_replay" --days 7 --root "$gt_dir/replay" --quiet 2>&1 | tr -d '\r')"
check_not_contains 'replay --quiet: sums only'    'HIT /' "$o"
expect 'replay: no folder is exit 2'              2 "$(bash "$gt_replay" --root "$gt_dir/none" >/dev/null 2>&1; echo $?)"
expect 'replay: a bad --days is exit 2'           2 "$(bash "$gt_replay" --days x --root "$gt_dir/replay" >/dev/null 2>&1; echo $?)"

finish
