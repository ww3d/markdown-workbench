# Architecture

Marker evidence is the latest state audit (`audit/ist-stand-2026-09-27T2058Z.md`); this repo has
no dedicated architecture tests.

## Overview

The extension renders markdown as an interactive workbench view: checkboxes
(in lists and table cells) are clickable and every toggle is mirrored
surgically into the source file - a single-character `[ ]` <-> `[x]` edit,
one undo step. [erfuellt]

Two entry modes wrap the same machinery, mirroring the built-in markdown
preview exactly. [nicht verifiziert] (microsoft/vscode - the built-in preview's
behavior lives there; the shared `wireWebview` path is covered under "Both
modes call" below)

1. **WebviewPanel preview** (`showPreview` into the active group,
   `showPreviewToSide` next to it). One panel per document, tracked in a
   `previews` map. [erfuellt] The panel closes with its source document.
   [teilweise backlog] steht: the `onDidCloseTextDocument` listener
   (`src/views/wire.js`) fehlt: a test firing it
2. **CustomTextEditorProvider** (`markdownWorkbench.editor`) replacing the
   text editor in place (`Open as Workbench` / `Reopen as source file` use
   `reopenActiveEditorWith` for an in-place tab swap). [teilweise backlog]
   steht: `reopenActiveEditorWith` wiring (src/extension.js) fehlt: Test

Both modes call `wireWebview(document, panel, closeWithDocument)`, which owns
the full message protocol. [erfuellt]

**Restore after a restart (DECISIONS.md #34).** The preview panel registers a
`WebviewPanelSerializer` for `markdownWorkbench.preview` (with
`onWebviewPanel:markdownWorkbench.preview` in `activationEvents`). The webview
persists its document URI via `setState` (the URI rides the `config` message);
`deserializeWebviewPanel` reopens that document and re-wires the panel through
the same `attachPreviewPanel` path as a fresh open. The custom editor mode needs
no serializer - VS Code re-resolves registered custom editors on restart.
[erfuellt]

## Module layout

The extension-host code is split by responsibility; all modules are
bundled into `dist/extension.cjs` by tsdown (`src/extension.js` is the entry).
[erfuellt]

- **`src/extension.js`** - activation entry point. `activate`/`deactivate`,
  command registration and the WebviewPanel preview orchestration (the
  `previews` map, `openPreviewPanel`, the showSource / toggle / save-undo-redo
  bridges). [erfuellt]
- **`src/render/`** - the markdown-it instance and its plugins, one file per
  subject: `parser.js` (the one `md` instance, plugin registration order, the
  line-start recording the table editor reads - no `vscode` import), `index.js`
  (adds the Shiki fence renderer, re-exports `md`, `activePosts`), `task-lists.js`, `table-checkboxes.js`, `extra-markers.js`,
  `heading-anchors.js`, `frontmatter.js` (the property-card renderer) and
  `fence-highlight.js` (the Shiki fence renderer - `initHighlighter`,
  `shikiTheme`). `activePosts`, the set of re-render callbacks the highlighter
  triggers once it finishes loading, lives in `fence-highlight.js` and is
  re-exported from `index.js`. [erfuellt]
- **`src/views/`** - the shared view machinery, one file per subject:
  `index.js` (public exports), `identity.js` (`extensionUri`, tab-title
  prefix, `workbenchIconPath`), `config.js` (`configuredViewConfig`),
  `scroll-sync.js` (`getVisibleLine` / `scrollEditorToLine` / capture /
  reveal), `toggles.js` (`applyToggle` / `applyCellToggle`) and `html.js`
  (`getWebviewHtml`). `wire.js` ties them together (`wireWebview`, the
  custom-editor provider `WorkbenchEditorProvider`). [erfuellt]
- **`src/editing/`** - editor-side authoring commands (see below), one file per
  subject (`enter.js`, `tab.js`, `join.js`, ...); `index.js` registers them.
  [erfuellt]
- **`src/tables/`** - markdown table editing (DECISIONS.md #48): the pure table
  model (`row.js`, `blocks.js`, `detect.js`, `width.js`, `format.js`,
  `grid-ops.js`, `sort.js`, `csv.js` - no `vscode` import) and the editor side
  (`enter.js`, `tab.js`, `arrows.js`, `commands.js`, `paste.js`,
  `diagnostics.js`, `config.js`, `apply.js`); `index.js` registers them and
  hands the Enter/Tab branches to `src/editing/`. [erfuellt]

The webview runtime is shipped as plain media assets, not bundled into the
host: **`media/webview.js`** (the script) and **`media/webview.css`** (the
styles). They run in the webview, never in the extension host.
[teilweise backlog] steht: `src/extension.js` is the only tsdown entry
(`tsdown.config.ts`) fehlt: a test asserting `media/webview.js`/`.css` stay out
of the host bundle

## Webview loading

`getWebviewHtml(webview)` returns a slim skeleton: a `<link>` to
`media/webview.css` and two `<script>` tags - `media/morphdom.js` (loaded
first, so its global is ready at first render) and `media/webview.js` - both
resolved via `webview.asWebviewUri`. [erfuellt] `wireWebview` sets
`localResourceRoots` to the `media/` folder so the webview may load them.
[teilweise backlog] steht: `localResourceRoots` set to `media/`
(`src/views/wire.js`) fehlt: Test

The skeleton carries a Content-Security-Policy with a per-load nonce, in this
order: `default-src 'none'`; `img-src` from the webview origin plus
`https:`/`http:`/`data:` (remote images keep loading as before the CSP
existed); `style-src` from the webview origin plus `'unsafe-inline'` (Shiki
emits per-token colors as inline `style` attributes, and user markdown may too
with `html: true`, so a strict style policy would blank highlighted code);
`font-src` from the webview origin (the vendored `media/codicon.ttf`,
DECISIONS.md #43); and `script-src 'nonce-...'` matching the nonce on the
script tags. [teilweise backlog] steht: `script-src` (nonce) and `style-src`
(`'unsafe-inline'`) asserted by test fehlt: a test asserting the `default-src`,
`img-src` and `font-src` directives

Only the scripts are nonce-gated; the rendered content itself is not
CSP-restricted (DECISIONS.md #22). [teilweise backlog] steht: nonce only on
the script tags, content left unrestricted (DECISIONS.md #22, predates the
nonce but consistent with the current code) fehlt: Test

## Rendering pipeline

markdown-it (`html: true`, `linkify`) with these plugins, registered in this
order. [teilweise backlog] steht: options and registration order (`md` in
`src/render/parser.js`) fehlt: a test asserting the options and the plugin order

- **markdown-it-front-matter** - YAML headers render as a property card
  (key/value grid for flat mappings). [erfuellt] Raw block fallback otherwise.
  [teilweise backlog] steht: the `fm-raw` branch (`src/render/frontmatter.js`) fehlt: Test
- **extraMarkerListsPlugin** - recognizes the configured non-CommonMark list
  markers (`markdownWorkbench.lists.extraMarkers`) as list items when
  `markdownWorkbench.lists.renderExtraMarkers` is on (DECISIONS.md #26).
  [erfuellt]
- **taskListPlugin** - list items starting with `[ ]`/`[x]` become
  `.task-row` elements (checkbox + content) carrying `data-line`. [erfuellt]
- **tableCheckboxPlugin** - `[ ]`/`[x]` inside `td` cells become
  `input.cell-task`. A table row is one source line that can hold several
  checkboxes, so each input carries the row line (from `tr_open.map`) plus
  its occurrence index on that line. Code spans are skipped; `th` cells are
  excluded by contract. See DECISIONS.md #10/#11. [erfuellt]
- **headingAnchorsPlugin** - assigns slugged ids to headings, the basis for
  the in-document TOC and anchor navigation (DECISIONS.md #31). [erfuellt]
- **injectLineNumbers** - every block token with a map gets `data-line`.
  [erfuellt]
- **custom fence renderer** - Shiki highlighting (async-initialized;
  plain-text fallback until ready), themes `dark-plus`/`light-plus` chosen
  by `activeColorTheme.kind`, re-render on theme switch; also sets
  `data-line-end` on fences for intra-block scroll interpolation.
  [teilweise backlog] steht: Shiki init, theme selection and `data-line-end` emission
  (`src/render/fence-highlight.js`) fehlt: Test for the theme-switch re-render trigger

## Toggle paths

- **Lists**: `applyToggle(document, lines, checked)` - validates each line
  against `CHECKBOX_RE`, flips the bracket character via one `WorkspaceEdit`
  (uniform target state for multi-select, single undo step). [erfuellt]
- **Table cells**: `applyCellToggle(document, line, idx, checked)` - flips
  the nth bracket occurrence on the line. Code spans are blanked
  index-preservingly before counting so render-side and source-side
  occurrence indices stay aligned. [erfuellt]
- Webview side: checkbox clicks read `hasAttribute('checked')` (the live
  `.checked` has already flipped when the click handler runs). A cell with
  exactly one checkbox toggles on any click inside the cell (`:has()`-based
  affordance styling). [erfuellt]

## Scroll sync

Bidirectional and fractional. [erfuellt] The algorithms are taken 1:1 from the
built-in preview (`scrolling.ts` / `scroll-sync.ts`). [nicht verifiziert]
(microsoft/vscode - those sources are not part of this repo, so a 1:1 match
cannot be proven or disproven from here)

- Editor -> webview: `getVisibleLine` = top line + `character/(length+2)`.
  [erfuellt] The webview interpolates between `data-line` elements and
  proportionally inside multi-line fences via `data-line-end`.
  [teilweise backlog] steht: `scrollToSourceLine`'s `endLine` branch (`media/webview.js`)
  fehlt: Test
- Webview -> editor: `scrollEditorToLine` encodes the fraction as a
  character offset using `fraction * text.length` (deliberately asymmetric).
  [erfuellt] That asymmetry is what the built-in does. [nicht verifiziert]
  (microsoft/vscode - the built-in preview's sources are not part of this repo)
- Echo suppression: 200ms windows on both sides. [erfuellt] Webview scroll
  handling is rAF-throttled. [teilweise backlog] steht: the rAF-driven scroll
  listener (`media/webview.js`) fehlt: a test asserting exactly one rAF per
  scroll burst for the handler itself. The minimap updates inside that rAF
  even for suppressed (editor-driven) scrolls. [erfuellt]
- Throttle + delta gates (DECISIONS.md #35): the webview coalesces its `scrolled`
  posts to ~30Hz with a delta gate (`scrollPostDecision`) plus a trailing post for
  the rest position; the host skips `revealRange` / `scrollTo` when the line moved
  less than `SYNC_LINE_DELTA` from the last one pushed in that direction. Keeps a
  large source editor from lagging under ~60Hz two-way messaging. [erfuellt]
- Initial position: captured before opening (`pendingInitialScroll`),
  delivered as `scrollTo` after `ready` + first render. [teilweise backlog]
  steht: `pendingInitialScroll` capture and delivery (`src/views/scroll-sync.js`) fehlt:
  Test. `lastKnownTopLine` feeds the reverse navigation (`showSource` reveals
  the stored line). [teilweise backlog] steht: `showSource` focuses the
  source editor (tested) fehlt: a test asserting the stored line is actually
  revealed

## Minimap

An 88px rail containing a scaled `cloneNode` of the rendered content.
[teilweise backlog] steht: clone construction (tested) fehlt: a test asserting
the 88px rail width. Plus a viewport slider (minimapSlider theme tokens).
[teilweise backlog] steht: slider theme tokens (`media/webview.css`) fehlt:
Test. Three size modes mirroring
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
modes. [teilweise backlog] steht: the geometric hit-test formula (tested)
fehlt: a dedicated test for a `showSlider: 'mouseover'`-hidden slider staying
grabbable. Clicks on the rail outside the slider keep the centering jump
(pointer capture, held drag keeps centering). [teilweise backlog] steht: two
separate outside-slider clicks (tested) fehlt: a test covering a `pointermove`
during a held centering drag. The rail spans the full viewport height; the
hint bar yields to it. [teilweise backlog] steht: CSS rules (`media/webview.css`)
fehlt: Test. The clone is rebuilt only on
render, resize and config changes; per-scroll work is limited to
transform/slider updates, and a fold mirrors itself onto the existing clone
instead of rebuilding it (DECISIONS.md #47). [erfuellt] Visibility is decided
_before_ measuring the rail width (a `display: none` element reports
`clientWidth` 0 and would bake a scale of 0 into the clone).
[teilweise backlog] steht: visibility toggled before the width read (`media/webview.js`)
fehlt: a dedicated regression test for this ordering

## Table of contents (scroll-spy + rail/FAB)

A visible in-document TOC, built on the heading anchors (DECISIONS.md #31/#32).
[erfuellt]

- **Scroll-spy** (`scrollSpy` in `media/webview.js`) is a self-contained,
  reusable base: it tracks the active heading (the last one scrolled past an
  activation line near the top, `activeHeadingIndex`) and its h1..h6 ancestor
  chain (`ancestorChain`), and notifies subscribers on change. [erfuellt] The
  rAF scroll pump (plus render/resize) is the single `update()` trigger; an
  `IntersectionObserver` on every heading was removed as redundant and
  expensive on large documents (DECISIONS.md #35). [erfuellt] The follow-up
  breadcrumb + sticky-scroll stack (#44) subscribes to this same signal.
  [erfuellt] Heading tops are document coordinates,
  cached on render and refreshed on reflow only. [teilweise backlog] steht:
  `collect()`/`refreshMetrics` (`media/webview.js`) fehlt: Test.
- **Rail** - a `position: fixed` panel with the heading hierarchy, on the side
  opposite the minimap (no own side config). [erfuellt] The active entry is
  highlighted, its section expanded (others collapsed), and kept in view; a
  click scrolls smoothly to the heading via the shared `navigateToHash`.
  [erfuellt] The rail's width is reserved as body padding so the centered
  content clears it. [erfuellt] Entries with children carry an expand/collapse twistie - a real
  codicon node (`<i class="codicon codicon-chevron-right toc-twistie">`,
  DECISIONS.md #43), not a CSS `::before`; the manual open/close state is
  sticky against the scroll-spy automatic (DECISIONS.md #35). [erfuellt]
- **FAB/overlay** - when the viewport is too narrow for the rail beside the
  content, a floating button opens the same TOC in an overlay (backdrop click /
  Escape to close). [erfuellt]
- **Rail vs. FAB** is content-relative (`railFits`: viewport >= content
  max-width + rail reserve + the opposite-side rail/gutter), live via a
  `ResizeObserver`; [teilweise backlog] steht: the `railFits` formula (tested)
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
  A constant-height bar; `body.has-breadcrumb` reserves its measured height
  (`--breadcrumb-height`) as top padding so content clears it. [erfuellt]
- **Sticky-scroll stack** (`#sticky-scroll`) - the same chain rendered as pinned
  heading rows directly below the breadcrumb, rebuilt from the active chain on
  each emit (an overlay, not `position: sticky` on the content headings). Overlays
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
  measured only when the sticky row count changes (no per-frame forced layout),
  the CSS vars are written only on change, the bars reconcile their `<a>` nodes
  in place, and `applyTocActive` toggles only the changed links (O(path), not
  O(headings)). [teilweise backlog] steht: no stack measurement or margin-var
  rewrite on a depth-changing drag (tested) fehlt: a test for the unchanged-chain rebuild skip, the in-place `<a>`
  reconcile and `applyTocActive` touching only the changed links
- **Layout** - the bars fill the content region only, clearing the minimap and
  TOC rail via the same per-side reserves as the body padding. [erfuellt] z-index
  top to
  bottom: breadcrumb dropdown (8) > TOC overlay (7) > FAB/backdrop (6) >
  minimap/TOC rail (5) > top bars (4) > sticky table header (2) > content.
  [teilweise backlog] steht: z-index rules (`media/webview.css`) fehlt: Test
- **Config** - `markdownWorkbench.breadcrumb.enabled` and
  `markdownWorkbench.stickyScroll.enabled` (both default `true`, independent),
  on the `config` message with the same defensive defaults as the minimap/TOC.
  [erfuellt]

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
  [teilweise backlog] steht: the `setTimeout` fallback (tested; the test mock has
  no `requestIdleCallback`) fehlt: a test for the `requestIdleCallback` branch
  and its deadline. The `ResizeObserver` skips its own re-measure while that pass
  is pending, so the work is not done twice per toggle. [erfuellt]
- **Minimap** - the clone is _mirrored_, not rebuilt: its top-level children are
  index-parallel to `#content`'s, so a fold is one class write per block. A full
  rebuild is reserved for the rail appearing/disappearing or a clone that no longer
  matches the document. [erfuellt]
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
styling entirely until reset to `auto`. [teilweise backlog] steht: CSS rules
and the DECISIONS.md #15 write-up fehlt: Test (browser scrollbar rendering is
not asserted in the Node test environment)

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
`vscode.workspace.getConfiguration` at command time. [erfuellt] The
`tables.*` values fall back to their defaults when unset, mistyped or out of
range (`tablesConfig`; test `every setting falls back to its default when
unset`). [erfuellt] The arrow keybindings hang on
`config.markdownWorkbench.tables.enabled`/`arrowNavigation` and the context key
`markdownWorkbench.inTable` in their `when` clauses. [teilweise backlog] steht:
`when` clauses in `package.json` fehlt: Test The two
`*.enabled` join switches gate the keybindings through `when` clauses in
`package.json`; the preview-side `lists.renderExtraMarkers` /
`lists.extraMarkers` reach the renderer through the render env
(`configuredRenderEnv` in `src/views/config.js`). [teilweise backlog] steht: `when`
clauses (`package.json`) and `configuredRenderEnv` (`src/views/config.js`) fehlt: Test

## Editing features (src/editing/)

Editor-side authoring commands, modeled on Learn Markdown / Markdown All in
One: Enter list continuation (numbered increment, empty-item termination),
code-fence auto-close (unindented snippet - VS Code auto-indents
continuation lines), fence language IntelliSense (Shiki ids + verified
aliases), Tab/Shift+Tab adaptive nesting, wrap toggles (bold/italic/code,
wrap/unwrap/extend-unwrap), web/file link insertion, table insert
(snippet with tab stops), distribute/consolidate table reflow (alignment
colons preserved), numeric-aware selection sort, authoring quick-pick menu.
[erfuellt]

### Tables (src/tables/)

Table editing sees the table the preview renders (DECISIONS.md #48). [erfuellt]

- **Model** - which lines are table rows, and where each row's content starts,
  comes from a block parse with the preview's own markdown-it instance
  (`src/render/parser.js`, read by `blocks.js`, cached per document version);
  rows are split like markdown-it 15 (`\|` stays content, a `|` in a code span
  splits); list indentation and `>` prefixes are kept byte for byte; nothing
  inside code, HTML blocks or the frontmatter. Checked against the preview
  instance on a corpus and on seeded random documents (tests `the model finds
the same tables and cells as the preview`, `random documents yield the
preview tables`). [erfuellt]
- **Alignment** - display width per grapheme (`Intl.Segmenter`,
  `get-east-asian-width`, emoji 2, combining 0, ambiguous per
  `tables.ambiguousWidth`); only spaces and delimiter dashes change (seeded
  random test `aligning changes only spaces and delimiter dashes`); edits are
  minimal per line (`lineEdits`), an aligned table yields none; above
  `tables.maxAlignedWidth` the automatic alignment consolidates. [erfuellt]
- **Keys** - Enter (E1-E10), Shift+Enter (`cellLineBreak`), Tab/Shift+Tab
  (T1-T8) run as branches in front of the list handling in `src/editing/`,
  each as one edit (one undo step; test `E1+E8: Enter and alignment are one
undo step`); Up/Down (T9) run only where the context key
  `markdownWorkbench.inTable` is set, which `arrows.js` writes on selection
  changes only when it flips (test `the context key is set only when it
changes`). [erfuellt] Behavior in the real VS Code (keybinding precedence,
  context key) [nicht verifiziert] (microsoft/vscode - the headless tests run
  against a mock of its API).
- **Commands** - sort by column (editor and the preview's `sortTable`,
  stale document versions dropped), insert/delete/move column, all in the
  Alt+M menu. [erfuellt]
- **Providers** - CSV/TSV paste as a table (`DocumentPasteEditProvider`,
  yields to the plain-text paste), diagnostics for cells beyond the header
  with the quick fix "Add column to header", and the "Right-align column" code
  action for number columns. [erfuellt]

## Message protocol (host <-> webview)

| Direction       | Type         | Payload                                                                                                                                                                                   |
| --------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| host -> webview | `config`     | `documentUri`, `maxWidth`, `minimap{enabled,size,showSlider,side}`, `toc{enabled,mode}`, `breadcrumb{enabled}`, `stickyScroll{enabled}`, `tables{previewSort}`, preview readability flags |
| host -> webview | `render`     | `html`, document `version`                                                                                                                                                                |
| host -> webview | `scrollTo`   | fractional `line`                                                                                                                                                                         |
| webview -> host | `ready`      | -                                                                                                                                                                                         |
| webview -> host | `toggle`     | `lines[]`, `checked`                                                                                                                                                                      |
| webview -> host | `toggleCell` | `line`, `idx`, `checked`                                                                                                                                                                  |
| webview -> host | `scrolled`   | fractional `line`                                                                                                                                                                         |
| webview -> host | `sortTable`  | table start `line`, `col`, `dir` (`asc`/`desc`), document `version`                                                                                                                       |

[erfuellt]
