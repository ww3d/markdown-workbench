# Changelog

## 0.31.0
- Heading anchors and in-document TOC navigation. Every heading now gets a
  GitHub-compatible slug `id` (lowercase; everything but Unicode
  letters/marks/numbers/connector punctuation, hyphens and spaces stripped;
  spaces to hyphens; duplicates suffixed `-1`/`-2`), so in-document links like a
  generated table of contents resolve in the preview. A bare `#hash` link does
  not self-navigate inside a VS Code webview, so a click on an internal
  `a[href^="#"]` now scrolls to the target heading (and the source editor
  follows via the existing scroll sync); a missing target is a no-op. The
  slugger mirrors `github-slugger` and is implemented inline, adding no runtime
  dependency. Cross-file (`./other.md#x`) and external `http(s)://` links are
  unchanged (#31).

## 0.30.0
- Preview text is now selectable and copyable. `body` carried a global
  `user-select: none` purely to keep a drag on a task row from ending as a text
  selection instead of a toggle; the side effect was that no preview text at all
  (prose, code, tables) could be selected. `user-select: text` is now the
  default; `none` is confined to the minimap and the checkbox inputs. The task
  toggle is decided at click time instead (#15): a click directly on a checkbox
  always toggles, while a bare click in the row/label or a single-checkbox cell
  toggles only when it produced no text selection and is a single click (so
  dragging out a selection or double-clicking to select a word no longer
  toggles). The batch gestures (Shift = range, Ctrl/Meta = membership) now fire
  from the checkbox only, not the label, so Shift in the label stays normal text
  selection.
- In-preview find: Ctrl+F in a focused preview or workbench editor now opens
  VS Code's native find widget with highlight, next/previous and a match count
  (#24). Enabled via `enableFindWidget` on both `WebviewPanel` construction
  paths (custom editor and side preview); it searches the rendered DOM text, not
  the markdown source, consistent with the copy behavior.
- Three settings make the new selection/toggle behavior tunable; their defaults
  reproduce the behavior above exactly. `markdownWorkbench.preview.textSelection`
  (default `true`) locks selection again when off, restoring the pre-0.30.0
  whole-row toggle. `markdownWorkbench.preview.taskBatchSelect` (`checkbox`
  default / `row`) chooses whether the Shift/Ctrl batch select fires on the
  checkbox (so Shift in the label stays text selection) or anywhere in the row.
  `markdownWorkbench.preview.taskRowTextCursor` (default `false`, only with
  `textSelection` on) shows a text caret over the row label while the checkbox
  keeps the pointer hand. Setting `textSelection: false` + `taskBatchSelect:
  row` reproduces the full pre-0.30.0 behavior.

## 0.29.1
- Fix: the tab-action icons introduced in 0.29.0 were missing from the packaged
  vsix, so the commands rendered without glyphs. `.vscodeignore` was an
  allowlist (`media/*.svg` excluded, the two removed `checklist-*.svg`
  re-added), so the six new `workbench-*`/`source-*` SVGs matched the exclude
  with no negation and never entered the package. `.vscodeignore` now excludes
  only the `media/icon.svg` design master, shipping every runtime icon SVG by
  default. A new `tests/package-assets.test.js` guard asserts every asset
  referenced by `package.json` and `src/views.js` is present in the real
  `vsce ls` pack list, so a dropped icon turns the build red.

## 0.29.0
- The five editor tab-action commands (`Open Workbench`,
  `Open Workbench to the Side`, `Open as Workbench`, `Open Source File`,
  `Reopen as source file`) now share one monochrome 16px icon set built on a
  common document housing: a `workbench` glyph (page + check), a
  `workbench-side` glyph (split page), and a `source` glyph (page + `</>`),
  each in a light and dark variant. `Open as Workbench` no longer uses the
  generic `$(preview)` codicon, so it no longer looks identical to VS Code's
  built-in Open Preview sitting right next to it; `Open Source File` /
  `Reopen as source file` no longer use `$(file-code)`. `open` and
  `showPreview` deliberately share the `workbench` motif (their menu text tells
  them apart). The retired `media/checklist-*.svg` assets are removed. Extends
  the monochrome tab glyphs introduced in 0.15.0.

## 0.28.0
- Fix: Enter on a continuation/hanging line that sits below deeper-indented
  children of its item now continues the item (creates the next sibling at the
  parent's level) instead of falling back to a plain newline.
  `enclosingListItem` walks up over the intervening children and binds the line
  to the first item at or shallower than its own indentation; a whitespace-only
  hanging line resolves the same way.
- Fix: Tab nesting a numbered item into a deeper level that already has a
  preceding sibling now continues that sequence (`1.` `2.` `3.`) instead of
  writing a hardcoded `1`, so tabbing several items into one sublist no longer
  leaves duplicate `1.`/`1.` markers. The gap-closing renumber of the level
  left behind and the "skip children of the tabbed item" behavior are
  unchanged.
- Tab/Shift+Tab on a markerless line (a continuation or plain-text line, not a
  list item) now snaps its indentation onto a column stop instead of a fixed
  step: column 0, the indent/content columns of nearby list items, the word
  starts of nearby lines, and the editor's tab-size multiples. Tab moves to the
  next stop right, Shift+Tab to the next left; with nothing detected nearby it
  steps by the tab size. `markdownWorkbench.indent.continuationStopRadius`
  (default 5) bounds the scan window. List-item lines are unaffected - they keep
  their structural nesting/renumbering. A multi-line selection - list items and
  markerless lines together - moves as a block by one common delta (reference =
  topmost line; left shift capped by the flattest line), so the relative
  indentation is preserved and nothing drifts apart even when marker widths
  differ (e.g. `8.`/`9.` next to `10.`/`11.`); markers are not renumbered in a
  multi-line selection (a single item still nests/renumbers structurally). The
  block reads each line once and builds the stop set once per keystroke (not per
  line), so fast Tab/Shift+Tab on a large selection stays smooth.
- New (opt-in, off by default) content-line joins on Ctrl+Delete
  (`markdownWorkbench.editing.forwardJoin.enabled`,
  `markdownWorkbench.joinForwardOrFallback`) and Ctrl+Backspace
  (`markdownWorkbench.editing.backwardJoin.enabled`,
  `markdownWorkbench.joinBackwardOrFallback`): at the end / start of a line's
  visible content (or on an empty/whitespace-only line, which counts as both),
  merge it with the next / previous line that has content, deleting blank and
  whitespace-only lines in between and normalizing the seam to exactly
  `markdownWorkbench.editing.joinSpaces` spaces (default 1, 0 = no space) - never
  a double space, and no space at all when one side is an empty line. Otherwise
  each runs its configurable fallback
  command (`forwardJoin.fallbackCommand` default deleteWordRight,
  `backwardJoin.fallbackCommand` default deleteWordLeft), executed directly.
  Replaces the earlier single `editing.smartForwardDelete` option.
- New (opt-in, off by default) custom list markers, gated by
  `markdownWorkbench.lists.extraMarkersEnabled` plus a non-empty
  `markdownWorkbench.lists.extraMarkers` (with `markdownWorkbench.lists.markerCycle`):
  the editor recognizes configurable non-CommonMark markers as list items -
  symbol bullets (`->`, `→`, `❯`, repeat), lettered markers (`a)`, `A)`, `a.`,
  `A.`, `a:`, `A:`, count up a…z, za; upper-case separate; delimiter preserved)
  and digit markers (`1)`, `1:`, including the `:` delimiter). Enter continues
  them; Tab/Shift+Tab nest AND renumber them with the same machinery as native
  numbers - the level left behind closes its gap and Shift+Tab joins the target
  level's sequence (adopting its family), while a symbol item keeps its bullet
  and only indents. Only the marker token is rewritten, so a multi-space gap is
  preserved. Tab into an empty deeper level uses the markerCycle by depth;
  changing the first item's marker type pulls its same-level siblings to the new
  type (never children/parents). Being non-CommonMark, an enabled letter/digit
  family can also match ordinary prose (`ok) go`, `is: this`) - an accepted
  trade-off of opting in (docs/DECISIONS.md #26).
- New (opt-in, off by default) `markdownWorkbench.lists.renderExtraMarkers`:
  when extra markers are configured, the preview renders those lines as lists
  with the same outline styling as native lists. Deliberately non-portable -
  the source stays plain text everywhere else and with the setting off
  (docs/DECISIONS.md #26). An open workbench preview now reacts live to changes
  of `renderExtraMarkers`/`extraMarkers` (and the other settings): the config
  listener re-renders instead of only updating view options, so a setting change
  no longer needs the preview closed and reopened.
- Numbered lists auto-renumber on a manual marker change: typing a new number
  over a marker makes the following same-level siblings continue from it
  (`1. a / 5. b / 6. c`) - the sequence follows the input and is never reset to
  1 (a list may start at any number). Only editing the marker triggers it (a
  text edit leaves an intentionally non-sequential list alone), and it runs
  behind the same re-entrancy guard as Enter/Tab/Shift+Tab so those do their own
  renumbering without the manual pass firing on top (docs/DECISIONS.md #27).

## 0.27.0
- Hanging continuation lines for lists in the text editor: Shift+Enter inside
  a list item (or one of its continuation lines) splits at the cursor and
  indents the new line with whitespace to the item's content column -
  markerless, no number, text right of the cursor moving down with it (`2. `
  -> 3 spaces, `   - [ ] ` -> 9, compound `1. - [ ] ` -> 9). Outside a list,
  or with the cursor still inside the marker/indentation, it falls through to
  the editor default. There was no Shift+Enter handling before; it ran on the
  VS Code default (plain break auto-indented to the marker), which is the bug
  this fixes.
- Enter is now continuation-aware: pressing Enter on a continuation line
  continues its enclosing item with a fresh sibling at the item's level (next
  number / same bullet) and renumbers the following siblings (`   buttons
  rechts` under `2. ...` + Enter -> `3. `). Cursor directly on an item line is
  unchanged.
- `renumberSiblingsBelow` and `previousSiblingNumber` step over continuation
  lines instead of breaking on the first markerless line: a markerless,
  non-blank line indented to at least the running item's content column is
  skipped, so a wrapped continuation mid-sequence no longer stops the
  renumbering (`1.`/`2.` with a wrapped line under `2.`, a new item between
  them now counts `3.` through). A blank line or a shallower/foreign line still
  ends the run - the skip is decided on the content-column comparison, not on
  "somehow indented". The compared column is the trigger item's content column
  (a stable floor for the run, since numbers only grow downward), so a
  continuation that hangs under the narrower marker before a one-/two-digit
  transition (`9.` -> `10.`) still counts instead of silently breaking the
  renumbering. This also makes Enter count correctly past the markerless,
  content-column-indented lines that external reflow extensions (e.g.
  marvhen.reflow-markdown, Alt+Q) produce.

## 0.26.0
- Compound task items (`1. - [ ] foo` - a numbered item whose content is a
  one-line bullet task) are first-class: they toggle from the view
  (CHECKBOX_RE now accepts an optional second marker between the first
  marker and the box) and continue on Enter (`1. - [ ] asd` ->
  `2. - [ ] `; the leading marker follows its continuation rule, the rest
  of the compound prefix continues verbatim with a fresh box - a dash-led
  compound never increments the inner number). Empty compound items
  terminate the list like plain ones; 0.25.0 renumbering and Tab/Shift+Tab
  treat compound lines as ordinary numbered items (pinned by tests).
- Editing-oriented task rendering, deviating from the built-in preview
  (docs/DECISIONS.md #25): ordered task items keep their visible
  number/outline marker (the hidden markers used to keep counting -
  visible gaps in mixed lists); `[ ]`/`[x]` without a label renders as a
  clickable task row instead of literal text, so fresh Enter-continuation
  lines don't flicker while typing.

## 0.25.0
- Numbered lists in the text editor: Enter mid-sequence now renumbers the
  following siblings of the same level and delimiter (delimiter `.`/`)`
  and a `[ ]`/`[x]` checkbox continue as before, empty item still
  terminates the list). Tab on a single numbered item starts a new sublist
  (number restarts at `1`, delimiter preserved); Shift+Tab joins the
  target-level sequence (number = next after the preceding sibling there).
  Both directions close the gap in the sequence left behind, Shift+Tab
  also renumbers the target sequence. Dash items under numbered parents
  (and vice versa) are never rewritten.
- The view renders ordered lists with classic outline markers by ol-depth:
  decimal, lower-alpha, lower-roman, repeating from level 4. Presentation
  only - the source always keeps portable CommonMark digit markers, never
  letters (docs/DECISIONS.md #24).

## 0.24.7
- Fixed: the sticky table header vanished on vertical scrolling for tables
  wide enough to scroll element-wise (the 0.24.6 `scrolls` wrapper is the
  th's scrollport, so native `position: sticky` is inert against the window
  scroll). The pin is now emulated for those tables by translating the thead
  with the window scroll (rAF-throttled, clamped to the table's bottom edge,
  reset on render/config/resize). The thead stays in-flow, so it keeps
  scrolling horizontally with the wrapper and columns stay aligned. Tables
  that fit the viewport keep native sticky, unchanged; the minimap clone
  neutralizes the emulated pin.

## 0.24.6
- Fixed: with a configured `markdownWorkbench.preview.maxWidth`, a table wider
  than the reading column overflowed to the right only and h-scrolled the
  whole window while the left centering margin stayed empty. Tables (and
  fenced code blocks) wider than the column now grow symmetrically into both
  margins, capped at the body's content width; a table wider than that cap
  scrolls element-wise inside its own wrapper instead of the window. Body
  text keeps the configured centered measure, `data-line` attributes stay on
  the table itself (scroll sync, cell toggles and minimap unchanged), and the
  sticky table header is preserved for tables that fit the viewport.

## 0.24.5
- `publish.ps1` preflight now verifies that the signed-in az identity holds
  publish permission on the publisher (`vsce verify-pat <publisher>
  --azure-credential`) - before download and integrity checks, so an
  identity mismatch fails in seconds instead of after the whole chain at
  upload with "Access Denied". The vsce output stays visible because it
  carries the diagnosis. Found live: the same e-mail existed as both a
  personal Microsoft account (publisher owner) and an Entra identity (what
  az login uses) - two different principals; the new CONTRIBUTING
  subsection "Publisher identity" documents the trap, the verify-pat
  one-liner, and how to find the UPN the publisher's Members dialog
  actually accepts.

## 0.24.4
- Fixed: `publish.ps1` hung at "Check the gallery" in a fresh clone without
  `npm ci` - npx found no local `@vscode/vsce`, offered its interactive
  install prompt, and the captured output streams made that prompt invisible
  while npx waited forever on stdin. The preflight now fails hard with "Run
  'npm ci' first" when `node_modules/@vscode/vsce` is missing (the script
  never installs anything itself), and both vsce calls use
  `npx --no-install` so npx fails hard instead of prompting even if the
  preflight is ever bypassed. CONTRIBUTING lists `npm ci` in the one-time
  publishing setup.

## 0.24.3
- New `publish.ps1`: manual Marketplace publishing of the attested GitHub
  release artifact - never a local build - via Entra ID
  (`vsce publish --azure-credential`; no PAT path, Marketplace PATs retire
  12/2026). The script preflights the toolchain (node >= 22, az logged in,
  gh authenticated, publisher set in package.json), downloads the vsix and
  SHA256SUMS.txt of the `v<version>` release, verifies the checksum and the
  build-provenance attestation (both mandatory, hard abort on any mismatch
  before any publish attempt), and skips cleanly with exit 0 when the
  gallery already has that version. Publishing deliberately stays out of
  build.ps1, which remains credential-free and deterministic for CI.
- CONTRIBUTING: new "Marketplace publishing" section - one-time setup
  (publisher, Azure CLI, az login), then exactly one command per release.
  README notes the Marketplace as the future install path.

## 0.24.2
- Every green build on main now publishes a GitHub Release automatically: a
  `release` job (CI workflow, runs only on push to main, after the test/
  package job) tags `v<version>` from package.json, names the release
  `v<version>`, and attaches the curated CHANGELOG section for that version
  as the release notes, with GitHub's auto-generated PR/contributor list
  appended (fetched via the releases/generate-notes REST endpoint, so the
  full notes file is built deterministically before publishing). Idempotent:
  if the tag already exists (e.g. a docs
  merge with no version bump) the release step is skipped cleanly, never
  overwriting an existing release.
- Release assets: the vsix as a direct download (no zip wrapper) and
  `SHA256SUMS.txt` (sha256sum format). The vsix carries a build-provenance
  attestation (Sigstore public-good via actions/attest-build-provenance),
  verifiable with `gh attestation verify <vsix> --repo ww3d/markdown-workbench`.
- Release notes are cut from CHANGELOG.md by `scripts/release-notes.js`
  (section between `## <version>` and the next `## ` heading); a missing or
  empty section fails the release loudly. Covered by tests/release-notes.test.js.

## 0.24.1
- Fixed: syntax highlighting was dead in the packaged vsix - broken since
  0.23.0. Two stacked root causes, the second masked by the first:
  (1) Rolldown's CJS output appends its cross-chunk runtime helpers to the
  entry's exports object; the entry reassigned module.exports and dropped
  them, so every lazy Shiki chunk failed to load. The entry now extends
  module.exports via Object.assign instead of replacing it.
  (2) Shiki's default Oniguruma WASM engine loads its binary through a
  template-literal import('shiki/wasm') that no bundler can statically
  resolve - the bare specifier survives bundling, resolves in the repo via
  node_modules and dies in the installed vsix (which ships none) with
  ERR_MODULE_NOT_FOUND. Shiki now runs on the JavaScript regex engine
  (shiki/engine/javascript); the tsdown alwaysBundle entry became the regex
  /^shiki/ so the engine subpath is bundled too. In both cases
  initHighlighter swallowed the error and silently fell back to plain code
  blocks; unit tests run against src/ and could not see either.
- New bundle smoke test (scripts/bundle-smoke.js, npm run bundle-smoke):
  copies dist/ to a temp directory outside the repo - no node_modules on
  Node's upward search path, exactly the installed-vsix topology - then
  drives the bundle through the vscode mock, renders a fence for every one
  of the 18 bundled languages and asserts real Shiki output for each
  (class="shiki", inline color styles, no language-* fallback). Wired into
  build.ps1 directly after the bundle step, so CI goes red instead of
  silently degrading on any future bundler/config/entry change that breaks
  the chunks or the engine.
- Minimap slider can be grabbed and dragged like the editor minimap, no jump
  on grab: pointerdown inside the slider rectangle moves the viewport
  relative to the grab point (geometric hit test, so the mouseover-hidden
  slider stays grabbable; works in all three size modes); clicks on the rail
  outside the slider keep the centering jump.

## 0.24.0
- Naming: the user-visible view labels now read "Workbench" instead of
  "Checklist" - command titles (Open Workbench / Open Workbench to the Side /
  Toggle Workbench / Open as Workbench), the "Workbench: <file>" tab/panel
  title (now a single constant, no longer duplicated), and the settings
  descriptions. The "checklist" Marketplace keyword, the checkbox-feature
  docs and the media/checklist-*.svg icon filenames are intentionally kept.
- Source split into modules under src/: render.js (markdown-it, plugins,
  Shiki, fence/frontmatter renderers), views.js (preview/custom-editor
  providers, wireWebview, scroll-sync helpers, surgical toggles, webview
  skeleton), a slim extension.js (activation + command wiring + preview
  orchestration), and editing.js moved unchanged. No behavior change; tsdown
  now bundles from src/extension.js, package.json main stays
  dist/extension.cjs.
- Webview extracted to real assets: the inline HTML template became
  media/webview.js and media/webview.css, loaded via asWebviewUri under a
  nonce'd Content-Security-Policy (localResourceRoots scoped to media/). The
  assets ship in the vsix but are not inlined into the host bundle - they run
  in the webview. getWebviewHtml is now a slim skeleton.
- Tests: 94 (was 88), still green under the 88/82/78 coverage gate. The
  headless DOM mock loads media/webview.js directly instead of extracting the
  script from the HTML; a new smoke test asserts getWebviewHtml carries the
  CSP, the script nonce and both asset URIs; added preview-panel orchestration
  tests for the relocated command wiring.

## 0.23.0
- Build modernized: esbuild replaced by tsdown (Rolldown + Oxc). Shiki's
  dynamic language/theme imports are code-split into lazy chunks - only
  languages actually used in fences load at runtime, instead of one
  monolithic 9.4 MB bundle. Same tool will carry the planned TypeScript
  migration without re-tooling. CI runs on Node 22 (tsdown requirement).
- Renamed to Markdown Workbench (was Markdown Checklist): the extension has
  grown into a full interactive preview plus an editor authoring suite, the
  old name only described the checkbox USP. Package name, display name,
  command and settings prefix (markdownWorkbench.*), custom editor view
  type and repository move accordingly. Existing keybindings referencing
  markdownChecklist.* commands need a one-time update.

## 0.22.0
- Fixed: checkboxes inside table header cells were converted to inputs
  although README and the 0.16.0 entry documented header cells as
  untouched - the th branch is removed from the cell plugin; the contract
  now matches the code (found by the new test suite)
- Test suite: 88 tests across rendering, toggles, scroll math, webview
  behavior (headless DOM), activation/wiring and all editing commands;
  c8 coverage gate at 88% lines / 82% branches / 78% functions
  (current: ~91/86/89)
- Build: esbuild bundle to dist/extension.js (main now points there,
  node_modules excluded from the vsix via .vscodeignore), PowerShell
  orchestrator build.ps1 (Test / Coverage / Build / Package / All) with a
  package.json-vs-CHANGELOG version consistency check
- CI: GitHub Actions workflow running the coverage gate and packaging the
  vsix as artifact
- Marketplace metadata: keywords, categories, gallery banner, bugs URL

## 0.21.5
- Root cause of the persistent scrollbar arrows found in the VS Code
  webview host source: VS Code injects scrollbar-color into every webview,
  and a non-auto scrollbar-color makes Chromium ignore all
  ::-webkit-scrollbar rules (which is why 0.21.3 and 0.21.4 were inert).
  scrollbar-color is now reset to auto (unlayered author style beats the
  injected @layer vscode-default), activating the custom scrollbar:
  no arrow buttons, full-height thumb track aligned with the minimap rail.

## 0.21.4
- Fixed for real: the 0.21.3 button-removal rule was inert - Chromium only
  honors scrollbar pseudo-element rules once ::-webkit-scrollbar itself is
  styled (custom mode). The full custom scrollbar block is now in place as
  the functional carrier (14px, transparent track, scrollbarSlider thumb
  tokens, no arrow buttons), making the thumb track span the full height
  and align with the minimap rail in fill mode.

## 0.21.3
- Fixed: remaining offset between minimap and scrollbar in fill mode - the
  native Chromium scrollbar has arrow buttons at both ends on Windows,
  shortening the thumb track against the full-height rail. The buttons are
  now removed so thumb track and rail share the same mapping length (a
  functional rule, distinct from the reverted 0.17.1 cosmetic styling).

## 0.21.2
- Fixed: minimap was offset against the real scrollbar - the rail ended
  26px above the bottom (reserved for the hint bar), so its mapping length
  was shorter than the scrollbar track. The rail now spans the full
  viewport height (like the editor) and the hint bar yields to it instead.

## 0.21.1
- Fixed: minimap could disappear entirely when the configuration values
  resolved to undefined (e.g. settings schema not yet active right after
  an in-place update) - both sides now fall back to defaults: get() with
  explicit defaults in the extension, Object.assign over defaults in the
  webview

## 0.21.0
- Minimap configurable like the editor minimap (markdownChecklist.minimap.*):
  enabled (on/off), size (proportional | fill | fit - fill maps the whole
  document linearly onto the rail so the slider stays aligned with the
  scrollbar and never drifts; fit downscales without stretching;
  proportional keeps the old panning behavior), showSlider (mouseover |
  always; default mouseover like the editor), side (right | left). All
  apply live via the config message; navigation math follows the active
  size mode.

## 0.20.0
- New setting markdownChecklist.preview.maxWidth: switch the content width
  between "github" (980px, default) and "narrow" (72ch). Applies live to
  open views via a config message; the minimap rebuilds since its scale
  depends on the column width.

## 0.19.2
- Reading column widened from 72ch to 980px centered - GitHub's own
  measure (github-markdown-css), matching the look of the built-in preview
  when styled by the Markdown Preview Github Styling extension (VS Code
  core itself sets no max-width; that one is extension-injected via
  markdown.previewStyles)

## 0.19.1
- Reverted the 0.18.2 and 0.19.0 layout changes 1:1 - back to the 0.18.1
  state: centered 72ch reading column, no full-width, no breakout grid

## 0.19.0
- Reading column with breakout (full-bleed grid pattern): prose renders in
  a centered 76ch column (industry range: GitHub ~980px container, Medium
  ~680px, Notion ~700px, Tailwind prose 65ch), while tables and code
  fences break out to the full pane width - readable text and full-width
  tables at the same time. The built-in preview has no max-width at all.

## 0.18.2
- Content renders at full pane width like the built-in preview (the 72ch
  measure is removed; the built-in's markdown.css has no max-width either,
  only horizontal padding)

## 0.18.1
- Fixed: minimap stayed empty on first display - the rail was still
  display:none when its width was measured, baking a scale of 0 into the
  clone; visibility is now decided before measuring

## 0.18.0
- Minimap in the checklist views: an 88px rail on the right shows a scaled
  clone of the rendered content with a viewport slider (minimapSlider theme
  tokens, hover/active states). Pans proportionally like the editor minimap
  when the scaled content exceeds the rail; click or drag navigates
  (centered); hidden automatically when the document fits the viewport.
  Rebuilt only on render/resize, position updates ride the existing
  scroll rAF - including editor-driven sync scrolls.

## 0.17.2
- Reverted the 0.17.1 scrollbar styling 1:1 (no visible benefit over the
  webview default scrollbar theming)

## 0.17.1
- Scrollbar in the checklist views explicitly styled with the editor's
  scrollbarSlider theme tokens (14px, transparent track, hover/active
  states) for visual parity with the source editor

## 0.17.0
- Modern table styling: vertical grid removed (horizontal hairlines only),
  uppercase muted header labels, generous padding, subtle row hover on top
  of the zebra striping
- Sticky table header: column labels stay pinned at the viewport top while
  scrolling through long tables (border-collapse: separate is required so
  the sticky header keeps its border in Chromium); headers hand over
  naturally between multiple tables

## 0.16.2
- Zebra striping for tables: even body rows get a subtle theme-derived
  background (4% foreground mix); header and cell hover highlight win over
  the stripe

## 0.16.1
- Clicking anywhere in a table cell that contains exactly one checkbox
  toggles it (pointer cursor and hover highlight as affordance); cells with
  multiple checkboxes still require a direct click on the checkbox

## 0.16.0
- Checkboxes inside table cells: "[ ]" / "[x]" in td cells render as
  clickable checkboxes and toggle surgically in the source; a row line can
  hold several, addressed by line + occurrence index (code spans are
  excluded consistently on both the render and the toggle side). Header
  cells are left untouched; direct toggle only (no multi-select for cells).

## 0.15.0
- Extension icon (media/icon.png, rendered from icon.svg): slate tile with
  an accent-gradient checked box (knockout check) above muted pending rows
- The tab-row preview buttons and the tab iconPath now use a matching
  monochrome 16px glyph (light/dark) instead of the codicon; Open as
  Checklist keeps $(preview) for distinction

## 0.14.2
- Open as Checklist / Reopen as source file now swap the editor in-place in
  the same tab via the workbench command reopenActiveEditorWith, like the
  built-in reopenAsPreview/reopenAsSource; vscode.openWith opened a second
  tab because tabs are keyed by resource + editor type (kept as fallback
  for invocations on non-active resources)

## 0.14.1
- Tab icon and title parity with the built-in preview: the checklist custom
  editor tab and the preview panels now carry the checklist icon
  (light/dark SVGs in media/) and a "Checklist: <file>" title, like
  preview.ts sets iconPath/title for its static and dynamic previews

## 0.14.0
- Pixel-accurate fractional scroll sync, algorithms taken from the built-in
  preview: getVisibleLine encodes the viewport's progress into the top line,
  the view interpolates positions between mapped elements, multi-line code
  fences scroll proportionally via their end line (markdown-it token map),
  and reveals encode the fraction as a character offset (toRevealRange)

## 0.13.2
- Opening a checklist view (preview to the side, in the active group, or as
  custom editor) now jumps straight to the position the source editor was
  scrolled to, like the built-in preview
- The way back (Open Source File, Reopen as source file) restores the last
  synced position when the target editor was not visibly live-synced

## 0.13.1
- Fixed: Open Source File (and the undo/redo focus hop) opened a new editor
  group when the preview was in the same group as the source tab - the
  background source tab is not in visibleTextEditors, so the fallback now
  targets the panel's own view column where the tab gets focused instead

## 0.13.0
- Ctrl+S / Ctrl+Z / Ctrl+Y (and Ctrl+Shift+Z) work while the preview panel
  has focus: save calls document.save(), undo/redo hop focus to the source
  editor, run the command, and return focus to the panel
- (Custom editor mode already had native save/undo/redo via the
  CustomTextEditorProvider document model)

## 0.12.0
- Preview opens with focus on the panel (analog built-in Open Preview to
  the Side); existing panels are revealed with focus
- Open Source File ($(file-code), navigation@2) on the preview panel:
  focuses an existing source editor or opens one beside the panel
- Reopen as source file ($(file-code), navigation@2) on the checklist
  custom editor: replaces it with the default text editor

## 0.11.0
- Alt+P now toggles the side preview: opens it, closes it when already
  open for the active document (new command Toggle Checklist), and closes
  the panel when pressed while the panel itself has focus

## 0.10.2
- Default keybinding Alt+P -> Open Checklist to the Side (when
  editorLangId == markdown)

## 0.10.1
- Fixed: closing fence was double-indented for indented fences (VS Code
  auto-indents snippet continuation lines; the snippet no longer carries
  the indentation itself)

## 0.10.0
- Fence language IntelliSense: completions after ```/~~~ from the bundled
  shiki languages plus common aliases
- Fence auto-close: Enter at the end of an unclosed opening fence inserts
  the matching closing delimiter with the cursor in between (parity check
  against later fence lines avoids double-closing)

## 0.9.0
- Tab / Shift+Tab nest and un-nest list items (adaptive indent unit =
  marker + gap width, multi-line selections, clean fallbacks)
- Formatting toggles bold/italic/code on Alt+D B/I/C (wrap selection or
  word, unwrap when already wrapped)
- Link insertion: Alt+D K web link snippet, Alt+D L relative link to a
  workspace file via quick pick
- Table tools: insert (size prompt, snippet), evenly distribute,
  consolidate (alignment markers preserved)
- Bulleted/numbered/task list conversion, numeric-aware selection sorting,
  language-identifier quick pick
- Alt+M authoring menu bundling all of the above
- Editing concerns moved to editing.js

## 0.8.0
- List continuation on Enter in markdown text editors: `- ` / `- [ ] ` /
  incremented `4. ` markers, indentation preserved, empty item terminates
  the list, non-list lines fall through to the default newline
- Documentation rewritten (README, CHANGELOG added)

## 0.7.0
- YAML frontmatter rendered as a property card (uppercase muted keys,
  monospace values); nested YAML falls back to a raw card
- Fixed: Alt-held tab-row button disappeared because the alt command had no
  icon; `Open Checklist` now carries `$(checklist)`
- Distinct icons: `$(checklist)` for preview buttons, `$(preview)` for
  "Open as Checklist"
- Titles aligned with the genuine built-in scheme ("Open Preview" pattern):
  Open Checklist / Open Checklist to the Side / Open as Checklist

## 0.6.x
- Fixed preview->editor scroll sync: container elements (long `<ul>`) pinned
  the reported line to the list start; now the first element starting at or
  below the viewport top is reported
- Interim title experiments based on menu screenshots (superseded in 0.7.0)

## 0.5.0
- Syntax highlighting via shiki (dark-plus / light-plus following the active
  theme kind, live re-render on theme switch, plain fallback)
- Menus mirrored from the built-in markdown preview manifest: two tab-row
  buttons (to-the-side with Alt-variant, reopen-as), tab context `1_open`,
  explorer context; preview opens in active group or beside

## 0.4.0
- Renderer replaced with markdown-it: full markdown (tables, links, images,
  blockquotes, nested lists), task-list plugin, `data-line` injection from
  token maps
- Modern theme-aware prose styling (72ch measure, hairlines, rounded code
  blocks); selection/hover highlight limited to the task row
- Strikethrough on checked items removed (kept subtle dimming)

## 0.3.0
- Preview panel mode beside the source (closable independently, one panel
  per document, auto-close with the source document); shared wiring with the
  custom editor

## 0.2.0
- Bidirectional scroll sync with echo suppression
- Removed strikethrough on checked items

## 0.1.0
- Custom text editor: rendered checklist, multi-select parallel toggle,
  surgical single-character mirroring into the source
