# Architecture

Marker evidence is the latest state audit (`audit/ist-stand-2026-09-29T2304Z.md`); this repo has
no dedicated architecture tests.

## Overview

The extension renders markdown as an interactive workbench view: checkboxes
(in lists and table cells) are clickable and every toggle is mirrored
surgically into the source file - a single-character `[ ]` <-> `[x]` edit.
[erfuellt] (tests/views/toggle.test.js, tests/webview.test.js) Each toggle is
one undo step. [teilweise #97] steht: one `WorkspaceEdit` per toggle
(`src/views/toggles.js`, DECISIONS.md #1) fehlt: a test asserting exactly one
`applyEdit` call per toggle (`tests/views/toggle.test.js` counts ops, not
edits)

Two entry modes wrap the same machinery, mirroring the built-in markdown
preview's entry points (DECISIONS.md #2; task rendering deviates on purpose,
DECISIONS.md #25). [nicht verifiziert] (microsoft/vscode - the built-in preview's
behavior lives there; the shared `wireWebview` path is covered under "Both
modes call" below)

1. **WebviewPanel preview** (`showPreview` into the active group,
   `showPreviewToSide` next to it). [teilweise #97] steht: both commands open
   a wired panel (`src/extension.js`, tests/activation.test.js) fehlt: a test
   asserting the view column of each. One panel per document, tracked in a
   `previews` map. [teilweise #97] steht: a second open reveals the existing
   panel (tested) fehlt: a test that no second panel is created. The panel
   closes with its source document.
   [teilweise #97] steht: the `onDidCloseTextDocument` listener
   (`src/views/wire.js`) fehlt: a test firing it
2. **CustomTextEditorProvider** (`markdownWorkbench.editor`) replacing the
   text editor in place [erfuellt] (`Open as Workbench` swaps the active
   editor via `reopenActiveEditorWith` and falls back to `vscode.openWith` for
   a non-active resource; `Reopen as source file` swaps back with
   `reopenActiveEditorWith 'default'`; DECISIONS.md #2). [teilweise #97]
   steht: both `reopenActiveEditorWith` calls and the `openWith` fallback
   (`src/extension.js`) fehlt: Test

Both modes call `wireWebview(document, panel, closeWithDocument)`, which owns
the full message protocol. [erfuellt]

**Restore after a restart (DECISIONS.md #34).** The preview panel registers a
`WebviewPanelSerializer` for `markdownWorkbench.preview` (with
`onWebviewPanel:markdownWorkbench.preview` in `activationEvents`). The webview
persists its document URI via `setState` (the URI rides the `config` message);
`deserializeWebviewPanel` reopens that document and re-wires the panel through
the same `attachPreviewPanel` path as a fresh open. [teilweise #97] steht:
serializer registration, `setState` round trip and every `deserializeWebviewPanel`
edge (`tests/activation.test.js`) fehlt: a test asserting the
`onWebviewPanel:markdownWorkbench.preview` entry in `activationEvents`
(`package.json`). The custom editor mode needs no serializer - VS Code
re-resolves registered custom editors on restart. [nicht verifiziert]
(microsoft/vscode - the custom-editor restore behavior lives there)

## Module layout

The extension-host code is split by responsibility; every module under `src/`
is bundled into `dist/extension.cjs` by tsdown (`src/extension.js` is the
entry). [erfuellt]

- **`src/extension.js`** - activation entry point. `activate`/`deactivate`,
  command registration and the WebviewPanel preview orchestration (the
  `previews` map, `openPreviewPanel`, the showSource / toggle / save-undo-redo
  bridges). [erfuellt]
- **`src/render/`** - the markdown-it instance and its plugins, one file per
  subject: `parser.js` (the one `md` instance, plugin registration order, the
  line-start recording the table editor reads - no `vscode` import), `index.js`
  (adds the Shiki fence renderer, re-exports `md`, `activePosts`,
  `SHIKI_LANGS`, `initHighlighter`, `shikiTheme`), `task-lists.js`,
  `table-checkboxes.js`, `extra-markers.js`,
  `heading-anchors.js`, `frontmatter.js` (the property-card renderer) and
  `fence-highlight.js` (the Shiki fence renderer - `initHighlighter`,
  `shikiTheme`). `activePosts`, the set of re-render callbacks the highlighter
  triggers once it finishes loading, lives in `fence-highlight.js` and is
  re-exported from `index.js`. [erfuellt]
- **`src/views/`** - the shared view machinery, one file per subject:
  `index.js` (public exports), `identity.js` (`extensionUri`, tab-title
  prefix, `workbenchIconPath`), `config.js` (`configuredViewConfig`,
  `configuredRenderEnv`), `scroll-sync.js` (`getVisibleLine` /
  `scrollEditorToLine` / capture / reveal), `toggles.js` (`applyToggle` /
  `applyCellToggle`) and `html.js` (`getWebviewHtml`). `wire.js` ties them
  together (`wireWebview`, the custom-editor provider
  `WorkbenchEditorProvider`; it hands `sortTable` messages to `src/tables/`).
  [erfuellt]
- **`src/editing/`** - editor-side authoring commands (see below), one file per
  subject (`enter.js`, `tab.js`, `join.js`, ...); `index.js` registers them.
  [erfuellt]
- **`src/tables/`** - markdown table editing (DECISIONS.md #49): the pure table
  model (`row.js`, `blocks.js`, `detect.js`, `width.js`, `format.js`,
  `grid-ops.js`, `sort.js`, `csv.js` - no `vscode` import) and the editor side
  (`enter.js`, `tab.js`, `arrows.js`, `commands.js`, `paste.js`,
  `diagnostics.js`, `config.js`, `apply.js`); `index.js` registers them and
  hands the Enter/Tab branches to `src/editing/`. [teilweise #97] steht: the
  pure modules import no `vscode` (`src/tables/row.js` ... `csv.js`) and the
  Tab branch runs through `src/editing/` (tests/tables/tab.test.js) fehlt: a
  test that loads the pure modules without the vscode mock (pattern:
  `tests/markdown/syntax.test.js`) and a test of the Enter branch through
  `src/editing/` (`onEnterKey`)
- **`src/markdown/syntax.js`** - Markdown source primitives shared across
  modules and free of `vscode`: `CHECKBOX_RE` (the task-line pattern the
  toggle paths and the clipboard-diff check use) and `checkboxBoxPos` (the
  column of the box character in a match); `src/views/` re-exports it.
  [erfuellt] (tests/markdown/syntax.test.js) The one table reflow is
  `formatGrid` over `toGrid` in `src/tables/format.js`, on the table model: the
  editor's Distribute/Consolidate (`reflowTableCommand` in
  `src/editing/table-reflow.js`) call the two per table, the clipboard diff's
  style alignment calls `reflowTable` there, the line-based form of the same
  two. [erfuellt] (tests/tables/format.test.js,
  tests/editing/table-reflow.test.js, tests/clipboard-diff/style.test.js) The
  commands pass `tables.ambiguousWidth` (as `tablesConfig().ambiguousWide`).
  [teilweise #97] steht: `reflowTableCommand` fehlt: a test that the command
  follows `tables.ambiguousWidth` (only the wrapper `reflowTable` in
  `src/editing/table-reflow.js`, which no command calls, is tested for it)
- **`src/clipboard-diff/`** - the clipboard diff (section "Clipboard diff"
  below, DECISIONS.md #48). Pure modules without `vscode` - `anchor.js`,
  `style.js`, `emphasis.js`, `unwrap.js`, `check.js`, `history.js`,
  `region.js`, `lines.js`, `blocks.js` - and the binding to VS Code -
  `store.js`, `session.js`, `saving.js`, `sync.js`, `compare.js`, `apply.js`,
  `diagnostics.js`, `index.js`. Tests mirror the
  folder in `tests/clipboard-diff/`; the pure modules run there without the
  vscode mock. [erfuellt] (tests/clipboard-diff/)

`src/render/parser.js` builds the markdown-it instance without `vscode`, so it
also serves those pure modules and the table model outside the extension host.
[erfuellt] (tests/clipboard-diff/blocks.test.js loads it without the mock)

The webview runtime is shipped as plain media assets, not bundled into the
host: **`media/webview.js`** (the script) and **`media/webview.css`** (the
styles). They run in the webview, never in the extension host.
[teilweise #97] steht: `src/extension.js` is the only tsdown entry
(`tsdown.config.ts`) fehlt: a test asserting `media/webview.js`/`.css` stay out
of the host bundle

## Webview loading

`getWebviewHtml(webview)` returns a slim skeleton: a `<link>` to
`media/webview.css` and two `<script>` tags - `media/morphdom.js` (loaded
first, so its global is ready at first render) and `media/webview.js` - both
resolved via `webview.asWebviewUri`. [erfuellt] `wireWebview` sets
`localResourceRoots` to the `media/` folder so the webview may load them.
[teilweise #97] steht: `localResourceRoots` set to `media/`
(`src/views/wire.js`) fehlt: Test

The skeleton carries a Content-Security-Policy with a per-load nonce, in this
order: `default-src 'none'`; `img-src` from the webview origin plus
`https:`/`http:`/`data:` (remote images keep loading as before the CSP
existed); `style-src` from the webview origin plus `'unsafe-inline'` (Shiki
emits per-token colors as inline `style` attributes, and user markdown may too
with `html: true`, so a strict style policy would blank highlighted code);
`font-src` from the webview origin (the vendored `media/codicon.ttf`,
DECISIONS.md #43); and `script-src 'nonce-...'` matching the nonce on the
script tags. [teilweise #97] steht: `script-src` (nonce) and `style-src`
(`'unsafe-inline'`) asserted by test (`tests/webview.test.js`, "getWebviewHtml
embeds CSP, a script nonce and both webview asset URIs") fehlt: a test
asserting the `default-src`, `img-src` and `font-src` directives, their order
and a fresh nonce per `getWebviewHtml` call

Only the scripts are nonce-gated; the policy is deliberately not strict for
the rendered content (`'unsafe-inline'` styles, images from `https:`/`http:`/
`data:`), everything else - frames, media, connections - is blocked by
`default-src 'none'`. A strict CSP is out of scope (DECISIONS.md #22); the CSP
came with the asset extraction (#23). [teilweise #97] steht: nonce only on
the script tags (`src/views/html.js`), `style-src`/`img-src` left open
(DECISIONS.md #22, #23) fehlt: a test asserting that no `<link>`/`<style>` tag
carries the nonce

## Rendering pipeline

markdown-it (`html: true`, `linkify`) with these plugins, registered in this
order. [teilweise #97] steht: the options (`md` in `src/render/parser.js`;
`linkify` in `tests/render/index.test.js`, `html: true` only indirectly via
`tests/clipboard-diff/blocks.test.js`) fehlt: a test asserting the plugin order

- **markdown-it-front-matter** - YAML headers render as a property card
  (key/value grid for flat mappings, DECISIONS.md #8). [teilweise #97]
  steht: the `frontmatter` card (`src/render/frontmatter.js`,
  tests/render/index.test.js) fehlt: an assertion on the `fm-key`/`fm-val`
  markup. Raw block fallback otherwise. [teilweise #97] steht: the
  `fm-raw` branch (`src/render/frontmatter.js`) fehlt: Test
- **extraMarkerListsPlugin** - recognizes the configured non-CommonMark list
  markers (`markdownWorkbench.lists.extraMarkers`) as list items when
  `markdownWorkbench.lists.renderExtraMarkers` is on (DECISIONS.md #26).
  [erfuellt]
- **taskListPlugin** - list items starting with `[ ]`/`[x]` (an empty label
  included, DECISIONS.md #25) get the class `task` and `data-checked`; their
  content is wrapped in a `.task-row` span (checkbox + label). The `li`
  carries `data-line` (from `injectLineNumbers`), which the list toggle reads.
  [erfuellt]
- **tableCheckboxPlugin** - `[ ]`/`[x]` inside `td` cells become
  `input.cell-task`. A table row is one source line that can hold several
  checkboxes, so each input carries the row line (from `tr_open.map`) plus
  its occurrence index on that line. Code spans are skipped; `th` cells are
  excluded by contract. See DECISIONS.md #10/#11. [erfuellt]
- **headingAnchorsPlugin** - assigns slugged ids to headings, the basis for
  the in-document TOC and anchor navigation (DECISIONS.md #31). [erfuellt]
- **injectLineNumbers** - every block token with a map gets `data-line`.
  [erfuellt]
- **lineStartsPlugin** - records, per source line a `table` or `paragraph`
  rule consumes, where the line's content starts after its container prefix;
  active only when the caller passes `env.lineStarts`, rendering unchanged. The
  table editor reads it (DECISIONS.md #49). [erfuellt]
  (tests/tables/blocks.test.js) It is registered last; the order is part of the
  plugin-order gap above.
- **table renderer overrides** - every table sits in a `div.table-wrap`
  breakout wrapper (no `data-line`), every `th` carries a sort button
  (`button.mw-sort`, `data-col`) that the webview turns into a `sortTable`
  message (DECISIONS.md #49). [erfuellt] (tests/render/index.test.js)
- **custom fence renderer** - Shiki highlighting (async-initialized;
  plain-text fallback until ready), themes `dark-plus`/`light-plus` chosen
  by `activeColorTheme.kind`, re-render on theme switch; the theme's inline
  background is dropped, the preview paints code with `--code-bg`; also sets
  `data-line-end` on fences for intra-block scroll interpolation.
  [teilweise #97] steht: Shiki init, theme selection and `data-line-end`
  emission (`src/render/fence-highlight.js`) fehlt: Test for the theme-switch
  re-render trigger, the plain-text fallback markup and the re-render once the
  highlighter has loaded (`activePosts`)

## Toggle paths

- **Lists**: `applyToggle(document, lines, checked)` - validates each line
  against `CHECKBOX_RE`, flips the bracket character via one `WorkspaceEdit`
  (uniform target state for multi-select). [erfuellt]
  (tests/views/toggle.test.js; the single undo step and its gap: Overview)
- **Table cells**: `applyCellToggle(document, line, idx, checked)` - flips
  the nth bracket occurrence on the line. Code spans are blanked
  index-preservingly before counting so render-side and source-side
  occurrence indices stay aligned. [erfuellt]
- Webview side: a table-cell checkbox click reads `hasAttribute('checked')`
  (the live `.checked` has already flipped when the click handler runs); a
  list click reads the `li`'s `data-checked`. A cell with exactly one checkbox
  also toggles on a bare click inside the cell, gated like the list label (no
  toggle while text is selected or on a multi-click, DECISIONS.md #28), with
  `:has()`-based affordance styling. [teilweise #97] steht: the click
  paths and their gating (`media/webview.js`, tests/webview.test.js) fehlt: a
  test that fails when `.checked` replaces `hasAttribute('checked')`, and one
  for the `td:has(input.cell-task)` rule (`media/webview.css`)

## Scroll sync

Bidirectional and fractional. [erfuellt] The algorithms are taken 1:1 from the
built-in preview (`scrolling.ts` / `scroll-sync.ts`). [nicht verifiziert]
(microsoft/vscode - those sources are not part of this repo, so a 1:1 match
cannot be proven or disproven from here)

- Editor -> webview: `getVisibleLine` = top line + `character/(length+2)`.
  [erfuellt] The webview interpolates between `data-line` elements and
  proportionally inside multi-line fences via `data-line-end`.
  [teilweise #97] steht: `data-line-end` emission
  (`src/render/fence-highlight.js`, tested in `tests/render/index.test.js`)
  fehlt: a test for the webview side - the interpolation between `data-line`
  elements and the `endLine` branch in `scrollToSourceLine` and
  `sourceLineAtTop`
- Webview -> editor: `scrollEditorToLine` encodes the fraction as a
  character offset using `fraction * text.length` (deliberately asymmetric).
  [erfuellt] That asymmetry is what the built-in does. [nicht verifiziert]
  (microsoft/vscode - the built-in preview's sources are not part of this repo)
- Echo suppression: 200ms windows on both sides (`media/webview.js`,
  `src/views/wire.js`). [teilweise #97] steht: the windows in code fehlt: a
  test firing the editor visible-range handler and a webview scroll inside the
  window and asserting no echo message. Webview scroll
  handling is rAF-throttled. [teilweise #97] steht: the rAF-driven scroll
  listener (`media/webview.js`) fehlt: a test asserting exactly one rAF per
  scroll burst for the handler itself. The minimap updates inside that rAF
  even for suppressed (editor-driven) scrolls. [erfuellt]
- Throttle + delta gates (DECISIONS.md #35): the webview coalesces its `scrolled`
  posts to ~30Hz with a delta gate (`scrollPostDecision`) plus a trailing post for
  the rest position; the host skips `revealRange` / `scrollTo` when the line moved
  less than `SYNC_LINE_DELTA` from the last one pushed in that direction. Keeps a
  large source editor from lagging under ~60Hz two-way messaging.
  [teilweise #97] steht: `scrollPostDecision` and the delta gates on both
  sides fehlt: a test for the trailing post (`scrollTrailingTimer`) delivering
  the rest position
- Initial position: captured before opening (`pendingInitialScroll`),
  delivered as `scrollTo` after `ready` + first render. [teilweise #97]
  steht: `pendingInitialScroll` capture (`src/views/scroll-sync.js`) and
  delivery (`src/views/wire.js`) fehlt: Test. `lastKnownTopLine` feeds the
  reverse navigation (`showSource` reveals the stored line when the source is
  not already a live-synced visible editor; `reopenAsSource` does the same).
  [teilweise #97] steht: `showSource` focuses the
  source editor (tested) fehlt: a test asserting the stored line is actually
  revealed

## Minimap

An 88px rail containing a scaled `cloneNode` of the rendered content.
[teilweise #97] steht: clone construction (tested) fehlt: a test asserting
the 88px rail width. Plus a viewport slider (minimapSlider theme tokens).
[teilweise #97] steht: hover and active slider tokens plus rule order
(`tests/webview.test.js`, "a dragged minimap slider shows the active color,
even while hovered") fehlt: a test for the base token
`minimapSlider-background`. Three size modes mirroring
`editor.minimap.size`: [erfuellt]

- `proportional` - fixed scale `kx = railWidth / contentWidth`, pans when
  the scaled document exceeds the rail. [erfuellt]
- `fill` - the document maps linearly onto the full rail
  (`sy = railHeight / docHeight`); the slider stays aligned with the
  scrollbar thumb. [erfuellt]
- `fit` - `sy = min(kx, railHeight / docHeight)`: shrink to fit, never
  stretch. [erfuellt]

Pointerdown inside the slider rectangle grabs it (like the editor minimap):
the viewport moves relative to the grab point, no jump on grab. [erfuellt]
The hit test is geometric from the live mapping (`scrollY * mapSy + mapOffset`,
same math as the slider rendering) rather than CSS, so the
mouseover-hidden slider stays grabbable; the math works in all three size
modes. [teilweise #97] steht: the geometric hit-test formula (tested in
`fill` mode) fehlt: a dedicated test for a `showSlider: 'mouseover'`-hidden
slider staying grabbable and for the hit test with a non-zero pan offset.
Clicks on the rail outside the slider keep the centering jump
(pointer capture, held drag keeps centering). [teilweise #97] steht: two
separate outside-slider clicks (tested) fehlt: a test covering a `pointermove`
during a held centering drag. The rail spans the full viewport height; the
hint bar yields to it. [teilweise #97] steht: CSS rules (`media/webview.css`)
fehlt: Test. The clone is rebuilt only on
render, resize and config changes; per-scroll work is limited to
transform/slider updates (DECISIONS.md #16); a fold mirrors itself onto the
existing clone instead of rebuilding it (DECISIONS.md #47). [teilweise #97]
steht: the fold mirror (tested) fehlt: a test that a scroll frame does not
rebuild the clone. Visibility is decided
_before_ measuring the rail width (a `display: none` element reports
`clientWidth` 0 and would bake a scale of 0 into the clone).
[teilweise #97] steht: visibility toggled before the width read (`media/webview.js`)
fehlt: a dedicated regression test for this ordering

## Table of contents (scroll-spy + rail/FAB)

A visible in-document TOC, built on the heading anchors (DECISIONS.md #31/#32).
[erfuellt]

- **Scroll-spy** (`scrollSpy` in `media/webview.js`) is a self-contained,
  reusable base: it tracks the active heading (the last one scrolled past an
  activation line near the top, `activeHeadingIndex`) and its h1..h6 ancestor
  chain (`ancestorChain`), and notifies subscribers on change. [erfuellt] The
  rAF scroll pump (plus render/resize/fold) is the single scroll-driven
  `update()` trigger; an
  `IntersectionObserver` on every heading was removed as redundant and
  expensive on large documents (DECISIONS.md #35). [erfuellt] The follow-up
  breadcrumb + sticky-scroll stack (issue #44) subscribes to this same signal.
  [erfuellt] Heading tops are document coordinates,
  cached on render and refreshed on reflow only. [teilweise #97] steht:
  `collect()` (indirectly, via the render tests) fehlt: a test that
  `refreshMetrics` re-reads the tops on resize/reflow.
- **Rail** - a `position: fixed` panel with the heading hierarchy, on the side
  opposite the minimap (no own side config). [erfuellt] The active entry is
  highlighted, its section expanded (others collapsed), and kept in view; a
  click scrolls smoothly to the heading via the shared `navigateToHash`.
  [erfuellt] The rail's width is reserved as body padding so the centered
  content clears it. [erfuellt] Entries with children carry an expand/collapse twistie - a real
  codicon node (`<i class="codicon codicon-chevron-right toc-twistie">`,
  DECISIONS.md #43), not a CSS `::before`. [teilweise #97] steht: the
  twistie's CSS contract (`tests/webview.test.js`) fehlt: a test asserting the
  rendered node (`<i class="codicon codicon-chevron-right toc-twistie">`). The
  manual open/close state is sticky against the scroll-spy automatic
  (DECISIONS.md #35). [erfuellt] A manual expand/collapse animates the
  sublist (`grid-template-rows` 0fr/1fr, armed by `armTocAnimation` through the
  `body.toc-animating` flag); the scroll-driven expand/collapse stays instant,
  and `prefers-reduced-motion` turns it off (DECISIONS.md #43). [erfuellt]
  (tests/webview.test.js: "the TOC sublist expand/collapse is animated only on
  a manual toggle (#44 P5)", "a manual TOC toggle arms the animation flag; the
  scroll-driven auto path does not (#44 P5)")
- **FAB/overlay** - when the viewport is too narrow for the rail beside the
  content, a floating button opens the same TOC in an overlay (backdrop click /
  Escape to close). [erfuellt]
- **Rail vs. FAB** is content-relative (`railFits`: viewport >= content
  max-width + rail reserve + the opposite-side rail/gutter), live via a
  `ResizeObserver`; [teilweise #97] steht: the `railFits` formula (tested)
  fehlt: a test asserting the `ResizeObserver` re-evaluates live, beyond its
  fold-pending skip case. `markdownWorkbench.toc.mode` (`auto`/`rail`/`fab`)
  overrides it, `markdownWorkbench.toc.enabled` turns it off. [erfuellt]

## Breadcrumb + sticky-scroll stack

Two fixed bars pinned to the top of the content region (DECISIONS.md #33), both
consumers of the same `scrollSpy` signal as the TOC - no scroll-spy change.
[erfuellt]

- **Breadcrumb** (`#breadcrumb`) - a single-line trail of the active heading's
  chain. Each segment scrolls to its heading (smooth, via `navigateToHash`) and
  opens a sibling picker (`#breadcrumb-dropdown`): the headings at the same level
  under the same parent, computed by the pure `siblingHeadings(levels, index)`.
  A constant-height bar (`BREADCRUMB_HEIGHT_PX`, published once as
  `--breadcrumb-height`, never measured - DECISIONS.md #36);
  `body.has-breadcrumb` reserves that height as top padding so content clears
  it. [erfuellt]
- **Sticky-scroll stack** (`#sticky-scroll`) - the same chain rendered as pinned
  heading rows directly below the breadcrumb, rebuilt from the active chain
  whenever it changed (an overlay, not `position: sticky` on the content
  headings), capped at `MAX_STICKY_ROWS` (5) rows. Overlays
  content without reserving space; a row click scrolls to its heading. Hidden
  above the first heading (empty chain). [erfuellt]
- **Anchor clearance** - each heading carries its own `scroll-margin-top`, its
  bars height (breadcrumb + its ancestor-chain depth in sticky rows,
  `publishHeadingScrollMargins`, written per render/config, never on scroll);
  `navigateToHash` subtracts the target heading's own margin (the global
  `topBarsOffset` as fallback) so anchor jumps land below the bars. The same
  per-heading values feed the scroll-spy's activation line (`scrollSpy.setInsets`),
  so the heading marked active after a jump is the one that lands below the bars,
  not the one above it. `--toc-scroll-margin` (introduced in #32) is a constant
  written once (`publishTopBarVars`, the maximum stack height plus a gap) and only
  a coarse fallback. [erfuellt]
- **Scroll cost** - the per-active-change work is kept minimal: `updateTopBars`
  rebuilds only when the chain/heading-set/config actually changed, heights are
  computed from the fixed bar geometry (`topBarsHeight`), never measured
  (DECISIONS.md #36), the CSS vars are written only on change, the bars
  reconcile their `<a>` nodes in place, and `applyTocActive` toggles only the
  changed links (O(path), not O(headings)). [teilweise #97] steht: no stack
  measurement or margin-var rewrite on a depth-changing drag (tested) fehlt: a
  test for the unchanged-chain rebuild skip, the in-place `<a>` reconcile and
  `applyTocActive` touching only the changed links
- **Layout** - the bars fill the content region only, clearing the minimap and
  TOC rail via the same per-side reserves as the body padding. [erfuellt] z-index
  top to
  bottom: breadcrumb dropdown (8) > TOC overlay (7) > FAB/backdrop (6) >
  minimap/TOC rail (5) > top bars (4) > sticky table header (2) > content.
  [teilweise #97] steht: z-index rules (`media/webview.css`) fehlt: Test
- **Sticky table header** - a table's header docks directly below the current
  bars: `th` sits at `top: var(--sticky-head-top)`, a variable written on the
  document's `thead`s (never on `:root`) and only when the stack depth changes
  (`setStickyHeadInset`, DECISIONS.md #36/#38). A wide, horizontally scrolling
  table gets an emulated header instead, moved by `translateY` from cached
  geometry (`updateStickyHeads`, `stickyHeadOffset`, DECISIONS.md #39).
  [erfuellt] (tests/webview.test.js: "the sticky table header docks FLUSH under
  the current stack, per-thead not on :root (#44 perf)", "stickyHeadOffset:
  explicit geometries", "a wide (scrolling) table switches off native th sticky
  so the emulated pin is the only one")
- **Config** - `markdownWorkbench.breadcrumb.enabled` and
  `markdownWorkbench.stickyScroll.enabled` (both default `true`, independent),
  on the `config` message with the same defensive defaults as the minimap/TOC.
  [erfuellt]

## Click focus

A mouse click never focuses a control: one delegated `document` `mousedown`
listener calls `preventDefault` on every click target (`CLICK_FOCUS_TARGETS`:
links, inputs, buttons and the nav controls), so the webview does not scroll a
focused element into view and a TOC twistie click does not drift the active
heading; the click itself still navigates or toggles, keyboard focus is
untouched (DECISIONS.md #40). [erfuellt] (tests/webview.test.js: "one central
mousedown handler suppresses the click focus on every control (#44)")

## Content section folding

VS-Code-style folding of a heading's section, reachable from a chevron on the
heading and from the matching sticky-scroll row - one engine, one state
(DECISIONS.md #44/#45, performance #47). [erfuellt]

- **State** - `foldedIds` (heading ids) is the single source of truth, preserved
  across re-renders. A heading's section is every following block up to the next
  heading of the same or a higher level; `computeFoldHidden` walks the blocks with
  a level stack so a folded ancestor also hides a folded descendant's blocks, and
  `isFoldable` skips an empty section. Both pure and unit-tested. [erfuellt]
- **Click path writes only** - `applyFolds` toggles `.mw-fold-hidden` on the blocks
  whose visibility actually changed, flips the one chevron that changed, and derives
  the scroll-spy's folded-away mask from the fold set (`hiddenBlocks` /
  `isInHiddenBlock`, an ancestor walk). No layout is read while folding, so the
  browser lays the document out once, asynchronously, instead of inside the handler.
  [erfuellt]
- **Batched re-measure** - folding changes the rendered height, so the cached line
  tops, heading tops and table tops are re-read once per toggle burst, deferred
  rather than on a fixed timer (`refreshAfterFold`, ordered read-first - then the
  small derived writes - with the minimap mirror scheduled last into its own slot
  via `scheduleMinimapFoldMirror`). Whoever needs the tops before that pass runs
  calls `flushFoldMetrics` to run it synchronously first (DECISIONS.md #47,
  Round 2). [erfuellt] The deferral goes into the browser's idle time
  (`runWhenIdle`, `requestIdleCallback` with a `FOLD_REFRESH_DEADLINE_MS` = 250ms
  starvation-guard deadline, a `setTimeout` fallback where unavailable).
  [teilweise #97] steht: the `setTimeout` fallback (tested; the test mock has
  no `requestIdleCallback`) fehlt: a test for the `requestIdleCallback` branch
  and its deadline. The `ResizeObserver` skips its own re-measure while that pass
  is pending, so the work is not done twice per toggle. [erfuellt]
- **Minimap** - the clone is _mirrored_, not rebuilt: its top-level children are
  index-parallel to `#content`'s, so a fold is one class write per block.
  [erfuellt] A full rebuild is reserved for the rail appearing/disappearing or a
  clone that no longer matches the document. [teilweise #97] steht: the mirror
  path (tested) fehlt: a test for the rebuild fallback
- **Navigation** - a folded-away heading is `display: none` (its rect is 0), so
  `navigateToHash` maps such an id to the collapsed section header it sits in
  (`visibleFoldAnchor`). [erfuellt]
- **Stable side reserves** - the scrollbar gutter is reserved permanently and the
  minimap stays shown while anything is folded, so folding a page down to less than
  a viewport never drops a reserve and slides the centered content sideways.
  [erfuellt]

## Webview scrollbar

The webview uses a custom scrollbar (editor `scrollbarSlider` tokens, no
arrow buttons) so the thumb track spans the full height and aligns with the
minimap rail. Two traps documented in DECISIONS.md #15: pseudo-element
rules need `::-webkit-scrollbar` itself styled (custom mode), and VS Code
injects `scrollbar-color` into every webview which disables webkit scrollbar
styling entirely until reset to `auto`. [teilweise #97] steht: CSS rules
and the DECISIONS.md #15 write-up fehlt: a stylesheet-contract test
(`ruleBody` in `tests/webview.test.js`) for `scrollbar-color: auto` and the
`::-webkit-scrollbar-button` rule; real scrollbar rendering is not asserted in
the Node test environment

## Configuration

`markdownWorkbench.preview.maxWidth` (`github` = 980px default / `narrow` =
72ch), `markdownWorkbench.preview.textSelection` /
`markdownWorkbench.preview.taskBatchSelect` /
`markdownWorkbench.preview.taskRowTextCursor`, `markdownWorkbench.minimap.*`
(`enabled`, `size`, `showSlider`, `side`), `markdownWorkbench.toc.*`
(`enabled`, `mode`) and the top-bar toggles
`markdownWorkbench.breadcrumb.enabled` / `markdownWorkbench.stickyScroll.enabled`
(both default `true`) and `markdownWorkbench.tables.previewSort` (as
`tables{previewSort}`, default `true`). The extension resolves values
with explicit fallbacks and pushes them as a `config` message - on `ready`
_before_ the first render (so the initial scroll lands in the final layout) and
live on every configuration change. [erfuellt] The webview merges incoming
minimap and TOC config over defaults so undefined values can never disable the
rail (regression 0.21.1). [erfuellt] The TOC has no side setting: it derives
its side from `minimap.side` (opposite side) in the webview. [erfuellt]

The editor-side settings - `markdownWorkbench.indent.continuationStopRadius`,
`markdownWorkbench.editing.*` (join commands and their fallback commands,
`joinSpaces`), `markdownWorkbench.lists.*` (`extraMarkersEnabled`,
`extraMarkers`, `markerCycle`, `renderExtraMarkers`) and
`markdownWorkbench.tables.*` (`enabled`, `enterBehavior`, `tabSelectsCell`,
`tabAddsRow`, `arrowNavigation`, `autoAlign`, `maxAlignedWidth`,
`ambiguousWidth`, `cellLineBreak`, `createFromPipe`, `continueCheckboxes`,
`suggestNumericAlign`, `pasteAsTable`, `validate`) - do not travel over the
`config` message. `src/editing/` and `src/tables/` read them via
`vscode.workspace.getConfiguration` when a command, key, paste, diagnostics
refresh or code-action request runs; the two preview-side `lists.*` keys named below are the
exception. [erfuellt] The
`tables.*` values fall back to their defaults when unset, mistyped or out of
range (`tablesConfig`; tests `every setting falls back to its default when
unset`, `undefined, wrong types and unknown enum values fall back to the
default`). [erfuellt] The arrow keybindings hang on
`config.markdownWorkbench.tables.enabled`/`arrowNavigation` and the context key
`markdownWorkbench.inTable` in their `when` clauses. [teilweise #97] steht:
`when` clauses in `package.json` fehlt: Test The two
`*.enabled` join switches gate the keybindings through `when` clauses in
`package.json`; the preview-side `lists.renderExtraMarkers` /
`lists.extraMarkers` reach the renderer through the render env
(`configuredRenderEnv` in `src/views/config.js`). [teilweise #97] steht: `when`
clauses (`package.json`) and `configuredRenderEnv` (`src/views/config.js`) fehlt: Test

## Editing features (src/editing/)

Editor-side authoring commands, modeled on Learn Markdown / Markdown All in
One: Enter list continuation (numbered increment, empty-item termination),
code-fence auto-close (unindented snippet - VS Code auto-indents
continuation lines), fence language IntelliSense (Shiki ids + verified
aliases), Tab/Shift+Tab adaptive nesting, wrap toggles (bold/italic/code,
wrap/unwrap/extend-unwrap), web link insertion, table insert
(snippet with tab stops), distribute/consolidate table reflow (alignment
colons preserved), numeric-aware selection sort, authoring quick-pick menu.
[erfuellt] File link insertion works as well. [teilweise #97] steht: `insertFileLink`
(`src/editing/wrap-links.js`) fehlt: Test for the insert path (only the
no-workspace-files branch is tested)

### Tables (src/tables/)

Table editing sees the table the preview renders (DECISIONS.md #49). [erfuellt]

- **Model** - which lines are table rows, and where each row's content starts,
  comes from a block parse with the preview's own markdown-it instance
  (`src/render/parser.js`, read by `blocks.js`, cached per document version) -
  except a typed header, a line starting with `|` without a delimiter row yet
  (`pipeHeaderAt`, for E4 and K2), which the preview does not render as a table;
  rows are split like markdown-it 15 (`\|` stays content, a `|` in a code span
  splits); list indentation and `>` prefixes are kept byte for byte; nothing
  inside code, HTML blocks or the frontmatter. Checked against the preview
  instance on a corpus and on seeded random documents (tests `the model finds
the same tables and cells as the preview (REQ-003)`, `random documents yield
the preview tables (REQ-003, seeds 1-3)`). [erfuellt]
- **Alignment** - display width per grapheme (`Intl.Segmenter`,
  `get-east-asian-width`, emoji 2, combining 0, ambiguous per
  `tables.ambiguousWidth`); only whitespace and delimiter dashes change (seeded
  random test `aligning changes only spaces and delimiter dashes (REQ-011,
seed 20260928)`; Unicode whitespace at the row edge, trimmed like the preview,
  is dropped); edits are minimal per line (`lineEdits`), an aligned table yields
  none; above `tables.maxAlignedWidth` the automatic alignment consolidates.
  [erfuellt] Unicode whitespace at an inner cell edge becomes spaces.
  [teilweise #97] steht: `src/tables/row.js` (`contentStart`/`contentEnd`)
  fehlt: Test through the formatter
- **Keys** - Enter (E1-E10), Shift+Enter (`cellLineBreak`), Tab/Shift+Tab
  (T1-T8) and `|` + Tab starting a table (K2, `createFromPipe`) run as branches
  in front of the list handling in `src/editing/`; a new row carries `[ ]` in
  checkbox columns (K5, `continueCheckboxes`),
  each as one edit (one undo step; test `E1+E8: Enter and alignment are one
undo step (REQ-020, REQ-021)`); Up/Down (T9) run only where the context key
  `markdownWorkbench.inTable` is set, which `arrows.js` writes on selection
  changes only when it flips (test `the context key is set only when it
changes (REQ-038)`); after an edit that would cost a block parse, only once
  typing pauses (test `after an edit the key waits for a typing pause before it
parses (R2-4)`).
  [erfuellt] That Up/Down hang on the context key is the keybindings' `when`
  clause. [teilweise #97] steht: the clause in `package.json` fehlt: Test (the
  same gap as in § "Configuration"). Behavior in the real VS Code (keybinding precedence,
  context key) [nicht verifiziert] (microsoft/vscode - the headless tests run
  against a mock of its API).
- **Commands** - sort by column (editor and the preview's `sortTable`,
  stale document versions dropped, refused while `tables.previewSort` is off),
  insert/delete/move column, all in the
  Alt+M menu. [erfuellt]
- **Providers** - CSV/TSV paste as a table (`DocumentPasteEditProvider`,
  yields to the plain-text paste), diagnostics for cells beyond the header
  with the quick fix "Add column to header", and the "Right-align column" code
  action for number columns. [erfuellt]

## Clipboard diff

Compares the clipboard (the **candidate**) with a **baseline** in the native
diff editor, baseline left, candidate right (DECISIONS.md #48). [erfuellt]
(tests/clipboard-diff/compare.test.js) Evidence: the mock suites in
`tests/clipboard-diff/` and the integration suites in `tests/integration/suite/`
plus the normal-window guard (`tests/integration/guard/`, started by
`tests/integration/run.js`), in a real VS Code at the minimum and the stable
version, run locally by `build.ps1 -Task Integration` (not in CI). On Windows,
before VS Code starts, the runner measures the real path of the downloaded
`workbench.html` and stops with length, limit (260), path and remedy where
VS Code could not load it; a failed cleanup is a warning and does not hide the
run's result. [erfuellt] (tests/integration/run.test.js)

- **Commands** (`index.js`). "Compare with Clipboard" and "Compare with
  Earlier Clipboard" (a QuickPick of the session's clipboard texts, newest
  first, compared by the same baseline logic). [erfuellt]
  (tests/clipboard-diff/compare.test.js) Tab-bar buttons of a clipboard diff:
  "Apply Candidate" and the style switch between the raw clipboard and the
  text aligned to the baseline's style (`alignCandidateStyle` /
  `showRawCandidate`, context `markdownWorkbench.candidateStyleAligned`); the
  switch asks before it discards edits of the candidate and keeps the file
  text around an anchored section. [erfuellt] (tests/clipboard-diff/index.test.js)
  "Swap Diff Sides" has its own button (see Swap).
- **Scheme.** Candidate and selection pages live under
  `markdown-workbench-clipboard:/<id>/<name> (<Role>)<ext>`, served by a
  `FileSystemProvider` (`CandidateStore`) from a `Map` in memory; `writeFile`
  never touches the disk, `stat` reports a growing mtime. [erfuellt]
  (tests/clipboard-diff/store.test.js)
- **Immediate save** (`saving.js`). Every change of a page is saved at once
  (`onDidChangeTextDocument`, own scheme only), so VS Code's backup tracker
  never keeps an unsaved page long enough to write it under
  `Backups/<ws>/<scheme>/`. [erfuellt] (tests/integration/guard/scenario.js in
  the test host and in a normal window, both versions; mutation run:
  tests/integration/guard-mutation.js) The focused page
  (either side of a diff) is saved with `workbench.action.files.saveWithoutFormatting`, so the
  user's save actions (trim trailing whitespace, final newline, format on
  save) do not run while typing. [erfuellt] (saving.int.js) Any other page is
  saved with `document.save()`: its save actions may change that page, and
  the edits made while such a save runs - until did-save or its end, however
  long - are never written into the file. [erfuellt] (saving.int.js,
  tests/clipboard-diff/saving.test.js) A save VS Code starts itself (Ctrl+S on
  a page) marks its edits until did-save, at most `SAVE_WINDOW_MS` (3 s), so a
  save that fails without did-save does not keep the page unsaved. [erfuellt]
  (saving.test.js) What a
  selection page holds beyond the written text at did-save came after the
  write and goes into the file (`sync.js` `reconcileSaved`). [erfuellt]
  (tests/clipboard-diff/saving.test.js) A page focused during such a save that
  still differs from its file region in more than trailing blanks and final
  line breaks afterwards
  gets the sync warning, without page text. [erfuellt]
  (tests/clipboard-diff/sync.test.js) An edit that lands inside a save is
  saved right after it, also when `document.save()` resolves false for it; a
  failed save warns without the page content. [erfuellt]
  (tests/clipboard-diff/saving.test.js)
- **Lifecycle** (`session.js`). A diff's pages are released once no tab shows
  its candidate or its selection page and it is no longer opening
  (`tabGroups.onDidChangeTabs`, checked after the tab model settles, so a swap
  keeps them), and on `deactivate`; stored pages no diff owns (a
  "Save As" copy inside the scheme) go with them. Pages restored from an
  earlier window are closed on activation. [erfuellt]
  (tests/clipboard-diff/session.test.js, tests/integration/suite/guard.int.js)
  The clipboard text reaches no log, message or persisted state. [erfuellt]
  (tests/clipboard-diff/session.test.js, tests/integration/suite/guard.int.js)
- **Baseline shapes** (`sync.js`). A selection (or the hull of several) becomes a
  `(Selection)` page mirroring its range in the file both ways: a page edit
  writes through into the range, a file edit inside the range updates the
  page. Without a selection the baseline is the live file: the whole file,
  or, after an anchor hit, the file against the file with the anchored lines
  replaced, opened with that span selected. [erfuellt]
  (tests/clipboard-diff/compare.test.js, tests/integration/suite/hints.int.js)
  File edits outside the anchored lines follow into the candidate's copy of
  the file (`sync.js` `mirrorAround`) until that copy was edited around the
  section; from then on they no longer do. [erfuellt]
  (tests/clipboard-diff/session.test.js, tests/clipboard-diff/sync.test.js)
  The candidate takes the baseline's language and line endings. [erfuellt]
  (tests/clipboard-diff/compare.test.js)
- **Diff call and titles.** `vscode.diff(baseline, candidate)` without a
  title; VS Code names the tab from the page names
  (`notes.md ↔ notes (Candidate).md`) and renames it after a swap. [erfuellt]
  (tests/integration/suite/diff.int.js)
- **Swap** (`index.js`). `workbench.action.compareEditor.swapSides` through
  `executeCommand` for any active text diff; the result is checked on the tab,
  a skipped or failed swap is reported. [erfuellt] After a swap, other clean
  tabs of the group showing the same two sides are closed, so one tab is left
  (a Git change reopened after a swap opens in its first order); a dirty one
  stays and is reported. [erfuellt]
  (tests/clipboard-diff/session.test.js, tests/integration/suite/swap.int.js)
  The tab-bar button has
  `when: isInDiffEditor && !activeCompareEditorCanSwap`: it shows only where VS
  Code's own is hidden, which needs a writable left side (a Git diff as
  opened). [erfuellt] (tests/clipboard-diff/index.test.js,
  tests/integration/suite/swap.int.js)
- **Apply.** The tracked region (character offsets, moved by
  `contentChanges`, `region.js`) is replaced by one `WorkspaceEdit`, after the
  placeholder fill and the Markdown check; an edit inside the region since the
  diff opened makes Apply ask first. [erfuellt]
  (tests/clipboard-diff/apply.test.js, tests/clipboard-diff/region.test.js)
  Where the candidate was edited
  outside its clipboard part too (an anchored diff), the whole candidate
  replaces the whole file; the diff changes only after a successful Apply.
  [erfuellt] (tests/clipboard-diff/apply.test.js) One undo reverts it. [erfuellt]
  (tests/integration/suite/diff.int.js) Per-hunk apply is VS Code's revert
  arrow, which copies left to right: it drops a candidate hunk before a swap
  and takes it into the file after one. [erfuellt]
  (tests/integration/suite/diff.int.js)
- **Anchor** (`anchor.js`). A heading-led clipboard takes the same-named
  section; otherwise a line-hash index finds the first/last line and scores
  the overlap at no more than 2 × `MAX_ANCHOR_CANDIDATES` places (up to
  `MAX_ANCHOR_CANDIDATES` from each line); unsure or ambiguous hits go to a
  QuickPick with "Whole file". Placeholder lines never anchor. [erfuellt]
  (tests/clipboard-diff/anchor.test.js, tests/integration/suite/hints.int.js)
- **Style** (`style.js`, emphasis masking in `emphasis.js`). Baseline profile (bullet, emphasis, strong, table
  padding via `reflowTable` of the table model), applied by swapping markers in place outside
  verbatim blocks, verified by comparing the parsed structure before and
  after. [erfuellt] (tests/clipboard-diff/style.test.js)
- **Unwrap and placeholders** (`unwrap.js`). Outer fence and edge chat lines
  by named pattern lists; placeholder lines by `PLACEHOLDER_PATTERNS`, filled
  on Apply from the baseline between the neighbouring lines, unclear ones
  asked about. [erfuellt] (tests/clipboard-diff/unwrap.test.js)
- **Check** (`check.js`). Reset checkboxes (`CHECKBOX_RE`), lost reference and
  footnote definitions (markdown-it's `env.references`), front matter, removed
  headings with `#anchor` links. Diagnostics on the candidate (quick fixes for
  checkbox states and placeholders) use the file's own links (cached per file
  version); Apply adds the workspace's links behind
  `markdownWorkbench.clipboardDiff.checkWorkspaceAnchors` (resolved relative
  to their file, files over 1 MB (`MAX_SCAN_BYTES`) or unreadable skipped).
  One question at Apply, never a block. [erfuellt]
  (tests/clipboard-diff/check.test.js, diagnostics.test.js, apply.test.js;
  tests/integration/suite/hints.int.js)
- **History** (`history.js`). Ring buffer of the clipboard texts the
  extension read, memory only, `MAX_HISTORY_ENTRIES` / `MAX_ENTRY_BYTES`.
  [erfuellt] (tests/clipboard-diff/history.test.js)
- **Limits.** "Save As" cannot be locked. [nicht verifiziert]
  (microsoft/vscode - the extension API offers no lock besides `isReadonly`)
  Its default target is the candidate URI, and cancelling it writes nothing.
  [erfuellt] (tests/integration/suite/saveas.int.js, both versions) Only a
  local target the user picks via "Show Local" writes to disk, the candidate
  there and nothing else, and not before the target is accepted. [erfuellt]
  (tests/integration/suite/saveas.int.js, both versions; the case takes the
  same local Save As through the simplified dialog) A failed
  in-memory save lets VS Code back the page up.
  [nicht verifiziert] (microsoft/vscode - the backup tracker)

## Message protocol (host <-> webview)

| Direction       | Type         | Payload                                                                                                                                                                                                                 |
| --------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| host -> webview | `config`     | `documentUri`, `maxWidth`, `minimap{enabled,size,showSlider,side}`, `toc{enabled,mode}`, `breadcrumb{enabled}`, `stickyScroll{enabled}`, `tables{previewSort}`, `textSelection`, `taskBatchSelect`, `taskRowTextCursor` |
| host -> webview | `render`     | `html`, document `version`                                                                                                                                                                                              |
| host -> webview | `scrollTo`   | fractional `line`                                                                                                                                                                                                       |
| webview -> host | `ready`      | -                                                                                                                                                                                                                       |
| webview -> host | `toggle`     | `lines[]`, `checked`                                                                                                                                                                                                    |
| webview -> host | `toggleCell` | `line`, `idx`, `checked`                                                                                                                                                                                                |
| webview -> host | `scrolled`   | fractional `line`                                                                                                                                                                                                       |
| webview -> host | `sortTable`  | table start `line`, `col`, `dir` (`asc`/`desc`), document `version`                                                                                                                                                     |

[erfuellt] The webview sends `ready` once it has loaded. [teilweise #97] steht:
the host side of the handshake (tests/activation.test.js) fehlt: a test that
`media/webview.js` posts `ready`
