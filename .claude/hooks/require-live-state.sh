#!/usr/bin/env bash
#
# Live state at the tracking issue, enforced (ww3d/playbook#577). Generic, byte-identical across consumers.
#
# The session that causes a state transition sets its state label; this hook holds the end of its turn until it
# stands. The table .agents/state-labels.json maps each event to its label and its part ("label", or "status" for
# the status comment, which holds only for the session kinds a row lists, by default the controller).
#
# Entries:
#   --record  PostToolUse (Bash, PowerShell, Skill, the GitHub connector) and UserPromptSubmit. Appends what the
#             call did to the session's journal under ${TMPDIR:-/tmp}/claude-rule-gate/live-state/, without
#             network - only a gh write call at a command's position, never a failed one: an event of the
#             table (a draft PR opened, a PR readied, an approve, a merge, a tracking issue
#             opened by the design session, a received message naming an issue or PR), a state label set, a
#             comment edited, a line `State-Gate-Released: <event> <reason>` written. The first skill line sets
#             the session kind (.agents/session-kinds.json).
#   (none)    Stop. Replays the journal: an event stays open until a later own act of the same repository sets its
#             label (part "label") or edits an issue comment (part "status"), or a released line names it. With
#             an open event it blocks the turn end and names label, issue and PR; without one it ends silently,
#             no network and no jq beyond one replay. Before blocking it reads the tracking issue once (where the
#             session never saw it, the PR body first: its anchor names it, a PR without one is freed): its line
#             `State-Gate-Skip: <reason>` frees that issue. From the third block of one event on the reason names
#             the released line as the way past.
#   --stats   counts blocks, fulfilled, released, skipped and passed events from the log.
#
# Loop guard: with stop_hook_active and no recorded tool call since the last block the turn ends, the event stays
# open and blocks again at the next turn end. Fail-open: no jq, no gh, an unwritable folder, a failed read of the
# tracking issue end the turn. The hook never writes to GitHub. Learning log: live-state-log.jsonl beside the
# announce log of block-announce-end.sh.
#
# Stdin:  the hook event JSON. Stdout: Stop when blocking { decision, reason, systemMessage }; on the loop guard
#         { systemMessage }; otherwise nothing. --record prints nothing.

set -uo pipefail

gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
state_dir="$gate_dir/live-state"
log="$gate_dir/live-state-log.jsonl"
project="${CLAUDE_PROJECT_DIR:-.}"
table="$project/.agents/state-labels.json"
kinds_file="$project/.agents/session-kinds.json"
release_after=2   # blocks of one event before the reason names the released line

mode=stop
case "${1:-}" in
  --record) mode=record ;;
  --stats) mode=stats ;;
esac

if [ "$mode" = stats ]; then
  if [ ! -s "$log" ]; then echo "No live-state log at $log."; exit 0; fi
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  jq -Rnr '[ inputs | fromjson? | objects ] as $l | def n($o): $l | map(select(.outcome == $o)) | length;
    "\($l | length) lines in the live-state log: blocked \(n("block")), fulfilled \(n("fulfilled")), released \(n("released")), skipped \(n("skipped")), passed \(n("passed"))",
    ( $l | map(select(.outcome == "block")) | group_by(.event)[] | "blocks for \(.[0].event): \(length)" )
  ' "$log" 2>/dev/null || echo "The live-state log at $log could not be read."
  exit 0
fi

# shellcheck source=SCRIPTDIR/lib/stdin.sh
. "${BASH_SOURCE[0]%/*}/lib/stdin.sh" 2>/dev/null || read_hook_payload() { hook_input=""; [ -t 0 ] || hook_input="$(cat)" || true; }
hook_payload_quiet=1 read_hook_payload
input="$hook_input"

re_sid='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
[[ $input =~ $re_sid ]] || exit 0
sid="${BASH_REMATCH[1]}"
journal="$state_dir/$sid.jsonl"   # one JSON line per recorded act; emptied once nothing is open
seqf="$state_dir/$sid.seq"        # one byte per recorded tool call: its size is the loop guard's counter
blockf="$state_dir/$sid.blockseq" # the counter at the last block
kindf="$state_dir/$sid.kind"
prsf="$state_dir/$sid.prs"        # "repo pr issue" per PR whose tracking issue the session saw

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log_line() { # outcome, event json fields (compact object) -> one appended line, fail-open
  printf '{"ts":"%s","session_id":"%s","outcome":"%s",%s\n' "$(ts)" "$sid" "$1" "${2#\{}" >> "$log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------------------------------- record
if [ "$mode" = record ]; then
  { [ -d "$state_dir" ] || mkdir -p "$state_dir"; } 2>/dev/null || exit 0
  re_evt='"hook_event_name"[[:space:]]*:[[:space:]]*"([A-Za-z]+)"'
  evt=""; [[ $input =~ $re_evt ]] && evt="${BASH_REMATCH[1]}"
  [ "$evt" = UserPromptSubmit ] || printf . >> "$seqf" 2>/dev/null
  # Cheap first, without jq: a Bash or PowerShell call goes on only when its command calls gh, a connector call
  # only when it writes.
  re_tool='"tool_name"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_.-]+)"'
  tool=""; [[ $input =~ $re_tool ]] && tool="${BASH_REMATCH[1]}"
  if [[ $tool == Bash || $tool == PowerShell ]]; then
    re_cmd='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'; re_gh='gh([[:space:]]|\\[nt])+(-[^[:space:]]+[[:space:]]+)*(api|pr|issue)'
    [[ $input =~ $re_cmd ]] && [[ ${BASH_REMATCH[1]} =~ $re_gh ]] || exit 0
  elif [[ $tool == mcp__* ]]; then
    case "${tool##*__}" in
      create_pull_request|update_pull_request|pull_request_review_write|merge_pull_request|issue_write|update_issue_comment|add_issue_comment) ;;
      *) exit 0 ;;
    esac
  fi
  command -v jq >/dev/null 2>&1 || exit 0

  kind=""; { read -r kind < "$kindf"; } 2>/dev/null
  if [ -z "$kind" ]; then
    re_def='"defaultKind"[[:space:]]*:[[:space:]]*"([a-z]+)"'
    kind=dev; [[ $(cat -- "$kinds_file" 2>/dev/null) =~ $re_def ]] && kind="${BASH_REMATCH[1]}"
  fi
  items=()   # one tab-separated line per act: type, name, repo, issue, pr

  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; cwd="${cwd%$'\r'}"
  [ -d "$cwd" ] || cwd="$project"
  own_repo=""
  repo_here() { # the repository of the working folder, from its origin remote, lower case
    if [ -z "$own_repo" ]; then
      local url re='github\.com[:/]+([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)'
      url="$(git -C "$cwd" remote get-url origin 2>/dev/null)"
      [[ $url =~ $re ]] && own_repo="${BASH_REMATCH[1]%.git}"
      own_repo="${own_repo,,}"
    fi
    REPLY="$own_repo"
  }
  set_kind() { # a skill name, any plugin prefix -> the session kind of .agents/session-kinds.json, set once
    local k
    [ ! -s "$kindf" ] || return 0
    # The name goes in without its slash: Git Bash would turn a "/name" argument of a native jq into a path.
    # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
    k="$(jq -r --arg s "${1##*:}" '.skills["/" + $s] // empty' "$kinds_file" 2>/dev/null)"; k="${k%$'\r'}"
    [ -z "$k" ] || { printf '%s\n' "$k" > "$kindf"; } 2>/dev/null
    [ -z "$k" ] || kind="$k"
  }

  # One gh command, its words after `gh` unquoted (lib/segments.awk) -> the acts it writes, added to items.
  parse_gh() { # GH_REPO in scope, folder state, words...
    local ghrepo="$1" folder="$2"; shift 2
    local -a a=("$@") labs=() pos=()
    local n=$# i=0 w v group="" action="" path="" method="" fields=0 rflag="" bodyfile="" text="" head=""
    local approve=0 draft=0 undo=0 auto=0 editlast=0 r pr="" anchor="" l t write=0 status=0
    add_labels() { local x; IFS=, read -ra x <<<"$1"; for l in "${x[@]}"; do l="${l// /}"; [[ $l != state:* ]] || labs+=("$l"); done; }
    field() { # one -f/-F value of gh api
      case "$1" in
        body=@*) bodyfile="${1#body=@}" ;;
        event=APPROVE|event=approve) approve=1 ;;
        draft=true) draft=1 ;;
        'labels[]='*) add_labels "${1#labels\[\]=}" ;;
        head=*) head="${1#head=}" ;;
      esac
      text+=" $1"
    }
    while [ "$i" -lt "$n" ]; do
      w="${a[i]}"; v="${a[i + 1]:-}"
      case "$w" in
        -R|--repo) rflag="$v"; i=$((i + 2)); continue ;;
        --repo=*) rflag="${w#--repo=}" ;;
        -X|--method) method="${v^^}"; i=$((i + 2)); continue ;;
        -X?*) method="${w#-X}"; method="${method^^}" ;;
        --method=*) method="${w#--method=}"; method="${method^^}" ;;
        -f|--field|--raw-field) fields=1; field "$v"; i=$((i + 2)); continue ;;
        -F) if [ "$group" = api ]; then fields=1; field "$v"; else bodyfile="$v"; fi; i=$((i + 2)); continue ;;
        --input) fields=1; bodyfile="$v"; i=$((i + 2)); continue ;;
        --body-file) bodyfile="$v"; i=$((i + 2)); continue ;;
        -b|--body) text+=" $v"; i=$((i + 2)); continue ;;
        --add-label|--label|-l) add_labels "$v"; [[ ",${v// /}," != *,tracking,* ]] || labs+=(tracking); i=$((i + 2)); continue ;;
        --add-label=*|--label=*) v="${w#*=}"; add_labels "$v"; [[ ",${v// /}," != *,tracking,* ]] || labs+=(tracking) ;;
        -H|--head) if [ "$group" = api ]; then :; else head="$v"; fi; i=$((i + 2)); continue ;;
        --draft|-d) draft=1 ;;
        --approve|-a) approve=1 ;;
        --undo) undo=1 ;;
        --auto|--disable-auto) auto=1 ;;
        --edit-last) editlast=1 ;;
        -*) ;;
        *) if [ -z "$group" ]; then group="$w"
           elif [ "$group" = api ] && [ -z "$path" ]; then path="$w"
           elif [ "$group" != api ] && [ -z "$action" ]; then action="$w"
           else pos+=("$w"); fi ;;
      esac
      i=$((i + 1))
    done
    text+=" ${a[*]}"
    if [ -n "$bodyfile" ]; then
      [[ $bodyfile == /* || $folder != D* ]] || bodyfile="${folder#D}/$bodyfile"
      [[ $bodyfile == /* ]] || bodyfile="$cwd/$bodyfile"
      [ -f "$bodyfile" ] && text+=$'\n'"$(head -c 200000 -- "$bodyfile" 2>/dev/null)"
    fi
    # The repository: an api path, a PR URL, -R, GH_REPO in scope, else the working folder's origin.
    re_path='^/?repos/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(/.*)?$' re_url='github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([0-9]+)'
    if [[ $path =~ $re_path ]]; then r="${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]%%\?*}"
    elif [[ ${pos[0]:-} =~ $re_url ]]; then r="${BASH_REMATCH[1]}"; pr="${BASH_REMATCH[2]}"
    elif [ -n "$rflag" ]; then r="${rflag#*github.com/}"
    elif [ -n "$ghrepo" ]; then r="$ghrepo"
    else repo_here; r="$REPLY"; fi
    r="${r,,}"
    [ -n "$pr" ] || [[ ! ${pos[0]:-} =~ ^#?([0-9]+)$ ]] || pr="${BASH_REMATCH[1]}"
    re_pn='^/pulls/([0-9]+)'; [ -n "$pr" ] || [[ ! $path =~ $re_pn ]] || pr="${BASH_REMATCH[1]}"
    # gh pr ready/review/merge without a number acts on the PR of a branch: the number from the call's output
    # (owner/repo#N, .../pull/N), else the branch, which the stop reads as its PR; without either no event.
    pr_of_branch() {
      local re_o='([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)' re_u='/pull/([0-9]+)' b
      if [[ $out =~ $re_o ]]; then pr="${BASH_REMATCH[2]}"; return 0; fi
      if [[ $out =~ $re_u ]]; then pr="${BASH_REMATCH[1]}"; return 0; fi
      b="${pos[0]:-}"
      [ -n "$b" ] || b="$(git -C "$cwd" branch --show-current 2>/dev/null)"
      [[ $b =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
      pr="branch:$b"
    }
    re_anchor='([Cc]loses|[Ff]ixes|[Rr]esolves|[Rr]efs)[[:space:]]+#([0-9]+)'
    [[ ! $text =~ $re_anchor ]] || anchor="${BASH_REMATCH[2]}"
    re_head='^[A-Za-z0-9_-]+/([0-9]+)-'; [ -n "$anchor" ] || [[ ! $head =~ $re_head ]] || anchor="${BASH_REMATCH[1]}"
    [[ $text != *"Review-Verdict: approve"* ]] || approve=1
    ev() { items+=("event"$'\t'"$1"$'\t'"$r"$'\t'"$2"$'\t'"$3"); }
    opened() { created; ev pr-draft-opened "$anchor" "$REPLY"; [ -z "$REPLY" ] || [ -z "$anchor" ] || printf '%s %s %s\n' "$r" "$REPLY" "$anchor" >> "$prsf" 2>/dev/null; }
    case "$group" in
      api)
        { [[ $method =~ ^(POST|PUT|PATCH|DELETE)$ ]] || { [ -z "$method" ] && [ "$fields" = 1 ]; }; } || return 0
        write=1
        case "$path" in
          /pulls) [ "$draft" = 0 ] || opened ;;
          /pulls/*/ccr/ready_for_review) ev pr-ready "" "$pr" ;;
          /pulls/*/reviews|/pulls/*/reviews/*/events) [ "$approve" = 0 ] || ev pr-approved "" "$pr" ;;
          /pulls/*/merge) [ "$method" != PUT ] || ev pr-merged "" "$pr" ;;
          /issues) [[ " ${labs[*]} " != *" tracking "* && $text != *'labels[]=tracking'* ]] || { created; ev tracking-issue-opened "$REPLY" ""; } ;;
          /issues/comments/*) [ "$method" != PATCH ] || status=1 ;;
        esac
        # Labels sent as a JSON file (--input) count where the path is a label list.
        if [ "$method" != DELETE ] && [[ $path == */labels ]] && [ -n "$bodyfile" ]; then
          local rest="$text" re_st='"(state:[a-z-]+)"'
          while [[ $rest =~ $re_st ]]; do labs+=("${BASH_REMATCH[1]}"); rest="${rest#*"${BASH_REMATCH[0]}"}"; done
        fi
        [ "$method" != DELETE ] || labs=() ;;
      pr)
        write=1
        case "$action" in
          create) [ "$draft" = 0 ] || opened ;;
          ready) if [ "$undo" = 0 ] && { [ -n "$pr" ] || pr_of_branch; }; then ev pr-ready "" "$pr"; fi ;;
          review) if [ "$approve" = 1 ] && { [ -n "$pr" ] || pr_of_branch; }; then ev pr-approved "" "$pr"; fi ;;
          merge) if [ "$auto" = 0 ] && { [ -n "$pr" ] || pr_of_branch; }; then ev pr-merged "" "$pr"; fi ;;
          edit|comment) ;;
          *) write=0 ;;
        esac ;;
      issue)
        write=1
        case "$action" in
          create) [[ " ${labs[*]} " != *" tracking "* ]] || { created; ev tracking-issue-opened "$REPLY" ""; } ;;
          edit) ;;
          comment) [ "$editlast" = 0 ] || status=1 ;;
          *) write=0 ;;
        esac ;;
    esac
    [ "$write" = 1 ] || return 0
    for l in "${labs[@]}"; do [[ $l != state:* ]] || items+=("label"$'\t'"$l"$'\t'"$r"$'\t'$'\t'); done
    [ "$status" = 0 ] || items+=("status"$'\t'$'\t'"$r"$'\t'$'\t')
    local rest="$text" re_rel='State-Gate-Released:[[:space:]]+([a-z-]+)[[:space:]]+[^[:space:]]'
    while [[ $rest =~ $re_rel ]]; do
      items+=("release"$'\t'"${BASH_REMATCH[1]}"$'\t'"$r"$'\t'$'\t'); rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
  }

  if [ "$evt" = UserPromptSubmit ]; then
    prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"
    re_skill='^[[:space:]]*(<command-name>)?/([A-Za-z0-9_-]+:)?([A-Za-z0-9_-]+)'
    [[ $prompt =~ $re_skill ]] && set_kind "${BASH_REMATCH[3]}"
    # A received message naming an issue or PR: the status comment follows (part "status", controller by default).
    re_full='github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/(issues|pull)/([0-9]+)|([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)'
    re_bare='(^|[^A-Za-z0-9_/&])#([0-9]+)([^A-Za-z0-9_]|$)'
    if [[ $prompt =~ $re_full ]]; then
      if [ -n "${BASH_REMATCH[1]}" ]; then r="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[3]}"; else r="${BASH_REMATCH[4]}"; n="${BASH_REMATCH[5]}"; fi
      items+=("event"$'\t'"status-after-message"$'\t'"${r,,}"$'\t'"$n"$'\t')
    elif [[ $prompt =~ $re_bare ]]; then
      n="${BASH_REMATCH[2]}"; repo_here
      [ -z "$REPLY" ] || items+=("event"$'\t'"status-after-message"$'\t'"$REPLY"$'\t'"$n"$'\t')
    fi
  elif [ "$tool" = Skill ]; then
    s="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)"; s="${s%$'\r'}"
    [ -z "$s" ] || set_kind "$s"
  elif [[ $tool == Bash || $tool == PowerShell ]]; then
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    # A call that failed records nothing: an interrupted run, an HTTP error, or a gh failure line ("X ...") in the
    # output, stderr or stdout (`2>&1 | tail` moves it there).
    # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
    out="$(printf '%s' "$input" | jq -r '.tool_response | if type == "object" then
        (((.stdout // "") + "\n" + (.stderr // "")) as $all
         | if .interrupted == true or ($all | test("HTTP [45][0-9][0-9]|(^|\n)\\s*[X✗] |is not mergeable"))
           then "\u0001failed" else (.stdout // "") end)
      else tostring end' 2>/dev/null)"
    [[ $out != $'\001failed'* ]] || exit 0
    # The commands in command position, split once by lib/segments.awk (quotes, heredoc bodies, comments and line
    # breaks as the shell reads them); a missing awk, segmenter or heredoc library records nothing.
    src="$cmd"
    if [ "$tool" = Bash ] && [[ $cmd == *'<<'* ]]; then
      # shellcheck source=SCRIPTDIR/lib/heredoc.sh
      . "${BASH_SOURCE[0]%/*}/lib/heredoc.sh" 2>/dev/null || exit 0
      strip_heredocs "$cmd"; src="$hd_out"
    fi
    ps=""; [ "$tool" != PowerShell ] || ps=1
    recs="$(SEG_PS="$ps" LC_ALL=C awk -f "${BASH_SOURCE[0]%/*}/lib/segments.awk" <<<"$src" 2>/dev/null)" || exit 0
    created() { # the number the call created: a URL .../pull/N or .../issues/N, a "number" field, a bare number line
      local re='/(pull|pulls|issues)/([0-9]+)' re2='"number"[[:space:]]*:[[:space:]]*([0-9]+)' re3='^[[:space:]]*([0-9]+)[[:space:]]*$'
      REPLY=""
      if [[ $out =~ $re ]]; then REPLY="${BASH_REMATCH[2]}"
      elif [[ $out =~ $re2 ]]; then REPLY="${BASH_REMATCH[1]}"
      elif [[ ${out%%$'\n'*} =~ $re3 ]]; then REPLY="${BASH_REMATCH[1]}"; fi
    }
    while IFS= read -r rec; do
      [ -n "$rec" ] || continue
      IFS=$'\037' read -ra f <<<"$rec"
      if [ "${f[1]}" != gh ] || [[ ${f[2]} == *[pd]* ]]; then continue; fi
      parse_gh "${f[5]}" "${f[7]}" "${f[@]:$((10 + f[8]))}"
    done <<<"$recs"
  elif [[ $tool == mcp__* ]]; then
    # The GitHub connector: its tool name ends in the action; owner and repo name the repository.
    # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
    # A failed call records nothing: an error flag or an error text in the connector's answer.
    conn_out="$(printf '%s' "$input" | jq -r '
        (.tool_response | tostring) as $resp
      | if ($resp | test("\"isError\"\\s*:\\s*true|^\"?\\s*(failed|error)\\b|not mergeable"; "i")) then empty else . end
      | (.tool_name | sub("^mcp__.*__"; "")) as $t | (.tool_input // {}) as $i
      | ((($i.owner // "") + "/" + ($i.repo // "")) | ascii_downcase) as $r
      | ((.tool_response | tostring) | [ match("(?:number[^:0-9]{0,6}:\\s*|/(?:pull|issues)/)([0-9]+)").captures[0].string ] | first // "") as $num
      | (($i.body // "") | [ match("(?i)\\b(?:closes|fixes|resolves|refs)\\s+#([0-9]+)").captures[0].string ] | first
          // (($i.head // "") | capture("^[^/]+/(?<n>[0-9]+)-").n) // "") as $anchor
      | ($i.pullNumber // $i.pull_number // "" | tostring) as $pr
      | [ if $t == "create_pull_request" and $i.draft == true then ["event", "pr-draft-opened", $r, $anchor, $num] else empty end,
          if $t == "update_pull_request" and $i.draft == false then ["event", "pr-ready", $r, "", $pr] else empty end,
          if $t == "pull_request_review_write" and (($i.method // "") | IN("create", "submit_pending"))
             and ((($i.event // "") | ascii_upcase) == "APPROVE" or (($i.body // "") | test("Review-Verdict: approve")))
          then ["event", "pr-approved", $r, "", $pr] else empty end,
          if $t == "merge_pull_request" then ["event", "pr-merged", $r, "", $pr] else empty end,
          if $t == "issue_write" and $i.method == "create" and (($i.labels // []) | index("tracking"))
          then ["event", "tracking-issue-opened", $r, $num, ""] else empty end,
          if $t == "issue_write" then (($i.labels // [])[] | strings | select(startswith("state:")) | ["label", ., $r, "", ""]) else empty end,
          if $t == "update_issue_comment" then ["status", "", $r, "", ""] else empty end,
          (($i.body // "") | [ match("State-Gate-Released:\\s+([a-z-]+)\\s+\\S"; "g").captures[0].string ][] | ["release", ., $r, "", ""]) ]
      | .[] | map(tostring) | join("\t")' 2>/dev/null)"
    conn=(); [ -z "$conn_out" ] || mapfile -t conn <<<"${conn_out//$'\r'/}"
    items+=("${conn[@]}")
    for it in "${conn[@]}"; do
      IFS=$'\t' read -r t e r i p <<<"${it%$'\r'}"
      [ "$e" = pr-draft-opened ] && [ -n "$i" ] && [ -n "$p" ] && printf '%s %s %s\n' "$r" "$p" "$i" >> "$prsf" 2>/dev/null
    done
  fi

  [ "${#items[@]}" -gt 0 ] || exit 0
  # shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
  printf '%s\n' "${items[@]}" | jq -Rc --arg k "$kind" --arg ts "$(ts)" '
      split("\t") | {t: .[0], name: .[1], repo: (.[2] // ""), issue: (.[3] // ""), pr: (.[4] // ""), kind: $k, ts: $ts}' \
    >> "$journal" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------------------------------------------- stop
[ -s "$journal" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The replay, one jq call: each event of the table with its open state, block count and tracking issue where known;
# printed as tagged lines - C (closed, not yet logged: key, via, event), O (open: key, event), S (repo and issue to
# read for the skip line), B (the block output).
# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
replay_jq='
    def evt: {event: .event, label: .label, repo: .repo, issue: .issue, pr: .pr};
    ($tbl[0].rows // []) as $rows
  | [ inputs | fromjson? | objects ] as $j
  | ($prs | split("\n") | map(split(" ") | select(length == 3))
      + [ $j[] | select(.t == "anchor") | [.repo, .pr, .issue] ]) as $map
  | ($rows | map(select(.event == "status-after-event")) | first) as $sae
  | [ $j | to_entries[] | select(.value.t == "event") | .key as $n | .value as $e
      | ($rows | map(select(.event == $e.name)) | first) as $r
      | select($r != null and ($r.label != null or $r.part == "status"))
      | select(($r.kinds // null) == null or ($r.kinds | index($e.kind)))
      | ($e.issue | if . == "" then ([ $map[] | select(.[0] == $e.repo and .[1] == $e.pr) | .[2] ] | last // "") else . end) as $iss
      | {key: "\($n)", n: $n, event: $e.name, label: $r.label, part: $r.part, repo: $e.repo, issue: $iss, pr: $e.pr},
        ( select($r.part == "label" and $sae != null and (($sae.kinds // null) == null or ($sae.kinds | index($e.kind))))
          | {key: "\($n)s", n: $n, event: "status-after-event", label: null, part: "status", repo: $e.repo, issue: $iss, pr: $e.pr, after: $e.name} ) ]
  | map(. as $ev
      | ([ $j | to_entries[] | select(.key > $ev.n) | .value
           | select( (.t == "label" and $ev.part == "label" and .name == $ev.label and .repo == $ev.repo)
                  or (.t == "status" and $ev.part == "status" and .repo == $ev.repo)
                  or (.t == "release" and .repo == $ev.repo and (.name == $ev.event or .name == ($ev.after // "")))
                  or (.t == "skip" and .repo == $ev.repo
                      and ((.issue != "" and .issue == $ev.issue) or (.issue == "" and .pr != "" and .pr == $ev.pr))) ) ] | first) as $c
      | . + { open: ($c == null),
              via: (if $c == null then null elif $c.t == "label" or $c.t == "status" then "fulfilled" elif $c.t == "release" then "released" else "skipped" end),
              logged: any($j[]; .t == "logged" and .name == $ev.key),
              blocks: ([ $j[] | select(.t == "block" and .name == $ev.key) ] | length) })
  | map(select(.open | not) | select(.logged | not) | "C\t\(.key)\t\(.via)\t\(evt | tojson)")[],
    ( map(select(.open)) as $o | select($o | length > 0)
    | ($o[] | "O\t\(.key)\t\(evt | tojson)"),
      ([ $o[] | select(.issue != "") | "S\t\(.repo)\t\(.issue)" ] | unique[]),
      ([ $o[] | select(.issue == "" and .pr != "") | "P\t\(.repo)\t\(.pr)" ] | unique[]),
      ( ($o | map(
          (if .issue != "" then "\(.repo)#\(.issue)" elif (.pr | startswith("branch:")) then "the tracking issue of the \(.repo) PR of branch \(.pr[7:])" elif .pr != "" then "the tracking issue of \(.repo) PR #\(.pr)" else "the tracking issue in \(.repo)" end) as $where
          | if .part == "status" then "rewrite the status comment on \($where) (\(.event)\(if .after then " " + .after else "" end))"
            else "set `\(.label)` on \($where) and take the old state label off"
              + " (\(.event)\(if .pr != "" then ", PR #\(.pr)" else "" end))" end)) as $todo
        | ($o | map(select(.blocks >= $after) | .event) | unique) as $stuck
        | "B\t" + ({ decision: "block",
            reason: ("Live state lags behind your own GitHub act - the turn ends once it stands at GitHub: " + ($todo | join("; ")) + "."
              + (if ($stuck | length) > 0 then " Held \($after) times already: where the step cannot be done, write the line `State-Gate-Released: <event> <reason>` at the tracking issue, without one in the PR body (event: " + ($stuck | join(", ")) + ")." else "" end)
              + " Zustand nachziehen: Label setzen bzw. Status-Kommentar neu schreiben, dann endet der Zug."),
            systemMessage: "Turn end held: the state label or status comment lags behind this session'"'"'s own act." } | tojson) ) )
'
append() { printf '%s\n' "$@" >> "$journal" 2>/dev/null; }
mark() { # type, keys... -> one journal line per key
  local t="$1" k; shift
  for k in "$@"; do append "{\"t\":\"$t\",\"name\":\"$k\",\"repo\":\"\",\"issue\":\"\",\"pr\":\"\",\"kind\":\"\",\"ts\":\"$(ts)\"}"; done
}
replay() { # -> open (key<TAB>event json), reads (repo<TAB>issue), block; the closed events logged and marked
  local prs="" lines t a b c
  [ -s "$prsf" ] && prs="$(cat -- "$prsf" 2>/dev/null)"
  lines="$(jq -Rnr --slurpfile tbl "$table" --arg prs "$prs" --argjson after "$release_after" "$replay_jq" "$journal" 2>/dev/null)" || return 1
  open=(); reads=(); prreads=(); block=""
  while IFS=$'\t' read -r t a b c; do
    case "$t" in
      C) log_line "$b" "$c"; mark logged "$a" ;;
      O) open+=("$a"$'\t'"$b") ;;
      S) reads+=("$a"$'\t'"$b") ;;
      P) prreads+=("$a"$'\t'"$b") ;;
      B) block="$a" ;;
    esac
  done <<<"${lines//$'\r'/}"
  return 0
}

replay || exit 0
if [ "${#open[@]}" = 0 ]; then
  : > "$journal" 2>/dev/null; : > "$seqf" 2>/dev/null; rm -f -- "$blockf" 2>/dev/null
  exit 0
fi

# Loop guard: the turn already continues on a block and no tool ran since.
re_active='"stop_hook_active"[[:space:]]*:[[:space:]]*true'
seq="$({ wc -c < "$seqf"; } 2>/dev/null | tr -d '[:space:]')"; seq="${seq:-0}"
last=""; { read -r last < "$blockf"; } 2>/dev/null
if [[ $input =~ $re_active ]] && [ "$seq" = "$last" ]; then
  log_line passed '{"event":"loop-guard"}'
  printf '%s\n' '{"systemMessage":"Live state still lags behind this session'"'"'s own GitHub act; the Stop hook blocked once and no tool ran since, so the turn ends. The event stays open and blocks at the next turn end."}'
  exit 0
fi

# A PR whose tracking issue the session never saw: one read of its body. Its anchor (Closes/Refs #N) names the
# tracking issue; a PR without one has none to label, and its event is freed. A failed read lets the turn end.
command -v gh >/dev/null 2>&1 || exit 0
if [ "${#prreads[@]}" -gt 0 ]; then
  re_anchor='([Cc]loses|[Ff]ixes|[Rr]esolves|[Rr]efs)[[:space:]]+#([0-9]+)'
  for rd in "${prreads[@]}"; do
    IFS=$'\t' read -r repo pr <<<"$rd"
    if [[ $pr == branch:* ]]; then
      # The open PR of the branch, or none: then the event has no PR and nothing to label.
      body="$(timeout 10 gh api "repos/$repo/pulls?head=${repo%%/*}:${pr#branch:}&state=all" --jq '.[0].body // ""' 2>/dev/null)" || exit 0
    else
      body="$(timeout 10 gh api "repos/$repo/pulls/$pr" --jq '.body // ""' 2>/dev/null)" || exit 0
    fi
    if [[ $body =~ $re_anchor ]]; then t=anchor; iss="${BASH_REMATCH[2]}"; else t=skip; iss=""; fi
    append "{\"t\":\"$t\",\"name\":\"\",\"repo\":\"$repo\",\"issue\":\"$iss\",\"pr\":\"$pr\",\"kind\":\"\",\"ts\":\"$(ts)\"}"
  done
  replay || exit 0
  [ "${#open[@]}" -gt 0 ] || exit 0
fi

# State-Gate-Skip: one read of each tracking issue the block would name; a failed read lets the turn end.
skips=0
for rd in "${reads[@]}"; do
  IFS=$'\t' read -r repo issue <<<"$rd"
  body="$(timeout 10 gh api "repos/$repo/issues/$issue" --jq '.body // ""' 2>/dev/null)" || exit 0
  if printf '%s\n' "$body" | grep -qE '^[[:space:]]*State-Gate-Skip:[[:space:]]*[^[:space:]]'; then
    append "{\"t\":\"skip\",\"name\":\"\",\"repo\":\"$repo\",\"issue\":\"$issue\",\"pr\":\"\",\"kind\":\"\",\"ts\":\"$(ts)\"}"
    skips=$((skips + 1))
  fi
done
if [ "$skips" -gt 0 ]; then
  replay || exit 0
  [ "${#open[@]}" -gt 0 ] || exit 0
fi
[ -n "$block" ] || exit 0

# Block: every open event gets its block counted and logged; from the third on the reason names the released line.
for o in "${open[@]}"; do mark block "${o%%$'\t'*}"; log_line block "${o#*$'\t'}"; done
printf '%s\n' "$seq" > "$blockf" 2>/dev/null
printf '%s\n' "$block"
exit 0
