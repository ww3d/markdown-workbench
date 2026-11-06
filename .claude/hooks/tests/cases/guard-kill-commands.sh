#!/usr/bin/env bash
# Hook suite section: guard-kill.sh, process-ending commands
# Run alone: bash .claude/hooks/tests/cases/guard-kill-commands.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-kill.sh: process-ending commands =="
# MSYS_NO_PATHCONV: Git Bash would rewrite an argument that starts with a slash (/bin/kill) into a Windows path.
# one target by number -> deny, the reason names it and the rule
chk_kill 'kill one PID'                        deny   Bash       'kill 1234'                                  '1234'
chk_kill 'kill -9 one PID'                     deny   Bash       'kill -9 1234'                               '1234'
chk_kill 'taskkill /PID'                       deny   Bash       'taskkill /PID 1234 /F'                      '1234'
chk_kill 'taskkill, Git Bash spelling'         deny   Bash       'taskkill //PID 1234 //F'                    '1234'
chk_kill 'taskkill one exact image'            deny  Bash       'taskkill /IM notepad.exe'                   'notepad.exe'
chk_kill 'Stop-Process -Id'                    deny   PowerShell 'Stop-Process -Id 4242'                      '4242'
chk_kill 'Stop-Process -Name, no wildcard'     deny  PowerShell 'Stop-Process -Name notepad -Force'          'notepad'
chk_kill 'spps alias'                          deny   PowerShell 'spps -Id 12'                                '12'
chk_kill 'kill alias in PowerShell'            deny   PowerShell 'kill 12'                                    '12'
chk_kill 'wmic, one process id'                deny   Bash       'wmic process where processid=77 delete'     '77'
chk_kill 'the reason names rule K5'            deny   Bash       'kill 1234'                                  'Core rule K5'
# nested ways
chk_kill 'powershell -Command'                 deny   Bash       'powershell -Command "Stop-Process -Id 4242"' '4242'
chk_kill 'pwsh -c'                             deny   Bash       'pwsh -NoProfile -c "Stop-Process -Id 4242"'  '4242'
chk_kill 'cmd /c'                              deny   Bash       'cmd /c taskkill /PID 99'                    '99'
chk_kill 'bash -c'                             deny   PowerShell "bash -c 'kill 55'"                          '55'
chk_kill 'after && in a longer line'           deny   Bash       'cd x && kill 77 && echo done'               '77'
chk_kill 'sudo kill'                           deny   Bash       'sudo kill 31'                               '31'
enc="$(printf 'Stop-Process -Id 4242' | sed 's/./&\x00/g' | base64 -w0)"
chk_kill 'pwsh -EncodedCommand, decoded'       deny   Bash       "pwsh -EncodedCommand $enc"                  '4242'
enc_bulk="$(printf 'Stop-Process -Name a*' | sed 's/./&\x00/g' | base64 -w0)"
chk_kill 'encoded broad ending'                deny  Bash       "pwsh -enc $enc_bulk"
# broad ending -> deny
chk_kill 'taskkill /IM *'                      deny  Bash       'taskkill /IM *'
chk_kill 'taskkill /FI'                        deny  Bash       'taskkill /FI "imagename eq a.exe"'
chk_kill 'taskkill two images'                 deny  Bash       'taskkill /IM a.exe /IM b.exe'
chk_kill 'pkill -f'                            deny  Bash       'pkill -f node'
chk_kill 'pkill, a wildcard in the name'       deny  Bash       'pkill "node*"'
chk_kill 'pkill, two names'                    deny  Bash       'pkill node npm'
chk_kill 'killall, a wildcard in the name'     deny  Bash       "killall 'a*'"
chk_kill 'killall -r, a regular expression'    deny  Bash       'killall -r node'
chk_kill 'skill, two names'                    deny  Bash       'skill node npm'
chk_kill 'kill several PIDs'                   deny   Bash       'kill -9 1 2'
chk_kill 'kill 0, the process group'           deny  Bash       'kill 0'
chk_kill 'kill -1, every process'              deny  Bash       'kill -9 -1'
chk_kill 'kill a computed list'                deny  Bash       'kill $(pgrep node)'
chk_kill 'xargs kill'                          deny  Bash       'ps aux | xargs kill'
chk_kill 'two kills in one line'               deny   Bash       'kill 3; kill 4'
chk_kill 'Stop-Process -Name with wildcard'    deny  PowerShell 'Stop-Process -Name foo*'
chk_kill 'Stop-Process several ids'            deny   PowerShell 'Stop-Process -Id 12,13'
chk_kill 'Get-Process | Stop-Process'          deny  PowerShell 'Get-Process foo | Stop-Process'
chk_kill 'Get-Process | kill'                  deny  PowerShell 'Get-Process notepad | kill'
chk_kill 'pwsh -c with a pipeline'             deny  Bash       'pwsh -NoProfile -Command "Get-Process foo | Stop-Process"'
chk_kill 'wmic by condition'                   deny  Bash       "wmic process where \"name like '%a%'\" call terminate"
chk_kill 'the deny reason names rule K5'       deny  Bash       "killall 'a*'"                               'Core rule K5'
# A reason must name every target; the check reads the reason of a second run of the same command.
chk_has() { check_contains "$1" "$2" "$(kill_out "$3" "$4")"; }
# gap A: one target by number in a script block is denied, whatever the block (the closing brace is no target)
chk_kill 'A: call operator block'              deny   PowerShell '& { Stop-Process -Id 3568 }'                '3568'
chk_kill 'A: if block'                         deny   PowerShell 'if ($true) { Stop-Process -Id 3568 }'       '3568'
chk_kill 'A: Invoke-Command block'             deny   PowerShell 'Invoke-Command { Stop-Process -Id 3568 }'   '3568'
chk_kill 'A: foreach block'                    deny   PowerShell 'foreach ($i in 1) { Stop-Process -Id 3568 }' '3568'
chk_kill 'A: nested in powershell -Command'    deny   Bash       'powershell -NoProfile -Command "& { Stop-Process -Id 3568 }"' '3568'
chk_kill 'A: nested in pwsh -c, if block'      deny   Bash       'pwsh -c "if ($true) { Stop-Process -Id 3568 }"' '3568'
chk_kill 'A: kill alias in a block'            deny   PowerShell '& { kill 3568 }'                            '3568'
# the closing brace must not be named as a second target
chk_lacks() { # label, needle, tool, command
  if has_text "$2" "$(kill_out "$3" "$4")"; then bad "$1" "found: $2" "absent"; else ok "$1" "absent"; fi
}
chk_lacks 'A: the brace is no target (call operator)'  'stop-process }' PowerShell '& { Stop-Process -Id 3568 }'
chk_lacks 'A: the brace is no target (if)'             'stop-process }' PowerShell 'if ($true) { Stop-Process -Id 3568 }'
chk_lacks 'A: the brace is no target (Invoke-Command)' 'stop-process }' PowerShell 'Invoke-Command { Stop-Process -Id 3568 }'
chk_lacks 'A: the brace is no target (foreach)'        'stop-process }' PowerShell 'foreach ($i in 1) { Stop-Process -Id 3568 }'
# A value parameter of PowerShell consumes its value: `-ErrorAction Stop` names no target (ww3d/playbook#531).
chk_kill 'Stop-Process -ErrorAction Stop'      deny   PowerShell 'Stop-Process -Id 4242 -ErrorAction Stop'    'stop-process 4242'
chk_lacks 'a value parameter is no target'     'stop-process stop' PowerShell 'Stop-Process -Id 4242 -ErrorAction Stop'
chk_lacks 'value parameters, short forms'      'without a readable target' PowerShell \
  'Stop-Process 4242 -ea SilentlyContinue -wa Ignore -infa Ignore -proga Ignore -ev e -wv w -iv i -ov o -ob 2 -pv p'
chk_lacks 'value parameters, short forms, no value as target' 'stop-process 2' PowerShell \
  'Stop-Process 4242 -ea SilentlyContinue -wa Ignore -infa Ignore -proga Ignore -ev e -wv w -iv i -ov o -ob 2 -pv p'
chk_lacks 'value parameters, long forms'       'without a readable target' PowerShell \
  'Stop-Process -Id 4242 -WarningAction Ignore -InformationAction Ignore -ProgressAction Ignore -ErrorVariable e -WarningVariable w -InformationVariable i -OutVariable o -OutBuffer 2 -PipelineVariable p'
chk_lacks 'value parameters, long forms, no value as target' 'stop-process 2' PowerShell \
  'Stop-Process -Id 4242 -WarningAction Ignore -InformationAction Ignore -ProgressAction Ignore -ErrorVariable e -WarningVariable w -InformationVariable i -OutVariable o -OutBuffer 2 -PipelineVariable p'
chk_lacks 'value parameters by a prefix'         'without a readable target' PowerShell 'Stop-Process -Id 4242 -ErrorAct Stop -WarningAc Ignore -OutVar o'
chk_lacks 'value parameters by their shortest prefix' 'without a readable target' PowerShell 'Stop-Process -Id 4242 -pr Ignore -pi p'
chk_has  'the -Name:Value form consumes nothing further' 'stop-process 4242' PowerShell 'Stop-Process -ErrorAction:Stop 4242'
chk_kill 'a positional word is no named target' deny  PowerShell 'Stop-Process foo'                            'without a readable target'
chk_lacks 'a positional word is not named as a target' 'stop-process foo' PowerShell 'Stop-Process foo'
chk_lacks 'A: the brace is no target (kill alias)'     'kill }' PowerShell '& { kill 3568 }'
# several numbers named outright are denied, and the reason names each
chk_kill 'several PIDs after kill'             deny   Bash       'kill 1 2'                                   'kill 2'
chk_has  'several PIDs after kill: first'      'kill 1'         Bash 'kill 1 2'
chk_kill 'Stop-Process -Id 1,2'                deny   PowerShell 'Stop-Process -Id 1,2'                       'stop-process 2'
chk_has  'Stop-Process -Id 1,2: first'         'stop-process 1' PowerShell 'Stop-Process -Id 1,2'
chk_kill 'taskkill /PID twice'                 deny   Bash       'taskkill /PID 1 /PID 2'                     'pid 2'
chk_has  'taskkill /PID twice: first'          'pid 1'          Bash 'taskkill /PID 1 /PID 2'
chk_kill 'two kills, one number each'          deny   Bash       'kill 1; kill 2'                             'kill 2'
chk_has  'two kills: first'                    'kill 1'         Bash 'kill 1; kill 2'
chk_kill 'Stop-Process then taskkill'          deny   PowerShell 'Stop-Process -Id 1; taskkill /PID 2'        'pid 2'
chk_has  'Stop-Process then taskkill: first'   'stop-process 1' PowerShell 'Stop-Process -Id 1; taskkill /PID 2'
# an ending by one name, no pattern, is blocked, and the reason points at the way: the number
chk_kill 'by name: taskkill /IM'               deny  Bash       'taskkill /IM rc.exe'                        'rc.exe'
chk_kill 'by name: Stop-Process -Name'         deny  PowerShell 'Stop-Process -Name rc'                      'rc'
chk_kill 'by name: pkill'                      deny  Bash       'pkill rc'                                   'rc'
chk_kill 'by name: killall'                    deny  Bash       'killall rc'                                 'rc'
chk_kill 'by name: skill'                      deny  Bash       'skill rc'                                   'rc'
chk_kill 'by name: pskill'                     deny  Bash       'pskill notepad'                             'notepad'
chk_kill 'by name: Stop-Process -Name, a list' deny  PowerShell 'Stop-Process -Name a,b'
chk_kill 'by name: held in a variable'         deny  PowerShell 'Stop-Process -Name $n'                      'variable'
chk_has  'by name: the reason names the way'   'by its number'  Bash 'pkill rc'
chk_has  'by name: the way goes to the owner'  'owner of this session' Bash 'taskkill /IM rc.exe'
chk_kill 'by name mixed with a number'         deny  Bash       'kill 1; pkill rc'
chk_kill 'by name mixed, PowerShell'           deny  PowerShell 'Stop-Process -Id 1; Stop-Process -Name rc'
chk_kill 'by name mixed, one taskkill'         deny  Bash       'taskkill /PID 1 /IM rc.exe'
# gap B: a loop over Get-Process into an ending is a broad ending
chk_kill 'B: ForEach-Object Stop-Process'      deny  PowerShell 'Get-Process claude | ForEach-Object { Stop-Process -Id $_.Id }' 'process list'
chk_kill 'B: ForEach-Object .Kill()'           deny  PowerShell 'Get-Process claude | ForEach-Object { $_.Kill() }'
chk_kill 'B: % with the kill alias'            deny  PowerShell 'Get-Process claude | % { kill $_.Id }'
chk_kill 'B: foreach statement over Get-Process' deny PowerShell 'foreach ($p in Get-Process claude) { Stop-Process -Id $p.Id }'
chk_kill 'B: gps alias'                        deny  PowerShell 'gps claude | % { spps -Id $_.Id }'
chk_kill 'B: nested in pwsh -c'                deny  Bash       'pwsh -c "Get-Process claude | ForEach-Object { Stop-Process -Id $_.Id }"'
chk_kill 'B: .Kill() on a list beside a number'  deny  PowerShell 'kill 1; Get-Process claude | ForEach-Object { $_.Kill() }'
chk_kill 'B: .Kill() on a list beside Stop-Process' deny PowerShell 'Stop-Process -Id 5; (Get-Process claude).Kill()'
chk_kill 'B: .Kill() on a list beside a CIM process id' deny PowerShell 'Get-CimInstance Win32_Process -Filter "ProcessId=5" | Invoke-CimMethod -MethodName Terminate; (Get-Process claude).Kill()'
chk_kill 'B: a loop .Kill() beside a CIM process id' deny PowerShell 'Get-CimInstance Win32_Process -Filter "ProcessId=5" | Invoke-CimMethod -MethodName Terminate; Get-Process claude | % { $_.Kill() }'
chk_kill 'B: a listing next to a number is still denied' deny PowerShell 'Get-Process -Id 5; Stop-Process -Id 5'  '5'
chk_kill 'B: a listing alone passes'           allow PowerShell 'Get-Process claude | Select-Object Id'
# gap C: a CIM / WMI query chosen by name or command line is a broad ending,
# a process id alone is denied with the owner's way
chk_kill 'C: Get-CimInstance, command line'    deny  PowerShell "Get-CimInstance Win32_Process -Filter \"CommandLine like '%x%'\" | Invoke-CimMethod -MethodName Terminate"
chk_kill 'C: Get-WmiObject, name, .Terminate()' deny PowerShell "(Get-WmiObject Win32_Process -Filter \"Name='rc.exe'\").Terminate()"
chk_kill 'C: Get-CimInstance, no filter'       deny  PowerShell 'Get-CimInstance Win32_Process | Invoke-CimMethod -MethodName Terminate'
chk_kill 'C: nested in powershell -Command'    deny  Bash       'powershell -Command "Get-WmiObject Win32_Process | ForEach-Object { $_.Terminate() }"'
chk_kill 'C: a query by name'                  deny  PowerShell 'Invoke-CimMethod -Query "select * from win32_process where name = '"'"'rc.exe'"'"'" -MethodName Terminate'
chk_kill 'C: a filter on one process id is denied'  deny   PowerShell 'Get-CimInstance Win32_Process -Filter "ProcessId=3568" | Invoke-CimMethod -MethodName Terminate' '3568'
chk_kill 'C: WMI, one process id is denied'         deny   PowerShell '(Get-WmiObject Win32_Process -Filter "ProcessId=3568").Terminate()' '3568'
chk_kill 'C: wmic, one process id is denied'        deny   Bash       'wmic process where processid=3568 call terminate' '3568'
chk_kill 'C: a process id and a name'          deny  PowerShell 'Get-CimInstance Win32_Process -Filter "ProcessId=3568 or Name=1" | Invoke-CimMethod -MethodName Terminate'
# a backslash-escaped double quote does not close the quoted span of a nested command
chk_kill 'escaped backslash: a number is found' deny  Bash       'echo "C:\\"; kill 1234; echo "x"'               '1234'
chk_kill 'escaped backslash: a name is found'  deny  Bash       'cd "C:\\Users\\"; taskkill /IM rc.exe /F; echo "done"' 'rc.exe'
chk_kill 'escaped backslash: pkill is found'   deny  Bash       'echo "a\\" && pkill rc && echo "b"'             'pkill rc'
chk_kill 'grep -E pattern in quotes is data'    allow Bash       "x | grep -E '(stop|kill)' | head"
chk_kill 'rg -e pattern in quotes is data'      allow Bash       "rg -e '(pkill node)' ."
chk_kill 'bash -c after a grep still runs'      deny  Bash       "grep -e x f && bash -c 'pkill node'"
chk_kill 'a shell in $( after a grep still runs'   deny  Bash       'grep foo $(bash -c "pkill node")'
chk_kill 'a shell on the next line after a grep'   deny  Bash       'grep foo file
bash -c "pkill node"'
chk_kill 'a shell in <( after an rg still runs'    deny  Bash       'rg x <(sh -c "pkill node")'
chk_kill 'a shell in $( after a jq still runs'     deny  Bash       'jq -r .x f $(bash -c "pkill node")'
chk_kill 'a shell in backticks after a grep'       deny  Bash       'grep x `bash -c "pkill node"`'
chk_kill 'a heredoc piped on into a shell'         deny  Bash       'cat <<EOF | \
bash
pkill node
EOF'
chk_kill 'a heredoc whose opener follows the shell' deny Bash       "bash \\
<<'EOF'
pkill node
EOF"
chk_kill 'a heredoc after a continued data line'   allow Bash       "cat \\
<<'EOF'
pkill node
EOF"
# a body stays text only where every command outside the bodies is a listed one (ww3d/playbook#511)
chk_kill 'a heredoc whose pipe goes on after the end word' deny Bash 'cat <<EOF |
pkill node
EOF
bash'
chk_kill 'a heredoc continued twice into a shell'  deny  Bash       "cat <<EOF \\
| \\
bash
pkill node
EOF"
chk_kill 'a shell on a later line keeps the body code' deny Bash "cat <<'EOF' > n.md
pkill node
EOF
bash x.sh"
chk_kill 'a shell behind a wrapper keeps the body code' deny Bash "cat <<'EOF' | sudo -u x bash
pkill node
EOF"
chk_kill 'a variable as the command keeps the body code' deny Bash 'cat <<EOF | $SHELL
pkill node
EOF'
chk_kill 'a braced variable as the command too'    deny  Bash       'cat <<EOF | ${X}
pkill node
EOF'
chk_kill 'a heredoc chained on without a shell is data' allow Bash 'cat <<EOF &&
pkill node
EOF
true'
chk_kill 'a shell name as an argument is data'     allow Bash       "cat <<'EOF' | tee bash.log
pkill node
EOF"
chk_kill 'the word env as an argument is data'     allow Bash       "cat <<'EOF' | jq -r .env
pkill node
EOF"
chk_kill 'a ./path beside a heredoc is data'       allow Bash       "cat <<'EOF' > ./pfad/n.md
pkill node
EOF
git add ./pfad"
chk_kill 'a variable as an argument is data'       allow Bash       'cat <<EOF > n.md
pkill node
EOF
echo $cmd'
chk_kill 'a ./path in a later command is data'     allow Bash       "cat > n.md <<'EOF'
Stop-Process -Id 3260
EOF
git -C ./repo status"
chk_kill 'a variable before the heredoc is data'   allow Bash       "echo \$cmd; cat > n.md <<'EOF'
Stop-Process -Id 3260
EOF"
chk_kill 'the word env in a later command is data' allow Bash       "cat > n.md <<'EOF'
Stop-Process -Id 3260
EOF
echo see env"
chk_kill 'a shell variable fed a kill by number'   deny  Bash       'cat <<EOF | $SHELL
kill 1234
EOF'
chk_kill 'a commit message from a heredoc is data' allow Bash       "git commit -F - <<'EOF'
fix: guard Stop-Process -Id 3260
EOF"
chk_kill 'a shell reading a heredoc'               deny  Bash       'bash <<EOF
kill 1234
EOF'
chk_kill 'a shell with the opener stuck to it'     deny  Bash       'bash<<EOF
kill 1234
EOF'
chk_kill 'a quoted heredoc stuck to sh'            deny  Bash       "sh<<'EOF'
kill 1234
EOF"
chk_kill 'python with the opener stuck to it'      deny  Bash       'python3<<EOF
kill 1234
EOF'
chk_kill 'a shell with a redirection stuck to it'  deny  Bash       'bash>log <<EOF
kill 1234
EOF'
chk_kill 'a pipe without spaces into a shell'      deny  Bash       'cat <<EOF|bash
kill 1234
EOF'
chk_kill 'an unlisted program reading a heredoc'   deny  Bash       'python3 <<EOF
kill 1234
EOF'
chk_kill 'an unlisted filter keeps the body code'  deny  Bash       "cat <<'EOF' | grep node
pkill node
EOF"
chk_kill 'a listed name with the opener stuck to it' allow Bash     "cat<<'EOF'
Stop-Process -Id 3260
EOF"
chk_kill 'a shell heredoc inside a substitution'   deny  Bash       'echo $(bash <<EOF
kill 1234
EOF
)'
chk_kill 'a quoted substitution around cat stays data' allow Bash   "gh pr comment 5 --body \"\$(cat <<'EOF'
Stop-Process -Id 3260
EOF
)\""
chk_kill 'a change of folder before the heredoc is data' allow Bash  "cd x && cat > f <<'EOF'
Stop-Process -Id 3260
EOF"
chk_kill 'a new folder before the heredoc is data'  allow Bash       "mkdir -p d && cat > d/f <<'EOF'
Stop-Process -Id 3260
EOF"
chk_kill 'a test bracket before the heredoc is data' allow Bash      "[ -d d ] && cat > d/f <<'EOF'
Stop-Process -Id 3260
EOF"
chk_kill 'an escaped quote hides no shell'        deny  Bash       "cat <<'EOF' \\\" | bash \"x\"
pkill node
EOF"
chk_kill 'an unread tree says so'                  deny  Bash       'kill 1234'                              'could not be read'
# a backtick inside single quotes is text: no shell runs it there
chk_kill 'a backtick in single quotes is data'     allow Bash       "echo 'mit \`pkill\` im Text'"
chk_kill 'a backtick in a quoted body is data'     allow Bash       "gh api x -f body='mit \`pkill\` im Text'"
chk_kill 'a backtick in double quotes still runs'  deny  Bash       'echo "mit `pkill node` drin"'
chk_kill 'a backtick in a bash -c span still runs' deny  Bash       "bash -c 'x \`pkill node\`'"
chk_kill 'escaped backslash then escaped quote' allow Bash      'echo "a\\\" kill 5"'
chk_kill 'escaped quotes: a name is found'     deny  Bash       'powershell -Command "Stop-Process -Name \"rc\""'
chk_kill 'escaped quotes: a CIM filter is found' deny Bash      'powershell -Command "(Get-WmiObject Win32_Process -Filter \"Name='"'"'rc.exe'"'"'\").Terminate()"'
chk_kill 'escaped quotes: a number is still denied' deny   Bash       'powershell -Command "Stop-Process -Id 5; Stop-Process -Id \"6\""' 'stop-process 6'
chk_kill 'escaped quote before a verb word'    allow Bash       'echo "a \" kill 5"'
chk_kill 'escaped quotes around a verb word'   allow Bash       'git commit -m "say \"kill\" now"'
# gap C, the filter is the process id as a whole word, in the filter text
chk_kill 'C: ParentProcessId ends the children' deny PowerShell 'Get-CimInstance Win32_Process -Filter "ParentProcessId=3568" | Invoke-CimMethod -MethodName Terminate'
chk_kill 'C: wmic parentprocessid'             deny  Bash       'wmic process where parentprocessid=3568 call terminate'
chk_kill 'C: a stray processid= elsewhere'     deny  PowerShell "(Get-WmiObject Win32_Process -Filter \"Name='rc.exe'\").Terminate(); echo processid=5"
# a target held in a variable without a process list in the call is still denied
chk_kill 'a started process, its id in a variable' deny PowerShell '$p = Start-Process x -PassThru; Stop-Process -Id $p.Id' 'variable'
chk_kill 'a started process, .Kill()'          deny   PowerShell '$p = Start-Process x -PassThru; $p.Kill()'
# the nested ways stay recognised, each with the verdict of its target
chk_kill 'nested cmd.exe /c, a name'           deny  Bash       'cmd.exe /c "taskkill /IM rc.exe"'
chk_kill 'nested bash -c, a name'              deny  PowerShell "bash -c 'pkill rc'"
chk_kill 'nested pwsh -c, several numbers'     deny   Bash       'pwsh -c "Stop-Process -Id 1,2"'             'stop-process 2'
chk_kill 'kill -Id alias, one number'          deny   PowerShell 'kill -Id 3568'                              '3568'
chk_kill 'spps, several numbers'               deny   PowerShell 'spps -Id 1,2'                               'spps 2'
enc_name="$(printf 'Stop-Process -Name rc' | sed 's/./&\x00/g' | base64 -w0)"
chk_kill 'encoded Stop-Process by name'        deny  Bash       "pwsh -EncodedCommand $enc_name"
enc_block="$(printf '& { Stop-Process -Id 3568 }' | sed 's/./&\x00/g' | base64 -w0)"
chk_kill 'encoded block with one number'       deny   Bash       "pwsh -EncodedCommand $enc_block"            '3568'
# by name, one verdict whatever the verb: a name is blocked, with or without a wildcard
chk_kill 'pkill, one name'                     deny  Bash       'pkill node'                                 'pkill node'
chk_kill 'killall, one name'                   deny  Bash       'killall node'                               'killall node'
chk_kill 'killall, one name behind a signal'   deny  Bash       'killall -9 node'                            'killall node'
chk_kill 'skill, one name'                     deny  Bash       'skill -9 node'                              'skill node'
chk_kill 'pkill with the user option'          deny  Bash       'pkill -u root node'                         'pkill node'
chk_kill 'pkill -l lists signals'              allow Bash       'pkill -l'
# a selector without a name ends every process it matches: blocked, one case per form
chk_kill 'pkill -u, no name'                   deny  Bash       'pkill -u me'                                'by selector'
chk_kill 'pkill -U, no name'                   deny  Bash       'pkill -U 1000'                              'by selector'
chk_kill 'pkill -g, no name'                   deny  Bash       'pkill -g 5'                                 'by selector'
chk_kill 'pkill -G, no name'                   deny  Bash       'pkill -G staff'                             'by selector'
chk_kill 'pkill -P, no name'                   deny  Bash       'pkill -P 1'                                 'by selector'
chk_kill 'pkill -s, no name'                   deny  Bash       'pkill -s 100'                               'by selector'
chk_kill 'pkill -t, no name'                   deny  Bash       'pkill -t pts/1'                             'by selector'
chk_kill 'pkill --user, no name'               deny  Bash       'pkill --user me'                            'by selector'
chk_kill 'pkill --parent, no name'             deny  Bash       'pkill --parent 1'                           'by selector'
chk_kill 'pkill --pgroup, no name'             deny  Bash       'pkill --pgroup 5'                           'by selector'
chk_kill 'pkill --session, no name'            deny  Bash       'pkill --session 5'                          'by selector'
chk_kill 'pkill --terminal, no name'           deny  Bash       'pkill --terminal pts/1'                     'by selector'
chk_kill 'pkill --group, no name'              deny  Bash       'pkill --group staff'                        'by selector'
chk_kill 'killall -u, no name'                 deny  Bash       'killall -u me'                              'by selector'
chk_kill 'pkill -u5, value attached'           deny  Bash       'pkill -u5'                                  'by selector'
chk_kill 'pkill -uroot, value attached'        deny  Bash       'pkill -uroot'                               'by selector'
chk_kill 'pkill -P1, value attached'           deny  Bash       'pkill -P1'                                  'by selector'
chk_kill 'pkill --uid=5, value attached'       deny  Bash       'pkill --uid=5'                              'by selector'
chk_kill 'pkill -fu me, bundled flags'         deny  Bash       'pkill -fu me'
chk_kill 'pkill -xu me, bundled selector'      deny  Bash       'pkill -xu me'                               'by selector'
chk_kill 'pkill -u5 with a name is a name'     deny  Bash       'pkill -u5 node'                             'pkill node'
chk_kill 'pkill -HUP node, a signal name'      deny  Bash       'pkill -HUP node'                            'pkill node'
chk_kill 'pkill -P with a name is a name'      deny  Bash       'pkill -P 1 node'                            'pkill node'
chk_kill 'killall -s is a signal, no selector' deny   Bash       'killall -s TERM'                            'without a readable name'
chk_kill 'taskkill /IM, one image'             deny  Bash       'taskkill /IM chrome.exe'                    'chrome.exe'
chk_kill 'Stop-Process -Name, one name'        deny  PowerShell 'Stop-Process -Name claude'                  'claude'
chk_kill 'the same name through pkill'         deny  Bash       'pkill claude'                               'claude'
# every verb of the list reaches its classifier
chk_kill 'pskill'                              deny   Bash       'pskill 1234'                                '1234'
chk_kill 'tskill'                              deny   Bash       'tskill 1234'                                '1234'
chk_kill 'xkill'                               deny   Bash       'xkill'                                      'xkill'
chk_kill 'skill with a pid'                    deny  Bash       'skill 1234'                                 'skill 1234'
chk_kill 'upper case verb'                     deny   Bash       'KILL 5'                                     '5'
# a command position after a single `&`, a keyword or a wrapper with options
chk_kill 'after a single &'                    deny   Bash       'sleep 1 & kill 5'                           '5'
chk_kill 'after ;; without a space'            deny   Bash       'echo a;; kill 5'                            '5'
chk_kill 'after &; without a space'            deny   Bash       'echo a&; kill 5'                            '5'
chk_kill 'after |& (pipe with stderr)'         deny  Bash       'echo a |& kill 5'                           'pipeline'
chk_kill 'PowerShell call operator'            deny   PowerShell '& taskkill /PID 1'                          'pid 1'
chk_kill 'after a background &'                deny  Bash       'echo a & taskkill /F /IM x.exe'             'x.exe'
chk_kill 'after then'                          deny   Bash       'if true; then kill 5; fi'                   '5'
chk_kill 'after do'                            deny   Bash       'for p in $(pgrep x); do kill $p; done'      'variable'
chk_kill 'after else'                          deny   Bash       'if false; then :; else kill 5; fi'          '5'
chk_kill 'after !'                             deny   Bash       '! kill 5'                                   '5'
chk_kill 'xargs -r kill'                       deny  Bash       'pgrep claude | xargs -r kill'
chk_kill 'xargs kill reading a file'           deny  Bash       'xargs -r kill < pids.txt'
chk_kill 'xargs -n1 kill -9'                   deny  Bash       'pgrep claude | xargs -n1 kill -9'
chk_kill 'xargs -n 1 kill -9'                  deny  Bash       'pgrep claude | xargs -n 1 kill -9'
chk_kill 'timeout 5 kill'                      deny   Bash       'timeout 5 kill 1234'                        '1234'
chk_kill 'sudo -u x kill'                      deny   Bash       'sudo -u x kill 1'                           'kill 1'
chk_kill 'nohup kill in the background'        deny   Bash       'nohup kill 5 &'                             '5'
chk_kill 'env assignment before kill'          deny   Bash       'FOO=1 kill 5'                               '5'
chk_kill 'two assignments before pkill'        deny  Bash       'A=1 B=x pkill -f claude'                    'pkill'
chk_kill 'cmd /k'                              deny   Bash       'cmd /k taskkill /PID 4'                     'pid 4'
# the verb with a path before it, `.exe` behind it, or behind another wrapper
chk_kill 'a path before the verb'              deny   Bash       '/bin/kill 1234'                             'kill 1234'
chk_kill 'a longer path before the verb'       deny   Bash       '/usr/bin/kill -9 1234'                      'kill 1234'
chk_kill 'a Windows path and .exe'             deny   Bash       'C:\Windows\System32\taskkill.exe /PID 4'    'pid 4'
chk_kill 'a backslash before the verb'         deny   Bash       '\kill 1234'                                 'kill 1234'
chk_kill 'busybox kill'                        deny   Bash       'busybox kill 1234'                          'kill 1234'
chk_kill 'a path before busybox'               deny   Bash       '/bin/busybox kill 5'                        'kill 5'
chk_kill 'a path before env'                   deny   Bash       '/usr/bin/env kill 5'                        'kill 5'
chk_kill 'a path before sudo'                  deny   Bash       '/usr/bin/sudo kill 5'                       'kill 5'
chk_kill 'a path before timeout'               deny   Bash       '/usr/bin/timeout 5 kill 1'                  'kill 1'
chk_kill 'a path before xargs'                 deny  Bash       'ls | /usr/bin/xargs kill'                   'pipeline'
chk_kill 'a path before find'                  deny  Bash       '/usr/bin/find . -name x -exec kill {} \;'   'pipeline'
chk_kill 'taskkill.exe'                        deny  Bash       'taskkill.exe /F /IM node.exe'               'node.exe'
chk_kill 'kill.exe'                            deny   Bash       'kill.exe 12'                                'kill 12'
chk_kill 'find -exec kill'                     deny  Bash       'find . -name x -exec kill {} \;'            'pipeline'
chk_kill 'find -execdir pkill'                 deny  Bash       'find . -execdir pkill x \;'
chk_kill 'xargs -I{} kill'                     deny  Bash       'echo 1234 | xargs -I{} kill {}'             'pipeline'
chk_kill 'xargs -I <str> kill'                 deny  Bash       'echo 1234 | xargs -I % kill %'              'pipeline'
chk_kill 'a path in a commit message'          allow Bash       'git commit -m "kill the /bin/kill"'
chk_kill 'a path to a file that is no verb'    allow Bash       'cat /tmp/kill.exe.txt'
chk_kill 'ls of the kill binary'               allow Bash       'ls /bin/kill'
chk_kill 'ssh host "kill"'                     deny   Bash       'ssh host "kill 5"'                          '5'
chk_kill 'a substitution inside double quotes' deny   Bash       'echo "$(kill 5)"'                           '5'
# the argument branches of the classifiers
chk_kill 'kill -s TERM'                        deny   Bash       'kill -s TERM 1234'                          '1234'
chk_kill 'kill -- -1, every process'           deny  Bash       'kill -- -1'
chk_kill 'Stop-Process -InputObject'           deny   PowerShell 'Stop-Process -InputObject $p'               'cannot read'
chk_kill 'Stop-Process -Id:12'                 deny   PowerShell 'Stop-Process -Id:12'                        '12'
chk_kill 'task kill two PIDs'                   deny   Bash       'taskkill /PID 1 /PID 2'
chk_kill 'Invoke-CimMethod ... Terminate'      deny  PowerShell 'Invoke-CimMethod -Query "select * from win32_process" -MethodName Terminate'
chk_kill 'wmic delete by like'                 deny  Bash       "wmic process where \"name like '%a%'\" delete"
# a verb behind a long text is still found, and one inside it still is not
# (600 lines: jq --arg takes at most about 32 KB under Windows)
long_text="$(printf 'line of text %s\n' $(seq 1 600))"
chk_kill 'a verb after a long heredoc'         deny   Bash       "cat > f <<EOF
$long_text
EOF
kill 5"                                        '5'
chk_kill 'the word kill inside a long heredoc' allow Bash       "cat > f <<EOF
$long_text
please do not kill the process
EOF"
# 2000 short paths: counted, not timed. Without a separator the words are one statement, which the first failed
# match settles (2 runs: that statement and the real kill); with a `&` behind each word every path is a
# statement of its own and the runs grow with the words, over about the text's length in characters.
trace_file="$fix/guard-trace"
guard_trace() { # label, joiner between the paths, max runs
  local c i r ch runs=-1 chars=-1 bytes got
  c="sudo echo $(for i in $(seq 1 2000); do printf '%s%s' "/tmp/kill-$i" "$2"; done) ; kill 1234"
  c="$(kill_event Bash "$c")"; bytes=${#c}
  rm -f "$trace_file"
  out="$(printf '%s' "$c" | GUARD_KILL_TRACE="$trace_file" timeout 25 bash "$guard" 2>&1)"
  if [ -s "$trace_file" ]; then read -r r ch < "$trace_file"; runs=${r#runs=}; chars=${ch#chars=}; fi
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  if [ "$got" = deny ] && has_text 1234 "$out"; then ok "$1: the real kill is found" "$got"; else bad "$1: the real kill is found" "$got" 'deny 1234'; fi
  if [ "$runs" -ge 0 ] && [ "$runs" -le "$3" ]; then ok "$1: at most $3 pattern runs" "$runs"; else bad "$1: at most $3 pattern runs" "$runs" "<= $3"; fi
  if [ "$chars" -ge 0 ] && [ "$chars" -le $((bytes * 2)) ]; then ok "$1: pattern text within twice the input" "${chars} of ${bytes}"; else bad "$1: pattern text within twice the input" "${chars} of ${bytes}" "<= $((bytes * 2))"; fi
}
guard_trace '2000 short paths, no separator'    ' ' 5
guard_trace '2000 short paths, one per statement' '&' 2010
# wrappers that carry a value option: `-c` is a value here, not the code flag of a shell
chk_kill 'ionice -c 3 kill'                    deny   Bash       'ionice -c 3 kill 1'                         'kill 1'
chk_kill 'env -C / kill'                       deny   Bash       'env -C / kill 5'                            'kill 5'
chk_kill 'env -i -C / kill'                    deny   Bash       'env -i -C / kill 5'                         'kill 5'
chk_kill 'watch kill'                          deny   Bash       'watch kill 1'                               'kill 1'
chk_kill 'watch -n 5 kill'                     deny   Bash       'watch -n 5 kill 1'                          'kill 1'
# a quoted argument that runs as a command line is code, like the one behind `ssh host`
chk_kill 'watch with a quoted command'         deny   Bash       "watch 'kill 1'"                             'kill 1'
chk_kill 'watch -n1 with a double-quoted one'  deny   Bash       'watch -n1 "kill 1"'                         'kill 1'
chk_kill 'watch -n 2 with a quoted command'    deny   Bash       "watch -n 2 'kill 1'"                        'kill 1'
chk_kill 'nice watch with a quoted command'    deny   Bash       "nice watch 'kill 1'"                        'kill 1'
chk_kill 'env -S with a quoted command line'   deny  Bash       "env -S 'pkill -f node'"                     'full command line'
chk_kill 'env --split-string, quoted'          deny   Bash       "env --split-string 'kill 1'"                'kill 1'
chk_kill 'env -i -S, quoted'                   deny   Bash       "env -i -S 'kill 1'"                         'kill 1'
chk_kill 'env --split-string=, quote attached' deny   Bash       "env --split-string='kill 1'"                'kill 1'
chk_kill 'env -S, quote attached'              deny   Bash       "env -S'kill 1'"                             'kill 1'
chk_kill 'env -S, quote attached, harmless'    allow Bash       "env -S'echo kill-switch'"
chk_kill 'a path before watch'                 deny   Bash       "/usr/bin/watch 'kill 1'"                    'kill 1'
chk_kill 'a path before env -S'                deny   Bash       "/usr/bin/env -S 'kill 1'"                   'kill 1'
chk_kill 'a path before env -S, quote attached' deny   Bash       "/usr/bin/env -S'kill 1'"                    'kill 1'
chk_kill 'a relative path before env -S, attached' deny Bash     "./env -S'kill 1'"                           'kill 1'
chk_kill 'env -u X -S'                         deny   Bash       "env -u X -S 'kill 1'"                       'kill 1'
chk_kill 'env -C dir -S'                       deny   Bash       "env -C /tmp -S 'kill 1'"                    'kill 1'
chk_kill 'env --unset X -S'                    deny   Bash       "env --unset X -S 'kill 1'"                  'kill 1'
chk_kill 'env --chdir dir -S, quote attached'  deny   Bash       "env --chdir /tmp -S'kill 1'"                'kill 1'
chk_kill 'env -u X -S around a harmless text'  allow Bash       "env -u X -S 'echo kill-switch'"
chk_kill 'a path before ssh'                   deny   Bash       "/usr/bin/ssh h 'kill 1'"                    'kill 1'
chk_kill 'watch around a harmless quoted text' allow Bash       "watch 'echo kill-switch'"
chk_kill 'ssh host quoted is code too'         deny   Bash       "ssh h 'kill 1'"                             'kill 1'
chk_kill 'taskset -c cpu list, then kill'      deny   Bash       'taskset -c 0 kill 1'                        'kill 1'
chk_kill 'taskset with a mask, then kill'      deny   Bash       'taskset 0x1 kill 1'                         'kill 1'
chk_kill 'chrt -i 0 kill'                      deny   Bash       'chrt -i 0 kill 1'                           'kill 1'
chk_kill 'chrt priority kill'                  deny   Bash       'chrt -f 10 kill 1'                          'kill 1'
chk_kill 'flock file kill'                     deny   Bash       'flock /tmp/l kill 1'                        'kill 1'
chk_kill 'runuser -u x -- kill'                deny   Bash       'runuser -u x -- kill 1'                     'kill 1'
chk_kill 'systemd-run kill'                    deny   Bash       'systemd-run kill 1'                         'kill 1'
chk_kill 'systemd-run with options, kill'      deny   Bash       'systemd-run --scope -p MemoryMax=1G kill 1' 'kill 1'
chk_kill 'taskset around a harmless command'   allow Bash       'taskset -c 0 ls /tmp/kill'
chk_kill 'bash -c still opens code'            deny   Bash       'bash -c "kill 5"'                           'kill 5'
chk_kill 'env bash -c still opens code'        deny   Bash       'env -i bash -c "kill 5"'                    'kill 5'
chk_kill 'ionice around a harmless command'    allow Bash       'ionice -c 3 ls /tmp/kill'
# bundled short flags and a signal without a name
chk_kill 'pkill -fx, bundled full match'       deny  Bash       'pkill -fx node'                             'full command line'
chk_kill 'pkill -rx, bundled regexp'           deny  Bash       'pkill -rx node'                             'regular expression'
chk_kill 'pkill -x alone is a name match'      deny  Bash       'pkill -x node'                              'pkill node'
chk_kill 'pkill -HUP, a signal and no name'    deny   Bash       'pkill -HUP'                                 'without a readable name'
chk_kill 'pkill -HUP node'                     deny  Bash       'pkill -HUP node'                            'pkill node'
# a short encoded command: the same length decides in step 1 and step 2
chk_kill 'short encoded kill (16 characters)'  deny   Bash       'pwsh -enc awBpAGwAbAAgADEA'                 '1'
chk_kill 'shortest encoded verb (12 characters)' deny   Bash       'pwsh -enc awBpAGwAbAA='                     'without a readable target'
# unclear -> deny
chk_kill 'kill a variable'                     deny   Bash       'kill $PID'                                  'variable'
chk_kill 'Stop-Process with a variable'        deny  PowerShell 'Stop-Process -Name $n'                      'variable'
chk_kill 'taskkill without a target'           deny   Bash       'taskkill /F'
chk_kill 'an undecodable encoded command'      deny   Bash       'pwsh -enc AAAAAAAAAAAAAAAAAAAAA'
chk_kill 'a kill in inline code'               deny   Bash       'python -c "import os; os.kill(5, 9)"'
# everything else passes
chk_kill 'kill -l lists signals'               allow Bash       'kill -l'
chk_kill 'kill -0 only probes'                 allow Bash       'kill -0 1234'
chk_kill 'a plain command'                     allow Bash       'git status --short'
chk_kill 'a plain PowerShell command'          allow PowerShell 'Get-ChildItem -Recurse'
chk_kill '"skills" in a path'                  allow Bash       'ls .claude/skills/pr-poll-review'
chk_kill 'the word in a commit message'        allow Bash       'git commit -m "fix: kill guard for skills"'
chk_kill 'a commit message that starts with a verb' allow Bash  'git commit -m "kill the flaky test"'
chk_kill 'a single-quoted message with a verb' allow Bash       "git commit -m 'kill the flaky test'"
chk_kill 'a message with & and a verb'         allow Bash       'git commit -m "a & kill"'
chk_kill 'a message with ; and a verb'         allow Bash       "git commit -m 'done; kill 5'"
chk_kill 'a search for pkill'                  allow Bash       'rg -n "pkill|killall" .claude/hooks'
chk_kill 'a search for kill'                   allow Bash       'grep -n "kill" x'
chk_kill 'a verb at the start of a heredoc line quoted' allow Bash 'echo "line one
kill 5"'
chk_kill 'ls of a skill folder'                allow Bash       'ls .claude/skills'
chk_kill 'the word skill inside a path'        allow Bash       'cat .claude/skill-notes.md'
chk_kill 'wmic reading something else'         allow Bash       'wmic cpu get name'
chk_kill 'an encoded command without a verb'   allow Bash       'pwsh -enc QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo='
chk_kill 'a tool this hook does not guard'     allow Read       'kill 1234'

finish
