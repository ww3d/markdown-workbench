# shellcheck shell=bash
# shellcheck disable=SC2034 # state_* globals are the results session-state.sh reads
# Sourced by session-state.sh, never run: the core of SICHERN (save) - what a session said, was told and
# promised since its cursor, held against the texts of its carriers (ww3d/playbook#487, decision log
# docs/decisions/2026-11-12T0458Z-playbook-487-save-restore-decisions.md, decisions 2-4).
#
# Needs bash, jq and gh; no model call. Every function reports a read error on stderr and returns 2.
# shellcheck source=SCRIPTDIR/tempdir.sh
. "${BASH_SOURCE[0]%/*}/tempdir.sh"
hook_tmpdir || true # the temp folder is made known once, a subshell inherits it

# The normal form both sides of the comparison take: lower case, umlauts written out, every run of
# anything but a-z and 0-9 one blank. The haystack goes through sed and tr (fast on megabytes); a candidate
# through state_norm_jq, which must give the same result.
state_norm_sh() {
  LC_ALL=C sed -e 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/Ä/ae/g; s/Ö/oe/g; s/Ü/ue/g; s/ß/ss/g' \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' ' ' | LC_ALL=C tr -s ' '
}
# shellcheck disable=SC2016 # jq text, not shell
state_norm_jq='def norm: gsub("[äÄ]"; "ae") | gsub("[öÖ]"; "oe") | gsub("[üÜ]"; "ue") | gsub("ß"; "ss")
  | ascii_downcase | gsub("[^a-z0-9]+"; " ") | ltrimstr(" ") | rtrimstr(" ");'

# The transcript of the session: the given path, else <session>.jsonl under the projects folder.
state_transcript() { # given path, session -> global state_tx
  state_tx="$1"
  if [ -z "$state_tx" ]; then
    local f
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$2".jsonl; do
      [ -r "$f" ] && { state_tx="$f"; break; }
    done
  fi
  if [ -z "$state_tx" ] || [ ! -r "$state_tx" ]; then
    echo "transcript not readable: ${state_tx:-no <session>.jsonl under ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}" >&2; return 2
  fi
}

# Where save and restore start: after the line whose uuid the state file names, else after its line number, else
# at 1 - but never before the main thread's last compaction boundary once the restore file has no open box: what
# lies before it went through that restore. A boundary in the last 20 lines does not count, as it may be the
# compaction now running.
# After rc revive a session runs under a new id on a transcript forked from the old one: a "derived-from" line names
# the old id (via fork), and the forked lines keep their uuid. Without a cursor of its own the session takes over the
# old id's cursor (by uuid), check line and carriers, and its last list as its own first, keys and holder renamed; the
# old files stay (ww3d/playbook#727). The old id's last reported boundary comes along at the line of its uuid in the
# new transcript, unless the new id reported one itself (ww3d/playbook#750). Sets state_revived (the old id, empty when
# nothing was taken over).
state_revive() { # state dir, session, transcript -> 0 done or nothing to do, 2 not writable
  local dir="$1" s="$2" old v n d om u l nm rc lu ll=""
  state_revived=""
  if [ -s "$dir/$s.json" ] && jq -e '.cursor.uuid // .revivedFrom // empty' "$dir/$s.json" > /dev/null 2>&1; then return 0; fi
  old="$(head -n 40 "$3" 2>/dev/null | jq -r --arg s "$s" 'select(.type? == "derived-from") | .sessions[]?
    | select(.via == "fork" and .id != $s) | .id' 2>/dev/null | tr -d '\r' | tail -n 1)"
  [[ $old =~ ^[0-9a-fA-F-]{8,}$ ]] || return 0
  # An old id whose saves all ended with open boxes has a list and a mark but no state file.
  v="$(cutlist_latest "$old")"; om="$(state_unexamined_mark "$dir" "$old")"
  [ -s "$dir/$old.json" ] || [ -n "$v" ] || [ -s "$om" ] || return 0
  if [ -s "$dir/$old.json" ]; then cat "$dir/$old.json"; else echo '{}'; fi > "$dir/$s.old.tmp" || return 2
  lu="$(jq -r '.lastCutUuid // empty' "$dir/$s.old.tmp" 2>/dev/null | tr -d '\r')"
  [ -z "$lu" ] || ll="$(grep -n -m 1 -F "\"uuid\":\"$lu\"" "$3" | cut -d: -f1)"
  if [ -s "$dir/$s.json" ]; then cat "$dir/$s.json"; else echo '{}'; fi | jq -s --slurpfile o "$dir/$s.old.tmp" --arg t "$3" \
    --arg old "$old" --arg lu "$lu" --arg ll "$ll" '.[0] as $new | $new
      + ($o[0] | {cursor: (.cursor | if . != null then {transcript: $t, uuid} else null end), checked,
        checkedAt, checkLine, carriers} | with_entries(select(.value != null)))
      + (if $ll != "" and $new.lastCutUuid == null then {lastCutUuid: $lu, lastCutLine: ($ll | tonumber)} else {} end)
      + {revivedFrom: $old}' > "$dir/$s.json.tmp" \
    && mv -f "$dir/$s.json.tmp" "$dir/$s.json"; rc=$?
  rm -f "$dir/$s.old.tmp"; [ "$rc" -eq 0 ] || return 2
  # The mark comes along at the line its uuid stands at in the new transcript; without one the reading counts anew.
  u="$(jq -r '.uuid // empty' "$om" 2>/dev/null | tr -d '\r')"
  if [ -n "$u" ] && l="$(grep -n -m 1 -F "\"uuid\":\"$u\"" "$3" | cut -d: -f1)" && [ -n "$l" ]; then
    nm="$(state_unexamined_mark "$dir" "$s")"; mkdir -p "${nm%/*}" || return 2
    jq -n --arg t "$(ticks_canon "$3")" --argjson l "$l" --arg u "$u" '{transcript: $t, line: $l, uuid: $u}' > "$nm" || return 2
  fi
  if [ -n "$v" ] && [ -z "$(cutlist_latest "$s")" ]; then
    n="$(cutlist_n "${v%.md}.json")" || return 2
    d="$(cutlist_dir "$s")"; mkdir -p "$d" || return 2
    jq --arg o "$old:" --arg n "$s:" --arg s "$s" 'def rn: if type == "string" and startswith($o) then $n + .[($o | length):] else . end;
      .holder = $s | .boxes |= map(.key |= rn) | .closedKeys |= ((. // []) | map(rn)) | if .keys then .keys |= map(rn) else . end' \
      "${v%.md}.json" | ticks_write "$d/cut-$n.json" || return 2
    ticks_register "$d/cut-$n.md"
  fi
  state_revived="$old"
}
# The transcript of the id a revived session came from: the path its state file's cursor names, else the file beside
# the new transcript.
state_old_transcript() { # state folder, old id, new transcript -> path on stdout, exit 1 where none is readable
  local p
  p="$(jq -r '.cursor.transcript // empty' "$1/$2.json" 2>/dev/null | tr -d '\r')"
  [ -n "$p" ] && [ -r "$p" ] || p="${3%/*}/$2.jsonl"
  [ -r "$p" ] && printf '%s' "$p"
}
# The first main boundary the forked transcript carries, at its line in the old one.
state_fork_boundary() { # new transcript, old transcript -> "<old line> <uuid>" on stdout, exit 1 where there is none
  local bu ob
  bu="$(grep -F '"subtype":"compact_boundary"' "$1" 2>/dev/null | grep -v -F '"isSidechain":true' | head -n 1 \
    | grep -o '"uuid":"[^"]*"' | head -n 1)"
  [ -n "$bu" ] || return 1
  ob="$(grep -n -m 1 -F "$bu" "$2" | cut -d: -f1)"
  [[ $ob =~ ^[0-9]+$ ]] || return 1
  bu="${bu#'"uuid":"'}"; printf '%s %s' "$ob" "${bu%'"'}"
}
# A cursor the fork did not copy: it lies in the old transcript before the first boundary the new one carries.
state_forked_cursor() { # state file, new transcript, cursor uuid -> global state_forked "<old line> <old id>" or empty
  local old ot n ob
  state_forked=""
  old="$(jq -r '.revivedFrom // empty' "$1" 2>/dev/null | tr -d '\r')"
  [[ $old =~ ^[0-9a-fA-F-]{8,}$ ]] || return 0
  ot="$(state_old_transcript "${1%/*}" "$old" "$2")" || return 0
  ob="$(state_fork_boundary "$2" "$ot")" || return 0
  n="$(grep -n -m 1 -F "\"uuid\":\"$3\"" "$ot" | cut -d: -f1)"
  [[ $n =~ ^[0-9]+$ ]] && [ "$n" -lt "${ob%% *}" ] && state_forked="$n $old"
  return 0
}
# An old run that wrote on after the fork: its last entry is not in the new transcript and no save of the old id
# reached it - one candidate for the work list, which names the save over that transcript (ww3d/playbook#750).
state_fork_tail() { # state folder, state file, new transcript, work folder -> a candidate line on stdout or nothing
  local old ot last z u c
  old="$(jq -r '.revivedFrom // empty' "$2" 2>/dev/null | tr -d '\r')"
  [[ $old =~ ^[0-9a-fA-F-]{8,}$ ]] || return 0
  ot="$(state_old_transcript "$1" "$old" "$3")" || return 0
  last="$(grep -n -F '"uuid":"' "$ot" | grep -v -F '"isSidechain":true' | tail -n 1)"
  z="${last%%:*}"; u="$(grep -o '"uuid":"[^"]*"' <<< "$last" | head -n 1)"
  [ -n "$u" ] || return 0
  ! grep -q -F "$u" "$3" || return 0
  u="${u#'"uuid":"'}"; u="${u%'"'}"
  [ "$(jq -r '.cursor.uuid // empty' "$1/$old.json" 2>/dev/null | tr -d '\r')" != "$u" ] || return 0
  grep -o '"uuid":"[^"]*"' "$3" > "$4/fork-uuids.txt" || return 0
  c="$(grep -n -F -f "$4/fork-uuids.txt" "$ot" | tail -n 1 | cut -d: -f1)"
  [[ $c =~ ^[0-9]+$ ]] || c=0
  jq -nc --argjson z "$z" --arg u "$u" --arg t "Lauf $old hat nach dem Fork weitergeschrieben (alt L$((c + 1))-L$z): bash .claude/hooks/session-state.sh save --transcript \"$ot\" --session $old" \
    '{l: $z, ts: "-", art: "fork", text: $t, u: $u}' | tr -d '\r'
}

# The old id's restore did not run to its end - its marker stands at restore=pending, or its list still holds the box -
# and the new id's cursor is still the one it took over: no restore and no save of either id read what lies between
# that cursor and the copied boundary (ww3d/playbook#750).
state_old_unfinished() { # state folder, state file, marker folder -> global state_unfinished, the old id or empty
  local old rf lm
  state_unfinished=""
  old="$(jq -r '.revivedFrom // empty' "$2" 2>/dev/null | tr -d '\r')"
  [[ $old =~ ^[0-9a-fA-F-]{8,}$ ]] || return 0
  [ "$(jq -r '.cursor.uuid // empty' "$2" 2>/dev/null)" = "$(jq -r '.cursor.uuid // empty' "$1/$old.json" 2>/dev/null)" ] \
    || return 0
  rf="$1/$old-restore.md"; lm="$(cutlist_of "$rf")"
  if cut_pending "$3/$old-cut-pending" || grep -q '^- \[ \] .*Restore unvollstaendig' "${lm:-$rf}" 2>/dev/null; then
    state_unfinished="$old"
  fi
}
# Those old lines are not in the new transcript: one candidate for the work list names the save over the old one.
state_fork_gap() { # state folder, old id, new transcript -> a candidate line on stdout or nothing
  local ot ob u n=0
  ot="$(state_old_transcript "$1" "$2" "$3")" || return 0
  ob="$(state_fork_boundary "$3" "$ot")" || return 0
  u="$(jq -r '.cursor.uuid // empty' "$1/$2.json" 2>/dev/null | tr -d '\r')"
  [ -z "$u" ] || n="$(grep -n -m 1 -F "\"uuid\":\"$u\"" "$ot" | cut -d: -f1)"
  [ "${n:-0}" -lt "${ob%% *}" ] || return 0
  jq -nc --argjson z "${ob%% *}" --arg u "${ob#* }" \
    --arg t "Restore von Lauf $2 lief nicht zu Ende (alt L$((${n:-0} + 1))-L${ob%% *}): bash .claude/hooks/session-state.sh save --transcript \"$ot\" --session $2" \
    '{l: $z, ts: "-", art: "fork", text: $t, u: $u}' | tr -d '\r'
}

# hold (third argument, not empty): a compaction whose restore did not run to its end stands - what lies before its
# boundary went through no restore, so the start stays behind the cursor (ww3d/playbook#750).
state_cursor() { # state file, transcript [, hold] -> sets state_start, state_start_note, state_cursor_at (line of the
  # save's cursor, 0 without one) and state_cb (the main thread's last boundary before the last 20 lines, or 0)
  local uuid="" line="" hit total cb
  state_forked=""
  state_start=1; state_start_note="no cursor: from line 1"; state_cursor_at=0
  total="$(wc -l < "$2" | tr -d ' ')"
  cb="$(grep -n -F '"subtype":"compact_boundary"' "$2" 2>/dev/null | grep -v -F '"isSidechain":true' | cut -d: -f1 \
    | awk -v max=$((total - 20)) '$1 <= max { b = $1 } END { print b + 0 }')" || cb=0
  [[ $cb =~ ^[0-9]+$ ]] || cb=0
  state_cb=$cb
  if [ -r "$1" ]; then
    # One field a line: an empty uuid stays empty (tab-separated fields collapse in read).
    { IFS= read -r uuid; IFS= read -r line; } <<< "$(jq -r '(.cursor.uuid // ""), (.cursor.line // "" | tostring)' < "$1" 2>/dev/null)" || true
    # A jq for Windows ends its lines with CR LF.
    uuid="${uuid%$'\r'}"; line="${line%$'\r'}"
    if [[ $uuid =~ ^[0-9a-fA-F-]{8,}$ ]]; then
      hit="$(grep -n -m 1 -F "\"uuid\":\"$uuid\"" "$2" 2>/dev/null)" && hit="${hit%%:*}"
      [[ $hit =~ ^[0-9]+$ ]] && { state_start=$((hit + 1)); state_cursor_at=$hit; state_start_note="cursor: after L$hit (uuid $uuid)"; }
    fi
    if [ "$state_start" -eq 1 ]; then
      if [[ $line =~ ^[0-9]+$ ]] && [ "$line" -le "$total" ]; then
        state_start=$((line + 1)); state_cursor_at=$line; state_start_note="cursor: uuid not found, after L$line by line number"
      elif [ -n "$uuid$line" ]; then
        # A state file without a cursor (only the report's lastCut fields) is no cursor, not a lost one.
        state_start_note="cursor not found in the transcript: from line 1"
        [ -z "$uuid" ] || state_forked_cursor "$1" "$2" "$uuid"
        # Before the forked part is not lost: the old id read it (ww3d/playbook#750).
        [ -z "$state_forked" ] || state_start_note="cursor before the forked part (old L${state_forked% *}): from line 1"
      fi
    fi
  fi
  # A restore with an open box was not worked off (a compaction came before it was read): its start holds.
  # Its side list counts (a tick by hand is open); a restore file without one counts its "- [ ]" lines.
  local rf="${1%.json}-restore.md" open prev
  if [ -n "$(cutlist_of "$rf")" ]; then open="$(state_restore_open "$rf")"
  else
    open="$(awk '{ sub(/\r$/, "") } /^## / { s = ($0 == "## History without a carrier" || $0 == "## Carriers changed since checked"); next }
      s && /^- \[ \]/ { n++ } END { print n + 0 }' "$rf" 2>/dev/null)" || open=0
  fi
  if [[ $open =~ ^[1-9][0-9]*$ ]]; then
    prev="$(grep -m 1 '^Since the cursor: ' "$rf" 2>/dev/null)" || prev=""
    # Each start form written here: "after L<n>" begins one line on, "from L<n>," at that line.
    if [[ $prev =~ after\ (the\ compaction\ boundary\ )?L([0-9]+) ]]; then prev=$((BASH_REMATCH[2] + 1))
    elif [[ $prev =~ from\ L([0-9]+), ]]; then prev=$((BASH_REMATCH[1]))
    else prev=1; fi
    if [ "$prev" -lt "$state_start" ]; then
      state_start=$prev; state_start_note="${state_start_note%%: *}: from L$prev, where the last restore began ($open open boxes)"
    fi
  elif [ -z "${3:-}" ] && [ "$cb" -ge "$state_start" ]; then
    state_start=$((cb + 1)); state_start_note="${state_start_note%%: *}: after the compaction boundary L$cb"
    [ -z "$state_forked" ] || state_start_note="$state_start_note, covered by the restore of ${state_forked#* }"
  fi
}

# One jq pass over the transcript from the start line: the candidates as JSON lines, and last a line
# {"end":..} with the last line that carries a uuid. Side threads (isSidechain) are skipped.
# shellcheck disable=SC2016 # jq text, not shell
state_extract_jq='
def ts: (.timestamp // "") | if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}") then .[0:10] + "T" + .[11:13] + .[14:16] + "Z" else "-" end;
def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;
def one: gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");
# A slash command the maintainer typed is an input like any other: "/<name> <args>".
def slash: if test("<command-name>") then
    ([capture("<command-name>(?<n>[^<]*)</command-name>").n] | first // "") + " "
    + ([capture("<command-args>(?<a>[^<]*)</command-args>").a] | first // "") | one
  else . end;
def sentences: one | [splits("(?<=[.!?])\\s+")] | map(select(length > 0));
# The length of sentences without building them: one match pass instead of a replace and a split per text.
def sentence_count: if test("\\S") then 1 + ([match("[.!?]\\s+(?=\\S)"; "g")] | length) else 0 end;
def low: ascii_downcase | if test("[äöüß]") then gsub("ä"; "ae") | gsub("ö"; "oe") | gsub("ü"; "ue") | gsub("ß"; "ss") else . end;
# One test of the words any of the five tests below needs, before the five (a sentence none of them matches is the
# bulk of a transcript): a sentence outside it has no kind, as the chain ends in empty.
def kind_words: "\\?\\s*$|\\b(doch nicht|nehme [^.]*zurueck|zurueckgezogen|widerrufe?n?|stattdessen|statt dessen|nicht mehr)\\b|\\b(entschieden|entscheide|entscheidung|beschlossen|wir nehmen|ich nehme|bleibt bei|decided|going with)\\b|\\b(erledigt|fertig|gemergt|gemerged|gepusht|geschlossen|abgehakt|eingetragen|nachgetragen|behoben|gefixt|steht jetzt|ist drin|done|merged|pushed|fixed|closed)\\b|\\b(ich|wir) [a-z]+(e|en)\\b|\\bbescheid\\b|\\b(i|we)(.ll| will| am going to)\\b|\\b(als naechstes|danach|sobald|vorschlag|empfehlung|schlage vor|next step)\\b|^(mache|baue|melde|pruefe|trage|raeume|starte|schicke|schreibe|hole|setze) ";
def kind_of: low as $s
  | select($s | test(kind_words))
  | if test("\\?\\s*$") then "question"
    elif ($s | test("\\b(doch nicht|nehme [^.]*zurueck|zurueckgezogen|widerrufe?n?|stattdessen|statt dessen|nicht mehr)\\b")) then "revoke"
    elif ($s | test("\\b(entschieden|entscheide|entscheidung|beschlossen|wir nehmen|ich nehme|bleibt bei|decided|going with)\\b")) then "decision"
    elif ($s | test("\\b(erledigt|fertig|gemergt|gemerged|gepusht|geschlossen|abgehakt|eingetragen|nachgetragen|behoben|gefixt|steht jetzt|ist drin|done|merged|pushed|fixed|closed)\\b")) then "done"
    elif ($s | test("\\b(ich|wir) [a-z]+(e|en)\\b|\\bbescheid\\b|\\b(i|we)(.ll| will| am going to)\\b|\\b(als naechstes|danach|sobald|vorschlag|empfehlung|schlage vor|next step)\\b|^(mache|baue|melde|pruefe|trage|raeume|starte|schicke|schreibe|hole|setze) ")) then "promise"
    else empty end;
# An own sentence that reports a done action - pushed, sent to a session, commented at an issue or PR - as
# {claim: ..}; state_claims holds it against the own tool calls of its turn (ww3d/playbook#621). Quoted text,
# questions, negations, future and conditions, and sentences about a third party (an auxiliary without
# "ich/wir/I/we") and received ones ("mir", "bekommen") are no claim, so a miss stays silent rather than raising a
# box on a true sentence. A session named after "von/from" is the source, not a receiver.
def unquote: ([39] | implode) as $a | gsub("(^|\\s)" + $a + "[^" + $a + "]*" + $a + "(?=[\\s.,;:!?)]|$)"; " ") | gsub("\"[^\"]*\"|„[^“”]*[“”]|“[^”]*”|`[^`]*`"; " ");
# The words a claim category needs (below), tested before the unquoting: a sentence without one is no claim.
def claim_words: "gepusht|pushed|kommentiert|gepostet|commented|posted|geschickt|gesendet|zugestellt|weitergeleitet|weitergegeben|sent|delivered|forwarded|bekam|bekommen|erhielt|erhalten|received|got";
# The same words for a whole text block, with the anchors of the sentence tests dropped and each blank run a \\s+: a
# block without one has no sentence with a kind or a claim, so only its text ends the open questions (.openq).
def block_words: "\\?|doch\\s+nicht|nehme\\s[^.]*zurueck|zurueckgezogen|widerruf|stattdessen|statt\\s+dessen|nicht\\s+mehr|entscheide|entscheidung|entschieden|beschlossen|bleibt\\s+bei|decided|going\\s+with|erledigt|fertig|gemergt|geschlossen|abgehakt|eingetragen|nachgetragen|behoben|gefixt|steht\\s+jetzt|ist\\s+drin|done|merged|fixed|closed|\\b(ich|wir)\\s+[a-z]+(e|en)\\b|bescheid|\\b(i|we)(.ll|\\s+ll|\\s+will|\\s+am\\s+going\\s+to)\\b|als\\s+naechstes|danach|sobald|vorschlag|empfehlung|schlage\\s+vor|next\\s+step|(mache|baue|melde|pruefe|trage|raeume|starte|schicke|schreibe|hole|setze)\\s|" + claim_words;
def claim_of($n; $t; $turn; $ins): select(ascii_downcase | test(claim_words)) | . as $orig | (unquote | one) as $u | ($u | low) as $s
  | select(($u | test("\\?\\s*$")) | not)
  | select(($s | test("\\b(nicht|kein|keine|keinen|keiner|nichts|nie|not|never|nothing|no)\\b")) | not)
  | select(($s | test("\\b(wird|werde|werden|wuerde|wuerden|soll|sollen|sollte|muss|muessen|kann|koennen|will|wollen|sobald|wenn|falls|nachdem|bevor|once|if|when|after|before|should|would|must|shall|going to)\\b")) | not)
  | select(($s | test("\\b(ich|wir|i|we)\\b")) or ($s | test("\\b(hat|haben|ist|sind|has|have|is|are|was|were|wurde|wurden)\\b") | not))
  | ($s | test("\\b(alle|allen|jede[mnrs]?|everyone|everybody|all)\\b")) as $all
  | (if ($s | test("\\b(gepusht|pushed)\\b")) and ($s | test("pushed back") | not) then "push"
     elif ($s | test("\\b(kommentiert|gepostet|commented|posted)\\b")) and ($s | test("#[0-9]+|\\b(issue|issues|pr|prs|pull request|github)\\b")) then "comment"
     elif (($s | test("\\b(geschickt|gesendet|zugestellt|weitergeleitet|weitergegeben|sent|delivered|forwarded)\\b"))
           or ($all and ($s | test("\\b(bekam|bekamen|bekommen|erhielt|erhielten|erhalten|received|got)\\b"))
               and ($s | test("\\b(ich|wir|i|we)\\b") | not)))
          and (($s | test("\\b(mir|uns|me|us)\\b"))
               or (($all | not) and ($s | test("\\b(bekam|bekamen|bekommen|erhielt|erhielten|erhalten|received|got)\\b"))) | not)
       then "send"
     else empty end) as $cat
  | {claim: {l: $n, ts: $t, turn: $turn, ins: $ins, cat: $cat, all: $all, text: ($orig | one),
      names: ([$s | gsub("\\b(von|from) [a-z][a-z0-9]*(?:-[a-z0-9]+)*-[0-9]+\\b"; " ")
               | scan("\\b[a-z][a-z0-9]*(?:-[a-z0-9]+)*-[0-9]+\\b")] | unique),
      refs: ([$s | scan("#([0-9]+)") | .[0]] | unique)}};
# An own sentence about the save itself, said in the save window (from the save call to the next input of the maintainer
# or another session): a word of the save list, no reference, no address - no candidate (ww3d/playbook#672, decision 2).
def save_meta: low as $s
  | ($s | test("\\b(kasten|kaesten|save|sicher[a-z]*|sicherung|skript|arbeitsliste|abhak[a-z]*|abgehakt|hand-back|check-zeile|gesichert|verdicht[a-z]*)\\b"))
    and ($s | test("#[0-9]+|\\bq[0-9]+\\b|\\b[a-z][a-z0-9]*(?:-[a-z0-9]+)*-[0-9]+\\b") | not)
    and ($s | test("\\b(dir|dich|euch|ihnen|du|you)\\b") | not);
def save_call: .type == "tool_use" and (.name == "Bash" or .name == "PowerShell")
  and ((.input.command? // "") | strings | test("session-state\\.sh[\"\\x27]?\\s+save\\b"));
def sender($c): (.origin.name // "") as $n | (.origin.from // "") as $f
  | if $n != "" then $n
    elif $f != "" and $f != "unknown" and ($f | test("^uds:") | not) then $f
    else ($c | capture("from-name=\"(?<n>[^\"]+)\"").n
      // capture("\\[rc · from (?<n>[^ ·\\]]+)").n
      // capture("\\[rc-delivery: (?<n>[A-Za-z0-9_]+)").n
      // ($c | one | split(" ") | map(select(length > 0)) | .[0] // "-" | rtrimstr(":"))) end;
# A message or input that arrives while a turn runs stands as an attachment "queued_command": read it as the
# user line it is. Fields read below are objects or null from here on: a "?" that yields nothing would empty
# the whole reduce step (a failed tool call carries toolUseResult as a string).
def obj: if type == "object" then . else null end;
def origin_obj: if type == "string" then (fromjson? // null) else . end | obj;
def as_user: (.attachment | obj) as $a
  | if .type == "attachment" and ($a.type // null) == "queued_command" then
      {type: "user", uuid, timestamp, isSidechain, isMeta: $a.isMeta,
       origin: ($a.origin | origin_obj), message: {content: $a.prompt}}
    else .origin |= origin_obj | .toolUseResult |= obj end;
# The feedback Claude Code writes for a Stop hook that blocked quotes that hook (box titles, delivery marks): no
# message, no input (ww3d/playbook#734).
def stop_feedback($c): .isMeta == true and ($c | startswith("Stop hook feedback:"));
def is_message($c): (.isCompactSummary != true) and (stop_feedback($c) | not) and ($c | test("^This session is being continued") | not) and (.origin.kind == "peer" or ($c | test("^\\[rc · from |\\[rc-delivery: |^<cross-session-message|^Another Claude session sent a message")));
def human_text($c): (.isMeta != true) and ($c | length > 0)
  and ($c | test("^\\s*<local-command-|^\\s*<command-message>|^\\s*<task-notification>|^\\s*<system-reminder>|^Caveat:|^This session is being continued") | not)
  and (.isCompactSummary != true);
# The answer to the last input stays in .ans until the next input or the end: written into .out at every text, the
# growing list would be copied each time. Unexamined sentences after line $ARGS.named.from count apart (unexaminedNew).
def put_answer: if .lasth != null and .ans != null then .out[.lasth].answer = .ans else . end | .ans = null;
($ARGS.named.from // 0) as $ufrom
| reduce (inputs | (fromjson? // null) | if type == "object" then as_user else . end) as $j (
  {n: ($start - 1), out: [], tools: {}, lastq: null, openq: [], end: null, turn: 0, ins: [], claims: [], win: false,
   si: 0, lasth: null, ans: null, unexamined: 0, unexaminedNew: 0};
  .n += 1
  # A line of a shape no branch expects is skipped, never the end of the run: the step falls back to the
  # state before it.
  | . as $before
  | first((try (if $j == null or ($j | type) != "object" or $j.isSidechain == true then .
    else
      .n as $n | ($j | ts) as $t | ($j.uuid // null) as $u | .si = 0
      | (if ($j.uuid // "") != "" then .end = {line: $n, uuid: $j.uuid} else . end)
      | if $j.type == "assistant" then
          reduce (($j.message.content // []) | if type == "array" then .[] | objects else empty end) as $b (.;
            # The last own text before the next input of the maintainer is the answer to it (ww3d/playbook#727).
            (if $b.type == "text" and .lasth != null then .ans = $b.text else . end)
            | if $b.type == "tool_use" and (["Agent", "Task", "Workflow"] | index($b.name)) then .tools[$b.id] = true
            elif ($b | save_call) then .win = true
            elif $b.type == "text" and (($b.text | low | test(block_words)) | not) then
              ($b.text | sentence_count) as $k | .openq = [] | .unexamined += $k | .si += $k
              | if $n > $ufrom then .unexaminedNew += $k else . end
            elif $b.type == "text" then
              # Each sentence keeps its number in the entry, the key of its box with the entry uuid.
              .win as $win | ($b.text | sentences) as $all | .si as $si
              | [$all | to_entries[] | select((.value | $win and save_meta) | not)] as $se | [$se[].value] as $ss
              | .openq = [] | .si += ($all | length)
              | .lastq as $prev | .lastq = (([$ss[] | select(test("\\?\\s*$"))] | last) // $prev)
              | reduce ($se[] | {i: ($si + .key), s: .value, k: ([.value | kind_of] | first)}) as $c (.;
                  if $c.k == null then .unexamined += 1 | if $n > $ufrom then .unexaminedNew += 1 else . end
                  else .out += [{l: $n, ts: $t, art: $c.k, text: $c.s, u: $u, s: $c.i}] end)
              | .turn as $turn | .ins as $ins | .claims += [$ss[] | claim_of($n; $t; $turn; $ins)]
            else . end)
        elif $j.type == "user" then
          ($j.message.content // "") as $raw_c | ($raw_c | flat | slash) as $c
          | if ($raw_c | type) == "array" and ($raw_c | any(.type? == "tool_result")) then
              reduce ($raw_c[] | select(.type? == "tool_result")) as $r (.;
                if .tools[$r.tool_use_id] and ($r.is_error != true) and ($j.toolUseResult.isAsync != true) then
                  .out += [{l: $n, ts: $t, art: "helper", text: ($r.content | flat | one), full: ($r.content | flat), u: $u, s: $r.tool_use_id}]
                else . end)
            elif $j.origin.kind == "task-notification" or ($c | test("^<task-notification>")) then
              if ($c | test("<summary>Background command")) then .
              else .out += [{l: $n, ts: $t, art: "helper", text: ($c | one), full: $c, u: $u}] end
            elif ($j | is_message($c)) then
              ($j | sender($c)) as $from | ($j.origin.body // $c) as $body
              | .out += [{l: $n, ts: $t, art: "message", text: ($from + ": " + ($body | one)), from: $from, full: $body, u: $u}]
              | .ins += [{l: $n, from: ($from | ascii_downcase)}] | .win = false
            elif ($j | human_text($c)) then
              ($c | one) as $h
              | (if .lastq then $h + " (auf: " + .lastq + ")" else $h end) as $txt
              | .lastq = null
              | (if ($h | test("\\?")) then .openq += [.out | length] else . end)
              | put_answer | .lasth = (.out | length) | .out += [{l: $n, ts: $t, art: "human", text: $txt, full: $c, u: $u}]
              | .turn = $n | .ins = [] | .win = false
            else . end
        else . end
    end) catch $before), $before))
| put_answer | . as $s
| reduce $s.openq[] as $i ($s; .out[$i].art = "open-question")
| (.out[] | select(.text != "")), .claims[], {end: .end, unexamined: .unexamined, unexaminedNew: .unexaminedNew, from: $ufrom}
'

state_extract() { # transcript, start line [, line after which unexamined sentences are new] -> candidates as JSON lines
  tail -n "+$2" "$1" | jq -R -n -c --argjson start "$2" --argjson from "${3:-0}" "$state_extract_jq"
}
state_extract_timed() { # seconds, transcript, output file [, line after which unexamined sentences are new]
  # shellcheck disable=SC2016 # $1 to $4 belong to the inner bash
  timeout "$1" bash -c 'tail -n "+$2" "$1" | jq -R -n -c --argjson start "$2" --argjson from "$4" "$3"' _ "$2" "$state_start" \
    "$state_extract_jq" "${4:-0}" > "$3" 2>/dev/null
}
# The read of a start hook: from state_start within PLAYBOOK_RESTORE_READ_SECS; a read that outlasts it (a very large
# transcript without a save, ww3d/playbook#692) takes the last PLAYBOOK_RESTORE_TAIL_BYTES, moves state_start there and
# says so in state_start_note. Exit 1 where nothing was read, the reason in state_read_note. state_read_full and
# state_read_tail give the seconds of the two reads (the restore hook hands in what its budget leaves), else 30 and 20.
# state_read_cut is set where the whole read ran out of time.
state_extract_bounded() { # transcript, output file [, line after which unexamined sentences are new]
  local total win full="${PLAYBOOK_RESTORE_READ_SECS:-${state_read_full:-30}}" tail_s="${state_read_tail:-20}"
  state_read_note=""; state_read_cut=""
  state_extract_timed "$full" "$1" "$2" "${3:-0}" && return 0
  state_read_cut=1
  total="$(wc -l < "$1" | tr -d ' ')"
  win="$(tail -c "${PLAYBOOK_RESTORE_TAIL_BYTES:-6000000}" "$1" | wc -l | tr -d ' ')"
  if [[ $total =~ ^[0-9]+$ && $win =~ ^[0-9]+$ ]] && [ $((total - win + 1)) -gt "$state_start" ]; then
    state_start=$((total - win + 1))
    state_start_note="${state_start_note%%: *}: the transcript is too large to read in time, the history before L$state_start is not read"
    state_extract_timed "$tail_s" "$1" "$2" "${3:-0}" && return 0
    state_read_note="jq could not read the last part of the transcript within $tail_s s"
  else state_read_note="jq could not read the transcript within $full s"; fi
  return 1
}

# The unexamined sentences of this reading that no report counted yet: a save that ends with open boxes and every
# compaction read the stretch behind the cursor again, and the report counts each sentence once (ww3d/playbook#727).
# The reading takes the line from state_unexamined_from; the end of the reading is noted in a mark file beside the
# cut lists, so a save that ends with open boxes writes no state file.
state_unexamined_mark() { printf '%s/ticks/%s/unexamined.json' "$1" "$2"; } # state folder, session -> mark file
state_unexamined_from() { # mark file, transcript -> line on stdout, 0 for another transcript or no mark
  jq -r --arg t "$(ticks_canon "$2")" 'if type == "object" and (.transcript // "") == $t
    then .line // 0 else 0 end' "$1" 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' || echo 0
}
# The mark carries the uuid of its line too: after rc revive the new transcript holds the same entries at other lines.
state_unexamined_new() { # candidates file, mark file, transcript -> count on stdout
  local t r n l u; t="$(ticks_canon "$3")"
  r="$(jq -rs '([.[] | select(has("end"))][0] // {}) as $e
    | [$e.unexaminedNew // $e.unexamined // 0, ([$e.end.line // 0, $e.from // 0] | max),
       (if ($e.end.line // 0) >= ($e.from // 0) then $e.end.uuid // "" else "" end)] | map(tostring) | join(" ")' \
    < "$1" | tr -d '\r')" \
    || { echo 0; return 2; }
  read -r n l u <<< "$r"
  # A reading that ended before the mark keeps the mark's own uuid.
  [ -n "$u" ] || u="$(jq -r --arg t "$t" 'select(.transcript == $t) | .uuid // empty' "$2" 2>/dev/null | tr -d '\r')"
  mkdir -p "${2%/*}" && jq -n --arg t "$t" --argjson l "$l" --arg u "$u" '{transcript: $t, line: $l}
    + if $u != "" then {uuid: $u} else {} end' > "$2.tmp" && mv -f "$2.tmp" "$2"
  echo "$n"
}

# The haystack: the bodies of the named carriers, of every issue or PR they link (one level), and the text
# of PLAYBOOK_CARRIER_TEXT_CMD. Bodies are fetched in parallel, each once.
state_key() { # owner/repo#N -> owner_repo_N
  local k="${1//\//_}"; printf '%s' "${k/\#/_}"
}
# One body per carrier: a conditional request (If-None-Match with the ETag of the last answer); GitHub does not
# count a 304 against the primary rate limit, see
# https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests
# and ww3d/playbook#701. The cache holds one file per carrier, <key>.cache: the ETag as its first line, the body after
# it, shared by all sessions of the user and replaced by a single rename, so ETag and body never part.
state_cache() { printf '%s' "${STATE_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-${hook_tmp:-/dev/null}}/.cache}/playbook-state}"; }
state_body() { # owner/repo#N, folder -> the body in <folder>/<key>.md, an error text in <folder>/<key>.err
  local k c etag="" rc=0 raw h
  k="$(state_key "$1")"; c="$(state_cache)"; raw="$2/$k.raw"
  mkdir -p "$c" 2>/dev/null
  [ -s "$c/$k.cache" ] && etag="$(head -n 1 "$c/$k.cache" | tr -d '\r')"
  timeout "${STATE_GH_TIMEOUT:-30}" gh api -i ${etag:+-H "If-None-Match: $etag"} "repos/${1%%#*}/issues/${1##*#}" > "$raw" 2>"$2/$k.err" || rc=$?
  h="$(head -n 1 "$raw" 2>/dev/null | tr -d '\r')"
  if [[ $h == HTTP/*" 304"* ]]; then
    tail -n +2 "$c/$k.cache" > "$2/$k.md" && rm -f "$2/$k.err" "$raw"; return 0
  elif [ "$rc" -eq 0 ] && [[ $h == HTTP/*" 200"* ]]; then
    sed '1,/^\r\?$/d' "$raw" | jq -r '.body // ""' > "$2/$k.md" 2>"$2/$k.err" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
      rm -f "$2/$k.err"
      etag="$(sed -n '1,/^\r\?$/{s/^[Ee][Tt][Aa][Gg]: *//p}' "$raw" | tr -d '\r' | head -n 1)"
      if [ -n "$etag" ]; then
        { { printf '%s\n' "$etag"; cat "$2/$k.md"; } > "$c/$k.cache.$$" \
          && mv -f "$c/$k.cache.$$" "$c/$k.cache"; } 2>/dev/null || rm -f "$c/$k.cache.$$"
      fi
      rm -f "$raw"; return 0
    fi
  fi
  rm -f "$raw"
  if [ "$rc" -eq 124 ]; then
    echo "gh timed out after ${STATE_GH_TIMEOUT:-30} s" > "$2/$k.err"; rm -f "$2/$k.md"
  else
    [ -s "$2/$k.err" ] || echo "gh exit $rc" > "$2/$k.err"
    rm -f "$2/$k.md"
  fi
}
# Eight at a time (ww3d/playbook docs/provenance.md: all at once was several times slower).
state_fetch() { # folder < owner/repo#N per line
  export -f state_body state_key state_cache
  # shellcheck disable=SC2016 # $1 and $2 belong to the inner bash
  [ "$#" -eq 1 ] && xargs -r -P 8 -I{} bash -c 'state_body "$1" "$2"' _ {} "$1"
}
state_refs() { # default repo < body -> owner/repo#N per line
  grep -oE 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|(^|[^A-Za-z0-9_/&])#[0-9]+' \
    | sed -E -e 's#github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+)#\1/\2\#\4#' -e "s@^[^A-Za-z0-9_.#-]?#([0-9]+)\$@$1#\\1@" -e 's@^[^A-Za-z0-9_.-]@@'
}
# Globals: state_hay_note, state_bodies (the named carriers). <folder>/refs.tsv maps each fetched file to its
# carrier ("<key><TAB>owner/repo#N", "channel<TAB>further channel").
state_haystack() { # folder, carriers... -> <folder>/<key>.md per text, <folder>/refs.tsv
  local dir="$1" c f; shift
  state_hay_note=""; state_bodies=()
  [ "$#" -eq 0 ] || printf '%s\n' "$@" | state_fetch "$dir"
  : > "$dir/refs.tsv"
  for c in "$@"; do
    f="$dir/$(state_key "$c")"
    [ -e "$f.md" ] || { echo "carrier not readable: $c ($(head -c 200 "$f.err" 2>/dev/null))" >&2; return 2; }
    state_bodies+=("$f.md"); printf '%s\t%s\n' "$(state_key "$c")" "$c" >> "$dir/refs.tsv"
  done
  for c in "$@"; do state_refs "${c%%#*}" < "$dir/$(state_key "$c").md"; done | sort -u \
    | while IFS= read -r c; do
        [[ $c =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+$ ]] && [ ! -e "$dir/$(state_key "$c").md" ] && printf '%s\n' "$c"
      done > "$dir/linked.txt"
  state_fetch "$dir" < "$dir/linked.txt"
  while IFS= read -r c; do printf '%s\t%s\n' "$(state_key "$c")" "$c"; done < "$dir/linked.txt" >> "$dir/refs.tsv"
  for f in "$dir"/*.err; do
    [ -e "$f" ] && state_hay_note="${state_hay_note}linked not read: $(basename "${f%.err}") ($(head -c 120 "$f"))"$'\n'
  done
  if [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then
    local rc=0
    timeout 60 bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ text > "$dir/channel.md" 2>"$dir/channel.err" || rc=$?
    if [ "$rc" -eq 124 ]; then
      state_hay_note="${state_hay_note}further channel: not checked (PLAYBOOK_CARRIER_TEXT_CMD timed out after 60 s)"$'\n'
      : > "$dir/channel.md"
    elif [ "$rc" -ne 0 ]; then
      state_hay_note="${state_hay_note}further channel: not checked (PLAYBOOK_CARRIER_TEXT_CMD failed: $(head -c 200 "$dir/channel.err"))"$'\n'
      : > "$dir/channel.md"
    fi
    printf 'channel\tfurther channel\n' >> "$dir/refs.tsv"
  else
    state_hay_note="${state_hay_note}further channel: not checked"$'\n'
  fi
}

# The candidates no carrier holds: up to six words as a whole, longer ones by at least half of their 6-word
# shingles (across line ends, as one stream). jq gives each candidate its normal form, awk holds the haystack's
# shingles in one hash (a jq object instead took far longer, ww3d/playbook docs/provenance.md). A carried
# candidate becomes a pair with the carrier line that holds it, or the most of its shingles.
# shellcheck disable=SC2016 # jq text, not shell
state_match_jq="$state_norm_jq"'select(has("art")) | .text | norm'
# shellcheck disable=SC2016 # awk text, not shell
state_match_find='
  function at(p,   lo, hi, mid) { lo = 1; hi = nl; while (lo < hi) { mid = int((lo + hi + 1) / 2); if (start[mid] <= p) lo = mid; else hi = mid - 1 }; return lo }
  BEGIN { nk = split(keys, key, " ") }
  FILENAME == ARGV[1] { sub(/\r$/, ""); hay = $0; next }
  FILENAME == ARGV[2] { sub(/\r$/, "")
    if ($0 ~ /^ ?qqsrcqq [0-9]+ ?$/) { split($0, m, " "); src = key[m[2]]; ln = 0 } else ln++
    nl++; start[nl] = pos + 2; pos += length($0) + 1; loc[nl] = src SUBSEP ln
    n = split($0, w, " ")
    for (i = 1; i <= n; i++) { r[rn % 6] = w[i]; rn++
      if (rn >= 6) { s = r[(rn - 6) % 6] " " r[(rn - 5) % 6] " " r[(rn - 4) % 6] " " r[(rn - 3) % 6] " " r[(rn - 2) % 6] " " r[(rn - 1) % 6]
                     if (!(s in set)) set[s] = loc[nl] } }
    next }
  { sub(/\r$/, ""); k = split($0, c, " "); if (k == 0) next
    if (k <= 6) { p = index(hay, " " $0 " "); if (p == 0) print "O\t" FNR; else print "P\t" FNR "\t" loc[at(p + 1)]; next }
    hit = 0; best = ""; top = 0; split("", cnt)
    for (i = 1; i + 5 <= k; i++) { s = c[i] " " c[i+1] " " c[i+2] " " c[i+3] " " c[i+4] " " c[i+5]
      if (s in set) { hit++; if (++cnt[set[s]] > top) { top = cnt[set[s]]; best = set[s] } } }
    if (hit * 2 < k - 5) print "O\t" FNR; else print "P\t" FNR "\t" best }'
state_match() { # folder, candidates file -> the unmatched candidates on stdout; the pairs in <folder>/pairs.txt
  local dir="$1" f i=0 keys=""
  jq -r "$state_match_jq" < "$2" > "$2.norm" || return 2
  # Every text once, each behind a marker line that survives the normal form, so a line maps back to its carrier.
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    i=$((i + 1)); keys="$keys $(basename "${f%.md}")"
    printf 'qqsrcqq %s\n' "$i"; cat "$f"; printf '\n'
  done > "$dir/all.raw"
  LC_ALL=C sed -e 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/Ä/ae/g; s/Ö/oe/g; s/Ü/ue/g; s/ß/ss/g' "$dir/all.raw" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9\n' ' ' | LC_ALL=C tr -s ' ' > "$dir/all.lines" || return 2
  { printf ' '; LC_ALL=C tr '\n' ' ' < "$dir/all.lines"; printf ' \n'; } > "$dir/hay.txt"
  awk -F '\t' -v keys="$keys" "$state_match_find" "$dir/hay.txt" "$dir/all.lines" "$2.norm" > "$2.hits" || return 2
  jq -c 'select(has("art"))' < "$2" | awk -F '\t' '{ sub(/\r$/, "") } NR == FNR { if ($1 == "O") keep[$2] = 1; next } FNR in keep' "$2.hits" -
  jq -r 'select(has("art")) | "L\(.l) \(.art): \(.text | gsub("[\t\r\n]"; " ") | if length > 400 then .[0:397] + "..." else . end)"' \
    < "$2" > "$2.boxes" || return 2
  awk -F '\t' -v keys="$keys" '
    function cut(s) { gsub(/[\t\r]/, " ", s); sub(/^[ ]+/, "", s); return length(s) > 400 ? substr(s, 1, 397) "..." : s }
    BEGIN { nk = split(keys, key, " ") }
    FILENAME == ARGV[1] { sub(/\r$/, ""); ref[$1] = $2; next }
    FILENAME == ARGV[2] { sub(/\r$/, ""); if ($1 == "P") { pair[$2] = $3; want[$3] = 1 }; next }
    FILENAME == ARGV[3] { if ($0 ~ /^qqsrcqq [0-9]+$/) { split($0, m, " "); src = key[m[2]]; ln = 0; next }
                          ln++; if ((src SUBSEP ln) in want) text[src SUBSEP ln] = $0; next }
    (FNR in pair) { sub(/\r$/, ""); split(pair[FNR], a, SUBSEP)
                    print $0 " => " (a[1] in ref ? ref[a[1]] : a[1]) ": " cut(text[pair[FNR]]) }' \
    "$dir/refs.tsv" "$2.hits" "$dir/all.raw" "$2.boxes" > "$dir/pairs.txt" || return 2
}

# The carried boxes a carrier of this cut holds (ww3d/playbook#727, question 1921 a): the same match as state_match,
# against the haystack it left in the folder. Candidates {key, art, text} -> {key: carrier} on stdout.
state_match_held() { # folder, candidates file
  local dir="$1" f keys=""
  if ! { [ -s "$2" ] && [ -s "$dir/hay.txt" ]; }; then echo '{}'; return 0; fi
  for f in "$dir"/*.md; do [ -e "$f" ] && keys="$keys $(basename "${f%.md}")"; done
  jq -r "$state_match_jq" < "$2" > "$2.norm" || return 2
  awk -F '\t' -v keys="$keys" "$state_match_find" "$dir/hay.txt" "$dir/all.lines" "$2.norm" > "$2.hits" || return 2
  awk -F '\t' -v keys="$keys" 'BEGIN { nk = split(keys, key, " ") }
    FILENAME == ARGV[1] { sub(/\r$/, ""); ref[$1] = $2; next }
    $1 == "P" { sub(/\r$/, ""); split($3, a, SUBSEP); print $2 "\t" (a[1] in ref ? ref[a[1]] : a[1]) }' \
    "$dir/refs.tsv" "$2.hits" > "$2.held" || return 2
  jq -s -R --slurpfile c "$2" '[split("\n")[] | select(length > 0) | split("\t") | {key: $c[(.[0] | tonumber) - 1].key, value: .[1]}]
    | from_entries' < "$2.held"
}

# A forge write call: gh with a writing method or subcommand, or a GitHub MCP tool that is no read.
# shellcheck disable=SC2016 # jq text, not shell
state_gh_write_jq='def gh_write: (.input | tostring) as $s
  | (((.name == "Bash" or .name == "PowerShell") and ($s | test("\\bgh\\b"))
      and ($s | test("-X ?(POST|PATCH|PUT|DELETE)|--method[ =](POST|PATCH|PUT|DELETE)| -[fF] |--field|--raw-field|--input|gh (issue|pr) (comment|edit|close|reopen|create|ready|review|merge|lock)")))
     or ((.name | test("github"; "i")) and (.name | test("get|list|search|read"; "i") | not)));
def numbered: (capture("^(?<n>[0-9]+):(?<j>.*)$") // null) as $m | select($m != null)
  | ($m.j | fromjson? // null) | objects | select(.isSidechain != true) | {l: ($m.n | tonumber), j: .};'
# The own tool calls a claim can rest on, from the whole transcript: git push, rc send/report/ask, a forge write.
# shellcheck disable=SC2016 # jq text, not shell
state_uses_jq="$state_gh_write_jq"'numbered | select(.j.type == "assistant") | .l as $l
  | .j.message.content[]? | objects | select(.type == "tool_use") | (.input | tostring) as $s
  | {id, l: $l, write: gh_write, s: $s,
     push: ((((.name == "Bash" or .name == "PowerShell") and ($s | test("\\bgit\\b[^\\n;&|]*\\bpush\\b")))) or (.name | test("push_files|create_or_update_file"))),
     rc: ((.name == "Bash" or .name == "PowerShell") and ($s | test("\\brc(\\.exe)?\\s+(send|report|ask)\\b")))}
  | select(.push or .rc or .write)'
# shellcheck disable=SC2016 # jq text, not shell
state_results_jq="$state_gh_write_jq"'def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;
  numbered | select(.j.type == "user") | .l as $l | .j.message.content | arrays | .[] | objects | select(.type == "tool_result")
  | (.content | flat) as $x
  | {id: .tool_use_id, l: $l, text: $x, ok: ((.is_error != true) and ($x | test("\\[rejected\\]|failed to push|^(fatal|error):"; "m") | not))}'
# shellcheck disable=SC2016 # jq text, not shell
state_claims_jq='($r | map({key: .id, value: .}) | from_entries) as $res
| $c[] as $k
| (reduce ($k.ins[] | select(.l < $k.l)) as $i ($k.turn; . as $w
    | if ($i.from | length) > 0
         and ([$u[] | select(.rc and .l > $w and .l < $i.l) | .s | ascii_downcase] | join(" ")
              | test("(^|[^a-z0-9-])" + ($i.from | gsub("[^a-z0-9-]"; "")) + "([^a-z0-9-]|$)"))
      then $w else $i.l end)) as $w
| [$u[] | select(.l > $w and .l < $k.l) | . as $x
   | if .exec then $x else $res[$x.id] | select(. != null and .ok and .l < $k.l) | $x + {text: .text} end] as $ev
| (if $k.cat == "push" then (if any($ev[]; .push) then empty else "no successful git push in this turn" end)
   elif $k.cat == "comment" then
     [$ev[] | select(.write)] as $w
     | if ($w | length) == 0 then "no forge write call in this turn"
       elif ($k.refs | length) > 0 and ([$k.refs[] as $n | $w[] | select(.s | test("(^|[^0-9])" + $n + "([^0-9]|$)"))] | length) == 0
         then "no forge write call naming #" + ($k.refs | join(", #")) + " in this turn"
       else empty end
   else
     ([$ev[] | select(.rc) | if .exec then .to else .text | scan("(?:dlv|msg)_[0-9A-Za-z]{10,}[ \\t]+([A-Za-z0-9_.-]+)") | .[0] end
       | ascii_downcase] | unique) as $to
     | ([$u[] | select(.rc and .l < $k.l) | .s | ascii_downcase] | join(" ")) as $addr
     | [$k.names[] | select(. as $n | $addr | test("(^|[^a-z0-9-])" + $n + "([^a-z0-9-]|$)"))] as $named
     | if ($named | length) > 0 then
         [$named[] | select(. as $n | any($to[]; . == $n) | not)] as $miss
         | if ($miss | length) > 0 then "no delivery to " + ($miss | join(", ")) + " in this turn" else empty end
       elif ($to | length) == 0 then "no delivery in this turn"
       elif $k.all then "delivered in this turn only to " + ($to | join(", ")) + "; close it with the tool if that is everyone"
       else empty end
   end) as $why
| {l: $k.l, ts: $k.ts, art: "claim", text: ($k.text + " (no proof: " + $why + ")"), core: $k.text}'
# A web session calls rc through a call line "<tool>-exec:v1:<key>:<n>:<mac>:<argv base64>" in a shell command
# (as the argument of ":") or alone on a line of a tool's output; its result comes later as a message, so the line
# itself stands as the delivery to the receiver its argv names.
# shellcheck disable=SC2016 # jq text, not shell
state_exec_jq="$state_gh_write_jq"'def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n") else "" end;
  def call: "[a-z][a-z0-9]*(?:-[a-z0-9]+)*-exec:v[0-9]+:[0-9a-f]{32}:[0-9]+:[0-9a-f]{64}:([A-Za-z0-9+/=]+)";
  numbered | .l as $l | .j
  | (if .type == "assistant" then .message.content[]? | objects | select(.type == "tool_use" and (.name == "Bash" or .name == "PowerShell"))
       | (.input.command // "" | strings) | scan("(?:^|[\\n;&|(])[ \\t]*:[ \\t]+[\u0027\"]?" + call)
     elif .type == "user" then .message.content | arrays | .[] | objects | select(.type == "tool_result")
       | (.content | flat) | scan("(?:^|\\n)(?:: \u0027)?" + call + "\u0027?[ \\t\\r]*(?=\\n|$)")
     else empty end) | .[0]
  | ((@base64d? // "") | split("\u0000") | map(select(length > 0))) as $a
  | select(($a[0] // "") | test("^(send|report|ask)$"))
  | ($a | index("--to")) as $i
  | {id: ("exec:" + ($l | tostring)), l: $l, exec: true, rc: true, push: false, write: false, s: ($a | join(" ")),
     to: (if $i != null then $a[$i + 1] // "" elif $a[0] == "send" then ([$a[1:][] | select(startswith("-") | not)][0] // "")
          else "owner" end)}'
# The claims of the candidates file without proof among the own tool calls of their turn - from the last input of the
# maintainer or another session before it, where a reply of a session addressed with rc in the turn opens none: a
# session named in the claim that the session addressed with rc needs a delivery to it (rc prints the delivery id
# before the receiver), "alle" without names lists who got one.
state_claims() { # transcript, candidates file, folder -> the claims without proof as candidates on stdout
  local t="$1" d="$3"
  jq -c 'select(has("claim")) | .claim' < "$2" > "$d/claims.jsonl" || return 2
  [ -s "$d/claims.jsonl" ] || return 0
  { grep -n -F '"type":"tool_use"' "$t" | grep -E 'push|gh|github|rc'; } > "$d/uses.txt"
  jq -R -c "$state_uses_jq" < "$d/uses.txt" > "$d/uses.jsonl" || return 2
  jq -r '.id' < "$d/uses.jsonl" | tr -d '\r' > "$d/ids.txt" || return 2
  : > "$d/results.txt"
  [ ! -s "$d/ids.txt" ] || { grep -n -F -f "$d/ids.txt" "$t" | grep -F '"tool_result"'; } > "$d/results.txt"
  jq -R -c "$state_results_jq" < "$d/results.txt" > "$d/results.jsonl" || return 2
  { grep -n -F -- '-exec:v' "$t" || true; } | jq -R -c "$state_exec_jq" >> "$d/uses.jsonl" || return 2
  jq -n -c --slurpfile c "$d/claims.jsonl" --slurpfile u "$d/uses.jsonl" --slurpfile r "$d/results.jsonl" "$state_claims_jq"
}

# The work list as a list of ticks.sh (ww3d/playbook#688): a box "L<line> <UTC> <art>: <text>" per candidate,
# unanswered questions of the maintainer first. A box closes only through the tool, by a reference that holds its
# core (the candidate's text); a box of the same line, kind and text keeps its closing from the previous run. A stand
# box "<line> — <ref> ist <state> (Stand ...)" closes like the one of the restore file, at a carrier of this save once
# the stand check finds no contradiction there (ticks_stale_gone, ww3d/playbook#734).
# shellcheck disable=SC2016 # jq text, not shell
state_worklist_jq='def iso: if type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z$") then .[0:13] + ":" + .[13:15] + ":00Z" else null end;
  def one: gsub("[\t\r\n]"; " ");
  {title: "Save list \($s)", intro: $intro, gate: "warn",
   boxes: [sort_by(if .art == "open-question" then 0 else 1 end, .l)[]
     | (.text | one) as $t
     | {key: (if .u != null then "\($s):\(.u)" + (if .s != null then ":\(.s)" else "" end) else "\($s):L\(.l) \(.art): \($t)" end),
        title: "L\(.l) \(.ts) \(.art): \($t | if length > 400 then .[0:397] + "..." else . end)",
        at: (.ts | iso), kind: .art}
       + (if .art == "stale" and ($t | test("^.* — [^ ]+ ist [^ ]+ [(]Stand [^)]*[)]$")) then
           ($t | capture("^(?<l>.*) — (?<r>[^ ]+) ist [^ ]+ [(]Stand [^)]*[)]$")) as $c
           | {rule: "stale", core: $c.l, judged: $c.r, carriers: $cs}
         else {rule: "core", core: (.core // .text | one)} end)
       + (if .answer != null then {answer: .answer} else {} end)]}'
# The keys of the reading's candidates of the kinds human, open-question and message, as a box or as carried: the
# report of the cut names them (ww3d/playbook#727).
state_cut_keys() { # side list (locked by the caller), session of the history, candidates file
  [ -s "$3" ] || return 0
  # Through a file: the keys of a long history are too long for a command line. Keys that were not computed stay
  # out of the list, so the report has none rather than an empty set.
  local k="${1%.json}.keys.tmp" rc=0
  if jq -sc --arg S "$2" '[.[] | select(.art == "human" or .art == "open-question" or .art == "message")
    | if .u != null then "\($S):\(.u)" + (if .s != null then ":\(.s)" else "" end)
      else "\($S):L\(.l) \(.art): \(.text | gsub("[\t\r\n]"; " "))" end] | unique' < "$3" > "$k"; then
    jq --slurpfile k "$k" '.keys = $k[0]' "$1" | ticks_write "$1" || rc=2
  else rc=2; fi
  rm -f "$k"; return "$rc"
}
# The list of this save is a list of a cut (lib/cutlist.sh): it begins with what did not end in the session's last
# list; the file the session reads (<session>-save.md) names it.
state_worklist() { # unmatched candidates file, read file, session [, unexamined, match folder, save carriers as JSON]
  # -> globals state_open, state_unchecked, state_cut (the list's view)
  local prev side held=""; prev="$(cutlist_latest "$3")"
  if [ -n "$prev" ] && [ -n "${5:-}" ] && cutlist_carried "$(ticks_side "$prev")" > "$5/carried.jsonl" \
    && state_match_held "$5" "$5/carried.jsonl" > "$5/held.json"; then held="$5/held.json"; fi
  jq -s --arg s "$3" --argjson cs "${6:-[]}" --arg intro "Written by session-state.sh save: what no carrier of this save holds, since the cursor. Carry each box to a carrier and run save again, or close it with the tool." \
    "$state_worklist_jq" < "$1" > "$2.spec" || return 2
  state_cut="$(cutlist_reserve "$3")" || { rm -f "$2.spec"; return 2; }
  side="$(ticks_side "$state_cut")"
  ticks_lock "$side" || { rm -f "$2.spec"; return 2; }
  cutlist_build "$state_cut" "$2.spec" "$3" save "$held" "${4:-0}" ${prev:+"$(ticks_side "$prev")"}; local rc=$?
  [ "$rc" -ne 0 ] || { state_restore_saved "$side" "$(ticks_now)"; [ -z "${5:-}" ] || state_cut_keys "$side" "$3" "$5/cand.jsonl"; }
  ticks_unlock; rm -f "$2.spec"
  [ "$rc" -eq 0 ] || return 2
  cutlist_read_file "$state_cut" "$2" || return 2
  state_open="$(ticks_open_count "$side")"; [[ $state_open =~ ^[0-9]+$ ]] || return 2
  state_unchecked="$(jq "$ticks_state_jq"' with_state | [.boxes[] | select(.state == "u")] | length' "$side" | tr -d '\r')"
}

# Boxes under "## Open points" of a named carrier that run over 600 characters or append history outside
# quotes: a warning each, the exit stays.
state_open_point_warnings() { # body files...
  local f
  for f in "$@"; do
    awk -v src="$(basename "${f%.md}")" '
      function flush() { if (box != "") { t = box; gsub(/"[^"]*"|„[^“]*“|`[^`]*`/, "", t)
          if (length(box) > 600) print "warning: " src " open point over 600 characters: " substr(box, 1, 80)
          else if (t ~ /(^|[^A-Za-z])(Stand|Nachtrag|nachgetragen|Rest aus)([^A-Za-z]|$)/) print "warning: " src " open point appends history: " substr(box, 1, 80) }
        box = "" }
      /^## / { flush(); inside = ($0 ~ /^## Open points/); next }
      !inside { next }
      /^[[:space:]]*>/ { next }
      /^- \[ \]/ { flush(); box = $0; next }
      /^- \[x\]/ { flush(); next }
      /^[[:space:]]+[^[:space:]]/ { if (box != "") box = box " " $0; next }
      { flush() }
      END { flush() }' "$f"
  done
}

# --- EINLESEN (restore) -------------------------------------------------------------------------------------
# The carriers changed since checkedAt that another hand changed: one forge call per repo of the carriers
# (issues?since=), then the comments since then of each changed carrier. A change counts as the session's own
# where its time falls into one of the session's own write calls on that carrier (tool_use to tool_result, one
# second either side), told by the transcript, not the account: every session writes as the same bot.
# shellcheck disable=SC2016 # jq text, not shell
state_writes_jq='def ep: if type == "string" and length >= 19 then (.[0:19] + "Z" | fromdateiso8601) else null end;
$ARGS.positional as $refs
| [inputs | fromjson? | objects | select(.isSidechain != true)] as $e
| (reduce ($e[] | select(.type == "user") | .timestamp as $t | .message.content[]? | objects | select(.type == "tool_result") | {id: (.tool_use_id // ""), t: $t})
     as $r ({}; .[$r.id] = $r.t)) as $done
| [$e[] | select(.type == "assistant") | .timestamp as $t | .message.content[]? | objects | select(.type == "tool_use")
   | . as $u | ($u.input | tostring) as $s
   | select((($u.name == "Bash" or $u.name == "PowerShell") and ($s | test("\\bgh\\b"))
             and ($s | test("-X ?(POST|PATCH|PUT|DELETE)|--method[ =](POST|PATCH|PUT|DELETE)| -[fF] |--field|--raw-field|--input|gh (issue|pr) (comment|edit|close|reopen|create|ready|review|merge|lock)")))
            or (($u.name | test("github"; "i")) and ($u.name | test("get|list|search|read"; "i") | not)))
   | $refs[] as $c | ($c | capture("^(?<o>[^/]+)/(?<r>[^#]+)#(?<n>[0-9]+)$")) as $p
   | select(($s | contains("repos/\($p.o)/\($p.r)/issues/\($p.n)")) or ($s | contains("repos/\($p.o)/\($p.r)/pulls/\($p.n)"))
            or ($s | contains($c)) or (($s | contains("\($p.o)/\($p.r)")) and ($s | test("(^|[^0-9])\($p.n)([^0-9]|$)")))
            # A call without owner/repo writes to the checkout'"'"'s own repo ($home).
            or (($home == "\($p.o)/\($p.r)")
                and (($s | test("repos/\\{owner\\}/\\{repo\\}/(issues|pulls)/\($p.n)([^0-9]|$)"))
                     or (($s | test("gh (issue|pr) [a-z]+ #?\($p.n)([^0-9]|$)")) and ($s | test("--repo|-R ") | not))))
            or ((($u.input.owner? // "") == $p.o) and (($u.input.repo? // "") == $p.r)
                and ([$u.input.issue_number?, $u.input.pullNumber?, $u.input.pull_number?, $u.input.number?]
                     | map(select(. != null) | tostring) | index($p.n))))
   | {ref: $c, from: (($t | ep) - 1), to: ((($done[$u.id] // $t) | ep) + 1)}]'
# The checkout's own repo as owner/repo, from its origin; empty where there is none.
state_home() {
  git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null | tr -d '\r' \
    | sed -E -n 's#^.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's#\.git$##'
}
# shellcheck disable=SC2016 # jq text, not shell
state_changed_jq='def ep: if type == "string" and length >= 19 then (.[0:19] + "Z" | fromdateiso8601) else null end;
$ARGS.positional as $refs | ($w[0] // []) as $w | ($at | ep) as $since
| [$refs[] as $c | ($c | capture("^(?<o>[^/]+)/(?<r>[^#]+)#(?<n>[0-9]+)$")) as $p
   | ($issues[] | select(.repo == "\($p.o)/\($p.r)") | .items[]? | select((.number | tostring) == $p.n)) as $i
   | ([$i.updated_at] + [($comments[] | select(.ref == $c) | .items[]? | .created_at, .updated_at)]
      | map(ep) | map(select(. != null and . > $since)) | unique) as $times
   | [$times[] | select(. as $x | [$w[] | select(.ref == $c and .from <= $x and $x <= .to)] | length == 0)] as $foreign
   | select($foreign | length > 0)
   | "- [ ] \($c) changed since \($at): \($i.title // "" | gsub("[\r\n\t]"; " ")) (changes at \($foreign | map(todate) | join(", ")))"]
| .[]'
state_changed() { # folder, checkedAt (ISO), transcript, start line, carriers... -> section text on stdout
  local dir="$1" at="$2" t="$3" from="$4" c r k repos=() rc
  shift 4
  mapfile -t repos <<< "$(printf '%s\n' "$@" | sed 's/#.*//' | sort -u)"
  for r in "${repos[@]}"; do
    ( k="${r//\//_}"; rc=0
      timeout 10 gh api "repos/$r/issues?since=$at&state=all&per_page=100" > "$dir/since-$k.json" 2> "$dir/since-$k.err" || rc=$?
      [ "$rc" -eq 0 ] || { [ "$rc" -ne 124 ] || echo "timed out after 10 s" > "$dir/since-$k.err"; rm -f "$dir/since-$k.json"; } ) &
  done
  wait
  for r in "${repos[@]}"; do
    k="${r//\//_}"
    if [ -s "$dir/since-$k.json" ]; then jq -c --arg r "$r" '{repo: $r, items: (if type == "array" then . else [] end)}' "$dir/since-$k.json" 2>/dev/null
    else echo "carriers changed: not checked for $r ($(head -c 200 "$dir/since-$k.err" 2>/dev/null | tr '\r\n' '  '))" >&2; fi
  done > "$dir/issues.jsonl" 2> "$dir/changed.note"
  # The comments of each carrier the forge names as changed.
  for c in "$@"; do
    jq -e --arg r "${c%%#*}" --argjson n "${c##*#}" 'select(.repo == $r) | .items[] | select(.number == $n)' "$dir/issues.jsonl" >/dev/null 2>&1 || continue
    ( k="$(state_key "$c")"
      timeout 10 gh api "repos/${c%%#*}/issues/${c##*#}/comments?since=$at&per_page=100" > "$dir/comments-$k.json" 2>/dev/null \
        || rm -f "$dir/comments-$k.json" ) &
  done
  wait
  for c in "$@"; do
    k="$(state_key "$c")"
    [ -s "$dir/comments-$k.json" ] && jq -c --arg c "$c" '{ref: $c, items: (if type == "array" then . else [] end)}' "$dir/comments-$k.json" 2>/dev/null
  done > "$dir/comments.jsonl"
  tail -n "+$from" "$t" 2>/dev/null | jq -nRc --arg home "$(state_home)" --args "$state_writes_jq" "$@" 2>/dev/null > "$dir/writes.json" || echo '[]' > "$dir/writes.json"
  cat "$dir/changed.note"
  jq -nr --arg at "$at" --slurpfile w "$dir/writes.json" --slurpfile issues "$dir/issues.jsonl" \
    --slurpfile comments "$dir/comments.jsonl" --args "$state_changed_jq" "$@" 2>/dev/null
}

# --- the restore file, shared by restore-compact-state.sh and session-state.sh restore --from ----------------
read -r -d '' state_step_jq <<'JQ'
def flat: if type == "string" then . elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n")
  elif . == null then "" else tostring end;
def oneline($n): gsub("\\s+"; " ") | if length > $n then .[0:$n - 3] + "..." else . end;
def human: .type == "user" and (.isMeta | not) and (.isCompactSummary | not) and (.isSidechain | not)
  and ((.message.content | type) == "string" or ([.message.content[]? | select(.type? == "tool_result")] | length) == 0);
[inputs | (fromjson? // null) | objects | select(.isSidechain != true)] as $e
| ($e | length) as $len
| ((first(range($len - 1; -1; -1) as $k | $e[$k]
     | ([.message.content[]? | objects | select(.type == "tool_use" and .name == "Skill")
         | "skill " + (.input.skill // "?" | tostring) + (if (.input.args // "") != "" then " " + (.input.args | tostring) else "" end)]
        + [select(human) | .message.content | flat | select(test("<command-name>")) as $t
           | ($t | capture("<command-name>(?<n>[^<]*)</command-name>").n | if startswith("/") then . else "/" + . end) as $n
           | ([$t | match("<command-args>([\\s\\S]*?)</command-args>") | .captures[0].string] | first // "") as $a
           # A harness command (model, compact, ...) is no work step.
           | select($n | test("^/(compact|clear|model|config|context|cost|status|help|resume|rewind|permissions|hooks|memory|login|logout|exit)$") | not)
           | $n + (if $a == "" then "" else " " + $a end)])
     | last // empty) // "none found") | oneline(500)) as $step
| ([$e[] | select(.type == "assistant") | .message.content[]? | objects
    | select(.type == "tool_use" and (.name == "TodoWrite" or .name == "TaskCreate" or .name == "TaskUpdate"))] as $tu
   | if ($tu | length) == 0 then []
     elif ($tu | last | .name) == "TodoWrite" then [($tu | last | .input.todos // [])[] | "- [\(.status // "?")] \(.content // .subject // "")"]
     else (reduce ($e[] | select(.type == "user") | .message.content[]? | objects | select(.type == "tool_result"))
             as $r ({}; .[$r.tool_use_id // ""] = ($r.content | flat))) as $res
       | (reduce $tu[] as $u ({};
            if $u.name == "TaskCreate" then
              ([($res[$u.id // ""] // "") | match("Task #([0-9]+)") | .captures[0].string] | first) as $n
              | if $n == null then . else .[$n] = {s: ($u.input.subject // ""), st: "pending"} end
            elif $u.name == "TaskUpdate" and ($u.input.taskId // null) != null then
              ($u.input.taskId | tostring) as $n
              | .[$n] = ((.[$n] // {s: "", st: "pending"}) | .st = ($u.input.status // .st) | .s = ($u.input.subject // .s))
            else . end))
          | to_entries | map(select(.value.st != "deleted")) | sort_by(.key | tonumber? // 0)
          | map("- [\(.value.st)] #\(.key) \(.value.s)") end) as $todos
# The main thread's own boundary is written only after this hook (3 s, measured 2026-11-12): the newest own text
# of the transcript is the step, a boundary in it belongs to an earlier compaction.
| (first(range($len - 1; -1; -1) as $k | $e[$k] | select(.type == "assistant")
     | [.message.content[]? | objects | select(.type == "text") | .text] | join("\n")
     # A read-receipt line ("+ <file> <version> <sha> read") is no work step.
     | gsub("(?m)^\\+ \\S+ .* read( \\(rule\\))?\\s*$"; "") | select(test("[^\\s]")))
   // "none found" | oneline(500)) as $work
| "Step: " + $work + "\n\nSkill: " + $step
  + "\n\nTodos:\n\n" + (if ($todos | length) > 0 then $todos | join("\n") else "_none_" end)
JQ

# What the restore file needs from outside, side by side: the haystack and the match of the candidates in
# <folder>/cand.jsonl (where a transcript was read), the carriers changed since checkedAt, the further channel's
# changes since checked, the open posts of a predecessor (state_posts_of) and the tool additions. Each has its own
# time limit; the caller's hook has one too (settings.json).
state_restore_gather() { # folder, transcript ('' where none was read), start line, checked, checkedAt, carriers...
  local dir="$1" t="$2" from="$3" checked="$4" at="$5"
  shift 5
  export STATE_GH_TIMEOUT=10
  if [ $# -gt 0 ] && command -v gh >/dev/null 2>&1; then
    ( state_haystack "$dir" "$@" > /dev/null 2> "$dir/hay.log"; printf '%s' "$state_hay_note" > "$dir/hay.note"
      # Written whole or not at all: a gathering ended by its time limit leaves no half list.
      [ -z "$t" ] || [ -s "$dir/hay.log" ] || { state_match "$dir" "$dir/cand.jsonl" > "$dir/open.part" 2>/dev/null \
        && mv -f "$dir/open.part" "$dir/open.jsonl"; }
      # The truth receipt: the open boxes of the carriers against the state of their references.
      state_stale_lines "$dir" "" "$@" > "$dir/stale-lines.jsonl" 2>/dev/null
      TICKS_TIMEOUT=10 state_stale "$dir/stale-lines.jsonl" "$dir" > "$dir/stale.jsonl" 2>/dev/null ) &
    if [[ $at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
      { mkdir -p "$dir/ch" && { state_changed "$dir/ch" "$at" "${t:-/dev/null}" "$from" "$@" > "$dir/changed.part" 2>&1
        mv -f "$dir/changed.part" "$dir/changed.txt"; }; } &
    fi
  fi
  if [ -n "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then
    [ -z "$checked" ] || state_tool_run "$dir/channel-changed.txt" 'further channel' changed "$checked" &
    [ -z "${state_posts_of:-}" ] || state_tool_run "$dir/posts.txt" 'open posts' posts "$state_posts_of" &
    state_tool_run "$dir/extra.txt" 'tool additions' extra &
  fi
  wait
}
# One call of PLAYBOOK_CARRIER_TEXT_CMD, STATE_TOOL_TIMEOUT or 60 s; a failure or the time limit is a "not checked"
# line after its output.
state_tool_run() { # output file, label, arguments...
  local out="$1" label="$2" rc=0 s="${STATE_TOOL_TIMEOUT:-60}"
  shift 2
  timeout "$s" bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ "$@" > "$out" 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || printf '\n%s: not checked (PLAYBOOK_CARRIER_TEXT_CMD %s %s)\n' "$label" "$1" \
    "$([ "$rc" -eq 124 ] && echo "timed out after $s s" || echo "failed, exit $rc")" >> "$out"
}

# The restore file as a list of ticks.sh (ww3d/playbook#688): its sections stay text in their order, every "- [ ]"
# line of the two box sections becomes a box of its section. A box of the history, a post of the predecessor and any
# other box close by a reference that holds their core; a carrier another hand changed closes as a box of the hour
# list (its changes, erledigt at the carrier or gelesen); a stand box closes at a carrier of the last save ($cs) where
# the stand check no longer finds it (ticks_stale_gone).
# shellcheck disable=SC2016 # jq text, not shell
state_restore_jq='def iso: if test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z$") then .[0:13] + ":" + .[13:15] + ":00Z" else null end;
  def strip: sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "");
  def boxed: test("^- [[] []] ");
  # The key of a box (ww3d/playbook#727, question 1917 a): a box of the history takes the key of its entry in the
  # transcript ($hk, in the order of the history, with the answer to a sentence of the maintainer), every other box
  # its title before, with the session in front.
  def box($s): sub("^- [[] []] "; "") as $x | {key: "\($S):\($x)", title: $x, section: $s}
    + if ($x | test("^L[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}Z [a-z-]+: ")) then
        ($x | capture("^L[0-9]+ (?<ts>[^ ]+) (?<art>[a-z-]+): (?<text>.*)$")) as $c
        | {rule: "core", core: $c.text, at: ($c.ts | iso), kind: $c.art, hist: true}
      elif ($x | test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+ changed since [^ ]+: .* [(]changes at [^)]*[)]$")) then
        ($x | capture("^(?<c>[^ ]+) changed since [^ ]+: (?<t>.*) [(]changes at (?<at>[^)]*)[)]$")) as $c
        | {key: "\($S):changed:\($c.c)", kind: "changed", carriers: [$c.c], changes: [$c.at | split(", ")[] | {carrier: $c.c, kind: "changed", at: ., first: $c.t}]}
      elif ($x | test("^post: ")) then {key: "\($S):\($x)", rule: "core", core: ($x | sub("^post: "; "")), kind: "post"}
      elif ($x | test("^stale: .* — [^ ]+ ist [^ ]+ [(]Stand [^)]*[)]$")) then
        ($x | capture("^stale: (?<l>.*) — (?<r>[^ ]+) ist [^ ]+ [(]Stand [^)]*[)]$")) as $c
        | {rule: "stale", core: $c.l, judged: $c.r, carriers: $cs, kind: "stale"}
      elif ($x | test("^stale: ")) then {rule: "core", core: ($x | sub("^stale: "; "")), kind: "stale"}
      elif ($x | test("^Restore unvollstaendig [(]Frist ")) then {key: "\($S):restore-incomplete", rule: "core", core: $x, kind: "restore-incomplete"} + (if $ev != "" then {event: $ev} else {} end)
      elif ($x | test("^compaction instruction did not arrive ")) then {key: "\($S):instruction", rule: "core", core: $x, kind: "instruction"} + (if $ev != "" then {event: $ev} else {} end)
      else {rule: "core", core: $x, kind: "other"} end;
  split("\n") | map(sub("\r$"; "")) as $ls
  | [range(0; $ls | length) | select($ls[.] | startswith("## "))] as $h
  | [$h | to_entries[] | ($ls[.value] | sub("^## "; "")) as $t | $ls[(.value + 1):($h[.key + 1] // ($ls | length))] as $b
      | ($t == "History without a carrier" or $t == "Carriers changed since checked") as $boxes
      | {title: $t, text: ([$b[] | select($boxes and boxed | not)] | join("\n") | strip),
         boxes: [if $boxes then $b[] | select(boxed) | box($t) else empty end]}] as $secs
  | {title: ($ls[0] | sub("^# "; "")), intro: ($ls[1:($h[0] // 1)] | join("\n") | strip), gate: "view",
     sections: [$secs[] | {title, text: (if .text == "" and (.boxes | length) == 0 then "_none_" else .text end)}],
     boxes: (reduce ($secs[].boxes[]) as $b ({i: 0, out: []};
       if $b.hist then .out += [$b + {key: ($hk[.i].key // $b.key)} + ($hk[.i] | if .answer != null then {answer} else {} end)
         | del(.hist)] | .i += 1 else .out += [$b] end) | .out)}'
# The restore is a cut (lib/cutlist.sh): its list begins with what did not end in the session's last list, after a
# switch also in the predecessor's; the read file names it. Global out: state_cut (the list's view).
state_restore_list() { # rendered (masked), read file, session, source (compact|switch|clear), session of the history,
  # its unmatched candidates ('' none), match folder, the predecessor's last side list ('' none)
  local s="$3" hs="$5" hk prev side rc cs held=""
  # The carriers of the last save, from the caller's rs_carriers.
  # shellcheck disable=SC2154 # rs_carriers is set by the caller (restore-compact-state.sh, lib/successor.sh)
  cs="$(printf '%s\n' ${rs_carriers[@]+"${rs_carriers[@]}"} | jq -R 'select(length > 0)' | jq -sc .)" || return 2
  # The keys go through a file: a long history makes them too long for a command line ("Argument list too long").
  hk="$7/keys.json"; echo '[]' > "$hk" || return 2
  [ -z "$6" ] || [ ! -s "$6" ] || jq -sc --arg S "$hs" '[.[] | select(has("art")) | {key: (if .u != null then "\($S):\(.u)" + (if .s != null then ":\(.s)" else "" end)
    else "\($S):L\(.l) \(.art): \(.text | gsub("[\t\r\n]"; " "))" end), answer}]' < "$6" > "$hk" || return 2
  jq -Rs --argjson cs "$cs" --arg S "$hs" --arg ev "${STATE_EVENT:-}" --slurpfile hk "$hk" "\$hk[0] as \$hk | $state_restore_jq" < "$1" > "$1.spec" || return 2
  prev="$(cutlist_latest "$s")"; [ -z "$prev" ] || prev="$(ticks_side "$prev")"
  if cutlist_carried "$prev" "${8:-}" > "$7/carried.jsonl" && state_match_held "$7" "$7/carried.jsonl" > "$7/held.json"; then
    held="$7/held.json"
  fi
  state_cut="$(cutlist_reserve "$s")" || { rm -f "$1.spec"; return 2; }
  side="$(ticks_side "$state_cut")"
  ticks_lock "$side" || { rm -f "$1.spec"; return 2; }
  cutlist_build "$state_cut" "$1.spec" "$s" "$4" "$held" "${state_unexamined:-0}" "$prev" "${8:-}"; rc=$?
  [ "$rc" -ne 0 ] || state_cut_keys "$side" "$hs" "$7/cand.jsonl"
  ticks_unlock; rm -f "$1.spec"
  [ "$rc" -eq 0 ] || return 2
  cutlist_read_file "$state_cut" "$2"
}
# The open boxes of the list a read file names.
state_restore_open() { # read file -> the number on stdout
  local l n=0; l="$(cutlist_of "$1")"
  [ -z "$l" ] || n="$(ticks_open_count "$(ticks_side "$l")")"
  [[ $n =~ ^[0-9]+$ ]] && printf '%s' "$n" || echo 0
}
# A save closes the boxes "compaction instruction did not arrive" and "Restore unvollstaendig" in its own list: that
# save is what they ask for (q1889 a, point 2; ww3d/playbook#750).
state_restore_saved() { # side list (locked by the caller), time of the save (ISO)
  local id
  for id in $(jq -r "$ticks_state_jq"' with_state | .boxes[] | select(.state == "open" and (.kind == "instruction" or .kind == "restore-incomplete")) | .id' "$1" | tr -d '\r'); do
    ticks_journal "$1" "$(jq -nc --arg b "$id" --arg at "$2" '{box: $b, how: "done", ref: "session-state.sh save", by: "tool",
      evidence: {ok: true, kind: "save", ref: "session-state.sh save", at: $at}, at: $at, text: "save at \($at)"}')"
  done
}

# The eight sections of the restore file, from what state_restore_gather left in the folder; unmasked, on stdout.
# Globals the caller sets: rs_title, rs_lead (the line under it), rs_note (nothing read: every section from the
# history to the helper results says so), rs_txnote (the transcript alone not read: the history and the three
# verbatim sections say so, the changed carriers stand), rs_steps, rs_rules (body of "Rule files to reread"),
# rs_start_note, rs_checked, rs_checked_at, rs_carriers (array), rs_posts (1 where open posts were asked for), rs_first
# (the compaction check: a box or a line that stands first in the history), rs_incomplete (the box of a restore that
# ran out of its budget: first of all, also where rs_note says that nothing was read).
state_section() { printf '## %s\n\n%s\n\n' "$1" "${2:-_none_}"; }
# What the gathering left in a file; a file it did not get to is said.
state_gathered() { # file, label
  if [ -e "$1" ]; then tr -d '\r' < "$1"; else printf '%s: not checked (the restore ran out of time)' "$2"; fi
}
# shellcheck disable=SC2154 # rs_* are set by the caller (restore-compact-state.sh, lib/successor.sh)
state_restore_render() { # folder
  local work="$1" h hist unread boxes changed c_out entry posts=""
  printf '# %s\n\n%s\n\n' "$rs_title" "$rs_lead"
  [ -z "$rs_note" ] || printf 'Only partly written: %s.\n\n' "$rs_note"
  state_section "Step and todos" "${rs_steps:-_not read_}"
  state_section "Rule files to reread" "$rs_rules"
  if [ -n "$rs_note" ]; then
    hist="_not read: ${rs_note}_"
    [ -z "${rs_incomplete:-}" ] || hist="$rs_incomplete"$'\n\n'"Since the cursor: $rs_start_note."$'\n\n'"$hist"
    state_section "History without a carrier" "$hist"
    for h in "Carriers changed since checked" "The maintainer's sentences since the cursor" \
             "Messages of other sessions since the cursor" "Helper results since the cursor"; do state_section "$h" "_not read: ${rs_note}_"; done
  else
    # A predecessor's open posts and orders stand as boxes in the history (PLAYBOOK_CARRIER_TEXT_CMD posts).
    if [ "${rs_posts:-}" = 1 ]; then
      if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then posts="open posts: not checked"
      else
        # A failed call leaves its error text in the file: then only its "not checked" line stands, never a box.
        posts="$(tr -d '\r' < "$work/posts.txt" 2>/dev/null | awk '/^open posts: not checked/ { failed = $0; next }
          /[^[:space:]]/ { sub(/^[[:space:]]*(- \[[ xX]\][[:space:]]*|[-*][[:space:]]+)?/, ""); b[++n] = "- [ ] post: " $0 }
          END { if (failed != "") print failed; else for (i = 1; i <= n; i++) print b[i] }')"
        posts="${posts:-_no open post_}"
      fi
    fi
    if [ -n "$rs_txnote" ]; then
      hist="Not readable: $rs_txnote."
    else
      hist="Since the cursor: $rs_start_note."
      # A check line "transcript: not readable" newer than the last save leaves the stretch since it unchecked.
      unread="$(cat "$work"/*.md 2>/dev/null | grep -o 'checked: [0-9TZ-]* · transcript: not readable[^)]*)' | sort | tail -n 1)" || unread=""
      if [ -n "$unread" ] && [[ ${unread#checked: } > ${rs_checked:-0} ]]; then
        hist="$hist"$'\n\n'"Unchecked since ${unread%% ·*}: the last check line says the transcript was not readable (${unread#*not readable })."
      fi
      if [ ${#rs_carriers[@]} -eq 0 ]; then
        hist="$hist No carrier named at the last save (or no save): every candidate since the cursor stands as a box."
        jq -c 'select(has("art"))' < "$work/cand.jsonl" > "$work/open.jsonl"
      elif [ -s "$work/hay.log" ] || [ ! -e "$work/open.jsonl" ]; then
        hist="$hist Carriers not read ($(head -c 300 "$work/hay.log" 2>/dev/null | tr '\r\n' '  ')): every candidate since the cursor stands as a box."
        jq -c 'select(has("art"))' < "$work/cand.jsonl" > "$work/open.jsonl"
      fi
      [ ! -s "$work/hay.note" ] || hist="$hist"$'\n\n'"$(cat "$work/hay.note")"
      boxes="$(jq -r '"- [ ] L\(.l) \(.ts) \(.art): \(.text | gsub("[\t\r\n]"; " ") | if length > 400 then .[0:397] + "..." else . end)"' \
        < "$work/open.jsonl" 2>/dev/null | tr -d '\r')"
      hist="$hist${boxes:+$'\n\n'$boxes}"
    fi
    # The compaction check of restore-compact-state.sh: its box stands first, its "not checkable" line likewise.
    [ -z "${rs_first:-}" ] || hist="$rs_first"$'\n\n'"$hist"
    [ -z "${rs_incomplete:-}" ] || hist="$rs_incomplete"$'\n\n'"$hist"
    state_section "History without a carrier" "$hist${posts:+$'\n\n'$posts}"

    if [ -z "$rs_checked_at" ]; then changed="Not checked: no save with exit 0 in this session (no checkedAt)."
    elif [ ${#rs_carriers[@]} -eq 0 ]; then changed="Not checked: the last save named no carrier."
    else changed="Since $rs_checked (checkedAt $rs_checked_at), changes of the session's own write calls left out."
      if [ -e "$work/changed.txt" ]; then c_out="$(tr -d '\r' < "$work/changed.txt" 2>/dev/null)"
      elif ! command -v gh >/dev/null 2>&1; then c_out="carriers changed: not checked (gh not found)"
      elif [ -n "${rs_incomplete:-}" ]; then c_out="carriers changed: not checked (the restore ran out of time)"
      else c_out="carriers changed: not checked (checkedAt '$rs_checked_at' is no ISO time)"; fi
      changed="$changed"$'\n\n'"${c_out:-_no carrier changed by another hand_}"
    fi
    # The truth receipt: an open box of a carrier its references contradict, and what was not checkable.
    c_out="$({ jq -r '"- [ ] stale: \(.text)"' < "$work/stale.jsonl" | tr -d '\r'; cat "$work/stale.note"; } 2>/dev/null)"
    [ -z "$c_out" ] || changed="$changed"$'\n\n'"$c_out"
    if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then changed="$changed"$'\n\n'"further channel: not checked"
    elif [ -n "$rs_checked" ]; then changed="$changed"$'\n\n'"Further channel (PLAYBOOK_CARRIER_TEXT_CMD changed $rs_checked):"$'\n\n'"$(state_gathered "$work/channel-changed.txt" 'further channel')"; fi
    state_section "Carriers changed since checked" "$changed"

    if [ -n "$rs_txnote" ]; then
      for h in "The maintainer's sentences since the cursor" "Messages of other sessions since the cursor" \
               "Helper results since the cursor"; do state_section "$h" "_not readable: ${rs_txnote}_"; done
    else
      # shellcheck disable=SC2016 # jq text, not shell
      entry='"### L\(.l) \(.ts)" + (if .from then " " + .from else "" end) + "\n\n" + (.full // .text)'
      state_section "The maintainer's sentences since the cursor" \
        "$(jq -r "select(.art == \"human\" or .art == \"open-question\") | $entry + \"\n\"" < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
      state_section "Messages of other sessions since the cursor" \
        "$(jq -r "select(.art == \"message\") | $entry + \"\n\"" < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
      state_section "Helper results since the cursor" \
        "$(jq -r "select(.art == \"helper\") | $entry + \"\n\"" < "$work/cand.jsonl" 2>/dev/null | tr -d '\r')"
    fi
  fi
  if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then state_section "Tool additions" "tool additions: not checked"
  else state_section "Tool additions" "$(state_gathered "$work/extra.txt" 'tool additions')"; fi
}

# The state check of the references in the pairs and open boxes (ww3d/playbook#672); it needs the jq texts above.
# shellcheck source=SCRIPTDIR/stale.sh
. "${BASH_SOURCE[0]%/*}/stale.sh"
# The read parts of a large restore file (ww3d/playbook#672).
# shellcheck source=SCRIPTDIR/parts.sh
. "${BASH_SOURCE[0]%/*}/parts.sh"
# The work list and the restore file are lists of the tick tool (ww3d/playbook#688).
# shellcheck source=SCRIPTDIR/ticks.sh
. "${BASH_SOURCE[0]%/*}/ticks.sh"
