# Architecture

## Overview

The extension renders markdown as an interactive workbench view: checkboxes
(in lists and table cells) are clickable and every toggle is mirrored
surgically into the source file - a single-character `[ ]` <-> `[x]` edit,
one undo step. Two entry modes wrap the same machinery, mirroring the
built-in markdown preview exactly:

1. **WebviewPanel preview** (`showPreview` into the active group,
   `showPreviewToSide` next to it). One panel per document, tracked in a
   `previews` map; the panel closes with its source document.
2. **CustomTextEditorProvider** (`markdownWorkbench.editor`) replacing the
   text editor in place (`Open as Workbench` / `Reopen as source file` use
   `reopenActiveEditorWith` for an in-place tab swap).

Both modes call `wireWebview(document, panel, closeWithDocument)`, which owns
the full message protocol.

## Module layout

The extension-host code is split by responsibility; all four modules are
bundled into `dist/extension.cjs` by tsdown (`src/extension.js` is the entry):

- **`src/extension.js`** - activation entry point. `activate`/`deactivate`,
  command registration and the WebviewPanel preview orchestration (the
  `previews` map, `openPreviewPanel`, the showSource / toggle / save-undo-redo
  bridges).
- **`src/render.js`** - the markdown-it instance, the task-list /
  table-checkbox / line-number plugins, the frontmatter property-card
  renderer and the Shiki fence renderer (`initHighlighter`, `shikiTheme`).
  Owns `activePosts`, the set of re-render callbacks the highlighter triggers
  once it finishes loading.
- **`src/views.js`** - the shared view machinery: `wireWebview`, the
  custom-editor provider (`WorkbenchEditorProvider`), the scroll-sync helpers
  (`getVisibleLine` / `scrollEditorToLine` / capture / reveal), the
  configuration resolver (`configuredViewConfig`), the surgical toggle paths
  (`applyToggle` / `applyCellToggle`) and the `getWebviewHtml` skeleton. Holds
  the `Workbench:` tab-title prefix as a single constant.
- **`src/editing.js`** - editor-side authoring commands (see below).

The webview runtime is shipped as plain media assets, not bundled into the
host: **`media/webview.js`** (the script) and **`media/webview.css`** (the
styles). They run in the webview, never in the extension host.

## Webview loading

`getWebviewHtml(webview)` returns a slim skeleton: a `<link>` to
`media/webview.css` and a `<script>` to `media/webview.js`, both resolved via
`webview.asWebviewUri`. `wireWebview` sets `localResourceRoots` to the
`media/` folder so the webview may load them. The skeleton carries a
Content-Security-Policy with a per-load nonce: `default-src 'none'`;
`script-src 'nonce-...'` matching the nonce on the script tag; `style-src`
from the webview origin plus `'unsafe-inline'` (Shiki emits per-token colors
as inline `style` attributes, and user markdown may too with `html: true`, so
a strict style policy would blank highlighted code); and `img-src` from the
webview origin plus `https:`/`http:`/`data:` (remote images keep loading as
before the CSP existed). Only the script is nonce-gated; the rendered content
itself is not CSP-restricted (DECISIONS.md #22).

## Rendering pipeline

markdown-it (`html: true`, `linkify`) with these plugins, in order:

- **taskListPlugin** - list items starting with `[ ]`/`[x]` become
  `.task-row` elements (checkbox + content) carrying `data-line`.
- **tableCheckboxPlugin** - `[ ]`/`[x]` inside `td` cells become
  `input.cell-task`. A table row is one source line that can hold several
  checkboxes, so each input carries the row line (from `tr_open.map`) plus
  its occurrence index on that line. Code spans are skipped; `th` cells are
  excluded by contract. See DECISIONS.md #10/#11.
- **markdown-it-front-matter** - YAML headers render as a property card
  (key/value grid for flat mappings, raw block fallback otherwise).
- **injectLineNumbers** - every block token with a map gets `data-line`;
  fences additionally get `data-line-end` for intra-block scroll
  interpolation.
- **custom fence renderer** - Shiki highlighting (async-initialized;
  plain-text fallback until ready), themes `dark-plus`/`light-plus` chosen
  by `activeColorTheme.kind`, re-render on theme switch.

## Toggle paths

- **Lists**: `applyToggle(document, lines, checked)` - validates each line
  against `CHECKBOX_RE`, flips the bracket character via one `WorkspaceEdit`
  (uniform target state for multi-select, single undo step).
- **Table cells**: `applyCellToggle(document, line, idx, checked)` - flips
  the nth bracket occurrence on the line. Code spans are blanked
  index-preservingly before counting so render-side and source-side
  occurrence indices stay aligned.
- Webview side: checkbox clicks read `hasAttribute('checked')` (the live
  `.checked` has already flipped when the click handler runs). A cell with
  exactly one checkbox toggles on any click inside the cell (`:has()`-based
  affordance styling).

## Scroll sync

Bidirectional and fractional, algorithms taken 1:1 from the built-in
preview (`scrolling.ts` / `scroll-sync.ts`):

- Editor -> webview: `getVisibleLine` = top line + `character/(length+2)`;
  the webview interpolates between `data-line` elements and proportionally
  inside multi-line fences via `data-line-end`.
- Webview -> editor: `scrollEditorToLine` encodes the fraction as a
  character offset using `fraction * text.length` (deliberately asymmetric -
  that is what the built-in does).
- Echo suppression: 200ms windows on both sides; webview scroll handling is
  rAF-throttled. The minimap updates inside that rAF even for suppressed
  (editor-driven) scrolls.
- Initial position: captured before opening (`pendingInitialScroll`),
  delivered as `scrollTo` after `ready` + first render. `lastKnownTopLine`
  feeds the reverse navigation (`showSource` reveals the stored line).

## Minimap

An 88px rail containing a scaled `cloneNode` of the rendered content plus a
viewport slider (minimapSlider theme tokens). Three size modes mirroring
`editor.minimap.size`:

- `proportional` - fixed scale `kx = railWidth / contentWidth`, pans when
  the scaled document exceeds the rail.
- `fill` - the document maps linearly onto the full rail
  (`sy = railHeight / docHeight`); the slider stays aligned with the
  scrollbar thumb.
- `fit` - `sy = min(kx, railHeight / docHeight)`: shrink to fit, never
  stretch.

Pointerdown inside the slider rectangle grabs it (like the editor minimap):
the viewport moves relative to the grab point, no jump on grab. The hit
test is geometric from the live mapping (`scrollY * mapSy + mapOffset`,
same math as the slider rendering) rather than CSS, so the
mouseover-hidden slider stays grabbable; the math works in all three size
modes. Clicks on the rail outside the slider keep the centering jump
(pointer capture, held drag keeps centering). The rail spans the full
viewport height; the hint bar yields to it. The clone is rebuilt only on
render, resize and config changes; per-scroll work is limited to
transform/slider updates. Visibility is decided *before* measuring the rail
width (a `display: none` element reports `clientWidth` 0 and would bake a
scale of 0 into the clone).

## Table of contents (scroll-spy + rail/FAB)

A visible in-document TOC, built on the heading anchors (DECISIONS.md #31/#32).

- **Scroll-spy** (`scrollSpy` in `media/webview.js`) is a self-contained,
  reusable base: it tracks the active heading (the last one scrolled past an
  activation line near the top, `activeHeadingIndex`) and its h1..h6 ancestor
  chain (`ancestorChain`), and notifies subscribers on change. An
  `IntersectionObserver` on the headings triggers the recompute; the active
  index is decided by geometry, and the existing scroll rAF pumps the same
  `update()`. Heading tops are document coordinates, cached on render and
  refreshed on reflow only. The follow-up breadcrumb + sticky-scroll stack (#44)
  subscribes to this same signal.
- **Rail** - a `position: fixed` panel with the heading hierarchy, on the side
  opposite the minimap (no own side config). The active entry is highlighted,
  its section expanded (others collapsed), and kept in view; a click scrolls
  smoothly to the heading via the shared `navigateToHash`. The rail's width is
  reserved as body padding so the centered content clears it.
- **FAB/overlay** - when the viewport is too narrow for the rail beside the
  content, a floating button opens the same TOC in an overlay (backdrop click /
  Escape to close).
- **Rail vs. FAB** is content-relative (`railFits`: viewport >= content
  max-width + rail reserve + the opposite-side rail/gutter), live via a
  `ResizeObserver`; `markdownWorkbench.toc.mode` (`auto`/`rail`/`fab`) overrides
  it, `markdownWorkbench.toc.enabled` turns it off.

## Breadcrumb + sticky-scroll stack

Two fixed bars pinned to the top of the content region (DECISIONS.md #33), both
consumers of the same `scrollSpy` signal as the TOC - no scroll-spy change.

- **Breadcrumb** (`#breadcrumb`) - a single-line trail of the active heading's
  chain. Each segment scrolls to its heading (smooth, via `navigateToHash`) and
  opens a sibling picker (`#breadcrumb-dropdown`): the headings at the same level
  under the same parent, computed by the pure `siblingHeadings(levels, index)`.
  A constant-height bar; `body.has-breadcrumb` reserves its measured height
  (`--breadcrumb-height`) as top padding so content clears it.
- **Sticky-scroll stack** (`#sticky-scroll`) - the same chain rendered as pinned
  heading rows directly below the breadcrumb, rebuilt from the active chain on
  each emit (an overlay, not `position: sticky` on the content headings). Overlays
  content without reserving space; a row click scrolls to its heading. Hidden
  above the first heading (empty chain).
- **Anchor clearance** - `--toc-scroll-margin` (introduced in #32) is raised to
  the bars' combined height plus a gap (`topBarsScrollMargin`), and
  `navigateToHash` subtracts the same offset so anchor jumps land below the bars.
  The scroll-spy's activation line is shifted by the same inset
  (`scrollSpy.setTopInset`), so the heading marked active after a jump is the one
  that lands below the bars, not the one above it.
- **Scroll cost** - the per-active-change work is kept minimal: `updateTopBars`
  rebuilds only when the chain/heading-set/config actually changed, heights are
  measured only when the sticky row count changes (no per-frame forced layout),
  the CSS vars are written only on change, the bars reconcile their `<a>` nodes
  in place, and `applyTocActive` toggles only the changed links (O(path), not
  O(headings)).
- **Layout** - the bars fill the content region only, clearing the minimap and
  TOC rail via the same per-side reserves as the body padding. z-index top to
  bottom: breadcrumb dropdown (8) > TOC overlay (7) > FAB/backdrop (6) >
  minimap/TOC rail (5) > top bars (4) > sticky table header (2) > content.
- **Config** - `markdownWorkbench.breadcrumb.enabled` and
  `markdownWorkbench.stickyScroll.enabled` (both default `true`, independent),
  on the `config` message with the same defensive defaults as the minimap/TOC.

## Webview scrollbar

The webview uses a custom scrollbar (editor `scrollbarSlider` tokens, no
arrow buttons) so the thumb track spans the full height and aligns with the
minimap rail. Two traps documented in DECISIONS.md #15: pseudo-element
rules need `::-webkit-scrollbar` itself styled (custom mode), and VS Code
injects `scrollbar-color` into every webview which disables webkit scrollbar
styling entirely until reset to `auto`.

## Configuration

`markdownWorkbench.preview.maxWidth` (`github` = 980px default / `narrow` =
72ch), `markdownWorkbench.minimap.*` (`enabled`, `size`, `showSlider`, `side`),
`markdownWorkbench.toc.*` (`enabled`, `mode`) and the top-bar toggles
`markdownWorkbench.breadcrumb.enabled` / `markdownWorkbench.stickyScroll.enabled`
(both default `true`). The extension resolves values
with explicit fallbacks and pushes them as a `config` message - on `ready`
*before* the first render (so the initial scroll lands in the final layout) and
live on every configuration change. The webview merges incoming minimap and TOC
config over defaults so undefined values can never disable the rail (regression
0.21.1). The TOC has no side setting: it derives its side from `minimap.side`
(opposite side) in the webview.

## Editing features (editing.js)

Editor-side authoring commands, modeled on Learn Markdown / Markdown All in
One: Enter list continuation (numbered increment, empty-item termination),
code-fence auto-close (unindented snippet - VS Code auto-indents
continuation lines), fence language IntelliSense (Shiki ids + verified
aliases), Tab/Shift+Tab adaptive nesting, wrap toggles (bold/italic/code,
wrap/unwrap/extend-unwrap), web/file link insertion, table insert
(snippet with tab stops), distribute/consolidate table reflow (alignment
colons preserved), numeric-aware selection sort, authoring quick-pick menu.

## Message protocol (host <-> webview)

| Direction | Type | Payload |
|---|---|---|
| host -> webview | `config` | `maxWidth`, `minimap{enabled,size,showSlider,side}`, `toc{enabled,mode}`, `breadcrumb{enabled}`, `stickyScroll{enabled}`, preview readability flags |
| host -> webview | `render` | `html` |
| host -> webview | `scrollTo` | fractional `line` |
| webview -> host | `ready` | - |
| webview -> host | `toggle` | `lines[]`, `checked` |
| webview -> host | `toggleCell` | `line`, `idx`, `checked` |
| webview -> host | `scrolled` | fractional `line` |
