#!/usr/bin/env bash
# Hook suite section: guard-kill.sh step 0, a build or test run cut off with `&` (ww3d/playbook#652)
# Run alone: bash .claude/hooks/tests/cases/guard-kill-background-run.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax as text
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== guard-kill.sh: build or test run cut off with & =="
w='run_in_background'
# the plain forms
chk_kill 'rc run with &'                  deny  Bash       'rc run --label 12 -- ./test.ps1 &'                    "$w"
chk_kill 'dotnet test with &'             deny  Bash       'dotnet test -c Release &'                             "$w"
chk_kill 'dotnet build with &'            deny  PowerShell 'dotnet build src/x.sln &'                             "$w"
chk_kill 'build.ps1 with &'               deny  Bash       './build.ps1 -Tier Full &'                             "$w"
chk_kill 'test.ps1, redirect then &'      deny  Bash       './scripts/test.ps1 > out.log 2>&1 &'                  "$w"
chk_kill 'test.ps1, & then next line'     deny  Bash       $'./scripts/test.ps1 &\necho started'                  "$w"
chk_kill 'dotnet test with &, then ;'     deny  Bash       'dotnet test & ; echo x'                               "$w"
chk_kill 'upper case Dotnet Test &'       deny  PowerShell 'Dotnet Test &'                                        "$w"
chk_kill 'the reason names #652'          deny  Bash       'dotnet test &'                                        'ww3d/playbook#652'
chk_kill 'no blank before &'              deny  Bash       'dotnet test&'                                         "$w"
# R1-1: the shapes measured in real sessions (the sessions behind ww3d/playbook#652)
chk_kill 'group, ; inside, then & sleep'  deny  Bash       '( rc run --label 644 -- pwsh ./build.ps1 > log 2>&1; echo done >> log ) & sleep 1' "$w"
chk_kill 'group, redirect, & at the end'  deny  Bash       '(rc run --label 1395 -- pwsh -NoProfile -File ./build.ps1 -Pinboard > /d/x.log 2>&1; echo done >> /d/x.log) > /dev/null 2>&1 &' "$w"
chk_kill '& inside the group'             deny  Bash       'S=x && (rc run --label 1440 -- pwsh -NoProfile -File ./build.ps1 > $S/r.txt 2>&1 &); echo started' "$w"
chk_kill 'group with PUBDONE, & sleep'    deny  Bash       '(pwsh -NoProfile -File ./build.ps1 -Publish -Gated > "$J/pub.log" 2>&1; echo PUBDONE >> "$J/pub.log") & sleep 1' "$w"
chk_kill 'dotnet build in a group'        deny  Bash       '(dotnet build src/X.Tests -v:m > /tmp/b1.log 2>&1; echo done >> /tmp/b1.log) & sleep 14' "$w"
chk_kill 'nohup in a group, & inside'     deny  Bash       '(nohup dotnet test tests/B.Tests > /x/bt.log 2>&1 &); echo started' "$w"
chk_kill 'cmd //c start, quoted run word' deny  Bash       'mkdir -p a && cmd //c "start /b /wait /affinity F000 pwsh -NoProfile -File build.ps1 -Class X" &' "$w"
chk_kill 'pipeline to tee, &'             deny  Bash       'dotnet test 2>&1 | tee out.log &'                     "$w"
chk_kill '&& chain, & at the end'         deny  Bash       'dotnet test && echo ok &'                             "$w"
chk_kill '& then pid=$!'                  deny  Bash       'rc run --label 1 -- dotnet test & pid=$!'             "$w"
chk_kill '& then wait'                    deny  Bash       'dotnet test & wait'                                   "$w"
chk_kill '& then echo'                    deny  Bash       'dotnet test & echo started'                           "$w"
chk_kill 'brace group, &'                 deny  Bash       '{ dotnet test; echo done; } &'                        "$w"
chk_kill 'command substitution before &'  deny  Bash       'dotnet test $(pwd)/x.sln &'                           "$w"
chk_kill 'bash <<EOF reads the body'      deny  Bash       $'bash <<\'EOF\'\ndotnet test &\nEOF'                  "$w"

# counter cases: every other & passes
chk_kill '&& chain'                       allow Bash       'dotnet build && dotnet test'
chk_kill '&& after test.ps1'              allow Bash       './scripts/test.ps1 && echo ok'
chk_kill '2>&1 only'                      allow Bash       'dotnet test 2>&1'
chk_kill '2>&1 piped'                     allow Bash       'dotnet test 2>&1 | tail -5'
chk_kill '|& pipe'                        allow Bash       'dotnet test |& tail -5'
chk_kill '&> redirect'                    allow Bash       'dotnet test &> out.log'
chk_kill 'run in the foreground'          allow Bash       'dotnet test --filter Name=x'
chk_kill 'other command in the background' allow Bash      'sleep 5 & echo started'
chk_kill '& before the run'               allow Bash       'sleep 5 & dotnet test'
chk_kill '& after ; behind the run'       allow Bash       'dotnet test; sleep 5 &'
chk_kill 'group without a run, &'         allow Bash       '(sleep 5; echo x) & dotnet test'
chk_kill 'unrelated command with &'       allow Bash       'npm start &'
chk_kill 'run word only in the message'   allow Bash       'git commit -m "fix dotnet test &"'
chk_kill 'run word in a comment'          allow Bash       $'sleep 1 &\n# dotnet test &'
chk_kill 'rc run, no &'                   allow Bash       'rc run --label 1 -- dotnet test'
chk_kill 'ampersand in a URL'             allow Bash       'curl "https://x/?a=1&b=2" -o dotnet-test.txt'
chk_kill 'PowerShell call operator'       allow PowerShell '& ./scripts/test.ps1 -Tier Fast'
chk_kill 'call operator after ;'          allow PowerShell 'cd x; & ./scripts/test.ps1'
chk_kill 'heredoc body for cat is data'   allow Bash       $'cat > f.md <<\'EOF\'\ndotnet test &\nEOF'
chk_kill 'heredoc body for a loop is data' allow Bash      $'while read c; do :; done <<\'EOF\'\ndotnet test &\nEOF'
chk_kill 'PowerShell here-string is data' allow PowerShell $'$t = @\'\ndotnet test &\n\'@'
chk_kill 'no command'                     allow Bash       ''

# the switch and fail-open
off_out="$(kill_event Bash 'dotnet test &' | PLAYBOOK_BG_RUN_GUARD=off bash "$guard" 2>&1)"
if [ -z "$off_out" ]; then ok 'switch off lets it pass' allow; else bad 'switch off lets it pass' deny allow; fi
broken="$(printf '{"tool_name":"Bash","tool_input":{"command":"dotnet test &"' | bash "$guard" 2>&1)"
if [ -z "$broken" ]; then ok 'broken envelope passes' allow; else bad 'broken envelope passes' deny allow; fi

finish
