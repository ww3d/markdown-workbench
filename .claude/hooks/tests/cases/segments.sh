#!/usr/bin/env bash
# Hook suite section: lib/segments.awk, the one splitter of a command line for require-rule-read.sh
# Run alone: bash .claude/hooks/tests/cases/segments.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

segs="$hooks/lib/segments.awk"
forms="$hooks/tests/param-forms.txt"
# The commands of a text as `name:word word ...`, joined by ` | ` (fields 2 and 11 onwards of each record).
seg() { # text, [ps]
  timeout 20 env SEG_PS="${2:-}" LC_ALL=C awk -f "$segs" <<<"$1" | awk -F '\037' '{
    w = ""; for (i = 11; i <= NF; i++) w = w (i > 11 ? " " : "") $i
    out = out (NR > 1 ? " | " : "") $2 ":" w } END { print out }'
}
# One field of the record whose command word is the given name.
seg_field() { # text, name, field
  timeout 20 env LC_ALL=C awk -f "$segs" <<<"$1" | awk -F '\037' -v n="$2" -v k="$3" '$2 == n { print $k; exit }' | tr '\035' ,
}
nl=$'\n'
# A CR goes into the text through a variable: Git Bash drops one written as $'\r' inside $( ).
cr=$'\r'

echo "== lib/segments.awk: separators, groups and substitutions =="
expect 'a ; and a newline split'                 'a:a 1 | b:b | c:c'          "$(seg "a 1; b${nl}c")"
expect '&& || | & split'                         'a:a | b:b | c:c | d:d | e:e' "$(seg 'a && b || c | d & e')"
expect 'a ( ) group splits'                      'a:a | b:b | c:c'            "$(seg '(a; b) && c')"
expect 'a { } group splits'                       'a:a | b:b'                  "$(seg '{ a; b; }')"
expect 'a { after another word splits too'        'gh:gh api x | f:f'          "$(seg 'function f { gh api x; }; f' | sed 's/^function:function f | //')"
expect 'coproc { ... }'                           'gh:gh api x'                "$(seg 'coproc { gh api x; }' | sed 's/^.* | //')"
expect 'a PowerShell block without a blank'      'gh:gh api x'                "$(seg 'if ($true) {gh api x}' 1 | sed 's/^.* | //')"
expect 'a PowerShell script block'                'gh:gh api x'                "$(seg '1 | ForEach-Object { gh api x }' 1 | sed 's/^.* | //')"
expect 'a brace inside a word is text'           'gh:gh api repos/{owner}/{repo}/pulls' "$(seg 'gh api repos/{owner}/{repo}/pulls')"
expect 'a $(...) is a command of its own'        'b:b x | a:a $(...) y'       "$(seg 'a $(b x) y')"
expect 'a backtick substitution too'             'b:b | a:a $(...)'           "$(seg 'a `b`')"
expect 'a process substitution too'              'b:b | a:a --input $(...)'   "$(seg 'a --input <(b)')"
expect 'a $(...) inside double quotes'           'b:b | a:a x $(...)'         "$(seg 'a "x $(b)"')"
expect 'a redirection is a word, no separator'   'a:a 2>&1 &>/dev/null >| f <&0' "$(seg 'a 2>&1 &>/dev/null >| f <&0')"
expect 'the substitution flag is set'            's'                          "$(seg_field 'a $(b)' a 3)"
expect 'a case label ends a command'             'case:case x in x | a:a | esac:esac' "$(seg 'case x in x) a;; esac')"

echo "== lib/segments.awk: environment assignments, keywords and wrappers =="
expect 'an assignment before the command'        'gh:A=1 GH_REPO=o/r gh pr' "$(seg 'A=1 GH_REPO=o/r gh pr')"
expect 'the command word index skips it'         '3'                          "$(seg_field 'A=1 B=2 gh x' gh 9)"
expect 'keywords before the command'             'gh:if ! gh api'             "$(seg 'if ! gh api; then :; fi' | cut -d'|' -f1 | sed 's/ $//')"
for w in 'sudo -u x' 'doas' 'env -i' 'env -u GH_REPO' 'command' 'nice -n 5' 'timeout 5' 'timeout -s KILL 5' \
         'exec' 'time' 'nohup' 'xargs -n 1' 'ionice -c 3' 'stdbuf -o0' 'setsid' '/usr/bin/env'; do
  expect "wrapper: $w"                           'gh'                         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"$w gh api x" | cut -d $'\037' -f2)"
done
for w in 'sudo --user x' 'timeout --signal KILL 10' 'xargs --max-args 1' 'nice --adjustment 5' \
         'stdbuf --output L' 'env --chdir /tmp' 'ionice --class 2' 'sudo --user=x'; do
  expect "wrapper, long option: $w"              'gh'                         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"$w gh api x" | cut -d $'\037' -f2)"
done
expect 'env assigns after its options'           'gh'                         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<'env -i GH_REPO=o/r gh api' | cut -d $'\037' -f2)"
expect 'a path and .exe before the name'         'gh'                         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<'/usr/bin/GH.EXE pr' | cut -d $'\037' -f2)"
expect 'a quoted path as the command word'       'gh'                         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"& 'C:/Program Files/GitHub CLI/gh.exe' api" | cut -d $'\037' -f2)"
expect 'a PowerShell assignment before it'       'gh'                         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<'$null = gh api' | cut -d $'\037' -f2)"

echo "== lib/segments.awk: code another program runs =="
expect 'bash -c "..."'                           'bash:bash -c gh pr review 5 | gh:gh pr review 5' "$(seg 'bash -c "gh pr review 5"')"
expect 'bash -lc unquoted'                       'bash:bash -lc gh api x | gh:gh api x'           "$(seg 'bash -lc gh api x')"
expect 'sh -c with a quoted word inside'         'gh:gh api -f b=c d'                             "$(seg "sh -c 'gh api -f b=\"c d\"'" | sed 's/^.* | //')"
expect 'pwsh -Command'                           'gh:gh api x'                                    "$(seg 'pwsh -Command "gh api x"' | sed 's/^.* | //')"
expect 'powershell -c'                           'gh:gh api x'                                    "$(seg 'powershell -c gh api x' | sed 's/^.* | //')"
expect 'cmd /c and /K'                           'gh:gh api x'                                    "$(seg 'CMD /K gh api x' | sed 's/^.* | //')"
expect 'eval'                                    'gh:gh api x'                                    "$(seg "eval 'gh api x'" | sed 's/^.* | //')"
expect 'iex and Invoke-Expression'               'gh:gh api x'                                    "$(seg "Invoke-Expression 'gh api x'" 1 | sed 's/^.* | //')"
expect 'options between -c and the code'          'gh:gh api x'                                    "$(seg "bash -c -e -o pipefail 'gh api x'" | sed 's/^.* | //')"
deep="gh api x"; for _ in $(seq 1 20); do deep="eval $deep"; done
expect 'code nested too deep is one record (flag d)' 'd'                                             "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"$deep" | awk -F '\037' '$3 == "d" { print $3; exit }')"
deep="gh api x"; for _ in $(seq 1 10); do deep="eval $deep"; done
expect 'code nested ten deep is still read'      'gh:gh api x'                                    "$(seg "$deep" | sed 's/^.* | //')"
expect 'a -c of another program is no code'      'git:git -c a=b gh api'                          "$(seg 'git -c a=b gh api')"

echo "== lib/segments.awk: quotes, comments and heredoc text are data =="
expect 'a quoted span is one word'               'git:git commit -m gh pr review 5'   "$(seg 'git commit -m "gh pr review 5"')"
expect 'an escaped quote stays inside'           'echo:echo a "b c'                   "$(seg 'echo "a \"b" c')"
expect 'a # at a word start comments out'        'a:a | b:b'                          "$(seg "a # ; gh api x${nl}b")"
expect 'a # inside a word does not'              'a:a b#c | gh:gh'                    "$(seg 'a b#c; gh')"
expect 'a # in a backtick ends at the backtick'    'echo:echo $(...) | gh:gh api x' "$(seg 'echo `#x`; gh api x')"
expect 'a quoted { inside ${...}'                 ":\${x:-'{'}; gh api x | echo:echo" "$(seg "echo \${x:-'{'}; gh api x")"
expect 'a quoted } inside ${...}'                 ':${x:-"}"}; gh api x | echo:echo' "$(seg 'echo ${x:-"}"}; gh api x')"
expect 'an escaped { inside ${...}'               ':${x/\{/}; gh api x; echo } | echo:echo' "$(seg 'echo ${x/\{/}; gh api x; echo }')"
expect 'a # inside ${...} does not'              'echo:echo ${v:- #} | gh:gh'         "$(seg 'echo ${v:- #}; gh')"
expect 'an escaped blank before # keeps it'      'echo:echo  # | gh:gh'               "$(seg 'echo \ #; gh')"
expect 'a quote that never closes ends the command' 'echo:echo | gh:gh pr review 5'   "$(seg "echo 'gh pr review 5" | sed 's/echo:echo | gh/echo:echo | gh/')"
expect "PowerShell: '' inside single quotes"     "echo:echo it's"                     "$(seg "echo 'it''s'" 1)"
expect 'PowerShell: a backslash is a character'  'gh:C:\gh.exe api'                   "$(seg '"C:\gh.exe" api' 1)"
expect 'a heredoc operator is a word'            "cat:cat <<EOF"                      "$(seg "cat <<'EOF'")"

echo "== lib/segments.awk: continued lines =="
expect 'backslash-newline joins'                 'gh:gh api x -f a=1'      "$(seg "gh api x \\${nl}  -f a=1")"
expect 'backslash-CRLF joins'                    'gh:gh api x -f a=1'      "$(seg "gh api x \\${cr}${nl}  -f a=1")"
expect 'PowerShell: a backtick-newline joins'    'gh:gh api x -f a=1'      "$(seg "gh api x \`${nl}  -f a=1" 1)"
expect 'a newline without one splits'            'gh:gh api x | grep:grep -f p' "$(seg "gh api x${nl}grep -f p")"

echo "== lib/segments.awk: GH_REPO= and cd in scope =="
expect 'an earlier GH_REPO= reaches a later command'  'o/r'          "$(seg_field 'export GH_REPO=o/r; gh x' gh 6)"
expect 'a host goes'                                  'o/r'          "$(seg_field 'GH_REPO=github.com/o/r; gh x' gh 6)"
expect 'the own prefix is not in scope yet'           ''             "$(seg_field 'GH_REPO=o/r gh x' gh 6)"
expect 'a group ends its scope'                       ''             "$(seg_field '(GH_REPO=o/r); gh x' gh 6)"
expect 'every value in scope'                         'a/b,c/d'      "$(seg_field 'GH_REPO=a/b; GH_REPO=c/d; gh x' gh 7 | tr ',' '\n' | sort | paste -sd, -)"
expect '$env:GH_REPO = "x" counts'                    'o/r'          "$(seg_field '$env:GH_REPO = "o/r"; gh x' gh 6)"
expect 'a quoted GH_REPO= is text'                    ''             "$(seg_field 'echo "GH_REPO=o/r"; gh x' gh 6)"
expect 'cd folders join'                              'D/a/b/c'      "$(seg_field 'cd /a && cd b/ && cd c && gh x' gh 8)"
expect 'a cd to a variable cannot be read'            'I'            "$(seg_field 'cd "$d"; cd /a; gh x' gh 8)"
expect 'a relative cd stays relative'                 'Dsub'         "$(seg_field 'cd sub; gh x' gh 8)"
expect 'cd options are no folder'                    'D/a'          "$(seg_field 'cd -P -- /a; gh x' gh 8)"
expect 'Set-Location -Path'                           'D/a'          "$(seg_field 'Set-Location -Path /a; gh x' gh 8)"
expect 'a cd in a group that ended'                   ''             "$(seg_field '(cd /a); gh x' gh 8)"

echo "== lib/segments.awk: what the review gate reads off a record =="
expect 'the length of a command'                      '8'            "$(seg_field 'gh api x; y' gh 4)"
expect '"review" at or after the command'             'r'            "$(seg_field 'gh api x # Review' gh 5)"
expect 'no "review" after it'                         ''             "$(seg_field 'echo review; gh api x' gh 5)"
expect 'a newline in a quoted word becomes a blank'   'gh:gh api -f b=a b' "$(seg "gh api -f b='a${nl}b'")"

echo "== lib/segments.awk: probes of the first review wave =="
expect 'PowerShell $r=gh'                         'gh:gh api x'    "$(seg '$r=gh api x' 1)"
expect 'PowerShell $r= gh'                        'gh:$r= gh api x' "$(seg '$r= gh api x' 1)"
expect 'PowerShell $r =gh'                        'gh:$r gh api x' "$(seg '$r =gh api x' 1)"
expect 'an escaped backtick inside backticks'     'gh:gh api x'    "$(seg 'x=`echo \`gh api x\``' | sed 's/ | .*//')"
expect 'builtin cd'                               'D/a'            "$(seg_field 'builtin cd /a; gh x' gh 8)"
expect 'find -exec ... ;'                         'gh:gh api x'    "$(seg 'find . -exec gh api x \;' | sed 's/^.* | //')"
for c in 'busybox sh -c' 'su -c' 'fish -c' 'script -qc' 'flock /tmp/l -c'; do
  expect "$c runs its code"                        'gh:gh api x'    "$(seg "$c 'gh api x'" | sed 's/^.* | //')"
done
expect 'a shell takes only its first operand'     'bash:bash -c echo "$1" _ note; gh api x | echo:echo $1' "$(seg "bash -c 'echo \"\$1\"' _ 'note; gh api x'")"
expect 'eval keeps what it assigns'               'o/x'            "$(seg_field "eval 'export GH_REPO=o/x'; gh x" gh 6)"
expect 'bash -c does not'                         ''               "$(seg_field "bash -c 'export GH_REPO=o/x'; gh x" gh 6)"
expect 'a backtick ends the scope like $(...)'    ''               "$(seg_field 'echo `GH_REPO=a/b true`; gh x' gh 6)"
expect 'a quoted $env:GH_REPO= is text'           ''               "$(seg_field "echo '\$env:GH_REPO=o/x'; gh x" gh 6)"
expect 'the scope only on a gh record'            ''               "$(seg_field 'GH_REPO=a/b; echo x' echo 6)"
many=""; for i in $(seq 1 40); do many+="GH_REPO=a/r$i; "; done
expect 'more than 32 distinct values stand as *'  '*'              "$(seg_field "${many}gh x" gh 7)"
long=""; for i in $(seq 1 1100); do long+="cd abcd; "; done
expect 'a very long relative cd chain is unreadable' 'I'           "$(seg_field "${long}gh x" gh 8)"
expect 'a substitution is printed at a higher level' '2 1'         "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<'gh api $(echo x)' | cut -d $'\037' -f10 | paste -sd' ' -)"

echo "== lib/segments.awk: every entry of its word lists (read from the file, so a new entry gets its case) =="
# The words of one list of the BEGIN block: the quoted strings of the split(...) that fills the named array.
list_of() { # array name -> its words, one per line
  awk -v want="$1" '
    /^BEGIN/ { b = 1 } b && /^}/ { exit }
    b && /split\(/ { buf = "" }
    b { line = $0; while (match(line, /"[^"]*"/)) { buf = buf " " substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH) }
        if (match($0, /for \(k in a\) [A-Z]+\[/)) { name = substr($0, RSTART + 13, RLENGTH - 14); if (name == want) { print buf; exit } } }' "$segs" \
    | tr ' ' '\n' | grep -v '^$'
}
name_of() { timeout 20 env LC_ALL=C awk -f "$segs" <<<"$1" | awk -F '\037' '$2 != "" { n = $2 } END { print n }'; }
n_kw=0; for w in $(list_of KW); do n_kw=$((n_kw + 1)); expect "keyword $w before the command" gh "$(name_of "$w gh api x")"; done
n_wr=0; for w in $(list_of WRAP); do n_wr=$((n_wr + 1)); expect "wrapper $w" gh "$(name_of "$w gh api x")"; done
# env -S runs its value as a command line: there the value is the command.
n_wv=0; for e in $(list_of WVAL); do
  n_wv=$((n_wv + 1)); want=gh; case "$e" in env:-S|env:--split-string) want=v ;; esac
  expect "wrapper option $e takes a value" "$want" "$(name_of "${e%%:*} ${e#*:} v gh api x")"
done
n_sh=0; for w in $(list_of SHELL) $(list_of CFLAG); do n_sh=$((n_sh + 1)); expect "$w -c runs its code" gh "$(name_of "$w -c 'gh api x'")"; done
n_sv=0; for o in $(list_of SHVAL); do n_sv=$((n_sv + 1)); expect "bash -c $o v takes a value" gh "$(name_of "bash -c $o v 'gh api x'")"; done
n_cd=0; for w in $(list_of CDCMD); do n_cd=$((n_cd + 1)); expect "$w changes the folder" 'D/a' "$(seg_field "$w /a; gh x" gh 8)"; done
# The lists were read at all: an empty list would leave its loop without a case.
for c in "KW $n_kw" "WRAP $n_wr" "WVAL $n_wv" "SHELL+CFLAG $n_sh" "SHVAL $n_sv" "CDCMD $n_cd"; do
  if [ "${c##* }" -gt 0 ]; then ok "the list ${c% *} was read" "${c##* } entries"; else bad "the list ${c% *} was read" 0 '>0'; fi
done
expect 'an option without a value is the command after it' 'x' "$(name_of 'env -i x gh pr review 5')"

echo "== lib/segments.awk: blanks, quotes and scope edges =="
expect 'a tab is a blank'                         'gh:gh pr review 5'          "$(seg $'gh\tpr\treview 5')"
expect 'a CR is a blank'                          'gh:gh pr review 5'          "$(seg "gh pr${cr}review 5")"
expect 'a CR splits the words'                    4                            "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"gh pr${cr}review 5" | awk -F '\037' '{ print NF - 10 }')"
expect 'timeout with a unit'                      gh                           "$(name_of 'timeout 5s gh api x')"
expect 'timeout with a fraction'                  gh                           "$(name_of 'timeout 1.5 gh api x')"
expect 'an escaped $( in double quotes is text'   'echo:echo $(gh api x)'      "$(seg 'echo "\$(gh api x)"')"
expect 'a backtick in double quotes is code'      'gh:gh api x'                "$(seg 'echo "`gh api x`"' | sed 's/ | .*//')"
expect 'a double quote that never closes'         'echo:echo | x:x | gh:gh api x'    "$(seg 'echo "x; gh api x')"
expect 'PowerShell: `" inside double quotes'      'echo:echo a"b | gh:gh api x' "$(seg 'echo "a`"b"; gh api x' 1)"
expect 'PowerShell: "" inside double quotes'      'echo:echo a"b | gh:gh api x' "$(seg 'echo "a""b"; gh api x' 1)"
expect 'an empty "" is a word'                    'echo:echo  x'               "$(seg 'echo "" x')"
expect 'a glued $env:GH_REPO="x"'                 'o/r'                        "$(seg_field '$env:GH_REPO="o/r"; gh x' gh 6)"
expect 'a group keeps the scope before it'        'a/b'                        "$(seg_field 'GH_REPO=a/b; (true); gh x' gh 6)"
expect 'a cd in bash -c ends with it'             ''                           "$(seg_field 'bash -c "cd /a"; gh x' gh 8)"
expect 'a later absolute cd wins'                 'D/b'                        "$(seg_field 'cd /a; cd /b; gh x' gh 8)"
expect 'a drive-letter cd'                        'DC:/a'                      "$(seg_field 'cd C:/a; gh x' gh 8)"
expect 'GH_REPO stays across a cd'                'a/b'                        "$(seg_field 'GH_REPO=a/b; cd x; gh x' gh 6)"
expect 'the folder stays across a GH_REPO='       'D/x'                        "$(seg_field 'cd /x; GH_REPO=a/b; gh x' gh 8)"
expect 'GH_REPO values compare without case'      1                            "$(seg_field 'GH_REPO=O/R; GH_REPO=o/r; gh x' gh 7 | tr ',' '\n' | wc -l | tr -d ' ')"
for c in '~' '-' ''; do expect "cd ${c:-without a folder} cannot be read" 'I' "$(seg_field "cd $c; gh x" gh 8)"; done
evals=""; for _ in $(seq 1 20); do evals+="eval :; "; done
expect 'evals one after another are no nesting'   0                            "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"${evals}gh api x" | awk -F '\037' '$3 == "d"' | wc -l | tr -d ' ')"
for d in 15 16 17; do
  deep="gh api x"; for _ in $(seq 1 "$d"); do deep="eval $deep"; done
  want=gh; [ "$d" -le 16 ] || want=d
  got="$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"$deep" | awk -F '\037' '$3 == "d" { print "d"; exit } $2 == "gh" { print "gh"; exit }')"
  expect "eval $d deep" "$want" "$got"
done
expect 'nested braces in ${...}'                  'echo:echo ${x:-${y}} | gh:gh api x' "$(seg 'echo ${x:-${y}}; gh api x')"
expect 'an escaped quote in "" in ${...}'         ':${x:-"a\"}"}; gh api x -f b="x" | echo:echo' "$(seg 'echo ${x:-"a\"}"}; gh api x -f b="x"')"
expect 'a ${ that never closes'                   'echo:echo ${x; gh api x'    "$(seg 'echo ${x; gh api x')"

echo "== lib/segments.awk: probes of the second review wave =="
P='gh pr review 5 -R o/r --approve'
# A post is seen where it is a gh record, or inside the record of a ${...} that is not read (flag p).
sees_post() { timeout 20 env LC_ALL=C SEG_PS="${2:-}" awk -f "$segs" <<<"$1" | awk -F '\037' '$2 == "gh" || $3 == "p" { n++ } END { print n + 0 }'; }
has_gh() { timeout 20 env LC_ALL=C SEG_PS="${2:-}" awk -f "$segs" <<<"$1" | awk -F '\037' '$2 == "gh" { n++ } END { print n + 0 }'; }
for c in "echo \${x:-\$($P)}" "echo \${x:-\`$P\`}" ": \${x:=\$($P)}" 'echo `(echo \`'"$P"'\`)`' 'echo `echo $(echo \`'"$P"'\`)`' \
         'echo `echo "\`'"$P"'\`"`' "find . -exec true \; -exec $P \;" "find . -name x -exec echo {} + -exec $P \;" \
         "sh -c 'exec \"\$0\" \"\$@\"' $P" "bash -c '\"\$0\" \"\$@\"' $P" "ash -c '$P'" "mksh -c '$P'" "tcsh -c '$P'" \
         "env -S '$P'" "env --split-string='$P'" "su --command='$P'" "flock /tmp/l $P"; do
  expect "a post in: $c" 1 "$(sees_post "$c")"
done
for c in "1 | %{ $P }" ".{$P}" "\$sb={ $P }; & \$sb" "ForEach-Object -Process{$P}" "[string]\$x = $P" "\$x += $P" "\$x[0] = $P" \
         "\$x.y = $P"; do
  expect "a post in PowerShell: $c" 1 "$(has_gh "$c" 1)"
done
expect 'a quoted ; in find -exec is text'         0      "$(has_gh "find . -exec grep -e 'x;$P' {} \;")"
expect 'bash: {} and {a,b} are text'              'echo:echo {a,b} | gh:gh x'  "$(seg 'echo {a,b}; gh x')"
for c in "\$env:GH_REPO= 'x/y'" "\${env:GH_REPO}='x/y'" 'Set-Item env:GH_REPO x/y'; do
  expect "PowerShell: $c sets the repo" 'x/y' "$(SEG_PS=1 seg_field "$c; gh x" gh 6)"
done
for c in 'export "GH_REPO=x/y"' "export 'GH_REPO'=x/y"; do expect "$c sets the repo" 'x/y' "$(seg_field "$c; gh x" gh 6)"; done
expect 'Push-Location changes the folder'         'D/o'  "$(seg_field 'Push-Location /o; gh x' gh 8)"
expect 'env -C runs the command in a folder'      'D/o'  "$(seg_field 'env -C /o gh x' gh 8)"
expect 'sudo -D runs the command in a folder'     'D/o'  "$(seg_field 'sudo -D /o gh x' gh 8)"
expect 'env -C does not move the next command'    ''     "$(seg_field 'env -C /o true; gh x' gh 8)"
expect 'eval code is no substitution of a later command' '1 1002 2 1' "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"eval 'echo a'; gh api \$(echo b)" | cut -d $'\037' -f10 | paste -sd' ' -)"

expect 'PowerShell: $env:GH_REPO ="o/r"'          'o/r'    "$(SEG_PS=1 seg_field '$env:GH_REPO ="o/r"; gh x' gh 6)"
expect 'a drive-letter cd after another cd'       'DC:/a'  "$(seg_field 'cd /x; cd C:/a; gh x' gh 8)"
expect 'PowerShell: `$ in double quotes is text'  'echo:echo a$(gh api x)' "$(seg 'echo "a`$(gh api x)"' 1)"
expect 'sh -c "$@" starts at $1'                 1        "$(has_gh "sh -c 'echo x; \"\$@\"' _ gh pr review 5")"
expect 'sh -c "$0" starts at $0'                 1        "$(has_gh "sh -c '\"\$0\" \"\$@\"' gh pr review 5")"
echo "== lib/segments.awk: every escape form in \${...}, per mode =="
post='gh api repos/o/r/pulls/5/reviews -f event=APPROVE'
n_forms=0
while IFS=$'\t' read -r mode form; do
  case "$mode" in bash) ps= ;; ps) ps=1 ;; *) continue ;; esac
  n_forms=$((n_forms + 1))
  expect "$mode: $form; post" 1 "$(sees_post "$form; $post" "$ps")"
done < "$forms"
expect 'the escape forms are read from their list' 1 "$([ "$n_forms" -ge 30 ] && echo 1)"
expect 'Bash: ${x/\{/}; post; echo }' 1 "$(sees_post "echo \${x/\\{/}; $post; echo }")"
expect 'a ${...} with a quote is not read: the rest is one record' 'p ' "$(timeout 20 env LC_ALL=C awk -f "$segs" <<<"echo \${x:-'a'}; $post" | cut -d $'\037' -f3 | paste -sd' ' -)"
# Without a quote, \, backtick, $( or $' a ${...} is read exactly, and the command after it stands as its own.
for c in 'echo ${x}' 'echo ${x:-a}' 'echo ${#a[@]}' 'echo ${x:-${y}}'; do
  expect "Bash: $c is read exactly" 'echo:echo '"${c#echo }"' | gh:gh x' "$(seg "$c; gh x")"
done
expect 'PowerShell: ${env:x} is read exactly' 'echo:echo ${env:x} | gh:gh x' "$(seg 'echo ${env:x}; gh x' 1)"
# Bash `${x\}}`, Bash `"${x:-'}"` and PowerShell `${x{}` do not parse in the real shell: no verdict is pinned there.

finish
