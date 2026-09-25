#!/usr/bin/env bash
#
# SessionStart read-confirmation hook — generic, byte-identical across consumers.
#
# Runs as a SECOND SessionStart hook next to the repo-specific session-start.sh
# (which is consumer-owned and stays untouched — it installs e.g. a per-repo SDK
# version). This hook determines which conventions, skills, profile and memory
# state are visible from the current environment and injects a four-group
# receipt into the initial context via hookSpecificOutput.additionalContext.
# SessionStart stdout has gone silently into context since CC 2.1.0, so the
# receipt is *present* in context, not merely readable; it stays well under the
# 10k-character limit. On resume the hook runs again (source:"resume") — that
# is fine.
#
# Honest about environment limits (decision V4): what an environment cannot see
# is reported as "— (nicht verfuegbar in dieser Umgebung)", never silently
# dropped. Detail depth is hybrid (decision V3): versioned convention/baseline
# docs are listed individually with their version, bulk directories are
# aggregated with a count and the newest entry.
#
# Cost. Under Git Bash every process start costs tens of milliseconds, and a
# per-file git/awk/grep/mktemp/mv chain measured 67-96 s on a repository with
# ~140 docs (issue ww3d/playbook#275) — past the 30 s timeout, so the receipt never arrived
# and every session start waited the full 30 s. Hence: one `git hash-object`
# for every listed file, one `grep` for every build marker, one `mv` for the
# cache, and bash builtins for everything else (reading files, the rule index,
# skill frontmatter, the memory count, paths, slugs). The count no longer grows
# with the number of files.
#
# Idempotent, set -euo pipefail, never aborts on a missing file (then the entry
# reads "— nicht gefunden").
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# --- a compaction ends every point-of-use receipt ----------------------------
# AGENTS.md, section "Session Start: Read Before Anything Else": after a
# compaction every rule receipt counts as unread. require-rule-read.sh
# remembers a found receipt per session in a marker file; on source "compact"
# this hook deletes the session's markers (found receipts and stage-2 alike), so
# the next trigger reads the transcript again - where only what follows the
# compaction counts. The event JSON is read with builtins only, and never from a
# terminal: /read-check runs this hook by hand, with nothing on stdin.
hook_input=""
if [ ! -t 0 ]; then IFS= read -r -t 2 -d '' hook_input || true; fi
session_re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
compact_re='"source"[[:space:]]*:[[:space:]]*"compact"'
if [[ $hook_input =~ $compact_re ]] && [[ $hook_input =~ $session_re ]]; then
  rm -f "${TMPDIR:-/tmp}/claude-rule-gate/${BASH_REMATCH[1]}-"* 2>/dev/null || true
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

# --- blob-SHA cache (E17) ----------------------------------------------------
# Files listed individually (tech overlays, docs/*.md, CLAUDE.md, AGENTS.md)
# are cheap to re-hash but expensive to re-read in full every session. Cache
# their blob SHA across runs, keyed by project (the same path-to-slug shape
# projects/<slug>/ under ~/.claude uses, reproduced here only well enough to
# give this cache file its own name per project — no cross-project collision,
# nothing more is asked of it). Unchanged files then get a short line instead
# of the full one; aggregated groups (docs/common/, docs/decisions/) are
# counts, not per-file lines, and stay outside the cache on purpose.
# The Claude Code projects/ directory name for a given path, reproduced just
# well enough to key a cache file (below) and look up a memory/ dir (Gruppe 4)
# by it: every ':', '\', '/', '.' becomes '-'. Sets `slug`.
slugify() {
  slug="${1//:/-}"; slug="${slug//\\/-}"; slug="${slug//\//-}"; slug="${slug//./-}"
}

slugify "$ROOT"
CACHE_FILE="${TMPDIR:-/tmp}/read-confirm-cache-${slug}.tsv"

# Playbook version: the synced .playbook-version in a consumer; fall back to
# /VERSION so the hook also reports correctly when run inside the playbook itself.
# Sets the globals VER (the value) and VER_SRC (the source file it was read from).
VER=""
VER_SRC=""
read_playbook_version() {
  local f
  for f in ".playbook-version" "VERSION"; do
    if [ -f "${ROOT}/${f}" ]; then
      IFS= read -r VER < "${ROOT}/${f}" || true
      VER="${VER//[[:space:]]/}"
      VER_SRC="$f"
      return 0
    fi
  done
  return 1
}

read_playbook_version || true
VER_LABEL="${VER:-unbekannt}"

# --- the individually listed files, collected before anything is emitted -----
# Paths relative to ROOT, each with the line it gets when it has changed (or no
# cache entry). docs/*.md carry a "build NN" marker where their header has one;
# the marker is filled in below, once all files are known.
shopt -s nullglob
tracked=()
full=()
track() { tracked+=("$1"); full+=("$2"); }

[ -f "${ROOT}/CLAUDE.md" ] && track "CLAUDE.md" "- CLAUDE.md @ projekt OK"
[ -f "${ROOT}/AGENTS.md" ] && track "AGENTS.md" "- AGENTS.md @ playbook ${VER_LABEL}"

# Tech overlays (playbook-versioned): tech/common/*.md plus tech/*.md wrappers.
for f in "${ROOT}"/tech/common/*.md "${ROOT}"/tech/*.md; do
  [ "${f##*/}" = "README.md" ] && continue
  rel="${f#"${ROOT}"/}"
  track "$rel" "- ${rel} @ playbook ${VER_LABEL}"
done

# Top-level docs/*.md — consumer-owned wrappers and baseline docs. Versioned
# baseline docs carry a "build NN" header; show it where present (hybrid detail).
docs=()
for f in "${ROOT}"/docs/*.md; do
  [ "${f##*/}" = "README.md" ] && continue
  docs+=("${f#"${ROOT}"/}")
done
shopt -u nullglob

# First "build NN" marker per doc, one grep over all of them: -m1 stops at the
# first matching line of each file, and the first match of that line wins
# (-o prints them in order). Relative names, so the "path:" prefix of -H holds
# no drive-letter colon to trip over.
builds=$'\n'
if [ "${#docs[@]}" -gt 0 ]; then
  while IFS= read -r hit; do
    hit="${hit%$'\r'}"
    doc="${hit%%:*}"
    case "$builds" in *$'\n'"${doc}"$'\t'*) continue ;; esac
    number="${hit#*:}"
    builds+="${doc}"$'\t'"${number//[!0-9]/}"$'\n'
  done <<< "$(cd "$ROOT" || exit 0; grep -oiEH -m1 'build[[:space:]]+[0-9]+' -- "${docs[@]}" 2>/dev/null || true)"
fi
for rel in ${docs[@]+"${docs[@]}"}; do
  b=""
  case "$builds" in
    *$'\n'"${rel}"$'\t'*)
      b="${builds#*$'\n'"${rel}"$'\t'}"
      b="${b%%$'\n'*}" ;;
  esac
  if [ -n "$b" ]; then track "$rel" "- ${rel} build ${b}"; else track "$rel" "- ${rel} OK"; fi
done

# Blob SHAs of every tracked file in one git start, one SHA per line in input
# order. Should git fail or answer short, no file has a SHA and every file gets
# its full line - the pre-cache behaviour, never a wrong "unveraendert".
shas=()
if [ "${#tracked[@]}" -gt 0 ]; then
  printf -v path_list '%s\n' "${tracked[@]}"
  sha_text="$(git -C "$ROOT" hash-object --stdin-paths 2>/dev/null <<< "${path_list%$'\n'}" || true)"
  while IFS= read -r sha; do
    [ -n "$sha" ] && shas+=("${sha%$'\r'}")
  done <<< "$sha_text"
  [ "${#shas[@]}" -eq "${#tracked[@]}" ] || shas=()
fi

# The cache as one newline-framed "path<TAB>sha" text; a lookup is a pattern
# match on it, not a process.
cache_old=""; slurp cache_old "$CACHE_FILE"
cache_old=$'\n'"${cache_old}"
[ "${cache_old: -1}" = $'\n' ] || cache_old+=$'\n'

cache_new=$'\n'
tracked_lines=()
for i in "${!tracked[@]}"; do
  rel="${tracked[$i]}"
  line="${full[$i]}"
  if [ "${#shas[@]}" -gt 0 ]; then
    sha="${shas[$i]}"
    cache_new+="${rel}"$'\t'"${sha}"$'\n'
    case "$cache_old" in
      *$'\n'"${rel}"$'\t'"${sha}"$'\n'*) line="- ${rel}: unveraendert seit ${sha:0:7}" ;;
    esac
  fi
  tracked_lines+=("$line")
done

# Write the cache back once: the entries hashed now, plus the old entries for
# paths not listed this time (a file that comes back finds its SHA again).
# Atomic via rename; a failure only costs the next run its short lines.
if [ "${#shas[@]}" -gt 0 ]; then
  while IFS=$'\t' read -r p h; do
    [ -n "$p" ] || continue
    case "$cache_new" in *$'\n'"${p}"$'\t'*) continue ;; esac
    cache_new+="${p}"$'\t'"${h}"$'\n'
  done <<< "$cache_old"
  if printf '%s' "${cache_new#$'\n'}" 2>/dev/null > "${CACHE_FILE}.$$"; then
    mv -f "${CACHE_FILE}.$$" "$CACHE_FILE" 2>/dev/null || rm -f "${CACHE_FILE}.$$" 2>/dev/null || true
  fi
fi

emit "# Session-Read-Confirmation (Playbook ${VER_LABEL})"
emit ""

# --- Gruppe 1: Konventionen -------------------------------------------------
emit "## Konventionen"
if [ -n "$VER" ]; then
  emit "- Playbook-Version: ${VER} (${VER_SRC})"
else
  emit "- Playbook-Version: — nicht gefunden"
fi

# The tracked lines in collection order - CLAUDE.md, AGENTS.md, overlays, then
# docs - with a missing CLAUDE.md / AGENTS.md reported at its own place and the
# docs/common line between overlays and docs, as before.
i=0
for f in CLAUDE.md AGENTS.md; do
  if [ "${tracked[$i]:-}" = "$f" ]; then emit "${tracked_lines[$i]}"; i=$((i + 1))
  else emit "- ${f}: — nicht gefunden"; fi
done
n_head=$(( ${#tracked[@]} - ${#docs[@]} ))
for (( ; i < n_head; i++ )); do emit "${tracked_lines[$i]}"; done

# docs/common/ — playbook-synced bulk, aggregated.
shopt -s nullglob
if [ -d "${ROOT}/docs/common" ]; then
  common=("${ROOT}"/docs/common/*.md)
  emit "- docs/common/ — ${#common[@]} Dateien OK"
fi
shopt -u nullglob

for (( i = n_head; i < ${#tracked[@]}; i++ )); do emit "${tracked_lines[$i]}"; done

# The generated rule index. One line per point of use, read from
# .agents/rules/index.json rather than from the rule files themselves: the JSON
# IS the generated artifact, and reading the files instead would put a second,
# ungated derivation of the same table into the receipt. Parsed with bash
# builtins, not jq — this hook must run where jq is absent. The generator
# writes one key per line in a fixed order (trigger, then path), which is what
# makes the pairing safe.
if [ -f "${ROOT}/.agents/rules/index.json" ]; then
  index_text=""; slurp index_text "${ROOT}/.agents/rules/index.json"
  rule_lines=()
  trigger_re='"trigger"[[:space:]]*:[[:space:]]*"([^"]*)"'
  path_re='"path"[[:space:]]*:[[:space:]]*"([^"]*)"'
  t=""
  while IFS= read -r l; do
    if [[ $l =~ $trigger_re ]]; then
      t="${BASH_REMATCH[1]}"
    elif [[ $l =~ $path_re ]] && [ -n "$t" ]; then
      rule_lines+=("- ${t} -> ${BASH_REMATCH[1]}")
      t=""
    fi
  done <<< "$index_text"
  if [ "${#rule_lines[@]}" -gt 0 ]; then
    emit "- .agents/rules/ — Einsatzpunkt-Regeln (vor der ersten Aktion je Trigger lesen):"
    for l in "${rule_lines[@]}"; do emit "  ${l}"; done
  else
    emit "- .agents/rules/index.json: — nicht lesbar"
  fi
fi

# docs/decisions/ — mass of logs, aggregated with count and newest date.
# README.md is the directory's convention document, not a log: it is skipped
# before both the count and the name comparison. Skipping it only in the
# comparison would leave the count one too high, and leaving it in the
# comparison made the receipt report "neuestes README" forever - "README.md"
# sorts above every YYYY-MM-DD name, so the newest real log could never win.
if [ -d "${ROOT}/docs/decisions" ]; then
  dec_count=0
  newest=""
  shopt -s nullglob
  for f in "${ROOT}"/docs/decisions/*.md; do
    name="${f##*/}"
    if [ "$name" = "README.md" ]; then continue; fi
    dec_count=$((dec_count + 1))
    [ "$name" \> "$newest" ] && newest="$name"
  done
  shopt -u nullglob
  if [ "$dec_count" -gt 0 ]; then
    emit "- docs/decisions/ — ${dec_count} Logs, neuestes ${newest:0:10}"
  fi
fi
emit "OK"
emit ""

# --- Gruppe 2: Skills --------------------------------------------------------
# One line per .claude/skills/<name>/SKILL.md, name and metadata.version read
# from its YAML frontmatter (the block between the first two "---" lines; the
# last match wins, quotes stripped). Bash builtins, not jq, matching the
# rule-index parsing above: this hook must run where jq is absent.
# .claude/skills/README.md sits directly under skills/ (no directory hop) and
# is the directory's own convention doc, not a skill - the glob below already
# excludes it.
emit "## Skills"
shopt -s nullglob
name_re='^name:[[:space:]]*(.*)$'
version_re='^[[:space:]]+version:[[:space:]]*(.*)$'
quotes="\"'"
for f in "${ROOT}"/.claude/skills/*/SKILL.md; do
  skill_text=""; slurp skill_text "$f"
  name="" ver="" fences=0
  while IFS= read -r l; do
    if [[ $l =~ ^---[[:space:]]*$ ]]; then
      fences=$((fences + 1))
      [ "$fences" -ge 2 ] && break
      continue
    fi
    [ "$fences" -eq 1 ] || continue
    if [[ $l =~ $name_re ]]; then name="${BASH_REMATCH[1]}"
    elif [[ $l =~ $version_re ]]; then ver="${BASH_REMATCH[1]}"; fi
  done <<< "$skill_text"
  name="${name//[$quotes]/}"; ver="${ver//[$quotes]/}"
  [ -n "$name" ] && emit "- ${name} v${ver:-?}"
done
shopt -u nullglob
emit "OK"
emit ""

# --- Gruppe 3: Profil --------------------------------------------------------
emit "## Profil"
emit "- Claude-Profil / User-Preferences: — (nicht verfuegbar in dieser Umgebung)"
emit "OK"
emit ""

# --- Gruppe 4: Memory --------------------------------------------------------
# The memory index, if this environment has one: ${CLAUDE_CONFIG_DIR:-~/.claude}/
# projects/<slug>/memory/MEMORY.md, <slug> being $ROOT with each of ':', '\',
# '/', '.' replaced by '-' (the same shape Claude Code itself uses for the
# projects/ directory name). Reimplementing that mapping exactly is not
# required and not attempted beyond this; when it does not resolve, the line
# falls back to the honest "not available" marker rather than a DIFFERENT
# project's memory - a review round measured this reporting another project's
# 5-entry MEMORY.md as this session's own, the unhonest direction ww3d/playbook#164 point 2
# exists against.
emit "## Memory"
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mem_md="${config_dir}/projects/${slug}/memory/MEMORY.md"
if [ -f "$mem_md" ]; then
  mem_text=""; slurp mem_text "$mem_md"
  mem_count=0
  while IFS= read -r l; do
    case "$l" in "- ["*) mem_count=$((mem_count + 1)) ;; esac
  done <<< "$mem_text"
  emit "- Memory: ${mem_count} Eintraege (MEMORY.md)"
else
  emit "- Memory-Stand: — (nicht verfuegbar in dieser Umgebung)"
fi
emit "OK"

# Assemble the receipt and inject it as SessionStart additionalContext. JSON is
# built by hand (no jq dependency): the content is fixed German prose, so only
# backslash, double-quote and newline need escaping.
printf -v text '%s\n' "${lines[@]}"
text="${text%$'\n'}"
text="${text//\\/\\\\}"
text="${text//\"/\\\"}"
text="${text//$'\n'/\\n}"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$text"
