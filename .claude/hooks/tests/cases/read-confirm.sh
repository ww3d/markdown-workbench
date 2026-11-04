#!/usr/bin/env bash
# Hook suite section: read-confirm.sh, the read-receipt block, the version check and the Stop-hook line
# Run alone: bash .claude/hooks/tests/cases/read-confirm.sh
#   all sections: bash .claude/hooks/tests/run-tests.sh
# shellcheck disable=SC2016 # the test inputs hold shell syntax ($(...), $VAR) as text, never to expand
# shellcheck source=SCRIPTDIR/../harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../harness.sh"

echo "== read-confirm.sh: the read-receipt block =="
use_rc_root
# Line filters without a process: the lines of a text that match a regex, one per line.
rc_lines_re() { # regex, text
  local l
  while IFS= read -r l; do [[ $l =~ $1 ]] && printf '%s\n' "$l"; done <<<"$2"
}
rc_count_re() { # regex, text -> the number of lines that match
  local n=0 l
  while IFS= read -r l; do [[ $l =~ $1 ]] && n=$((n + 1)); done <<<"$2"
  echo "$n"
}

ctx1="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
n_lines="$(rc_count_re . "$ctx1")"
if [ "${n_lines:-0}" -eq 9 ]; then ok 'instruction plus a block of eight lines' "$n_lines"; else bad 'instruction plus a block of eight lines' "$n_lines" '9'; fi
check_contains 'heading says once per start (ww3d/playbook#337)' \
  'give the block below once per session start or compaction, never unprompted per turn' "$ctx1"
check_contains 'heading: the session sets read itself' 'turn "- … not read" into "+ … read" only for a file you read in full' "$ctx1"
check_contains 'heading: an unread file stays red' 'an unread file stays "- … not read"' "$ctx1"
check_contains 'heading: a later rule file gets its own line' '"+ <file> <version> <sha> read (rule)"' "$ctx1"
check_contains 'the block opens with its title line' '── Read receipt ──' "$ctx1"
last_line="$(printf '%s\n' "$ctx1" | tail -n 1)"
if [ "$last_line" = '──────────────────────────────────────────────' ]; then ok 'the block ends with its closing line' found
else bad 'the block ends with its closing line' "$last_line" 'the closing line'; fi
sha_agents="$(git hash-object "$rc_root/AGENTS.md")"; sha_claude="$(git hash-object "$rc_root/CLAUDE.md")"
sha_audit="$(git hash-object "$rc_root/audit/state-2026-02-02T0000Z.md")"
check_line 'head line: version, then Core alone' 'Playbook 1.0.0 | Core' "$ctx1"
check_line 'AGENTS.md not imported: red, not read'      "- AGENTS.md    1.0.0    ${sha_agents:0:7}   not read" "$ctx1"
check_line 'CLAUDE.md loaded by the start: green'       "+ CLAUDE.md    (repo)   ${sha_claude:0:7}   read" "$ctx1"
check_line 'audit line: the newest audit, named in brackets' \
  "- Audit        —        ${sha_audit:0:7}   not read (state-2026-02-02T0000Z.md)" "$ctx1"
if [ "$(rc_count_re '^\+ ' "$ctx1")" = 1 ]; then ok 'the template marks only the loaded file read' '1'
else bad 'the template marks only the loaded file read' "$(rc_lines_re '^\+ ' "$ctx1")" 'only CLAUDE.md'; fi
check_contains 'heading: the Stop hook checks green lines' 'the Stop hook checks every green line against the read record' "$ctx1"
# A caller's Git Bash path switches (ww3d/playbook#507) reach no hook: lib/stdin.sh drops them, and the SHAs stay.
mkdir -p "$fix/rc-tmp-npc"
ctx_npc="$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' CLAUDE_PROJECT_DIR="$rc_root" TMPDIR="$fix/rc-tmp-npc" \
  CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
check_line 'MSYS_NO_PATHCONV from the caller: AGENTS.md keeps its SHA' \
  "- AGENTS.md    1.0.0    ${sha_agents:0:7}   not read" "$ctx_npc"
# A1: with "@AGENTS.md" in CLAUDE.md the start loads both; the hook writes both into the read record.
a1_root="$fix/rc-a1"; mkdir -p "$a1_root"; git init -q "$a1_root"
printf '# P\n\n@AGENTS.md\n' > "$a1_root/CLAUDE.md"; printf '# A\n' > "$a1_root/AGENTS.md"; printf '1.0.0\n' > "$a1_root/VERSION"
a1_tmp="$fix/rc-tmp-a1"; mkdir -p "$a1_tmp"
ctx_a1="$(printf '{"source":"startup","session_id":"a1-%s"}' "$$" | CLAUDE_PROJECT_DIR="$a1_root" TMPDIR="$a1_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
sha_a1="$(git hash-object "$a1_root/AGENTS.md")"
check_line 'AGENTS.md imported by CLAUDE.md: green' "+ AGENTS.md    1.0.0    ${sha_a1:0:7}   read" "$ctx_a1"
present_file 'the start records CLAUDE.md as read' "$a1_tmp/claude-rule-gate/a1-$$-read-main-core.claude"
present_file 'the start records AGENTS.md as read' "$a1_tmp/claude-rule-gate/a1-$$-read-main-core.agents"
# A compaction injects CLAUDE.md with its imports again (ww3d/playbook#487): both stay green and recorded,
# while the rule reads before it go.
: > "$a1_tmp/claude-rule-gate/a1-$$-read-main-pr"
ctx_a1c="$(printf '{"source":"compact","session_id":"a1-%s"}' "$$" | CLAUDE_PROJECT_DIR="$a1_root" TMPDIR="$a1_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
present_file 'after a compaction CLAUDE.md is recorded as read again' "$a1_tmp/claude-rule-gate/a1-$$-read-main-core.claude"
present_file 'after a compaction AGENTS.md is recorded as read again' "$a1_tmp/claude-rule-gate/a1-$$-read-main-core.agents"
absent_file 'after a compaction a rule read before it is gone' "$a1_tmp/claude-rule-gate/a1-$$-read-main-pr"
check_line 'after a compaction AGENTS.md stays green' "+ AGENTS.md    1.0.0    ${sha_a1:0:7}   read" "$ctx_a1c"
check_contains 'after a compaction CLAUDE.md stays green' '+ CLAUDE.md    (repo)' "$ctx_a1c"
check_not_contains 'after a compaction no line asks to read a core file again' 'read it again' "$ctx_a1c"
# Counter: a resume keeps the start's reads, both green and recorded.
ctx_a1r="$(printf '{"source":"resume","session_id":"a1-%s"}' "$$" | CLAUDE_PROJECT_DIR="$a1_root" TMPDIR="$a1_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
check_line 'a resume keeps AGENTS.md green' "+ AGENTS.md    1.0.0    ${sha_a1:0:7}   read" "$ctx_a1r"
present_file 'a resume records CLAUDE.md as read' "$a1_tmp/claude-rule-gate/a1-$$-read-main-core.claude"
: > "$a1_tmp/claude-rule-gate/a1-$$-recorder.on"; : > "$a1_tmp/claude-rule-gate/a1-$$-read-main-pr"
printf '{"source":"clear","session_id":"a1-%s"}' "$$" | CLAUDE_PROJECT_DIR="$a1_root" TMPDIR="$a1_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" >/dev/null
absent_file 'a /clear ends the rule reads before it' "$a1_tmp/claude-rule-gate/a1-$$-read-main-pr"
present_file 'a /clear keeps the sign that the record runs' "$a1_tmp/claude-rule-gate/a1-$$-recorder.on"
a1_variant() { # label, expected mark (+ or -), CLAUDE.md text
  printf '%b' "$3" > "$a1_root/CLAUDE.md"
  local got; got="$(CLAUDE_PROJECT_DIR="$a1_root" TMPDIR="$a1_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" \
    | jq -r '.hookSpecificOutput.additionalContext')"
  got="$(rc_lines_re '^[-+] AGENTS.md' "$got")"
  if [ "${got:0:1}" = "$2" ]; then ok "$1" "$2"; else bad "$1" "$got" "$2"; fi
}
a1_variant 'a BOM before the import line'      + '\xef\xbb\xbf@AGENTS.md\n# P\n'
a1_variant 'an import line with CRLF'          + '# P\r\n@AGENTS.md\r\n'
a1_variant 'the import inside a code fence'    - '# P\n```\n@AGENTS.md\n```\n'
a1_variant '@AGENTS.mdx is no import'           - '# P\n@AGENTS.mdx\n'
a1_variant 'the import inside a ~~~ fence'      - '# P\n~~~\n@AGENTS.md\n~~~\n'
a1_variant 'a ``` line inside a ```` fence'     - '# P\n````\n```\n@AGENTS.md\n````\n'
printf '# P\nsee @AGENTS.md here\n' > "$a1_root/CLAUDE.md"
ctx_a1b="$(CLAUDE_PROJECT_DIR="$a1_root" TMPDIR="$a1_tmp" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
check_line 'an @AGENTS.md inside a sentence is no import' "- AGENTS.md    1.0.0    ${sha_a1:0:7}   not read" "$ctx_a1b"
check_contains 'heading names the diff fence' 'inside a ```diff fence' "$ctx1"
check_contains 'rule index: none read at the start, of the count' 'Rules 0 of 2 read' "$ctx1"
check_not_contains 'rule index: the trigger names are gone' 'code docs' "$ctx1"
check_contains 'skills counted'                   'Rules 0 of 2 read · Skills 2 · Stop hook' "$ctx1"
check_contains 'Memory honest fallback when nothing is found' \
  'Memory: — (not available in this environment)' "$ctx1"
check_not_contains 'no newer-version line without a network answer' 'Newer playbook version' "$ctx1"
# The old audit name is read until playbook 26.0.0 (ww3d/playbook#356): the newest stamp wins
# across both names.
printf '# audit c\n' > "$rc_root/audit/ist-stand-2026-03-03T0000Z.md"
check_contains 'a newer audit under the old name is still the newest' \
  'not read (ist-stand-2026-03-03T0000Z.md)' "$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
rm "$rc_root/audit/ist-stand-2026-03-03T0000Z.md"
# The new place docs/audit/ is read first; audit/ is read until playbook 26.0.0, the first MAJOR
# after the move. The newest stamp wins across both places, the new place on a tie; the SHA shows
# that the right file was hashed.
mkdir -p "$rc_root/docs/audit"
printf '# audit d\n' > "$rc_root/docs/audit/state-2026-04-04T0000Z.md"
sha_audit_d="$(git hash-object "$rc_root/docs/audit/state-2026-04-04T0000Z.md")"
check_line 'a newer audit under docs/audit/ is the newest' \
  "- Audit        —        ${sha_audit_d:0:7}   not read (state-2026-04-04T0000Z.md)" "$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
printf '# audit e\n' > "$rc_root/audit/state-2026-05-05T0000Z.md"
check_contains 'a newer audit under audit/ still wins over docs/audit/' \
  'not read (state-2026-05-05T0000Z.md)' "$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
printf '# audit f\n' > "$rc_root/docs/audit/state-2026-05-05T0000Z.md"
sha_audit_f="$(git hash-object "$rc_root/docs/audit/state-2026-05-05T0000Z.md")"
check_line 'the same stamp at both places: docs/audit/ wins' \
  "- Audit        —        ${sha_audit_f:0:7}   not read (state-2026-05-05T0000Z.md)" "$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
rm -r "$rc_root/docs" "$rc_root/audit/state-2026-05-05T0000Z.md"

# A changed core file shows its new SHA.
printf '# Test Project (geaendert)\n' > "$rc_root/CLAUDE.md"
ctx2="$(run_readconfirm | jq -r '.hookSpecificOutput.additionalContext')"
sha_claude2="$(git hash-object "$rc_root/CLAUDE.md")"
check_contains 'a changed CLAUDE.md shows its new SHA' "(repo)   ${sha_claude2:0:7}" "$ctx2"
check_not_contains 'the old CLAUDE.md SHA is gone' "(repo)   ${sha_claude:0:7}" "$ctx2"

# No rule index, no audit, no skills: every absent piece is named, none dropped.
bare="$fix/rc-bare"; mkdir -p "$bare"; git init -q "$bare"
ctx_bare="$(CLAUDE_PROJECT_DIR="$bare" TMPDIR="$fix/rc-tmp-bare" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
check_line 'bare project: version unknown'   'Playbook unknown | Core' "$ctx_bare"
check_line 'bare project: AGENTS.md missing is a sync error' '- AGENTS.md    —        —         missing (sync error)' "$ctx_bare"
check_line 'bare project: CLAUDE.md missing'                '- CLAUDE.md    (repo)   —         missing' "$ctx_bare"
check_line 'bare project: no audit'            '- Audit        —        —         not found' "$ctx_bare"
printf '1.0.0\n' > "$bare/VERSION"
ctx_bare_v="$(CLAUDE_PROJECT_DIR="$bare" TMPDIR="$fix/rc-tmp-bare" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
check_line 'a missing AGENTS.md shows no version' '- AGENTS.md    —        —         missing (sync error)' "$ctx_bare_v"
printf '124.10.10\n' > "$bare/VERSION"; printf '# A\n' > "$bare/AGENTS.md"
ctx_bare_long="$(CLAUDE_PROJECT_DIR="$bare" TMPDIR="$fix/rc-tmp-bare" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext')"
sha_bare="$(git hash-object "$bare/AGENTS.md")"
check_line 'a version as wide as its column keeps one space' "- AGENTS.md    124.10.10 ${sha_bare:0:7}   not read" "$ctx_bare_long"
rm "$bare/VERSION" "$bare/AGENTS.md"
# The version: the manifest first (no jq, its playbookVersion line), then the stamp
# .playbook-version, then VERSION (until playbook 26.0.0, the first MAJOR after the move).
mkdir -p "$bare/.agents"
printf '3.0.0\n' > "$bare/.playbook-version"; printf '1.0.0\n' > "$bare/VERSION"
printf '{\n  "schemaVersion": 1,\n  "playbookVersion": "2.0.0",\n  "playbookCommit": "abc",\n  "stacks": [],\n  "files": {}\n}\n' \
  > "$bare/.agents/manifest.json"
rc_bare() { CLAUDE_PROJECT_DIR="$bare" TMPDIR="$fix/rc-tmp-bare" CLAUDE_CONFIG_DIR="$rc_config" bash "$readconfirm" | jq -r '.hookSpecificOutput.additionalContext'; }
check_line 'version: the manifest first'        'Playbook 2.0.0 | Core' "$(rc_bare)"
printf '{\r\n  "schemaVersion": 1,\r\n  "playbookVersion" :  "2.1.0" ,\r\n  "stacks": []\r\n}\r\n' > "$bare/.agents/manifest.json"
check_line 'version: the manifest with CRLF and loose spacing' 'Playbook 2.1.0 | Core' "$(rc_bare)"
printf '{\n  "schemaVersion": 1,\n  "files": {}\n}\n' > "$bare/.agents/manifest.json"
check_line 'version: a manifest without it falls back to the stamp' 'Playbook 3.0.0 | Core' "$(rc_bare)"
rm "$bare/.agents/manifest.json"
check_line 'version: no manifest, the stamp'    'Playbook 3.0.0 | Core' "$(rc_bare)"
rm "$bare/.playbook-version"
check_line 'version: neither, VERSION'          'Playbook 1.0.0 | Core' "$(rc_bare)"
rm -r "$bare/VERSION" "$bare/.agents"
if [ "$(rc_count_re '^\+ ' "$ctx_bare")" != 0 ]; then bad 'bare project: nothing marked read' 'a + line' 'none'
else ok 'bare project: nothing marked read' 'none'; fi
check_contains 'bare project: index missing'      'Rules — (index.json not found)' "$ctx_bare"
check_contains 'bare project: no skills'          'Skills 0 · Stop hook' "$ctx_bare"

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

# Memory group, positive case: a MEMORY.md index this environment CAN see.
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
check_line 'Memory counts real MEMORY.md entries when found' 'Memory: 3 entries' "$ctx_mem"

# Negative case (review round 1 of ww3d/playbook#233): only a FOREIGN project's memory
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
  'Memory: — (not available in this environment)' "$ctx_foreign"

echo "== read-confirm.sh: a newer playbook version, only where the network answers =="
# A local repository stands in for the playbook's: three version tags and a non-version tag.
remote="$fix/remote"; git init -q "$remote"
git -C "$remote" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x
for tag in v0.9.0 v1.0.0 v1.2.0 v1.10.0 nightly; do git -C "$remote" tag "$tag"; done
check_contains 'the newest tag is compared numerically (1.10.0 beats 1.2.0)' \
  'Newer playbook version: v1.10.0' "$(version_ctx "$remote")"
check_not_contains 'an equal version is silent'  'Newer playbook version' "$(version_ctx "$remote" 1.10.0)"
check_not_contains 'a newer local version is silent' 'Newer playbook version' "$(version_ctx "$remote" 2.0.0)"
check_not_contains 'an unreachable remote is silent' 'Newer playbook version' "$(version_ctx "$fix/no-such-remote")"
# A stand-in `timeout` logs the limit it is given and reports the limit as run out at once (exit 124),
# so the hang is a signal, not seconds that pass.
slow="$fix/slow-timeout"; mkdir -p "$slow"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> "$STUB_TO_LOG"\nexit 124\n' > "$slow/timeout"
chmod +x "$slow/timeout"
slow_log="$fix/slow-timeout.log"; : > "$slow_log"
slow_ctx="$(STUB_TO_LOG="$slow_log" PATH="$slow:$PATH" version_ctx "$remote" 1.0.0 startup "$fix/rc-tmp-slow")"
slow_limit="$(sed -n 1p "$slow_log")"
if [ "$slow_limit" = 1 ]; then ok 'the lookup is bounded to about a second' "$slow_limit s"
else bad 'the lookup is bounded to about a second' "${slow_limit:-none}" '1'; fi
check_not_contains 'a hanging lookup is silent' 'Newer playbook version' "$slow_ctx"
# Only a fresh start asks; a resume, clear or compaction does not, though the remote answers.
for src in resume clear compact; do
  check_not_contains "source $src: no lookup" 'Newer playbook version' "$(version_ctx "$remote" 1.0.0 "$src" "$fix/rc-tmp-$src")"
done
# The answer is kept for a day: the same start with the remote gone still shows the line,
# a cache older than a day is asked again, and a failed lookup is not kept.
vc_tmp="$fix/rc-tmp-cache"
check_contains 'the first start asks and keeps the answer' 'Newer playbook version: v1.10.0' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
mv "$remote" "$remote.gone"
check_contains 'a second start within a day reads the kept answer' \
  'Newer playbook version: v1.10.0' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
for cache_file in "$vc_tmp"/claude-rule-gate/newer-*; do sed -i '1s/.*/1/' "$cache_file"; done
check_not_contains 'a cache older than a day is asked again (remote gone: silent)' \
  'Newer playbook version' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
mv "$remote.gone" "$remote"
check_contains 'the failed lookup was not kept: the next start asks again' \
  'Newer playbook version: v1.10.0' "$(version_ctx "$remote" 1.0.0 startup "$vc_tmp")"
# The newer-version line stands directly above the closing line.
with_newer="$(version_ctx "$remote" 1.0.0 startup "$fix/rc-tmp-lines")"
above_close="$(printf '%s\n' "$with_newer" | tail -n 2 | head -n 1)"
if [ "$above_close" = 'Newer playbook version: v1.10.0' ]; then ok 'the newer-version line sits above the closing line' found
else bad 'the newer-version line sits above the closing line' "$above_close" 'Newer playbook version: v1.10.0'; fi
printf '1.0.0\n' > "$rc_root/VERSION"

echo "== read-confirm.sh: markers of ended sessions are swept on a fresh start =="
sweep_tmp="$fix/rc-tmp-sweep"; mkdir -p "$sweep_tmp/claude-rule-gate"
: > "$sweep_tmp/claude-rule-gate/old-session-read-main-code"; touch -d '10 days ago' "$sweep_tmp/claude-rule-gate/old-session-read-main-code"
: > "$sweep_tmp/claude-rule-gate/fresh-session-read-main-code"
version_ctx "$fix/no-such-remote" 1.0.0 resume "$sweep_tmp" >/dev/null
present_file 'a resume leaves a week-old marker alone' "$sweep_tmp/claude-rule-gate/old-session-read-main-code"
version_ctx "$fix/no-such-remote" 1.0.0 startup "$sweep_tmp" >/dev/null
absent_file 'a fresh start removes a marker older than a week' "$sweep_tmp/claude-rule-gate/old-session-read-main-code"
present_file 'a fresh start keeps a recent marker' "$sweep_tmp/claude-rule-gate/fresh-session-read-main-code"

echo "== read-confirm.sh: reports whether the Stop hook is wired (ww3d/playbook#171 (b)) =="
# Each case builds its own project, user and managed directory. The pairs: a
# registration at every level the hook can read is found (the false-alarm
# direction), and each way a registration is present but inert is reported.
# shellcheck disable=SC2016 # the settings file must hold ${CLAUDE_PROJECT_DIR} literally
stop_entry='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash","args":["${CLAUDE_PROJECT_DIR}/.claude/hooks/require-receipt.sh"]}]}]}}'
gate_case=0
bash_bin="$(command -v bash)"
gate_setup() { # sets g_root, g_cfg, g_mgd: empty project with the hook file, empty user and managed dirs
  gate_case=$((gate_case + 1))
  g_root="$fix/gate-$gate_case/root"; g_cfg="$fix/gate-$gate_case/cfg"; g_mgd="$fix/gate-$gate_case/mgd"
  mkdir -p "$g_root/.claude/hooks" "$g_cfg" "$g_mgd"
  printf '#!/usr/bin/env bash\n' > "$g_root/.claude/hooks/require-receipt.sh"
}
gate_line() { # [PATH override] - the receipt's Stop-Hook line for the current case
  CLAUDE_PROJECT_DIR="$g_root" TMPDIR="$fix/gate-$gate_case" CLAUDE_CONFIG_DIR="$g_cfg" \
    READ_CONFIRM_MANAGED_DIR="$g_mgd" PATH="${1:-$PATH}" "$bash_bin" "$readconfirm" \
    | jq -r '.hookSpecificOutput.additionalContext' | { while IFS= read -r l; do [[ $l == 'Rules '* ]] && printf '%s\n' "$l"; done; }
}
chk_gate() { # label, expected substring; "Stop hook on" must end the line
  local got; got="$(gate_line)"
  if [ "$2" = 'Stop hook on' ]; then
    case "$got" in *' · Stop hook on') ok "$1" "found" ;; *) bad "$1" "$got" "... · Stop hook on" ;; esac
  elif has_text "$2" "$got"; then ok "$1" "found"
  else bad "$1" "$got" "$2"; fi
}

gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
chk_gate 'registered in the project settings'  'Stop hook on'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.local.json"
chk_gate 'registered in the local settings'    'Stop hook on'
gate_setup; printf '%s' "$stop_entry" > "$g_cfg/settings.json"
chk_gate 'registered in the user settings only' 'Stop hook on'
gate_setup; mkdir -p "$g_mgd/managed-settings.d"; printf '%s' "$stop_entry" > "$g_mgd/managed-settings.d/10-gate.json"
chk_gate 'registered in a managed drop-in'     'Stop hook on'
gate_setup
# shellcheck disable=SC2016 # the settings file must hold $CLAUDE_PROJECT_DIR literally
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"bash \\"$CLAUDE_PROJECT_DIR/.claude/hooks/require-receipt.sh\\""}]}]}}' \
  > "$g_root/.claude/settings.json"
chk_gate 'registered in the shell form'        'Stop hook on'

gate_setup
chk_gate 'no settings file anywhere'           'Stop hook off (registered in no readable settings file (read: none)'
chk_gate 'not found names what it cannot see'  '/hooks shows them all'
gate_setup
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash","args":["x/require-receipt.sh"]}]}]}}' \
  > "$g_root/.claude/settings.json"
chk_gate 'registered under SessionStart, not Stop' '(read: Project)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; rm "$g_root/.claude/hooks/require-receipt.sh"
chk_gate 'registered, hook file missing'       'registered (Project); .claude/hooks/require-receipt.sh missing or unreadable'
gate_setup; printf '{"hooks": {' > "$g_root/.claude/settings.json"; printf '%s' "$stop_entry" > "$g_cfg/settings.json"
chk_gate 'broken project JSON beside a user registration' 'registered (User); invalid JSON: Project'

gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"disableAllHooks": true}' > "$g_root/.claude/settings.local.json"
chk_gate 'disableAllHooks in the local settings' 'turned off by disableAllHooks (Local)'
gate_setup; printf '{"disableAllHooks": false, "hooks": %s}' "$(x="${stop_entry#'{"hooks":'}"; printf '%s' "${x%\}}")" \
  > "$g_root/.claude/settings.json"
printf '{"disableAllHooks": true}' > "$g_cfg/settings.json"
chk_gate 'a project false outranks a user true' 'Stop hook on'
gate_setup; printf '%s' "$stop_entry" > "$g_mgd/managed-settings.json"
printf '{"disableAllHooks": true}' > "$g_root/.claude/settings.json"
chk_gate 'a project disableAllHooks leaves a managed hook running' 'Stop hook on'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.json"
chk_gate 'allowManagedHooksOnly blocks a project registration' 'blocked by allowManagedHooksOnly (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_root/.claude/settings.local.json"
chk_gate 'allowManagedHooksOnly outside Managed has no effect' 'Stop hook on'

# Managed files merge base first, then the drop-ins in name order; the later
# file wins a single value. Each pair contradicts itself in both directions.
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"disableAllHooks": true}' > "$g_mgd/managed-settings.d/10-a.json"
printf '{"disableAllHooks": false}' > "$g_mgd/managed-settings.d/20-b.json"
chk_gate 'a later drop-in false outranks an earlier true' 'Stop hook on'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"disableAllHooks": false}' > "$g_mgd/managed-settings.d/10-a.json"
printf '{"disableAllHooks": true}' > "$g_mgd/managed-settings.d/20-b.json"
chk_gate 'a later drop-in true outranks an earlier false' 'turned off by disableAllHooks (Managed)'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.json"
printf '{"allowManagedHooksOnly": false}' > "$g_mgd/managed-settings.d/10-a.json"
chk_gate 'a drop-in outranks the managed base file' 'Stop hook on'
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"; mkdir -p "$g_mgd/managed-settings.d"
printf '{"allowManagedHooksOnly": false}' > "$g_mgd/managed-settings.json"
printf '{"allowManagedHooksOnly": true}' > "$g_mgd/managed-settings.d/10-a.json"
chk_gate 'a drop-in true outranks a base false' 'blocked by allowManagedHooksOnly (Managed)'

# Without jq the Stop hook itself cannot judge; the line says so rather than
# guessing. PATH then holds only what read-confirm.sh needs besides bash.
gate_setup; printf '%s' "$stop_entry" > "$g_root/.claude/settings.json"
nojq="$fix/gate-nojq"; mkdir -p "$nojq"
for helper in git grep mv rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$(command -v bash)" "$(command -v "$helper")" > "$nojq/$helper"
  chmod +x "$nojq/$helper"
done
got="$(gate_line "$nojq")"
if has_text 'jq missing' "$got"; then ok 'without jq' 'found'; else bad 'without jq' "$got" 'jq missing'; fi
# A failing jq must leave a valid receipt, never an aborted hook.
printf '#!/usr/bin/env bash\nexit 2\n' > "$stub/jq"; chmod +x "$stub/jq"
got="$(gate_line "$stub:$PATH")"
if has_text 'settings not readable (jq error)' "$got"; then ok 'jq failing on the settings' 'found'
else bad 'jq failing on the settings' "$got" 'settings not readable (jq error)'; fi
rm -f "$stub/jq"

echo "== read-confirm.sh: process starts do not grow with the number of files (ww3d/playbook#275) =="
# Under Git Bash each process start costs tens of milliseconds; a start per
# listed file took 67-96 s on a real repository. Shadow every external command
# the hook has ever used with a logger, and hold the total to a small constant
# across a project of 40 docs, cold and warm.
many="$fix/rc-many"
mkdir -p "$many/docs" "$many/.agents/tech" "$fix/rc-tmp-many"
git init -q "$many"
printf '# P\n' > "$many/CLAUDE.md"; printf '# A\n' > "$many/AGENTS.md"
for i in $(seq 1 40); do printf '# Doc %s\n\nbuild %s\n' "$i" "$i" > "$many/docs/d$i.md"; done
printf '1.0.0\n' > "$many/VERSION"
calls="$fix/rc-calls.log"
for helper in git grep awk sed head tr mktemp mv cat basename; do
  real="$(command -v "$helper")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >> "%s"\nexec "%s" "$@"\n' "$helper" "$calls" "$real" > "$stub/$helper"
  chmod +x "$stub/$helper"
done
for run in cold warm; do
  : > "$calls"
  CLAUDE_PROJECT_DIR="$many" TMPDIR="$fix/rc-tmp-many" CLAUDE_CONFIG_DIR="$rc_config" PATH="$stub:$PATH" bash "$readconfirm" >/dev/null
  n_calls="$(rc_count_re . "$(<"$calls")")"
  if [ "${n_calls:-0}" -le 3 ]; then ok "40 docs, $run: at most 3 process starts" "$n_calls"
  else bad "40 docs, $run: at most 3 process starts" "$n_calls ($(tr '\n' ' ' < "$calls"))" "<= 3"; fi
done
for helper in git grep awk sed head tr mktemp mv cat basename; do rm -f "$stub/$helper"; done

finish
