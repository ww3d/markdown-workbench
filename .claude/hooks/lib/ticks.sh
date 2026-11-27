# shellcheck shell=bash
# Sourced by ticks.sh, never run: a list of boxes that only the tool closes, each closing checked against the server
# (ww3d/playbook#688, decision log docs/decisions/2026-11-21T0002Z-playbook-688-tick-guard-decisions.md, decisions
# 1-3). A list is <name>.md (the view) and <name>.json (the side list: boxes, carriers, changes, journal); only this
# tool writes the side list. A box counts as closed only through its journal entry: a "[x]" written by hand is open.
#
# Side list: {version, title, intro, created, boxes: [{id, key, title, carriers, lines, changes: [{id, carrier, kind,
# serverId, at, author, first, hash}]}], sections: [{title, lines}], notes: [text], journal: [{seq, box, how, ...}]}.
# how: done (erledigt), read (gelesen), released (abgelegt, only in the list of a cut), unchecked (ungeprueft),
# uncheckable (nicht pruefbar), reopened.

# shellcheck source=SCRIPTDIR/tempdir.sh
. "${BASH_SOURCE[0]%/*}/tempdir.sh"
hook_tmpdir || true # the temp folder is made known once, a subshell inherits it
ticks_now() { if [ -n "${TICKS_NOW:-}" ]; then printf '%s' "$TICKS_NOW"; else date -u +%Y-%m-%dT%H:%M:%SZ; fi; }
ticks_side() { printf '%s.json' "${1%.md}"; } # view -> side list
ticks_project() { printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}"; }
ticks_registry() { printf '%s/.agent/state/ticks/open' "$(ticks_project)"; }
ticks_abs() { case "$1" in /*|[A-Za-z]:[/\\]*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "${1#./}" ;; esac; }

# One spelling per list for the registry: D:\x, D:/x and /D/x name one file on Windows and become /d/x.
ticks_canon() { # absolute path
  local p="${1//\\//}" win="${MSYSTEM:-}" d
  case "$p" in [A-Za-z]:/*) p="/${p:0:1}${p:2}"; win=1 ;; esac
  if [ -n "$win" ] && [[ $p == /[A-Za-z]/* ]]; then d="${p:1:1}"; p="/${d,}${p:2}"; fi
  printf '%s' "$p"
}
# One writer per list: open, close and check hold <side list>.lock while they read, change and write it. A lock whose
# process is gone is taken over; after TICKS_LOCK_WAIT seconds (default 120) the call gives up with exit 2.
ticks_lock() { # side list
  local d="$1.lock" i=0 pid
  until mkdir "$d" 2>/dev/null; do
    pid="$(cat "$d/pid" 2>/dev/null)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$d"; continue; fi
    i=$((i + 1))
    if [ "$i" -gt $(( ${TICKS_LOCK_WAIT:-120} * 10 )) ]; then echo "list locked by process ${pid:-?}: $d" >&2; return 2; fi
    sleep 0.1
  done
  printf '%s' "$$" > "$d/pid"
  ticks_locked="$d"
}
ticks_unlock() { [ -z "${ticks_locked:-}" ] || rm -rf "$ticks_locked"; ticks_locked=""; }

# The state of every box from its journal: the last entry decides; none, or "reopened", is open. An entry that does
# not fit its box (evidence older than the change, ids that are not the box's changes, no reason) does not count.
# shellcheck disable=SC2016 # jq text, not shell
ticks_state_jq='
  def latest_change($b; $created): [$b.changes[]?.at | select(. != null) | sub("[.][0-9]+Z$"; "Z")] | max // ($b.at // $created);
  def fits($b; $created): if .how == "done" then (.evidence.ok == true and ((.evidence.at // .at) | sub("[.][0-9]+Z$"; "Z")) > latest_change($b; $created))
    elif .how == "read" then ((.ids | sort) == ([$b.changes[]?.id] | sort) and ((.sentence // "") | length) > 0)
    elif .how == "unchecked" or .how == "uncheckable" or .how == "released" then ((.reason // "") | length) > 0
    else true end;
  def box_state($b): .created as $l_created | .cut as $l_cut | [.journal[] | select(.box == $b.id)] | last as $e
    | if $e == null or $e.how == "reopened" then "open"
      elif ($e | fits($b; $l_created)) | not then "open"
      elif $e.how == "released" and $l_cut == null then "open"
      elif $e.how == "done" or $e.how == "read" or $e.how == "released" then "x" else "u" end;
  def with_state: . as $l | .boxes |= map(. as $b | .state = ($l | box_state($b)));'

# The view from the side list. Boxes without a section first, each with its changes and plan lines below; then the
# sections in their order, each its lines or its verbatim text, then the boxes that name it as their section.
ticks_render() { # side list file -> view on stdout
  jq -r "$ticks_state_jq"'
    def mark: if .state == "x" then "x" elif .state == "u" then "u" else " " end;
    # A box line quoted in a section (a message, a helper result) is indented: the guard reads marks at line start only.
    def quoted: gsub("(?<l>^|\n)- [[](?<m>.)[]] (?<id>K[0-9]+) "; "\(.l)  - [\(.m)] \(.id) ");
    def boxlines($l): . as $b | ([$l.journal[] | select(.box == $b.id)] | last) as $e
      | "- [\(mark)] \(.id) \(.title)" + (if (.hops // 0) > 0 then " (weitergereicht, \(.hops)x)" else "" end)
        + (if .state == "open" then "" else " -> \($e.text)" end),
        (.changes[]? | "  - \(.id) \(.carrier // "-") \(.kind) \(.at // "-")\(if .author then " " + .author else "" end): \(.first // "")"),
        (.lines[]? | "  - Zeile: \(.)");
    . as $l | with_state | . as $s
    | "# \(.title)", "", (if (.intro // "") != "" then .intro, "" else empty end),
      "Schliessen nur mit dem Werkzeug: bash .claude/hooks/ticks.sh close <Kennung> erledigt <Verweis> | gelesen <Kennungen> <Satz> | ungeprueft <Grund>"
        + (if .cut != null then " | abgelegt <Grund>" else "" end) + ". Ein Haken von Hand zaehlt als offen.", "",
      (.boxes[] | select(.section == null) | boxlines($l)),
      (if (.notes // []) | length > 0 then "", "## Fuer den Menschen", "", (.notes[] | "- \(.)") else empty end),
      (.sections[]? | .title as $t | "", "## \($t)", "",
        (if .text != null then .text | quoted else (.lines[] | "- \(.)" | quoted) end),
        ([$s.boxes[] | select(.section == $t)] | if length > 0 then "", (.[] | boxlines($l)) else empty end))' "$1" | tr -d '\r'
}

ticks_write() { # side list file < new JSON on stdin: written atomically, the view rendered beside it
  local side="$1" tmp
  tmp="$(mktemp "${side}.XXXXXX")" || return 2 # tmp-ok: beside the side list, so the rename stays on one volume
  if ! jq . > "$tmp" || [ ! -s "$tmp" ]; then rm -f "$tmp"; echo "side list not written: $side" >&2; return 2; fi
  mv -f "$tmp" "$side" && ticks_render "$side" > "${side%.json}.md"
}

ticks_open_count() { jq "$ticks_state_jq"' with_state | [.boxes[] | select(.state == "open")] | length' "$1" 2>/dev/null | tr -d '\r'; }

# Register a list for the guard while it has an open box; drop it when none is left. The entry is named by a hash of
# the absolute path, so two paths never share one and no name starts with a dot.
ticks_register() { # view (absolute)
  local reg name s v; reg="$(ticks_registry)"; v="$(ticks_canon "$1")"; name="$(printf '%s' "$v" | sha256sum | cut -c1-32)"
  # An entry under another spelling of the same path goes; the canonical one stands for it.
  [ "$v" = "$1" ] || rm -f "$reg/$(printf '%s' "$1" | sha256sum | cut -c1-32)"
  # The list of an earlier cut warns about nothing: its boxes that did not end stand in the newer list of its session.
  case "$v" in */.agent/state/ticks/*/cut-*.md) s="${v%/cut-*}" ;; *) s="" ;; esac
  if [ -n "$s" ] && [ "$(ticks_canon "$(cutlist_latest_in "$s")")" != "$v" ]; then rm -f "$reg/$name"
  elif [ "$(ticks_open_count "$(ticks_side "$1")")" -gt 0 ]; then
    mkdir -p "$reg" && printf '%s\n' "$v" > "$reg/$name"
  else rm -f "$reg/$name"; fi
}

# A new list from a spec {title, intro, gate?, boxes: [{key, title, carriers, lines, changes, closeWith?, uncheckable?,
# rule?, core?, at?, kind?, section?, judged?}], sections: [{title, lines | text}], notes}: ids K1.. and K<n>.<m>;
# a box the spec marks uncheckable gets its "[u]" entry from the tool. With the list it replaces, a box of the same
# key keeps its journal: a list rebuilt from scratch (session-state.sh save) loses no closing.
ticks_open() { # view, spec file [, the side list it replaces]
  local view="$1" now old=(--argjson old '[]'); now="$(ticks_now)"
  # From the file, never the command line: a list of a few dozen boxes outgrows the Windows limit of 32 KB.
  if [ -n "${3:-}" ] && [ -r "$3" ] && jq -e . "$3" > /dev/null 2>&1; then old=(--slurpfile old "$3"); fi
  jq --arg now "$now" "${old[@]}" '{version: 1, title, intro: (.intro // ""), created: $now, notes: (.notes // []),
      sections: (.sections // []), gate: (.gate // null), cut: (.cut // null), holder: (.holder // null),
      source: (.source // null), closedKeys: (.closedKeys // null), carried: (.carried // null),
      boxes: [.boxes | to_entries[] | (.key + 1) as $n | .value | {id: "K\($n)", key: (.key // .title), title,
        carriers: (.carriers // []), lines: (.lines // []), closeWith: (.closeWith // null),
        changes: [(.changes // []) | to_entries[] | .value + {id: "K\($n).\(.key + 1)"}], uncheckable}
        + ({rule, core, at, kind, event, section, judged, hops, answer} | with_entries(select(.value != null)))],
      journal: []}
    | with_entries(select(.value != null))
    | ($old[0] // {boxes: [], journal: []}) as $o
    # A box without a time counts from the list'"'"'s creation; a rebuild keeps it, so a kept closing still fits.
    | .created = ($o.created // .created)
    | .journal = ([.boxes[] | .id as $id | .key as $k | ([$o.boxes[] | select(.key == $k) | .id] | first) as $was
        | if $was == null then empty else ($o.journal[] | select(.box == $was) | .box = $id) end]
      + [.boxes[] | select(.uncheckable != null)
        | {box: .id, how: "uncheckable", reason: .uncheckable, at: $now, by: "tool", text: "nicht pruefbar: \(.uncheckable)"}])
    | .journal |= (to_entries | map(.value + {seq: (.key + 1)}))
    | .boxes |= map(del(.uncheckable)) | if .gate == null then del(.gate) else . end' "$2" | ticks_write "$(ticks_side "$view")" || return 2
  ticks_register "$view"
}

# shellcheck source=SCRIPTDIR/cutlist.sh
. "${BASH_SOURCE[0]%/*}/cutlist.sh"

# --- closing a box ------------------------------------------------------------------------------------------------
# The running tool call, the key the cap of three counts by (ww3d/playbook#750): the process the agent host started
# for it (lib/proc.sh), so a loop or a script of one call shares it and each helper or parallel call has its own.
# Where the process cannot be told, the transcript. Exit 2, the reason on stderr, when neither names the call.
ticks_tool_use() { # box id
  # shellcheck source=SCRIPTDIR/proc.sh
  . "${BASH_SOURCE[0]%/*}/proc.sh" || return 2
  if call_process; then printf 'proc:%s' "$call_proc"; return 0; fi
  ticks_transcript_call "$1"
}
# The tool_use without a tool_result whose command closes this box, the newest by timestamp, in the session's
# transcript (TICKS_TRANSCRIPT, else <CLAUDE_CODE_SESSION_ID>.jsonl under the projects folder) or, without
# TICKS_TRANSCRIPT, one of the eight newest helper transcripts under <sid>/subagents/, since a helper shares the
# session id; five processes whatever the number of helpers (ww3d/playbook#734). The host writes the transcript
# behind the call: no hit is a refusal, never the call before it.
ticks_transcript_call() { # box id
  local tx="${TICKS_TRANSCRIPT:-}" f id="" span files=()
  if [ -z "$tx" ] && [[ ${CLAUDE_CODE_SESSION_ID:-} =~ ^[A-Za-z0-9_-]+$ ]]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl; do
      [ -r "$f" ] && { tx="$f"; break; }
    done
  fi
  if [ -z "$tx" ] || [ ! -r "$tx" ]; then
    echo "$1 not closed: no process of this tool call (CLAUDE_PID) and no readable transcript for the cap of three per tool call: ${tx:-no session transcript (CLAUDE_CODE_SESSION_ID)}" >&2
    return 2
  fi
  if [ -z "${TICKS_TRANSCRIPT:-}" ]; then
    # shellcheck disable=SC2012 # helper transcripts are named agent-<hex>.jsonl; ls -t is the sort by time
    mapfile -t files <<< "$(ls -t "${tx%.jsonl}"/subagents/*.jsonl 2>/dev/null | head -n 8)"
    [ -n "${files[0]}" ] || files=()
  fi
  # The last 400 KB hold the running call almost always; only without a hit the last 4 MB are searched.
  for span in 400000 4000000; do
    id="$(tail -q -c "$span" "${files[@]}" "$tx" 2>/dev/null | grep -F -e 'ticks.sh close' -e '"tool_result"' \
      | jq -R -n -r --arg k "$1" '[inputs | fromjson? | .timestamp as $t | .message.content? | arrays | .[]
          | if .type? == "tool_use" and ((.input.command? // "") | test("ticks[.]sh close( .*)? " + $k + "( |$)"))
            then {use: .id, at: ($t // "")} elif .type? == "tool_result" then {done: .tool_use_id} else empty end]
        | (map(.done // empty | {key: ., value: 1}) | from_entries) as $done
        | map(select(.use != null and $done[.use] == null)) | sort_by(.at) | last | .use // empty' 2>/dev/null | tr -d '\r')"
    [ -z "$id" ] || { printf '%s' "$id"; return 0; }
  done
  echo "$1 not closed: no process of this tool call (CLAUDE_PID), and no running call in the transcript names $1 in a ticks.sh close command - write the box id literally" >&2
  return 2
}

# Does the text hold the core of a box? The comparison of session-state.sh save (state_match in lib/state.sh): up to
# six words as a whole, longer ones by half of their 6-word shingles. Exit 0 found, 1 not found or no core, 2 failed.
ticks_core_found() { # text, core
  local d out
  [ -n "$(printf '%s' "$2" | tr -d '[:space:]')" ] || return 1
  if [ "$(type -t state_match)" != function ]; then
    # shellcheck source=/dev/null # state.sh sources this file: naming it here would loop the analysis
    . "${BASH_SOURCE[0]%/*}/state.sh" || return 2
  fi
  d="$(hook_mktemp -d ticks-core)" || return 2
  printf '%s\n' "$1" > "$d/evidence.md"; printf 'evidence\tevidence\n' > "$d/refs.tsv"
  # The core through stdin: as an argument a core over ~100 KB breaks jq ("Argument list too long"), and an empty
  # core.jsonl would let every evidence pass.
  if ! printf '%s' "$2" | jq -Rsc '{l: 0, ts: "-", art: "core", text: .}' > "$d/core.jsonl" || [ ! -s "$d/core.jsonl" ]; then
    rm -rf "$d"; return 2
  fi
  if ! out="$(state_match "$d" "$d/core.jsonl")"; then rm -rf "$d"; return 2; fi
  rm -rf "$d"
  [ -z "$out" ]
}

# A stand box "<line> — <ref> ist <state>" of the restore file (lib/stale.sh) closes at a carrier of the last save
# once the stand check finds no carrier of that save at odds with <ref> (q1889 a, point 1): fixing the line removes the
# very text a core would need. Evidence JSON on stdout; exit 0 gone, 1 refused, 2 failed, 3 not checkable.
# shellcheck disable=SC2154 # r_kind and r_norm come from resolve_ref in resolve.sh, which every caller sources first
ticks_stale_gone() { # reference, box JSON
  local c judged d hit k cs=()
  if ! resolve_ref "$1" || [ "$r_kind" != issue ]; then resolve_refuse "a stand box closes at its carrier: owner/repo#N"; return 1; fi
  c="$r_norm"; judged="$(printf '%s' "$2" | jq -r '.judged // ""' | tr -d '\r')"
  if ! printf '%s' "$2" | jq -e --arg c "$c" '(.carriers // []) | length == 0 or index($c) != null' >/dev/null; then
    resolve_refuse "$c is no carrier of the last save: $(printf '%s' "$2" | jq -r '.carriers | join(", ")' | tr -d '\r')"; return 1
  fi
  if [ "$(type -t state_stale)" != function ]; then
    # shellcheck source=/dev/null # state.sh sources this file: naming it here would loop the analysis
    . "${BASH_SOURCE[0]%/*}/state.sh" || return 2
  fi
  # The box does not name the carrier its line stands at: every carrier of the last save is checked.
  mapfile -t cs <<< "$(printf '%s' "$2" | jq -r --arg c "$c" '(.carriers // []) | if length == 0 then [$c] else . end | .[]' | tr -d '\r')"
  for k in "${cs[@]}"; do
    d="$(hook_mktemp -d ticks-stale)" || return 2
    if ! state_haystack "$d" "$k" > /dev/null 2> "$d/err"; then resolve_unreachable "$(head -c 200 "$d/err")"; rm -rf "$d"; return 3; fi
    state_stale_lines "$d" "" "$k" > "$d/lines.jsonl"; state_stale "$d/lines.jsonl" "$d" > "$d/found.jsonl"
    if [ -s "$d/stale.note" ]; then resolve_unreachable "$(head -n 1 "$d/stale.note" | tr -d '\r')"; rm -rf "$d"; return 3; fi
    hit="$(jq -r --arg j " — $judged ist " 'select(.text | contains($j)) | .text' "$d/found.jsonl" | head -n 1 | tr -d '\r')"
    rm -rf "$d"
    [ -z "$hit" ] || { resolve_refuse "the contradiction stands at $k: $hit"; return 1; }
  done
  jq -nc --arg c "$c" --arg at "$(ticks_now)" '{ok: true, kind: "stand", ref: $c, at: $at, first: "no contradiction left"}'
}

ticks_norm_sentence() { printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'; }

# Append one journal entry (JSON object without seq) and write the list.
ticks_journal() { # side list, entry JSON
  jq --argjson e "$2" '.journal += [$e + {seq: ((.journal | map(.seq) | max // 0) + 1)}]' "$1" | ticks_write "$1"
}

# close <K> erledigt <ref> | gelesen <ids> <sentence> | ungeprueft <reason>. Exit 0 closed, 1 refused, 2 usage or
# no transcript, 3 set to "[u] nicht pruefbar" because the forge or the channel could not be asked.
ticks_close() { # view, box id, how, arguments...
  local view="$1" id="$2" how="$3" side box tool now entry verdict rc text f=() u n=0 unc=""; shift 3
  side="$(ticks_side "$view")"; now="$(ticks_now)"
  [ -r "$side" ] || { echo "no side list for $view" >&2; return 2; }
  # The box and every field the checks read, in one jq: the box, its state, closeWith, rule, core, the time its
  # evidence must be newer than, then the tool calls of the journal (one per line).
  mapfile -t f <<< "$(jq -r --arg id "$id" "$ticks_state_jq"' with_state | .created as $c | .journal as $j
    | .boxes[] | select(.id == $id) | (tojson, .state, (.closeWith // ""), (.rule // ""),
      (if .rule == "core" then .core // "" | gsub("[\r\n]+"; " ") else "" end),
      (. as $b | ([.changes[]?.at | select(. != null)] | max) // ($b.at // $c)),
      ($j[] | select(.how != "reopened") | .toolUse // ""))' "$side" | tr -d '\r')"
  box="${f[0]:-}"
  [ -n "$box" ] || { echo "no box $id in $view" >&2; return 1; }
  [ "${f[1]}" != x ] || { echo "$id is closed already" >&2; return 1; }
  tool="$(ticks_tool_use "$id")" || return 1
  for u in "${f[@]:6}"; do [ "$u" != "$tool" ] || n=$((n + 1)); done
  [ "$n" -lt 3 ] || { echo "at most three boxes per tool call: $id refused, call the tool again for it" >&2; return 1; }
  # shellcheck disable=SC2154 # r_kind and r_norm come from resolve_ref in resolve.sh, which every caller sources first
  case "$how" in
    erledigt)
      [ $# -eq 1 ] || { echo "usage: close <K> erledigt <reference>" >&2; return 2; }
      resolve_ref "$1" || { echo "not a reference: '$1' (owner/repo#N, its URL, a comment URL, owner/repo@sha or qNNN)" >&2; return 1; }
      if [ "${f[2]}" = question ] && [ "$r_kind" != question ]; then
        echo "refused: $id closes only with the question it asks for: erledigt qNNN" >&2; return 1
      fi
      local after="${f[5]}" core="${f[4]}"
      if [ "${f[3]}" = stale ]; then
        verdict="$(ticks_stale_gone "$1" "$box")"; rc=$?; core="stand"
        [ "$rc" -ne 2 ] || { echo "the stand of $id was not checked" >&2; return 2; }
      elif [ "${f[3]}" = core ]; then
        # A box no carrier held (decision 2, point 10): the evidence counts when it holds the box's core.
        verdict="$(resolve_core_evidence "$1" "$after" "$now")"; rc=$?
        if [ "$rc" -eq 0 ]; then
          ticks_core_found "$(printf '%s' "$verdict" | jq -r .text)" "$core"; case $? in
            0) verdict="$(printf '%s' "$verdict" | jq -c 'del(.text)')" ;;
            1) verdict="$(resolve_refuse "the core of $id is not in $(printf '%s' "$verdict" | jq -r .ref | tr -d '\r'): $core")"; rc=1 ;;
            *) echo "the core of $id was not compared" >&2; return 2 ;;
          esac
        fi
      else
        verdict="$(resolve_evidence "$1" "$after" "$(printf '%s' "$box" | jq -c .carriers)")"; rc=$?
      fi
      case "$rc" in
        0) # One server object, one box: the same comment under another issue number or a short and a long sha is one.
           # A box checked by its core or its stand may share its evidence: each is checked in it on its own.
           if [ -z "$core" ] && jq -e --argjson v "$verdict" --arg id "$id" 'def oid: .node // "\(.kind) \(.serverId)";
               [.journal[] | select(.how == "done" and .box != $id and (.evidence | oid) == ($v | oid))] | length > 0' "$side" >/dev/null; then
             echo "$(printf '%s' "$verdict" | jq -r .ref | tr -d '\r') closes another box of this list already: one reference, one box" >&2; return 1
           fi
           text="$(printf '%s' "$verdict" | jq -r '"\(.kind) \(.ref) von \(.author // "-") \(.at // "-"): \(.first // "")\(if .via then " (" + .via + ")" else "" end)"' | tr -d '\r')"
           entry="$(jq -nc --arg b "$id" --argjson v "$verdict" --arg t "$tool" --arg at "$now" --arg x "$text" \
             '{box: $b, how: "done", ref: $v.ref, evidence: $v, toolUse: $t, at: $at, text: $x}')" ;;
        3) unc=1; text="$(printf '%s' "$verdict" | jq -r .why | tr -d '\r')"
           entry="$(jq -nc --arg b "$id" --arg r "$text" --arg t "$tool" --arg at "$now" \
             '{box: $b, how: "uncheckable", reason: $r, toolUse: $t, at: $at, by: "tool", text: ("nicht pruefbar: " + $r)}')" ;;
        *) echo "refused: $(printf '%s' "$verdict" | jq -r .why | tr -d '\r')" >&2; return 1 ;;
      esac ;;
    gelesen|ungeprueft|abgelegt)
      if [ "$(printf '%s' "$box" | jq -r '.closeWith // ""' | tr -d '\r')" = question ]; then
        echo "refused: $id closes only with the question it asks for: erledigt qNNN" >&2; return 1
      fi ;;&
    gelesen)
      [ $# -ge 2 ] || { echo "usage: close <K> gelesen <ids> <sentence why nothing is to do>" >&2; return 2; }
      local ids="$1" sentence; shift; sentence="$(ticks_norm_sentence "$*")"
      [ -n "$sentence" ] || { echo "usage: close <K> gelesen <ids> <sentence why nothing is to do>: the sentence is empty" >&2; return 2; }
      if ! printf '%s' "$box" | jq -e --arg ids "$ids" '($ids | split("[ ,;]+"; null) | map(select(length > 0)) | sort) == ([.changes[]?.id] | sort)' >/dev/null; then
        echo "refused: gelesen names exactly the changes of $id: $(printf '%s' "$box" | jq -r '[.changes[]?.id] | join(",")' | tr -d '\r')" >&2; return 1
      fi
      if jq -e --arg s "$sentence" --arg id "$id" '[.journal[] | select(.how == "read" and .box != $id and .sentence == $s)] | length > 0' "$side" >/dev/null; then
        echo "refused: the same sentence closes another box: write what holds for $id" >&2; return 1
      fi
      entry="$(jq -nc --arg b "$id" --arg ids "$ids" --arg s "$sentence" --arg t "$tool" --arg at "$now" \
        '{box: $b, how: "read", ids: ($ids | split("[ ,;]+"; null) | map(select(length > 0))), sentence: $s, toolUse: $t, at: $at,
          text: "gelesen: \($ids | split("[ ,;]+"; null) | map(select(length > 0)) | join(", ")); nichts zu tun, weil \($s)"}')" ;;
    ungeprueft)
      local reason; reason="$(ticks_norm_sentence "$*")"
      [ -n "$reason" ] || { echo "usage: close <K> ungeprueft <reason>: the reason is empty" >&2; return 2; }
      entry="$(jq -nc --arg b "$id" --arg r "$reason" --arg t "$tool" --arg at "$now" \
        '{box: $b, how: "unchecked", reason: $r, toolUse: $t, at: $at, text: ("ungeprueft: " + $r)}')" ;;
    abgelegt)
      # No order and no open point (ww3d/playbook#727, question 1856): only in the list of a cut,
      # each with its own reason.
      jq -e '.cut != null' "$side" >/dev/null || { echo "refused: abgelegt only in the list of a cut (.agent/state/ticks/<session>/cut-<n>.md)" >&2; return 1; }
      local reason; reason="$(ticks_norm_sentence "$*")"
      [ -n "$reason" ] || { echo "usage: close <K> abgelegt <reason>: the reason is empty" >&2; return 2; }
      if jq -e --arg r "$reason" --arg id "$id" '[.journal[] | select(.how == "released" and .box != $id and .reason == $r)] | length > 0' "$side" >/dev/null; then
        echo "refused: the same reason sets aside another box: write what holds for $id" >&2; return 1
      fi
      entry="$(jq -nc --arg b "$id" --arg r "$reason" --arg t "$tool" --arg at "$now" \
        '{box: $b, how: "released", reason: $r, toolUse: $t, at: $at, text: ("abgelegt: " + $r)}')" ;;
    *) echo "how: erledigt, gelesen, ungeprueft or abgelegt" >&2; return 2 ;;
  esac
  ticks_journal "$side" "$entry" || return 2
  ticks_register "$view"
  printf '%s %s\n' "$id" "$(printf '%s' "$entry" | jq -r .text | tr -d '\r')"
  [ -z "$unc" ] || return 3
}

# --- check: evidence after the tick, the own account at foreign comments ------------------------------------------
# Reopen a box with one more change (kind, what) so that reading it again needs that change named.
ticks_reopen() { # side list, box id, kind, text, server id
  local side="$1" now; now="$(ticks_now)"
  jq --arg id "$2" --arg k "$3" --arg x "$4" --arg s "$5" --arg now "$now" '
    (.boxes | map(.id) | index($id)) as $i
    | .boxes[$i].changes += [{id: "\($id).\(.boxes[$i].changes | length + 1)", carrier: null, kind: $k, serverId: $s, at: $now, author: null, first: $x}]
    | .journal += [{seq: ((.journal | map(.seq) | max // 0) + 1), box: $id, how: "reopened", reason: "\($k): \($x)", at: $now, by: "tool"}]' "$side" \
    | ticks_write "$side"
}

ticks_check() { # view -> exit 0 every box closed, 1 one open, 2 list not readable, 3 a source not reachable
  local view="$1" side items verdict carriers snap me notes key node what k open why unreached=""
  side="$(ticks_side "$view")"
  jq -e .boxes "$side" >/dev/null 2>&1 || { echo "side list not readable: $side" >&2; return 2; }
  # 1. Evidence edited or deleted after the tick reopens its box. Unreachable, the box goes to "[u]" until a later
  # check reaches the evidence again and restores the tick.
  items="$(hook_mktemp ticks-items)" && verdict="$(hook_mktemp ticks-verdict)" || return 2
  jq -c "$ticks_state_jq"' . as $l | ($l.journal | group_by(.box) | map({key: .[0].box, value: .}) | from_entries) as $j
    | with_state | [.boxes[] | select(.state != "open") | $j[.id] as $es | ($es | last) as $e
      | ([$es[] | select(.how == "done")] | last) as $d
      | select($d != null and $d.evidence.node != null and ($e.how == "done" or ($e.how == "uncheckable" and $e.recheck == true)))
      | {key: .id, node: $d.evidence.node, at: $d.at, ref: $d.ref, retry: ($e.how != "done"), done: $d}]' "$side" > "$items"
  if resolve_recheck "$items" > "$verdict"; then
    while IFS=$'\t' read -r key what node; do
      [ -n "$key" ] || continue
      if [ "$what" = restore ]; then
        ticks_journal "$side" "$(jq -c --arg k "$key" --arg now "$(ticks_now)" '.[] | select(.key == $k)
          | .done + {at: $now, by: "tool", toolUse: "check"} | del(.seq)' "$items")"
        echo "$key evidence reached again: tick restored"; continue
      fi
      ticks_reopen "$side" "$key" "$what" "evidence $node" "$node"
      echo "$key reopened: $what ($node)"
    done <<< "$(jq -rn --slurpfile is "$items" --slurpfile vs "$verdict" '$vs[0] as $v | $is[0][] | . as $e | $v[$e.key] as $r
      | if $r.gone then "\($e.key)\tBeleg geloescht\t\($e.ref)"
        elif ($r.editedAt // "") > $e.at then "\($e.key)\tBeleg nach dem Haken geaendert\t\($e.ref)"
        elif $e.retry then "\($e.key)\trestore\t\($e.ref)" else empty end' | tr -d '\r')"
  else
    why="evidence not checked again: $(resolve_lasterr)"; unreached=1; echo "$why"
    while IFS= read -r key; do
      key="${key%$'\r'}"; [ -n "$key" ] || continue
      ticks_journal "$side" "$(jq -nc --arg b "$key" --arg r "$why" --arg now "$(ticks_now)" \
        '{box: $b, how: "uncheckable", reason: $r, recheck: true, at: $now, by: "tool", text: ("nicht pruefbar: " + $r)}')"
      echo "$key set to [u]: $why"
    done <<< "$(jq -r '.[] | select(.retry | not) | .key' "$items")"
  fi
  rm -f "$items" "$verdict"
  # 2. The own account edited or deleted a comment of another author at a carrier of this list.
  carriers=(); while IFS= read -r k; do k="${k%$'\r'}"; [ -z "$k" ] || carriers+=("$k"); done <<< "$(jq -r '[.boxes[].carriers[]] | unique[]' "$side")"
  if [ ${#carriers[@]} -gt 0 ] && ! me="$(resolve_self)"; then
    unreached=1; echo "own edits not checked: the account is not readable: $(resolve_lasterr)"
  elif [ ${#carriers[@]} -gt 0 ]; then
    snap="$(hook_mktemp ticks-snap)" || return 2; resolve_snapshot "" "${carriers[@]}" > "$snap"
    why="$(jq -r '[to_entries[] | select(.value.error != null) | "\(.key): \(.value.error)"] | join("; ")' "$snap" | tr -d '\r')"
    if [ -n "$why" ]; then unreached=1; echo "own edits not checked at: $why"; fi
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      # Each edit once: the carrier, the comment and the time of this edit; a later edit is a new one.
      key="$(printf '%s' "$k" | jq -r '"\(.carrier) \(.serverId) \(.at)"' | tr -d '\r')"
      jq -e --arg k "$key" '(.noteKeys // []) | index($k) != null' "$side" >/dev/null && continue
      notes="$(printf '%s' "$k" | jq -r --arg me "$me" '"\(.kind) by \($me): \(.carrier) \(.serverId) of \(.author // "-") at \(.at)"' | tr -d '\r')"
      jq --arg n "$notes" --arg k "$key" '.notes += [$n] | .noteKeys = ((.noteKeys // []) + [$k])' "$side" | ticks_write "$side"
      while IFS= read -r b; do
        b="${b%$'\r'}"; [ -n "$b" ] || continue
        ticks_reopen "$side" "$b" "$(printf '%s' "$k" | jq -r .kind | tr -d '\r')" "$notes" "$(printf '%s' "$k" | jq -r .serverId | tr -d '\r')"
        echo "$b reopened: $notes"
      done <<< "$(jq -r --arg c "$(printf '%s' "$k" | jq -r .carrier | tr -d '\r')" '.boxes[] | select(.carriers | index($c)) | .id' "$side")"
    done <<< "$(resolve_foreign_edits "$snap" "$me" "$(jq -r .created "$side" | tr -d '\r')" | jq -c '.[]')"
    rm -f "$snap"
  fi
  ticks_render "$side" > "$view"
  ticks_register "$view"
  open="$(ticks_open_count "$side")"
  echo "$view: ${open:-?} open"
  [ -z "$unreached" ] || return 3
  [ "${open:-1}" -eq 0 ]
}

# --- guard: the Stop check over every registered list -----------------------------------------------------------
# Local only, no network: a box is open while its journal does not close it, and a mark in the view for a box the
# side list does not know is open too. The guard only warns and never holds a turn end (maintainer 2026-11-25T1351Z
# on q1931 a, ww3d/playbook#734): one line with the count and the path per list, once per turn; the boxes stand in
# the file. Drops lists that are done.
# shellcheck disable=SC2016 # jq text, not shell
ticks_guard_jq='with_state | (.boxes | map(.id)) as $ids
  | ([$v | split("\n")[] | capture("^- [[].[]] (?<id>K[0-9]+) ").id] | unique) as $marked
  | ([$marked[] | . as $x | select(($ids | index($x)) == null) | "\(.) (mark by hand, the side list has no such box)"]
     + [.boxes[] | select(.state == "open") | "\(.id) \(.title)"])[]'
ticks_guard_lines() { # view -> one line per open box on stdout
  local side; side="$(ticks_side "$1")"
  if [ ! -f "$side" ]; then printf '? side list missing: %s\n' "$side"; return 0; fi
  jq -r --rawfile v "$1" "$ticks_state_jq $ticks_guard_jq" "$side" 2>/dev/null | tr -d '\r' \
    || { printf '? side list not readable: %s\n' "$side"; }
}
# The open boxes of one list (pb-hook stop, the report after a cut): a number on stdout.
ticks_guard_count() { # view
  ticks_guard_lines "$1" | grep -c . || true
}
ticks_guard() {
  local reg f view out b n lists="" counts="" proj line
  local -A seen=()
  reg="$(ticks_registry)"
  proj="$(ticks_canon "$(ticks_project)")"
  for f in "$reg"/*; do
    [ -f "$f" ] || continue
    view="$(ticks_canon "$(head -n 1 "$f" | tr -d '\r')")"
    # A list registered under a second spelling of its path counts once; the extra entry goes.
    if [ -n "${seen[$view]:-}" ]; then rm -f "$f"; continue; fi
    seen[$view]=1
    # The save list, the restore file and the list of a cut of another session warn only at that session's turn end.
    if [ -n "${TICKS_SESSION:-}" ]; then
      b="${view##*/}"
      case "$b" in *-save.md | *-restore.md) b="${b%-save.md}"; [ "${b%-restore.md}" = "$TICKS_SESSION" ] || continue ;; esac
      case "$view" in */.agent/state/ticks/*/cut-*.md) b="${view%/cut-*}"; [ "${b##*/}" = "$TICKS_SESSION" ] || continue ;; esac
    fi
    # A registered list without its side list counts too: only the tool ends a registration.
    out="$(ticks_guard_lines "$view")"
    if [ -z "$out" ]; then rm -f "$f"; continue; fi
    n="$(printf '%s\n' "$out" | grep -c .)"
    counts="${counts:+$counts$'\n'}$view"$'\t'"$n"
    lists="${lists:+$lists, }$n offene Punkte in ${view#"$proj"/}"
  done
  # No open box: the next one warns again, whatever the count.
  [ -n "$lists" ] || { [ -z "${TICKS_WARNED:-}" ] || rm -f "$TICKS_WARNED"; return 0; }
  # Once per turn: the second stop of a turn has had its word already.
  [ "${TICKS_STOP_ACTIVE:-}" != true ] || return 0
  # Silent while every count equals the one of this session's last warning (TICKS_WARNED, one "<list>\t<n>" line per
  # list; ww3d/playbook#734): it warns again once a count rises or falls, or a list comes or goes.
  if [ -n "${TICKS_WARNED:-}" ]; then
    [ "$counts" != "$(tr -d '\r' 2>/dev/null < "$TICKS_WARNED")" ] || return 0
    mkdir -p "${TICKS_WARNED%/*}" 2>/dev/null; printf '%s\n' "$counts" > "$TICKS_WARNED" 2>/dev/null || true
  fi
  # One short line, at most 200 characters, no box text: the boxes stand only in the file.
  line=", schliessen mit bash .claude/hooks/ticks.sh close"
  [ $((${#lists} + ${#line})) -le 200 ] || lists="${lists:0:$((196 - ${#line}))} ..."
  line="$lists$line"
  # TICKS_PLAIN: the bare line for pb-hook stop, which folds it into its own message without another jq.
  if [ -n "${TICKS_PLAIN:-}" ]; then printf '%s\n' "$line"; else jq -cn --arg l "$line" '{systemMessage: $l}' || true; fi
}

# --- the old format ---------------------------------------------------------------------------------------------
# A list of "- [x] <box> -> <evidence>" lines as the tool before it wrote them, judged by point 6 of the order: the
# same evidence text in two boxes, a reference that does not exist, is older than the change or stands at no carrier
# of the line. Steps without a carrier (the alarm steps, now measured by the tool) and lines the old tool ticked itself
# ("wartet unveraendert") are no evidence of the session and are listed, not judged.
ticks_legacy_check() { # view [, time of the list, UTC] -> one line per box; exit 1 when one is refused
  local view="$1" stamp at bad refused=0 n=0 line box ev title carriers refs ref verdict rc why
  # The old lines carry no change time; the list's own time, given or from its name, stands in: every change of the
  # list is older, so evidence older than the list cannot be the answer to it.
  if [ $# -gt 1 ]; then
    stamp=""; [[ ! $2 =~ ^([0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2})T[0-9]{4}Z$ ]] || stamp="${2//-/}"
    bad="not a time (--at YYYY-MM-DDTHHMMZ): '$2'"
  else
    stamp="$(printf '%s' "${view##*/}" | grep -oE '[0-9]{8}T[0-9]{4}Z' | head -n 1)"
    [ -n "$stamp" ] || { echo "no time in the list name (YYYYMMDDTHHMMZ), name it with --at <UTC>: $view" >&2; return 2; }
    bad="the time in the list name does not exist, name one with --at <UTC>: $view"
  fi
  at="${stamp:0:4}-${stamp:4:2}-${stamp:6:2}T${stamp:9:2}:${stamp:11:2}:00Z"
  # The shape alone takes a 13th month: only a time that reads back as itself exists.
  jq -en --arg t "$at" '($t | fromdateiso8601 | todateiso8601) == $t' > /dev/null 2>&1 || { echo "$bad" >&2; return 2; }
  local dupes; dupes="$(tr -d '\r' < "$view" | awk '/^- \[[xX]\] / { i = index($0, " -> "); if (i) print substr($0, i + 4) }' | sort | uniq -d)"
  # shellcheck disable=SC2094 # the loop and grep -c only read the view, nothing writes it
  while IFS= read -r line; do
    n=$((n + 1)); line="${line%$'\r'}"
    [[ $line =~ ^-\ \[[xX]\]\  ]] || continue
    box="${line#- \[?\] }"; ev="${box#* -> }"; box="${box%% -> *}"; title="${box%% | *}"
    case "$ev" in "wartet unveraendert"*) echo "Z$n tool  $title: ticked by the old tool itself"; continue ;; esac
    if [[ $title == Wecker\ * ]]; then echo "Z$n step  $title: alarm step without a carrier (measured by the tool from now on)"; continue; fi
    if [ -n "$dupes" ] && printf '%s\n' "$dupes" | grep -qxF -- "$ev"; then
      echo "Z$n REFUSED $title: the same evidence text stands in $(grep -cF -- "-> $ev" "$view") boxes"; refused=$((refused + 1)); continue
    fi
    carriers="$(resolve_refs_in "$box" | jq -R . | jq -sc .)"
    refs="$(resolve_refs_in "$ev"; printf '%s\n' "$ev" | grep -oE 'https://github\.com/[^ )]+#issuecomment-[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{7,40}')"
    if [ -z "$refs" ]; then echo "Z$n open  $title: no reference in the evidence, not checkable"; continue; fi
    why="" rc=1
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      verdict="$(resolve_evidence "$ref" "$at" "$carriers")"; rc=$?
      [ "$rc" -eq 0 ] && break
      why="${why:+$why; }$(printf '%s' "$verdict" | jq -r .why | tr -d '\r')"
    done <<< "$refs"
    case "$rc" in
      0) echo "Z$n ok    $title" ;;
      3) echo "Z$n open  $title: $why" ;;
      *) echo "Z$n REFUSED $title: $why"; refused=$((refused + 1)) ;;
    esac
  done < "$view"
  echo "refused: $refused"
  [ "$refused" -eq 0 ]
}
