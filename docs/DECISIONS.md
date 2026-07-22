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
and `Workbench:` title prefix all mirror the built-in markdown preview so
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
The webview script and styles ship as plain media assets
(`media/webview.js` / `media/webview.css`), loaded into a slim HTML skeleton
via `asWebviewUri` (see #23 for the extraction history). No framework, no
build step for the view. State lives in the source document; the webview is
re-rendered from scratch on every change.

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

Tables wider than the breakout cap (0.24.6) scroll element-wise inside a
`.table-wrap.scrolls` wrapper. An overflow container in any axis becomes the
scrollport for `position: sticky`, so native sticky is inert against the
window scroll there - 0.24.6 shipped that as a documented tradeoff, 0.24.7
lifted it: for scrolls wrappers the pin is emulated by translating the thead
with the window scroll (rAF-throttled, clamped to the table's bottom edge).
The thead stays in-flow, which keeps it column-aligned during horizontal
wrapper scrolling for free. Tables that fit the viewport keep native sticky.

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

**Entry-export trap (found 0.24.1, broken since 0.23.0):** Rolldown's CJS
output appends its cross-chunk runtime helpers (`__esmMin` etc.) to the
*entry's* exports object after the entry body runs; the lazy chunks fetch
them via `require('./extension.cjs')` when they load. An entry that does
`module.exports = {...}` replaces that object, the helpers vanish, every
Shiki language/theme chunk dies on load - and `initHighlighter` catches the
error and silently falls back to plain code blocks. The entry must only
*extend* its exports (`Object.assign(module.exports, ...)`); the inner
modules are wrapped by Rolldown and may keep reassigning. The trap
disappears structurally with the TypeScript/ESM migration.

**Shiki engine: JavaScript regex instead of Oniguruma WASM (0.24.1):** a
second trap sat under the first one, masked by it. Shiki's default engine
loads its WASM binary through a template-literal `import('shiki/wasm')`
that no bundler can analyze statically; the bare specifier survives
bundling, resolves in the repo (node_modules next to dist/) and dies in
the installed vsix - which ships no node_modules - with
ERR_MODULE_NOT_FOUND and the same silent fallback. The highlighter now
uses `createJavaScriptRegexEngine()` (`shiki/engine/javascript`), which
bundles like ordinary JS and carries all 18 shipped grammars. The tsdown
`alwaysBundle` entry is the regex `/^shiki/`, not the string `'shiki'` -
the string matches only the bare package and would leave the engine
subpath external (exactly how it failed).

Both traps are invisible to the unit tests (they run against `src/`), so
`scripts/bundle-smoke.js` guards them permanently: it copies `dist/` to a
temp directory outside the repo (no node_modules on Node's upward search
path - the installed topology), drives the bundle through the vscode mock
and asserts real Shiki output for every one of the 18 bundled languages
(inline colors, no `language-*` fallback). It runs as its own step right
after the bundle in `build.ps1`, i.e. in CI's Package task.

## 22. Out of scope (deliberate, revisit on demand)
Relative local images (`asWebviewUri`/`localResourceRoots` rewriting),
Mermaid/Math, exact user theme for Shiki, strict CSP (the view renders the
user's own files with `html: true` and scripts enabled), a Chrome minimap
extension (explored, shelved). Anchor links + heading slugs left this list in
0.31.0 (#31).

## 23. Workbench naming, module split, webview asset extraction (0.24.0)
Three coordinated structural changes, no behavior change:

- **Naming.** The user-visible view labels follow the product name: command
  titles (`Open Workbench` / `... to the Side` / `Toggle Workbench` /
  `Open as Workbench`), the tab/panel title prefix (`Workbench:`, now a single
  constant `TAB_TITLE_PREFIX` instead of two literals) and the settings
  descriptions ("... of the workbench views"). Deliberately kept as
  `checklist`: the Marketplace `keywords` search term, the README/CHANGELOG
  text that describes the checkbox feature, and the `media/checklist-*.svg`
  icon files (renaming them would only churn `package.json` for no gain). The
  `media/checklist-*.svg` files were later retired in 0.29.0 (tab-action icons
  unified into the `workbench`/`source` set); the `checklist` keyword and
  feature text stay.
- **Module split.** The 1100-line `extension.js` was cut along its existing
  seams into `render.js` (markdown/Shiki), `views.js` (view machinery +
  toggles + webview skeleton) and a slim `extension.js` (activation +
  command wiring + preview orchestration); `editing.js` moved under `src/`
  unchanged. No new abstractions - the boundaries follow the functions that
  were already there. `_internal` test exports moved with their code; the
  test `loadFresh` helper now drops the whole `src/` graph so each module
  re-binds the `vscode` mock consistently.
- **Webview asset extraction.** The inline HTML template (~500 lines of
  CSS/JS in a string) became real files `media/webview.js` /
  `media/webview.css`, loaded via `webview.asWebviewUri` under a CSP with
  `localResourceRoots` scoped to `media/`. The CSP nonce-gates the script;
  `style-src` keeps `'unsafe-inline'` because Shiki delivers its token colors
  as inline `style` attributes (a strict style policy blanks all highlighted
  code, just as the built-in preview allows inline styles for the same
  reason), and `img-src` keeps `http:` so remote images load exactly as they
  did when the inline view had no CSP at all. The assets ship in the vsix
  (`.vscodeignore`) but are not part of the host bundle - they run in the
  webview. Benefits: editable/lintable files with real syntax highlighting,
  a defined CSP, and a simpler test path (the DOM mock loads `webview.js`
  directly instead of regex-extracting it from the HTML). `getWebviewHtml`
  is now a skeleton; a smoke test asserts it carries the CSP, the script
  nonce and both asset URIs.

## 24. Outline letters live in the stylesheet, never in the source
CommonMark ordered markers are digits with `.` or `)` - letter markers
(`a.`, `b.`) and compound markers (`1.a)`) are not markdown and are never
written into the source. The classic Word-outline look (decimal /
lower-alpha / lower-roman by depth, repeating from level 4) comes entirely
from `media/webview.css` via `ol`-depth selectors; the descendant
combinator counts only `ol` levels, so interleaved `ul` levels do not
advance the cycle. The source stays portable (`1.` / `2.` on every level,
each level renumbering for itself) and renders as `a.` / `b.` on level 2 in
this preview only. The editing commands enforce the same rule: Enter, Tab
and Shift+Tab only ever write digit markers and preserve the delimiter.

## 25. Editing-oriented task rendering, compound items first-class
Two deliberate deviations from the built-in preview, both in favor of the
edit-toggle loop, plus one syntax decision:

- **Ordered task items keep their visible number.** The built-in hides the
  marker on every task item; the hidden `ol` markers keep counting, so
  mixed lists show visible numbering gaps. Marker suppression (and the
  negative margin that reclaims the bullet's space) is limited to
  `ul > li.task`; `ol > li.task` keeps its number/outline marker (#24)
  with the checkbox at the start of the content.
- **Empty task items render as task rows.** `[ ]`/`[x]` without a label is
  literal text in the built-in. Every fresh Enter-continuation line looks
  exactly like that, so the view flickered between task row and literal
  text while typing. An empty label renders as a clickable task row.
- **Compound items are first-class.** `1. - [ ] foo` (a numbered item whose
  content is a one-line bullet task list) is valid CommonMark and renders
  as a task row; toggle (CHECKBOX_RE: (marker, whitespace) x2, box) and
  Enter continuation (leading marker follows its rule, the rest of the
  prefix continues verbatim with a fresh box) treat it as equivalent
  syntax. Render and toggle path classify the same lines as tasks.

## 26. Configurable custom (non-CommonMark) list markers (0.28.0)
Opt-in via an explicit flag `lists.extraMarkersEnabled` (default false) plus a
non-empty `lists.extraMarkers`. The flag was added after the first cut keyed
recognition off "list non-empty" alone, which gave no clean way to keep a marker
set configured but inactive. A closed set of marker families the editor may
additionally recognize as list items: symbol bullets (`->`, `→`, `❯`, repeat
like dashes), lettered markers (`a)` / `A)` / `a.` / `A.` / `a:` / `A:`,
counting up with the delimiter preserved) and digit markers with a delimiter
(`1)`, `1:`). `numericMarker` accepts `:` as a delimiter so `1:` counts like a
number (native `.`/`)` paths are untouched). LIST_ITEM_RE (native markers) is
never touched; recognition goes through a matcher built from the config and
cached, rebuilt on change, so the native paths and the default-off config keep
the existing behavior exactly.

**Shared renumber machinery.** Tab/Shift+Tab/Enter renumbering was generalized
from numeric-only to any countable family. `renumberSiblingsBelow` became
`resequenceSiblingsBelow`, which advances a `startBullet` per sibling via
`advanceMarker` (numbers and letters count, the delimiter is preserved; symbols
never count and end the family match, exactly as a delimiter change did before).
`markerFamily`/`sameFamily`/`firstOfFamily`/`seedBullet` express the family
logic; the Tab/Shift+Tab paths use them for both the moved item and the
left-behind/target runs, so a custom sequence closes its gap and joins the
target level just like a numeric one. A symbol item keeps its bullet on Tab
(symbols repeat). Only the marker token is rewritten, so a multi-space gap after
it is preserved.

- **Letter sequence is a prepend-z overflow, not base-26 carry.** `z) -> za)`,
  `za) -> zb)` (deliberately, per the spec), upper-case kept separate. Letter
  runs are bounded to two characters so ordinary prose (`word) ...`) is not
  mistaken for a list.
- **Prose false positives are accepted, not fixed.** A non-CommonMark marker
  cannot be distinguished from a line that merely starts the same way: with
  `a)` / `a:` enabled, `ok) go` or `is: this` are recognized as list items, and
  continuation / indentation then act on them. The two-character bound limits
  it to short tokens but cannot eliminate 1-2 letter collisions. This is the
  cost of opting in; the user enables the families deliberately. Kept the bound
  at two characters - more digits would only add prose collisions for the
  near-zero value of `aaa)` lists.
- **Local per-level scheme, not path markers.** Indenting cycles
  `lists.markerCycle` by depth (`1.` → `a)` → `1)` → `a.`), and changing the
  first item's marker type pulls only the same-level siblings (Lesart A,
  local) - never children or parents, and never a composed path marker
  (`1.a)`). Rejected the path-marker / full-cascade reading: it would write
  non-portable compound markers into the source and couple levels that the
  user edits independently. The local rule mirrors `resequenceSiblingsBelow`
  (siblings of one level only) and keeps each level's marker a single token.
- **Preview rendering is opt-in and deliberately non-portable.**
  `lists.renderExtraMarkers` (off by default, only effective with
  `extraMarkers` set) turns custom-marker paragraphs into real ol/ul lists in
  this workbench's preview, with the same outline styling as native lists.
  These markers are **not** CommonMark: a document written with them renders
  as a list only here with the setting on; on GitHub/GitLab/Forgejo, and with
  the setting off, it stays plain text. Intended for working notes where the
  authoring affordances matter more than cross-renderer fidelity. Nesting
  renders cleanly when every level uses a non-CommonMark marker; levels
  written with native markers (`1.`, `1)`) are parsed as native lists by
  CommonMark and stay separate (a documented best-effort limit). The default
  `markerCycle` (`1.` → `a)` → `1)` → `a.`) mixes native and custom levels on
  purpose, so the preview keeps the Word-outline look; for cleanly nested
  custom-list rendering, set an all-custom cycle (e.g. `a)` → `A)` → `a.`).

## 27. Column stops for markerless lines; smart forward delete (0.28.0)

- **Column stops belong on continuation lines, not on list items.** A first
  attempt (`indent.respectExistingStops`) let Tab snap *list items* onto nearby
  indentation columns - but a list item's Tab/Shift+Tab is structural (move a
  level in/out, renumber, the 0b join), and snapping it onto a foreign deeper
  indentation broke that (`2. zwei` jumping under an unrelated deeper line). So
  that setting was dropped entirely and list-item indentation is back to exactly
  the native structural behavior. The column-stop idea moved to where it fits:
  **markerless lines** (`execListItem` returns null - wrapped/hung continuation
  lines or plain text). On those, Tab/Shift+Tab snap the leading whitespace onto
  the next column stop: column 0, the indent/content columns of nearby list
  items, the word starts of nearby lines, and the editor's `tabSize` multiples
  (so a forward step always exists). This is plain indentation behavior with no
  risk to the structural path, so it is always on; only the scan window is
  configurable (`indent.continuationStopRadius`, default 5). Stops are computed
  in visual columns (tabs expanded) and re-rendered per the editor's
  `insertSpaces`/`tabSize`. A line that matches a custom marker
  (docs/DECISIONS.md #26) counts as a list item, not a continuation line.
  A selection of more than one line moves as a block by one common delta instead
  of each line snapping independently (which would drift the block apart). This
  applies to the WHOLE multi-line selection - list items and markerless lines
  together - not just markerless runs: list items at different marker widths
  (`8.` vs `10.`) used to reindent by their own `indentUnitFor` and drift, now
  they shift by the same delta. Markers are NOT renumbered in a multi-line
  selection ("multi-line selections only reindent", #25/#26); only a single item
  nests and renumbers structurally. The topmost line is the reference and snaps
  to its next stop, that delta applies to all, and a left shift is capped by the
  flattest line so nothing crosses column 0. The block's own lines are excluded
  from each other's stop computation so they don't anchor each other. For
  performance the block reads each line's indentation once and builds the stop
  set exactly once per keystroke (for the reference line), rather than
  recomputing it implicitly per line - a deliberate once-per-block computation.
- **Content-line joins on Ctrl+Delete / Ctrl+Backspace.** Two mirror-image
  commands share one pure seam helper (`joinSeam`): it replaces everything from
  the left line's last visible character through the right line's first
  non-whitespace character - trailing whitespace, the line break(s), any
  whitespace-only lines in between, and the right side's leading whitespace -
  with `editing.joinSpaces` spaces (shared by both directions; 0 = no space) -
  but only when both sides have visible content. So the seam never ends up with
  a double space, and joining onto or from an empty/whitespace-only line adds no
  leading/trailing space (the texts meet directly). The forward join (cursor at
  the end of visible content) pulls in the next line that has content; the
  backward join (cursor at the start of visible content) appends to the previous
  one. An empty/whitespace-only line is a valid trigger for both - the cursor
  counts as being at the line's end (forward) and start (backward), so a join
  works from a blank line between paragraphs. Both reach across blank lines
  deliberately - "aggressive": at a line end you always get the next content,
  indented or not. Each direction has its own `enabled` flag (via the keybinding
  when-clause) and its own `fallbackCommand`, run with `executeCommand` (not key
  resolution) so binding the fallback to the same key cannot recurse. Replaced
  the earlier single `editing.smartForwardDelete` (fixed one space, hard
  `deleteWordRight` fallback, only an adjacent indented line, forward only).
- **Manual native renumber follows the input (Variant A).** Changing a numbered
  marker by hand makes the following same-level siblings continue from it
  (`1. a / 5. b / 6. c`); the sequence is never auto-reset to 1, so a list may
  start at any number. Driven by the `onDidChangeTextDocument` listener that
  already carries the custom type-propagation, both behind the shared
  `propagating` re-entrancy guard: our own Enter/Tab/Shift+Tab edits run with the
  guard set (`suppressedEdit`), so the structural renumber and the manual pass
  never collide (the cause of the messy numbering @ww3d saw on tab-out-then-in).
  The manual pass fires only when the edit actually touched the marker region
  (the change's start column is within indent+marker), so editing the body of a
  line in an intentionally non-sequential list does not reflow it - the one
  place where "sequence follows input" must not over-reach. Custom markers keep
  their first-of-level type propagation (#26); native numbers continue from any
  edited item.

## 28. Preview text selectable; task toggle gated at click time (0.30.0)
The webview body carried a global `user-select: none` whose only job was to
stop a drag on a `.task-row` from ending as a text selection instead of a
toggle - the toggle hangs off the whole row, not just the checkbox. The side
effect was that no preview text at all (prose, code, tables) could be selected
or copied, unlike the built-in preview. Variant B: `body` is `user-select:
text`; `none` is kept only where it protects an interaction - the minimap
(`#minimap`) and the checkbox inputs themselves (`.task-row
input[type=checkbox]`, `input.cell-task`, so a drag starting on the box toggles
rather than selecting). The toggle decision moves into the click handler,
geometric/state-based instead of a CSS lock: a click directly on a checkbox
input always toggles; a bare click in the row/label or in a single-checkbox
table cell toggles only when `window.getSelection().toString()` is empty AND
`e.detail === 1` (so a drag-out selection or a double-click-to-select-a-word
does not toggle). The gate is a pure helper (`canToggleFromBareClick`) so it is
unit-testable without click simulation. The batch gestures (Shift = range,
Ctrl/Meta = membership) are re-scoped to the checkbox only, never the label:
otherwise Shift+click in selectable label text would collide with native text
range-selection. The existing parallel multi-toggle (`.task-row.selected` ->
toggle the whole selection) is unchanged, only checkbox-triggered. Rejected:
keeping the CSS lock with an opt-out, and a `taskSelection: row | checkbox`
setting - deferred to a follow-up only if on-device use proves the row-wide
batch gesture is missed, rather than added on suspicion. The drag-end-on-row
edge (a drag that selects but releases over the row) starts with the simple
`getSelection()` check; a `mousedown`-range comparison is added only on a
demonstrated misfire.

## 29. In-preview find: native `enableFindWidget` first (0.30.0)
Both preview modes are `WebviewPanel` (custom editor via
`resolveCustomTextEditor`, side preview via `createWebviewPanel`), so VS Code's
built-in find widget is available for free: `enableFindWidget: true` on the
custom editor's `webviewOptions` and as the side panel's fourth option. Ctrl+F
on a focused webview is wired by VS Code automatically; `media/webview.js`
intercepts only `Escape` (clear selection), never Ctrl+F, so there is no
handler conflict and no keybinding to register. This buys highlight,
next/previous, match count and case/regex/whole-word, VS-Code-consistent. It
searches the rendered DOM text, not the markdown source (no hit on raw
`#`/`-`), consistent with the copy decision (#28). A custom in-preview search
(minimap match markers on the rail, task filter, own highlight DOM) is NOT
built now - it is evaluated as a follow-up only when a concrete limit of the
native widget bites, with demonstrated need rather than on suspicion.

## 30. Preview readability is configurable; defaults reproduce #28 (0.30.0)
#28 made selection vs. toggle a fixed choice. Rather than wait for on-device
use to decide, three settings expose the knobs, with defaults that reproduce
#28 byte-for-byte (no migration). The flags ride the existing `type:'config'`
message (`configuredViewConfig` in `src/views.js`, defensive defaults like the
minimap), the webview reflects them as body classes the stylesheet keys off,
and the click handler reads them.
- `preview.textSelection` (default `true`): off restores the pre-#15 global
  `user-select: none` (`body.mw-no-text-select`) and the bare click toggles
  ungated - a `bareClickToggles(enabled, sel, detail)` wrapper collapses the
  gate to "always" when selection is off and otherwise defers to
  `canToggleFromBareClick`.
- `preview.taskBatchSelect` (`checkbox` default / `row`): where Shift/Ctrl
  batch fires. `checkbox` keeps #28's checkbox-only batch; `row` routes the
  gesture through the label too.
- `preview.taskRowTextCursor` (default `false`): cosmetic caret on the row,
  scoped to `.task-row` (the checkbox keeps the pointer hand via a
  higher-specificity rule). Deliberately gated on `textSelection === true` - a
  text caret on unselectable text would lie about what a drag does.

`textSelection` x `taskBatchSelect` are orthogonal:

| textSelection | taskBatchSelect | behavior                                            |
|---------------|-----------------|-----------------------------------------------------|
| true          | checkbox        | #28 default (selectable, batch on the checkbox)     |
| true          | row             | selectable text, batch on the whole row             |
| false         | checkbox        | not selectable, row toggles, batch only on checkbox |
| false         | row             | exactly pre-#15 (not selectable, row toggles+batch) |

The `true/row` cell is a deliberate collision: routing batch through the label
means Shift+click in the label no longer extends a text selection. It is opt-in
for users who want the row-wide batch gesture and accept the trade. The cursor
knob only applies while `textSelection` is on (the false rows keep the pointer
hand regardless). Single-checkbox table cells stay out of the cursor scope for
now - only `.task-row` follows the setting.

## 31. Heading anchors + in-document TOC navigation (inline slugger, no dependency)
GitHub-style tables of contents (`[Text](#slug)`) dead-ended in the preview:
`render.js` emitted no heading `id`s, so a hash link had no target, and even a
resolvable `#hash` does not self-navigate inside a VS Code webview. Both sides
are fixed. A markdown-it core rule (`heading-anchors`, styled like
`taskListPlugin`/`injectLineNumbers`) sets an `id` on every `heading_open` from
the visible text of its `inline` token (concatenated `text` + `code_inline`
children; emphasis/link markup carries no content and does not contribute). The
webview's delegated click handler gains a branch, ahead of the generic
`closest('a')` early-return, that intercepts `a[href^="#"]` and resolves the
target with `content.querySelector('#' + CSS.escape(decodeURIComponent(hash)))`,
scoped to the content root so the webview skeleton ids (`content`, `minimap`,
...) can never win the lookup (a heading `# Content` slugs to `content`); it
then scrolls via the existing `absTop` helper, and the scroll listener reports
the new position so the source editor follows. Guards: an empty hash (`href="#"`,
an invalid selector) and a malformed percent-escape (`decodeURIComponent` throws
on a raw HTML anchor) both fall back to a no-op / the literal hash. A missing
target is a no-op (no error, no fallthrough to the task-toggle path).

**Inline slugger, not a dependency.** The slug rule follows `github-slugger` -
lowercase, strip everything that is not a Unicode letter, mark, decimal/letter
number or connector punctuation, hyphen or space, then spaces to hyphens;
duplicates get `-1`, `-2`, ... via the same occurrences bookkeeping. It is ~15 lines and
was implemented inline rather than pulling in `github-slugger` or
`markdown-it-anchor`: the repo keeps its runtime deps deliberately minimal, and
every runtime dep has to survive the vsix bundling topology (the Shiki
WASM/engine history, #21, and `scripts/bundle-smoke.js`). `github-slugger` ships
its character set as a generated explicit character-class; the compact Unicode
property-escape form (`/[^\p{L}\p{M}\p{Nd}\p{Nl}\p{Pc}\- ]/gu`) matches it for
the realistic cases but is deliberately **not** bitwise identical (full parity
needs the generated table, which contradicts the dep-free/compact choice).
Divergences, all verified against `github-slugger` 2.0.0 by a full-codepoint
sweep and all obscure in real headings:

- `\p{Nd}\p{Nl}`, not `\p{N}`: the broad `\p{N}` also keeps `\p{No}`
  (superscripts like `m^2`, fractions `1/2`, circled digits `(1)`), which
  `github-slugger` strips. Using it verbatim was the first-cut bug (found in
  review); `\p{Nd}` (decimal) plus `\p{Nl}` (letter numbers, e.g. Roman
  numerals, which `github-slugger` keeps) reproduces the number handling.
- Unicode version: the property escapes track the Node/ICU build,
  `github-slugger` a pinned data release, so a code point assigned in a newer
  Unicode version can classify differently (this form keeps it, the pinned
  table does not).
- 130 enclosed alphanumeric Latin letters (`\p{So}`) that `github-slugger`
  keeps and this form strips: 52 circled (U+24B6..U+24E9) plus three 26-letter
  blocks - squared, negative-circled, negative-squared (U+1F130..U+1F149,
  U+1F150..U+1F169, U+1F170..U+1F189). Adding `\p{So}` wholesale would over-keep
  (emoji, symbols), so this obscure set stays stripped.

The duplicate counter lives in the rule run, never at module scope: the `md`
instance is shared across renders, so module state would leak suffixes between
documents.

**Scope.** Only internal `#`-anchors are handled. Cross-file links
(`./other.md#x`) and external `http(s)://` links keep the browser default,
unchanged. No hover permalink anchors on headings.

## 32. TOC navigation: scroll-spy base, sticky rail, FAB/overlay fallback
Building on the heading anchors (#31), the preview gains a visible table of
contents. Design round 2026-07-22; this is PR 1 of 2 (the breadcrumb +
sticky-scroll stack is the follow-up #44, deliberately not built here).

**Scroll-spy is a shared base, not TOC-internal.** A small self-contained
`scrollSpy` module in `media/webview.js` tracks the active heading (the last one
scrolled past an activation line near the top) and its ancestor chain
(h1..h6), and notifies subscribers on change. The TOC rail/FAB is the first
consumer; the follow-up breadcrumb + sticky-scroll (#44) subscribes to the same
signal instead of re-deriving it. An `IntersectionObserver` on the headings
drives the "a heading crossed the activation line" trigger; the active index is
decided by geometry (pure `activeHeadingIndex` / `ancestorChain`, unit-tested)
so it stays correct when several or no headings are on screen, and the existing
scroll rAF pumps the same `update()` so the highlight tracks every frame. Cached
heading tops are document coordinates (scroll-invariant), refreshed only on
reflow (resize / ResizeObserver), not per scroll.

**Rail side is derived, not configured (no config cross-product).** The rail
takes the side opposite `markdownWorkbench.minimap.side` (minimap right -> TOC
left); the FAB sits on the same side as the rail. A dedicated `toc.side` setting
was rejected: it would let the user place the rail and the minimap on the same
side and invent overlap collisions for no gain. The rail's width is reserved as
body padding (like the minimap), so the centered content clears it instead of
being overlapped.

**Rail vs. FAB is content-relative, not a fixed breakpoint.** The rail shows
only when the viewport can hold the content column plus the rail reserve plus
the opposite-side rail/gutter, side by side (`railFits`, pure/unit-tested);
otherwise a floating button opens the same TOC in an overlay (close by clicking
outside or Escape). A fixed px breakpoint would be wrong in the `narrow`
(`72ch`) width mode, where the content column is font-relative. The threshold is
live via a `ResizeObserver` (content-box changes such as image loads or the
minimap padding can flip it without a window resize). `markdownWorkbench.toc.mode`
(`auto` default / `rail` / `fab`) forces one mode, which also makes the switch
deterministic and testable; `markdownWorkbench.toc.enabled` (default `true`)
turns the feature off. Both flags ride the existing `config` message
(`configuredViewConfig`) with the same defensive defaults as the minimap
(undefined must never disable the TOC or force a mode - regression 0.21.1).

**Active-section behavior.** The active entry is highlighted, its ancestors are
marked on the path, only the active section is expanded (siblings collapse), and
the active entry is kept in view (`scrollIntoView({block:'nearest'})`). A TOC
click scrolls smoothly to the heading through the shared anchor mechanism
(`navigateToHash`), while the internal content anchors keep their instant scroll
so the source editor mirrors the final position at once. Headings gained a
`scroll-margin-top` (a CSS var the #44 sticky bars will bump) so anchor jumps and
the activation line clear the top edge.

**Not verified in the sandbox:** the live rail/FAB rendering, the overlay
interaction and the rail-fit switch in a real webview - the headless DOM tests
cover the pure decisions (active index, ancestor chain, tree, rail-fit
threshold), the config resolution and the class/message wiring; visual layout
and pointer interaction need manual verification.

## 33. Breadcrumb + sticky-scroll stack (top bars, scroll-spy consumers)
The follow-up to #32 (issue #44): two navigation bars pinned to the top of the
preview, both subscribing to the same `scrollSpy.onChange` signal as the TOC -
no scroll-spy change, only new consumers. Design round 2026-07-22; both features
run in parallel deliberately (the breadcrumb navigates, the sticky stack shows
context - exactly as VS Code ships both at once), the breadcrumb above the stack,
with separate toggles instead of an exclusive switch.

**Overlay stack, not `position: sticky` on the content headings.** The stack is
a separate fixed `#sticky-scroll` element rebuilt from the active chain on each
emit (like the minimap clones content, and the TOC rail derives from the same
signal), not the real content headings made `position: sticky`. Only the
*ancestors* of the current position should pin, and their `top` offsets stack
cumulatively - neither is expressible in static CSS (which heading is an ancestor
changes with scroll), so it would need JS to mutate heading `top`/`z-index` per
scroll anyway. Mutating the content headings' positioning would also move them
out of normal flow and break the scroll-spy/anchor geometry, which relies on
heading tops being stable document coordinates (#32). The overlay keeps that
geometry untouched and swaps in place when the active section changes (it does
not animate the push-out of an outgoing header - a deliberate simplification).

**Breadcrumb reserves a constant top padding; the stack overlays.** The
breadcrumb is a constant-height bar, so `body.has-breadcrumb` reserves its
measured height (`--breadcrumb-height`) as top padding - content clears it with
no per-scroll reflow. The sticky stack overlays content without reserving space
(exactly like the editor sticky scroll covers the lines it stands in for), so it
can grow and shrink with the chain depth without shifting the layout. Above the
first heading (`active = -1`, empty chain) the breadcrumb shows a single *root
segment* rather than nothing (owner decision, mirroring the file segment in VS
Code's editor breadcrumb): its label is the document's leading H1 when present,
else the fallback `Document`; it carries no sibling picker and its click scrolls
to the top. The sticky stack stays hidden there (empty chain). The state is
deterministic through the `update(true)` force-emit from `rebuildToc`, the same
mechanism #32 uses for its initial state; the constant bar height is unchanged, so
there is still no scroll reflow.

**Segment click = navigate + pick (the VS Code breadcrumb gesture).** A
breadcrumb segment both scrolls to its heading (smooth, via the shared
`navigateToHash`) and opens a picker of its sibling headings - those at the same
level under the same parent. `siblingHeadings(levels, index)` is a pure function
(unit-tested): walking outward from the segment, a strictly shallower heading is
the parent boundary and ends the run, deeper headings (children of a sibling) are
skipped, equal-level headings are siblings. It handles level jumps (an h4 with no
h2/h3 above bounds on the nearest shallower heading) and the single-child case
(returns just itself). A picker selection navigates; Escape and an outside click
close it. A rebuild (the chain changed under an open picker) keeps the picker
open only while its heading is still on the chain, otherwise closes it.

**`--toc-scroll-margin` is raised to the bars' height; z-index order.** The var
#32 put on the headings is now set to the measured breadcrumb + stack height plus
a small gap (`topBarsScrollMargin`, pure/unit-tested; the stylesheet default
`1.2em` is reproduced when both bars are hidden), and `navigateToHash` subtracts
the same offset so an anchor jump lands *below* the bars, not behind them (the
sticky-scroll dynamic-height caveat is inherent and shared with VS Code: the
offset uses the current stack height, not the target section's). The bars fill
the content region only, clearing the minimap and the TOC rail through the same
per-side reserves as the body padding (each side set independently; the rail is
always opposite the minimap, so no side carries both). z-index top to bottom:
breadcrumb dropdown (8) > TOC overlay (7) > FAB/backdrop (6) > minimap/TOC rail
(5) > top bars (4) > sticky table header (2) > content. The bars sit below the
rails on purpose - they never overlap horizontally, so at a rounding edge the
rail wins rather than a bar covering it.

**Config: two independent flags, defensive defaults.** `breadcrumb.enabled` and
`stickyScroll.enabled` (both default `true`) ride the existing `config` message
(`configuredViewConfig` in `src/views.js`) with the same defensive handling as
the minimap/TOC - undefined (schema not yet active after an in-place update) must
never disable a bar, and the webview merges over its own defaults too
(regression 0.21.1). A live settings toggle force-emits the scroll-spy
(`scrollSpy.update(true)`) so it applies at once, like the TOC's
`updateTocLayout`, instead of waiting for the next active-heading change. Either
bar can be off alone. The controls carry
`tabindex="-1"` like the FAB and the other preview controls (a11y is a separate
task, PR #45); theming is via VS Code theme tokens like the TOC/minimap.

**Scroll performance: cheap per-frame, work only on real change (review 3).** A
fast scrollbar/minimap drag changes the active heading almost every frame, so
the per-emit work has to be minimal. The measures, in order of impact:

- **Rebuild only on real change.** `updateTopBars` returns early unless the chain,
  the heading set (a re-render) or a structural generation (config / resize)
  actually changed - a force-emit or a scroll that keeps the active heading costs
  nothing. The comparison is allocation-free (reused index arrays).
- **No forced layout per frame.** Reading a height forces synchronous layout, so
  the breadcrumb (constant one line) is measured once and the sticky stack only
  when its row count changes - not on same-depth crossings. (A same-depth chain
  whose levels differ keeps the cached height; the residual few-px error only
  feeds the belt-and-suspenders scroll-margin, never the marking.)
- **No per-frame style invalidation.** `--toc-scroll-margin` is consumed by every
  heading (`scroll-margin-top`), so writing it each frame would recalc every
  heading's style; it and `--breadcrumb-height` are written only when their value
  changes.
- **Incremental DOM.** The bars reconcile their `<a>` children in place (reuse
  nodes, update only changed text/attrs) instead of an `innerHTML` reparse;
  separators are pure CSS (`.breadcrumb-seg::before`), so there are no separator
  nodes to manage. `contain: layout paint` isolates a bar's relayout from the page.
- **TOC highlight as a delta.** `applyTocActive` was O(headings) per change (it
  swept every link). It now toggles only the links whose active/in-path/collapsed
  state changed - O(path depth) - with the tree built collapsed by default
  (`renderTocInto`), so a large document's TOC no longer pays for every entry on
  every active-heading change. `#toc` also gets `contain: layout paint` (review 4:
  containment for the rail, not just the bars), isolating the rail's relayout
  from the page.
- **Reveal coalesced and conditional (review 4).** Keeping the active entry
  visible used a synchronous `scrollIntoView` on every change - a per-frame forced
  reflow in the rail during a fast drag. It is now coalesced into one rAF
  (separate from the class-toggle writes, so no read follows a write) and scrolls
  only when the entry is actually outside the panel viewport; an active entry that
  stays in view during a drag costs no scroll at all.

**Activation line includes the top-bar inset (off-by-one fix, review 3).**
`navigateToHash` lands a target at `scrollY + topBarsOffset` (just below the
bars), but the scroll-spy's activation line was still `scrollY + 8`, so once the
bars were taller than 8px the target sat *below* the line and the heading above
it stayed marked active (owner saw it after a TOC click). The scroll-spy gained a
generic `setTopInset(px)`; the bars set it to their measured height, and the
activation line is now `topInset + ACTIVATION_OFFSET`. With the bars hidden
(inset 0) it reproduces the #45 behavior exactly. This is the one minimal
scroll-spy extension the #44 scope allowed for the stack ("minimal erweitern
statt duplizieren"): a fixed top inset is a general concept, not top-bars-specific.

**Not verified in the sandbox:** the live sticky pinning while scrolling, the
picker rendering/positioning, the anchor-clearing offset, and the *frame-time*
of the scroll path in a real webview cannot be measured here (no VS Code webview
in the sandbox). The headless DOM tests cover the pure decisions (sibling
grouping, scroll margin, active index), the class/config wiring, the
scroll-driven chain, the dropdown open/close, the activation-inset marking, and
the reduced work (the sticky stack is measured once and the margin var written
once across same-depth crossings); the actual rendering, pointer interaction and
in-browser frame profiling need manual verification.

## 34. Preview panels restore after a restart via a serializer (#47)
WebviewPanels are not restored across a VS Code restart unless the extension
registers a `WebviewPanelSerializer` for the viewType and persists enough state
to rebuild them. Without one VS Code reopens the split editor group but leaves
the preview tab empty (the panel is discarded). Found by the owner's manual test
of PR #46; a pre-existing gap, taken in the same PR.

- **Only the WebviewPanel preview mode needs it.** The custom editor mode
  (`markdownWorkbench.editor`) is restored automatically - VS Code re-resolves
  registered custom editors for their document on restart, so
  `resolveCustomTextEditor` runs again and rebuilds the view. The side/active
  preview panel (`markdownWorkbench.preview`) has no such machinery and needs the
  serializer plus `onWebviewPanel:markdownWorkbench.preview` in `activationEvents`
  so the extension activates to deserialize it.
- **State is the document URI, persisted webview-side.** VS Code only persists
  what the webview writes via `setState`, so the document URI rides the `config`
  message (`views.js`) and the webview stores it (`vscode.setState`). The
  serializer's `deserializeWebviewPanel(panel, state)` reads `state.documentUri`,
  reopens the document and re-wires the panel through the **same**
  `attachPreviewPanel` path as a fresh open (icon, previews-map bookkeeping,
  dispose/active tracking, `wireWebview`) - the restore path is not a duplicate.
- **Edge cases, no swallowed errors.** No persisted state -> dispose the empty
  panel (no dead tab). The document is gone (deleted/renamed since the restart)
  -> `openTextDocument` rejects; log the reason and dispose, never leave a dead
  tab or hide the error. A preview already open for that document (a duplicate
  restored panel) -> keep one, dispose the extra.
- **Scroll position is not restored (deliberate).** Persisting it would mean a
  `setState` in the scroll hot path for a marginal gain; the restored preview
  opens at the top. The issue lists scroll restore as "ideally", not required.

**Not verified in the sandbox:** the actual close/reopen cycle in a real VS Code
needs manual verification; the headless tests cover the serializer registration,
the deserialize wiring, the state roundtrip and every edge branch (no state,
vanished document, duplicate).

## 35. Scroll-sync throttle, IntersectionObserver removal, TOC chevrons (#44 review 5, #48)
The owner's manual test showed the scroll path still stuttered - and the *source
editor* lagged too, which points at the scroll-**sync** path (messaging + host),
not just webview rendering. Plus a new TOC feature (#48).

**Scroll-sync coalesced to ~30Hz with delta gates.** The webview posted a
`scrolled` message every rAF frame (~60Hz), and the host answered with a
`revealRange` each time - IPC + serialization + host work in both directions, per
frame, which a large source file cannot keep up with. Now: the webview posts only
when the fractional line actually changed (delta gate, `scrollPostDecision`,
pure/unit-tested), coalesced to ~30Hz - post immediately once the window elapsed,
else a single trailing post so the final rest position always syncs (last value
wins). The host side is delta-gated too: `revealRange` (webview->editor) and the
`scrollTo` post (editor->webview) are skipped when the line moved less than
`SYNC_LINE_DELTA` (0.25 line) from the last one pushed in that direction (the
suppression window and `lastKnownTopLine` still update on every message). The
structural minimap rewrite (canvas over DOM-clone) is out of scope here and
tracked as #49.

**IntersectionObserver removed (dead path).** The scroll-spy observed every
heading with an `IntersectionObserver` that only called `update()`. Since the rAF
scroll pump already calls `update()` every frame (and render/resize call it too),
the IO was redundant - and on a large document it observed hundreds of nodes and
fired callbacks throughout a drag. It was struck entirely; the single rAF trigger
is what remains.

**TOC chevrons with sticky manual state (#48).** Entries with children get an
expand/collapse twistie. To keep the hot path clean it is a pure CSS `::before`
on the entry (no per-entry node), rotated via `:has(> .toc-sublist:not(.toc-collapsed))`
reading the sibling sublist's state; the click is delegated on the panel (one
listener) and the twistie hit is decided geometrically (`isChevronClick`, an
`offsetX` zone - a heuristic, manually verified) so a click on the label still
navigates. The manual state is **sticky**: two small sets (`tocManualExpanded` /
`tocManualCollapsed`) that the automatic `applyTocActive` delta consults with
O(1) lookups - it never re-expands a manually collapsed branch nor re-collapses a
manually expanded one, so the O(path) delta (DECISIONS #33) is preserved (no
O(headings) sweep). A re-render resets the manual state (fresh tree, like VS
Code's outline).

**Not verified in the sandbox:** the real in-browser frame time of the scroll and
sync paths (webview DevTools + extension-host profiles at a large document) needs
manual measurement; the headless tests prove the reduction in the observable
counts (a same-line frame burst posts once; no IntersectionObserver is
constructed; the host reveal/scrollTo skip sub-threshold changes) and the chevron
behavior (visibility, toggle, sticky both ways, re-render reset, click
separation). The twistie's exact hit zone and rotation are visual - manual check.
