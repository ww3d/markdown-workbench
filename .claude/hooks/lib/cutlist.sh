# shellcheck shell=bash
# shellcheck disable=SC2154 # ticks_state_jq comes from lib/ticks.sh, which sources this file
# Sourced by lib/ticks.sh, never run: the list of each cut (ww3d/playbook#727).
# Every cut - a save, the restore after a compaction, restore --from - writes its own list
# <project>/.agent/state/ticks/<session>/cut-<n>.md with its side list; no run overwrites or deletes an earlier one.
# A new list begins with every box of the session's last list that did not end (open or "[u]"), under the same key,
# after restore --from also with those of the predecessor's last list. A box ended with evidence, read or set aside
# (abgelegt) stands in no later list. The side list of a cut adds: cut, holder (the session), source (save, compact,
# switch), closedKeys, openBefore, repaired, ownUnexamined, holds, holdSeq, byTool; a box adds hops.

cutlist_dir() { printf '%s/.agent/state/ticks/%s' "$(ticks_project)" "$1"; } # session -> its folder
cutlist_n() { local b="${1##*/cut-}"; b="${b%.*}"; [[ $b =~ ^[0-9]+$ ]] && printf '%s' "$b"; } # view -> n
# The view of the newest list in a folder of cut lists, or of a session, nothing without one.
cutlist_latest() { cutlist_latest_in "$(cutlist_dir "$1")"; } # session
cutlist_latest_in() { # folder
  local f n best=0 out=""
  for f in "$1"/cut-*.json; do
    [ -s "$f" ] || continue
    n="$(cutlist_n "$f")" || continue
    [ "$n" -le "$best" ] || { best=$n; out="${f%.json}.md"; }
  done
  printf '%s' "$out"
}
# A new number: its side list is made empty at once (noclobber), so no other run takes it. The view on stdout.
cutlist_reserve() { # session
  local d; d="$(cutlist_dir "$1")"; mkdir -p "$d" || return 2
  local f m n=1
  for f in "$d"/cut-*.json; do m="$(cutlist_n "$f")" && [ "$m" -ge "$n" ] && n=$((m + 1)); done
  until (set -C; : > "$d/cut-$n.json") 2>/dev/null; do n=$((n + 1)); [ "$n" -lt 1000000 ] || return 2; done
  printf '%s/cut-%s.md' "$d" "$n"
}

# The spec of a cut from the builder's spec and the lists before it ($olds, each with its state): boxes whose key
# ended there are left out, boxes that did not end come along (hops + 1), a box the carriers of this cut hold
# ($held: key -> carrier) is closed by the tool. The second output is the old side list ticks_open keeps journals from.
# shellcheck disable=SC2016 # jq text, not shell
cutlist_carry_jq='
  ($olds | map(with_state)) as $os
  | [$os | to_entries[] | .key as $i | .value as $l | $l.boxes[] | . + {oid: "o\($i)-\(.id)", lcreated: $l.created}] as $ob
  | (([$os[] | .closedKeys // []] | add // []) + [$ob[] | select(.state == "x") | .key] | unique) as $closed
  | (reduce ($ob[] | select(.state != "x")) as $b ({}; if .[$b.key] == null then .[$b.key] = $b else . end)) as $carry
  | ([.sections[]?.title]) as $secs
  # A changed carrier and a missing instruction keep one key per session (question 1917 a): their fresh box is a new
  # event, never one closed before.
  | .boxes = [.boxes[] | select(.kind == "changed" or .kind == "instruction" or (.key as $k | $closed | index($k) | not))
      | if $carry[.key] != null then .hops = (($carry[.key].hops // 0) + 1) else . end]
  # An earlier closing of that key reaches it only for the same event (the times of the changes, the cut of the
  # missing instruction): a new event starts without the journal of the lists before it.
  | def ev: if .kind == "changed" then [.changes[]?.at] | sort else .event // null end;
    ([.boxes[] | select(.kind == "changed" or .kind == "instruction") | . as $b | ($b | ev) as $v
      | select(any($ob[] | select(.key == $b.key) | ev; . == $v) | not) | .key]) as $fresh
  | ([.boxes[].key]) as $have
  | .boxes += [$carry[] | select(.key as $k | $have | index($k) | not)
      | {key, title, carriers, lines, closeWith, rule, core, kind, event, judged, answer, at: (.at // .lcreated),
         hops: ((.hops // 0) + 1), changes: [.changes[]? | del(.id)],
         section: (.section as $sc | if ($sc != null and ($secs | index($sc))) then $sc
           elif ($secs | index("History without a carrier")) and .kind != "changed" then "History without a carrier"
           elif ($secs | index("Carriers changed since checked")) and .kind == "changed" then "Carriers changed since checked"
           else null end)}
      | with_entries(select(.value != null))]
  | .closedKeys = $closed | .cut = $n | .holder = $s | .source = $src
  | {spec: ., old: {boxes: [$ob[] | select(.key as $k | $fresh | index($k) | not) | {id: .oid, key}],
      journal: [$os | to_entries[] | .key as $i | .value.journal[] | .box = "o\($i)-\(.box)"]},
     must: [$carry | keys[]]}'

# Write the list of a cut. olds: the side lists before it (the session's last one, the predecessor's), held: a JSON
# file {key: carrier} of carried boxes a carrier of this cut holds (may be missing), unexamined: own sentences the
# reading gave no kind. Exit 2 when the list was not written; the reserved number stays empty then.
cutlist_build() { # view, builder spec file, session, source, held file, unexamined, olds...
  local view="$1" spec="$2" s="$3" src="$4" held="$5" un="$6" side d; shift 6
  side="$(ticks_side "$view")"; d="$(hook_mktemp -d cutlist)" || return 2
  local olds=() o; for o in "$@"; do [ -n "$o" ] && [ -s "$o" ] && jq -e .boxes "$o" >/dev/null 2>&1 && olds+=("$o"); done
  { if [ ${#olds[@]} -gt 0 ]; then jq -s . "${olds[@]}"; else echo '[]'; fi; } > "$d/olds.json" || { rm -rf "$d"; return 2; }
  jq --slurpfile olds "$d/olds.json" --argjson n "$(cutlist_n "$view")" --arg s "$s" --arg src "$src" \
    "$ticks_state_jq"' $olds[0] as $olds | '"$cutlist_carry_jq" "$spec" > "$d/carry.json" || { rm -rf "$d"; return 2; }
  if ! { jq .spec "$d/carry.json" > "$d/spec.json" && jq .old "$d/carry.json" > "$d/old.json" && jq .must "$d/carry.json" > "$d/must.json"; }; then
    rm -rf "$d"; return 2
  fi
  ticks_open "$view" "$d/spec.json" "$d/old.json" || { rm -rf "$d"; return 2; }
  [ -s "${held:-}" ] || held="$d/none.json"; [ -s "$held" ] || echo '{}' > "$held"
  cutlist_repair "$side" "$d/must.json" "$d/olds.json" || { rm -rf "$d"; return 2; }
  cutlist_close_held "$side" "$held" || { rm -rf "$d"; return 2; }
  jq --argjson u "${un:-0}" '. + {openBefore: (.boxes | length), ownUnexamined: $u, holds: 0,
      holdSeq: (.journal | map(.seq) | max // 0), byTool: 0}' "$side" | ticks_write "$side" || { rm -rf "$d"; return 2; }
  rm -rf "$d"
  ticks_register "$view"
  for o in ${olds[@]+"${olds[@]}"}; do [ "${o%/*}" != "${side%/*}" ] || ticks_register "${o%.json}.md"; done
}

# Every key that must stand in the list (the boxes of the lists before it that did not end) and does not: the box
# comes from the list before, counted in repaired.
cutlist_repair() { # side list, keys file (JSON array), olds file (JSON array of side lists)
  jq --slurpfile must "$2" --slurpfile olds "$3" "$ticks_state_jq"'
    ([.boxes[].key]) as $have | ([$must[0][] | select(. as $k | $have | index($k) | not)]) as $miss
    | ([$olds[0][] | with_state | .boxes[]] | map({key: .key, value: .}) | from_entries) as $ob
    | (.boxes | length) as $n0
    | .boxes += [$miss | to_entries[] | (.key + $n0 + 1) as $i | $ob[.value]
        | {id: "K\($i)", key, title, carriers: (.carriers // []), lines: (.lines // []), closeWith: (.closeWith // null),
           changes: [.changes[]? | del(.id)] | to_entries | map(.value + {id: "K\($i).\(.key + 1)"}),
           hops: ((.hops // 0) + 1), repaired: true}
          + ({rule, core, at, kind, event, section, judged, answer} | with_entries(select(.value != null)))]
    | .repaired = (($miss | length) + (.repaired // 0))' "$1" | ticks_write "$1"
}

# A carried box a carrier of this cut holds is closed by the tool, the carrier as its evidence.
cutlist_close_held() { # side list, held file {key: carrier}
  jq --slurpfile h "$2" --arg now "$(ticks_now)" '. as $l | $h[0] as $h
    | .journal += [.boxes[] | select($h[.key] != null and (.hops // 0) > 0)
        | {box: .id, how: "done", ref: $h[.key], by: "tool", at: $now, text: "am Traeger \($h[.key]) gefunden",
           evidence: {ok: true, kind: "carrier", ref: $h[.key], at: $now}}]
    | .journal |= (to_entries | map(.value + {seq: (.key + 1)}))' "$1" | ticks_write "$1"
}

# The balance of a cut for its report: what its list held at its start, and how each box stands now.
cutlist_balance() { # view -> JSON on stdout
  local side; side="$(ticks_side "$1")"
  jq -c "$ticks_state_jq"' . as $l | with_state | . as $s
    | def how($b): ([$l.journal[] | select(.box == $b.id)] | last | .how) // null;
      ([.boxes[] | select(.state == "x" and how(.) != "released")] | length) as $done
    | ([.boxes[] | select(.state == "x" and how(.) == "released")]) as $rel
    | {openBefore: (.openBefore // (.boxes | length)), done: $done, released: ($rel | length),
       forwarded: ([.boxes[] | select(.state != "x")] | length), open: ([.boxes[] | select(.state == "open")] | length),
       repaired: (.repaired // 0), ownUnexamined: (.ownUnexamined // 0), byTool: (.byTool // 0),
       releasedHuman: [$rel[] | select(.kind == "human" or .kind == "open-question") | . as $b
         | ([$l.journal[] | select(.box == $b.id)] | last) as $e
         | {key, sentence: ((.core // .title) | .[0:400]), answer: ((.answer // "") | .[0:400]), reason: (($e.reason // "") | .[0:400])}]}
    + (if $l | has("keys") then {keys: $l.keys} else {} end)' "$side"
}

# The guard at the turn end, for a list of the session that holds: a hold without a new journal entry since the
# last one counts on; at the third the tool sets every open box to "[u]" and the turn ends (decision 8702).
# Exit 0 released, 1 counted, 2 not counted (list locked or unreadable: the hold stands as it is).
cutlist_hold() { # view
  local side; side="$(ticks_side "$1")"
  TICKS_LOCK_WAIT=2 ticks_lock "$side" 2>/dev/null || return 2
  jq --arg now "$(ticks_now)" "$ticks_state_jq"' (.journal | map(.seq) | max // 0) as $seq
    | .holds = (if $seq == (.holdSeq // -1) then (.holds // 0) + 1 else 1 end) | .holdSeq = $seq
    | if .holds >= 3 then
        . as $l | ($l | with_state | [.boxes[] | select(.state == "open") | .id]) as $ids
        | .journal += [$ids | to_entries[] | {seq: ($seq + .key + 1), box: .value, how: "unchecked", by: "tool", at: $now,
            reason: "weitergereicht vom Werkzeug nach 3 Halten", text: "ungeprueft: weitergereicht vom Werkzeug nach 3 Halten"}]
        | .byTool = ((.byTool // 0) + ($ids | length)) | .holds = 0 | .holdSeq = (.journal | map(.seq) | max // 0) | .released = true
      else del(.released) end' "$side" > "$side.hold" 2>/dev/null || { rm -f "$side.hold"; ticks_unlock; return 2; }
  local r; r="$(jq -r '.released // false' "$side.hold" | tr -d '\r')"
  jq 'del(.released)' "$side.hold" | ticks_write "$side"; rm -f "$side.hold"
  ticks_unlock; ticks_register "$1"
  [ "$r" = true ] && return 0 || return 1
}

# The file the session reads: the view of the cut as written, with the line that names the list to close in.
cutlist_read_file() { # view, read file
  { head -n 1 "$1"; printf '\nList of this cut: %s - close its boxes there; this file is not updated.\n' "$1"
    tail -n +2 "$1"; } > "$2.tmp" && mv -f "$2.tmp" "$2"
}
# The list a read file names, nothing where it names none.
cutlist_of() { # read file
  local l; l="$(grep -m 1 '^List of this cut: ' "$1" 2>/dev/null | tr -d '\r')" || return 0
  l="${l#List of this cut: }"; printf '%s' "${l%% - close its boxes there*}"
}

# The boxes the lists before a cut carry on (open or "[u]"), one candidate per key for the match against the carriers
# of the cut (state_match_held): {key, art, text}, one per line.
cutlist_carried() { # side lists before the cut ('' ones are skipped)
  local o olds=()
  for o in "$@"; do [ -n "$o" ] && [ -s "$o" ] && olds+=("$o"); done
  [ ${#olds[@]} -gt 0 ] || return 0
  # A changed carrier and a missing instruction are no sentence a carrier holds; their key returns with a fresh box.
  jq -nc "$ticks_state_jq"' [inputs | with_state | .boxes[]
      | select(.state != "x" and .kind != "changed" and .kind != "instruction")] | unique_by(.key)[]
    | {key, art: (.kind // "carried"), text: (.core // .title)}' "${olds[@]}" | tr -d '\r'
}
