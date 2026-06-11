# Decisions

Numbered log of the significant decisions, including rejected approaches.
Newest entries last.

## 1. Surgical toggles instead of re-serialization
A toggle replaces exactly one character (`[ ]` <-> `[x]`) via
`WorkspaceEdit`. The document is never re-serialized from the rendered
model, so formatting, whitespace and everything else stay untouched. One
edit per toggle batch = one undo step.

## 2. Two view modes, mirroring the built-in preview
WebviewPanel preview (active group / to the side) plus a
CustomTextEditorProvider for in-place opening. Command titles, menu
placement (tab-row buttons with Alt-alternates, context menus), tab icon
and `Checklist:` title prefix all mirror the built-in markdown preview so
the extension can act as a drop-in replacement. `vscode.openWith` created a
second tab (tabs are keyed by resource + editor type), so in-place swaps
use `reopenActiveEditorWith`; `openWith` remains the fallback for non-active
URIs.

## 3. No strikethrough on completed items
Tried in 0.1.x, removed in 0.2.0 on feedback. Completed items keep a
dimming (`opacity: .55`) only.

## 4. Multi-select toggling for list tasks only
Ctrl/Shift selection collects task rows and toggles them to the uniform
state of the clicked row. Table cell checkboxes are direct-toggle: cells
are not selectable row items, and column-wise batch toggling was deferred
until actually needed.

## 5. Scroll sync ported 1:1 from the built-in preview
`getVisibleLine` decodes with `character/(length+2)`; `scrollEditorToLine`
encodes with `fraction * text.length`. The asymmetry is deliberate - it is
exactly what `scrolling.ts` in the built-in preview does (verified against
the VS Code source; a test initially "fixed" this and was itself wrong).

## 6. Shiki over highlight.js
The built-in preview highlights with highlight.js plus a static stylesheet
(`markdownEngine.ts` line ~399, `media/highlight.css`). Shiki with real
TextMate grammars (dark-plus/light-plus by theme kind) tokenizes more
accurately. Loading the user's exact theme JSON into Shiki is possible
(include-chain resolution) but deferred; Shiki cannot do semantic
highlighting either way.

## 7. Interpreted, dependency-light webview
The webview HTML/CSS/JS is one inline template in extension.js. No
framework, no build step for the view. State lives in the source document;
the webview is re-rendered from scratch on every change.

## 8. Frontmatter as a property card
YAML frontmatter renders as a key/value grid for flat mappings, raw block
otherwise - instead of leaking `---` as a thematic break or hiding the
header entirely.

## 9. Table checkboxes addressed by line + occurrence index
A table row is a single source line holding several checkboxes. `tr_open`
carries the line map; each converted bracket gets a per-line occurrence
index. The source-side toggle finds the nth bracket on the line.

## 10. Code spans excluded on both sides, index-preservingly
markdown-it does not convert brackets inside code spans, so the source-side
occurrence scan must not count them either - otherwise indices drift and a
click toggles the wrong bracket (found by a test in 0.16.0). Code spans are
blanked with same-length spaces before counting.

## 11. Header cells (`th`) stay literal
Documented from 0.16.0 on, but the plugin accidentally converted `th`
content until 0.22.0 (the `th_open` branch set `inCell`). The test suite
exposed the contract violation; the documented behavior won and the code
was fixed.

## 12. Whole-cell click toggles single-checkbox cells
Cells containing exactly one checkbox toggle on any click inside the cell
(pointer cursor + hover highlight via `:has()`); multi-checkbox cells
require a direct checkbox click to stay unambiguous.

## 13. Width: GitHub's 980px by default, 72ch opt-in
History: 72ch reading column -> full width (matching the unstyled built-in,
which has *no* max-width, only `padding: 0 26px`) -> full-bleed breakout
grid (rejected) -> 980px (GitHub's measure from github-markdown-css,
matching the user's built-in preview which is styled by the Markdown
Preview Github Styling extension via `markdown.previewStyles`) -> finally a
setting (`markdownWorkbench.preview.maxWidth`: `github` | `narrow`).
Industry reference points: GitHub ~980px, Medium ~680px, Notion ~700px,
Tailwind prose 65ch.

## 14. Tables: modern docs styling with sticky headers
No vertical grid, horizontal hairlines only, uppercase muted header labels,
zebra striping (4% foreground mix), row hover (7%).
`border-collapse: separate` is required: with `collapse`, the border of a
`position: sticky` th scrolls away with the body in Chromium.

## 15. Custom webview scrollbar - functional, not cosmetic
A purely cosmetic scrollbar restyle (0.17.1) was reverted as useless. It
returned in 0.21.x for a functional reason, after two inert attempts:
(a) `::-webkit-scrollbar-button { display: none }` alone does nothing -
pseudo-element rules require `::-webkit-scrollbar` itself to be styled
(custom mode); (b) even the full block stays dead because VS Code injects
`scrollbar-color` into every webview (`pre/index.html`, `@layer
vscode-default`), and a non-auto `scrollbar-color` makes Chromium ignore
all webkit scrollbar pseudos. The fix resets `scrollbar-color: auto`
(unlayered author styles beat the injected layer), then styles the custom
scrollbar. Without it, the Windows arrow buttons shorten the thumb track
and misalign it against the full-height minimap rail.

## 16. Minimap: own implementation, three size modes
The Monaco minimap is editor-only and unavailable to webviews. The own
implementation clones the rendered content (rebuilt only on
render/resize/config; per-scroll work is transform/slider updates inside
the existing rAF). Size modes mirror `editor.minimap.size`:
`proportional` (fixed scale, pans), `fill` (linear mapping, slider aligned
with the scrollbar - never drifts), `fit` (shrink to fit, never stretch).
`renderCharacters`/`scale` were deliberately not mirrored: the clone is
real HTML, there is no block-vs-character rendering to switch.
Two captured regressions: visibility must be decided before measuring the
rail (display:none -> clientWidth 0 -> scale 0 baked into the first
render), and the rail must span the full viewport height (it initially
ended above the hint bar, shortening its mapping length against the
scrollbar).

## 17. Defensive configuration handling
Right after an in-place extension update, `get()` can resolve contributed
settings to `undefined`, which once disabled the minimap entirely
(0.21.0 -> 0.21.1). Both sides guard: `get(key, default)` in the extension,
`Object.assign` over defaults in the webview.

## 18. Editing features absorbed from Learn Markdown
The generic authoring features (Enter/Tab list handling, Alt+D formatting,
table tools, sort) were reimplemented natively so the Learn Markdown
extension can be disabled (its keybindings collide). Learn-specific
pipeline features were not copied. Fence auto-close inserts an unindented
snippet (`'\n$0\n' + delimiter`) because VS Code auto-indents snippet
continuation lines - including the indent would double it.

## 19. Icon: filled accent box, monochrome glyph for VS Code UI
Marketplace icon (PNG - vsce rejects SVG): slate tile, filled
mint-to-cyan checked box with knockout check above muted pending rows. An
outline-box variant mushed at small sizes; a mask-based knockout glyph was
dropped because mask rendering proved unreliable. The in-product 16px
glyphs are monochrome outline (codicon-style) in light/dark variants.

## 20. package.json version is the source of truth
vsce requires it; the topmost CHANGELOG.md entry must match, enforced by
`build.ps1` before packaging. README.md and CHANGELOG.md are updated with
every change (standing rule).

## 21. tsdown bundle, PowerShell orchestration, node:test + c8
The vsix ships a minified bundle built by tsdown (Rolldown + Oxc - the
tsup successor and 2026 state of the art for library bundling; esbuild
served until 0.22.0). Rolldown code-splits Shiki's dynamic language and
theme imports into lazy chunks, so only languages actually used in fences
load at runtime. Runtime dependencies are inlined via `deps.alwaysBundle`;
`vscode` stays external (`deps.neverBundle`). tsdown also carries the
planned TypeScript migration (including .d.ts) without re-tooling; it
requires Node 22+. Tests use
node:test with a hand-rolled vscode mock (editable documents/editors) and
a DOM mock that executes the webview script headlessly; c8 gates coverage
in CI. Build tasks live in `build.ps1` (Test / Coverage / Build / Package /
All).

## 22. Out of scope (deliberate, revisit on demand)
Relative local images (`asWebviewUri`/`localResourceRoots` rewriting),
anchor links + heading slugs, Mermaid/Math, exact user theme for Shiki,
strict CSP (the view renders the user's own files with `html: true` and
scripts enabled), a Chrome minimap extension (explored, shelved).
