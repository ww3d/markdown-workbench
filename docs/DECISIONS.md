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
re-rendered from scratch on every change. _(Addendum: revised by #50 - the webview is
TypeScript modules under `src/webview/`, bundled by tsdown into `dist/webview.js` and
`dist/webview.css`, so the view has a build step now; still no framework.)_

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
which has _no_ max-width, only `padding: 0 26px`) -> full-bleed breakout
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
_entry's_ exports object after the entry body runs; the lazy chunks fetch
them via `require('./extension.cjs')` when they load. An entry that does
`module.exports = {...}` replaces that object, the helpers vanish, every
Shiki language/theme chunk dies on load - and `initHighlighter` catches the
error and silently falls back to plain code blocks. The entry must only
_extend_ its exports (`Object.assign(module.exports, ...)`); the inner
modules are wrapped by Rolldown and may keep reassigning. The trap
disappears structurally with the TypeScript/ESM migration. _(Addendum: revised by #50 -
the ESM entry exports with `export`, so the trap is gone; the bundle smoke, now
`scripts/bundle-smoke.ts`, still loads the lazy chunks from an isolated directory.)_

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
`scripts/bundle-smoke.cjs` guards them permanently: it copies `dist/` to a
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
  re-binds the `vscode` mock consistently. _(Addendum, state audit 2026-09-29T2304Z: `render.js`, `views.js` and
  `editing.js` were later split into the folders `src/render/`, `src/views/` and
  `src/editing/` (#91); `docs/ARCHITECTURE.md` § "Module layout" holds the current
  layout.)_
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
  attempt (`indent.respectExistingStops`) let Tab snap _list items_ onto nearby
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
| ------------- | --------------- | --------------------------------------------------- |
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
WASM/engine history, #21, and `scripts/bundle-smoke.cjs`). `github-slugger` ships
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
_ancestors_ of the current position should pin, and their `top` offsets stack
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
first heading (`active = -1`, empty chain) the breadcrumb shows a single _root
segment_ rather than nothing (owner decision, mirroring the file segment in VS
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
the same offset so an anchor jump lands _below_ the bars, not behind them
_(Addendum, state audit 2026-09-29T2304Z: superseded by #36 - the bar height is computed from fixed geometry, never
measured, and `--toc-scroll-margin` is a constant written once.)_ (the
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
bars were taller than 8px the target sat _below_ the line and the heading above
it stayed marked active (owner saw it after a TOC click). The scroll-spy gained a
generic `setTopInset(px)`; the bars set it to their measured height, and the
activation line is now `topInset + ACTIVATION_OFFSET`. With the bars hidden
(inset 0) it reproduces the #45 behavior exactly. This is the one minimal
scroll-spy extension the #44 scope allowed for the stack ("minimal erweitern
statt duplizieren"): a fixed top inset is a general concept, not top-bars-specific.

**Not verified in the sandbox:** the live sticky pinning while scrolling, the
picker rendering/positioning, the anchor-clearing offset, and the _frame-time_
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
  message (`views.js`; today `src/views/wire.js`, addendum state audit
  2026-09-29T2304Z) and the webview stores it (`vscode.setState`). The
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
  _(Addendum: revised by #50 - the webview persists its last render with the scroll
  position and shows both at once after a restart; the write is throttled to one
  `setState` per quiet phase, never one per scroll frame.)_

**Not verified in the sandbox:** the actual close/reopen cycle in a real VS Code
needs manual verification; the headless tests cover the serializer registration,
the deserialize wiring, the state roundtrip and every edge branch (no state,
vanished document, duplicate).

## 35. Scroll-sync throttle, IntersectionObserver removal, TOC chevrons (#44 review 5, #48)

The owner's manual test showed the scroll path still stuttered - and the _source
editor_ lagged too, which points at the scroll-**sync** path (messaging + host),
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
expand/collapse twistie. _(Addendum, state audit 2026-09-29T2304Z: superseded by #43 - the twistie is a real
codicon node, and its hit test an exact node check.)_ To keep the hot path clean it is a pure CSS `::before`
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

## 36. Sticky-stack computed height; table-header dock a render-time constant to kill the stutter (#44 review 6/8, rebuilt)

Reintroduced after a revert. The owner bisected a scroll freeze on large documents
to the **sticky-scroll stack** (`stickyScroll.enabled: false` -> smooth) at the
_measuring_ implementation: the stack changed **depth** almost every frame during a
drag, and each depth change ran (a) `getBoundingClientRect` on the stack - a forced
layout right after the DOM mutation - and (b) `setProperty('--toc-scroll-margin')`
on `documentElement`, a var every heading's `scroll-margin` consumes, so a style
recalc over the whole document.

**Compute the height, never measure it.** The bars have fixed heights in the
stylesheet (`#breadcrumb` 28px, `.sticky-row` 22px, `box-sizing: border-box`),
mirrored by `BREADCRUMB_HEIGHT_PX` / `STICKY_ROW_HEIGHT_PX` in `webview.js` (a
contract test asserts they stay in sync) _(Addendum, state audit 2026-09-29T2304Z: no such test exists at
`98f7590` - the tests check the JS constants only, the CSS-against-JS test is carried in
#97.)_ _(Addendum #50: the test exists now - `the bar heights in the stylesheet are the
constants the stack height is computed from (#36)`; the constants live in
`src/webview/top-bars/geometry.ts`.)_ The stack height is `rows x
STICKY_ROW_HEIGHT_PX` - pure arithmetic, so there is **no `getBoundingClientRect`
in the scroll path**. `--toc-scroll-margin` is set once to the maximum stack height
(`breadcrumb + MAX_STICKY_ROWS x row + gap`); navigation subtracts the exact offset
itself, so the coarse constant only catches native hash jumps. The stack is capped
at `MAX_STICKY_ROWS = 5`.

**Table-header pin: a per-scroll variable (the stutter), then a constant.** Round 8
offset the native sticky `thead` below the top bars via `top: var(--sticky-head-top)`,
a custom property updated as the stack depth changed. Even value-gated, a scroll
that crosses section depths rewrites that `:root` property, and it is consumed by
**every** `th` - so on a table-heavy document Chromium invalidates and recomputes
every table header on almost every scroll frame. A headless-Chromium scroll
benchmark (`bench/scroll-bench.js`, real CDP CPU profile) measured it directly: a
240-table page ran ~22ms/frame with the per-scroll write, ~17ms without - matching
the owner's report that disabling the stack made it smooth.

The fix keeps the header docked below the bars but publishes `--sticky-head-top`
as a **constant** **once per render/config**, never on the scroll path
(`publishStickyHeadInset`); the emulated wide-table header takes the same constant
as its `topInset`. The constant is the breadcrumb plus the document's **actual**
maximum heading depth (`maxChainDepth`, capped at `MAX_STICKY_ROWS`), not the hard
cap - so a uniformly nested document (only H1>H2, the common config-reference shape)
reserves exactly its stack height and the header docks **flush**, no gap; a
screenshot in a real Chromium confirmed it. A document that mixes shallow and deep
sections over-reserves only in its shallow sections (a small gap, never an
overlap). Two rejected alternatives, both measured with `bench/scroll-bench.js`: a
fixed max-depth constant left a visible gap on uniform docs; per-table scoping of
the variable (write it on only the table currently at the top) removed the gap but
cost ~28 ms/frame on a fast fling (one scoped invalidation per table crossed)
versus ~18 ms for the render-time constant. Rule reaffirmed: never write a
`documentElement` custom property on the scroll path if a live element consumes it.

**Deliberately excluded** from this rebuild (kept for a later, visually-verified
step): the round-7/8 optics - codicons, chevron rotation, the central click-focus
handling, the sublist animation. This entry is the pure perf structure.

## 37. Sticky-bar separator: a crisp border, not a blurred shadow (#44)

The owner still felt a residual stutter when dragging the scrollbar over a whole
large document (`ww3d/win-util` `anleitung.md`, ~178 KB) - only with the stack
enabled. A CDP trace over a 140-frame full-document drag (real Chromium, paint /
raster / layout / style-recalc via `Tracing`, averaged over 3 runs) isolated the
cause to the **`box-shadow` on the fixed `#sticky-scroll` bar**: a soft `0 2px 6px`
drop shadow whose full-width blur repaints every frame the stack's rows change
during a drag. Measured, over the drag: baseline (shadow) Paint 2054 / Raster 447;
shadow removed Paint 1941 / Raster 416 - **at or below the stack-disabled baseline**
(Paint 1995 / Raster 426). The shadow alone pushed paint above the "sticky off"
smoothness the owner used as the bar.

**A 1px border-bottom already separated the bar** (`border-bottom: 1px solid
var(--border)`); the shadow was a redundant elevation layer on top of it, so the
fix is a pure deletion - no behaviour, no DOM, no scroll-path change, all 369 tests
still green. VS Code's own sticky scroll draws the same crisp border rather than a
drop shadow.

The residual style-recalc gap versus stack-off (Recalc ~125 vs ~88 over 140 frames,
~0.26 ms/frame) is the stack's DOM rebuild as the active section changes mid-drag.
It is sub-perceptual and was **deliberately not** addressed: coalescing the rebuild
during a fast drag would trade the immediate active-heading tracking (an assertion
in nine integration tests) and add stale-bar UX for a fraction of a millisecond per
frame. Paint/raster - the visible jank - is what the shadow removal fixed. Headless
Chromium has no GPU compositor, so the absolute paint numbers are not the on-device
figures; the _relative_ ordering (shadow > border ~= off) is the load-bearing
result and matches the owner's report.

**Measured, not assumed:** a real-browser scroll benchmark (headless Chromium via
CDP, CPU profile + per-frame `getBoundingClientRect` count) drove this - it showed
the earlier "sourceLineAtTop 54%" reading was the profiler attributing forced
layout to the last JS frame, and isolated the true cost to the `--sticky-head-top`
write. The webview's own per-frame JS is otherwise negligible against the browser's
cost of painting a very tall document.

## 38. Table-header dock: flush under the CURRENT stack, via a thead-scoped var (#44)

Decision 36 docked the header at a **constant** = breadcrumb + the document's _max_
heading depth, to avoid any per-scroll `--sticky-head-top` write. That kept it
smooth but **over-reserved in shallow sections**: on `anleitung.md` (max depth 4,
but the `courier.json` section only H1>H2) the header floated ~44 px below the
2-row stack with document text showing through the gap. The owner rejected that
outright - the header must sit flush under the stack, always.

**Flush docking needs a per-depth-change write - the trap is _where_ it is written.**
`--sticky-head-top` is an **inherited** custom property. Writing it on `:root`
forces the whole document tree to re-resolve inheritance on every change; measured
over the 140-frame drag that was a **10x style-recalc blow-up** (Recalc 1316 ms vs
142 for the constant, 127 for stack-off) - far worse than decision 36 had even
attributed to it, and independent of the `th` count. Scoping the write to each
`<table>` element cut it to 393 ms (every cell in the table still re-inherits).
Scoping it to each **`thead`** - the smallest subtree that actually contains the
consuming `th` - brought it to **111 ms, at parity with the constant (127) and
stack-off (97)**, with paint and raster at or below stack-off. So: cache the
document's `thead`s per render, and on a depth change write the current dock
(`breadcrumb + current rows x 22`, value-gated) onto each. A scroll that stays
inside a section writes nothing; a real document has a handful of tables, so the
per-crossing cost is negligible. A real-Chromium screenshot confirmed the header
docks flush under the 2-row stack even when the document's max depth is 4.

This **refines** decision 36's rule. Not "never write `--sticky-head-top` on the
scroll path" but: **never write an inherited custom property on `:root` (or any
large subtree) from the scroll path; scope it to the smallest subtree that consumes
it.** The `--toc-scroll-margin` constant (36) stays a `:root` write, but it is
published once at init, never on scroll, so it is unaffected. `maxChainDepth` (the
document-max helper from 36) is removed - the dock follows the live chain now.

## 39. Wide-table emulated header: kill the double dock, the per-frame layout, the stale top (#44)

A wide (horizontally scrolling) table takes the _emulated_ header path, not native
`th` sticky: the wrapper's `overflow-x: auto` makes it the th's scrollport, so the
pin is faked by translating the thead each frame (`updateStickyHeads`). On a real
inventory document (a 19-column table) three bugs compounded there; all three were
found by driving the actual file in a real Chromium (CDP geometry read + screenshot).

1. **Double dock.** The native `th` sticky was left on. Measured, the thead was
   translated to the bar bottom AND the th then stuck another `top: --sticky-head-top`
   below _that_ (the transform on the thead re-parents the sticky), docking the
   header a full stack height too low - floating over the data rows. Fix: switch
   native sticky off in a scrolls wrapper (`.table-wrap.scrolls th { position:
static }`); the emulated transform is the single source of the pin.

2. **A forced layout every frame (the freeze).** `updateStickyHeads` called
   `getBoundingClientRect` twice per scrolling table per scroll frame - a forced
   synchronous layout, the freeze the owner hit on a table-heavy document. The
   table's document top, its height and the header height are layout values that
   change only on reflow, so they are cached (`scrollingHeads`) on
   render/config/resize and the scroll path now reads plain numbers - zero
   `getBoundingClientRect`. A test counts the call and asserts it stays flat across
   `updateStickyHeads`.

3. **A stale cached top.** The cache is first filled in `updateTableScroll`
   (`rebuildMinimap`), but `has-breadcrumb`'s `padding-top` is applied later, in
   `rebuildToc` - so the first measurement is short by the padding and the pin sat
   ~15 px low. `refreshScrollingHeads` re-measures after the bars are up (render and
   config) and on resize, mirroring `scrollSpy.refreshMetrics`. A real-Chromium read
   confirmed the header then docks exactly at the stack bottom (72 px for a 2-row
   stack).

The emulated offset itself (`stickyHeadOffset`) was already correct and unit-tested;
these were all in the geometry feeding it and in the native/emulated overlap.

## 40. Central click-focus suppression: no first-click jump, no toggle drift (#44)

Re-added from the reverted round-8 work (the perf rebuild had deliberately excluded
the optics; this is the first of them, brought back one at a time now the scroll
path is confirmed smooth). Two owner-reported symptoms were **one** root cause: a
mouse click focuses the control, and a VS Code webview scrolls a newly focused
element into view - a few-pixel page jump on the first click, and, for a TOC twistie
(inside its `<a>`), a spurious active-heading change, so a collapse/expand appeared
to drag the selection to the entry above.

**One delegated `document` `mousedown` listener** over every focusable target
(`a, input, button` plus the nav-control classes `.breadcrumb-seg,
.breadcrumb-option, .toc-link, .sticky-row`) calls `preventDefault`, which stops the
focus without touching the click itself - links still navigate, checkboxes still
toggle. Keyboard use is untouched (`mousedown` is pointer-only; `:focus-visible`
still rings on Tab), and plain text (headings, paragraphs, table-cell prose) is not
matched, so text selection stays normal.

The **scope had to be every focusable element, not just the nav controls**: the owner
reported the page jumping "a level" on clicks in _all_ paths, including content links
and task/table checkboxes. The mechanism is measurable in a real Chromium - focusing
an off-screen link scrolls the page to it (1979 px in the repro), a checkbox to
2180 px - and the browser/webview does this on every click that lands focus, sliding
the target under the fixed top bars. With the listener over `a, input, button`, a
real click on an off-screen link or checkbox leaves `scrollY` at 0 and
`document.activeElement` on `<body>`: no focus, no scroll. This is the interaction
Major (P1) and the focus-ring Minor (P4) in one fix - the same root cause (a click
granting focus). The absolute pixel jump under VS Code's own bars is a manual check;
the focus-and-scroll mechanism and its suppression are headless-proven.

**The focus ring itself, everywhere (the visual half of P4).** The `mousedown`
suppression stops the nav controls from focusing at all, but the other focusable
elements a click lands on - content links, and the task checkboxes and table cells
(`tabindex="-1"`, so a click still focuses them) - still showed VS Code's injected
focus outline (`--vscode-focusBorder`, an orange ring in some themes). One global
rule `:focus:not(:focus-visible) { outline: none }` drops the outline for
pointer/programmatic focus across the whole preview and keeps it for `:focus-visible`
(keyboard), so accessibility is unaffected. It is unlayered, so it beats VS Code's
layered webview focus rule (#15) - verified in a real Chromium against an injected
`@layer` outline: a programmatically focused link and a `tabindex="-1"` checkbox both
compute `outline: none`, and neither matches `:focus-visible`. Preferred over the
reverted round-8 version, which suppressed the ring per nav-control selector and so
left content links and checkboxes ringing.

## 41. Per-heading scroll-margin so the native #id jump selects the clicked heading (#44)

The owner reported that clicking a TOC entry, a breadcrumb segment or a sticky row
scrolled to the right place but highlighted the heading **just before** the clicked
one (click c2 -> c1). A readout added to the real webview gave the numbers: clicking
"Transporte" (top 45000) landed at scrollY 44854 = 45000 - **146**, and 146 is
`--toc-scroll-margin` (breadcrumb + MAX_STICKY_ROWS x row + gap, the document maximum).
Transporte's own bars are 94, so its activation line sits at 44854 + 94 + 8 = 44956,
44 px above the heading - the previous heading stayed active.

Root cause: a VS Code webview performs the browser's native fragment navigation when
an in-page `<a href="#id">` control link is clicked, and `preventDefault` in the click
handler does **not** stop it (the webview host intercepts link activation). So that jump

- not our `navigateToHash` - lands the final scroll position, and it uses the heading's
  CSS `scroll-margin-top`, which was the single coarse maximum (#33/#36 kept it a constant
  to avoid a per-scroll `:root` rewrite). An over-estimate is _not_ fine: it lands every
  shallow heading below its own activation line.

Fix: `publishHeadingScrollMargins` writes each heading's own `scroll-margin-top` -
`breadcrumb + its ancestor-chain depth in sticky rows` - once per render/config (never
on scroll, so no per-frame recalc). The native jump then lands every heading right at
its own bars, where the scroll-spy marks it active. Smooth navigation is unchanged
(the fix only corrects where the jump settles). Verified in a real Chromium over an
a/b/c(c1 c2 c3)/d/e hierarchy: every control click now selects the clicked heading
(c2->c2, d->d, c3->c3), each landing at its own margin (72/50/72 px). Rejected earlier
attempts: subtracting the target's own offset inside `navigateToHash` (the native jump
overrode it) and making the control scroll instant (the jump, not smoothness, was the
cause) - both were reverted.

**Follow-up: per-heading activation line, not just per-heading margin.** The per-heading
margin fixed the three top-bar controls but the owner then found the in-document TOC (the
`[..](#id)` links at the top of the file) still marked the previous heading by a few
pixels. Cause: the scroll-margin (where a heading _lands_) was per-heading, but the
scroll-spy's activation line (where a heading counts as _reached_) was still one global
inset = the **currently active** heading's bars. Clicking a top-of-file TOC link jumps
from active = -1 (inset 0), so the native jump lands a deep h3 at its own 94 px bars while
the activation line sat at the stale 8 px - 86 px above the heading, so its h2 parent
stayed marked. Fix: `scrollSpy.setInsets` takes the **same** per-heading bars array that
`publishHeadingScrollMargins` already computes, and `activeHeadingIndex` uses `insets[i]`
per heading instead of the one global inset. Landing line and activation line are now the
identical per-heading value by construction, so the heading a jump lands is the heading
marked active - at any depth, from any starting position, and independent of the lagging
global inset. The flat global inset stays as the fallback when no per-heading insets are
set (bars disabled, or before the first render). This is a refinement of the top-bars
feature's own activation, not a change to the base scroll-sync or the minimap. It does
shift the free-scroll highlight flip point at a depth change by the depth difference in
rows (a deeper child now highlights once it reaches its own taller dock, ~22 px later per
level) - the intended behaviour, matching where each heading actually docks.

## 42. The three top-bar controls are buttons, not #id anchors, so the smooth scroll is visible (#44)

The owner reported that the smooth scroll he had asked for was nowhere to be seen. Root
cause is the same webview quirk as #41: a click on an in-page `<a href="#id">` runs the
browser's **native, instant** fragment jump, which `preventDefault` cannot stop, so it -
not our smooth `navigateToHash(.., true)` - won the final position. The smooth scroll ran
but was instantly overridden, so no motion was visible.

Fix: the three new controls - the TOC panel/rail entries (`.toc-link`), the breadcrumb
segments (`.breadcrumb-seg`) and their sibling-picker options (`.breadcrumb-option`), and
the sticky rows (`.sticky-row`) - no longer render as `#id` anchors. They are
`role="button"` elements that carry the target id in `data-id`; the click handlers read
`dataset.id` and scroll via the smooth `navigateToHash`. With no href there is no native
jump to override, so the smooth scroll is the only motion.

Deliberately **not** changed: the in-file markdown `[..](#id)` links stay real anchors
(their href is the author's content, not ours to rewrite) and therefore stay instant - the
one place the native jump still wins. So the controls are smooth, the in-file TOC is
instant; there is no reliable way to make a native markdown anchor smooth in the webview.

Selection stays correct because a button lands via JS at `absTop - topBarsOffset` and the
per-heading activation line (#41 follow-up) already absorbs the offset difference at any
depth - the per-heading `scroll-margin-top` machinery is kept, since the in-file anchors
still rely on it for their native jump. Headless contract (`webview.test.js`): the rendered
controls are `role="button"` with a `data-id` and no href; the click handlers navigate via
`dataset.id`. The smoothness itself is a manual VS Code check (a headless DOM has no scroll
animation). This is a refinement of the top-bars feature; the base scroll-sync and the
minimap are untouched.

## 43. Native codicon TOC twistie + animated sublist expand/collapse (#44)

The owner found the TOC twistie "winzig und nicht wie im vscode native" (a self-drawn
`::before "\203A"` glyph) and the section expand/collapse not animated. Both concern the
same TOC row, so they were done together.

**Twistie: the real codicon font, not a text glyph.** `@vscode/codicons` (pinned
`0.0.46-24`) is vendored as `media/codicon.ttf` and loaded via a webview `@font-face`
(`font-src` added to the CSP for the webview origin). The base `.codicon` rule mirrors the
upstream one (`font: normal normal normal 16px/1 codicon`) so the glyph renders at its
native metrics; the twistie is `<i class="codicon codicon-chevron-right">` (`\eab6`).
Rejected: an inline SVG of the same path (visually identical, no font/CSP) - the owner
chose the real font for a truly native result; the FAB's inline-SVG icon is left as is.
The whole ttf ships (~146 KB) rather than a subset, matching how VS Code webviews embed it;
subsetting would need a heavier build tool than the font it saves.

**Layout: a gutter + label, flex-centered.** Each row is `display: flex; align-items:
center` with a fixed 16px `.toc-gutter` (the twistie for a parent, empty for a leaf so
labels align at each depth) and an ellipsized `.toc-label`. That centers the chevron
against both the text and the row box - the owner's "exakte zentrierung" - without the old
absolute-positioned `::before`. Collapsed points right (`rotate(0deg)`), expanded points
down (`rotate(90deg)`). The chevron hit-test is now an exact node check
(`e.target.closest('.toc-gutter')`) instead of the previous geometric `offsetX` zone.

**Animation: grid-template-rows, armed for manual toggles only.** The sublist is wrapped in
`.toc-sublist-wrap` that animates `grid-template-rows` `0fr <-> 1fr` (animates to the
content height with no magic number); the sublist clips via `overflow: hidden; min-height:
0`. The transition is enabled only while `body.toc-animating` is set - a flag armed by the
manual `toggleTocBranch` and cleared by a 250 ms timer - so the scroll-driven auto
expand/collapse in `applyTocActive` (the hot path) stays instant, never a per-frame
animation during a scroll. `prefers-reduced-motion: reduce` disables it. Headless contracts
(`webview.test.js`): the codicon `@font-face`/glyph/metrics, the gutter centering, the
rotation both ways, the `0fr/1fr` tracks, and that a manual toggle sets `toc-animating`
while a scroll does not. The visual (glyph size, centering, animation smoothness) is a
manual VS Code check. Base scroll-sync and minimap untouched.

## 44. Content section folding, from the document and the sticky stack (#44)

The owner wanted VS-Code-style folding: a fold control before each foldable heading in
the document AND on each sticky-scroll row, both folding the same rendered section and
kept in sync (fold from either surface, both reflect it).

**One fold engine, keyed by heading id.** `foldedIds` (a Set of heading ids) is the single
source of truth, preserved across re-renders (re-applied after each render, so folding
survives an edit like VS Code). A heading's section is every following block up to the
next heading of the same or a higher level; `computeFoldHidden` walks the blocks with a
level stack so nesting is handled (a folded ancestor hides a folded descendant's blocks
too) and the folded heading itself stays visible with its collapsed chevron. `isFoldable`
skips a heading whose section is empty. Both are pure and unit-tested.

**Two surfaces, one toggle.** The document control is a native codicon chevron injected
before each foldable heading (`injectFoldToggles`), in the heading's left gutter so it
never reflows the text, hover-revealed (as in VS Code) but always shown while folded. The
sticky row carries the same chevron in a `.sticky-gutter` before its label. A click on
either calls `toggleFold(id)`, which flips the set, re-hides the blocks (`applyFolds`),
reflects both surfaces (`applyFolds` for the document chevrons, `reflectStickyFolds` for
the sticky ones), and runs the existing layout refresh. Unfolded points down, folded
right.

**The layout refresh, not a logic change.** Hiding blocks changes the rendered height, so
the minimap, scroll-spy tops and line-metric tops must be re-measured. `toggleFold` re-runs
the existing `onViewportResize` sequence (the same one a real resize runs) - the minimap
and scroll-sync logic is untouched, only its refresh is triggered. This is the one place
folding reaches the protected base path, and it reaches it only through its public refresh.

**In-page anchors became buttons here too (#44 shift fix).** Independently, the in-file
`[..](#id)` links were converted to `.mw-anchor` buttons (`convertInternalAnchors`): as
real `<a href>` they fired the webview's native #id jump on top of `navigateToHash`, and
once the bars gave headings a scroll-margin the two scrolls landed ~2-4px apart, shifting
the whole view (and the TOC rail) on every in-file-TOC click. With no href there is no
native jump; `navigateToHash` - scoped to `#content`, CSS.escaped, collision-safe - is the
sole scroll. Headless contracts cover the fold engine, the toggle wiring on both surfaces,
and the anchor conversion; the fold visuals and animation are a manual VS Code check.
Minimap and base scroll-sync untouched.

## 45. Idempotent render + fold-aware navigation (#44 P2 follow-up)

Two folding follow-ups the owner hit in real use.

**Idempotent render.** The render path is fully unconditional: it replaces `#content`'s
innerHTML, re-clones the minimap, rebuilds the TOC and re-runs the scroll-spy. Both webview
construction paths already set `retainContextWhenHidden`, so the DOM survives a tab switch,
but any redundant render (a theme/config re-post that produced identical HTML, or a
host-side re-push) still thrashed the DOM and reset scroll + fold state. The `render`
handler now guards on the exact HTML against the last rendered string: an identical render
returns immediately, keeping the built DOM and its live scroll/fold state. A genuinely
changed document (an edit, the shiki-highlight upgrade, an extra-marker config change) still
carries different HTML and re-renders as before. Config-driven layout changes ride the
separate `config` message, so skipping an identical render never drops a layout update.

**Fold-aware navigation.** A heading inside a folded section is `display:none`, so its
`getBoundingClientRect()` is 0; navigating to it (TOC / breadcrumb / sticky) scrolled to
`scrollY - offset`, walking the view upward a little more on every click. `navigateToHash`
now runs the target id through `visibleFoldAnchor`, which maps a folded-away heading to the
section header it visually collapsed into - the outermost folded ancestor that is itself
still visible - by scanning the same content blocks and fold set `computeFoldHidden` uses. A
visible id (or a non-heading id) is returned unchanged, so the normal path is untouched.
Both are unit-tested; minimap and base scroll-sync untouched.

## 46. Incremental preview rendering via a vendored morphdom (#44 P2 follow-up)

Decision #45 made an identical render a no-op. A _changed_ render (an edit, the
shiki-highlight upgrade) still replaced `#content`'s innerHTML wholesale, which
destroyed and rebuilt every node - losing text selection and risking a scroll
reset. The built-in Markdown preview does not do this: since VS Code 1.63 it
updates the preview by morphing the existing DOM (morphdom) rather than replacing
it, so only changed nodes are patched. The owner chose the same approach here for
parity.

**Vendored, like codicon.ttf.** `media/morphdom.js` is the morphdom 2.7.8 UMD build
committed into the repo (sourced from the pinned `morphdom` devDependency), loaded
via a nonce'd `<script>` before `webview.js` so its global is ready at the first
render. The webview script is not bundled, so a committed asset is the established
pattern; the vsix ships without node_modules. _(Addendum: revised by #50 - morphdom comes
from the npm package, pinned exactly, and is bundled into `dist/webview.js`;
`media/morphdom.js` and its second `<script>` tag are gone.)_

**Diff like-for-like.** Our render post-processes the HTML client-side (in-page
anchors become buttons, a fold control is injected on each heading). A naive morph
of the authoritative HTML against that post-processed DOM would fight those
injections, so the incoming tree is built off-DOM and run through the SAME
post-processing (`convertInternalAnchors`/`injectFoldToggles`, now root-parameterised)
before `morphdom(content, incoming, { childrenOnly: true })`. morphdom keys nodes
by `id`, so headings keep their identity across edits; `childrenOnly` leaves
`#content` itself untouched. Fold state is re-asserted on the morphed tree by the
existing `applyFolds` (idempotent), and the same re-measure pipeline
(line-metrics, minimap, TOC, sticky) runs as before - unchanged, and the minimap
and base scroll-sync logic is untouched.

**Verified.** Headless contracts cover the orchestration: the render morphs (a spy
asserts `childrenOnly` and the live `#content` target), an identical render is
guarded (no morph), a changed one morphs again. The vendored library itself was
checked in real Chromium: `childrenOnly` keeps `#content`, and a heading node
keyed by `id` is reused (a JS-only marker property survives the morph) while its
text updates.

**Measured**, and the tool is committed: `bench/render-bench.js` (headless Chromium
over CDP, the same harness as the other benches) times the content-update step of
both paths on a generated document and checks the selection claim. Medians of 60
iterations on a 400-block document, three runs on the same machine:

```
edit(morphdom)=2.20-2.40ms  edit(innerHTML)=6.70-7.00ms
identical(guarded)=0.00ms   whole(morphdom)=6.10-6.80ms
selection: morphdom=survives  innerHTML=lost
```

A one-block edit is ~3x cheaper through morphdom (only the changed node
re-lays-out, not all 400) and a live text selection outside the edited block
survives it, while the replace destroys it - the two halves of the decision, both
reproduced. An identical re-render is 0 ms (the string guard from #45). A
full-document change (a file switch) is the one case where morphdom's diff cost
approaches the replace; the common live-edit case wins clearly. The end-to-end
delta equals this content-update delta - the minimap/TOC/line-metric re-measure
runs identically either way.

Two honesty notes on the numbers. They replace the ones this decision first
carried (~3.3 vs ~7.4 ms), which were produced by a session-local harness that was
never committed - same conclusion, but only the committed tool makes it
reproducible. And the container is noisy: one run of the three reported 5.0 vs
17.1 ms. The ratio is the stable part, not the absolute values.

## 47. Fold performance: a write-only click path and a mirrored minimap (#44 P2 follow-up)

Folding a section was still visibly slow on a large document: the owner reported the
toggle "dauert viel zu lange". Measured first (`bench/fold-bench.js`, headless
Chromium, medians), the wait splits in two - the synchronous work inside the click
(before the browser can paint) and the batched re-measure ~120 ms later, which showed
up as one long frame:

| document                            | metric           |    before |    after |
| ----------------------------------- | ---------------- | --------: | -------: |
| 300 sections (1800 blocks, 95k px)  | click            |   4.80 ms |  4.70 ms |
|                                     | blocking refresh |  64.10 ms | 17.60 ms |
|                                     | rects per toggle |      4795 |     2395 |
| 600 sections (3600 blocks, 190k px) | click            |   9.80 ms | 10.80 ms |
|                                     | blocking refresh | 113.50 ms | 30.80 ms |
|                                     | rects per toggle |      9595 |     4795 |
| 300 sections + 200 tables (150k px) | click            |   7.40 ms |  8.10 ms |
|                                     | blocking refresh | 127.10 ms | 27.90 ms |
|                                     | rects per toggle |      5194 |     2594 |

**The minimap clone was the cost, and it is now mirrored, not rebuilt.** The batched
refresh called `rebuildMinimap`, which `cloneNode(true)`s the whole document into the
rail - a second full layout and paint per toggle. A CPU profile put `rebuildMinimap`
at 10.5 % _total_ self-time (with 72 % idle, i.e. ~37 % of the active time), the single
largest entry. The clone's top-level children are index-parallel to `#content`'s, so a
fold is mirrored onto the existing clone as one class write per block
(`mirrorFoldsToMinimap`). A real rebuild is left for the two cases that need it: the
rail appearing or disappearing (that changes the content width) and a clone that no
longer matches the document. With the rail switched off entirely the refresh costs
16.9 ms vs 17.6 ms with it - the clone is no longer a factor.

**The click path only writes.** `applyFolds` ended with
`heads.map((el) => el.offsetParent === null)` to tell the scroll-spy which headings
are folded away. `offsetParent` is a layout read, so asking for it right after the
fold's class writes forced a synchronous full-document layout _inside_ the click
handler. The mask is now derived from the fold set itself (`hiddenBlocks` +
`isInHiddenBlock`, a pure ancestor walk), which also covers the nested-heading case the
`offsetParent` read used to cover; `lineMetrics.collect` filters by the same predicate.
The click now writes only, and the browser lays the document out once, asynchronously.

**Only what changed is written.** `applyFolds` re-wrote the class of _every_ block and
did a `querySelector('.mw-fold-toggle')` per heading on every toggle. It now diffs
against what it last wrote (`writtenHidden` / `writtenFolded`) and touches only the
blocks and the one chevron that flipped. A render re-applies in full (`applyFolds(true)`):
morphdom syncs our injected classes away, so the cached baseline no longer describes
the DOM.

**The work was being done twice per toggle.** The `ResizeObserver` on `document.body`
fires on a fold too (the body height changes) and did a full `lineMetrics.refresh()` +
`scrollSpy.refreshMetrics()` of its own - the second half of the 4795 rects per toggle.
Worse, it ran _before_ the folded-away blocks were filtered out, so it measured them at
top 0 and corrupted the monotonic line->pixel map the scroll sync binary-searches. It
now skips while a fold refresh is pending; the pending pass covers exactly that work,
with the correct filter. Image loads and real reflows are unaffected.

**The refresh pass is ordered write -> read -> write** (`refreshAfterFold`): the minimap
mirror writes first, every cached measurement is read next, and only derived positions
are written after - so the browser lays the document out once for the whole pass.

**What is left is the browser, not our JS.** With the batched pass suppressed entirely,
the 600-section fold still shows a 17.2 ms frame with **zero** rect reads: that is
Chromium re-laying-out and painting a folded 190,000 px document, the floor for this
document size. Our pass now adds ~14 ms on top of that floor (it added ~96 ms before).
The remaining JS share is the ~4800 rects of the re-measure; a fresh profile shows
`(program)` (browser layout) at 18.3 % against `getBoundingClientRect` at 3.0 %.

**`content-visibility: auto` measured and rejected here.** Issue #49 keeps it as a
measurement-gated option. Measured on the 600-section document (`#content > *` with
`contain-intrinsic-size: auto 120px`): the click improved 10.8 -> 7.5 ms and the refresh
30.8 -> 29.5 ms, but `scrollHeight` went from 190,078 to 493,455 px - the placeholder
sizes replace the real geometry, which is exactly what the minimap scale, the scroll
sync and the anchor jumps are built on. Not adopted; the number is recorded for #49,
where the canvas minimap changes the picture.

**Bench rot fixed in the same pass.** `bench/scroll-bench.js` had been reporting
`lines=0` since the morphdom change (#46): the vendored `morphdom` global was not in
the bench page, so the render threw inside the message listener and was swallowed - the
"benchmark" measured an empty document. Every bench now shares `bench/harness.js`,
which loads the same vendored asset the webview loads and reports a page error as the
result instead of timing out silently. Re-verified on the repaired bench, the scroll
path is unchanged by this round: 300 sections 16.67 -> 16.63 ms/frame, 200 sections +
200 tables 31.40 -> 27.33 ms/frame, 2.0 rects/frame in both.

**Round 2: order the pass read-then-write, and hand it to idle time.** The first pass
still cost two consecutive ~30 ms frames per toggle. A frame trace
(`fold-bench.js --trace`, which also counts who re-measures) showed why: the pass
mirrored the minimap _before_ measuring. When it runs, the fold's own layout is long
done and clean, so every measurement is a free read - but a write dirties layout again,
so mirroring first made the first read force the clone's relayout **synchronously
inside our pass**. Reads now come first and the minimap mirror goes last, into an idle
slot (`scheduleMinimapFoldMirror`): the clone's relayout happens in the browser's own
time. Measured over-budget time per toggle (frames beyond a 20 ms budget in the 400 ms
settle window, 3600 blocks): 27.4 ms -> 12.0 ms.

The pass itself is also no longer on a fixed 120 ms timer but scheduled into idle time
(`runWhenIdle`, deadline 250 ms as a starvation guard). Nothing needs the tops until the
reader scrolls or navigates, and whoever does need them flushes the pass synchronously
first (`flushFoldMetrics`, called from `maybePostScrolled` and `scrollToSourceLine`).
That closes a real correctness hole as well: for the 120 ms the timer was pending, a
scroll reported a source line computed from the _pre-fold_ tops, so the host revealed
the wrong range in the source editor. The idle move alone is not a throughput win
(measured 13.4 ms vs 14.6 ms over-budget, inside noise); the flush guard is why it is
there.

**Where the remaining delay is: the DOM-clone minimap, i.e. #49.** With the rail
switched off, folding a 3600-block document costs 0.6 ms of over-budget time on a fold
and 0.0 ms on an unfold - a single 20 ms frame of Chromium's own layout and nothing
else. With the rail on it is 13.4 / 16.1 ms. On an 1800-block document the whole
interaction is already jank-free with the rail on (0.0 ms both directions). So the
clone - a second full document that has to re-lay-out whenever the fold changes - is
now the _entire_ remaining cost, which is exactly what #49 exists for. Per #49's own
scope note that rebuild is its own PR, not this one.

**Two more experiments, both measured and rejected** (600 sections, same machine):

- `contain: layout style` on the content blocks: over-budget time 12.0 -> 10.8 ms, but
  `scrollHeight` 190,078 -> 193,678 px. `contain: layout` establishes a new block
  formatting context, so margins between blocks stop collapsing - the rendering
  visibly changes. Not worth it for noise-level gains.
- `content-visibility: auto` **with `contain-intrinsic-size` seeded from each block's
  measured height** (the "geometry-safe" variant the first round's rejection suggested):
  strictly worse - click 9.2 -> 17.4 ms, over-budget 12.0 -> 42.4 ms, and the height
  still drifts (193,944 px, same containment side effect). The reason is fundamental:
  reading `getBoundingClientRect` on a skipped `content-visibility` subtree forces the
  browser to render it. Browser-native virtualisation and per-element measurement
  exclude each other. Virtualising the preview (the editor's approach, which is why
  editor folding is instant) therefore requires _first_ replacing per-element
  measurement with model-based positions - and it would give up find-in-page and
  select-all over the whole document, which the built-in VS Code markdown preview does
  not do either (it is a full DOM document with morphdom updates, like ours).

**Verified.** Headless contracts: a fold reuses the minimap clone (a clone counter
stays at zero across fold and unfold) and mirrors the hidden class onto it; the click
path reads neither `offsetParent` nor a rect; a scroll right after a fold flushes the
pending re-measure before it reports a line (and only once - a second scroll finds it
fresh); flushing does not pay the clone cost (the clone catches up in idle time); a toggle writes only the blocks whose
visibility changed (and not those already hidden by a nested fold); the scroll-spy mask
resolves a nested heading through its ancestors; the `ResizeObserver` does nothing while
a fold refresh is pending and measures again once it has run; the clone root drops
`#content`'s own id (the duplicate id that the bench tripped over). The in-VS-Code feel
of the toggle stays a manual owner check - headless can show the numbers, not the
perception.

## 48. Native clipboard diff with an editable, memory-only candidate (#82)

VS Code's own "Compare Active File with Clipboard" puts the clipboard left and the file
right, with no way to swap (microsoft/vscode#259434, "not planned"). The clipboard diff
reads the clipboard - typically an AI answer - as **baseline -> candidate** in the native
diff editor: the file (or the selection, or the section the clipboard replaces) on the
left, an editable candidate on the right, and **Apply Candidate** writes it back. The
design round ran on #82 (tracking issue #88); everything below ships in one PR. Code
lives in its own subject folder `src/clipboard-diff/` (the folder rules forbid more flat
files in `src/`), tests mirror it in `tests/clipboard-diff/`.

**The candidate is an in-memory file system.** A `FileSystemProvider` under the scheme
`markdown-workbench-clipboard` serves the candidate page (and the selection page) from a
`Map`; `writeFile` never touches the disk and `stat` reports an ever-growing mtime. A
read-only `TextDocumentContentProvider` would be safe but not editable. An editable
scheme runs through VS Code's backup tracker, which writes unsaved text in plain text to
`<userData>/Backups/<ws>/<scheme>/` about one second after the last change, whatever
`files.hotExit` says (`workingCopyBackupTracker.ts`, microsoft/vscode `2322fa7`); the
public API has no opt-out except `isReadonly`. So every change of a page is **saved
immediately** (`onDidChangeTextDocument` -> `document.save()`, own scheme only): a
successful save discards the backup and cancels its timer, and the backup never gets its
second. The promise, in the wording of the decision log: "Die Extension schreibt den
Clipboard-Inhalt nie auf die Platte. Damit VS Code keine Sicherung anlegt, speichert sie
jede Aenderung sofort in den Speicher; gemessen durch den Waechter-Test
(`tests/integration/guard/scenario.js`, heute `scenario.ts`). Ausnahmen: 'Speichern unter' auf ein lokales
Ziel ist eine ausdrueckliche Nutzerhandlung. Scheitert das Speichern, kann VS Code eine
Sicherung anlegen." The content never goes to a log or an error text and is never
persisted; a page is released once no tab shows it, and on `deactivate`.

**The immediate save skips the user's save actions where it can** (decided on #88 after
review wave 1). An extension's `document.save()` counts as an explicit save
(`$trySaveDocument` passes no reason, so `SaveReason.EXPLICIT`): VS Code would run
`files.trimTrailingWhitespace`, `files.insertFinalNewline`, `files.trimFinalNewlines`,
`editor.formatOnSave` and `editor.codeActionsOnSave` on every keystroke - a typed space at
a line end would vanish at once. The API offers no save with `reason: AUTO` or without
participants for a given document. So a page that is the focused editor (either side of
the active diff - the selection page is the left one - or its own tab) - the typing case -
is saved with `workbench.action.files.saveWithoutFormatting`, which saves the focused side
and skips them (measured on 1.100.0 and 1.139.1, review round 2 of #89); any other page (a
page changed by a diff arrow while the other side has focus, a mirror edit) is saved with
`document.save()`. There the save actions may change the page itself, but the
edits made while that save runs (from the save call to its end - VS Code 1.100 runs the
save actions even before `onWillSaveTextDocument`, measured)
count as the save's own and are never written through into the file; the page's
write-through passes the user's changes one by one, never the whole page, so a drifted
page does not carry them over either. An edit that lands inside a save is saved right
after it. Save actions run before the write, so the written text holds them: what a
selection page holds beyond it at did-save came after the write and is the user's, and
it is written into the file then (decided on #89, review round 1). A user edit that lands
before the write is saved along with the save actions and cannot be told from them; since
typing needs focus and a focused page is saved without save actions, this is left to a
page focused during an unfocused save: when such a page still differs from its file
region in more than trailing blanks after the save, the sync warning shows, without page
text. A `document.save()` that resolves false because an edit came during it is no
failure: the page is saved again.

**Roles in the names, not in a title.** `vscode.diff` is called without a title; the
pages are named `notes (Candidate).md` / `notes (Selection).md` (the extension keeps the
language). VS Code then titles the tab `notes.md ↔ notes (Candidate).md` itself and
re-titles it after every swap - a set title would travel along with the swap and lie.

**Swap is VS Code's own** `workbench.action.compareEditor.swapSides` (since 1.86, no
precondition on the command, only on its button) for every text diff, ours and foreign;
it keeps tab position and pin. The command returns silently where it cannot reopen a side,
so **Swap Diff Sides** checks the tab afterwards and reports a skipped swap. No 1.85
branch: `engines.vscode` is `^1.100.0` since #84. Its button shows only where VS Code's
own is hidden (`!activeCompareEditorCanSwap`, false where the left side is read-only, as
in a Git diff), so a diff never shows two; after a swap it closes other clean tabs of the
same two sides in the group, since VS Code opens a Git change reopened after a swap in its
first order beside the swapped tab (#94, measured on 1.100.0 and 1.139.1).

**Baseline choice.** A non-empty selection becomes a `(Selection)` page, a two-way mirror
of its range in the file; several selections become their hull (start of the first to
end of the last, in document order) with a note - concatenating cannot be written back
unambiguously, and "first only" throws away the intent. Without a selection the **section
anchor** looks for the part the clipboard replaces: a heading-led clipboard takes the
same-named section (up to the next heading of the same or a higher level, spans from
`token.map`); otherwise a line-hash index of the baseline (built once, O(n)) finds the
clipboard's first and last line and scores the overlap at no more than
2 × `MAX_ANCHOR_CANDIDATES` places, K hits of each line (O(n + K·m)). An unsure or ambiguous hit asks with a
QuickPick that also offers the whole file. An anchored diff shows the whole live file
against the file with the section replaced and opens with the span selected, so the
native diff shows only that place. Without a hit the baseline is the live file itself.
Clipboard line endings follow the baseline.

**Apply Candidate** replaces the tracked region with the candidate as one
`WorkspaceEdit` (one undo step). The region follows edits of the file through
`contentChanges`; if the region itself was edited since the diff opened, Apply asks
instead of replacing (ClipDiff replaces the old range). Per-hunk apply uses the built-in
arrows only: with the file on the left an arrow drops a candidate hunk and Apply writes
the rest; after a swap the arrow takes a hunk into the file directly (the selection page
writes through to its range). No proposed API, no `diffEditor.revert` with arguments.

**Beyond the diff** (all accepted by the owner, 2026-09-27):

- **Earlier clipboards** - every clipboard text the extension itself read goes into a
  session ring buffer (`MAX_HISTORY_ENTRIES`, `MAX_ENTRY_BYTES`; a larger text is dropped,
  never cut). Memory only, no polling of the clipboard.
- **Style alignment** - the baseline's dominant bullet, emphasis/strong markers and table
  padding (the editor's `reflowTable`) are applied to the candidate by swapping markers
  at their source positions, never by re-serializing (#1); never inside code, HTML or
  front matter; paragraph breaks stay. A rewrite that changes the parsed structure is
  dropped. A visible switch toggles raw/aligned and asks before it discards edits.
- **Unwrapping an AI answer** - an outer fence and chat lines at the edges ("Sure, here
  is ...:", "Let me know ...") go, by named pattern lists. **Placeholder guard**: a line
  like "… rest unchanged …" is marked, and Apply fills in the baseline text it hides,
  aligned by the neighbouring lines through the same line index; an unclear alignment
  asks instead of guessing. An ellipsis in running text never counts.
- **Markdown check before Apply** - reset checkboxes (one-click "keep checkbox states from
  the baseline", with the preview's `CHECKBOX_RE`), lost footnote and reference-link
  definitions, removed or changed front matter, and removed headings a `#anchor` still
  points at (own file; the workspace only with
  `markdownWorkbench.clipboardDiff.checkWorkspaceAnchors`, and only at Apply - links
  resolved relative to their file, files over 1 MB or unreadable skipped). Hints and quick
  fixes on the candidate for the file's own links, a question at Apply - never a block.

**Shared primitives moved, not copied.** `CHECKBOX_RE` (from `views.js`) and the table
reflow (`splitRow` / `isSeparatorRow` / `reflowTable`, from `editing.js`) now live in the
vscode-free `src/markdown/syntax.js`; `render.js` requires `vscode` only inside
`shikiTheme`. _(Addendum, state audit 2026-09-29T2304Z: the table reflow moved on into the table model,
`src/tables/format.js` (#49); `syntax.js` keeps `CHECKBOX_RE` and `checkboxBoxPos`, and
the vscode-free markdown-it instance is `src/render/parser.js`.)_ The pure modules of the clipboard diff reuse the preview's own markdown-it
instance and run under `node --test` without the vscode mock.

**Tests in a real VS Code.** The mock (#21) keeps testing the logic; the promise needs
the real backup tracker. `@vscode/test-electron` (pinned exactly) runs
`tests/integration/` with a small own runner - no `@vscode/test-cli`, no Mocha (a second
test framework, a 0.0.x package) - against the minimum `engines.vscode` version and the
current stable one, each with a fresh `--user-data-dir`, `--disable-extensions` and a
copy of the fixture workspace; a second launch on the same profile plays the reloaded
window. **The guard needs a normal window**: VS Code registers no backup path for an
extension-development host and keeps its backups in memory there (`main.js`:
`config.extensionDevelopmentPath || registerWorkspaceBackup(...)`), so a guard in the
test host alone can never see a backup file - measured: the first mutation run stayed
green. The guard scenario (`tests/integration/guard/scenario.js`, today `scenario.ts`) therefore runs twice:
in the test host, where a page left unsaved for 800 ms (the tracker writes after ~1000 ms)
is the signal, and in a normal window with the packaged extension and a test-only driver
extension installed into a fresh `--extensions-dir` (instead of `--disable-extensions`,
which would disable the installed extension too), where any file under
`Backups/**/<scheme>/` is red. Both are also red on any write, log line or file with the
clipboard text, while typing fast, with `editor.formatOnSave`, across a swap, when
closing and after a restart; a mutation run without the immediate save turns both red.
`build.ps1 -Task Integration` runs it all (under Linux through `xvfb-run -a`), and `All`
includes it.

**Rejected:** closing and reopening the tab as a swap (loses position and pin, pinning
needs an undocumented command); an own swap for foreign diffs (VS Code has one); a
read-only candidate; a webview diff editor or a rendered Markdown diff (non-goals of #82;
Rich Markdown Diff exists); deleting VS Code's backup files (private paths); proposed
gutter menus; detecting the clipboard's language (no public API - the candidate takes the
baseline's); re-serializing Markdown for the style alignment (#1).

## 49. Markdown table editing: GFM table model, Enter/Tab/arrows, sort, paste (#86, #90)

Design round of 2026-09-28 with the maintainer (tracking issue #90). The decision log
of that round follows (German, as written; table pipes inside code spans escaped); the
notes from the implementation are at the end.

| Feld           | Wert                                                                                                                                            |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Stempel        | 2026-09-28T0011Z                                                                                                                                |
| Repo / Basis   | ww3d/markdown-workbench, `main` `4221a9f` (0.34.0, VS Code `^1.100.0`)                                                                          |
| Anlass         | ww3d/markdown-workbench#86                                                                                                                      |
| Tracking Issue | ww3d/markdown-workbench#90                                                                                                                      |
| Runde          | Design-Session `design-mw-86`, Entscheider: Maintainer direkt im Chat (Controller `ctrl-markdown-workbench-1` hatte die Runde an ihn abgegeben) |
| Audit-Gate     | `audit/ist-stand-2026-09-27T2058Z.md`                                                                                                           |
| Review-Modus   | `hard v4` (Vorschlag der Session; der Maintainer hat die Runde danach ohne Einwand geschlossen)                                                 |

Ablage im Repo: Das Repo fuehrt keine `docs/decisions/`; der dev-PR traegt den Inhalt als neuen
Eintrag in `docs/DECISIONS.md` (naechste freie Nummer am Head) ein.

### Rahmen (Maintainer, vor der Runde)

- Gebaut wird nach Claudes Empfehlung und mit allen Claude-Ideen, eigene Umsetzung in
  `src/editing.js`.
- Alles in **einem** PR; jeder Punkt ist im Umfang oder ausdruecklich verworfen, mit Grund.
- Einstellungen fuer alle Features, wo sinnvoll.

### Ausgeraeumte Fehlannahmen

- `splitRow` ist nicht nur fuer Enter unzureichend: Schon heute macht `reflowTable` aus
  `a \| b` zwei Zellen und verliert beim Schreiben den Schutz (gemessen am Head).
- Ein `|` in einem Code-Span trennt nach GFM (Spec-Beispiele 199–204) **und** in unserer Preview
  (markdown-it 15.0.2, gemessen) die Zellen. Ein Parser, der Backticks schuetzt (so `mte-kernel`),
  saehe eine andere Tabelle als die Preview.
- markdown-it 15.0.2 erkennt Tabellen ohne Randstriche, in Listenpunkten und in Zitaten (gemessen).
  Eine Textzeile direkt unter einer Tabelle wird zur Tabellenzeile; Beenden braucht eine Leerzeile.
- Eine Tabellenzeile ist fuer `onTabKey` heute eine markerlose Zeile: Tab rueckt sie per
  Spaltenstopp ein (DECISIONS.md #27). Der Tabellen-Zweig muss davor greifen.
- Learn Markdown 1.0.18 (Quelle aus der VSIX-Sourcemap gelesen): Enter kennt keine Tabellen;
  Tabellen nur als Distribute/Consolidate/Insert/„Convert to data matrix“ auf einer Markierung;
  Zerlegung per `split('|')`, Breite per Codepoints mit grobem Emoji-Abzug, keine CJK-Breite.
- `DocumentPasteEditProvider` ist stabil seit dem Zyklus Januar 2025 (microsoft/vscode#238916,
  VS Code 1.97); mit `engines.vscode ^1.100.0` aus #84 nutzbar.

### Entscheidungen

#### D1 Grundlage: eigenes Tabellenmodell plus `get-east-asian-width`

- Eigenes Modell in `src/editing.js` (Zerlegung nach GFM, Erkennung wie die Preview, Breite nach
  Graphemen). Verworfen: alte Zerlegung behalten (erbt den Inhaltsfehler); markdown-it zur Erkennung
  (keine Zell-Positionen, keine Kopfzeile ohne Trennzeile); `mte-kernel` (schuetzt Backticks
  gegen GFM, `meaw ^5` veraltet, seit 2020 ohne Release, 600 KB); `string-width` (drei
  Transitiv-Pakete, `/v`-Regex, Terminal-Semantik).
- **Abhaengigkeit freigegeben:** `get-east-asian-width` 1.7.0 (MIT, 0 Abhaengigkeiten), nur als
  Unicode-Breitendaten. Grund: ersetzt die einzige Liste, die sonst selbst gepflegt veralten wuerde.
- Festlegungen: (1) Erkennung wie die Preview, Tipp-Ausnahme fuer eine mit `|` beginnende Zeile
  ohne Trennzeile; (2) `\|` bleibt Inhalt, ungeschuetzter `|` im Code-Span trennt, keine stille
  Korrektur; (3) Breite: East-Asian Wide/Fullwidth und Emoji 2, kombinierende Zeichen 0,
  Ambiguous 1; (4) Stil bleibt: randlos bleibt randlos, Ausrichtungs-Doppelpunkte, Einrueckung,
  Listen-Einrueckung und `>` bleiben.
- Abheben: Ausrichten aendert nur Leerzeichen und Strichzahl der Trennzeile, mit Zufalls-Test unter
  festem Seed; dieselbe Tabelle wie die Preview; korrekte Breite bei CJK/Emoji.
- Architektur-Abgleich: `docs/ARCHITECTURE.md` § „Editing features (editing.js)“.

#### D2 Enter

| #   | Fall                                               | Entscheidung                                                                                            |
| --- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| E1  | Enter in einer Datenzeile                          | neue leere Zeile darunter, gleiche Spaltenzahl, Cursor in die erste Zelle; die Zeile wird nicht geteilt |
| E2  | Enter vor dem ersten Inhalt (Praefix, erster `\|`) | neue leere Zeile darueber                                                                               |
| E3  | Enter in der Kopfzeile mit Trennzeile              | neue Zeile direkt unter der Trennzeile                                                                  |
| E4  | Enter in der Kopfzeile ohne Trennzeile             | Trennzeile plus leere Datenzeile, Cursor in deren erste Zelle                                           |
| E5  | Enter in der Trennzeile                            | wie E3                                                                                                  |
| E6  | Enter in der letzten, ganz leeren Zeile            | Zeile wird Leerzeile, Praefix (`>`, Einrueckung) bleibt                                                 |
| E7  | leere Zeile mitten in der Tabelle                  | wie E1                                                                                                  |
| E8  | nach Enter                                         | Tabelle ausrichten; Enter plus Ausrichten ist ein Undo-Schritt; nur geaenderte Bereiche werden ersetzt  |
| E9  | mehrere Cursor oder Markierung                     | normales Enter                                                                                          |
| E10 | Codeblock, Frontmatter                             | kein Tabellen-Zweig                                                                                     |

Verworfen: Sprung in dieselbe Spalte (org/Obsidian) als Vorgabe — bleibt als Einstellung
(`enterBehavior`); Zelle am Cursor teilen; Stil „kompakt bleibt kompakt“ automatisch erkennen.
Abheben: ein Undo-Schritt samt Ausrichten; Shift+Enter in einer Zelle fuegt `<br>` ein; Beenden
und Einfuegen richtig in Zitaten und Listen.

#### D3 Tab, Shift+Tab, Pfeile

| #   | Fall                                 | Entscheidung                                                                                                                                                                                                                |
| --- | ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T1  | Tab                                  | naechste Zelle, Inhalt markiert; leere Zelle: Cursor hinein                                                                                                                                                                 |
| T2  | Tab in der letzten Zelle einer Zeile | erste Zelle der naechsten Zeile, Trennzeile uebersprungen                                                                                                                                                                   |
| T3  | Tab in der allerletzten Zelle        | neue Zeile wie E1                                                                                                                                                                                                           |
| T4  | Shift+Tab                            | vorherige Zelle markiert; erste Zelle: letzte Zelle der Vorzeile; erste Kopfzelle: nichts; nie ausruecken                                                                                                                   |
| T5  | Ausrichten bei Tab/Shift+Tab         | ja, ein Undo-Schritt; schon ausgerichtet: kein Undo-Schritt                                                                                                                                                                 |
| T6  | Zeile mit zu wenigen Zellen          | wird beim Ausrichten aufgefuellt                                                                                                                                                                                            |
| T7  | Cursor vor dem ersten `\|`           | Tab springt in die erste Zelle                                                                                                                                                                                              |
| T8  | Markierung ueber mehrere Zeilen      | unveraendert: Block-Einrueckung (DECISIONS.md #27)                                                                                                                                                                          |
| T9  | Pfeil hoch/runter                    | dieselbe Zelle der Nachbarzeile, gleiche Stelle (sonst Zellende), Trennzeile uebersprungen; normaler Pfeil am Tabellenrand, mit Markierung, mehreren Cursorn, offener Vorschlagsliste oder `editor.wordWrap` ungleich `off` |
| T10 | Kontext                              | Kontext-Schluessel `markdownWorkbench.inTable`, nur bei Selektionswechsel berechnet und nur bei Wechsel gesetzt; die Pfeil-Bindungen haengen daran                                                                          |

Verworfen: Pfeile generell ueber die Extension leiten (Latenz bei jedem Pfeil). Abheben: keine
Tastenkonflikte (nur in Tabellen, nie bei Snippet/Vorschlagsliste); Pfeil bleibt in der Zelle auch
bei CJK/Emoji; Tab markiert zum Ueberschreiben.

#### D4 Kandidaten aus #86

| #   | Entscheidung                                                                                                                                                                                                                                                                                               | Verworfen, mit Grund                                                                                         |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| K1  | Ausrichten waehlt consolidate, wenn die breiteste ausgerichtete Zeile (samt Praefix, in Anzeigebreite) `maxAlignedWidth` (Vorgabe 100, 0 = aus) ueberschreitet; die Befehle Distribute/Consolidate bleiben unbedingt                                                                                       | feste Grenze ohne Einstellung                                                                                |
| K2  | `\|` + Tab: Zeile, die mit `\|` beginnt und keine Tabelle ist, bekommt Zellende und neue Zelle; Enter danach wie E4                                                                                                                                                                                        | —                                                                                                            |
| K3  | Code Action „Spalte rechtsbuendig ausrichten“ fuer Spalten ohne Ausrichtung mit nur Zahlen, setzt `--:`                                                                                                                                                                                                    | automatisch: aendert die Darstellung, bricht die Invariante aus D1                                           |
| K4  | Preview: Sortier-Knopf beim Ueberfahren des Spaltenkopfs, auf-/absteigend; neue Nachricht `sortTable` an den Host; Host sortiert die Datenzeilen der Quelle (numerisch, stabil) in einem Undo-Schritt; veraltete Dokumentversion wird ignoriert. Dazu Editor-Befehl „Tabelle nach dieser Spalte sortieren“ | nur die Anzeige sortieren (bricht die aufsteigenden `data-line`, Scroll-Sync); Klick auf die ganze Kopfzelle |
| K5  | Neue Zeile (E1, T3) uebernimmt Checkbox-Spalten: Zelle nur `[ ]`/`[x]` → neue Zeile `[ ]`                                                                                                                                                                                                                  | Mehrfachauswahl hier bauen (bleibt #56)                                                                      |

Nachzuege: `docs/ARCHITECTURE.md` § „Message protocol“ (`sortTable`), `package.json`
(Einstellung K1, Befehl K4). Abheben: Sortieren per Klick zurueck in die Quelle; Vorschlag statt
Bevormundung; Checkbox-Spalten laufen mit.

#### D5 Einstellungen und weitere Ideen

Einstellungen unter `markdownWorkbench.tables.*`, Vorgabe = das entschiedene Verhalten, defensive
Rueckfaelle wie DECISIONS.md #17, Schalter an Tastenbelegungen per `when`-Klausel:

| Einstellung           | Vorgabe                        | fuer                                       |
| --------------------- | ------------------------------ | ------------------------------------------ |
| `enabled`             | `true`                         | Hauptschalter Enter/Tab/Pfeile in Tabellen |
| `enterBehavior`       | `newRow` (`nextRowSameColumn`) | E1                                         |
| `tabSelectsCell`      | `true`                         | T1                                         |
| `tabAddsRow`          | `true`                         | T3                                         |
| `arrowNavigation`     | `true`                         | T9                                         |
| `autoAlign`           | `true`                         | E8, T5                                     |
| `maxAlignedWidth`     | `100` (0 = aus)                | K1                                         |
| `ambiguousWidth`      | `narrow` (`wide`)              | D1                                         |
| `cellLineBreak`       | `<br>` (leer = aus)            | Shift+Enter                                |
| `createFromPipe`      | `true`                         | K2                                         |
| `continueCheckboxes`  | `true`                         | K5                                         |
| `suggestNumericAlign` | `true`                         | K3                                         |
| `previewSort`         | `true`                         | K4, reist mit der `config`-Nachricht       |
| `pasteAsTable`        | `true`                         | X1                                         |
| `validate`            | `true`                         | X3                                         |

Verworfen: eine Einstellung je Randfall E2–E7.

| #   | Idee                                                                                                                                    | Entscheidung |
| --- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| X1  | CSV/TSV einfuegen als Markdown-Tabelle (`DocumentPasteEditProvider`), ausgerichtet, `\|` im Inhalt wird \\\|                            | bauen        |
| X2  | Spalte links/rechts einfuegen, loeschen, nach links/rechts verschieben; als Befehle und im Alt+M-Menue                                  | bauen        |
| X3  | Diagnose fuer Zellen jenseits der Kopfbreite (GFM zeigt sie still nicht an, Spec-Beispiel 204), Quick Fix „Spalte zum Kopf hinzufuegen“ | bauen        |

Abheben: Umsteiger-Modus per `enterBehavior`; Warnung vor still verlorenen Zellen; Einfuegen aus
Excel mit geschuetzten `|`.

### Nicht in diesem Design

- Mehrfachauswahl von Tabellen-Checkboxen in der Preview: ww3d/markdown-workbench#56.
- „Convert table to data matrix“ (Learn Markdown): Abgleich in ww3d/markdown-workbench#4.

### Konstellation

- ww3d/markdown-workbench#84 ist gemerged (`4221a9f`): pnpm, Node 26, markdown-it 15.0.2,
  `engines.vscode ^1.100.0`, Version 0.34.0. Dieser PR baut darauf auf und setzt 0.35.0.
- Parallel laeuft die Design-Runde zu ww3d/markdown-workbench#82 (neues Modul `src/diff.js`); beide
  koennen dieselbe naechste `DECISIONS.md`-Nummer beanspruchen — am Head die naechste freie nehmen.

### Nachtraege aus der Umsetzung

- **Ort im Code (Controller, 2026-09-28, auf #90):** D1 heisst "eigener Code statt
  Bibliothek", nicht "in `src/editing.js`". Das Tabellenmodell und die Tabellen-Features
  stehen im Fachordner `src/tables/` (reine Module ohne `vscode`-Import, wo moeglich:
  `row.js`, `blocks.js`, `detect.js`, `width.js`, `format.js`, `grid-ops.js`,
  `sort.js`, `csv.js`), `src/editing/` ruft nur die Zweige auf. Weil der PR
  `src/editing.js` anfasst, wurde es vorher nach Fach in `src/editing/` aufgeteilt
  (Grenze 300 Zeilen je Einheit, `.agents/rules/code.md`); ebenso `src/render.js` und
  `src/views.js`.
- **Randlose Zeile mit Listen-Anfang:** Beim Ausrichten einer randlosen Tabelle wuerde
  eine erste Zelle wie `*` oder `1.` mit Fuellleerzeichen zu `* | x`, und markdown-it
  laese die Zeile als Listenpunkt - die Tabelle waere dort zu Ende. Solche Zeilen behalten
  die erste Zelle direkt am Strich (`*| x`); gefunden vom Zufalls-Test der
  Inhalts-Invariante.
- **T9 und Zeilenumbruch:** Pfeil hoch/runter in der Zelle laeuft nur mit
  `editor.wordWrap: off` (sprachbezogen gelesen). Ob VS Code fuer Markdown standardmaessig
  umbricht, ist nicht belegt; `markdown-basics` setzt es nicht.
- **Dokumentversion fuer `sortTable`:** Die `render`-Nachricht traegt jetzt die
  Dokumentversion; die Preview schickt sie mit, der Host verwirft einen Klick auf einen
  veralteten Stand.
- **Tabellen-Zeilen dieses Eintrags:** `|` in Code-Spans der uebernommenen Tabellen ist als `\|`
  geschuetzt - ungeschuetzt trennt er die Zelle (D1), die Zeilen waeren zerbrochen. In X1 steht
  der zweite Code-Span (`\|`) ohne Backticks als `\\\|`: als Code-Span `` `\\|` `` zeigte die
  Preview zwar `\|`, Prettier liest `\\` aber als geschuetzten Backslash und trennt die Zelle.
- **D1, Nachtrag - Erkennung per markdown-it-Block-Parse** (Entscheid des Controllers vom
  2026-09-28T0312Z auf ww3d/markdown-workbench#91): Welche Zeilen Tabellenzeilen sind und wo
  ihr Inhalt beginnt, liefert ein Block-Parse mit der markdown-it-Instanz der Preview
  (`src/render/parser.js`, je Dokumentversion zwischengespeichert); die Zellen mit Positionen
  und die getippte Kopfzeile (eine Absatz-Zeile, deren Inhalt mit `|` beginnt) bleiben
  eigener Code. Das dreht die Verwerfung in D1: Deren Gruende (keine Zellpositionen, keine
  Kopfzeile ohne Trennzeile) gelten fuer diesen Teil nicht, und die Nachbildung der
  Preview-Erkennung von Hand hielt nicht dicht - nach zwei Nachbesserungen wichen im
  Differenz-Fuzz noch 502 von 20 000 Dokumenten (Reviewer) bzw. 53-82 je Seed ab (Listen,
  Zitate, HTML-Bloecke, Einrueckung). Preis: ein Parse je Aenderung (bei 5000 Tabellenzeilen
  rund 40 ms), Tippen in einer Zelle behaelt den Zwischenspeicher. Tippen auf einer anderen
  Zeile mit `|` (Prosa, Code-Span, Shell-Pipe) wuerde den Kontext-Schluessel je Taste einen
  Parse kosten (20 000 Zeilen: 18 ms); er wird dort erst nach einer Tipp-Pause von 400 ms
  neu gesetzt - laenger als der Abstand zweier Tasten beim normalen Tippen (80-300 ms) -,
  ein veralteter Schluessel ist harmlos (die Pfeile fallen auf die normale Bewegung zurueck),
  und ein Editor-Wechsel verwirft das wartende Setzen. E4 schreibt nur, wo der Block-Parse danach eine Tabelle sieht. Zeilen
  und Zellen werden wie in markdown-it mit `trim()` gekuerzt, also auch um NBSP und U+3000;
  beim Ausrichten wird solcher Leerraum am Zellrand zu Leerzeichen. Geprueft gegen die
  Preview-Instanz: die Tests in `tests/tables/detect.test.js` (Korpus, Listen und Zitate,
  HTML-Bloecke, Zufallsdokumente mit festen Seeds).
- **Distribute/Consolidate mit Auswahl** (Review-Runde 1 auf #91, F1, Entscheid des
  Controllers): Mit einer Auswahl richten die Befehle jede Tabelle aus, die die Auswahl
  beruehrt, sonst die Tabelle am Cursor - in einem Undo-Schritt. Verworfen: das fruehere
  Ausrichten nach Zeilenbereich (dann saehe der Editor eine andere Tabelle als die Preview).
- **Enter im Zitat-Praefix der Kopfzeile:** fuegt darueber eine Zeile mit dem Praefix ein,
  statt das Zitat zu teilen und den Kopf aus der Tabelle zu schieben.
- **Ein Tabellen-Reflow** (Nachzug nach ww3d/markdown-workbench#89, Anordnung des Controllers auf
  #90): #48 hatte den alten Reflow (`splitRow` / `isSeparatorRow` / `reflowTable`) nach
  `src/markdown/syntax.js` verlegt, dieser Eintrag ersetzt ihn durch das Tabellenmodell. Die eine
  Funktion ist jetzt `reflowTable` in `src/tables/format.js`; Distribute/Consolidate und die
  Stil-Angleichung des Clipboard-Diffs rufen beide sie, `syntax.js` behaelt nur `CHECKBOX_RE`.
  _(Nachtrag State Audit 2026-09-29T2304Z: Distribute/Consolidate rufen nicht `reflowTable`,
  sondern je Tabelle `toGrid`/`formatGrid` (`reflowTableCommand`), nur die Stil-Angleichung
  ruft `reflowTable`; `syntax.js` behaelt ausserdem `checkboxBoxPos`.)_ Die
  markdown-it-Instanz ohne `vscode`, die #48 ueber ein spaetes `require` in `render.js` erreichte,
  ist hier `src/render/parser.js`.
- **Version nach den Nachzuegen:** 0.36.0. Die 0.35.0 unter "Konstellation" ist der Stand der
  Design-Runde; 0.35.0 traegt ww3d/markdown-workbench#89, 0.35.1 den Fix
  ww3d/markdown-workbench#100, beide stehen im `CHANGELOG.md` als eigene Abschnitte unter 0.36.0.

## 50. TypeScript 7 and a bundled webview split into modules (#2, #92)

Design round of 2026-09-28 (tracking issue #92, audit gaps in its sub-issue #97). The
decision log of that round follows (German, as written; its title dropped and its headings
moved two levels down to fit this file); the notes from the implementation are at the end.
It revises #7 ("no build step for the view"), #21 (the entry-export trap), the vendor part of
#46 and the scroll part of #34; each carries an addendum.

| Feld           | Wert                                                                                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stempel        | 2026-09-28T0946Z                                                                                                                                                                |
| Repo / Basis   | ww3d/markdown-workbench, `main` nach dem Merge von ww3d/markdown-workbench#89 und #91 (bei Niederschrift `4221a9f`, 0.34.0; Fakten von den PR-Heads `88f52ff` / `20ea905`)      |
| Anlass         | Entscheid des Maintainers vom 2026-09-28T0926Z plus Nachtrag 0927Z auf ww3d/markdown-workbench#90; ww3d/markdown-workbench#2                                                    |
| Tracking Issue | ww3d/markdown-workbench#92                                                                                                                                                      |
| Runde          | Design-Session `design-mw-ts7`; Entscheider: Controller `ctrl-markdown-workbench-3`; Vorlage `design/ts7-webview/2026-09-28T0934Z-design-round.md` (volle Form je Entscheidung) |
| Audit-Gate     | neuer State Audit auf `main` nach beiden Merges, als erster Auftrag (Entscheid des Controllers, Frage 1); `audit/ist-stand-2026-09-27T2058Z.md` gilt als verbraucht             |
| Review-Modus   | `hard v4`                                                                                                                                                                       |

Ablage im Repo: Das Repo fuehrt keine `docs/decisions/`; der dev-PR traegt den Inhalt als neuen
Eintrag in `docs/DECISIONS.md` (naechste freie Nummer am Head) ein.

### Rahmen (Maintainer, vor der Runde)

- Ladeweg der Webview: eigener tsdown-Eintrag nach `dist/`, alles sauber aufgeteilt, ein Script-Tag mit
  Nonce.
- TypeScript 7 fuer die Webview-Module und den Rest von `src/` (ww3d/markdown-workbench#2) in
  **demselben** PR, ausdruecklich statt der vom Controller empfohlenen zwei PRs. `tsc` 7 prueft nur
  Typen; uebersetzt wird vom Bundler bzw. beim Test durch Node.
- Dauerfreigabe: alle Abhaengigkeiten auf neuestem Stand; ein Major-Sprung bleibt eigener Commit mit
  eigenem Testlauf (`AGENTS.md` § "Dependencies" Regel 3).
- Schnell, sauber, Stand der Technik; messbare Leistungsziele mit Benchmark.
- Start erst auf `main` nach dem Merge von ww3d/markdown-workbench#89 und #91.

### Ausgeraeumte Fehlannahmen

- ww3d/markdown-workbench#2 (2026-06) nennt Node 22, `tsx` und "CI unveraendert" — ueberholt: Node 26
  entfernt Typen ohne Flag, ein Loader ist nicht noetig.
- "Ein Script-Tag" gilt heute nicht: `getWebviewHtml` laedt zwei (`media/morphdom.js` vor
  `media/webview.js`, `docs/DECISIONS.md` #46).
- Der Tab-Wechsel laedt die Webview nicht neu (`retainContextWhenHidden: true` an beiden
  Panel-Stellen, idempotenter Render `docs/DECISIONS.md` #45); ein Nachlade-Teil fuer schnelleren
  Start braechte dort nichts.
- Es gibt keine Messung zu Webview-Start, Aktivierung, Bundle-Groesse oder Typpruefung; `bench/`
  misst Scroll, Fold, Render (und auf den PR-Branches Anker und Tabellen), ausdruecklich nicht als Gate.
- `@types/vscode` "latest" (1.138.0) wuerde gegen APIs pruefen, die `engines.vscode ^1.100.0` nicht
  zusichert.

### Entscheidungen

#### D1 Aufbau und Build der Webview

- Fachordner `src/webview/` mit Unterordnern je vorhandenem Abschnitt (Scroll-Sync, Minimap, Folding,
  Scroll-Spy, TOC, Breadcrumb/Sticky, Tabellen-Sortierknopf); Namen der Unterordner legt der dev nach
  den Abschnitten fest und nennt sie im PR.
- CSS neben dem Code, vom Modul importiert; `@tsdown/css` zieht es zu `dist/webview.css`.
- Ein IIFE-Bundle `dist/webview.js`, keine Nachlade-Teile, ein Script-Tag mit Nonce.
- morphdom aus dem npm-Paket eingebuendelt; `media/morphdom.js` und das zweite Script-Tag entfallen.
- Tests importieren die Module direkt (kein `new Function`, keine String-Ersetzung von
  `acquireVsCodeApi`); dazu ein Smoke-Test, der das gebaute `dist/webview.js` im DOM-Mock startet.
- `localResourceRoots` auf `dist/` plus `media/`; CSP inhaltlich wie heute (`docs/DECISIONS.md` #22).
- Freigegebene neue Namen: `src/webview/`, `dist/webview.js`, `dist/webview.css`, Paket
  `@tsdown/css`.
- Verworfen: CSS als eigener Baum mit `@import`-Einstieg (trennt Zusammengehoeriges); ESM-Script
  (`type="module"`, kein Gewinn bei einem Bundle); Nachlade-Teile (widerspricht einem Tag, kein Gewinn
  bei `retainContextWhenHidden`); morphdom-Kopie behalten (zweites Tag, Version von Hand).
- Architektur-Abgleich: `docs/ARCHITECTURE.md` § "Module layout" und § "Webview loading";
  revidiert `docs/DECISIONS.md` #7 ("no build step for the view") und den Vendor-Teil von #46;
  #23 (Schnitt entlang vorhandener Funktionen) gilt weiter.

#### D2 Form der TypeScript-7-Umstellung

- ESM-Quellen (`"type": "module"`, `import`/`export`, `.ts`-Endungen in relativen Imports); CJS nur
  aus dem Bundler (`dist/extension.cjs`). Der Bundle-Smoke bleibt und belegt, dass die Rolldown-Falle
  aus `docs/DECISIONS.md` #21 nicht mehr greift.
- `tsconfig.base.json` nach `tech/common/typescript.md` § "Baseline"; zwei Pruefbereiche: Host mit
  Node-Typen ohne DOM, Webview mit DOM ohne Node-Typen; das Protokoll lesen beide.
- `@types/vscode` 1.100.0 (passend zu `engines.vscode`), Grund an der Pin-Stelle; `@types/node`
  26.x.
- Tests als `*.test.ts` unter `node --test`, Coverage mit c8; Attrappen mit Typen an den Grenzen,
  kein `as T` als Ausweg.
- Commit-Schnitt: Werkzeug (tsconfig, `typecheck`, Biome-Regeln des Overlays) → ESM-Umstellung → je
  Fachordner `.js`→`.ts` mit Typen → Webview-Schnitt (D1) → Messung (D3); jeder Schritt gruen.
- Verworfen: JSDoc + `@ts-check` als Zwischenschritt; zwei PRs (Maintainer).
- Ausserhalb: Playbook-Manifest `consumers/markdown-workbench.yml` auf `stack: typescript` —
  Traeger ww3d/playbook#336.
- Architektur-Abgleich: `CLAUDE.md` (Stack-Satz, Override-Zeile zum Overlay), `docs/ARCHITECTURE.md`
  § "Module layout", `docs/DECISIONS.md` #7 und #21, `CONTRIBUTING.md`, `build.ps1`.

#### D3 Leistungsziele und Benchmark

- Groesse als hartes Gate im Gate-Lauf (eigenes kleines Skript, gzip-Bytes, kein neues Paket).
- Zeiten als Benchmark mit Zielwert, nicht als Gate (`bench/README.md`; Praxis aus #89); Median aus 21
  Laeufen; "vorher" auf dem Basis-Head vor dem ersten Commit, "nachher" auf dem PR-Head, beides im
  PR-Body.
- Ziele:

| Nr. | Messgroesse                                                                       | Ziel                                                         | Art       |
| --- | --------------------------------------------------------------------------------- | ------------------------------------------------------------ | --------- |
| P1  | Webview-Auslieferung gz, JS + CSS (am `4221a9f`: 41 418 B inkl. morphdom)         | ≤ 28 000 B                                                   | Gate      |
| P2  | `dist/extension.cjs` gz                                                           | ≤ Basis + 2 %                                                | Gate      |
| P3  | Webview-Start: HTML gesetzt bis erster Render sichtbar (CDP-Harness, 400 Bloecke) | ≤ Basis, Ziel −15 %                                          | Benchmark |
| P4  | Update: morphdom-Edit (`bench/render-bench.js`)                                   | ≤ Basis + 5 %                                                | Benchmark |
| P5  | Typpruefung `tsc` 7, ganzes Repo, kalt                                            | ≤ 2 s und ≥ 5× schneller als TypeScript 6 auf demselben Baum | Benchmark |
| P6  | Testlauf `node --test` gesamt                                                     | ≤ Basis + 10 %                                               | Benchmark |
| P7  | Aktivierung bis `ready` im Bundle-Smoke                                           | ≤ Basis + 5 %                                                | Benchmark |
| P8  | VS-Code-Neustart bis Inhalt sichtbar (Sofort-Stand, D4-2)                         | Inhalt vor dem ersten Host-Render sichtbar; Zeit gemessen    | Benchmark |

- P1 wird gemessen, nicht gesenkt: ist die Grenze nicht erreichbar, meldet der dev das mit Messwert.
- Verworfen: Zeit als hartes Gate (flackert, widerspricht `bench/README.md`); `size-limit`
  (Abhaengigkeit fuer 20 Zeilen).

#### D4 Alleinstellungsmerkmale

1. **Typisiertes Nachrichtenprotokoll** `src/webview/protocol.ts` (Name freigegeben): eine Union aller
   Nachrichten beider Richtungen, beide Seiten importieren sie; kein Laufzeitcode.
2. **Sofort-Stand nach VS-Code-Neustart:** die Webview legt das zuletzt gerenderte HTML samt
   Scroll-Stelle in `setState`, zeigt es beim Wiederherstellen sofort und ersetzt es beim ersten
   echten Render. Feste Obergrenze fuer den State, mit Test fuer beide Seiten der Grenze; darueber
   kein Sofort-Stand.
3. Groessen-Gate (D3).

- Verworfen: Nachlade-Teile; Nutzer-Befehl "Preview Performance" (Nische, doppelt zu `bench/`).
- Abheben: nach einem Neustart sofort da; Host und Webview koennen nicht aneinander vorbei reden;
  jede Groessenzunahme faellt im Gate auf — bei keinem Vergleichsprojekt gefunden (GitLens, Markdown
  Preview Enhanced, Foam, VS-Code-Preview; "nicht gefunden", kein Gegenbeleg).

#### D5 Review-Modus und Zuschnitt

- `hard v4`; Commit-Schnitt nach D2.

### Vorab-Klaerung durch den dev

Nicht nachgelesen in der Runde; der dev klaert sie zuerst und meldet, falls einer den Plan kippt:

- `tsc` 7.0 mit Projekt-Referenzen (`-b`), sonst zwei `tsc -p`-Aufrufe.
- `url()` auf `media/codicon.ttf` durch `@tsdown/css`.
- Groessengrenze von `vscode.setState` in Webviews (setzt die Obergrenze aus D4-2).

### Nicht in diesem Design

- Strengere CSP (`docs/DECISIONS.md` #22, bleibt aus).
- Playbook-Manifest: ww3d/playbook#336.

### Konstellation

- ww3d/markdown-workbench#89 (Clipboard-Diff, `src/clipboard-diff/`, `docs/folder-rules.md`,
  Integrationstests mit `@vscode/test-electron`) und #91 (Tabellen-Editing, `src/{editing,render,
tables,views}/`) sind vor dem Start gemergt; beide aendern `media/webview.js`/`.css`.
- Offene Punkte aus #90, die nach dem Merge von #89 noch an #91 haengen (Reflow-Zusammenfuehrung,
  `src/`-Ausnahme in `docs/folder-rules.md`), gehoeren nicht zu diesem Design.

### Nachtraege der Umsetzung

**Entscheide des Maintainers** (im Chat an den Controller, nachgetragen als Kommentare auf #92):

- **Start auf dem Kopf von #91** (2026-09-29T2248Z): Die Umstellung beginnt sofort auf `98f7590` (Head von
  ww3d/markdown-workbench#91) statt auf `main` nach beiden Merges; der PR zielt zuerst auf den Branch von #91,
  der State Audit `audit/ist-stand-2026-09-29T2304Z.md` beschreibt `98f7590`. Hebt "Start erst auf `main`" im
  Rahmen oben auf.
- **Atlas-nah, mit Abgleich** (2026-09-29T2254Z): Wo der Decision-Log die Form offen laesst, gilt die Form von
  ww3d/atlas. Alle Ausgabe- und Zwischenpfade kommen aus `eng/layout.ts` (Umsetzungsentscheide unten); der
  PR-Body gleicht Ausgabe-Layout, Wurzelskripte, Versionierung, reproduzierbare Pakete und Pflichtangaben je
  Punkt mit Atlas ab.
- **Nichts kuerzen** (2026-09-29T2256Z): nichts auslagern, verschieben oder senken; eine Luecke mit bekanntem
  Fix in einer Datei, die dieser PR aendert, wird hier gefixt. Darum traegt der PR alle Punkte aus
  ww3d/markdown-workbench#97 (Luecken des State Audits, darunter die 44 `[teilweise #97]`-Marker in
  `docs/ARCHITECTURE.md`); eine verfehlte Zielgroesse wird mit Messwert gemeldet, nicht gesenkt.
- **Vier Zusatzpunkte** (2026-09-29T2303Z): (1) Neustart ohne neues Rendern - der Webview-State traegt
  `BUILD_ID` und einen Schluessel, der Host rendert bei Gleichstand nicht und schickt nur die Dokumentversion
  (neue Nachricht `version`); (2) Ladezeit-Benchmark vom Skriptbeginn bis `ready`; (3) Groessen-Gate
  zusaetzlich auf die ungepackten Bytes von `dist/webview.js` und `dist/webview.css` (aendert D3), Grenze nicht
  hoeher als der Wert nach dem Umbau; (4) feste CSS-Zielversion auf die Chromium-Version des Mindest-VS-Code.
  Nicht aufgenommen: Block-Delta, Entprellen beim Tippen, Abloesung von `retainContextWhenHidden`;
  `content-visibility: auto` bleibt verworfen (#47).
- **`happy-dom` fuer den Webview-Smoke** (2026-09-29T2324Z, auf Frage zu REQ-035): neue devDependency
  `happy-dom` 20.14.5 (MIT, exakt gepinnt, Registry-Stand des Tages), nur fuer `scripts/webview-smoke.ts`,
  nicht im `.vsix`. Grund: die DOM-Attrappe der Unit-Tests parst kein HTML, ein Smoke darin zeigte nichts.
  Verworfen: (B) Headless-Chrome ueber den Bench-Harness - Chrome auf jeder Gate-Maschine noetig, Suchpfade
  unter Windows fehlen, flackeranfaellig; (C) die DOM-Attrappe um einen HTML-Parser erweitern - gross und
  fehleranfaellig.
- **Testumbenennung** (Entscheid des Controllers, #97): `the breadcrumb reserves body top padding from its
measured height` heisst jetzt `the breadcrumb reserves body top padding from its computed height` - die
  Hoehe ist seit #36 berechnet. Einzige gewollte Differenz im Namensabgleich der Webview-Tests (REQ-034).

**Umsetzungsentscheide** (dev, mit Grund):

- **ESM vor `typecheck`.** Der Commit-Schnitt aus D2 (erst Werkzeug, dann ESM) ist getauscht: unter
  `module: nodenext` liest `tsc` eine `.ts`-Datei ohne `"type": "module"` als CommonJS und lehnt ihre
  `import`/`export` ab (TS1295). Die ESM-Umstellung ging darum voraus.
- **`tsc -b` mit vier Pruefbereichen** unter `tsconfig.json`: Host (`tsconfig.host.json`, Node-Typen, kein DOM,
  liest `src/webview/protocol.ts` mit), Webview (`tsconfig.webview.json`, DOM, keine Node-Typen), Tests
  (`tsconfig.tests.json`, DOM und Node - Tests laden beide Seiten) und Werkzeug (`tsconfig.tools.json`:
  `tsdown.config.ts`, `eng/`, `scripts/`, `bench/`). Projekt-Referenzen statt mehrerer `tsc -p` (Vorab-Klaerung
  1: `tsc` 7.0 kann `-b` mit `noEmit`). Die Build-Info liegt unter `artifacts/obj/`.
- **`skipLibCheck` und lokale Shims.** Zwei Fremd-Typen sind kaputt: `markdown-it-front-matter` 0.2.4 importiert
  `markdown-it/lib`, das markdown-it 15 nicht mehr exportiert (`src/render/markdown-it-lib.d.ts`), und die
  Shiki-Typen nennen `WebAssembly`, das `@types/node` nicht deklariert (`src/render/shiki-webassembly.d.ts`).
  Dazu `src/webview/page/stylesheets.d.ts` (CSS-Importe der Module) und `src/webview/render/morphdom.d.ts`
  (Default-Export unter `nodenext`). `skipLibCheck` stand zuerst aus; es ist an, weil jeder Pruefbereich die
  Deklarationen von Node, VS Code und DOM neu pruefte und das die kalte Typpruefung verdoppelte (P5). Die
  eigenen Quellen bleiben voll geprueft, die Shims decken die kaputten Fremd-Typen.
- **Waechter statt `!`.** `noUncheckedIndexedAccess` macht jeden Index-Zugriff `T | undefined`; wo der Wert
  durch den Ablauf sicher da ist, steht ein Waechter mit Fruehausstieg oder `?? ''`, kein `!` - der ist derselbe
  Ausweg wie `as T` (REQ-018). Preis: tote Zweige senken die Zweig-Coverage; die Schwellen bleiben unveraendert.
- **`module.registerHooks` und `?gen=N` fuer frische Modulgraphen.** Die `vscode`-Attrappe ist ein virtuelles
  Modul, dessen Named-Exports aus der beim Laden installierten Attrappe entstehen (`tests/helpers/vscode-hooks.ts`,
  geladen ueber `node --import ./tests/helpers/setup.ts`); jede `src/`-URL traegt eine Generation, `loadFresh` erhoeht
  sie und bekommt einen frischen Graphen mit eigenem Modulzustand. Verworfen: `mock.module()` (Stufe "Early
  development", braucht ein Stub-Paket, liefert keinen frischen Graphen) und `module.register()` (seit Node 26
  abgekuendigt).
- **Integrationssuite als Bundle.** Das Mindest-VS-Code 1.100 laeuft auf Node 20.19 (Electron 34) ohne
  Type-Stripping und laedt keine `.ts`-Datei; Suite und Treiber-Extension baut `tests/integration/tsdown.config.ts`
  vor dem Lauf zu CJS nach `artifacts/obj/integration`, die Faelle stehen in einer statischen Liste.
- **Shiki per `import()`.** `initHighlighter` laedt Shiki dynamisch; Rolldown legt den Kern in einen eigenen
  Lazy-Chunk. `dist/extension.cjs` sinkt dadurch von 154 572 auf rund 75 600 B gzip. Shiki laedt im Hintergrund
  direkt nach `activate`; der Gewinn ist die Zeit bis zum ersten Render (P7), nicht die Zeit bis zum ersten
  hervorgehobenen Render.
- **P2 misst den mit `extension.cjs` geladenen Host-Code** (Abweichung von D3, Entscheid des Controllers
  `ctrl-markdown-workbench-5` vom 2026-09-30): `dist/extension.cjs` plus jede Datei, die es direkt per `require`
  laedt, aus dem Bundle gelesen (`hostFiles` in `scripts/size-gate.ts`), Grenze unveraendert 157 663 B. Nur
  `extension.cjs` haette nach dem `import()` von Shiki eine Luecke gemessen, die der Umbau selbst schafft;
  Grammatik- und Theme-Chunks bleiben aussen vor wie an der Basis.
- **`sideEffects` mit `./src/render/index.ts`.** Das Barrel registriert beim Laden den Shiki-Fence-Renderer; mit
  nur `"*.css"` liess Rolldown es weg, und das Bundle haette still nur Klartext-Code gerendert (der Bundle-Smoke
  fing es: 0 von 18 Sprachen). `./src/webview/main.ts` steht aus demselben Grund darin: der Bench-Einstieg
  importiert es nur fuer seine Seiteneffekte.
- **`eng/layout.ts`** ist die eine Stelle aller Ausgabepfade (Atlas-Namen unter `artifacts/`: `packages`,
  `TestResults`, `obj`, `tmp`, `toolset`); `dist/` bleibt an der Wurzel, weil `package.json` `main` und das
  `.vsix` es nennen. `toolset` nimmt das heruntergeladene VS Code der Integrationstests auf und ersetzt
  `.vscode-test/` an der Wurzel (Q3); der Compile-Cache der Testprozesse liegt unter `obj` in
  `artifacts/obj/compile-cache` (kein Atlas-Name). Die Paketschicht `tests/package/` laeuft nach dem Build
  (`pnpm run test:package`, im Task `Package`), nicht im Unit-Lauf (Q2, Entscheid des Controllers im
  PR-Kommentar 2026-09-30T0522Z). Tests in `tests/eng/layout.test.ts` pruefen jedes unvermeidliche
  Pfad-Literal gegen diese Stelle.
- **`target: 'chrome132'`** im Webview-Eintrag von `tsdown.config.ts`: microsoft/vscode, Branch `release/1.100`,
  `.npmrc` `target="34.5.1"`; releases.electronjs.org fuehrt Electron 34.5.1 mit Chrome 132.0.6834.210. Das Ziel
  gilt auch fuer das CSS, das damit nie darunter heruntergerechnet wird (Test `the webview stylesheet build
keeps nesting and color-mix as written`).
- **Sofort-Stand nach Neustart:**
  - Obergrenze `MAX_RESTORE_HTML_CHARS` = 512 KiB (`src/webview/restore/state.ts`). VS Code nennt fuer
    `setState` keine Grenze (Vorab-Klaerung 3), schickt aber bei jedem Aufruf den ganzen State als JSON an den
    Host und bettet ihn beim Wiederherstellen URL-kodiert in das Startskript. Das gerenderte HTML von
    `README.md`, `docs/ARCHITECTURE.md` und `CHANGELOG.md` misst 41,6 bis 59,0 KiB (mit Shiki); die
    vorgeschlagenen 64 KiB haetten kaum Platz gelassen. Darueber wird nur `documentUri` und `BUILD_ID` gespeichert.
  - Schluessel: SHA-256 (hex, volle Laenge) ueber Render-Einstellungen, Theme-Art, Zustand des Highlighters und
    den Text (`renderKey` in `src/views/restore.ts`); gekuerzt spart nichts neben dem HTML, eine Kollision zeigte
    ein falsches Dokument.
  - Warten auf den Highlighter: passt der Stand nur zum hervorgehobenen Render und laedt Shiki noch, behaelt der
    Host ihn und wartet (`onHighlighterSettled`, hoechstens `HIGHLIGHTER_WAIT_MS` = 5000 ms), statt erst Klartext
    und dann hervorgehoben zu rendern (zwei Renders, sichtbarer Ruecksprung).
  - Gedrosseltes `setState`: Render und Scroll planen das Schreiben nur; geschrieben wird nach
    `STATE_SAVE_QUIET_MS` (250 ms) Ruhe - eine Scroll-Folge kostet einen Aufruf, nicht einen je Frame.
  - `BUILD_ID` setzt tsdown per `define` aus der Paketversion in beide Bundles; ein Stand einer anderen Kennung
    wird in der Webview verworfen.
- **Abhaengigkeiten:** `typescript` 7.0.2, `@types/node` 26.x (folgt dem Node-Major, `CLAUDE.md`), `@tsdown/css`
  0.23.0 und `morphdom` 2.7.8 exakt gepinnt. `@types/vscode` steht bewusst exakt auf 1.100.0 statt "latest"
  (1.138.0): die Typpruefung soll nur APIs kennen, die `engines.vscode ^1.100.0` zusichert; `package.json` traegt
  keinen Kommentar, darum steht der Grund hier (REQ-010).
