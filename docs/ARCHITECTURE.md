# Architecture

Marker evidence is the test named at the marker, otherwise the latest state audit
(`audit/ist-stand-2026-09-29T2304Z.md`); this repo has no dedicated architecture tests.

## Overview

The extension renders markdown as an interactive workbench view: checkboxes
(in lists and table cells) are clickable and every toggle is mirrored
surgically into the source file - a single-character `[ ]` <-> `[x]` edit.
[erfuellt] (tests/views/toggle.test.ts, tests/webview/tasks/listeners.test.ts) Each
toggle is one undo step: one `WorkspaceEdit` per toggle (`src/views/toggles.ts`,
DECISIONS.md #1). [erfuellt] (tests/views/toggle.test.ts: "a multi-line toggle is one
applyEdit call, so one undo step")

Two entry modes wrap the same machinery, mirroring the built-in markdown
preview's entry points (DECISIONS.md #2; task rendering deviates on purpose,
DECISIONS.md #25). [nicht verifiziert] (microsoft/vscode - the built-in preview's
behavior lives there; the shared `wireWebview` path is covered under "Both
modes call" below)

1. **WebviewPanel preview** (`showPreview` into the active group,
   `showPreviewToSide` next to it). [erfuellt] (tests/activation.test.ts:
   "`${id} opens the panel in the ${column} view column`", run for both commands)
   One panel per document, tracked in a `previews` map. [erfuellt]
   (tests/activation.test.ts: "a second showPreview for the same document creates
   no second panel") The panel closes with its source document. [erfuellt]
   (tests/views/wire.test.ts: "the side preview closes with its source document,
   not with another one")
2. **CustomTextEditorProvider** (`markdownWorkbench.editor`) replacing the
   text editor in place [erfuellt] (`Open as Workbench` swaps the active
   editor via `reopenActiveEditorWith` and falls back to `vscode.openWith` for
   a non-active resource; `Reopen as source file` swaps back with
   `reopenActiveEditorWith 'default'`; DECISIONS.md #2). [erfuellt]
   (tests/activation.test.ts: "open without a uri swaps the active editor in
   place", "open on the active resource swaps the active editor in place", "open on
   another resource opens it with the custom editor instead", "reopenAsSource swaps
   the active custom editor back to the default editor")

Both modes call `wireWebview(document, panel, closeWithDocument)`, which owns
the full message protocol. [erfuellt]

**Restore after a restart (DECISIONS.md #34).** The preview panel registers a
`WebviewPanelSerializer` for `markdownWorkbench.preview` (with
`onWebviewPanel:markdownWorkbench.preview` in `activationEvents`). The webview
persists its document URI via `setState` (the URI rides the `config` message);
`deserializeWebviewPanel` reopens that document and re-wires the panel through
the same `attachPreviewPanel` path as a fresh open. [erfuellt] (serializer
registration, `setState` round trip and every `deserializeWebviewPanel` edge in
tests/activation.test.ts; the `activationEvents` entry in tests/package-assets.test.ts:
"the preview panel viewType is an activation event, so a restored panel wakes the
extension") The webview also persists its last render; § "Webview loading" holds
that part. The custom editor mode needs no serializer - VS Code
re-resolves registered custom editors on restart. [nicht verifiziert]
(microsoft/vscode - the custom-editor restore behavior lives there)

## Module layout

The extension-host code is split by responsibility; every module under `src/`
outside `src/webview/` is bundled into `dist/extension.cjs` by tsdown
(`src/extension.ts` is the entry). [erfuellt]

- **`src/extension.ts`** - activation entry point. `activate`/`deactivate`,
  command registration and the WebviewPanel preview orchestration (the
  `previews` map, `openPreviewPanel`, the showSource / toggle / save-undo-redo
  bridges). [erfuellt]
- **`src/render/`** - the markdown-it instance and its plugins, one file per
  subject: `parser.ts` (the one `md` instance, plugin registration order, the
  line-start recording the table editor reads - no `vscode` import), `index.ts`
  (adds the Shiki fence renderer, re-exports `md`, `activePosts`,
  `SHIKI_LANGS`, `initHighlighter`, `shikiTheme`), `task-lists.ts`,
  `table-checkboxes.ts`, `extra-markers.ts`,
  `heading-anchors.ts`, `frontmatter.ts` (the property-card renderer) and
  `fence-highlight.ts` (the Shiki fence renderer - `initHighlighter`,
  `shikiTheme`). `activePosts`, the set of re-render callbacks the highlighter
  triggers once it finishes loading, lives in `fence-highlight.ts` and is
  re-exported from `index.ts`. [erfuellt]
- **`src/views/`** - the shared view machinery, one file per subject:
  `index.ts` (public exports), `identity.ts` (`extensionUri`, tab-title
  prefix, `workbenchIconPath`), `config.ts` (`configuredViewConfig`,
  `configuredRenderEnv`), `scroll-sync.ts` (`getVisibleLine` /
  `scrollEditorToLine` / capture / reveal), `toggles.ts` (`applyToggle` /
  `applyCellToggle`), `html.ts` (`getWebviewHtml`) and `restore.ts` (`renderKey`,
  `createRestoreGate` - the host half of the restored stand, § "Webview loading").
  `wire.ts` ties them together (`wireWebview`, the custom-editor provider
  `WorkbenchEditorProvider`; it hands `sortTable` messages to `src/tables/`).
  [erfuellt] (tests/views/)
- **`src/editing/`** - editor-side authoring commands (see below), one file per
  subject (`enter.ts`, `tab.ts`, `join.ts`, ...); `index.ts` registers them.
  [erfuellt]
- **`src/tables/`** - markdown table editing (DECISIONS.md #49): the pure table
  model (`row.ts`, `blocks.ts`, `detect.ts`, `width.ts`, `format.ts`,
  `grid-ops.ts`, `sort.ts`, `csv.ts` - no `vscode` import) and the editor side
  (`enter.ts`, `tab.ts`, `arrows.ts`, `commands.ts`, `paste.ts`,
  `diagnostics.ts`, `config.ts`, `apply.ts`); `index.ts` registers them and
  hands the Enter/Tab branches to `src/editing/`. [erfuellt]
  (tests/tables/pure-modules.test.ts: the "... loads without vscode" test of each
  pure module; tests/tables/tab.test.ts;
  tests/editing/enter.test.ts: "Enter in a table row runs the table branch, not the
  default newline")
- **`src/markdown/syntax.ts`** - Markdown source primitives shared across
  modules and free of `vscode`: `CHECKBOX_RE` (the task-line pattern the
  toggle paths and the clipboard-diff check use) and `checkboxBoxPos` (the
  column of the box character in a match); `src/views/` re-exports it.
  [erfuellt] (tests/markdown/syntax.test.ts) The one table reflow is
  `formatGrid` over `toGrid` in `src/tables/format.ts`, on the table model: the
  editor's Distribute/Consolidate (`reflowTableCommand` in
  `src/editing/table-reflow.ts`) call the two per table, the clipboard diff's
  style alignment calls `reflowTable` there, the line-based form of the same
  two. [erfuellt] (tests/tables/format.test.ts,
  tests/editing/table-reflow.test.ts, tests/clipboard-diff/style.test.ts) The
  commands pass `tables.ambiguousWidth` (as `tablesConfig().ambiguousWide`).
  [erfuellt] (tests/editing/table-reflow.test.ts: "the distribute command follows
  tables.ambiguousWidth: wide counts an ambiguous char twice")
- **`src/clipboard-diff/`** - the clipboard diff (section "Clipboard diff"
  below, DECISIONS.md #48). Pure modules without `vscode` - `anchor.ts`,
  `style.ts`, `emphasis.ts`, `unwrap.ts`, `check.ts`, `history.ts`,
  `region.ts`, `lines.ts`, `blocks.ts` - and the binding to VS Code -
  `store.ts`, `session.ts`, `saving.ts`, `sync.ts`, `compare.ts`, `apply.ts`,
  `diagnostics.ts`, `index.ts`. Tests mirror the
  folder in `tests/clipboard-diff/`; the pure modules run there without the
  vscode mock. [erfuellt] (tests/clipboard-diff/)
- **`src/webview/`** - the webview runtime (DECISIONS.md #50, D1), run in the
  webview, never in the extension host. On its top level `main.ts` (the entry: wires
  the modules, restores a persisted stand, posts `ready`), `protocol.ts` (the message
  types, § "Message protocol") and `host.ts` (the `acquireVsCodeApi` handle); below
  them one folder per subject - `anchors/`, `folding/`, `minimap/`, `page/`,
  `render/`, `restore/`, `scroll-spy/`, `scroll-sync/`, `tables/`, `tasks/`, `toc/`,
  `top-bars/`. A module with styles imports its own stylesheet next to it. The tests
  mirror the folders in `tests/webview/` and import the modules directly, without a
  build. [erfuellt] (tests/webview/)

`src/render/parser.ts` builds the markdown-it instance without `vscode`, so it
also serves those pure modules and the table model outside the extension host.
[erfuellt] (tests/clipboard-diff/blocks.test.ts loads it without the mock)

tsdown builds two entries (`tsdown.config.ts`), both into `dist/`: the extension host
as one CJS bundle (`dist/extension.cjs`, platform `node`, `vscode` external) and the
webview as one minified browser IIFE (`dist/webview.js`, morphdom inlined, target
`chrome132` - the Chromium of the minimum VS Code 1.100) plus the stylesheets its
modules import, merged in import order into `dist/webview.css`. [erfuellt]
(tests/package-assets.test.ts: "the vsix carries the webview bundle and no sources";
tests/webview-css-target.test.ts: "the webview entry targets Chrome 132, the Electron
of the minimum VS Code"; `scripts/webview-smoke.ts` runs the built bundle) The host
bundle carries no webview code. [erfuellt] (tests/package-assets.test.ts: "the
extension-host bundle carries no webview code") The build gate fails when a bundle
outgrows its size limit (`scripts/size-gate.ts`: gzip of `dist/webview.js` +
`dist/webview.css` and of `dist/extension.cjs`, uncompressed bytes of each webview
file). [erfuellt] (tests/size-gate.test.ts)

## Webview loading

`getWebviewHtml(webview)` returns a slim skeleton with exactly one stylesheet,
`dist/webview.css`, and one script, `dist/webview.js` (morphdom inside), both
resolved via `webview.asWebviewUri` from the bundle folder (`BUNDLE_DIR` in
`src/views/identity.ts`). [erfuellt] (tests/views/html.test.ts: "getWebviewHtml
embeds CSP, a script nonce and both webview asset URIs", "the bundle folder the
skeleton loads from is the layout dist folder") `wireWebview` sets
`localResourceRoots` to exactly `dist/` and `media/` (the codicon font, the
icons). [erfuellt] (tests/views/wire.test.ts: "a wired webview may load exactly from
dist/ and media/ (localResourceRoots)") The stylesheet reaches `media/codicon.ttf`
through a `url()` relative to `dist/`. [erfuellt] (tests/package-assets.test.ts:
"every url() in dist/webview.css points to a file in the vsix")

The skeleton carries a Content-Security-Policy with a per-load nonce, in this
order: `default-src 'none'`; `img-src` from the webview origin plus
`https:`/`http:`/`data:` (remote images keep loading as before the CSP
existed); `style-src` from the webview origin plus `'unsafe-inline'` (Shiki
emits per-token colors as inline `style` attributes, and user markdown may too
with `html: true`, so a strict style policy would blank highlighted code);
`font-src` from the webview origin (the vendored `media/codicon.ttf`,
DECISIONS.md #43); and `script-src 'nonce-...'` matching the nonce on the
script tag. [erfuellt] (tests/views/html.test.ts: "the CSP is exactly the documented
policy, directive by directive (docs/DECISIONS.md #22)", "every skeleton gets a fresh
nonce, and only the script carries it")

Only the script is nonce-gated; the policy is deliberately not strict for
the rendered content (`'unsafe-inline'` styles, images from `https:`/`http:`/
`data:`), everything else - frames, media, connections - is blocked by
`default-src 'none'`. A strict CSP is out of scope (DECISIONS.md #22); the CSP
came with the asset extraction (#23). [erfuellt] (tests/views/html.test.ts: "every
skeleton gets a fresh nonce, and only the script carries it")

**Instant stand after a restart (DECISIONS.md #50).** After a render the webview
persists the host's HTML, its `render.key`, the scroll position and `BUILD_ID` (the
package version, set by tsdown) via `setState` - once the view has been quiet for
`STATE_SAVE_QUIET_MS` (250 ms), never once per scroll frame. [erfuellt]
(tests/webview/restore/state.test.ts: "after a render the webview persists html, key
and build id once quiet (REQ-041)", "a render and scroll burst writes the state once
per quiet phase, never in the frame") HTML longer than `MAX_RESTORE_HTML_CHARS`
(512 KiB, `src/webview/restore/state.ts`) is not persisted; the state then holds only
the document URI and the build id. [erfuellt] (tests/webview/restore/state.test.ts:
"html just below the bound is persisted", "html just above the bound is not
persisted: build id and document URI only (REQ-042)") On a restore the webview shows
a stand of its own build through the render path before the host's first render, at
its scroll position, and names it in `ready` (`buildId`, `key`); a stand of another
build is discarded. [erfuellt] (tests/webview/restore/restore.test.ts: "a persisted
stand of this build is shown before the first host render, and ready names it
(REQ-043, REQ-070)", "the restored scroll position is re-established without a
scrolled report", "a stand of another build is discarded: nothing shown, ready
without build id and key (REQ-073)") The host compares both with its own build id and
the key of its current render inputs (`renderKey` in `src/views/restore.ts`: render
settings, theme kind, highlighter state, text): on a match it does not render and
posts only `version`, otherwise it renders as before. [erfuellt]
(tests/views/restore.test.ts: "restore hit: same build and key -> no render, the
version goes out alone" and the four "restore miss: ..." tests) A stand that matches
the highlighted render while the highlighter still loads is kept, at most
`HIGHLIGHTER_WAIT_MS` (5 s). [erfuellt] (tests/views/restore.test.ts: "a highlighted
stand waits for the loading highlighter and is kept once it is ready (0 renders)", "a
highlighter that never settles renders the waiting stand after the wait bound") A real
VS Code restart shows the stand without a host render. [teilweise #92] steht: the
mechanism above, tested against the mocks fehlt: the P8 measurement in a real VS Code
(time until the content is visible, host renders = 0)

## Rendering pipeline

markdown-it (`html: true`, `linkify`) with these plugins, registered in this
order. [erfuellt] (tests/render/index.test.ts: "the render plugins sit in the core
rule chain in their fixed order"; the options `md` in `src/render/parser.ts`,
`linkify` in tests/render/index.test.ts, `html: true` indirectly via
tests/clipboard-diff/blocks.test.ts)

- **markdown-it-front-matter** - YAML headers render as a property card
  (key/value grid for flat mappings, DECISIONS.md #8). [erfuellt]
  (tests/render/index.test.ts: "flat frontmatter renders one key cell and one value
  cell per line, escaped") Raw block fallback otherwise. [erfuellt]
  (tests/render/index.test.ts: "frontmatter that is not flat key/value falls back to
  an escaped monospace block")
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
  (tests/tables/blocks.test.ts) It is registered last; the order is part of the
  plugin-order gap above.
- **table renderer overrides** - every table sits in a `div.table-wrap`
  breakout wrapper (no `data-line`), every `th` carries a sort button
  (`button.mw-sort`, `data-col`) that the webview turns into a `sortTable`
  message (DECISIONS.md #49). [erfuellt] (tests/render/index.test.ts)
- **custom fence renderer** - Shiki highlighting (async-initialized;
  plain-text fallback until ready), themes `dark-plus`/`light-plus` chosen
  by `activeColorTheme.kind`, re-render on theme switch; the theme's inline
  background is dropped, the preview paints code with `--code-bg`; also sets
  `data-line-end` on fences for intra-block scroll interpolation.
  [erfuellt] (tests/views/wire.test.ts: "a color theme change re-renders the view
  (fence colors follow the theme)", "a highlighter start re-renders every open view,
  until its panel is disposed"; tests/render/index.test.ts: "before shiki is ready a
  fence renders as escaped plain code with its language class", "the highlighter
  start re-renders every open view once")

## Toggle paths

- **Lists**: `applyToggle(document, lines, checked)` - validates each line
  against `CHECKBOX_RE`, flips the bracket character via one `WorkspaceEdit`
  (uniform target state for multi-select). [erfuellt]
  (tests/views/toggle.test.ts; the single undo step: Overview)
- **Table cells**: `applyCellToggle(document, line, idx, checked)` - flips
  the nth bracket occurrence on the line. Code spans are blanked
  index-preservingly before counting so render-side and source-side
  occurrence indices stay aligned. [erfuellt]
- Webview side: a table-cell checkbox click reads `hasAttribute('checked')`
  (the live `.checked` has already flipped when the click handler runs); a
  list click reads the `li`'s `data-checked`. A cell with exactly one checkbox
  also toggles on a bare click inside the cell, gated like the list label (no
  toggle while text is selected or on a multi-click, DECISIONS.md #28), with
  `:has()`-based affordance styling (`src/webview/tasks/`). [erfuellt]
  (tests/webview/tasks/listeners.test.ts: "a cell toggle reads the rendered checked
  attribute, not the flipped live state"; tests/webview/tables/sticky-head.test.ts:
  "a cell holding exactly one checkbox shows the pointer hand as a whole")

## Scroll sync

Bidirectional and fractional. [erfuellt] The algorithms are taken 1:1 from the
built-in preview (`scrolling.ts` / `scroll-sync.ts`). [nicht verifiziert]
(microsoft/vscode - those sources are not part of this repo, so a 1:1 match
cannot be proven or disproven from here)

- Editor -> webview: `getVisibleLine` = top line + `character/(length+2)`.
  [erfuellt] The webview interpolates between `data-line` elements and
  proportionally inside multi-line fences via `data-line-end`. [erfuellt]
  (`data-line-end` emission in tests/render/index.test.ts; the webview side,
  `scrollToSourceLine` and `sourceLineAtTop` in `src/webview/scroll-sync/`:
  tests/webview/scroll-sync/report.test.ts: "the reported line interpolates between
  two [data-line] elements", "inside a multi-line block the reported line runs
  through its data-line-end"; tests/webview/scroll-sync/follow.test.ts: "a line
  between two [data-line] elements scrolls proportionally between them", "a line
  inside a multi-line block scrolls proportionally through it (data-line-end)")
- Webview -> editor: `scrollEditorToLine` encodes the fraction as a
  character offset using `fraction * text.length` (deliberately asymmetric).
  [erfuellt] That asymmetry is what the built-in does. [nicht verifiziert]
  (microsoft/vscode - the built-in preview's sources are not part of this repo)
- Echo suppression: 200ms windows on both sides (`src/webview/scroll-sync/`,
  `src/views/wire.ts`). [erfuellt] (tests/activation.test.ts: "webview scrolled
  message reveals the line in visible editors and suppresses the echo";
  tests/webview/scroll-sync/report.test.ts: "scroll events within 200 ms of a host
  scrollTo are not reported back (echo)") Webview scroll handling is rAF-throttled.
  [erfuellt] (tests/webview/scroll-sync/report.test.ts: "a burst of scroll events
  schedules one animation frame") The minimap updates inside that rAF
  even for suppressed (editor-driven) scrolls. [erfuellt]
- Throttle + delta gates (DECISIONS.md #35): the webview coalesces its `scrolled`
  posts to ~30Hz with a delta gate (`scrollPostDecision`) plus a trailing post for
  the rest position; the host skips `revealRange` / `scrollTo` when the line moved
  less than `SYNC_LINE_DELTA` from the last one pushed in that direction. Keeps a
  large source editor from lagging under ~60Hz two-way messaging.
  [erfuellt] (`scrollPostDecision` and the delta gates on both sides;
  tests/webview/scroll-sync/report.test.ts: "a deferred scroll post delivers the rest
  position once the window passes")
- Initial position: captured before opening (`pendingInitialScroll`),
  delivered as `scrollTo` after `ready` + first render. [erfuellt]
  (tests/views/wire.test.ts: "the editor position captured at open is delivered once,
  after config and render") `lastKnownTopLine` feeds the
  reverse navigation (`showSource` reveals the stored line when the source is
  not already a live-synced visible editor; `reopenAsSource` does the same).
  [erfuellt] (tests/activation.test.ts: "showSource shows the last line the preview
  reported")

## Minimap

An 88px rail containing a scaled `cloneNode` of the rendered content
(`src/webview/minimap/`). [erfuellt] (tests/webview/minimap/minimap.test.ts: "the
minimap rail is 88px wide and spans the full height; its slider has the base token")
Plus a viewport slider (minimapSlider theme tokens). [erfuellt] (same test for the
base token; "a dragged minimap slider shows the active color, even while hovered" for
hover and active) Three size modes mirroring
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
modes. [erfuellt] (tests/webview/minimap/drag.test.ts: "a slider hidden until hover
(showSlider mouseover) is still grabbed, not jumped over", "the slider hit test
follows the pan offset of the proportional mode") Clicks on the rail outside the
slider keep the centering jump (pointer capture, held drag keeps centering).
[erfuellt] (tests/webview/minimap/drag.test.ts: "moving the pointer while a rail
(centering) drag is held keeps centering") The rail spans the full viewport height;
the hint bar yields to it. [erfuellt] (tests/webview/minimap/minimap.test.ts: "the
minimap rail is 88px wide and spans the full height; its slider has the base token",
"the hint bar yields to the rail on its side") The clone is rebuilt only on
render, resize and config changes; per-scroll work is limited to
transform/slider updates (DECISIONS.md #16); a fold mirrors itself onto the
existing clone instead of rebuilding it (DECISIONS.md #47). [erfuellt]
(tests/webview/minimap/minimap.test.ts: "a scroll frame moves the slider but never
re-clones the document") Visibility is decided
_before_ measuring the rail width (a `display: none` element reports
`clientWidth` 0 and would bake a scale of 0 into the clone).
[erfuellt] (tests/webview/minimap/minimap.test.ts: "the rail is made visible before
its width is measured for the clone scale")

## Table of contents (scroll-spy + rail/FAB)

A visible in-document TOC, built on the heading anchors (DECISIONS.md #31/#32).
[erfuellt]

- **Scroll-spy** (`scrollSpy` in `src/webview/scroll-spy/spy.ts`) is a self-contained,
  reusable base: it tracks the active heading (the last one scrolled past an
  activation line near the top, `activeHeadingIndex`) and its h1..h6 ancestor
  chain (`ancestorChain`), and notifies subscribers on change. [erfuellt] The
  rAF scroll pump (plus render/resize/fold) is the single scroll-driven
  `update()` trigger; an
  `IntersectionObserver` on every heading was removed as redundant and
  expensive on large documents (DECISIONS.md #35). [erfuellt] The follow-up
  breadcrumb + sticky-scroll stack (issue #44) subscribes to this same signal.
  [erfuellt] Heading tops are document coordinates,
  cached on render and refreshed on reflow only. [erfuellt]
  (tests/webview/page/viewport.test.ts: "a window resize and a content-box change
  re-read the heading tops")
- **Rail** - a `position: fixed` panel with the heading hierarchy, on the side
  opposite the minimap (no own side config). [erfuellt] The active entry is
  highlighted, its section expanded (others collapsed), and kept in view; a
  click scrolls smoothly to the heading via the shared `navigateToHash`.
  [erfuellt] The rail's width is reserved as body padding so the centered
  content clears it. [erfuellt] Entries with children carry an expand/collapse twistie - a real
  codicon node (`<i class="codicon codicon-chevron-right toc-twistie">`,
  DECISIONS.md #43), not a CSS `::before`. [erfuellt] (tests/webview/toc/tree.test.ts:
  "a parent TOC entry carries a real twistie node, a leaf none") The
  manual open/close state is sticky against the scroll-spy automatic
  (DECISIONS.md #35). [erfuellt] A manual expand/collapse animates the
  sublist (`grid-template-rows` 0fr/1fr, armed by `armTocAnimation` through the
  `body.toc-animating` flag); the scroll-driven expand/collapse stays instant,
  and `prefers-reduced-motion` turns it off (DECISIONS.md #43). [erfuellt]
  (tests/webview/toc/tree.test.ts: "the TOC sublist expand/collapse is animated only
  on a manual toggle (#44 P5)"; tests/webview/toc/toggle.test.ts: "a manual TOC toggle
  arms the animation flag; the scroll-driven auto path does not (#44 P5)")
- **FAB/overlay** - when the viewport is too narrow for the rail beside the
  content, a floating button opens the same TOC in an overlay (backdrop click /
  Escape to close). [erfuellt]
- **Rail vs. FAB** is content-relative (`railFits`: viewport >= content
  max-width + rail reserve + the opposite-side rail/gutter), live via a
  `ResizeObserver`; [erfuellt] (tests/webview/toc/layout.test.ts: "a content-box
  change re-decides rail or FAB without a window resize") `markdownWorkbench.toc.mode` (`auto`/`rail`/`fab`)
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
  changed links (O(path), not O(headings)). [erfuellt]
  (tests/webview/top-bars/bars.test.ts: "a forced re-emit with an unchanged chain
  rebuilds nothing", "a chain change of the same depth updates the bar links in
  place"; tests/webview/toc/tree.test.ts: "the TOC highlight touches only the links
  whose state changed")
- **Layout** - the bars fill the content region only, clearing the minimap and
  TOC rail via the same per-side reserves as the body padding. [erfuellt] z-index
  top to
  bottom: breadcrumb dropdown (8) > TOC overlay (7) > FAB/backdrop (6) >
  minimap/TOC rail (5) > top bars (4) > sticky table header (2) > content.
  [erfuellt] (tests/webview/top-bars/bars.test.ts: "the layers stack in the documented
  z-index order")
- **Sticky table header** - a table's header docks directly below the current
  bars: `th` sits at `top: var(--sticky-head-top)`, a variable written on the
  document's `thead`s (never on `:root`) and only when the stack depth changes
  (`setStickyHeadInset`, DECISIONS.md #36/#38). A wide, horizontally scrolling
  table gets an emulated header instead, moved by `translateY` from cached
  geometry (`updateStickyHeads`, `stickyHeadOffset`, DECISIONS.md #39).
  [erfuellt] (tests/webview/tables/sticky-head.test.ts: "the sticky table header docks
  FLUSH under the current stack, per-thead not on :root (#44 perf)",
  "stickyHeadOffset: explicit geometries", "a wide (scrolling) table switches off
  native th sticky so the emulated pin is the only one")
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
untouched (DECISIONS.md #40). [erfuellt] (tests/webview/page/focus.test.ts: "one
central mousedown handler suppresses the click focus on every control (#44)")

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
  [erfuellt] (tests/webview/folding/refresh.test.ts: "the fold pass waits for idle
  time with a 250 ms deadline where requestIdleCallback exists"; the `setTimeout`
  fallback in the same file) The `ResizeObserver` skips its own re-measure while that pass
  is pending, so the work is not done twice per toggle. [erfuellt]
- **Minimap** - the clone is _mirrored_, not rebuilt: its top-level children are
  index-parallel to `#content`'s, so a fold is one class write per block.
  [erfuellt] A full rebuild is reserved for the rail appearing/disappearing or a
  clone that no longer matches the document. [erfuellt]
  (tests/webview/folding/refresh.test.ts: "the fold mirror rebuilds the minimap when
  the clone no longer matches the document", "the fold mirror rebuilds the minimap
  when the rail has to appear")
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
styling entirely until reset to `auto`. [erfuellt] (tests/webview/page/page.test.ts:
"the custom scrollbar is in effect: scrollbar-color auto, no arrow buttons"; the real
rendering is a manual check, the Node tests read the stylesheet)

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
`markdownWorkbench.inTable` in their `when` clauses. [erfuellt]
(tests/package-assets.test.ts: "`${command} is bound only inside a table, with tables
and arrow navigation enabled`" for `onUpKey` and `onDownKey`) The two `*.enabled`
join switches gate the keybindings through `when` clauses in `package.json`; the
preview-side `lists.renderExtraMarkers` / `lists.extraMarkers` reach the renderer
through the render env (`configuredRenderEnv` in `src/views/config.ts`). [erfuellt]
(tests/package-assets.test.ts: "`${command} is bound only while its join setting is
on`" for both join commands; tests/views/config.test.ts: "configuredRenderEnv passes
the extra-marker settings to markdown-it, with defaults")

## Editing features (src/editing/)

Editor-side authoring commands, modeled on Learn Markdown / Markdown All in
One: Enter list continuation (numbered increment, empty-item termination),
code-fence auto-close (unindented snippet - VS Code auto-indents
continuation lines), fence language IntelliSense (Shiki ids + verified
aliases), Tab/Shift+Tab adaptive nesting, wrap toggles (bold/italic/code,
wrap/unwrap/extend-unwrap), web link insertion, table insert
(snippet with tab stops), distribute/consolidate table reflow (alignment
colons preserved), numeric-aware selection sort, authoring quick-pick menu.
[erfuellt] File link insertion works as well. [erfuellt]
(tests/editing/wrap-links.test.ts: the three `insertFileLink` tests "... links the
picked file relative to a file document", "... labels the link with the selected
text", "... uses the workspace-relative path outside a file document")

### Tables (src/tables/)

Table editing sees the table the preview renders (DECISIONS.md #49). [erfuellt]

- **Model** - which lines are table rows, and where each row's content starts,
  comes from a block parse with the preview's own markdown-it instance
  (`src/render/parser.ts`, read by `blocks.ts`, cached per document version) -
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
  [erfuellt] Unicode whitespace at an inner cell edge becomes spaces. [erfuellt]
  (tests/tables/format.test.ts: "Unicode whitespace at an inner cell edge is trimmed
  and becomes spaces"; tests/tables/row.test.ts: "Unicode whitespace at an inner cell
  edge is padding, not content")
- **Keys** - Enter (E1-E10), Shift+Enter (`cellLineBreak`), Tab/Shift+Tab
  (T1-T8) and `|` + Tab starting a table (K2, `createFromPipe`) run as branches
  in front of the list handling in `src/editing/`; a new row carries `[ ]` in
  checkbox columns (K5, `continueCheckboxes`),
  each as one edit (one undo step; test `E1+E8: Enter and alignment are one
undo step (REQ-020, REQ-021)`); Up/Down (T9) run only where the context key
  `markdownWorkbench.inTable` is set, which `arrows.ts` writes on selection
  changes only when it flips (test `the context key is set only when it
changes (REQ-038)`); after an edit that would cost a block parse, only once
  typing pauses (test `after an edit the key waits for a typing pause before it
parses (R2-4)`).
  [erfuellt] That Up/Down hang on the context key is the keybindings' `when`
  clause. [erfuellt] (the arrow-key test in § "Configuration"). Behavior in the real VS Code (keybinding precedence,
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
(tests/clipboard-diff/compare.test.ts) Evidence: the mock suites in
`tests/clipboard-diff/` and the integration suites in `tests/integration/suite/`
plus the normal-window guard (`tests/integration/guard/`, started by
`tests/integration/run.ts`), in a real VS Code at the minimum and the stable
version, run locally by `build.ps1 -Task Integration` (not in CI). On Windows,
before VS Code starts, the runner measures the real path of the downloaded
`workbench.html` and stops with length, limit (260), path and remedy where
VS Code could not load it; a failed cleanup is a warning and does not hide the
run's result. [erfuellt] (tests/integration/run.test.ts)

- **Commands** (`index.ts`). "Compare with Clipboard" and "Compare with
  Earlier Clipboard" (a QuickPick of the session's clipboard texts, newest
  first, compared by the same baseline logic). [erfuellt]
  (tests/clipboard-diff/compare.test.ts) Tab-bar buttons of a clipboard diff:
  "Apply Candidate" and the style switch between the raw clipboard and the
  text aligned to the baseline's style (`alignCandidateStyle` /
  `showRawCandidate`, context `markdownWorkbench.candidateStyleAligned`); the
  switch asks before it discards edits of the candidate and keeps the file
  text around an anchored section. [erfuellt] (tests/clipboard-diff/index.test.ts)
  "Swap Diff Sides" has its own button (see Swap).
- **Scheme.** Candidate and selection pages live under
  `markdown-workbench-clipboard:/<id>/<name> (<Role>)<ext>`, served by a
  `FileSystemProvider` (`CandidateStore`) from a `Map` in memory; `writeFile`
  never touches the disk, `stat` reports a growing mtime. [erfuellt]
  (tests/clipboard-diff/store.test.ts)
- **Immediate save** (`saving.ts`). Every change of a page is saved at once
  (`onDidChangeTextDocument`, own scheme only), so VS Code's backup tracker
  never keeps an unsaved page long enough to write it under
  `Backups/<ws>/<scheme>/`. [erfuellt] (tests/integration/guard/scenario.ts in
  the test host and in a normal window, both versions; mutation run:
  tests/integration/guard-mutation.ts) The focused page
  (either side of a diff) is saved with `workbench.action.files.saveWithoutFormatting`, so the
  user's save actions (trim trailing whitespace, final newline, format on
  save) do not run while typing. [erfuellt] (saving.int.ts) Any other page is
  saved with `document.save()`: its save actions may change that page, and
  the edits made while such a save runs - until did-save or its end, however
  long - are never written into the file. [erfuellt] (saving.int.ts,
  tests/clipboard-diff/saving.test.ts) A save VS Code starts itself (Ctrl+S on
  a page) marks its edits until did-save, at most `SAVE_WINDOW_MS` (3 s), so a
  save that fails without did-save does not keep the page unsaved. [erfuellt]
  (saving.test.ts) What a
  selection page holds beyond the written text at did-save came after the
  write and goes into the file (`sync.ts` `reconcileSaved`). [erfuellt]
  (tests/clipboard-diff/saving.test.ts) A page focused during such a save that
  still differs from its file region in more than trailing blanks and final
  line breaks afterwards
  gets the sync warning, without page text. [erfuellt]
  (tests/clipboard-diff/sync.test.ts) An edit that lands inside a save is
  saved right after it, also when `document.save()` resolves false for it; a
  failed save warns without the page content. [erfuellt]
  (tests/clipboard-diff/saving.test.ts)
- **Lifecycle** (`session.ts`). A diff's pages are released once no tab shows
  its candidate or its selection page and it is no longer opening
  (`tabGroups.onDidChangeTabs`, checked after the tab model settles, so a swap
  keeps them), and on `deactivate`; stored pages no diff owns (a
  "Save As" copy inside the scheme) go with them. Pages restored from an
  earlier window are closed on activation. [erfuellt]
  (tests/clipboard-diff/session.test.ts, tests/integration/suite/guard.int.ts)
  The clipboard text reaches no log, message or persisted state. [erfuellt]
  (tests/clipboard-diff/session.test.ts, tests/integration/suite/guard.int.ts)
- **Baseline shapes** (`sync.ts`). A selection (or the hull of several) becomes a
  `(Selection)` page mirroring its range in the file both ways: a page edit
  writes through into the range, a file edit inside the range updates the
  page. Without a selection the baseline is the live file: the whole file,
  or, after an anchor hit, the file against the file with the anchored lines
  replaced, opened with that span selected. [erfuellt]
  (tests/clipboard-diff/compare.test.ts, tests/integration/suite/hints.int.ts)
  File edits outside the anchored lines follow into the candidate's copy of
  the file (`sync.ts` `mirrorAround`) until that copy was edited around the
  section; from then on they no longer do. [erfuellt]
  (tests/clipboard-diff/session.test.ts, tests/clipboard-diff/sync.test.ts)
  The candidate takes the baseline's language and line endings. [erfuellt]
  (tests/clipboard-diff/compare.test.ts)
- **Diff call and titles.** `vscode.diff(baseline, candidate)` without a
  title; VS Code names the tab from the page names
  (`notes.md ↔ notes (Candidate).md`) and renames it after a swap. [erfuellt]
  (tests/integration/suite/diff.int.ts)
- **Swap** (`index.ts`). `workbench.action.compareEditor.swapSides` through
  `executeCommand` for any active text diff; the result is checked on the tab,
  a skipped or failed swap is reported. [erfuellt] After a swap, other clean
  tabs of the group showing the same two sides are closed, so one tab is left
  (a Git change reopened after a swap opens in its first order); a dirty one
  stays and is reported. [erfuellt]
  (tests/clipboard-diff/session.test.ts, tests/integration/suite/swap.int.ts)
  The tab-bar button has
  `when: isInDiffEditor && !activeCompareEditorCanSwap`: it shows only where VS
  Code's own is hidden, which needs a writable left side (a Git diff as
  opened). [erfuellt] (tests/clipboard-diff/index.test.ts,
  tests/integration/suite/swap.int.ts)
- **Apply.** The tracked region (character offsets, moved by
  `contentChanges`, `region.ts`) is replaced by one `WorkspaceEdit`, after the
  placeholder fill and the Markdown check; an edit inside the region since the
  diff opened makes Apply ask first. [erfuellt]
  (tests/clipboard-diff/apply.test.ts, tests/clipboard-diff/region.test.ts)
  Where the candidate was edited
  outside its clipboard part too (an anchored diff), the whole candidate
  replaces the whole file; the diff changes only after a successful Apply.
  [erfuellt] (tests/clipboard-diff/apply.test.ts) One undo reverts it. [erfuellt]
  (tests/integration/suite/diff.int.ts) Per-hunk apply is VS Code's revert
  arrow, which copies left to right: it drops a candidate hunk before a swap
  and takes it into the file after one. [erfuellt]
  (tests/integration/suite/diff.int.ts)
- **Anchor** (`anchor.ts`). A heading-led clipboard takes the same-named
  section; otherwise a line-hash index finds the first/last line and scores
  the overlap at no more than 2 × `MAX_ANCHOR_CANDIDATES` places (up to
  `MAX_ANCHOR_CANDIDATES` from each line); unsure or ambiguous hits go to a
  QuickPick with "Whole file". Placeholder lines never anchor. [erfuellt]
  (tests/clipboard-diff/anchor.test.ts, tests/integration/suite/hints.int.ts)
- **Style** (`style.ts`, emphasis masking in `emphasis.ts`). Baseline profile (bullet, emphasis, strong, table
  padding via `reflowTable` of the table model), applied by swapping markers in place outside
  verbatim blocks, verified by comparing the parsed structure before and
  after. [erfuellt] (tests/clipboard-diff/style.test.ts)
- **Unwrap and placeholders** (`unwrap.ts`). Outer fence and edge chat lines
  by named pattern lists; placeholder lines by `PLACEHOLDER_PATTERNS`, filled
  on Apply from the baseline between the neighbouring lines, unclear ones
  asked about. [erfuellt] (tests/clipboard-diff/unwrap.test.ts)
- **Check** (`check.ts`). Reset checkboxes (`CHECKBOX_RE`), lost reference and
  footnote definitions (markdown-it's `env.references`), front matter, removed
  headings with `#anchor` links. Diagnostics on the candidate (quick fixes for
  checkbox states and placeholders) use the file's own links (cached per file
  version); Apply adds the workspace's links behind
  `markdownWorkbench.clipboardDiff.checkWorkspaceAnchors` (resolved relative
  to their file, files over 1 MB (`MAX_SCAN_BYTES`) or unreadable skipped).
  One question at Apply, never a block. [erfuellt]
  (tests/clipboard-diff/check.test.ts, diagnostics.test.ts, apply.test.ts;
  tests/integration/suite/hints.int.ts)
- **History** (`history.ts`). Ring buffer of the clipboard texts the
  extension read, memory only, `MAX_HISTORY_ENTRIES` / `MAX_ENTRY_BYTES`.
  [erfuellt] (tests/clipboard-diff/history.test.ts)
- **Limits.** "Save As" cannot be locked. [nicht verifiziert]
  (microsoft/vscode - the extension API offers no lock besides `isReadonly`)
  Its default target is the candidate URI, and cancelling it writes nothing.
  [erfuellt] (tests/integration/suite/saveas.int.ts, both versions) Only a
  local target the user picks via "Show Local" writes to disk, the candidate
  there and nothing else, and not before the target is accepted. [erfuellt]
  (tests/integration/suite/saveas.int.ts, both versions; the case takes the
  same local Save As through the simplified dialog) A failed
  in-memory save lets VS Code back the page up.
  [nicht verifiziert] (microsoft/vscode - the backup tracker)

## Message protocol (host <-> webview)

The source of the protocol is `src/webview/protocol.ts`: one union per direction
(`HostToWebview`, `WebviewToHost`) plus the persisted `WebviewState`, types only.
Host and webview both import it, so a message the other side does not know is a type
error. [erfuellt] (tests/webview/protocol.probe.ts, checked by `pnpm run typecheck`)
The table summarizes it.

| Direction       | Type         | Payload                                                                                                                                                                                                                 |
| --------------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| host -> webview | `config`     | `documentUri`, `maxWidth`, `minimap{enabled,size,showSlider,side}`, `toc{enabled,mode}`, `breadcrumb{enabled}`, `stickyScroll{enabled}`, `tables{previewSort}`, `textSelection`, `taskBatchSelect`, `taskRowTextCursor` |
| host -> webview | `render`     | `html`, document `version`, `key` (hash of the render inputs, § "Webview loading")                                                                                                                                      |
| host -> webview | `version`    | document `version`, instead of a `render` for a restored stand that is current                                                                                                                                          |
| host -> webview | `scrollTo`   | fractional `line`                                                                                                                                                                                                       |
| webview -> host | `ready`      | after a restore: `buildId`, `key` of the shown stand and `restoredInMs`; otherwise nothing                                                                                                                              |
| webview -> host | `toggle`     | `lines[]`, `checked`                                                                                                                                                                                                    |
| webview -> host | `toggleCell` | `line`, `idx`, `checked`                                                                                                                                                                                                |
| webview -> host | `scrolled`   | fractional `line`                                                                                                                                                                                                       |
| webview -> host | `sortTable`  | table start `line`, `col`, `dir` (`asc`/`desc`), document `version`                                                                                                                                                     |

[erfuellt] The webview sends `ready` once it has loaded. [erfuellt] (host side in
tests/activation.test.ts; tests/webview/main.test.ts: "the webview posts ready once it
has loaded, and nothing before")
