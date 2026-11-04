#!/usr/bin/env bash
# Hook suite section: require-receipt.sh, the Stop hook against the read receipt
# Run alone: bash .claude/hooks/tests/cases/require-receipt.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== require-receipt.sh agrees with the gate =="
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
    # quote-only: the H1 alone is quoted in a code fence, with no "## Konventionen"
    # heading anywhere in the same text - fix #1 (issue ww3d/playbook#198 pt.1) means this
    # must BLOCK, not be read as a receipt.
    no-receipt|quote-only|trunc-no-receipt) want=BLOCK ;;
    # The new block: both lines quoted mid-sentence, "Core" only as a word start, an echo whose
    # result lacks the Memory line - none is a receipt.
    block-quoted-midline|block-head-midline|block-mem-midline|block-core-prefix|echo-head-only) want=BLOCK ;;
    # The memory line alone, the two lines in two messages and the old H1 format are no receipt.
    mem-only|split-messages|old-format) want=BLOCK ;;
    # echo-*: the receipt printed by a command counts only where the command ran
    # without error and its own result shows it (ww3d/playbook#271, same rule as ww3d/playbook#273).
    echo-unrun|echo-redirect|echo-refused) want=BLOCK ;;
    # A compaction or /clear ends the receipt before it; a further start (resume, fork,
    # startup) in the same transcript does not (ww3d/playbook#337).
    receipt-then-compact|receipt-then-compact-hook|echo-then-compact|receipt-then-clear) want=BLOCK ;;
    drift) want=DRIFT ;;
    # trunc-then-receipt: a broken line sits between the session start and a
    # real, full receipt - fix #2 (issue ww3d/playbook#198 pt.2) means the broken line is
    # skipped and the receipt after it still counts.
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
  # The hook ends silent on ALLOW and on a failed jq alike: input the hook cannot parse must not read as ALLOW.
  payload="$(stop_in "$fix/${C1_FIX:-c1-receipt}.jsonl" "$active" "$sid")"
  if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then bad "$label" "NOINPUT" "$want"; return; fi
  out="$(printf '%s' "$payload" | TMPDIR="$c1_tmp" CLAUDE_PROJECT_DIR="$repo_root" bash "$stop" 2>&1)"
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
if has_text 'AGENTS.md, CLAUDE.md, Audit, carrier.md' "$out"; then ok 'the reason names each unread file' found
else bad 'the reason names each unread file' "$out" 'AGENTS.md, CLAUDE.md, Audit, carrier.md'; fi

echo "== require-receipt.sh: a single broken line never voids the whole transcript =="
# trunc-no-receipt is the case that demonstrates the actual bug: before fix #2,
# jq -rs (slurp) fails whole on the one unparsable line, the verdict comes back
# empty, matches no case in the BLOCK/DRIFT case statement, and the hook exits
# 0 with no output at all - i.e. ALLOW, even though no real receipt exists
# anywhere in the transcript. Re-asserted here by name (in addition to the loop
# above) since it is the fix's actual red/green case, not merely the shape the
# imported suite already asked for.
out="$(stop_in "$fix/trunc-no-receipt.jsonl" false '' Stop | bash "$stop" 2>&1)"
if has_text '"decision":"block"' "$out"; then
  ok "a broken line does not silently allow an unreceipted transcript" "BLOCK"
else
  bad "a broken line does not silently allow an unreceipted transcript" "not BLOCK" "BLOCK"
fi

echo "== require-receipt.sh: stop_hook_active releases a repeated block (issue ww3d/playbook#171 (c)) =="
# The loop guard: on a stop that already follows a Stop-hook block, a still
# missing receipt must not block again but end the turn with a warning. Paired
# with the same transcript on a first stop (must still BLOCK), a receipted
# transcript on a follow-up stop (must stay a silent ALLOW, no stray warning),
# and a non-boolean field value (must not count as true).
stop_verdict() { # transcript, stop_hook_active as a jq literal
  local out
  out="$(stop_in "$1" "$2" '' Stop | bash "$stop" 2>&1)"
  if   has_text '"decision":"block"' "$out"; then printf 'BLOCK'
  elif has_text 'blocked this stop once already' "$out"; then printf 'WARN'
  elif [ -z "$out" ]; then printf 'ALLOW'; else printf 'ERR'; fi
}
chk_stop() { # label, expected, transcript, stop_hook_active
  local v; v="$(stop_verdict "$3" "$4")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}
chk_stop 'no receipt, first stop'                   BLOCK "$fix/no-receipt.jsonl"   false
chk_stop 'no receipt, stop after a block'           WARN  "$fix/no-receipt.jsonl"   true
chk_stop 'receipt present, stop after a block'      ALLOW "$fix/with-receipt.jsonl" true
chk_stop 'no receipt, stop_hook_active as a string' BLOCK "$fix/no-receipt.jsonl"   '"true"'
out="$(stop_in "$fix/no-receipt.jsonl" | bash "$stop" 2>&1)"
if has_text 'do not repeat it unprompted in later turns' "$out"; then
  ok 'block text says once, not per turn (ww3d/playbook#337)' found
else
  bad 'block text says once, not per turn (ww3d/playbook#337)' 'not found' found
fi

echo "== require-receipt.sh: a jq failure while building the verdict output must still exit 0 =="
# Issue ww3d/playbook#198 pt.3: the two jq -cn calls that build this hook's own BLOCK/DRIFT
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
out="$(stop_in "$fix/no-receipt.jsonl" false '' Stop \
  | PATH="$stub:$PATH" bash "$stop" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then
  ok "BLOCK-branch jq failure still exits 0" "rc=0"
else
  bad "BLOCK-branch jq failure still exits 0" "rc=$rc" "rc=0"
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

finish
