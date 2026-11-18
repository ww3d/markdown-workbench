# Background-run detector of guard-kill.sh step 0 (ww3d/playbook#652). POSIX awk, run with LC_ALL=C.
#
# Input:  the command text on stdin. Output: `HIT` when a run word stands in a part of the command that a
#         background `&` cuts off, nothing otherwise.
# Run word: `rc run`, build.ps1, test.ps1, `dotnet build`, `dotnet test`, any case.
#
# What is read, in this order:
#   1. Data is blanked: the bodies of here-documents (`<<X`, `<<'X'`, `<<-X`) and PowerShell here-strings
#      (`@'`, `@"`), and a `#` comment to the end of its line. Quoted spans keep their words for the run-word
#      test (`cmd //c "start /b build.ps1" &` hits) but hold no operator: a `&` inside quotes is no `&`.
#   2. A background `&` is one that is not part of `&&`, `&>`, `>&`, `<&` or `|&`, and not a PowerShell call
#      operator (nothing but blanks before it in its command).
#   3. What the `&` cuts off is its unit: the command after the last `;`, newline, `(`, `{` or earlier `&`
#      at the same level, with `&&`, `||` and `|` inside it (the whole list or pipeline goes to the
#      background); where the `&` follows a closing `)` or `}`, the whole group. The run word must stand in
#      the unit. A `&` inside a group is read the same way (`(rc run x &); echo`).
# Limits, by design: the text is read, nothing runs; a script file or a variable holding the run is not opened;
# an unreadable shape passes.

function blank(str,   r) { r = str; gsub(/[^\n]/, " ", r); return r }

BEGIN { RS = "\001" }

{
  s = $0
  # --- 1a. here-documents and here-strings: blank the bodies, line by line
  nl = split(s, line, "\n")
  t = ""
  mode = 0; delim = ""
  for (k = 1; k <= nl; k++) {
    L = line[k]
    if (mode == 1) {                       # inside a here-document
      probe = L; sub(/^[ \t]+/, "", probe); sub(/\r$/, "", probe)
      if (probe == delim) mode = 0
      L = blank(L)
    } else if (mode == 2) {                # inside a PowerShell here-string
      if (L ~ /^['"]@/) mode = 0
      L = blank(L)
    } else {
      if (match(L, /<<-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
        d = substr(L, RSTART, RLENGTH)
        sub(/^<<-?[ \t]*['"]?/, "", d); sub(/['"]?$/, "", d)
        # A shell or PowerShell reading the body runs it: the body stays code.
        if (substr(tolower(L), 1, RSTART - 1) !~ /(^|[^a-z0-9_.-])(ba|z|da|k)?sh([ \t]|$)|pwsh|powershell/) { delim = d; mode = 1 }
      } else if (L ~ /@['"][ \t]*$/) {
        mode = 2
      }
    }
    t = t L (k < nl ? "\n" : "")
  }
  n = length(t)

  # --- 1b. structure copy m: quoted spans and comments blanked to x / space, same length as t
  m = ""; sq = 0; dq = 0; word = 1
  for (i = 1; i <= n; i++) {
    c = substr(t, i, 1)
    if (sq) { if (c == "'") sq = 0; m = m (c == "\n" ? c : "x"); continue }
    if (dq) {
      if (c == "\\") { m = m "x"; i++; if (i <= n) m = m (substr(t, i, 1) == "\n" ? "\n" : "x"); continue }
      if (c == "\"") dq = 0
      m = m (c == "\n" ? c : "x"); continue
    }
    if (c == "'") { sq = 1; m = m "x"; word = 0; continue }
    if (c == "\"") { dq = 1; m = m "x"; word = 0; continue }
    if (c == "\\") { m = m "x"; i++; if (i <= n) m = m (substr(t, i, 1) == "\n" ? "\n" : "x"); word = 0; continue }
    if (c == "#" && word) {                # comment to the end of the line
      while (i <= n && substr(t, i, 1) != "\n") { m = m " "; i++ }
      i--; continue
    }
    m = m c
    word = (c == " " || c == "\t" || c == "\n" || c == ";" || c == "(" || c == "&" || c == "|")
  }

  # --- 2 and 3. walk m, keep the unit start and the groups
  tl = tolower(t)
  ustart = 1; lastclose = 0; depth = 0; hit = 0
  for (i = 1; i <= n && !hit; i++) {
    c = substr(m, i, 1)
    if (c == " " || c == "\t") continue
    if (c == "\n" || c == ";") { ustart = i + 1; lastclose = 0; continue }
    if (c == "(" || (c == "{" && (i == 1 || substr(m, i - 1, 1) ~ /[ \t\n;(]/) && substr(m, i + 1, 1) ~ /[ \t\n]/)) {
      pv = (i > 1 ? substr(m, i - 1, 1) : ""); depth++; gopen[depth] = i; gkind[depth] = (c == "(" && (pv == "$" || pv == "<" || pv == ">")) ? "s" : c; gus[depth] = ustart; ustart = i + 1; lastclose = 0; continue
    }
    if ((c == ")" && depth > 0 && (gkind[depth] == "(" || gkind[depth] == "s")) || (c == "}" && depth > 0 && gkind[depth] == "{")) {
      if (gkind[depth] == "s") ustart = gus[depth]; else lastclose = gopen[depth]
      depth--; continue
    }
    if (c == "&") {
      nx = substr(m, i + 1, 1); pv = (i > 1 ? substr(m, i - 1, 1) : "")
      if (nx == "&") { i++; lastclose = 0; continue }          # &&
      if (nx == ">" || pv == ">" || pv == "<" || pv == "|") continue
      from = (lastclose > 0 ? lastclose : ustart)
      unit = substr(m, from, i - from)
      if (lastclose == 0 && unit ~ /^[ \t\n]*$/) continue      # call operator
      probe = substr(tl, from, i - from)
      if (probe ~ /(^|[^a-z0-9_.-])rc[ \t]+run([^a-z0-9_-]|$)|build\.ps1|test\.ps1|dotnet[ \t]+(build|test)([^a-z0-9_-]|$)/) hit = 1
      ustart = i + 1; lastclose = 0; continue
    }
    if (c == "|") lastclose = 0
  }
  if (hit) print "HIT"
}
