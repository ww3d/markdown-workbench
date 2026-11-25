# shellcheck shell=bash
# shellcheck disable=SC2034 # r_* globals are the results the callers read
# Sourced by ticks.sh and the tools built on it, never run: what changed at a carrier since the last stand, and
# what a reference given as evidence really is (ww3d/playbook#688, decision log
# docs/decisions/2026-11-21T0002Z-playbook-688-tick-guard-decisions.md, decision 2).
#
# Needs bash, jq and gh. Server times only: a commit is never judged by its git date. Every call to the forge or
# the channel ends after TICKS_TIMEOUT seconds (default 20); an unreachable source is reported, never guessed.
# shellcheck source=SCRIPTDIR/tempdir.sh
. "${BASH_SOURCE[0]%/*}/tempdir.sh"
hook_tmpdir || true # the temp folder is made known once, a subshell inherits it

# The normal form of a text for "changed or not": no whitespace at all, every tick box the same. A change that
# only moves whitespace or switches "- [ ]" and "- [x]" keeps the hash.
# shellcheck disable=SC2016 # jq text, not shell
resolve_norm_jq='def tnorm: (. // "") | gsub("[[][xX ][]]"; "[]") | gsub("[[:space:]]+"; "");
  def first_line: (. // "") | gsub("\r"; "") | split("\n") | map(select(test("[^[:space:]]"))) | (.[0] // "") | .[0:120];
  def utc: if type != "string" then . else . as $s
    | (capture("^(?<b>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})([.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$") // null) as $m
    | if $m == null then $s elif $m.z == "Z" then $m.b + "Z"
      else ($m.b + "Z" | fromdateiso8601) - (($m.z[0:1] + "1" | tonumber) * (($m.z[1:3] | tonumber) * 3600 + ($m.z[-2:] | tonumber) * 60))
        | todateiso8601 end end;'

resolve_timeout() { printf '%s' "${TICKS_TIMEOUT:-20}"; }

# The reason of the last failed call. Most calls run in a command substitution, where r_err would not reach the
# caller, so it also stands in a file of this process; resolve_cleanup removes it.
r_err=""
resolve_errfile() { printf '%s/resolve-err.%s' "${hook_tmp:-/dev/null}" "$$"; }
resolve_set_err() { r_err="$1"; printf '%s' "$1" > "$(resolve_errfile)" 2>/dev/null || true; }
resolve_lasterr() { cat "$(resolve_errfile)" 2>/dev/null || printf '%s' "$r_err"; }
resolve_cleanup() { rm -f "$(resolve_errfile)"; }

# One forge call under the time limit. Exit 0 with the output on stdout; 4 when the object does not exist
# (404, 410, 422); 3 when the forge is not reachable or the limit ran out. The reason: resolve_lasterr.
resolve_gh() { # gh arguments...
  local out errf rc why
  errf="$(hook_mktemp resolve-err)" || errf=/dev/null
  out="$(timeout "$(resolve_timeout)" gh "$@" 2>"$errf")"; rc=$?
  why="$(head -c 300 "$errf" | tr -d '\r' | tr '\n' ' ')"; [ "$errf" = /dev/null ] || rm -f "$errf"
  if [ "$rc" -eq 0 ]; then printf '%s' "$out"; return 0; fi
  if [ "$rc" -eq 124 ]; then resolve_set_err "no answer within $(resolve_timeout) s"; return 3; fi
  resolve_set_err "${why:-gh exit $rc}"
  case "$why" in *"HTTP 404"*|*"HTTP 410"*|*"HTTP 422"*|*"Not Found"*|*"No commit found"*) return 4 ;; esac
  return 3
}

# The login the session writes as, asked once per process.
resolve_self() {
  if [ -z "${r_self:-}" ]; then
    r_self="$(resolve_gh api user --jq .login)" || return $?
    r_self="${r_self//$'\r'/}"; r_self="${r_self//$'\n'/}"
  fi
  printf '%s' "$r_self"
}

# A reference as a kind and its parts: question qNNN, issue or pull request owner/repo#N (or its URL), comment
# (the URL with #issuecomment-ID), commit owner/repo@sha (or its URL). Exit 1 for anything else.
resolve_ref() { # text
  local t="${1%$'\r'}" re
  r_kind=bad r_repo="" r_num="" r_id="" r_sha="" r_q="" r_norm=""
  re='^q([0-9]{1,6})$'
  if [[ $t =~ $re ]]; then r_kind=question; r_q="q${BASH_REMATCH[1]}"; r_norm="$r_q"; return 0; fi
  re='^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)#issuecomment-([0-9]+)$'
  if [[ $t =~ $re ]]; then
    r_kind=comment; r_repo="${BASH_REMATCH[1]}"; r_num="${BASH_REMATCH[3]}"; r_id="${BASH_REMATCH[4]}"
    r_norm="$r_repo#$r_num#issuecomment-$r_id"; return 0
  fi
  re='^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)/?$'
  if [[ $t =~ $re ]]; then r_kind=issue; r_repo="${BASH_REMATCH[1]}"; r_num="${BASH_REMATCH[3]}"; r_norm="$r_repo#$r_num"; return 0; fi
  re='^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/commit/([0-9a-f]{7,40})$'
  if [[ $t =~ $re ]]; then r_kind=commit; r_repo="${BASH_REMATCH[1]}"; r_sha="${BASH_REMATCH[2]}"; r_norm="$r_repo@$r_sha"; return 0; fi
  re='^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)$'
  if [[ $t =~ $re ]]; then r_kind=issue; r_repo="${BASH_REMATCH[1]}"; r_num="${BASH_REMATCH[2]}"; r_norm="$r_repo#$r_num"; return 0; fi
  re='^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{7,40})$'
  if [[ $t =~ $re ]]; then r_kind=commit; r_repo="${BASH_REMATCH[1]}"; r_sha="${BASH_REMATCH[2]}"; r_norm="$r_repo@$r_sha"; return 0; fi
  return 1
}

# Every carrier reference in a text, once each, in order: owner/repo#N, the GitHub URL of an issue or pull
# request, qNNN.
resolve_refs_in() { # text -> one reference per line
  printf '%s\n' "$1" \
    | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(issues|pull)/[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|(^|[^A-Za-z0-9_])q[0-9]{3,6}\b' \
    | sed -E 's#^https://github\.com/([^/]+/[^/]+)/(issues|pull)/([0-9]+)$#\1\#\3#; s/^[^A-Za-z0-9_]?(q[0-9]+)$/\1/' | awk '!seen[$0]++'
}

# --- the stand of the carriers ---------------------------------------------------------------------------------
# One GraphQL query per 50 issues or pull requests (aliases), a channel call per question. The stand per carrier:
# updatedAt, state, body hash, the body edits, the newest 50 comments (server id, createdAt, lastEditedAt, author,
# editor, hash of the cleaned text, first line, URL) and the newest 30 timeline events of the kinds that matter.
resolve_select='__typename updatedAt state body
  userContentEdits(last:10){ nodes { editedAt editor{login} } }
  comments(last:50){ nodes { databaseId id url createdAt lastEditedAt author{login} editor{login} body } }
  timelineItems(last:30, itemTypes:[CLOSED_EVENT,REOPENED_EVENT,CROSS_REFERENCED_EVENT,REFERENCED_EVENT,LABELED_EVENT,UNLABELED_EVENT,COMMENT_DELETED_EVENT,RENAMED_TITLE_EVENT]) {
    nodes { __typename
      ... on ClosedEvent { id createdAt actor{login} }
      ... on ReopenedEvent { id createdAt actor{login} }
      ... on CrossReferencedEvent { id createdAt actor{login} source { __typename ... on Issue { url } ... on PullRequest { url } } }
      ... on ReferencedEvent { id createdAt actor{login} commit { oid } }
      ... on LabeledEvent { id createdAt actor{login} }
      ... on UnlabeledEvent { id createdAt actor{login} }
      ... on CommentDeletedEvent { id createdAt actor{login} deletedCommentAuthor{login} }
      ... on RenamedTitleEvent { id createdAt actor{login} } } }'

# GraphQL answer of one batch -> {ref: stand}, the cleaned texts still in _n and _bn (hashed below).
# shellcheck disable=SC2016 # jq text, not shell
resolve_batch_jq='
  def ev: { id, t: .__typename, at: .createdAt, actor: (.actor.login // null) }
    + (if .__typename == "CrossReferencedEvent" then { src: (.source.url // null) }
       elif .__typename == "ReferencedEvent" then { oid: (.commit.oid // null) }
       elif .__typename == "CommentDeletedEvent" then { victim: (.deletedCommentAuthor.login // null) } else {} end);
  . as $r | [ $refs | to_entries[] | .value as $ref | ($r.data["a\(.key)"].issueOrPullRequest? // null) as $n
    | { key: $ref, value: (if $n == null then { error: "not found" } else {
          type: $n.__typename, updatedAt: $n.updatedAt, state: $n.state, _bn: ($n.body | tnorm),
          edits: [ $n.userContentEdits.nodes[]? | { at: .editedAt, by: (.editor.login // null) } ],
          window: (if ($n.comments.nodes | length) >= 50 then $n.comments.nodes[0].createdAt else null end),
          comments: ([ $n.comments.nodes[]? | { key: (.databaseId | tostring), value: {
            c: .createdAt, e: .lastEditedAt, a: (.author.login // null), ed: (.editor.login // null),
            f: (.body | first_line), u: .url, node: .id, _n: (.body | tnorm) } } ] | from_entries),
          events: [ $n.timelineItems.nodes[]? | select(.id != null) | ev ]
        } end) } ] | from_entries'

# Hash every cleaned text of a stand in one sha256sum call, reusing the old hash where nothing moved.
resolve_hash_stand() { # stand file (with _n/_bn), old snapshot file ('' or missing) -> the stand without them on stdout
  local stand="$1" old="$2" dir
  [ -s "$old" ] || old=/dev/null
  dir="$(hook_mktemp -d resolve-hash)" || return 2; mkdir "$dir/t"; : > "$dir/keys"; : > "$dir/hash"
  { cat "$old" 2>/dev/null; echo "{}"; } > "$dir/old"
  # One file per text still to hash, named by a running number; number -> JSON path in keys.
  jq -r --slurpfile o "$dir/old" '
    ($o[0] // {}) as $old
    | to_entries[] | .key as $ref | .value as $v | select($v.error == null)
    | ( (if ($old[$ref].bh != null and $old[$ref].updatedAt == $v.updatedAt) then empty
         else [[$ref, "_bn"], $v._bn] end),
        ($v.comments | to_entries[] | .key as $id
         | if ($old[$ref].comments[$id].h != null and $old[$ref].comments[$id].e == .value.e) then empty
           else [[$ref, "comments", $id, "_n"], .value._n] end) )
    | "\(.[0] | @json)\t\(.[1])"' "$stand" 2>/dev/null \
    | tr -d '\r' | awk -F'\t' -v d="$dir" '{ n++; print n "\t" $1 > (d "/keys"); f = d "/t/" n; printf "%s", $2 > f; close(f) }'
  if [ -s "$dir/keys" ]; then
    # "<hash>  <name>" from GNU in text mode, "<hash> *<name>" in binary mode (Git for Windows)
    (cd "$dir/t" && sha256sum -- *) | tr -d '\r' | sed -E 's/^([0-9a-f]{64}) [ *](.*)$/\2\t\1/' > "$dir/hash"
  fi
  jq --slurpfile o "$dir/old" --rawfile k "$dir/keys" --rawfile h "$dir/hash" '
    ($o[0] // {}) as $old
    | ($h | split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1]}) | from_entries) as $hash
    | reduce ($k | split("\n")[] | select(length > 0) | split("\t") | {n: .[0], p: (.[1] | fromjson)}) as $x (.;
        setpath($x.p[0:-1] + [if $x.p[-1] == "_bn" then "bh" else "h" end]; $hash[$x.n]))
    | with_entries(.key as $ref | .value |= (
        if .error != null then . else
          (if .bh == null then .bh = $old[$ref].bh else . end)
          | .comments |= with_entries(.key as $id
              | .value |= ((if .h == null then .h = $old[$ref].comments[$id].h else . end) | del(._n)))
          | del(._bn) end))' "$stand"
  rm -rf "$dir"
}

resolve_json_list() { printf '%s\n' "$@" | jq -R . | jq -sc .; } # words -> JSON array

# One batch of resolve_snapshot into <tmp>/h<i>.json: the stand of each carrier, or {error} for all of them.
resolve_snapshot_batch() { # tmp dir, batch number, old snapshot file, refs...
  local tmp="$1" i="$2" old="$3" q="query {" j=0 ref name body refs_json; shift 3
  for ref in "$@"; do
    name="${ref#*/}"; name="${name%%#*}"
    q+=" a$j: repository(owner:\"${ref%%/*}\", name:\"$name\") { issueOrPullRequest(number:${ref##*#}) {"
    q+=" ... on Issue { $resolve_select } ... on PullRequest { $resolve_select } } }"
    j=$((j + 1))
  done
  q+=" }"
  refs_json="$(resolve_json_list "$@")"
  printf '%s' "$q" > "$tmp/q$i" # as a file: 50 carriers pass the 32 767 characters of a Windows command line
  if body="$(resolve_gh api graphql -F query=@"$tmp/q$i")" \
     && printf '%s' "$body" | jq --argjson refs "$refs_json" "$resolve_norm_jq $resolve_batch_jq" > "$tmp/b$i.json" 2>/dev/null; then
    resolve_hash_stand "$tmp/b$i.json" "$old" > "$tmp/h$i.json"
  else
    jq -n --arg e "not reachable: $(r="$(resolve_lasterr)"; printf "%s" "${r:-answer not readable}")" --argjson refs "$refs_json" \
      '[$refs[] | {key: ., value: {error: $e}}] | from_entries' > "$tmp/h$i.json"
  fi
}

# The stand of the given carriers as one JSON object on stdout. Issues and pull requests over GraphQL in batches of
# 50; questions over the channel. A batch that fails marks each of its carriers {error}, never a guessed stand.
resolve_snapshot() { # old snapshot file ('' for none), refs... -> JSON on stdout
  local old="$1"; shift
  local gh_refs=() q_refs=() ref tmp i q
  for ref in "$@"; do
    resolve_ref "$ref" || continue
    case "$r_kind" in issue) gh_refs+=("$r_norm") ;; question) q_refs+=("$r_q") ;; esac
  done
  tmp="$(hook_mktemp -d resolve-snap)" || return 2; : > "$tmp/parts"
  # Up to four batches at once: GitHub answers a batch of 50 in about 5-10 s (measured 2026-11-21), the rest waits.
  for ((i = 0; i < ${#gh_refs[@]}; i += 50)); do
    [ "$(jobs -rp | wc -l)" -lt 4 ] || wait -n
    resolve_snapshot_batch "$tmp" "$i" "$old" "${gh_refs[@]:i:50}" &
  done
  wait
  for ((i = 0; i < ${#gh_refs[@]}; i += 50)); do printf '%s\n' "$tmp/h$i.json" >> "$tmp/parts"; done
  for q in "${q_refs[@]}"; do
    resolve_question "$q" > "$tmp/$q.json"
    printf '%s\n' "$tmp/$q.json" >> "$tmp/parts"
  done
  if [ -s "$tmp/parts" ]; then tr -d '\r' < "$tmp/parts" | xargs jq -s 'add // {}'; else echo '{}'; fi
  rm -rf "$tmp"
}

# A question over the channel: PLAYBOOK_CARRIER_TEXT_CMD status qNNN prints {status, erstelltAm, issue,
# nachrichten: [{at, von, text}]}. Without the channel or its status the stand says so, never guessed.
resolve_question() { # qNNN -> {qNNN: stand} on stdout
  local q="$1" out rc errf why
  if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then
    jq -nc --arg q "$q" '{($q): {error: "not checkable: no channel with status"}}'; return 0
  fi
  errf="$(hook_mktemp resolve-err)" || errf=/dev/null
  out="$(timeout "$(resolve_timeout)" bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ status "$q" 2>"$errf")"; rc=$?
  why="$(head -c 200 "$errf" | tr -d '\r' | tr '\n' ' ')"; [ "$errf" = /dev/null ] || rm -f "$errf"
  [ "$rc" -eq 124 ] && why="no answer within $(resolve_timeout) s"
  if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | jq -e 'type == "object" and has("status")' >/dev/null 2>&1; then
    jq -nc --arg q "$q" --arg w "not checkable: channel without status (${why:-exit $rc})" '{($q): {error: $w}}'; return 0
  fi
  printf '%s' "$out" | jq -c --arg id "$q" "$resolve_norm_jq"'
    {($id): {type: "Question", status: .status, issue: (.issue // null), createdAt: (.erstelltAm // null | utc),
      messages: [ (.nachrichten // [])[] | {at: (.at // null | utc), by: (.von // null), f: (.text // "" | first_line)} ]}}'
}

# --- the changes between two stands ----------------------------------------------------------------------------
# Old and new snapshot plus the server ids the own evidence carries -> {ref: [change]}, a change {carrier, kind,
# serverId, at, author, first, hash}. A carrier the old stand does not know has none (first sight). Whitespace, a
# tick box or a label make none, nor does own evidence; a moved updatedAt nothing explains is one "without detail".
# shellcheck disable=SC2016 # jq text, not shell
resolve_changes_jq='
  def ch($ref; $kind; $id; $at; $by; $f; $h): {carrier: $ref, kind: $kind, serverId: $id, at: $at, author: $by, first: $f, hash: $h};
  def refof: if test("^https://github[.]com/[^/]+/[^/]+/(issues|pull)/[0-9]+$")
    then capture("^https://github[.]com/(?<r>[^/]+/[^/]+)/(issues|pull)/(?<n>[0-9]+)$") | "\(.r)#\(.n)" else . end;
  # Own evidence: its server id, or for a reference event the pull request (as owner/repo#N) or commit it names.
  def mine($own): (if .kind == "crossreferenced" or .kind == "referenced" then [.serverId, ((.first // "") | refof)] else [.serverId] end)
    | any(.[]; . as $x | ($own | index($x)) != null);
  ($own | map(tostring)) as $own
  | $new | with_entries(.key as $ref | .value as $n | ($old[$ref] // null) as $o
    | .value = (if $o == null or $o.error != null or $n.error != null then []
      elif $n.type == "Question" then
        ( (if $o.status != $n.status then [ch($ref; "status"; "\($ref)#status-\($n.status)"; ($n.messages | last | .at) // null; null; "\($o.status) -> \($n.status)"; null)] else [] end)
          + [ $n.messages | to_entries[] | select(.key >= ($o.messages | length))
              | ch($ref; "message"; "\($ref)#msg-\(.key)"; .value.at; .value.by; .value.f; null) ] )
        | map(select(mine($own) | not))
      else
        ($o.updatedAt) as $since
        | [ $n.comments | to_entries[] | .key as $id | .value as $c | ($o.comments[$id] // null) as $oc
            | if $oc == null then (if $c.c > $since then ch($ref; "comment"; $id; $c.c; $c.a; $c.f; $c.h) else empty end)
              elif $oc.h != $c.h then ch($ref; "comment edited"; $id; ($c.e // $c.c); ($c.ed // $c.a); $c.f; $c.h)
              elif $oc.e != $c.e then {trivial: true}
              else empty end ] as $cs
        | [ $o.comments | to_entries[] | select($n.comments[.key] == null and ($n.window == null or .value.c >= $n.window))
            | ch($ref; "deleted"; .key; $n.updatedAt; .value.a; .value.f; .value.h) ] as $gone
        | ($o.events | map(.id)) as $seen
        | [ $n.events[] | select(.at > $since and (.id as $i | $seen | index($i)) == null)
            | if (.t == "LabeledEvent" or .t == "UnlabeledEvent" or .t == "CommentDeletedEvent") then {trivial: true}
              else ch($ref; (.t | sub("Event$"; "") | ascii_downcase); .id; .at; .actor; (.src // .oid // ""); null) end ] as $es
        | (if $o.bh != $n.bh then
             [ch($ref; "text edited"; "\($ref)#body@\(($n.edits | last | .at) // $n.updatedAt)"; ($n.edits | last | .at) // $n.updatedAt; ($n.edits | last | .by); "body"; $n.bh)]
           elif ([$n.edits[] | select(.at > $since)] | length) > 0 then [{trivial: true}] else [] end) as $bs
        | (if $o.state != $n.state and ([$es[] | select(.kind? == "closed" or .kind? == "reopened")] | length) == 0
           then [ch($ref; "state"; "\($ref)#state-\($n.state)@\($n.updatedAt)"; $n.updatedAt; null; "\($o.state) -> \($n.state)"; null)] else [] end) as $ss
        | ($cs + $gone + $es + $bs + $ss) as $all
        | [ $all[] | select(.trivial != true) | select(mine($own) | not) ] as $real
        | if ($real | length) > 0 then $real
          elif $n.updatedAt > $since and ([$all[] | select(.trivial == true or mine($own))] | length) == 0
            then [ch($ref; "without detail"; "\($ref)#updated@\($n.updatedAt)"; $n.updatedAt; null; "updatedAt \($since) -> \($n.updatedAt)"; null)]
          else [] end
      end))'

resolve_changes() { # old snapshot file, new snapshot file, own ids JSON array -> {ref: [change]} on stdout
  jq -n --slurpfile o "$1" --slurpfile n "$2" --argjson own "${3:-[]}" \
    '($o[0] // {}) as $old | ($n[0] // {}) as $new | '"$resolve_changes_jq"
}

# Comments of other authors the session's own account edited or deleted at a carrier after a point in time ->
# [{carrier, kind, serverId, at, author}] on stdout.
resolve_foreign_edits() { # snapshot file, self login, since (ISO)
  jq -c --arg me "$2" --arg since "$3" '[ to_entries[] | .key as $ref | .value | select(.error == null and .type != "Question")
    | ((.comments // {}) | to_entries[] | .value as $c
        | select($c.ed == $me and $c.a != $me and ($c.e // "") > $since)
        | {carrier: $ref, kind: "foreign comment edited", serverId: .key, at: $c.e, author: $c.a}),
      ((.events // [])[] | select(.t == "CommentDeletedEvent" and .actor == $me and (.victim // "") != $me and .at > $since)
        | {carrier: $ref, kind: "foreign comment deleted", serverId: .id, at: .at, author: .victim}) ]' "$1"
}

# --- evidence ----------------------------------------------------------------------------------------------------
# A server time without its fraction, so "…:36.412Z" and "…:36Z" compare as one second.
resolve_iso() { local t="${1%$'\r'}"; t="${t%Z}"; t="${t%%.*}"; [ -z "$t" ] || printf '%sZ' "$t"; }

# Did an issue or pull request reference one of the carriers after a point in time? Read from the carriers'
# timelines ("cross-referenced" with that source); exit 0 yes, 1 no, 3 not reachable.
resolve_crossref() { # source owner/repo#N, after (ISO), carriers JSON array
  local src="$1" after carrier out at url
  after="$(resolve_iso "$2")"
  while IFS= read -r carrier; do
    carrier="${carrier%$'\r'}"
    resolve_ref "$carrier" || continue
    [ "$r_kind" = issue ] || continue
    out="$(resolve_gh api "repos/$r_repo/issues/$r_num/timeline?per_page=100" --paginate \
      --jq '.[] | select(.event == "cross-referenced") | "\(.created_at)\t\(.source.issue.html_url // "")"')" || return 3
    while IFS=$'\t' read -r at url; do
      url="${url%$'\r'}"
      [[ $url =~ ^https://github\.com/([^/]+/[^/]+)/(issues|pull)/([0-9]+)$ ]] || continue
      [ "${BASH_REMATCH[1]}#${BASH_REMATCH[3]}" = "$src" ] && [[ "$(resolve_iso "$at")" > "$after" ]] && return 0
    done <<< "$out"
  done <<< "$(printf '%s' "$3" | jq -r '.[]')"
  return 1
}

resolve_in_list() { printf '%s' "$2" | jq -e --arg x "$1" 'index($x) != null' >/dev/null 2>&1; } # item, JSON array

# Where an issue or pull request as evidence stands: at a carrier, or it cross-referenced one after the change.
resolve_belongs() { # owner/repo#N, after, carriers JSON -> exit 0 yes, 1 no, 3 not reachable
  resolve_in_list "$1" "$3" && return 0
  resolve_crossref "$1" "$2" "$3"
}

resolve_refuse() { jq -nc --arg w "$1" '{ok: false, why: $w}'; }
resolve_unreachable() { jq -nc --arg w "not checkable: $1" '{ok: false, unreachable: true, why: $w}'; }
resolve_answer() { # gh exit, what -> 0 found, 1 refused (printed), 3 not checkable (printed)
  case "$1" in
    0) return 0 ;;
    4) resolve_refuse "$2 does not exist"; return 1 ;;
    *) resolve_unreachable "$2: $(resolve_lasterr)"; return 3 ;;
  esac
}
resolve_after() { # at, after, what -> 0 when at is later, else refused (printed)
  [[ $1 > $2 ]] && return 0
  resolve_refuse "$3 was created at $1, not after the change at $2"; return 1
}
resolve_place() { # exit of resolve_belongs, what
  case "$1" in
    0) return 0 ;;
    1) resolve_refuse "$2 stands at no carrier of the box and referenced none after the change"; return 1 ;;
    *) resolve_unreachable "$2: $(resolve_lasterr)"; return 3 ;;
  esac
}

# One reference given as evidence for a box, judged by server times and place (decision 2). Prints a JSON verdict:
# {ok: true, kind, ref, serverId, author, at, first, url, node} or {ok: false, why}; exit 0 accepted, 1 refused,
# 3 not checkable (forge or channel unreachable, no channel with status).
resolve_evidence() { # reference, change time (ISO), carriers JSON array
  local ref="$1" after carriers="$3" out rc issue at src
  after="$(resolve_iso "$2")"
  if ! resolve_ref "$ref"; then
    resolve_refuse "not a reference: '$ref' (owner/repo#N, its URL, a comment URL, owner/repo@sha or qNNN)"; return 1
  fi
  case "$r_kind" in
    comment)
      # The reference text the journal keeps comes from the server: the issue number in the given URL is not checked.
      out="$(resolve_gh api "repos/$r_repo/issues/comments/$r_id" \
        --jq '{id: (.id|tostring), node: .node_id, url: .html_url, issue: .issue_url, author: .user.login, at: .created_at, body: .body}')"; rc=$?
      resolve_answer "$rc" "comment $r_norm" || return $?
      issue="$(printf '%s' "$out" | jq -r '.issue | capture("repos/(?<r>[^/]+/[^/]+)/issues/(?<n>[0-9]+)$") | "\(.r)#\(.n)"' | tr -d '\r')"
      src="$issue#issuecomment-$(printf '%s' "$out" | jq -r .id | tr -d '\r')"
      at="$(resolve_iso "$(printf '%s' "$out" | jq -r .at | tr -d '\r')")"
      resolve_after "$at" "$after" "comment $src" || return 1
      resolve_belongs "$issue" "$after" "$carriers"; rc=$?
      resolve_place "$rc" "comment $src at $issue" || return $?
      printf '%s' "$out" | jq -c --arg ref "$src" "$resolve_norm_jq"'{ok: true, kind: "comment", ref: $ref, serverId: .id, author, at, first: (.body | first_line), url, node}' ;;
    issue)
      out="$(resolve_gh api "repos/$r_repo/issues/$r_num" \
        --jq '{node: .node_id, url: .html_url, author: .user.login, at: .created_at, title: .title, pr: (.pull_request != null)}')"; rc=$?
      resolve_answer "$rc" "$r_norm" || return $?
      src="$(printf '%s' "$out" | jq -r '.url | capture("github[.]com/(?<r>[^/]+/[^/]+)/(issues|pull)/(?<n>[0-9]+)") | "\(.r)#\(.n)"' | tr -d '\r')"
      at="$(resolve_iso "$(printf '%s' "$out" | jq -r .at | tr -d '\r')")"
      resolve_after "$at" "$after" "$src" || return 1
      resolve_belongs "$src" "$after" "$carriers"; rc=$?
      resolve_place "$rc" "$src" || return $?
      printf '%s' "$out" | jq -c --arg ref "$src" '{ok: true, kind: (if .pr then "pull request" else "issue" end), ref: $ref, serverId: $ref, author, at, first: .title, url, node}' ;;
    commit) resolve_commit_evidence "$after" "$carriers" ;;
    question) resolve_question_evidence "$after" "$carriers" ;;
  esac
}


# One reference given as evidence for a box no carrier held (decision 2, point 10): the object and its text, for the
# caller to find the box's core in. An issue or pull request counts by its text as it stands now (a carrier is older
# than the box, its body was only added to): title, body and comments, at the time of the check. A comment, a commit
# and a question need a server time after the box as well: a commit through a pull request of it, never its git date.
# Prints {ok: true, kind, ref, serverId, author, at, first, url, node, text} or {ok: false, why}; exit as
# resolve_evidence.
resolve_core_evidence() { # reference, box time (ISO), now (ISO)
  local ref="$1" after now="$3" out rc src at body prs n pr
  after="$(resolve_iso "$2")"
  if ! resolve_ref "$ref"; then
    resolve_refuse "not a reference: '$ref' (owner/repo#N, its URL, a comment URL, owner/repo@sha or qNNN)"; return 1
  fi
  case "$r_kind" in
    comment)
      out="$(resolve_gh api "repos/$r_repo/issues/comments/$r_id" \
        --jq '{id: (.id|tostring), node: .node_id, url: .html_url, issue: .issue_url, author: .user.login, at: .created_at, body: .body}')"; rc=$?
      resolve_answer "$rc" "comment $r_norm" || return $?
      src="$(printf '%s' "$out" | jq -r '"\(.issue | capture("repos/(?<r>[^/]+/[^/]+)/issues/(?<n>[0-9]+)$") | "\(.r)#\(.n)")#issuecomment-\(.id)"' | tr -d '\r')"
      at="$(resolve_iso "$(printf '%s' "$out" | jq -r .at | tr -d '\r')")"
      resolve_after "$at" "$after" "comment $src" || return 1
      printf '%s' "$out" | jq -c --arg ref "$src" "$resolve_norm_jq"'{ok: true, kind: "comment", ref: $ref, serverId: .id, author, at, first: (.body | first_line), url, node, text: (.body // "")}' ;;
    issue)
      out="$(resolve_gh api "repos/$r_repo/issues/$r_num" \
        --jq '{node: .node_id, url: .html_url, author: .user.login, title: .title, body: (.body // ""), pr: (.pull_request != null)}')"; rc=$?
      resolve_answer "$rc" "$r_norm" || return $?
      body="$(resolve_gh api "repos/$r_repo/issues/$r_num/comments?per_page=100" --paginate --jq '.[].body')"; rc=$?
      resolve_answer "$rc" "comments of $r_norm" || return $?
      src="$(printf '%s' "$out" | jq -r '.url | capture("github[.]com/(?<r>[^/]+/[^/]+)/(issues|pull)/(?<n>[0-9]+)") | "\(.r)#\(.n)"' | tr -d '\r')"
      # Texts go in on stdin, never the command line: the comments outgrow the Windows limit of 32 KB.
      { printf '%s\n' "$out"; printf '%s' "$body" | jq -Rs .; } | jq -sc --arg ref "$src" --arg at "$now" \
        '.[1] as $c | .[0] | {ok: true, kind: (if .pr then "pull request" else "issue" end), ref: $ref, serverId: $ref, author, at: $at, first: .title, url, node,
          text: (.title + "\n" + .body + "\n" + $c)}' ;;
    commit)
      out="$(resolve_gh api "repos/$r_repo/commits/$r_sha" \
        --jq '{sha, node: .node_id, first: (.commit.message | split("\n")[0]), message: .commit.message, author: (.author.login // null), url: .html_url}')"; rc=$?
      resolve_answer "$rc" "commit $r_norm" || return $?
      src="$r_repo@$(printf '%s' "$out" | jq -r .sha | tr -d '\r')"
      prs="$(resolve_gh api "repos/$r_repo/commits/$r_sha/pulls" --jq '.[].number')"; rc=$?
      resolve_answer "$rc" "pull requests of $src" || return $?
      local repo="$r_repo" unreachable=""
      for n in $prs; do
        n="${n%$'\r'}"
        pr="$(resolve_gh api "repos/$repo/issues/$n" --jq '{at: .created_at, title: .title, body: (.body // "")}')"; rc=$?
        if [ "$rc" -ne 0 ]; then [ "$rc" -eq 4 ] || unreachable="$(resolve_unreachable "$repo#$n: $(resolve_lasterr)")"; continue; fi
        at="$(resolve_iso "$(printf '%s' "$pr" | jq -r .at | tr -d '\r')")"
        [[ $at > $after ]] || continue
        { printf '%s\n' "$out"; printf '%s\n' "$pr"; } | jq -sc --arg ref "$src" --arg at "$at" --arg via "pull request $repo#$n" \
          '.[1] as $pr | .[0] | {ok: true, kind: "commit", ref: $ref, serverId: .sha, author, at: $at, first, url, node, via: $via,
            text: (.message + "\n" + $pr.title + "\n" + $pr.body)}'
        return 0
      done
      if [ -n "$unreachable" ]; then printf '%s' "$unreachable"; return 3; fi
      resolve_refuse "commit $src: no pull request of it was opened after the box at $after"; return 1 ;;
    question)
      local q="$r_q"
      if [ -z "${PLAYBOOK_CARRIER_TEXT_CMD:-}" ]; then resolve_unreachable "$q: no channel with status"; return 3; fi
      out="$(timeout "$(resolve_timeout)" bash -c "$PLAYBOOK_CARRIER_TEXT_CMD"' "$@"' _ status "$q" 2>/dev/null)"; rc=$?
      if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | jq -e 'type == "object" and has("status")' >/dev/null 2>&1; then
        resolve_unreachable "$q: channel without status (exit $rc)"; return 3
      fi
      at="$(printf '%s' "$out" | jq -r "$resolve_norm_jq"'[(.erstelltAm // null | utc), ((.nachrichten // [])[].at // null | utc)] | map(select(. != null)) | max // ""' | tr -d '\r')"
      if [ -z "$at" ] || ! [[ $at > $after ]]; then resolve_refuse "$q: neither created nor a message after the box at $after"; return 1; fi
      printf '%s' "$out" | jq -c --arg q "$q" --arg at "$at" '{ok: true, kind: "question", ref: $q, serverId: $q,
        author: ((.nachrichten // []) | last | .von // null), at: $at, first: ("status " + .status), url: null,
        text: ([.text // "", ((.nachrichten // [])[].text // "")] | join("\n"))}' ;;
  esac
}

# A commit counts only through the server: a "referenced" event with it at a carrier after the change, or a pull
# request of it that counts as evidence itself. Its git date is never read.
resolve_commit_evidence() { # after, carriers JSON
  local after="$1" carriers="$2" repo="$r_repo" sha="$r_sha" norm="$r_norm" out rc carrier ev prs n at unreachable=""
  out="$(resolve_gh api "repos/$repo/commits/$sha" \
    --jq '{sha, node: .node_id, first: (.commit.message | split("\n")[0]), author: (.author.login // null), url: .html_url}')"; rc=$?
  resolve_answer "$rc" "commit $norm" || return $?
  sha="$(printf '%s' "$out" | jq -r .sha | tr -d '\r')"; norm="$repo@$sha"
  while IFS= read -r carrier; do
    carrier="${carrier%$'\r'}"
    resolve_ref "$carrier" || continue
    [ "$r_kind" = issue ] || continue
    ev="$(resolve_gh api "repos/$r_repo/issues/$r_num/timeline?per_page=100" --paginate \
      --jq ".[] | select(.event == \"referenced\" and ((.commit_id // \"\") | startswith(\"$sha\"))) | .created_at")"; rc=$?
    [ "$rc" -eq 0 ] || { resolve_answer "$rc" "timeline of $carrier"; return $?; }
    while IFS= read -r at; do
      at="$(resolve_iso "$at")"
      [ -n "$at" ] || continue
      [[ $at > $after ]] || continue
      printf '%s' "$out" | jq -c --arg ref "$norm" --arg at "$at" --arg c "$carrier" \
        '{ok: true, kind: "commit", ref: $ref, serverId: .sha, author, at: $at, first, url, node, via: ("referenced at " + $c)}'
      return 0
    done <<< "$ev"
  done <<< "$(printf '%s' "$carriers" | jq -r '.[]')"
  prs="$(resolve_gh api "repos/$repo/commits/$sha/pulls" --jq '.[].number')"; rc=$?
  [ "$rc" -eq 0 ] || { resolve_answer "$rc" "pull requests of $norm"; return $?; }
  for n in $prs; do
    n="${n%$'\r'}"
    at="$(resolve_evidence "$repo#$n" "$after" "$carriers")"; rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s' "$out" | jq -c --arg ref "$norm" --arg pr "$repo#$n" --argjson e "$at" \
        '{ok: true, kind: "commit", ref: $ref, serverId: .sha, author, at: $e.at, first, url, node, via: ("pull request " + $pr)}'
      return 0
    fi
    [ "$rc" -ne 3 ] || unreachable="$at"
  done
  if [ -n "$unreachable" ]; then printf '%s' "$unreachable"; return 3; fi
  resolve_refuse "commit $norm: no carrier of the box shows it after the change at $after, nor does a pull request of it"; return 1
}

# A question counts when the channel shows it created or answered after the change and its issue is a carrier.
resolve_question_evidence() { # after, carriers JSON
  local after="$1" carriers="$2" q="$r_q" out at issue
  out="$(resolve_question "$q" | jq -c --arg q "$q" '.[$q]')"
  if printf '%s' "$out" | jq -e '.error != null' >/dev/null 2>&1; then
    printf '%s' "$out" | jq -c '{ok: false, unreachable: true, why: .error}'; return 3
  fi
  issue="$(printf '%s' "$out" | jq -r '.issue // ""' | tr -d '\r')"
  resolve_in_list "$issue" "$carriers" || { resolve_refuse "$q names issue '${issue:-none}', no carrier of the box"; return 1; }
  at="$(printf '%s' "$out" | jq -r '[.createdAt, (.messages[].at)] | map(select(. != null) | sub("[.][0-9]+Z$"; "Z")) | max // ""' | tr -d '\r')"
  if [ -z "$at" ] || ! [[ $at > $after ]]; then resolve_refuse "$q: neither created nor a message after the change at $after"; return 1; fi
  printf '%s' "$out" | jq -c --arg q "$q" --arg at "$at" \
    '{ok: true, kind: "question", ref: $q, serverId: $q, author: (.messages | last | .by // null), at: $at, first: ("status " + .status), url: null}'
}

# The evidence objects again after the tick: edited since, or gone? GraphQL by node id, 100 per query; the query goes
# as a file, since a command line on Windows ends at 32 767 characters.
# Input: a file with a JSON array of {key, node}; output {key: {gone, editedAt}} on stdout; exit 3 when unreachable.
resolve_recheck() { # items file
  local items="$1" n i tmp body rc
  n="$(jq 'length' "$items" | tr -d '\r')"
  [ "${n:-0}" -gt 0 ] || { echo '{}'; return 0; }
  tmp="$(hook_mktemp -d resolve-edits)" || return 2
  for ((i = 0; i < n; i += 100)); do
    jq -r --argjson i "$i" '"query { " + ([.[$i:$i + 100] | to_entries[] | "e\(.key): node(id: \(.value.node | @json)) { ... on IssueComment { lastEditedAt } ... on Issue { lastEditedAt } ... on PullRequest { lastEditedAt } }"] | join(" ")) + " }"' \
      "$items" > "$tmp/q"
    # gh exits non-zero when a node is gone, with the partial answer on stdout: still read.
    body="$(timeout "$(resolve_timeout)" gh api graphql -F query=@"$tmp/q" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 124 ] || ! printf '%s' "$body" | jq -e '.data' >/dev/null 2>&1; then
      rm -rf "$tmp"; resolve_set_err "no readable answer"; return 3
    fi
    printf '%s' "$body" | jq -c --slurpfile it "$items" --argjson i "$i" '. as $r | [ $it[0][$i:$i + 100] | to_entries[]
      | ($r.data["e\(.key)"]) as $d | { key: .value.key, value: { gone: ($d == null), editedAt: ($d.lastEditedAt // null) } } ]
      | from_entries' >> "$tmp/out"
  done
  jq -sc 'add // {}' "$tmp/out"; rm -rf "$tmp"
}
