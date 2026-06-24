@AGENTS.md

## Project Context

**Markdown Workbench** is a VS Code extension: an interactive markdown preview
with toggleable checkboxes, a minimap, modern tables and authoring tools.
Toggles are mirrored surgically back into the source file. Stack: JavaScript
(VS Code Extension API, Node; `src/*.js`, tests via `node --test`), bundled
with tsdown.

Architecture and contributor docs in `docs/`:

- `docs/common/*.md` (synct aus `ww3d/playbook`)

## Architecture Principles

_keine_

## Project-Specific Overrides

- Stack ist im Playbook inventory-only (kein `tech/common/javascript.md`); diese
  CLAUDE.md importiert daher nur `@AGENTS.md`.
- Bestehender CI (`.github/workflows/test.yml`) ist projekt-eigen und nicht von
  `docs/common/ci.md` geregelt.
