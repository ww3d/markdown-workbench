#!/usr/bin/env bash
#
# SessionStart read-confirmation hook — generic, byte-identical across consumers.
#
# Runs as a SECOND SessionStart hook next to the repo-specific session-start.sh
# (which is consumer-owned and stays untouched — it installs e.g. a per-repo SDK
# version). It injects the session receipt into the initial context via
# hookSpecificOutput.additionalContext. SessionStart stdout has gone silently into
# context since CC 2.1.0, so the receipt is *present* in context, not merely
# readable. On resume the hook runs again (source:"resume") — that is fine.
#
# The receipt is at most six lines, in this form:
#
#   <instruction: give this once per session start or compaction, never unprompted again>
#   Playbook 23.0.0 | Kern AGENTS.md 1a2b3c4 · CLAUDE.md 5d6e7f8 · Audit ist-stand-….md 9a8b7c6
#   Regeln 7: audit carrier code docs evidence pr review
#   Skills 7 · Stop-Hook require-receipt.sh registriert (Projekt)
#   Gedaechtnis: — (nicht verfuegbar in dieser Umgebung)
#   Neuere Playbook-Version: v23.1.0          <- only on a fresh start, where the network answers
#
# The Stop hook require-receipt.sh recognises the first and the Gedaechtnis line
# in one assistant message as the receipt. What an environment cannot see is
# reported as "— (nicht verfuegbar in dieser Umgebung)", never silently dropped.
#
# Cost. Under Git Bash every process start costs tens of milliseconds, so a
# per-file git/awk/grep chain outgrows the 30 s timeout on a repository with
# many docs (issue ww3d/playbook#275). Hence: one `git
# hash-object` for the core files, one `jq` for the settings files, bash builtins
# for everything else, and one bounded `git ls-remote` for the version check.
#
# Idempotent, set -euo pipefail, never aborts on a missing file.
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# --- a compaction ends every point-of-use read --------------------------------
# AGENTS.md, section "Session Start: Read Before Anything Else": after a
# compaction every rule read counts as unread. require-rule-read.sh and
# record-rule-read.sh remember a read per session in marker files; on source
# "compact" this hook deletes the session's markers, so the next trigger asks for
# the file again. The event JSON is read with builtins only, and never from a
# terminal: /read-check runs this hook by hand, with nothing on stdin.
hook_input=""
if [ ! -t 0 ]; then IFS= read -r -t 2 -d '' hook_input || true; fi
session_re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
source_re='"source"[[:space:]]*:[[:space:]]*"([a-z]+)"'
src=""
if [[ $hook_input =~ $source_re ]]; then src="${BASH_REMATCH[1]}"; fi
gate_dir="${TMPDIR:-/tmp}/claude-rule-gate"
if [ "$src" = compact ] && [[ $hook_input =~ $session_re ]]; then
  rm -f "${gate_dir}/${BASH_REMATCH[1]}-"* 2>/dev/null || true
fi
# Markers of ended sessions are never read again; a fresh start sweeps the ones a week old.
# A session resumed after more than a week reads its rules again.
if [ "$src" = startup ] && [ -d "$gate_dir" ]; then
  find "$gate_dir" -type f -mtime +7 -delete 2>/dev/null || true
fi

lines=()
emit() { lines+=("$1"); }

# Reads a whole file into the named variable with the read builtin (no process);
# empty when the file is missing or unreadable. CR stripped, for CRLF files.
slurp() { # var, file
  local _text=""
  if [ -r "$2" ]; then IFS= read -r -d '' _text < "$2" || true; fi
  printf -v "$1" '%s' "${_text//$'\r'/}"
}

# The Claude Code projects/ directory name for a given path (looks up the memory
# dir below): every ':', '\', '/', '.' becomes '-'. Sets `slug`.
slugify() {
  slug="${1//:/-}"; slug="${slug//\\/-}"; slug="${slug//\//-}"; slug="${slug//./-}"
}
slugify "$ROOT"

# Playbook version: the synced .playbook-version in a consumer; fall back to
# /VERSION so the hook also reports correctly when run inside the playbook itself.
VER=""
for f in ".playbook-version" "VERSION"; do
  if [ -f "${ROOT}/${f}" ]; then
    IFS= read -r VER < "${ROOT}/${f}" || true
    VER="${VER//[[:space:]]/}"
    break
  fi
done

# --- core files: blob SHAs in one git start ------------------------------------
# AGENTS.md, CLAUDE.md and the newest state audit (audit/ist-stand-*.md, the
# stamp in the name sorts by time). A SHA missing or git failing reads "—".
audit=""
shopt -s nullglob
for f in "${ROOT}"/audit/ist-stand-*.md; do audit="${f##*/}"; done
shopt -u nullglob

core=(); [ -f "${ROOT}/AGENTS.md" ] && core+=("AGENTS.md"); [ -f "${ROOT}/CLAUDE.md" ] && core+=("CLAUDE.md")
[ -z "$audit" ] || core+=("audit/${audit}")
sha_of=()
if [ "${#core[@]}" -gt 0 ]; then
  printf -v path_list '%s\n' "${core[@]}"
  sha_text="$(git -C "$ROOT" hash-object --stdin-paths 2>/dev/null <<< "${path_list%$'\n'}" || true)"
  while IFS= read -r sha; do
    sha="${sha%$'\r'}"
    [ -z "$sha" ] || sha_of+=("${sha:0:7}")
  done <<< "$sha_text"
  [ "${#sha_of[@]}" -eq "${#core[@]}" ] || sha_of=()
fi
sha7() { # path -> global s: the short SHA of a core file, "—" when it has none
  local i
  s="—"
  for i in "${!core[@]}"; do
    if [ "${core[$i]}" = "$1" ] && [ "${#sha_of[@]}" -gt "$i" ]; then s="${sha_of[$i]}"; fi
  done
}
sha7 AGENTS.md; sha_agents="$s"
sha7 CLAUDE.md; sha_claude="$s"
if [ -n "$audit" ]; then sha7 "audit/${audit}"; audit_part="${audit} ${s}"; else audit_part="— (keiner)"; fi
[ -f "${ROOT}/AGENTS.md" ] || sha_agents="— nicht gefunden"
[ -f "${ROOT}/CLAUDE.md" ] || sha_claude="— nicht gefunden"

# --- the generated rule index: count and triggers --------------------------------
# Read from .agents/rules/index.json (the generated artifact), with bash builtins,
# not jq: this hook must run where jq is absent. The generator writes one key per
# line, which is what makes the trigger match safe.
rules_part="— (index.json nicht gefunden)"
if [ -f "${ROOT}/.agents/rules/index.json" ]; then
  index_text=""; slurp index_text "${ROOT}/.agents/rules/index.json"
  trigger_re='"trigger"[[:space:]]*:[[:space:]]*"([^"]*)"'
  triggers=""; n_rules=0
  while IFS= read -r l; do
    if [[ $l =~ $trigger_re ]]; then triggers+=" ${BASH_REMATCH[1]}"; n_rules=$((n_rules + 1)); fi
  done <<< "$index_text"
  rules_part="${n_rules}:${triggers}"
  [ "$n_rules" -gt 0 ] || rules_part="— (index.json nicht lesbar)"
fi

# --- skills: one per .claude/skills/<name>/SKILL.md ------------------------------
n_skills=0
shopt -s nullglob
for f in "${ROOT}"/.claude/skills/*/SKILL.md; do n_skills=$((n_skills + 1)); done
shopt -u nullglob

# --- is the receipt gate wired? (ww3d/playbook#171 (b)) ----------------------
# No hook sees Claude Code's effective hook configuration: neither the event
# JSON nor the environment carries it. So this reads the settings files a
# script can reach (managed file and drop-ins, local, project, user), highest
# precedence first, and judges them in one jq start. Plugins, --settings,
# MDM/server policy and skill frontmatter stay invisible; the line names what it
# read instead of calling the gate missing.
case "${OSTYPE:-}" in
  darwin*) managed_dir="/Library/Application Support/ClaudeCode" ;;
  msys*|cygwin*) managed_dir="C:/Program Files/ClaudeCode" ;;
  *) managed_dir="/etc/claude-code" ;;
esac
# Only the tests set this, to keep the machine's own policy out of their cases.
managed_dir="${READ_CONFIRM_MANAGED_DIR:-$managed_dir}"

set_labels=(); set_texts=(); read_from=""
shopt -s nullglob
# Claude Code merges managed-settings.json first, then the drop-ins in name
# order, the later file winning: so the drop-ins go in reversed, the base file last.
drop_ins=("${managed_dir}"/managed-settings.d/*.json)
managed_files=()
for (( i = ${#drop_ins[@]} - 1; i >= 0; i-- )); do managed_files+=("${drop_ins[$i]}"); done
for f in ${managed_files[@]+"${managed_files[@]}"} "${managed_dir}/managed-settings.json" \
         "${ROOT}/.claude/settings.local.json" "${ROOT}/.claude/settings.json" \
         "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
  [ -f "$f" ] || continue
  case "$f" in
    "$managed_dir"/*) l="Managed" ;;
    "$ROOT"/.claude/settings.local.json) l="Lokal" ;;
    "$ROOT"/.claude/settings.json) l="Projekt" ;;
    *) l="Nutzer" ;;
  esac
  text=""; slurp text "$f"
  set_labels+=("$l"); set_texts+=("$text")
  case ", ${read_from}, " in *", ${l}, "*) ;; *) read_from="${read_from:+${read_from}, }${l}" ;; esac
done
shopt -u nullglob

# One line per file: "invalid", or "ok <registered> <disableAllHooks> <allowManagedHooksOnly>".
# The texts go in as arguments, not paths: a native jq under Git Bash would see
# converted paths, and MSYS2_ARG_CONV_EXCL keeps it from touching the JSON.
# shellcheck disable=SC2016 # a jq program: its $ names are jq variables, not shell ones
gate_jq='$ARGS.positional[] | (fromjson? // null) as $s
  | if ($s | type) != "object" then "invalid"
    else ["ok",
          ([$s.hooks?.Stop?[]?.hooks?[]? | objects | [.command?, .args?[]?] | map(strings) | join(" ")
            | select(test("require-receipt\\.sh"))] | length > 0 | tostring),
          ($s.disableAllHooks | tostring), ($s.allowManagedHooksOnly | tostring)] | join(" ")
    end'
gate_state="ok"; verdicts=()
if ! command -v jq >/dev/null 2>&1; then
  gate_state="nojq"
elif [ "${#set_texts[@]}" -gt 0 ]; then
  if v_text="$(MSYS2_ARG_CONV_EXCL='*' jq -rn "$gate_jq" --args "${set_texts[@]}" 2>/dev/null)"; then
    # CR stripped outside the array assignment: bash 5.3 leaves $'\r' unexpanded inside ( ).
    while IFS= read -r v; do v="${v%$'\r'}"; verdicts+=("$v"); done <<< "$v_text"
  fi
  [ "${#verdicts[@]}" -eq "${#set_texts[@]}" ] || gate_state="jqerr"
fi

found=""; invalid=""; in_managed=false; in_other=false
disable=""; disable_from=""; managed_only=false; managed_only_set=false
if [ "$gate_state" = "ok" ]; then
  for i in "${!verdicts[@]}"; do
    l="${set_labels[$i]}"
    read -r st reg dis mgd <<< "${verdicts[$i]}"
    if [ "$st" != "ok" ]; then invalid="${invalid:+${invalid}, }${l}"; continue; fi
    if [ "$reg" = "true" ]; then
      case ", ${found}, " in *", ${l}, "*) ;; *) found="${found:+${found}, }${l}" ;; esac
      if [ "$l" = "Managed" ]; then in_managed=true; else in_other=true; fi
    fi
    # The highest file that sets a key decides it (settings precedence);
    # allowManagedHooksOnly counts only from a managed file.
    if [ -z "$disable_from" ] && [ "$dis" != "null" ]; then disable="$dis"; disable_from="$l"; fi
    if [ "$l" = "Managed" ] && [ "$managed_only_set" = false ] && [ "$mgd" != "null" ]; then
      managed_only_set=true
      if [ "$mgd" = "true" ]; then managed_only=true; fi
    fi
  done
fi

gate_parts=()
case "$gate_state" in
  nojq)  gate_parts+=("jq fehlt: Registrierung nicht pruefbar, und ohne jq laesst der Hook jeden Turn enden") ;;
  jqerr) gate_parts+=("Einstellungen nicht auswertbar (jq-Fehler), gelesen: ${read_from}") ;;
  *)
    if [ -z "$found" ]; then
      gate_parts+=("in keiner lesbaren Einstellungsdatei registriert (gelesen: ${read_from:-keine})")
      gate_parts+=("Plugin, --settings und MDM/Server sieht der Hook nicht, /hooks zeigt alle")
    fi
    # Only a managed disableAllHooks reaches a managed registration.
    if [ "$disable" = "true" ] && { [ "$in_managed" = false ] || [ "$disable_from" = "Managed" ]; }; then
      gate_parts+=("abgeschaltet durch disableAllHooks (${disable_from})")
    fi
    if [ "$managed_only" = true ] && [ "$in_other" = true ] && [ "$in_managed" = false ]; then
      gate_parts+=("gesperrt durch allowManagedHooksOnly (Managed)")
    fi
    [ -z "$invalid" ] || gate_parts+=("ungueltiges JSON: ${invalid}") ;;
esac
[ -r "${ROOT}/.claude/hooks/require-receipt.sh" ] || gate_parts+=(".claude/hooks/require-receipt.sh fehlt oder ist unlesbar")

if [ "${#gate_parts[@]}" -eq 0 ]; then
  stop_part="registriert (${found})"
else
  printf -v gate_text '%s; ' "${gate_parts[@]}"
  [ -z "$found" ] || gate_text="registriert (${found}); ${gate_text}"
  stop_part="— ${gate_text%; }"
fi

# --- memory: the index this environment can see ------------------------------------
# ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/memory/MEMORY.md; when it does not
# resolve, the honest "not available" marker rather than a DIFFERENT project's memory
# (ww3d/playbook#164 point 2).
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mem_md="${config_dir}/projects/${slug}/memory/MEMORY.md"
if [ -f "$mem_md" ]; then
  mem_text=""; slurp mem_text "$mem_md"
  mem_count=0
  while IFS= read -r l; do
    case "$l" in "- ["*) mem_count=$((mem_count + 1)) ;; esac
  done <<< "$mem_text"
  memory_part="${mem_count} Eintraege (MEMORY.md)"
else
  memory_part="— (nicht verfuegbar in dieser Umgebung)"
fi

# --- a newer playbook version ---------------------------------------------------
# The newest v<major>.<minor>.<patch> tag of the playbook repository, one bounded
# `git ls-remote` (1 s) on a fresh start only - not on a resume, clear or compaction, which
# ask nothing - and the answer kept for a day under the gate folder. Silent on every
# failure: offline, timeout, no git, no version of our own, no tag, equal or older; a failed
# lookup is not kept. READ_CONFIRM_REMOTE points the lookup at another repository (the tests
# use a local one).
newer=""
ver_re='^([0-9]+)\.([0-9]+)\.([0-9]+)$'
if [ "$src" = startup ] && [[ $VER =~ $ver_re ]]; then
  cur=$(( BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3] ))
  remote="${READ_CONFIRM_REMOTE:-https://github.com/ww3d/playbook}"
  cache="${gate_dir}/newer-${remote//[^A-Za-z0-9]/_}"
  now="${EPOCHSECONDS:-0}"
  cached=""; slurp cached "$cache"
  stamp="${cached%%$'\n'*}"
  if [[ $stamp =~ ^[0-9]+$ ]] && [ "$now" -ge "$stamp" ] && [ $(( now - stamp )) -lt 86400 ]; then
    tags="${cached#*$'\n'}"
  else
    tags="$(GIT_TERMINAL_PROMPT=0 timeout 1 git ls-remote --tags --refs "$remote" 'v*' 2>/dev/null || true)"
    if [ -n "$tags" ] && [ "$now" -gt 0 ]; then
      mkdir -p "$gate_dir" 2>/dev/null || true
      printf '%s\n%s\n' "$now" "$tags" > "$cache" 2>/dev/null || true
    fi
  fi
  best=$cur
  tag_re='refs/tags/v([0-9]+)\.([0-9]+)\.([0-9]+)$'
  while IFS= read -r l; do
    l="${l%$'\r'}"
    if [[ $l =~ $tag_re ]]; then
      n=$(( BASH_REMATCH[1] * 1000000 + BASH_REMATCH[2] * 1000 + BASH_REMATCH[3] ))
      if [ "$n" -gt "$best" ]; then best=$n; newer="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"; fi
    fi
  done <<< "$tags"
fi

emit "Session-Quittung, einmal je Sessionstart bzw. Kompaktierung ausgeben, ungefragt nie je Zug wiederholen:"
emit "Playbook ${VER:-unbekannt} | Kern AGENTS.md ${sha_agents} · CLAUDE.md ${sha_claude} · Audit ${audit_part}"
emit "Regeln ${rules_part}"
emit "Skills ${n_skills} · Stop-Hook require-receipt.sh ${stop_part}"
emit "Gedaechtnis: ${memory_part}"
[ -z "$newer" ] || emit "Neuere Playbook-Version: ${newer}"

# Assemble the receipt and inject it as SessionStart additionalContext. JSON is
# built by hand (no jq dependency): the content is fixed German prose, so only
# backslash, double-quote and newline need escaping.
printf -v text '%s\n' "${lines[@]}"
text="${text%$'\n'}"
text="${text//\\/\\\\}"
text="${text//\"/\\\"}"
text="${text//$'\n'/\\n}"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$text"
