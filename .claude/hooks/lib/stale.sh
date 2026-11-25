# shellcheck shell=bash
# Sourced by lib/state.sh, never run: the state check of the references (ww3d/playbook#672, decision log
# docs/decisions/2026-11-21T0115Z-playbook-672-save-restore-gaps-decisions.md, decisions 1 and 7). A line of a pair
# or an open box that says "offen" next to a merged pull request, or "wartet auf Frage N" next to an answered
# question, is a box "stale: ..."; the stand comes from lib/resolve.sh (one resolve_snapshot a run), no model.
# Needs lib/state.sh (state_norm_jq, state_extract_jq, state_match, state_key) and jq.
# shellcheck disable=SC2154 # state_norm_jq and state_extract_jq are set by lib/state.sh before it sources this file

# shellcheck source=SCRIPTDIR/resolve.sh
. "${BASH_SOURCE[0]%/*}/resolve.sh"

# The fixed patterns: words that say open, words that say done, words that say a question still waits; whole words
# of the normal form. A reference "#N" belongs to the repo of its carrier, "Frage N" and "question N" are qN; the
# number of a message in a thread ("Nachricht #2", "Nachfrage #10 und #11", "Verlauf #1", "message #3") is none.
# shellcheck disable=SC2016 # jq text, not shell
state_stale_defs="$state_norm_jq"'
def words: norm | " " + . + " ";
def w_open: test(" (offen|wartet|laeuft|draft|open|waiting) ");
def w_done: test(" (gemergt|geschlossen|erledigt|merged|closed|done) ");
def w_q: test(" (offen|wartet|nach frage) ");
def refnorm($repo): gsub("\\b(?:[Nn]achricht(?:en)?|[Nn]achfragen?|[Vv]erlauf|[Mm]essages?|[Ff]ollow-ups?)\\s+#[0-9]+(?:\\s*(?:und|and|bis|to|/)\\s*#[0-9]+)*"; "")
  | (if $repo == "" then . else gsub("(?<a>^|[^A-Za-z0-9_/.#-])#(?<n>[0-9]+)"; "\(.a)\($repo)#\(.n)") end)
  | gsub("\\b(?:[Ff]rage|[Qq]uestion) (?<n>[0-9]+)\\b"; "q\(.n)");
def refs_of: [scan("https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(?:issues|pull)/[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|(?<![A-Za-z0-9_])q[0-9]{3,6}\\b")
  | sub("^https://github\\.com/(?<r>[^/]+/[^/]+)/(?:issues|pull)/(?<n>[0-9]+)$"; "\(.r)#\(.n)")] | unique;
# The references of a line a pattern can judge: an issue or pull request where an open or done word stands, a
# question where a waiting word stands.
def judged($repo): (words) as $w | (refnorm($repo) | refs_of)
  | map(select(if startswith("q") then ($w | w_q) else ($w | w_open or w_done) end));
def one: gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");'

# The open boxes under "## Open points" of a carrier body, continuation lines joined, quotes skipped.
state_open_boxes() { # body file -> one box a line on stdout, without "- [ ] "
  awk 'function flush() { if (box != "") print box; box = "" }
    { sub(/\r$/, "") }
    /^## / { flush(); inside = ($0 ~ /^## Open points/); next }
    !inside { next }
    /^[[:space:]]*>/ { next }
    /^- \[ \]/ { flush(); box = substr($0, 7); next }
    /^- \[[xX]\]/ { flush(); next }
    /^[[:space:]]+[^[:space:]]/ { if (box != "") box = box " " $0; next }
    { flush() }
    END { flush() }' "$1" 2>/dev/null
}

# The lines the check reads: each open box of the named carriers (fetched by state_haystack into the folder) and,
# where a pair file is given, the carrier line of each pair. As JSON lines {l, ts, repo, text}.
state_stale_lines() { # folder, pair file ('' for none), carriers...
  local dir="$1" pf="$2" c
  shift 2
  for c in "$@"; do
    state_open_boxes "$dir/$(state_key "$c").md" | jq -R -c --arg r "${c%%#*}" '{l: 0, ts: "-", repo: $r, text: .}'
  done
  [ -z "$pf" ] || [ ! -r "$pf" ] || jq -R -c '
    capture("^L(?<l>[0-9]+) [^:]+: .* => (?<c>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|further channel): (?<t>.*)$")
    | {l: (.l | tonumber), ts: "-", repo: (.c | if test("#") then sub("#[0-9]+$"; "") else "" end), text: .t}' < "$pf"
}

# The check: one resolve_snapshot for every judged reference, then a finding per line and reference whose stand the
# line contradicts, as a candidate {l, ts, art: "stale", text} on stdout. What the snapshot could not resolve is no
# box and no green: the note "stale check: <n> not checked (<why>)" goes to <folder>/stale.note.
state_stale() { # lines file, folder
  local lines="$1" dir="$2" refs
  : > "$dir/stale.note"
  jq -c "$state_stale_defs"'(.repo // "") as $r | . + {cand: (.text | judged($r))} | select(.cand | length > 0)' < "$lines" \
    > "$dir/stale.cand" 2>/dev/null || return 0
  [ -s "$dir/stale.cand" ] || return 0
  refs="$(resolve_refs_in "$(jq -r '.cand[]' < "$dir/stale.cand" | tr -d '\r')")"
  mapfile -t refs <<< "$refs"
  [ -n "${refs[0]:-}" ] || return 0
  resolve_snapshot "" "${refs[@]}" > "$dir/stale.snap" 2>/dev/null; resolve_cleanup
  jq -e 'type == "object"' "$dir/stale.snap" > /dev/null 2>&1 || echo '{}' > "$dir/stale.snap"
  # The references go as a file: as arguments, 5,000 of them pass the 32 KB of a Windows command line.
  printf '%s\n' "${refs[@]}" > "$dir/stale.refs"
  jq -n -c --slurpfile s "$dir/stale.snap" --rawfile k "$dir/stale.refs" "$state_stale_defs"'
    ($s[0] // {}) as $s | ($k | split("\n") | map(select(length > 0)) | map({key: ., value: true}) | from_entries) as $known
    | [inputs | . as $x | ($x.text | words) as $w | ($x.text | one | if length > 200 then .[0:197] + "..." else . end) as $line
       | $x.cand[] | select($known[.]) as $r | ($s[$r] // {error: "no answer"}) as $st
       | if $st.error != null then {err: $r, why: $st.error}
         elif $st.type == "Question" then
           select($st.status != "offen")
           | {l: $x.l, ts: $x.ts, art: "stale", text: "\($line) — \($r) ist \($st.status) (Stand \(([$st.createdAt] + [$st.messages[]?.at] | map(select(. != null)) | max) // "-"))"}
         elif (($w | w_open) and ($st.state == "CLOSED" or $st.state == "MERGED")) or (($w | w_done) and $st.state == "OPEN") then
           {l: $x.l, ts: $x.ts, art: "stale", text: "\($line) — \($r) ist \($st.state) (Stand \($st.updatedAt // "-"))"}
         else empty end] as $all
    | ($all | map(select(.err == null)) | unique_by(.text) | sort_by(.l) | .[]),
      ([$all[] | select(.err != null)] | unique_by(.err) | select(length > 0)
       | {note: "stale check: \(length) not checked (\(map(.why) | unique | .[0:2] | join("; ")))"})' \
    < "$dir/stale.cand" > "$dir/stale.raw" 2>/dev/null \
    || { printf 'stale check: %s not checked (the judging step failed)\n' "${#refs[@]}" > "$dir/stale.note"; return 0; }
  tr -d '\r' < "$dir/stale.raw" > "$dir/stale.out"
  jq -r 'select(has("note")) | .note' < "$dir/stale.out" > "$dir/stale.note"
  jq -c 'select(has("art"))' < "$dir/stale.out"
}

# The pairs a helper checks: only those whose carrier line no pattern judges (the state check has them).
state_pairs_plain() { # < pair file -> the plain pairs on stdout
  jq -R -r "$state_stale_defs"'. as $p
    | (capture(" => (?<c>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|further channel): (?<t>.*)$") // {c: "", t: .}) as $m
    | select(($m.t | judged($m.c | if test("#") then sub("#[0-9]+$"; "") else "" end)) | length == 0) | $p' | tr -d '\r'
}

# At least 8 pairs for the helper: where this run has fewer, the youngest carried sentences before the cursor fill up,
# promises and the maintainer's sentences first (up to 2000 transcript lines back).
state_pairs_fill() { # folder, transcript, start line, plain pairs of this run -> the pair file on stdout
  local dir="$1" t="$2" start="$3" now="$4" n from
  n="$(grep -c . "$now" 2>/dev/null)" || n=0
  cat "$now"
  [ "$n" -lt 8 ] && [ "$start" -gt 1 ] || return 0
  from=$((start > 2000 ? start - 2000 : 1))
  sed -n "${from},$((start - 1))p" "$t" | jq -R -n -c --argjson start "$from" "$state_extract_jq" 2>/dev/null \
    | jq -c 'select(has("art"))' > "$dir/back.jsonl" 2>/dev/null || return 0
  [ -s "$dir/back.jsonl" ] && state_match "$dir" "$dir/back.jsonl" > /dev/null 2>&1 || return 0
  state_pairs_plain < "$dir/pairs.txt" \
    | awk '{ m = ($2 ~ /^(promise|human|open-question):$/) ? 0 : 1; print m "\t" substr($1, 2) "\t" $0 }' \
    | sort -t "$(printf '\t')" -k1,1n -k2,2nr | cut -f3- | head -n $((8 - n))
}
