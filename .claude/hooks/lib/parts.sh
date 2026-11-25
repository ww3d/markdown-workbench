# shellcheck shell=bash
# Sourced by lib/state.sh, never run: the read parts of a large restore file (ww3d/playbook#672, decision 6). A file
# above 25,000 tokens (the Read tool's limit) is named as offset/limit pairs for the Read tool that close up from line 1
# to the last line, cut at "## " borders where a section fits, each part under 15,000 tokens - so
# record-rule-read.sh sees the file read without a gap. Tokens are counted as 1.8 characters a token (measured on the
# restore files of this machine, ww3d/playbook#699), the line number the Read tool puts before each line as 8 more.

state_part_whole=45000
state_part_chars=27000

state_read_parts() { # file -> "offset=<a> limit=<b>, ..." on stdout, nothing at or under 25,000 tokens
  [ -s "$1" ] || return 0
  # A section that fits whole in the part begun stays in it; one that does not starts a new part; one larger than a
  # part is cut between lines.
  LC_ALL=C awk -v max="$state_part_chars" -v whole="$state_part_whole" '
    function cut(to) { out = out sep "offset=" first " limit=" (to - first + 1); sep = ", "; first = to + 1; used = 0 }
    { sub(/\r$/, ""); c[NR] = length($0) + 8; all += c[NR]; head[NR] = ($0 ~ /^## /) }
    END {
      if (all <= whole) exit
      first = 1; used = 0
      for (i = NR; i >= 1; i--) { run += c[i]; sec[i] = run; if (head[i]) run = 0 }
      for (i = 1; i <= NR; i++) {
        if (head[i] && used > 0 && used + sec[i] > max) cut(i - 1)
        if (used > 0 && used + c[i] > max) cut(i - 1)
        used += c[i]
      }
      cut(NR); print out
    }' "$1"
}
