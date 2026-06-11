@AGENTS.md

## Project Context

**Markdown Workbench** is a VS Code extension: an interactive markdown preview with toggleable checkboxes (mirrored surgically into the source file), a minimap, modern tables and editor authoring tools. Stack: Node.js / JavaScript (CommonJS sources, tsdown/Rolldown bundle; TypeScript migration planned).

Architecture and contributor docs in `docs/`:

- `docs/common/*.md` (synct aus `ww3d/playbook`)
- `docs/ARCHITECTURE.md` — Render-Pipeline, Toggle-Pfade, Scroll-Sync, Minimap, Message-Protokoll
- `docs/DECISIONS.md` — nummeriertes Entscheidungs-Log inkl. verworfener Ansaetze
- `CONTRIBUTING.md` — Build/Test/Release-Workflow (build.ps1, node:test + c8, vsce)

## Architecture Principles

- Toggles are surgical single-character edits via WorkspaceEdit - the document is never re-serialized from the rendered model.
- Both view modes (side preview, custom editor) share one wiring (`wireWebview`) and mirror the built-in markdown preview's commands, menus and scroll-sync algorithms.
- The webview stays one dependency-free inline template; state lives in the source document.
- package.json version is the source of truth; the topmost CHANGELOG entry must match (enforced by build.ps1). README and CHANGELOG move with every change.

## Project-Specific Overrides

_keine_
