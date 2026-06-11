# Changelog

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
