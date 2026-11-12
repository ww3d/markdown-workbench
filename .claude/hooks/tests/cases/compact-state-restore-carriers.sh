#!/usr/bin/env bash
# Hook suite section: restore-compact-state.sh against the carriers of the last save - what no carrier holds, the
# carriers another hand changed since checked (ww3d/playbook#487)
# Run alone: bash .claude/hooks/tests/cases/compact-state-restore-carriers.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== restore-compact-state.sh: carriers of the last save, changed since checked (ww3d/playbook#487) =="
proj="$fix/cr-proj"; mkdir -p "$proj"
use_forge "$fix/cr-forge"
cr_run() { # session, transcript -> the restore file's path in global f
  restore_event "$1" "$2" | PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
    "$BASH" "$restore_cs" >/dev/null 2>&1
  f="$(cs_rfile "$1" "$proj")"
}
since() { printf '%s\n' "$2" > "$forge/since-$1.json"; }       # owner_repo, JSON array of issues
comments() { printf '%s\n' "$2" > "$forge/comments-$1.json"; } # owner_repo_N, JSON array of comments
mcp_write() { # id, ISO time -> an own comment on ww3d/demo#7 through the GitHub MCP, call and result at that time
  TX_TS="$2" call "$1" mcp__github__add_issue_comment '{"owner":"ww3d","repo":"demo","issue_number":7,"body":"Stand"}'
  TX_TS="$2" result "$1" 'comment created'
}

# The history against the carrier: a carried sentence is no box, an uncarried promise is one.
tx="$fix/cr1.jsonl"; fresh
{
  said 'Gesichert.'
  human 'Bitte trage den Export Seidenreiher in den Traeger ein.'
  said 'Ich trage den Export Seidenreiher heute ein.'
  said 'Ich melde den Stand Kormoranflug am Abend.'
  for i in 1 2 3 4 5 6; do mcp_write "toolu_w$i" "2026-11-12T11:0$i:00.000Z"; done
} > "$tx"
body ww3d_demo_7 '## Open points
- [ ] Bitte trage den Export Seidenreiher in den Traeger ein.
- [ ] Ich trage den Export Seidenreiher heute ein.'
cs_state "$proj" cr1 1 2026-11-12T1000Z 2026-11-12T10:00:00Z ww3d/demo#7
since ww3d_demo '[{"number":7,"title":"Export Seidenreiher","updated_at":"2026-11-12T11:06:00Z"}]'
comments ww3d_demo_7 '[{"created_at":"2026-11-12T11:01:00Z","updated_at":"2026-11-12T11:01:00Z"},
 {"created_at":"2026-11-12T11:02:00Z","updated_at":"2026-11-12T11:02:00Z"},
 {"created_at":"2026-11-12T11:03:00Z","updated_at":"2026-11-12T11:03:00Z"},
 {"created_at":"2026-11-12T11:04:00Z","updated_at":"2026-11-12T11:04:00Z"},
 {"created_at":"2026-11-12T11:05:00Z","updated_at":"2026-11-12T11:05:00Z"},
 {"created_at":"2026-11-12T11:06:00Z","updated_at":"2026-11-12T11:06:00Z"}]'
cr_run cr1 "$tx"
hist="$(cs_sect 'History without a carrier' "$f")"
check_not_contains 'history: a sentence the carrier holds is no box' 'Seidenreiher' "$hist"
check_contains 'history: a promise no carrier holds is a box' '- [ ] L4 2026-11-12T1004Z promise: Ich melde den Stand Kormoranflug am Abend.' "$hist"
cc="$(cs_sect 'Carriers changed since checked' "$f")"
check_contains 'changed: the section names checked and checkedAt' 'Since 2026-11-12T1000Z (checkedAt 2026-11-12T10:00:00Z)' "$cc"
check_line 'changed: six changes of own write calls give no box' '_no carrier changed by another hand_' "$cc"
calls_="$(cat "$forge/calls.log" 2>/dev/null)"
check_line 'changed: one forge call per repo since checkedAt' 'repos/ww3d/demo/issues?since=2026-11-12T10:00:00Z&state=all&per_page=100' "$calls_"
check_line 'changed: the comments of the changed carrier since checkedAt' 'repos/ww3d/demo/issues/7/comments?since=2026-11-12T10:00:00Z&per_page=100' "$calls_"
# The maintainer's yes as a comment on the carrier: one change of another hand, one box.
since ww3d_demo '[{"number":7,"title":"Export Seidenreiher","updated_at":"2026-11-12T11:30:00Z"}]'
comments ww3d_demo_7 '[{"created_at":"2026-11-12T11:01:00Z","updated_at":"2026-11-12T11:01:00Z"},
 {"created_at":"2026-11-12T11:02:00Z","updated_at":"2026-11-12T11:02:00Z"},
 {"created_at":"2026-11-12T11:03:00Z","updated_at":"2026-11-12T11:03:00Z"},
 {"created_at":"2026-11-12T11:04:00Z","updated_at":"2026-11-12T11:04:00Z"},
 {"created_at":"2026-11-12T11:05:00Z","updated_at":"2026-11-12T11:05:00Z"},
 {"created_at":"2026-11-12T11:06:00Z","updated_at":"2026-11-12T11:06:00Z"},
 {"created_at":"2026-11-12T11:30:00Z","updated_at":"2026-11-12T11:30:00Z"}]'
cr_run cr1 "$tx"
cc="$(cs_sect 'Carriers changed since checked' "$f")"
expect 'changed: one change of another hand among six own gives one box' 1 "$(grep -c '^- \[ \] ww3d/demo#7 changed' <<<"$cc")"
check_line "changed: the maintainer's yes elsewhere names carrier, title and time" \
  '- [ ] ww3d/demo#7 changed since 2026-11-12T10:00:00Z: Export Seidenreiher (changes at 2026-11-12T11:30:00Z)' "$cc"
# An own write through gh in Bash counts as own too.
tg="$fix/cr2.jsonl"; fresh
{
  said 'Gesichert.'
  TX_TS=2026-11-12T11:40:00.000Z call toolu_g1 Bash '{"command":"gh issue comment 7 --repo ww3d/demo --body Stand"}'
  TX_TS=2026-11-12T11:40:00.000Z result toolu_g1 'https://github.com/ww3d/demo/issues/7#issuecomment-1'
} > "$tg"
cs_state "$proj" cr2 1 2026-11-12T1000Z 2026-11-12T10:00:00Z ww3d/demo#7
since ww3d_demo '[{"number":7,"title":"Export Seidenreiher","updated_at":"2026-11-12T11:40:00Z"}]'
comments ww3d_demo_7 '[{"created_at":"2026-11-12T11:40:00Z","updated_at":"2026-11-12T11:40:00Z"}]'
cr_run cr2 "$tg"
check_line 'changed: an own gh write in Bash gives no box' '_no carrier changed by another hand_' \
  "$(cs_sect 'Carriers changed since checked' "$f")"
# A read through the MCP is no write: the change at its time stays another hand's.
tr_="$fix/cr3.jsonl"; fresh
{
  said 'Gesichert.'
  TX_TS=2026-11-12T11:40:00.000Z call toolu_r1 mcp__github__issue_read '{"owner":"ww3d","repo":"demo","issue_number":7}'
  TX_TS=2026-11-12T11:40:00.000Z result toolu_r1 'body'
} > "$tr_"
cs_state "$proj" cr3 1 2026-11-12T1000Z 2026-11-12T10:00:00Z ww3d/demo#7
cr_run cr3 "$tr_"
expect 'changed: a read call at the same time is no own write' 1 "$(grep -c '^- \[ \] ww3d/demo#7 changed' <<<"$(cs_sect 'Carriers changed since checked' "$f")")"
# A change before checkedAt is no change.
since ww3d_demo '[{"number":7,"title":"Export Seidenreiher","updated_at":"2026-11-12T09:00:00Z"}]'
comments ww3d_demo_7 '[]'
cr_run cr3 "$tr_"
check_line 'changed: a change before checkedAt gives no box' '_no carrier changed by another hand_' "$(cs_sect 'Carriers changed since checked' "$f")"

# The forge call fails: the section says which repo was not checked and why.
body ww3d_broken_1 'Traeger ohne Abruf.'
cs_state "$proj" cr4 1 2026-11-12T1000Z 2026-11-12T10:00:00Z ww3d/broken#1
cr_run cr4 "$tr_"
check_contains 'forge failing: the repo is not checked, with the cause' 'carriers changed: not checked for ww3d/broken (HTTP 502: Bad Gateway' \
  "$(cs_sect 'Carriers changed since checked' "$f")"
expect 'forge failing: still eight sections' 8 "$(grep -c '^## ' "$f")"

# A check line "transcript: not readable" newer than checked leaves the stretch since it unchecked.
body ww3d_demo_8 '## Open points
checked: 2026-11-12T1100Z · transcript: not readable (Datei fehlt)'
cs_state "$proj" cr5 1 2026-11-12T1000Z 2026-11-12T10:00:00Z ww3d/demo#8
cr_run cr5 "$tx"
check_contains 'not readable: the history names the stretch unchecked' 'Unchecked since checked: 2026-11-12T1100Z' \
  "$(cs_sect 'History without a carrier' "$f")"
body ww3d_demo_8 '## Open points
checked: 2026-11-12T0900Z · transcript: not readable (Datei fehlt)'
cr_run cr5 "$tx"
check_not_contains 'not readable: an older check line leaves nothing unchecked' 'Unchecked since' "$(cs_sect 'History without a carrier' "$f")"

# A save with exit 0, then the compaction: the maintainer's sentence of the saved stretch stands at the carrier,
# not in the restore file.
ts="$fix/cr6.jsonl"; fresh
{ human 'Setz den Grenzwert Wieselbau bitte auf vierzig.'; said 'Erledigt, Grenzwert Wieselbau steht jetzt auf vierzig.'; } > "$ts"
body ww3d_demo_9 '- [x] Setz den Grenzwert Wieselbau bitte auf vierzig.
- [x] Erledigt, Grenzwert Wieselbau steht jetzt auf vierzig.'
out="$(cd "$proj" && PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" \
  CLAUDE_CODE_SESSION_ID=cr6 bash "$hooks/session-state.sh" save --carrier ww3d/demo#9 --transcript "$ts" 2>&1)"; rc=$?
expect 'saved stretch: save ends with 0' 0 "$rc"
{ boundary; summary 'Summary: Wieselbau.'; } >> "$ts"
cr_run cr6 "$ts"
check_not_contains "saved stretch: the maintainer's sentence is not among the sentences" 'Wieselbau' \
  "$(cs_sect "The maintainer's sentences since the cursor" "$f")"
check_not_contains "saved stretch: the maintainer's sentence is no box" 'Wieselbau' "$(cs_sect 'History without a carrier' "$f")"
check_not_contains 'history: the error file of the carrier fetch is no linked carrier' 'linked not read: hay' "$(cs_sect 'History without a carrier' "$f")"
check_contains "saved stretch: it stands in the carrier's body" 'Setz den Grenzwert Wieselbau bitte auf vierzig.' "$(cat "$forge/ww3d_demo_9.md")"

# Without gh, or with a checkedAt that is no ISO time, the section says why it was not checked.
nogh=""
IFS=: read -r -a dirs <<<"$PATH"
for d in "${dirs[@]}"; do [ -x "$d/gh" ] || [ -x "$d/gh.exe" ] || nogh="${nogh:+$nogh:}$d"; done
cs_state "$proj" cr7 1 2026-11-12T1000Z 2026-11-12T10:00:00Z ww3d/demo#7
restore_event cr7 "$tr_" | PATH="$nogh" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$proj" "$BASH" "$restore_cs" >/dev/null 2>&1
cc="$(cs_sect 'Carriers changed since checked' "$(cs_rfile cr7 "$proj")")"
check_line 'no gh: the carriers are not checked, with the cause' 'carriers changed: not checked (gh not found)' "$cc"
check_not_contains 'no gh: no claim that nothing changed' '_no carrier changed by another hand_' "$cc"
cs_state "$proj" cr8 1 2026-11-12T1000Z gestern ww3d/demo#7
cr_run cr8 "$tr_"
cc="$(cs_sect 'Carriers changed since checked' "$f")"
check_line 'checkedAt no ISO time: the carriers are not checked, with the cause' \
  "carriers changed: not checked (checkedAt 'gestern' is no ISO time)" "$cc"
check_not_contains 'checkedAt no ISO time: no claim that nothing changed' '_no carrier changed by another hand_' "$cc"

# Own writes without owner/repo go to the checkout's own repo, read from its origin.
home="$fix/cr-home"; mkdir -p "$home"
git -C "$home" init -q 2>/dev/null; git -C "$home" remote add origin https://github.com/ww3d/demo.git 2>/dev/null
cr_home() { # session, transcript -> restore under the repo with origin ww3d/demo, the restore file in global f
  restore_event "$1" "$2" | PATH="$forge_bin:$PATH" SS_FORGE="$forge" TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$home" \
    "$BASH" "$restore_cs" >/dev/null 2>&1
  f="$(cs_rfile "$1" "$home")"
}
own_bash() { # session, carrier, command -> an own Bash write at 11:40, the carrier changed at 11:40, global cc
  local r="${2%#*}" n="${2#*#}"
  fresh
  { said 'Gesichert.'
    js "$3"; TX_TS=2026-11-12T11:40:00.000Z call toolu_h1 Bash "{\"command\":$REPLY}"
    TX_TS=2026-11-12T11:40:00.000Z result toolu_h1 'ok'; } > "$fix/$1.jsonl"
  cs_state "$home" "$1" 1 2026-11-12T1000Z 2026-11-12T10:00:00Z "$2"
  since "${r//\//_}" "[{\"number\":$n,\"title\":\"Export Kranich\",\"updated_at\":\"2026-11-12T11:40:00Z\"}]"
  comments "${r//\//_}_$n" '[{"created_at":"2026-11-12T11:40:00Z","updated_at":"2026-11-12T11:40:00Z"}]'
  cr_home "$1" "$fix/$1.jsonl"
  cc="$(cs_sect 'Carriers changed since checked' "$f")"
}
own_bash cr9 ww3d/demo#487 'gh issue comment 487 --body x'
check_line 'own repo: gh issue comment without --repo is an own write' '_no carrier changed by another hand_' "$cc"
own_bash cr10 ww3d/demo#487 'gh api -X POST repos/{owner}/{repo}/issues/487/comments -f body=x'
check_line 'own repo: gh api on repos/{owner}/{repo} is an own write' '_no carrier changed by another hand_' "$cc"
own_bash cr11 ww3d/demo#487 'gh issue comment 487 -R other/x --body x'
expect 'own repo: gh issue comment with -R to another repo is no own write' 1 "$(grep -c '^- \[ \] ww3d/demo#487 changed' <<<"$cc")"
own_bash cr12 ww3d/else#487 'gh issue comment 487 --body x'
expect 'own repo: a carrier in another repo is not written by a call without owner/repo' 1 \
  "$(grep -c '^- \[ \] ww3d/else#487 changed' <<<"$cc")"

finish
