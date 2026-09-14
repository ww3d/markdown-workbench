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
# Idempotent, set -euo pipefail, never aborts on a missing file (then the entry
# reads "— nicht gefunden").
set -euo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

lines=()
emit() { lines+=("$1"); }
rel() { printf '%s' "${1#"${ROOT}"/}"; }

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
# by it: every ':', '\', '/', '.' becomes '-'.
slugify() { printf '%s' "$1" | tr ':\\/.' '----'; }

CACHE_FILE="${TMPDIR:-/tmp}/read-confirm-cache-$(slugify "$ROOT").tsv"

cache_get() { # path -> the cached blob SHA, or nothing
  [ -f "$CACHE_FILE" ] || return 0
  awk -F'\t' -v p="$1" '$1 == p { print $2 }' "$CACHE_FILE" 2>/dev/null
  return 0
}
cache_set() { # path sha
  local tmp
  tmp="$(mktemp "${CACHE_FILE}.XXXXXX" 2>/dev/null || true)"
  [ -n "$tmp" ] || return 0
  { [ -f "$CACHE_FILE" ] && awk -F'\t' -v p="$1" '$1 != p' "$CACHE_FILE" 2>/dev/null
    printf '%s\t%s\n' "$1" "$2"; } > "$tmp" 2>/dev/null
  mv "$tmp" "$CACHE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
# Emit either the full line, or - if this file's blob SHA matches the cached
# one from a previous run - a short "unveraendert seit" line instead.
emit_tracked_file() { # abs path, full-form line
  local f="$1" full_line="$2" rel_path sha cached
  rel_path="$(rel "$f")"
  sha="$(git -C "$ROOT" hash-object "$f" 2>/dev/null || true)"
  if [ -n "$sha" ]; then
    cached="$(cache_get "$rel_path")"
    cache_set "$rel_path" "$sha"
    if [ -n "$cached" ] && [ "$cached" = "$sha" ]; then
      emit "- ${rel_path}: unveraendert seit ${sha:0:7}"
      return
    fi
  fi
  emit "$full_line"
}

# Playbook version: the synced .playbook-version in a consumer; fall back to
# /VERSION so the hook also reports correctly when run inside the playbook itself.
# Sets the globals VER (the value) and VER_SRC (the source file it was read from).
VER=""
VER_SRC=""
read_playbook_version() {
  local f
  for f in ".playbook-version" "VERSION"; do
    if [ -f "${ROOT}/${f}" ]; then
      VER="$(head -n1 "${ROOT}/${f}" | tr -d '[:space:]')"
      VER_SRC="$f"
      return 0
    fi
  done
  return 1
}

# First "build NN" marker in a versioned baseline-doc header, if present.
build_marker() {
  grep -oiE 'build[[:space:]]+[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+' | head -n1
}

read_playbook_version || true
VER_LABEL="${VER:-unbekannt}"

emit "# Session-Read-Confirmation (Playbook ${VER_LABEL})"
emit ""

# --- Gruppe 1: Konventionen -------------------------------------------------
emit "## Konventionen"
if [ -n "$VER" ]; then
  emit "- Playbook-Version: ${VER} (${VER_SRC})"
else
  emit "- Playbook-Version: — nicht gefunden"
fi

if [ -f "${ROOT}/CLAUDE.md" ]; then
  emit_tracked_file "${ROOT}/CLAUDE.md" "- CLAUDE.md @ projekt OK"
else
  emit "- CLAUDE.md: — nicht gefunden"
fi

if [ -f "${ROOT}/AGENTS.md" ]; then
  emit_tracked_file "${ROOT}/AGENTS.md" "- AGENTS.md @ playbook ${VER_LABEL}"
else
  emit "- AGENTS.md: — nicht gefunden"
fi

# Tech overlays (playbook-versioned): tech/common/*.md plus tech/*.md wrappers.
shopt -s nullglob
for f in "${ROOT}"/tech/common/*.md "${ROOT}"/tech/*.md; do
  [ "$(basename "$f")" = "README.md" ] && continue
  emit_tracked_file "$f" "- $(rel "$f") @ playbook ${VER_LABEL}"
done

# docs/common/ — playbook-synced bulk, aggregated.
if [ -d "${ROOT}/docs/common" ]; then
  common_count=0
  for f in "${ROOT}"/docs/common/*.md; do
    common_count=$((common_count + 1))
  done
  emit "- docs/common/ — ${common_count} Dateien OK"
fi

# Top-level docs/*.md — consumer-owned wrappers and baseline docs. Versioned
# baseline docs carry a "build NN" header; show it where present (hybrid detail).
for f in "${ROOT}"/docs/*.md; do
  [ "$(basename "$f")" = "README.md" ] && continue
  b="$(build_marker "$f" || true)"
  if [ -n "$b" ]; then
    emit_tracked_file "$f" "- $(rel "$f") build ${b}"
  else
    emit_tracked_file "$f" "- $(rel "$f") OK"
  fi
done

# The generated rule index. One line per point of use, read from
# .agents/rules/index.json rather than from the rule files themselves: the JSON
# IS the generated artifact, and reading the files instead would put a second,
# ungated derivation of the same table into the receipt. Parsed with awk, not
# jq — this hook must run where jq is absent. The generator writes one key per
# line in a fixed order (trigger, then path), which is what makes the pairing
# safe.
if [ -f "${ROOT}/.agents/rules/index.json" ]; then
  rule_lines="$(awk -F'"' '
      /"trigger"[[:space:]]*:/ { t = $4 }
      /"path"[[:space:]]*:/    { if (t != "") { print "- " t " -> " $4; t = "" } }
    ' "${ROOT}/.agents/rules/index.json" 2>/dev/null || true)"
  if [ -n "$rule_lines" ]; then
    emit "- .agents/rules/ — Einsatzpunkt-Regeln (vor der ersten Aktion je Trigger lesen):"
    while IFS= read -r rule_line; do
      emit "  ${rule_line}"
    done <<< "$rule_lines"
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
  for f in "${ROOT}"/docs/decisions/*.md; do
    name="$(basename "$f")"
    if [ "$name" = "README.md" ]; then continue; fi
    dec_count=$((dec_count + 1))
    [ "$name" \> "$newest" ] && newest="$name"
  done
  if [ "$dec_count" -gt 0 ]; then
    emit "- docs/decisions/ — ${dec_count} Logs, neuestes ${newest:0:10}"
  fi
fi
shopt -u nullglob
emit "OK"
emit ""

# --- Gruppe 2: Skills --------------------------------------------------------
# One line per .claude/skills/<name>/SKILL.md, name and metadata.version read
# from its YAML frontmatter. Deliberately awk, not jq, matching the rule-index
# parsing above: this hook must run where jq is absent. .claude/skills/README.md
# sits directly under skills/ (no directory hop) and is the directory's own
# convention doc, not a skill - the glob below already excludes it.
emit "## Skills"
shopt -s nullglob
for f in "${ROOT}"/.claude/skills/*/SKILL.md; do
  info="$(awk -F': *' '
      /^---[[:space:]]*$/ { n++; if (n == 2) exit; next }
      n == 1 && /^name:/               { name = $2 }
      n == 1 && /^[[:space:]]+version:/ { ver = $2 }
      END { gsub(/["'"'"']/, "", name); gsub(/["'"'"']/, "", ver); print name "|" ver }
    ' "$f" 2>/dev/null || true)"
  name="${info%%|*}"
  ver="${info#*|}"
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
# 5-entry MEMORY.md as this session's own, the unhonest direction #164 point 2
# exists against.
emit "## Memory"
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mem_slug="$(slugify "$ROOT")"
mem_md=""
[ -f "${config_dir}/projects/${mem_slug}/memory/MEMORY.md" ] \
  && mem_md="${config_dir}/projects/${mem_slug}/memory/MEMORY.md"
if [ -n "$mem_md" ]; then
  mem_count="$(grep -c '^- \[' "$mem_md" 2>/dev/null || true)"
  emit "- Memory: ${mem_count:-0} Eintraege (MEMORY.md)"
else
  emit "- Memory-Stand: — (nicht verfuegbar in dieser Umgebung)"
fi
emit "OK"

# Assemble the receipt and inject it as SessionStart additionalContext. JSON is
# built by hand (no jq dependency): the content is fixed German prose, so only
# backslash, double-quote and newline need escaping.
text="$(printf '%s\n' "${lines[@]}")"
text="${text//\\/\\\\}"
text="${text//\"/\\\"}"
text="${text//$'\n'/\\n}"

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$text"
