#!/usr/bin/env bash
# Hook suite section: require-receipt.sh, the Stop hook against the read receipt
# Run alone: bash .claude/hooks/tests/cases/require-receipt.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-receipt.sh never blocks for a missing receipt (ww3d/playbook#435) =="
for f in no-receipt with-receipt with-old-receipt with-block-in-fence with-one-line-receipt echo-block-crlf \
         block-quoted-midline block-head-midline block-mem-midline block-core-prefix echo-head-only resumed quote-only drift trunc-no-receipt trunc-then-receipt \
         echo-receipt echo-unrun echo-redirect echo-refused echo-then-resumed \
         receipt-ss-receipt receipt-resume-turn receipt-fork-turn receipt-startup-turn \
         receipt-then-compact receipt-then-compact-hook echo-then-compact compact-then-receipt \
         receipt-then-clear clear-then-receipt mem-only split-messages old-format \
         compact-no-sessionstart other-hook-no-sessionstart; do
  out="$(stop_in "$fix/$f.jsonl" false '' Stop | bash "$stop" 2>&1)"
  if   has_text '"decision":"block"' "$out"; then v=BLOCK
  elif has_text 'systemMessage' "$out"; then v=DRIFT
  elif [ -z "$out" ]; then v=ALLOW; else v="ERR"; fi
  case "$f" in
    # The start hook shows the receipt, so a missing, quoted, split or stale one is no reason to hold
    # the turn end: every case passes, whatever the transcript holds; only the schema drift speaks.
    drift) want=DRIFT ;;
    *) want=ALLOW ;;
  esac
  if [ "$v" = "$want" ]; then ok "stop hook on $f" "$v"; else bad "stop hook on $f" "$v" "$want"; fi
done

echo "== require-receipt.sh: every green line against the read record (ww3d/playbook#366, C1) =="
c1_tmp="$fix/c1-tmp"; mkdir -p "$c1_tmp/claude-rule-gate"
c1() { # label, expected verdict, stop_hook_active, markers...
  # One session id per case: a repeated id would leave the earlier case's markers (an audit read) standing.
  # Each case ends in ok or bad, so pass + fail counts the finished ones: unique per case.
  local label="$1" want="$2" active="$3" sid="c1-$$-$((pass + fail))" payload out v m; shift 3
  for m in "$@"; do : > "$c1_tmp/claude-rule-gate/${sid}-${m}"; done
  # C1_SHORT: the line-reached file of a short read of the audit, "<reached> <end>".
  [ -z "${C1_SHORT:-}" ] || printf '%s\n' "$C1_SHORT" > "$c1_tmp/claude-rule-gate/${sid}-read-main-core.audit.2026-02-02T0000Z.short"
  # The hook ends silent on ALLOW and on a failed jq alike: input the hook cannot parse must not read as ALLOW.
  payload="$(stop_in "$fix/${C1_FIX:-c1-receipt}.jsonl" "$active" "$sid")"
  if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then bad "$label" "NOINPUT" "$want"; return; fi
  out="$(printf '%s' "$payload" | TMPDIR="$c1_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$stop" 2>&1)"
  c1_out="$out"
  if has_text '"decision":"block"' "$out"; then v=BLOCK
  elif has_text 'systemMessage' "$out"; then v=WARN
  elif [ -z "$out" ]; then v=ALLOW; else v="ERR $out"; fi
  if [ "$v" = "$want" ]; then ok "$label" "$v"; else bad "$label" "$v" "$want"; fi
}
c1 'all green lines recorded'               ALLOW false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z read-main-carrier
c1 'the audit line without its read'        BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
c1 'a rule line without its read'           BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
c1 'a read of a sub-agent does not count'   BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z read-agent-1-carrier
c1 'no sign that the record runs: pass'     ALLOW false read-main-core.claude
c1 'second stop: warn, never block twice'   WARN  true  recorder.on
all_read="read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z read-main-carrier"
# shellcheck disable=SC2086 # the marker list splits on purpose
{
C1_FIX=c1-fullpath c1 'a rule line with its full path, unread'     BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
C1_FIX=c1-fullpath c1 'a rule line with its full path, read'       ALLOW false recorder.on $all_read
C1_FIX=c1-other    c1 'a file that is no rule has no marker: pass' ALLOW false recorder.on $all_read
C1_FIX=c1-loose    c1 'tabs and a short checksum are still checked' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
C1_FIX=c1-auditpath c1 'an audit note given as a path'             ALLOW false recorder.on $all_read
# c1-auditdocs pins the note form docs/audit/... only; the place is pinned by the
# read-confirm and require-rule-read cases.
C1_FIX=c1-auditdocs c1 'an audit note under docs/audit/, read'     ALLOW false recorder.on $all_read
C1_FIX=c1-auditdocs c1 'an audit note under docs/audit/, unread'   BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
C1_FIX=c1-auditbare c1 'an audit line without a note, none read'   BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
C1_FIX=c1-auditbare c1 'an audit line without a note, one read'    ALLOW false recorder.on $all_read
C1_FIX=c1-crlf     c1 'a receipt with CRLF line ends, unread'      BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
C1_FIX=c1-echo     c1 'an echoed receipt: its green lines checked' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
C1_FIX=c1-echo     c1 'an echoed receipt, all read'                ALLOW false recorder.on $all_read
# ww3d/playbook#533: the audit name is pulled out of the brackets by pattern; one session id per case.
C1_FIX=c1-auditextra c1 'an audit note with text after the name, read'   ALLOW false recorder.on $all_read
C1_FIX=c1-auditextra c1 'an audit note with text after the name, unread'  BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
check_contains 'the reason names the audit file, no read recorded' 'Audit (no read of state-2026-02-02T0000Z.md recorded)' "$c1_out"
C1_FIX=c1-auditextra C1_SHORT='48 49' c1 'the same note after a short read' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
check_contains 'the reason names the line reached and the end of the short form' 'Audit (read through line 48, short form ends at 49)' "$c1_out"
C1_FIX=c1-auditextra C1_SHORT='junk' c1 'an unreadable line-reached file' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
check_contains 'the reason falls back to no read recorded' 'Audit (no read of state-2026-02-02T0000Z.md recorded)' "$c1_out"
C1_FIX=c1-auditpathextra c1 'an audit note with a path and text around it, read'   ALLOW false recorder.on $all_read
C1_FIX=c1-auditpathextra c1 'an audit note with a path and text around it, unread' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
C1_FIX=c1-auditnoname    c1 'a bracket without an audit name, none read'  BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
check_contains 'the reason for a bracket without a name' 'Audit (no read of an audit recorded)' "$c1_out"
C1_FIX=c1-auditnoname    c1 'a bracket without an audit name, one read'   ALLOW false recorder.on $all_read
C1_FIX=c1-auditbare C1_SHORT='3 9' c1 'a line-reached file alone is no read of an audit' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-carrier
check_contains 'the bare line names the short read' 'Audit (read through line 3, short form ends at 9)' "$c1_out"
for v in abs dot nospace indent after backslash; do
  C1_FIX="c1-$v" c1 "a rule line spelled '$v', unread" BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
done
C1_FIX=c1-backslash c1 'an audit note with a backslash, read'      ALLOW false recorder.on $all_read
}
out="$(stop_in "$fix/c1-receipt.jsonl" | TMPDIR="$c1_tmp" bash "$stop" 2>&1)"
if [ -z "$out" ]; then ok 'no session id: pass' ALLOW; else bad 'no session id: pass' "$out" ALLOW; fi
crjq="$fix/crjq"; mkdir -p "$crjq"
printf '#!/usr/bin/env bash\n"%s" "$@" | sed "s/$/\\r/"\n' "$(command -v jq)" > "$crjq/jq"; chmod +x "$crjq/jq"
: > "$c1_tmp/claude-rule-gate/c1-cr-$$-recorder.on"
out="$(stop_in "$fix/c1-receipt.jsonl" true "c1-cr-$$" \
  | PATH="$crjq:$PATH" TMPDIR="$c1_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$stop" 2>&1)"
case "$out" in *'"decision":"block"'*) bad 'a jq with CRLF ends: second stop still only warns' "$out" warn ;;
  *systemMessage*) ok 'a jq with CRLF ends: second stop still only warns' warn ;;
  *) bad 'a jq with CRLF ends: second stop still only warns' "$out" warn ;; esac
: > "$c1_tmp/claude-rule-gate/c1-n-$$-recorder.on"
out="$(stop_in "$fix/c1-receipt.jsonl" false "c1-n-$$" \
  | TMPDIR="$c1_tmp" bash "$stop" 2>&1)"
if has_text 'AGENTS.md, CLAUDE.md, Audit (no read of state-2026-02-02T0000Z.md recorded), carrier.md' "$out"; then ok 'the reason names each unread file' found
else bad 'the reason names each unread file' "$out" 'AGENTS.md, CLAUDE.md, Audit (no read of state-2026-02-02T0000Z.md recorded), carrier.md'; fi

echo "== require-receipt.sh: a single broken line never voids the whole transcript =="
# A line cut mid-write sits before the receipt: it is skipped, and the receipt after it is still
# checked against the read record (jq -R + fromjson? per line, not one -s slurp that fails whole).
{ printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"te\n'; cat "$fix/c1-receipt.jsonl"; } > "$fix/c1-broken.jsonl"
C1_FIX=c1-broken c1 'a broken line before the receipt: its unread line still blocks' BLOCK false recorder.on read-main-core.agents read-main-core.claude read-main-core.audit.2026-02-02T0000Z
# shellcheck disable=SC2086 # the marker list splits on purpose
C1_FIX=c1-broken c1 'a broken line before the receipt: all read passes'               ALLOW false recorder.on $all_read

# A receipt before a compaction is stale: its green lines are not checked against the reads the
# compaction ended.
{ cat "$fix/c1-receipt.jsonl"; printf '{"type":"system","subtype":"compact_boundary"}\n'; } > "$fix/c1-stale.jsonl"
C1_FIX=c1-stale c1 'a receipt before a compaction is not checked' ALLOW false recorder.on read-main-core.agents read-main-core.claude

echo "== require-receipt.sh: a missing receipt passes on every stop, the loop guard included =="
stop_verdict() { # transcript, stop_hook_active as a jq literal
  local out
  out="$(stop_in "$1" "$2" '' Stop | bash "$stop" 2>&1)"
  if   has_text '"decision":"block"' "$out"; then printf 'BLOCK'
  elif [ -z "$out" ]; then printf 'ALLOW'; else printf 'ERR'; fi
}
chk_stop() { # label, expected, transcript, stop_hook_active
  local v; v="$(stop_verdict "$3" "$4")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}
chk_stop 'no receipt, first stop'                   ALLOW "$fix/no-receipt.jsonl"   false
chk_stop 'no receipt, stop after a block'           ALLOW "$fix/no-receipt.jsonl"   true
chk_stop 'receipt present, stop after a block'      ALLOW "$fix/with-receipt.jsonl" true
chk_stop 'no receipt, stop_hook_active as a string' ALLOW "$fix/no-receipt.jsonl"   '"true"'
chk_stop 'no receipt after a compaction'            ALLOW "$fix/receipt-then-compact.jsonl" false

echo "== require-receipt.sh: a jq failure while building the block output must still exit 0 =="
# Issue ww3d/playbook#198 pt.3: the jq -cn calls that build this hook's own block/DRIFT
# output had no `|| true`. Shadow jq so that only a `-cn` invocation fails (exit
# 2, like a real jq system error) while every other call (the -Rrs verdict
# computation) still runs for real - found by mutation: removing `|| true` from
# either call leaves this red.
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-cn" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
chmod +x "$stub/jq"
# The UNREAD block is the one a receipt can still cause: a green line with no read behind it.
jq_tmp="$fix/jq-fail-tmp"; mkdir -p "$jq_tmp/claude-rule-gate"; : > "$jq_tmp/claude-rule-gate/jqf-recorder.on"
out="$(stop_in "$fix/c1-receipt.jsonl" false jqf \
  | PATH="$stub:$PATH" TMPDIR="$jq_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$stop" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then
  ok "UNREAD-branch jq failure still exits 0" "rc=0"
else
  bad "UNREAD-branch jq failure still exits 0" "rc=$rc" "rc=0"
fi
rm -f "$stub/jq"

echo "== require-receipt.sh: jq judges only the lines that can matter =="
# A transcript without a SessionStart or compaction line holds nothing to block, so the verdict
# jq never starts (two starts read the event); with such a line it starts once more.
printf '#!/usr/bin/env bash\nprintf "jq\\n" >> "%s"\nexec "%s" "$@"\n' "$calls" "$real_jq" > "$stub/jq"
chmod +x "$stub/jq"
noise="$fix/stop-noise.jsonl"
for i in $(seq 1 200); do
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Arbeit %s"}]}}\n' "$i"
done > "$noise"
stop_jq_starts() { # transcript
  : > "$calls"
  stop_in "$1" false '' Stop | PATH="$stub:$PATH" bash "$stop" >/dev/null 2>&1
  local n=0 l
  while IFS= read -r l; do [ "$l" = jq ] && n=$((n + 1)); done < "$calls"
  echo "$n"
}
expect 'a transcript without markers: the verdict jq does not start' 2 "$(stop_jq_starts "$noise")"
expect 'a transcript with a SessionStart: the verdict jq starts'      3 "$(stop_jq_starts "$fix/with-receipt.jsonl")"
rm -f "$stub/jq"

echo "== require-receipt.sh: the turn end after a compaction (ww3d/playbook#487) =="
rc_proj="$fix/rr-proj"; rc_state="$rc_proj/.agent/state"; mkdir -p "$rc_state" "$cs_gate"
rr() { # session, [stop_hook_active] -> global rr_v ALLOW, BLOCK or WARN, the raw output in rr_out
  rr_out="$(stop_in "$fix/no-receipt.jsonl" "${2:-false}" "$1" | TMPDIR="$cs_tmp" CLAUDE_PROJECT_DIR="$rc_proj" bash "$stop" 2>&1)"
  if has_text '"decision":"block"' "$rr_out"; then rr_v=BLOCK
  elif has_text 'systemMessage' "$rr_out"; then rr_v=WARN
  elif [ -z "$rr_out" ]; then rr_v=ALLOW; else rr_v="ERR $rr_out"; fi
}
# session, boxes
rr_file() { printf '# Restore\n\n## History without a carrier\n\n%s\n' "$2" > "$rc_state/$1-restore.md"; }
rr_lock() { printf 'from=0\nto=1\nneed=compact.restore %s\n' "$rc_state/$1-restore.md" > "$cs_gate/$1-compact-lock"; }
rr_file rr1 '- [x] L1 - human: erledigt -> ww3d/playbook#487'; rr_lock rr1
rr rr1; expect 'restore unread: the turn end is held' BLOCK "$rr_v"
check_contains 'restore unread: the reason says so' 'The turn end is held after the compaction' "$rr_out"
check_contains 'restore unread: it names the file' 'Not read in full yet' "$rr_out"
for w in helper cross-check; do check_not_contains "restore unread: the stop names no $w" "$w" "$rr_out"; done
rr rr1 true; expect 'restore unread: the second stop of the turn warns' WARN "$rr_v"
for w in helper cross-check; do check_not_contains "restore unread: the warning names no $w" "$w" "$rr_out"; done
: > "$cs_gate/rr1-read-main-compact.restore"
rr rr1; expect 'restore read, every box ticked: the turn ends' ALLOW "$rr_v"
rr_file rr2 '- [ ] L4 2026-11-12T1004Z promise: Ich melde den Stand.'; rr_lock rr2; : > "$cs_gate/rr2-read-main-compact.restore"
rr rr2; expect 'restore read, a box open: the turn end is held' BLOCK "$rr_v"
check_contains 'a box open: the reason counts it' '1 open boxes in' "$rr_out"
check_not_contains 'a box open: not held as unread' 'Not read in full yet' "$rr_out"
rr rr2 true; expect 'a box open: the second stop warns' WARN "$rr_v"
rm -f "$cs_gate/rr2-compact-lock"
rr rr2; expect 'a box open without a lock: the turn end is still held' BLOCK "$rr_v"
rr_file rr2 '- [x] L4 2026-11-12T1004Z promise: Ich melde den Stand. -> ww3d/playbook#487'
rr rr2; expect 'the box ticked: the turn ends' ALLOW "$rr_v"
rr rr3; expect 'no lock and no restore file: the turn ends' ALLOW "$rr_v"
rr_file rr4 '- [ ] L1 - human: offen'
rr rr5; expect "another session's open box holds nothing" ALLOW "$rr_v"
# Boxes count only in the history and the changed carriers; a "- [ ]" line quoted in a helper result is text.
rr_quoted() { # session, history box, carrier box -> a restore file whose helper result quotes two boxes
  printf '# Restore\n\n## History without a carrier\n\n%s\n\n## Carriers changed since checked\n\n%s\n\n## Helper results since the cursor\n\n### L9 2026-11-12T1009Z\n\nBefund:\n- [ ] x\n- [ ] x\n\n## Tool additions\n\n_none_\n' \
    "$2" "$3" > "$rc_state/$1-restore.md"
}
rr_quoted rr6 '- [ ] L4 2026-11-12T1004Z promise: Ich melde den Stand.' '- [ ] ww3d/demo#7 changed since 2026-11-12T10:00:00Z: Export'
rr rr6; expect 'quoted boxes in a helper result: the real boxes hold the turn end' BLOCK "$rr_v"
check_contains 'quoted boxes in a helper result: only the history and the carrier box count' '2 open boxes in' "$rr_out"
rr_quoted rr6 '- [x] L4 promise -> ww3d/playbook#487' '- [ ] ww3d/demo#7 changed since 2026-11-12T10:00:00Z: Export'
rr rr6; expect 'an open box of a changed carrier holds the turn end' BLOCK "$rr_v"
rr_quoted rr6 '- [x] L4 promise -> ww3d/playbook#487' '- [x] ww3d/demo#7 changed -> gelesen'
rr rr6; expect 'every real box ticked, two quoted in a helper result: the turn ends' ALLOW "$rr_v"

finish
