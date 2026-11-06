# Shell command segmenter of require-rule-read.sh (ww3d/playbook#537): reads a command line once and prints every
# command that stands in command position, one per line, for the gates to match on. POSIX awk, run with LC_ALL=C.
#
# Input:  the command text on stdin (the hook passes it as a here-string; one trailing newline is dropped).
#         SEG_PS=1 in the environment reads it as PowerShell: the backtick escapes and continues a line, `\` is a
#         plain character, `''` in single quotes and `""` in double quotes are a quote character.
# Output: one line per command, fields separated by \037:
#           1 C
#           2 the command word's name: last path part, lower case, `.exe` dropped (`/usr/bin/GH.exe` -> gh)
#           3 flags: `s` where a word of the command holds a substitution ($(...), `...`, <(...), >(...)); `d` on
#             the one record of code nested deeper than MAXDEPTH, `p` on the one of a ${...} holding a quote, \,
#             backtick, $( or $' and the rest of the text after it; neither is read (field 11 holds it whole)
#           4 the command's length in characters, from its first word to its end
#           5 `r` where the text "review" (any case, quoted or not) starts at or after the command's start
#           6 the last GH_REPO= value in scope before this command (repo form: no host)
#           7 every distinct GH_REPO= value in scope, joined by \035; `*` for more than MAXDIST of them
#           8 the folder state of cd/pushd/Set-Location in scope: empty, `I` (a folder it cannot read) or `D<path>`
#           (fields 6 to 8 only on a record whose command is gh, empty on every other)
#           9 the index of the command word among the words (1-based)
#          10 its nesting level: the commands of a substitution are printed before the command that holds it, with a
#             higher level; code read again (bash -c, eval) adds 1000 per step, so it never counts as a substitution
#             of the command after it
#          11 onwards the command's words, unquoted, a substitution standing as `$(...)`; newlines as blanks
# A command's words before its command word are kept: environment assignments, the keywords `if`, `then`, `!`
# and the like, and the wrappers sudo, doas, env, command, time, nohup, timeout, xargs, nice, ionice, stdbuf, setsid
# and exec with their options. A command is split at ; & | && || and newlines, at ( ) groups, at a { or } that
# starts a word (a PowerShell script block too; there any } ends one), and inside $(...),
# backticks and <(...) / >(...); a redirection (2>&1, &>, >|, <&) is a word, no separator. The code after -c of
# sh/bash/zsh/dash/ksh, after -c/-Command of pwsh/powershell, after /c or /k of cmd and after eval, iex and
# Invoke-Expression is read again as commands of its own, printed after the command that carries it. A quoted span
# is one word and holds no command; a `#` at a word's start comments out the rest of its line; `\` (PowerShell: the
# backtick) before a newline joins the lines. A quote that never closes ends the command before it. Heredoc bodies
# are blanked by lib/heredoc.sh before the text gets here.
#
# GH_REPO= and cd values reach the commands after them up to the ( ) group or substitution they stand in; a GH_REPO=
# word counts wherever it stands unquoted at a word's start (`export GH_REPO=x`, a prefix), $env:GH_REPO = x too.

BEGIN {
  RS = "\001"; US = "\037"; GS = "\035"
  ps = (ENVIRON["SEG_PS"] == "1")
  # Characters that end a run of plain word characters.
  SPECIAL = ps ? " \t\r\n;&|(){}<>$`'\"#" : " \t\r\n;&|(){}<>$`'\"#\\"
  DQSPECIAL = ps ? "\"$`" : "\"$`\\"
  split("if then do else elif while until !", a, " "); for (k in a) KW[a[k]] = 1
  split("sudo doas env command builtin time nohup timeout xargs nice ionice stdbuf setsid exec coproc busybox watch", a, " ")
  for (k in a) WRAP[a[k]] = 1
  # Wrapper options that take the next word as their value, short and long.
  split("sudo:-u sudo:-g sudo:-h sudo:-p sudo:-C sudo:-U sudo:-r sudo:-t sudo:-D sudo:-R sudo:-T " \
        "sudo:--user sudo:--group sudo:--host sudo:--prompt sudo:--close-from sudo:--other-user sudo:--role " \
        "sudo:--type sudo:--chdir sudo:--chroot sudo:--command-timeout doas:-u doas:-C " \
        "env:-u env:-C env:-S env:--unset env:--chdir env:--split-string nice:-n nice:--adjustment " \
        "timeout:-s timeout:-k timeout:--signal timeout:--kill-after " \
        "xargs:-n xargs:-I xargs:-L xargs:-P xargs:-s xargs:-d xargs:-E xargs:-a xargs:--max-args " \
        "xargs:--max-procs xargs:--max-chars xargs:--delimiter xargs:--arg-file xargs:--process-slot-var " \
        "ionice:-c ionice:-n ionice:-p ionice:-P ionice:-u ionice:--class ionice:--classdata ionice:--pid " \
        "ionice:--pgid ionice:--uid stdbuf:-i stdbuf:-o stdbuf:-e stdbuf:--input stdbuf:--output " \
        "stdbuf:--error exec:-a time:-f time:-o time:--format time:--output watch:-n watch:--interval", a, " ")
  for (k in a) WVAL[a[k]] = 1
  # Options of sh/bash/zsh that take the next word as their value (between -c and the code too).
  split("-o +o -O +O", a, " "); for (k in a) SHVAL[a[k]] = 1
  # Wrapper options whose value is the folder the command runs in.
  split("env:-C env:--chdir sudo:-D sudo:--chdir", a, " "); for (k in a) WCD[a[k]] = 1
  split("sh bash zsh dash ksh fish ash mksh tcsh csh", a, " "); for (k in a) SHELL[a[k]] = 1
  # Other programs that hand the word after -c (or --command) to a shell.
  split("su script flock", a, " "); for (k in a) CFLAG[a[k]] = 1
  split("cd pushd set-location sl chdir push-location", a, " "); for (k in a) CDCMD[a[k]] = 1
  L = 0; OD = 0; NENT = 0; NDIST = 0; NWL = 0; MAXDEPTH = 16; MAXDIST = 32; MAXCD = 4096
}
{ text = (NR > 1) ? text RS $0 : $0 }
END { sub(/\n$/, "", text); parse(text) }

# Position of the last occurrence of a literal needle (no regex character in it), 0 when there is none.
function lastpos(s, needle,   parts, n) {
  n = split(s, parts, needle)
  return n < 2 ? 0 : length(s) - length(parts[n]) - length(needle) + 1
}

function reset_level(l) { NW[l] = 0; CW[l] = ""; WS[l] = 0; FQ[l] = 0; Q[l] = ""; SUBF[l] = 0; START[l] = 0 }

# The word in progress gets text; its first character decides whether it starts quoted.
function addw(l, t, quoted) {
  if (!WS[l]) { WS[l] = 1; FQ[l] = quoted; if (NW[l] == 0) START[l] = POS }
  CW[l] = CW[l] t
}
function end_word(l) {
  if (!WS[l]) return
  NW[l]++; W[l, NW[l]] = CW[l]; WQ[l, NW[l]] = FQ[l]
  CW[l] = ""; WS[l] = 0; FQ[l] = 0
}
function end_cmd(l) {
  end_word(l)
  if (NW[l] > 0) emit(l)
  NW[l] = 0; SUBF[l] = 0
}

# An opening bracket: type S (a substitution, its own level), B (a backtick substitution, its own level; E for one
# opened by an escaped backtick inside another) or G (a ( ) group: the command before it ends). Each is a subshell:
# the scope of the assignments inside ends with it.
function open_br(type) {
  if (type == "G") end_cmd(L)
  else { addw(L, "$(...)", 0); SUBF[L] = 1 }
  OD++; BT[OD] = type; BM[OD] = NENT
  if (type != "G") { L++; reset_level(L) }
}
function close_br(   type) {
  type = BT[OD]
  end_cmd(L)
  if (type != "G") L--
  scope_to(BM[OD])
  OD--
}

# --- scope of GH_REPO= and cd ------------------------------------------------------------------------------------
function scope_to(m,   k) {
  while (NENT > m) {
    if (EK[NENT] == "R") { k = tolower(EV[NENT]); if (--RCNT[k] <= 0) { delete RCNT[k]; NDIST-- } }
    NENT--
  }
}
function repo_form(v) { gsub(/["']/, "", v); if (v ~ /\/.*\//) sub(/^[^\/]*\//, "", v); return v }
function push_repo(v,   k) {
  v = repo_form(v); NENT++; EK[NENT] = "R"; EV[NENT] = v
  ELR[NENT] = NENT; ECD[NENT] = (NENT > 1) ? ECD[NENT - 1] : ""
  k = tolower(v); if (RCNT[k]++ == 0) NDIST++; REP[k] = v
}
function push_cd(v,   st) {
  st = cd_join((NENT > 0) ? ECD[NENT] : "", v)
  NENT++; EK[NENT] = "C"; EV[NENT] = v; ECD[NENT] = st
  ELR[NENT] = (NENT > 1) ? ELR[NENT - 1] : 0
}

function base_name(w) { w = tolower(w); sub(/^.*[\/\\]/, "", w); sub(/\.exe$/, "", w); return w }

# --- one command -------------------------------------------------------------------------------------------------
function emit(l, num,   n, k, w, lw, b, i, last, dist, cdst, key, ci, name, j, code, rev, one, keep, envrepo, op, \
              rest, wcd, split_s) {
  n = NW[l]; k = 1; if (num == "") num = l
  while (k <= n) {
    w = W[l, k]; lw = tolower(w)
    if (!WQ[l, k] && (lw in KW)) { k++; continue }
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; continue }
    # A PowerShell assignment ($x = gh, $x=gh, $x= gh, $x =gh, [string]$x = gh, $x += gh, ${env:GH_REPO}='o/r').
    if (!WQ[l, k] && w ~ /^(\[[^]]*\])*\$[A-Za-z_{][^=]*[-+*\/%?]?=$/) {
      if (lw ~ /^\$\{?env:gh_repo\}?=$/ && k < n) envrepo = W[l, k + 1]
      k++; continue
    }
    if (!WQ[l, k] && w ~ /^(\[[^]]*\])*\$[A-Za-z_{][^=]*[-+*\/%?]?=./) {
      rest = w; sub(/^[^=]*=/, "", rest)
      if (lw ~ /^\$\{?env:gh_repo\}?=/) envrepo = rest
      W[l, k] = rest; continue
    }
    if (!WQ[l, k] && w ~ /^(\[[^]]*\])*\$[A-Za-z_{][^=]*$/ && k < n && W[l, k + 1] ~ /^[-+*\/%?]*=/) {
      op = W[l, k + 1]; sub(/=.*/, "=", op); rest = substr(W[l, k + 1], length(op) + 1)
      if (lw ~ /^\$\{?env:gh_repo\}?$/) envrepo = (rest != "") ? rest : W[l, k + 2]
      if (rest == "") k += 2; else { k++; W[l, k] = rest }
      continue
    }
    b = base_name(w)
    if (b in WRAP) {
      k++
      while (k <= n) {
        w = W[l, k]
        if (w ~ /^-/) {
          # env -C and sudo -D run the command in another folder; env -S runs a command line.
          if ((b ":" w) in WCD) wcd = W[l, k + 1]
          else if (w ~ /^--chdir=/ && (b == "env" || b == "sudo")) { wcd = w; sub(/^[^=]*=/, "", wcd) }
          if (b == "env" && (w == "-S" || w == "--split-string")) split_s = W[l, k + 1]
          else if (b == "env" && w ~ /^--split-string=/) { split_s = w; sub(/^[^=]*=/, "", split_s) }
          k++; if ((b ":" w) in WVAL) k++
          continue
        }
        if (w ~ /^[0-9][0-9.]*[smhd]?$/ && b == "timeout") { k++; continue }
        break
      }
      continue
    }
    break
  }
  ci = k; name = (k <= n) ? base_name(W[l, k]) : ""
  # The scope only where a gate reads it, a gh command: printed with every command it would grow with their number.
  last = dist = cdst = ""
  if (name == "gh") {
    last = (NENT > 0 && ELR[NENT] > 0) ? EV[ELR[NENT]] : ""
    # More distinct values than MAXDIST stand as `*`, which names no repo: the gate reads it as another one.
    if (NDIST > MAXDIST) dist = "*"
    else for (key in RCNT) dist = dist (dist == "" ? "" : GS) REP[key]
    cdst = (NENT > 0) ? ECD[NENT] : ""
    if (wcd != "") cdst = cd_join(cdst, wcd)
  }
  rev = (REVPOS > 0 && REVPOS >= START[l]) ? "r" : ""
  printf "%s", "C" US name US (SUBF[l] ? "s" : "") US (POS - START[l]) US rev US last US dist US cdst US ci US \
    (DEPTH * 1000 + num)
  for (i = 1; i <= n; i++) { w = W[l, i]; gsub(/[\n\r\037]/, " ", w); printf "%s", US w }
  printf "\n"

  # What this command leaves in scope for the commands after it. export and its kin assign a quoted GH_REPO= too.
  keep = (name == "export" || name == "declare" || name == "typeset" || name == "local" || name == "readonly")
  for (i = 1; i <= n; i++) if ((!WQ[l, i] || (keep && i > ci)) && W[l, i] ~ /^GH_REPO=/) push_repo(substr(W[l, i], 9))
  if (envrepo != "") push_repo(envrepo)
  if (name == "set-item" && ci + 2 <= n && tolower(W[l, ci + 1]) == "env:gh_repo") push_repo(W[l, ci + 2])
  if (name in CDCMD) {
    # The folder is the first word that is no option (`cd -P x`, `cd -- x`, `Set-Location -Path x`).
    for (i = ci + 1; i <= n && W[l, i] ~ /^-./; i++) {
      lw = tolower(W[l, i])
      if (lw == "--" || lw == "-path" || lw == "-literalpath") { i++; break }
    }
    push_cd(i <= n ? W[l, i] : "")
  }

  # Code another program runs: read again as commands of their own. A shell (sh, bash, ..., su, script, flock)
  # takes its first operand after -c, and the words after it where that code runs them ("$0" "$@"); pwsh -Command,
  # cmd /c, eval and iex the rest of the line; flock without -c the words after its lock file; each find -exec the
  # words up to `;` or `+`, and env -S its string. eval and iex run in this shell: what they assign stays in scope.
  if (split_s != "") {
    code = split_s " " join_words(l, ci, n)
    read_code(code, 0, l, num)
  }
  if (name == "find") {
    for (i = ci + 1; i <= n; i++) {
      if (W[l, i] !~ /^-(exec|execdir|ok|okdir)$/) continue
      for (j = i + 1; j <= n && W[l, j] != ";" && W[l, j] != "+"; j++) ;
      emit_words(l, i + 1, j - 1, num); i = j
    }
    return
  }
  code = ""; j = 0; one = 0; keep = 0; last = n
  if (name in SHELL || name in CFLAG) {
    for (i = ci + 1; i <= n; i++) {
      lw = W[l, i]
      if (!WQ[l, i] && (lw ~ /^-[A-Za-z]*c$/ || lw == "--command")) { j = i; break }
      # A glued --command=... is the whole code.
      if (!WQ[l, i] && lw ~ /^--command=/) { code = lw; sub(/^[^=]*=/, "", code); read_code(code, 0, l, num); return }
    }
    one = 1
    if (j == 0 && name == "flock") {
      for (i = ci + 1; i <= n && W[l, i] ~ /^-/; i++) if (W[l, i] ~ /^-(w|E|-timeout|-conflict-exit-code)$/) i++
      if (i < n) { emit_words(l, i + 1, n, num); return }
    }
  } else if (name == "pwsh" || name == "powershell") {
    for (i = ci + 1; i <= n; i++) { lw = tolower(W[l, i]); if (lw == "-c" || lw == "-command") { j = i; break } }
  } else if (name == "cmd") {
    for (i = ci + 1; i <= n; i++) { lw = tolower(W[l, i]); if (lw == "/c" || lw == "/k") { j = i; break } }
  } else if (name == "eval" || name == "iex" || name == "invoke-expression") { j = ci; keep = 1 }
  # Options between -c and a shell's code are skipped (`bash -c -e '...'`).
  if (j > 0 && one)
    while (j < n && W[l, j + 1] ~ /^[-+]./ && !WQ[l, j + 1]) j += (W[l, j + 1] in SHVAL) ? 2 : 1
  # A quoted operand is the whole code; an unquoted one runs on with the words after it, read as one command.
  if (j > 0 && one && WQ[l, j + 1]) {
    last = j + 1
    # "$0" runs the first word after the code; "$@" and "$*" start at $1, the word after it.
    if (W[l, j + 1] ~ /\$0/ && j + 2 <= n) emit_words(l, j + 2, n, num)
    else if (W[l, j + 1] ~ /\$[@*]/ && j + 3 <= n) emit_words(l, j + 3, n, num)
  }
  if (j > 0 && j < last) {
    code = join_words(l, j + 1, last)
    read_code(code, keep, l, num)
  }
}

# Code read again; nested deeper than MAXDEPTH it is not read: its record says so (flag d), and the gate reads it
# fail-closed.
function read_code(code, keep, l, num,   w) {
  if (DEPTH >= MAXDEPTH) {
    w = code; gsub(/[\n\r\037]/, " ", w)
    print "C" US "" US "d" US length(code) US "r" US US US US 1 US (DEPTH * 1000 + num) US w
  } else reparse(code, keep)
}

# Words a program runs as a command without a shell (find -exec, flock, "$@" of sh -c): a record of their own.
function emit_words(l, a, b, num,   l2, i) {
  if (a > b) return
  l2 = "w" (++NWL)
  NW[l2] = 0; SUBF[l2] = 0; START[l2] = START[l]
  for (i = a; i <= b; i++) { NW[l2]++; W[l2, NW[l2]] = W[l, i]; WQ[l2, NW[l2]] = WQ[l, i] }
  emit(l2, num)
}

# The folder after a cd to v from the state prev (empty, `I` or `D<path>`).
function cd_join(prev, v,   st) {
  if (prev == "I" || v == "" || v == "-" || v ~ /[$`]/ || v ~ /^~/) return "I"
  if (v ~ /^\// || v ~ /^[A-Za-z]:/) return "D" v
  if (prev == "") return "D" v
  # A chain of relative folders longer than MAXCD characters counts as one that cannot be read (fail-closed).
  if (length(prev) > MAXCD) return "I"
  st = prev; sub(/\/$/, "", st); return st "/" v
}

function reparse(code, keep,   sv_pos, sv_rev, sv_l, m) {
  sv_pos = POS; sv_rev = REVPOS; sv_l = L; m = NENT
  DEPTH++; parse(code); DEPTH--
  if (!keep) scope_to(m)
  POS = sv_pos; REVPOS = sv_rev; L = sv_l
}

# The `}` that closes a ${ at position p (its `{`), nested braces counted; the text's end where none closes. Its
# grammar differs by shell and mode, so a quote, \, backtick, $( or $' in it is not read: PSPEC says so, at its place.
function param_end(s, p, n,   d, c, c2) {
  d = 0; PSPEC = 0
  while (p <= n) {
    c = substr(s, p, 1)
    c2 = substr(s, p + 1, 1)
    if (c == "'" || c == "\"" || c == "`" || c == "\\" || (c == "$" && (c2 == "(" || c2 == "'"))) {
      PSPEC = 1; return p
    }
    if (c == "{") d++
    else if (c == "}" && --d == 0) return p
    p++
  }
  return n
}

# Whether a backtick substitution is open in this pass (inside it, an escaped backtick opens or closes one).
function in_bt(od0,   k) { for (k = OD; k > od0; k--) if (BT[k] == "B" || BT[k] == "E") return 1; return 0 }

# The words a..b of level l joined by blanks; halving keeps the copying at n log n where a loop would copy n^2.
function join_words(l, a, b,   m) {
  if (a > b) return ""
  if (a == b) return W[l, a]
  m = int((a + b) / 2)
  return join_words(l, a, m) " " join_words(l, m + 1, b)
}

# Whether the character at j continues a run of word characters: a plain one, a Bash brace, a < or > that opens no
# process substitution, and a & or | stuck to one of them (2>&1, >|, &>) - so a long word is copied once.
function in_run(s, j,   c, p) {
  c = substr(s, j, 1)
  if (index(SPECIAL, c) == 0) return 1
  if (!ps && (c == "{" || c == "}")) return 1
  if (c == "<" || c == ">") return substr(s, j + 1, 1) != "("
  if (c == "&" || c == "|") { p = substr(s, j - 1, 1); return p == "<" || p == ">" || (c == "&" && substr(s, j + 1, 1) == ">") }
  return 0
}

# --- the scan ----------------------------------------------------------------------------------------------------
function parse(s,   n, i, c, c2, j, base, od0, lsq, ldq, d) {
  n = length(s)
  lsq = lastpos(s, "'"); ldq = lastpos(s, "\""); REVPOS = lastpos(tolower(s), "review")
  base = L; od0 = OD; L = base + 1; reset_level(L)
  i = 1
  while (i <= n) {
    POS = i; c = substr(s, i, 1)
    if (Q[L] == "\"") {
      if (c == "\"") {
        if (ps && substr(s, i + 1, 1) == "\"") { addw(L, "\"", 1); i += 2; continue }
        Q[L] = ""; i++; continue
      }
      if (c == "$" && substr(s, i + 1, 1) == "(") { open_br("S"); i += 2; continue }
      if (c == "`" && !ps) { open_br("B"); i++; continue }
      if (ps ? c == "`" : c == "\\") {
        c2 = substr(s, i + 1, 1)
        if (!ps && c2 == "`" && in_bt(od0)) { if (BT[OD] == "E") close_br(); else open_br("E"); i += 2; continue }
        if (c2 == "\n") { i += 2; continue }
        if (ps || c2 == "$" || c2 == "`" || c2 == "\"" || c2 == "\\") { addw(L, c2, 1); i += 2; continue }
        addw(L, c, 1); i++; continue
      }
      j = i + 1
      while (j <= n && index(DQSPECIAL, substr(s, j, 1)) == 0) j++
      addw(L, substr(s, i, j - i), 1); i = j; continue
    }
    if (index(SPECIAL, c) == 0) {
      j = i + 1
      while (j <= n && in_run(s, j)) j++
      addw(L, substr(s, i, j - i), 0); i = j; continue
    }
    if (c == " " || c == "\t" || c == "\r") { end_word(L); i++; continue }
    if ((c == "\\" && !ps) || (c == "`" && ps)) {
      c2 = substr(s, i + 1, 1)
      # Inside a backtick substitution an escaped backtick opens or closes one nested in it.
      if (!ps && c2 == "`" && in_bt(od0)) {
        if (BT[OD] == "E") close_br(); else open_br("E")
        i += 2; continue
      }
      if (c2 == "\n") { i += 2; continue }
      if (c2 == "\r" && substr(s, i + 2, 1) == "\n") { i += 3; continue }
      addw(L, c2, 0); i += 2; continue
    }
    if (c == "\n" || c == ";") { end_cmd(L); i++; continue }
    if (c == "&" || c == "|") {
      c2 = substr(s, i - 1, 1)
      if (WS[L] && (c2 == ">" || c2 == "<")) { addw(L, c, 0); i++; continue }
      if (c == "&" && substr(s, i + 1, 1) == ">") { addw(L, c, 0); i++; continue }
      end_cmd(L); i++; continue
    }
    if (c == "<" || c == ">") {
      if (substr(s, i + 1, 1) == "(") { open_br("S"); i += 2; continue }
      addw(L, c, 0); i++; continue
    }
    if (c == "$") {
      c2 = substr(s, i + 1, 1)
      if (c2 == "(") { open_br("S"); i += 2; continue }
      if (c2 == "{") {
        j = param_end(s, i + 1, n)
        # A quote, escape or substitution inside ${...} is not read: the rest from the ${ is one record (flag p).
        if (PSPEC) {
          c2 = substr(s, i); gsub(/[\n\r\037]/, " ", c2)
          print "C" US "" US "p" US length(c2) US "r" US US US US 1 US (DEPTH * 1000 + L) US c2
          i = n + 1; continue
        }
        addw(L, substr(s, i, j - i + 1), 0); i = j + 1; continue
      }
      addw(L, c, 0); i++; continue
    }
    if (c == "`") {
      if (OD > od0 && BT[OD] == "B") close_br(); else open_br("B")
      i++; continue
    }
    if (c == "(") { open_br("G"); i++; continue }
    # { } groups and PowerShell script blocks: the command before ends, the block holds commands of its own.
    # A brace inside a word (`repos/{owner}/{repo}`) is text; PowerShell opens and ends a block at any brace.
    # In Bash a brace is a group only as a word of its own ({ cmd; }): {}, {a,b} and {gh are text.
    c2 = substr(s, i + 1, 1)
    if ((c == "{" || c == "}") && (ps || (!WS[L] && (c2 == "" || index(c == "{" ? " \t\r\n" : " \t\r\n;&|)", c2)))))
      { end_cmd(L); i++; continue }
    if (c == "{" || c == "}") { addw(L, c, 0); i++; continue }
    if (c == ")") {
      if (OD > od0 && BT[OD] != "B") close_br(); else end_cmd(L)
      i++; continue
    }
    if (c == "#") {
      if (WS[L]) { addw(L, c, 0); i++; continue }
      # Inside a backtick substitution the closing backtick ends the comment too.
      if (OD > od0 && (BT[OD] == "B" || BT[OD] == "E")) { while (i <= n && (c2 = substr(s, i, 1)) != "\n" && c2 != "`") i++ }
      else { while (i <= n && substr(s, i, 1) != "\n") i++ }
      continue
    }
    if (c == "'") {
      if (i == lsq) { end_cmd(L); i++; continue }
      j = i + 1
      while (j <= n) {
        if (substr(s, j, 1) == "'") { if (ps && substr(s, j + 1, 1) == "'") { j += 2; continue }; break }
        j++
      }
      c2 = substr(s, i + 1, j - i - 1); if (ps) gsub(/''/, "'", c2)
      addw(L, c2, 1); i = j + 1; continue
    }
    if (c == "\"") {
      if (i == ldq) { end_cmd(L); i++; continue }
      addw(L, "", 1); Q[L] = "\""; i++; continue
    }
    addw(L, c, 0); i++
  }
  POS = n + 1
  while (OD > od0) close_br()
  end_cmd(L)
  L = base
}
