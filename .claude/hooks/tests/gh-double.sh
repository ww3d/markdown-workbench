#!/usr/bin/env bash
#
# A stand-in for the gh calls of lib/resolve.sh and instance/hour-list.sh, answered from one world file, so the tick
# tool is tested without network and without a clock (ww3d/playbook#688). A section puts a `gh` wrapper that runs
# this script first on PATH.
#
# World ($GH_DOUBLE_WORLD, JSON): {user, issues: {"owner/repo#N": GraphQL node of the issue or pull request plus id,
#   url, author, createdAt, title}, commits: {sha: {sha, commit: {message}, author: {login}, html_url, pulls: [N]}},
#   search: [node], searchMore: true when the search has a next page}. The REST answers (comment, issue, timeline,
#   commit) are derived from it, as the forge would give them. A file "$GH_DOUBLE_WORLD.down" makes every call fail
#   as unreachable; each call is appended to "$GH_DOUBLE_WORLD.calls"; a PATCH of an issue body writes
#   "$GH_DOUBLE_WORLD.patched".
set -uo pipefail
world="${GH_DOUBLE_WORLD:?GH_DOUBLE_WORLD names the world file}"
printf '%s\n' "$*" >> "$world.calls"
[ ! -e "$world.down" ] || { echo "dial tcp: lookup api.github.com: no such host" >&2; exit 1; }
[ "${1:-}" = api ] || { echo "gh-double: only 'gh api' is stood in for: $*" >&2; exit 2; }
shift

method=GET jqf="" query="" path="" bodyfile=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --jq) jqf="$2"; shift 2 ;;
    --paginate) shift ;;
    -f) case "$2" in query=*) query="${2#query=}" ;; esac; shift 2 ;;
    -F) case "$2" in body=@*) bodyfile="${2#body=@}" ;; query=@*) query="$(cat "${2#query=@}")" ;; esac; shift 2 ;;
    *) path="$1"; shift ;;
  esac
done

# "$GH_DOUBLE_WORLD.down-path" holds a part of a path: only calls to such paths fail as unreachable.
if [ -s "$world.down-path" ] && [[ $path == *"$(cat "$world.down-path")"* ]]; then
  echo "dial tcp: lookup api.github.com: no such host" >&2; exit 1
fi

out() { # JSON on stdin -> through --jq when given
  if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi
}
missing() { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }

case "$path" in
  user) jq '{login: .user}' "$world" | out ;;
  graphql)
    if [[ $query == *"search("* ]]; then
      jq '{data: {search: {pageInfo: {hasNextPage: (.searchMore // false)}, nodes: (.search // [])}}}' "$world" | out
    elif [[ $query == *"node(id:"* ]]; then
      # eN: node(id: "X") -> the comment or issue with that node id, null when gone (gh then exits 1).
      pairs="$(printf '%s' "$query" | grep -oE 'e[0-9]+: node\(id: "[^"]+"\)' | sed -E 's/^(e[0-9]+): node\(id: "([^"]+)"\)$/\1 \2/')"
      ans="$(printf '%s\n' "$pairs" | jq -R 'split(" ") | {key: .[0], value: .[1]}' | jq -s --slurpfile w "$world" '
        ($w[0].issues | to_entries | map(.value)) as $is
        | map(.value as $id | {key, value: (([$is[] | select(.id == $id)] + [$is[].comments.nodes[] | select(.id == $id)]) | first
            | if . == null then null else {lastEditedAt: (.lastEditedAt // null)} end)}) | {data: from_entries}')"
      printf '%s' "$ans" | out
      printf '%s' "$ans" | jq -e '[.data[] | select(. == null)] | length == 0' >/dev/null || exit 1
    else
      # aN: repository(owner:"o", name:"r") { issueOrPullRequest(number:N) ... }
      pairs="$(printf '%s' "$query" | grep -oE 'a[0-9]+: repository\(owner:"[^"]+", name:"[^"]+"\) \{ issueOrPullRequest\(number:[0-9]+\)' \
        | sed -E 's/^(a[0-9]+): repository\(owner:"([^"]+)", name:"([^"]+)"\) \{ issueOrPullRequest\(number:([0-9]+)\)$/\1 \2\/\3#\4/')"
      printf '%s\n' "$pairs" | jq -R 'split(" ") | {key: .[0], value: .[1]}' | jq -s --slurpfile w "$world" '
        {data: (map({key, value: {issueOrPullRequest: ($w[0].issues[.value] // null)}}) | from_entries)}' | out
    fi ;;
  repos/*/issues/comments/*)
    id="${path##*/}"
    ans="$(jq --arg id "$id" '.issues | to_entries[] | .key as $ref | .value.comments.nodes[] | select((.databaseId | tostring) == $id)
      | {id: .databaseId, node_id: .id, html_url: .url, user: {login: .author.login}, created_at: .createdAt, body,
         issue_url: ($ref | capture("^(?<r>[^#]+)#(?<n>[0-9]+)$") | "https://api.github.com/repos/\(.r)/issues/\(.n)")}' "$world")"
    [ -n "$ans" ] || missing
    printf '%s' "$ans" | out ;;
  repos/*/issues/*/timeline*)
    ref="$(printf '%s' "${path%%\?*}" | sed -E 's#^repos/([^/]+/[^/]+)/issues/([0-9]+)/timeline$#\1\#\2#')"
    jq -e --arg r "$ref" '.issues[$r] != null' "$world" >/dev/null || missing
    jq --arg r "$ref" '[.issues[$r].timelineItems.nodes[]
      | if .__typename == "CrossReferencedEvent" then {event: "cross-referenced", created_at: .createdAt, source: {issue: {html_url: .source.url}}}
        elif .__typename == "ReferencedEvent" then {event: "referenced", created_at: .createdAt, commit_id: .commit.oid}
        else {event: (.__typename | sub("Event$"; "") | ascii_downcase), created_at: .createdAt} end]' "$world" | out ;;
  repos/*/issues/*)
    ref="$(printf '%s' "$path" | sed -E 's#^repos/([^/]+/[^/]+)/issues/([0-9]+)$#\1\#\2#')"
    jq -e --arg r "$ref" '.issues[$r] != null' "$world" >/dev/null || missing
    if [ "$method" = PATCH ]; then
      cp "$bodyfile" "$world.patched"
      jq -n '{updated_at: "patched"}' | out
    else
      jq --arg r "$ref" '.issues[$r] | {node_id: .id, html_url: .url, user: {login: .author.login}, created_at: .createdAt, title, body,
        pull_request: (if .__typename == "PullRequest" then {} else null end)}' "$world" | out
    fi ;;
  repos/*/commits/*/pulls)
    sha="$(printf '%s' "$path" | sed -E 's#^repos/[^/]+/[^/]+/commits/([0-9a-f]+)/pulls$#\1#')"
    ans="$(jq --arg s "$sha" '[.commits | to_entries[] | select(.key | startswith($s)) | .value][0] // empty | [.pulls[]? | {number: .}]' "$world")"
    [ -n "$ans" ] || missing
    printf '%s' "$ans" | out ;;
  repos/*/commits/*)
    sha="${path##*/}"
    ans="$(jq --arg s "$sha" '[.commits | to_entries[] | select(.key | startswith($s)) | .value][0] // empty | del(.pulls)' "$world")"
    [ -n "$ans" ] || { echo "gh: No commit found for SHA: $sha (HTTP 422)" >&2; exit 1; }
    printf '%s' "$ans" | out ;;
  *) echo "gh-double: no stand-in for $method $path" >&2; exit 2 ;;
esac
