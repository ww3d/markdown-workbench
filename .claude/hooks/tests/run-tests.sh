#!/usr/bin/env bash
#
# Behaviour tests for require-receipt.sh, require-rule-read.sh and
# read-confirm.sh.
#
# Ported from ww3d/rc-control@3de127c (.claude/hooks/tests/run-tests.sh), which
# also covered a fourth hook, gate-actions.sh, that this repo does not carry.
# Dropped entirely: the ~30 DENY/ALLOW pairs there that classify git/gh
# "acting" commands against a single global receipt, and the parent/subagent
# transcript-redirection tests — both are specific to that hook's own
# mechanism, which require-rule-read.sh does not share (it classifies by
# tool+trigger, not by a git/gh command allowlist, and never redirects to a
# parent transcript). Reused as-is: the "require-receipt.sh agrees with the
# gate" fixture-driven block. Adapted to require-rule-read.sh's own trigger
# map and its own "rule | <path> |" receipt line: the paired-DENY/ALLOW shape,
# the fail-open-on-missing-helper mutation test, and the jq-exit-2 inversion
# mutation test that AGENTS.md § "Always" asks for (a test that forces the
# success path of a silent catch-and-degrade).
#
# Every case states its expected verdict, and the ones that matter come in
# pairs: a command that must be refused next to one that must not. A gate is
# only as good as its counter-case — a suite of nothing but DENY/BLOCK lines
# passes just as well when the gate refuses everything.
#
# Usage:  bash .claude/hooks/tests/run-tests.sh
# Exit:   0 when every case holds, 1 otherwise.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
hooks="$(cd "$here/.." && pwd)"
repo_root="$(cd "$hooks/../.." && pwd)"
stop="$hooks/require-receipt.sh"
ruleread="$hooks/require-rule-read.sh"
readconfirm="$hooks/read-confirm.sh"

fix="$(mktemp -d)"
trap 'rm -rf "$fix"' EXIT
bash "$here/mkfixtures.sh" "$fix" >/dev/null

pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$1" "$2"; }
bad() { fail=$((fail + 1)); printf '  FAIL %-52s %s (expected %s)\n' "$1" "$2" "$3"; }

echo "== require-receipt.sh agrees with the gate =="
for f in no-receipt with-receipt resumed quote-only drift trunc-no-receipt trunc-then-receipt; do
  out="$(jq -cn --arg t "$fix/$f.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' | bash "$stop" 2>&1)"
  if   printf '%s' "$out" | grep -q '"decision":"block"'; then v=BLOCK
  elif printf '%s' "$out" | grep -q 'systemMessage'; then v=DRIFT
  elif [ -z "$out" ]; then v=ALLOW; else v="ERR"; fi
  case "$f" in
    # quote-only: the H1 alone is quoted in a code fence, with no "## Konventionen"
    # heading anywhere in the same text - fix #1 (issue #198 pt.1) means this
    # must BLOCK, not be read as a receipt.
    no-receipt|resumed|quote-only|trunc-no-receipt) want=BLOCK ;;
    drift) want=DRIFT ;;
    # trunc-then-receipt: a broken line sits between the session start and a
    # real, full receipt - fix #2 (issue #198 pt.2) means the broken line is
    # skipped and the receipt after it still counts.
    *) want=ALLOW ;;
  esac
  if [ "$v" = "$want" ]; then ok "stop hook on $f" "$v"; else bad "stop hook on $f" "$v" "$want"; fi
done

echo "== require-receipt.sh: a single broken line never voids the whole transcript =="
# trunc-no-receipt is the case that demonstrates the actual bug: before fix #2,
# jq -rs (slurp) fails whole on the one unparsable line, the verdict comes back
# empty, matches no case in the BLOCK/DRIFT case statement, and the hook exits
# 0 with no output at all - i.e. ALLOW, even though no real receipt exists
# anywhere in the transcript. Re-asserted here by name (in addition to the loop
# above) since it is the fix's actual red/green case, not merely the shape the
# imported suite already asked for.
out="$(jq -cn --arg t "$fix/trunc-no-receipt.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' | bash "$stop" 2>&1)"
if printf '%s' "$out" | grep -q '"decision":"block"'; then
  ok "a broken line does not silently allow an unreceipted transcript" "BLOCK"
else
  bad "a broken line does not silently allow an unreceipted transcript" "not BLOCK" "BLOCK"
fi

echo "== require-receipt.sh: a jq failure while building the verdict output must still exit 0 =="
# Issue #198 pt.3: the two jq -cn calls that build this hook's own BLOCK/DRIFT
# output had no `|| true`. Shadow jq so that only a `-cn` invocation fails (exit
# 2, like a real jq system error) while every other call (the -Rrs verdict
# computation) still runs for real - found by mutation: removing `|| true` from
# either call leaves this red.
stub="$fix/stub"; mkdir -p "$stub"
real_jq="$(command -v jq)"
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-cn" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
chmod +x "$stub/jq"
out="$(jq -cn --arg t "$fix/no-receipt.jsonl" '{transcript_path: $t, hook_event_name: "Stop", stop_hook_active: false}' \
  | PATH="$stub:$PATH" bash "$stop" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then
  ok "BLOCK-branch jq failure still exits 0" "rc=0"
else
  bad "BLOCK-branch jq failure still exits 0" "rc=$rc" "rc=0"
fi
rm -f "$stub/jq"

echo "== require-rule-read.sh: receipt recognised in a tool_use command, not just text =="
rule_event() { # transcript, tool, command, session
  jq -cn --arg t "$1" --arg n "$2" --arg c "$3" --arg s "$4" \
    '{session_id: $s, transcript_path: $t, cwd: "/tmp", hook_event_name: "PreToolUse",
      tool_name: $n, tool_input: ({command: $c} | if $c == "" then {} else . end)}'
}
rule_verdict() {
  local out rc
  out="$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$repo_root" bash "$ruleread" 2>&1)"; rc=$?
  if   printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then printf 'DENY'
  elif [ -z "$out" ] && [ "$rc" = 0 ]; then printf 'ALLOW'
  else printf 'ERR(rc=%s)' "$rc"; fi
}
sid_n=0
next_sid() { sid_n=$((sid_n + 1)); printf 'probe-rule-%s' "$sid_n"; }
chk_rule() { # label, expected, transcript, tool, command
  local v; v="$(rule_verdict "$(rule_event "$3" "$4" "$5" "$(next_sid)")")"
  if [ "$v" = "$2" ]; then ok "$1" "$v"; else bad "$1" "$v" "$2"; fi
}

chk_rule 'no rule receipt at all'                  DENY  "$fix/rule-no-receipt.jsonl"      Bash 'gh issue create --title x'
chk_rule 'rule receipt as its own text block'      ALLOW "$fix/rule-receipt-text.jsonl"    Bash 'gh issue create --title x'
# The new case: the receipt line never appears as a standalone assistant text
# entry, only inside a tool_use's .input.command (an echo). Before this fix,
# receipt_present() only looked at type=="text" blocks, so this case DENYed -
# the point-of-use gate stayed blocked even though the session had emitted the
# exact receipt line, just via a command instead of a closing turn of text.
chk_rule 'rule receipt only inside a tool_use command (new)' ALLOW "$fix/rule-receipt-toolcmd.jsonl" Bash 'gh issue create --title x'

echo "== require-rule-read.sh: fail-open on a missing transcript, like require-receipt.sh =="
chk_rule 'transcript missing'   ALLOW "$fix/nope.jsonl"  Bash 'gh issue create --title x'
# An EMPTY transcript is different from a missing one: the file reads as a
# valid, empty jq input (`[]`), so the hook can positively determine "no
# receipt anywhere" rather than merely failing to read - and DENYs on that
# evidence, same as any other transcript with no receipt in it. This is
# existing, untouched behaviour (receipt_present() unchanged for this case by
# task 2's fix); asserted here so a future change to that fail-open boundary
# does not slip past unnoticed.
chk_rule 'transcript empty (no receipt to find, not a read failure)' DENY "$fix/empty.jsonl" Bash 'gh issue create --title x'
chk_rule 'read-only command, no trigger mapped' ALLOW "$fix/rule-no-receipt.jsonl" Bash 'git status --short'

echo "== require-rule-read.sh: a missing helper degrades to allow, never to block =="
# Only jq: the hook guards it explicitly (`command -v jq >/dev/null 2>&1 ||
# exit 0`, line ~44) precisely because it is the one dependency that is not
# guaranteed to exist everywhere bash does. cat, by contrast, is not something
# this hook defends against losing - `input="$(cat)"` is a bare top-level
# assignment, so a missing cat would exit the whole script under `set -e`
# with cat's own exit code, not 0. That is outside what "fail-open by design"
# in the header claims (it names jq, not cat), so it is not asserted here.
printf '#!/usr/bin/env bash\nexit 127\n' > "$stub/jq"
chmod +x "$stub/jq"
out="$(printf '%s' "$(rule_event "$fix/rule-no-receipt.jsonl" Bash 'gh issue create --title x' "$(next_sid)")" \
  | CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'deny'; then
  ok "without jq" "ALLOW rc=0"
else
  bad "without jq" "rc=$rc out=$out" "ALLOW rc=0"
fi
rm -f "$stub/jq"

echo "== require-rule-read.sh: a jq failure in receipt_present() must still allow, never block =="
# receipt_present() reads its answer from a `jq -Rrs ... || true` call (line by
# line, REQ-017's own tool_use support plus the fail-closed reading fix -
# reads -Rrs as ONE combined flag, not the old -rs slurp); anything other than
# the literal string "false" counts as present (fail-open). Shadow jq so that
# call fails (exit 2) while the earlier `command -v jq` probe still finds the
# stub and proceeds past it.
cat > "$stub/jq" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-Rrs" ] && exit 2; done
exec "$real_jq" "\$@"
STUB
chmod +x "$stub/jq"
out="$(printf '%s' "$(rule_event "$fix/rule-no-receipt.jsonl" Bash 'gh issue create --title x' "$(next_sid)")" \
  | CLAUDE_PROJECT_DIR="$repo_root" PATH="$stub:$PATH" bash "$ruleread" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'deny'; then
  ok "receipt_present() jq failure" "ALLOW rc=0"
else
  bad "receipt_present() jq failure" "rc=$rc out=$out" "ALLOW rc=0"
fi
rm -f "$stub/jq"

echo "== read-confirm.sh: Skills / Memory / OK-per-group / SHA-cache =="
rc_root="$fix/rc-root"
mkdir -p "$rc_root/.claude/skills/beispiel-skill" "$rc_root/.claude/skills/zweiter-skill" \
         "$rc_root/docs/decisions"
printf '# Test Project\n' > "$rc_root/CLAUDE.md"
printf '# Agents\n' > "$rc_root/AGENTS.md"
printf '1.0.0\n' > "$rc_root/VERSION"
cat > "$rc_root/.claude/skills/beispiel-skill/SKILL.md" <<'EOF'
---
name: beispiel-skill
description: 'ein Testskill'
metadata:
  version: "1.2.3"
  source: test
---
# Beispiel
EOF
cat > "$rc_root/.claude/skills/zweiter-skill/SKILL.md" <<'EOF'
---
name: zweiter-skill
description: 'noch ein Testskill'
metadata:
  version: "0.1.0"
  source: test
---
# Zweiter
EOF
printf '# decisions readme\n' > "$rc_root/docs/decisions/README.md"
printf '# log a\n' > "$rc_root/docs/decisions/2026-01-01T0000-a.md"
printf '# log b\n' > "$rc_root/docs/decisions/2026-02-02T0000-b.md"
printf '# docs readme\n' > "$rc_root/docs/README.md"

rc_tmp="$fix/rc-tmp"; mkdir -p "$rc_tmp"
rc_config="$fix/rc-config-empty"; mkdir -p "$rc_config"

run_readconfirm() {
  CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$rc_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm"
}

check_contains() { # label, needle, haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1" "found"
  else bad "$1" "not found: $2" "found"; fi
}
check_not_contains() { # label, needle, haystack
  if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "found: $2" "not found"
  else ok "$1" "not found"; fi
}

ctx1="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"

check_contains 'Skills group header present'     '## Skills' "$ctx1"
check_contains 'skill beispiel-skill listed'      '- beispiel-skill v1.2.3' "$ctx1"
check_contains 'skill zweiter-skill listed'       '- zweiter-skill v0.1.0' "$ctx1"

ok_count="$(printf '%s\n' "$ctx1" | grep -c '^OK$' || true)"
if [ "${ok_count:-0}" = "4" ]; then ok 'all four groups close with their own OK' "$ok_count"
else bad 'all four groups close with their own OK' "${ok_count:-0}" "4"; fi

check_contains 'Memory honest fallback when nothing is found' \
  'Memory-Stand: — (nicht verfuegbar in dieser Umgebung)' "$ctx1"

check_contains 'docs/decisions README skipped in count and sort (already fixed, regression check)' \
  'docs/decisions/ — 2 Logs, neuestes 2026-02-02' "$ctx1"
check_not_contains 'docs/README.md not listed as an individual doc line' \
  '- docs/README.md' "$ctx1"

# slugify() itself, in isolation: a backslash must become '-' like every other
# separator it lists (':', '/', '.'). GNU tr treats an unescaped '\/' in its
# SET1 as an escape for a bare '/', silently dropping the backslash CHARACTER
# from the set entirely - measured before this fix: 'D:\a.b/c:d' came out as
# 'D-\a-b-c-d' (an untranslated backslash still in the result), not
# 'D--a-b-c-d'. The two-cache-key collision this class of bug risks (two
# different project roots slugifying to the same cache file) is exactly what
# read-confirm.sh's own comment above the function promises does not happen.
slug_out="$(printf '%s' 'D:\a.b/c:d' | tr ':\\/.' '----')"
if [ "$slug_out" = 'D--a-b-c-d' ]; then ok 'slugify translates a backslash like every other separator' "$slug_out"
else bad 'slugify translates a backslash like every other separator' "$slug_out" 'D--a-b-c-d'; fi

# Memory group, positive case: a MEMORY.md index this environment CAN see. Its
# own TMPDIR keeps this run's cache writes out of the cache-test sequence below.
rc_config_hit="$fix/rc-config-hit"
mem_slug="$(printf '%s' "$rc_root" | tr ':\\/.' '----')"
mem_dir="$rc_config_hit/projects/$mem_slug/memory"
mkdir -p "$mem_dir"
cat > "$mem_dir/MEMORY.md" <<'EOF'
# Memory Index
- [Eins](eins.md) — hook
- [Zwei](zwei.md) — hook
- [Drei](drei.md) — hook
EOF
ctx_mem="$(CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$fix/rc-tmp-mem" CLAUDE_CONFIG_DIR="$rc_config_hit" bash "$readconfirm" \
  | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'Memory counts real MEMORY.md entries when found' 'Memory: 3 Eintraege (MEMORY.md)' "$ctx_mem"

# Negative case (review round 1 of #233): only a FOREIGN project's memory
# exists under this CLAUDE_CONFIG_DIR - the own slug never matches, so the
# honest "not available" line is expected, not the fallback that used to pick
# up whichever memory/MEMORY.md it found first regardless of whose it was.
rc_config_foreign="$fix/rc-config-foreign"
foreign_dir="$rc_config_foreign/projects/some-other-project/memory"
mkdir -p "$foreign_dir"
printf '# Memory Index\n- [Eins](eins.md) — hook\n' > "$foreign_dir/MEMORY.md"
ctx_foreign="$(CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$fix/rc-tmp-foreign" CLAUDE_CONFIG_DIR="$rc_config_foreign" bash "$readconfirm" \
  | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'a foreign project memory is never reported as this one'"'"'s own' \
  'Memory-Stand: — (nicht verfuegbar in dieser Umgebung)' "$ctx_foreign"

# SHA-cache: run 1 (above, ctx1) got the full line; run 2, file unchanged,
# must get the short line; then the file changes and run 3 gets the full line
# again. All three runs share $rc_tmp, so the cache file persists between them.
check_contains 'run 1 lists CLAUDE.md in full (nothing cached yet)' \
  '- CLAUDE.md @ projekt OK' "$ctx1"
ctx2="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'unchanged CLAUDE.md gets the short cache line on run 2' \
  '- CLAUDE.md: unveraendert seit' "$ctx2"

printf '# Test Project (geaendert)\n' > "$rc_root/CLAUDE.md"
ctx3="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
check_contains 'a changed CLAUDE.md gets the full line again on run 3' \
  '- CLAUDE.md @ projekt OK' "$ctx3"
check_not_contains 'a changed CLAUDE.md is not reported as unveraendert' \
  '- CLAUDE.md: unveraendert seit' "$ctx3"

echo
printf '%s ok, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
