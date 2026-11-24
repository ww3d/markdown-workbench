# shellcheck shell=bash
# Sourced by ticks.sh, never run: a list of boxes that only the tool closes, each closing checked against the server
# (ww3d/playbook#688, decision log docs/decisions/2026-11-21T0002Z-playbook-688-tick-guard-decisions.md, decisions
# 1-3). A list is <name>.md (the view) and <name>.json (the side list: boxes, carriers, changes, journal); only this
# tool writes the side list. A box counts as closed only through its journal entry: a "[x]" written by hand is open.
#
# Side list: {version, title, intro, created, boxes: [{id, key, title, carriers, lines, changes: [{id, carrier, kind,
# serverId, at, author, first, hash}]}], sections: [{title, lines}], notes: [text], journal: [{seq, box, how, ...}]}.
# how: done (erledigt), read (gelesen), unchecked (ungeprueft), uncheckable (nicht pruefbar), reopened.

# shellcheck source=SCRIPTDIR/tempdir.sh
. "${BASH_SOURCE[0]%/*}/tempdir.sh"
hook_tmpdir || true # the temp folder is made known once, a subshell inherits it
ticks_now() { if [ -n "${TICKS_NOW:-}" ]; then printf '%s' "$TICKS_NOW"; else date -u +%Y-%m-%dT%H:%M:%SZ; fi; }
ticks_side() { printf '%s.json' "${1%.md}"; } # view -> side list
ticks_project() { printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}"; }
ticks_registry() { printf '%s/.agent/state/ticks/open' "$(ticks_project)"; }
ticks_abs() { case "$1" in /*|[A-Za-z]:[/\\]*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "${1#./}" ;; esac; }

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
  def latest_change($b; $created): [$b.changes[].at | select(. != null) | sub("[.][0-9]+Z$"; "Z")] | max // $created;
  def fits($b; $created): if .how == "done" then (.evidence.ok == true and ((.evidence.at // .at) | sub("[.][0-9]+Z$"; "Z")) > latest_change($b; $created))
    elif .how == "read" then ((.ids | sort) == ([$b.changes[].id] | sort) and ((.sentence // "") | length) > 0)
    elif .how == "unchecked" or .how == "uncheckable" then ((.reason // "") | length) > 0
    else true end;
  def box_state($b): .created as $l_created | [.journal[] | select(.box == $b.id)] | last as $e
    | if $e == null or $e.how == "reopened" then "open"
      elif ($e | fits($b; $l_created)) | not then "open"
      elif $e.how == "done" or $e.how == "read" then "x" else "u" end;
  def with_state: . as $l | .boxes |= map(. as $b | .state = ($l | box_state($b)));'

# The view from the side list. Boxes first, each with its changes and plan lines below; then the sections.
ticks_render() { # side list file -> view on stdout
  jq -r "$ticks_state_jq"'
    def mark: if .state == "x" then "x" elif .state == "u" then "u" else " " end;
    . as $l | with_state
    | "# \(.title)", "", (if (.intro // "") != "" then .intro, "" else empty end),
      "Schliessen nur mit dem Werkzeug: bash .claude/hooks/ticks.sh close <Kennung> erledigt <Verweis> | gelesen <Kennungen> <Satz> | ungeprueft <Grund>. Ein Haken von Hand zaehlt als offen.", "",
      (.boxes[] | . as $b | ([$l.journal[] | select(.box == $b.id)] | last) as $e
        | "- [\(mark)] \(.id) \(.title)" + (if .state == "open" then "" else " -> \($e.text)" end),
          (.changes[] | "  - \(.id) \(.carrier // "-") \(.kind) \(.at // "-")\(if .author then " " + .author else "" end): \(.first // "")"),
          (.lines[]? | "  - Zeile: \(.)")),
      (if (.notes // []) | length > 0 then "", "## Fuer den Menschen", "", (.notes[] | "- \(.)") else empty end),
      (.sections[]? | "", "## \(.title)", "", (.lines[] | "- \(.)"))' "$1" | tr -d '\r'
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
  local reg name; reg="$(ticks_registry)"; name="$(printf '%s' "$1" | sha256sum | cut -c1-32)"
  if [ "$(ticks_open_count "$(ticks_side "$1")")" -gt 0 ]; then
    mkdir -p "$reg" && printf '%s\n' "$1" > "$reg/$name"
  else rm -f "$reg/$name"; fi
}

# A new list from a spec {title, intro, boxes: [{key, title, carriers, lines, changes, uncheckable?}], sections, notes}:
# ids K1.. and K<n>.<m>; a box the spec marks uncheckable gets its "[u]" entry from the tool.
ticks_open() { # view, spec file
  local view="$1" now; now="$(ticks_now)"
  jq --arg now "$now" '{version: 1, title, intro: (.intro // ""), created: $now, notes: (.notes // []), sections: (.sections // []),
      boxes: [.boxes | to_entries[] | (.key + 1) as $n | .value | {id: "K\($n)", key: (.key // .title), title,
        carriers: (.carriers // []), lines: (.lines // []), closeWith: (.closeWith // null),
        changes: [(.changes // []) | to_entries[] | .value + {id: "K\($n).\(.key + 1)"}], uncheckable}],
      journal: []}
    | .journal = [.boxes | to_entries[] | select(.value.uncheckable != null)
        | {seq: (.key + 1), box: .value.id, how: "uncheckable", reason: .value.uncheckable, at: $now, by: "tool",
           text: "nicht pruefbar: \(.value.uncheckable)"}]
    | .boxes |= map(del(.uncheckable))' "$2" | ticks_write "$(ticks_side "$view")" || return 2
  ticks_register "$view"
}

# --- closing a box ------------------------------------------------------------------------------------------------
# The running tool call of the session: the last tool_use id in its transcript (decision 3). The transcript is
# TICKS_TRANSCRIPT, else <CLAUDE_CODE_SESSION_ID>.jsonl under the projects folder. Exit 2 when none is readable.
ticks_tool_use() {
  local tx="${TICKS_TRANSCRIPT:-}" f id
  if [ -z "$tx" ] && [[ ${CLAUDE_CODE_SESSION_ID:-} =~ ^[A-Za-z0-9_-]+$ ]]; then
    for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl; do
      [ -r "$f" ] && { tx="$f"; break; }
    done
  fi
  if [ -z "$tx" ] || [ ! -r "$tx" ]; then echo "transcript not readable: ${tx:-no session transcript (CLAUDE_CODE_SESSION_ID)}" >&2; return 2; fi
  id="$(tail -c 4000000 "$tx" | grep -oE '"type":"tool_use","id":"[^"]+"|"id":"toolu_[A-Za-z0-9_]+"' | tail -n 1 | sed -E 's/.*"id":"([^"]+)"$/\1/')"
  [ -n "$id" ] || { echo "transcript without a tool call: $tx" >&2; return 2; }
  printf '%s' "$id"
}

ticks_norm_sentence() { printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'; }

# Append one journal entry (JSON object without seq) and write the list.
ticks_journal() { # side list, entry JSON
  jq --argjson e "$2" '.journal += [$e + {seq: ((.journal | map(.seq) | max // 0) + 1)}]' "$1" | ticks_write "$1"
}

# close <K> erledigt <ref> | gelesen <ids> <sentence> | ungeprueft <reason>. Exit 0 closed, 1 refused, 2 usage or
# no transcript, 3 set to "[u] nicht pruefbar" because the forge or the channel could not be asked.
ticks_close() { # view, box id, how, arguments...
  local view="$1" id="$2" how="$3" side box tool n now entry verdict rc text; shift 3
  side="$(ticks_side "$view")"; now="$(ticks_now)"
  [ -r "$side" ] || { echo "no side list for $view" >&2; return 2; }
  box="$(jq -c --arg id "$id" "$ticks_state_jq"' with_state | .boxes[] | select(.id == $id)' "$side" | tr -d '\r')"
  [ -n "$box" ] || { echo "no box $id in $view" >&2; return 1; }
  [ "$(printf '%s' "$box" | jq -r .state | tr -d '\r')" != x ] || { echo "$id is closed already" >&2; return 1; }
  tool="$(ticks_tool_use)" || { echo "no closing without the transcript (at most three per tool call)" >&2; return 1; }
  n="$(jq --arg t "$tool" '[.journal[] | select(.toolUse == $t and .how != "reopened")] | length' "$side" | tr -d '\r')"
  [ "$n" -lt 3 ] || { echo "at most three boxes per tool call: $id refused, call the tool again for it" >&2; return 1; }
  # shellcheck disable=SC2154 # r_kind and r_norm come from resolve_ref in resolve.sh, which every caller sources first
  case "$how" in
    erledigt)
      [ $# -eq 1 ] || { echo "usage: close <K> erledigt <reference>" >&2; return 2; }
      resolve_ref "$1" || { echo "not a reference: '$1' (owner/repo#N, its URL, a comment URL, owner/repo@sha or qNNN)" >&2; return 1; }
      if [ "$(printf '%s' "$box" | jq -r '.closeWith // ""' | tr -d '\r')" = question ] && [ "$r_kind" != question ]; then
        echo "refused: $id closes only with the question it asks for: erledigt qNNN" >&2; return 1
      fi
      verdict="$(resolve_evidence "$1" "$(printf '%s' "$box" | jq -r --arg c "$(jq -r .created "$side")" '[.changes[].at | select(. != null)] | max // $c' | tr -d '\r')" \
        "$(printf '%s' "$box" | jq -c .carriers)")"; rc=$?
      case "$rc" in
        0) # One server object, one box: the same comment under another issue number or a short and a long sha is one.
           if jq -e --argjson v "$verdict" --arg id "$id" 'def oid: .node // "\(.kind) \(.serverId)";
               [.journal[] | select(.how == "done" and .box != $id and (.evidence | oid) == ($v | oid))] | length > 0' "$side" >/dev/null; then
             echo "$(printf '%s' "$verdict" | jq -r .ref | tr -d '\r') closes another box of this list already: one reference, one box" >&2; return 1
           fi
           text="$(printf '%s' "$verdict" | jq -r '"\(.kind) \(.ref) von \(.author // "-") \(.at // "-"): \(.first // "")\(if .via then " (" + .via + ")" else "" end)"' | tr -d '\r')"
           entry="$(jq -nc --arg b "$id" --argjson v "$verdict" --arg t "$tool" --arg at "$now" --arg x "$text" \
             '{box: $b, how: "done", ref: $v.ref, evidence: $v, toolUse: $t, at: $at, text: $x}')" ;;
        3) text="$(printf '%s' "$verdict" | jq -r .why | tr -d '\r')"
           entry="$(jq -nc --arg b "$id" --arg r "$text" --arg t "$tool" --arg at "$now" \
             '{box: $b, how: "uncheckable", reason: $r, toolUse: $t, at: $at, by: "tool", text: ("nicht pruefbar: " + $r)}')" ;;
        *) echo "refused: $(printf '%s' "$verdict" | jq -r .why | tr -d '\r')" >&2; return 1 ;;
      esac ;;
    gelesen|ungeprueft)
      if [ "$(printf '%s' "$box" | jq -r '.closeWith // ""' | tr -d '\r')" = question ]; then
        echo "refused: $id closes only with the question it asks for: erledigt qNNN" >&2; return 1
      fi ;;&
    gelesen)
      [ $# -ge 2 ] || { echo "usage: close <K> gelesen <ids> <sentence why nothing is to do>" >&2; return 2; }
      local ids="$1" sentence; shift; sentence="$(ticks_norm_sentence "$*")"
      [ -n "$sentence" ] || { echo "usage: close <K> gelesen <ids> <sentence why nothing is to do>: the sentence is empty" >&2; return 2; }
      if ! printf '%s' "$box" | jq -e --arg ids "$ids" '($ids | split("[ ,;]+"; null) | map(select(length > 0)) | sort) == ([.changes[].id] | sort)' >/dev/null; then
        echo "refused: gelesen names exactly the changes of $id: $(printf '%s' "$box" | jq -r '[.changes[].id] | join(",")' | tr -d '\r')" >&2; return 1
      fi
      if jq -e --arg s "$sentence" --arg id "$id" '[.journal[] | select(.how == "read" and .box != $id and .sentence == $s)] | length > 0' "$side" >/dev/null; then
        echo "refused: the same sentence closes another box: write what holds for $id" >&2; return 1
      fi
      entry="$(jq -nc --arg b "$id" --arg ids "$ids" --arg s "$sentence" --arg t "$tool" --arg at "$now" \
        '{box: $b, how: "read", ids: ($ids | split("[ ,;]+"; null) | map(select(length > 0))), sentence: $s, toolUse: $t, at: $at,
          text: "gelesen: \($ids | split("[ ,;]+"; null) | map(select(length > 0)) | join(", ")); nichts zu tun, weil \($s)"}')" ;;
    ungeprueft)
      [ -n "$(ticks_norm_sentence "$*")" ] || { echo "usage: close <K> ungeprueft <reason>: the reason is empty" >&2; return 2; }
      entry="$(jq -nc --arg b "$id" --arg r "$(ticks_norm_sentence "$*")" --arg t "$tool" --arg at "$now" \
        '{box: $b, how: "unchecked", reason: $r, toolUse: $t, at: $at, text: ("ungeprueft: " + $r)}')" ;;
    *) echo "how: erledigt, gelesen or ungeprueft" >&2; return 2 ;;
  esac
  ticks_journal "$side" "$entry" || return 2
  ticks_register "$view"
  printf '%s %s\n' "$id" "$(printf '%s' "$entry" | jq -r .text | tr -d '\r')"
  [ "$(printf '%s' "$entry" | jq -r .how | tr -d '\r')" != uncheckable ] || return 3
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
# side list does not know is open too. Prints the Stop hook's block when anything is open; drops lists that are done.
ticks_guard() {
  local reg f view side listed="" total=0 out lines=()
  reg="$(ticks_registry)"
  for f in "$reg"/*; do
    [ -f "$f" ] || continue
    view="$(head -n 1 "$f" | tr -d '\r')"; side="$(ticks_side "$view")"
    # A registered list without its side list holds too: only the tool ends a registration.
    if [ ! -f "$side" ]; then out="? side list missing: $side (registration $f)"
    elif ! out="$(jq -r --rawfile v "$view" "$ticks_state_jq"' with_state
      | ([.boxes[] | select(.state == "open") | "\(.id) \(.title)"]) as $open
      | (.boxes | map(.id)) as $ids
      | ([$v | split("\n")[] | capture("^- [[][xXu][]] (?<id>K[0-9]+) ") | .id | . as $x | select(($ids | index($x)) == null)
          | "\(.) (mark by hand, the side list has no such box)"]) as $hand
      | ($hand + $open)[]' "$side" 2>/dev/null)"; then out="? side list not readable: $side"; fi
    out="${out//$'\r'/}"
    if [ -z "$out" ]; then rm -f "$f"; continue; fi
    listed="${listed:+$listed, }$view"
    while IFS= read -r line; do lines+=("${line%$'\r'}"); total=$((total + 1)); done <<< "$out"
  done
  [ "$total" -gt 0 ] || return 0
  jq -nc --arg lists "$listed" --argjson n "$total" --args '$ARGS.positional as $b | {
    decision: "block",
    reason: ("\($n) open or unconfirmed boxes in " + $lists + ": " + ($b[0:8] | join("; "))
      + (if $n > 8 then "; ..." else "" end)
      + ". Close each with the tool, at most three per tool call: bash .claude/hooks/ticks.sh close <id> erledigt <reference>"
      + " | gelesen <change ids> <sentence why nothing is to do> | ungeprueft <reason>"
      + (if ($lists | contains(", ")) then " --list <view>" else "" end) + ". A tick written by hand counts as open."),
    systemMessage: ("Tick list open: \($n) boxes in " + $lists + ".")
  }' "${lines[@]}" || true
}

# --- the old format ---------------------------------------------------------------------------------------------
# A list of "- [x] <box> -> <evidence>" lines as the tool before it wrote them, judged by point 6 of the order: the
# same evidence text in two boxes, a reference that does not exist, is older than the change or stands at no carrier
# of the line. Steps without a carrier (the alarm steps, now measured by the tool) and lines the old tool ticked itself
# ("wartet unveraendert") are no evidence of the session and are listed, not judged.
ticks_legacy_check() { # view -> one line per box; exit 1 when one is refused
  local view="$1" stamp at refused=0 n=0 line box ev title carriers refs ref verdict rc why
  # The old lines carry no change time; the list's own time, from its name, stands in: every change of the list is
  # older, so evidence older than the list cannot be the answer to it.
  stamp="$(printf '%s' "${view##*/}" | grep -oE '[0-9]{8}T[0-9]{4}Z' | head -n 1)"
  [ -n "$stamp" ] || { echo "no time in the list name (YYYYMMDDTHHMMZ): $view" >&2; return 2; }
  at="${stamp:0:4}-${stamp:4:2}-${stamp:6:2}T${stamp:9:2}:${stamp:11:2}:00Z"
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
