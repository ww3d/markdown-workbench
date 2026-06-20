# Markdown Workbench

VS Code extension for working with markdown checklists. Renders markdown
(markdown-it, the same engine as the built-in preview) with clickable
checkboxes; every toggle is mirrored surgically into the source file.

## Features

### Workbench view
- Click a checkbox row to toggle it
- Ctrl+Click / Shift+Click selects multiple tasks; clicking a checkbox inside
  the selection toggles all selected tasks in parallel, as a single
  WorkspaceEdit (one undo step)
- Toggles replace exactly one character (`[ ]` <-> `[x]`); whitespace,
  HTML comments and everything else stay byte-identical
- Supported markers: `- [ ]`, `* [ ]`, `+ [ ]`, `1. [ ]`, nested, and the
  compound form `1. - [ ]` (a numbered item whose content is a one-line
  bullet task) - both forms toggle and continue on Enter alike
- Editing-oriented rendering, deviating from the built-in preview
  (docs/DECISIONS.md #25): numbered task items keep their visible number
  (mixed lists count without gaps), and `[ ]` / `[x]` without a label
  renders as a clickable task row instead of literal text - so fresh
  Enter-continuation lines don't flicker while typing
- `[ ]` / `[x]` inside table cells render as clickable checkboxes too,
  toggled surgically by line + occurrence (direct toggle, not part of
  multi-select; header row excluded). If a cell contains exactly one
  checkbox, clicking anywhere in the cell toggles it.
- Esc clears the selection

### Two modes (mirroring the built-in markdown preview)
- **Preview panel** (`Open Workbench` / `Open Workbench to the Side`): opens
  next to or in place of the active group; the source file stays open and the
  panel closes independently. One panel per document; closes automatically
  when the source document is closed.
- **Custom editor** (`Open as Workbench`): swaps the active editor in-place
  in the same tab (reopenActiveEditorWith, like the built-in); "Reopen as
  source file" swaps back in that tab. Also reachable via
  "Reopen Editor With...".
- Both modes mark their tabs with the workbench icon and a
  "Workbench: <file>" title, like the built-in preview marks its tabs.

Menu placement mirrors the built-in preview: two icon buttons at the end of
the tab row (the workbench glyph opens to the side, Alt held switches it to
open-in-active-group; `$(preview)` reopens the editor as workbench), tab
context menu entries in group `1_open`, and an explorer context entry.

### Rendering
- Full markdown via markdown-it (`html: true`, `linkify: true`): tables,
  links, images, blockquotes, nested lists, fenced code
- Syntax highlighting via shiki with the VS Code `dark-plus` / `light-plus`
  themes, following the active color theme kind (re-renders on theme switch).
  Preloaded languages: powershell, bat, shellscript, json, jsonc, yaml, ini,
  xml, javascript, typescript, html, css, markdown, csharp, python, sql,
  diff, docker. Unknown languages fall back to plain blocks.
- YAML frontmatter (`---` block at file start) renders as a property card:
  flat `key: value` pairs become a key/value grid, anything nested falls back
  to a raw monospace card
- HTML comments are hidden in the view and preserved in the source
- Theme-aware styling from `--vscode-*` tokens: configurable centered measure (setting `markdownWorkbench.preview.maxWidth`: `github` = 980px default, `narrow` = 72ch; applies live), hairline
  borders, rounded code blocks; tables with horizontal hairlines only, uppercase muted sticky headers (column labels stay visible while scrolling long tables), zebra striping and row hover

### Minimap
An editor-style minimap rail shows a scaled clone of the rendered content
with a draggable viewport slider (editor minimap theme tokens); the slider
can be grabbed and dragged like the editor minimap (no jump on grab), a
click on the rail outside it jumps and centers, and the rail hides
automatically when the document fits the viewport.
Configurable like the editor minimap via `markdownWorkbench.minimap.*`:
`enabled`, `size` (`proportional` pans for long documents, `fill` maps the
document linearly onto the rail so the slider never drifts from the
scrollbar, `fit` downscales without stretching), `showSlider` (`mouseover`
default / `always`), and `side` (`right` / `left`). Changes apply live.

### Scroll sync
Bidirectional and pixel-accurate between the view and any visible text
editor of the same document, using the built-in preview's fractional-line
algorithms: positions interpolate between `data-line` mapped elements
(markdown-it token maps), multi-line code fences scroll proportionally, and
echo suppression works in both directions. Opening any view jumps straight
to the source editor's position; the way back restores the synced position.

### List continuation on Enter
In the text editor (not the view), pressing Enter inside a list item inserts
the next marker:

- `- foo` + Enter -> `- ` on the next line
- `- [x] foo` + Enter -> `- [ ] ` (always unchecked)
- `3. item` + Enter -> `4. ` (delimiter preserved: `3)` -> `4)`;
  `3. [x] foo` -> `4. [ ] `)
- Enter in the middle of a numbered sequence renumbers the following
  siblings of the same level and delimiter, so the source stays readable
- Indentation is preserved; Enter on an empty item removes the marker
  (terminates the list)
- Enter on a continuation line (a wrapped or Shift+Enter-hung line, see
  below) continues its item too: a fresh sibling at the item's level, with
  the following siblings renumbered as usual - including when the
  continuation line sits below deeper-indented children of the item (the
  next sibling is still created at the parent's level)

### Hanging continuation lines on Shift+Enter
Shift+Enter inside a list item, or on one of its continuation lines, breaks
the line and indents the new one with whitespace to the item's content column
- markerless, no number, so the text hangs aligned under the item's text:

- `2. ` + Shift+Enter -> a new line indented by 3 spaces (under `2. `)
- `   - [ ] ` + Shift+Enter -> indented by 9, `1. - [ ] ` likewise
- Text right of the cursor moves down onto the new line

Outside a list - or with the cursor still inside the marker/indentation -
Shift+Enter falls through to the editor default. Because the hung lines are
markerless and indented to the content column, Enter afterwards
still counts the sequence correctly - the same shape external reflow
extensions (e.g. marvhen.reflow-markdown, Alt+Q) produce when they wrap long
list items.

### List nesting on Tab / Shift+Tab
On list lines, Tab indents and Shift+Tab outdents (multi-line selections
supported). The indent unit is adaptive per CommonMark: marker + gap width,
so `- ` nests by 2 and `10. ` by 4. Non-list lines fall through to the
default Tab/outdent; Tab keeps working for suggest, snippets and inline
suggestions via the when clause.

A single numbered item starts a new sublist on Tab; if the deeper level
already has a preceding sibling the item joins its sequence (number = next
after that sibling), otherwise it restarts at `1` (delimiter preserved), so
tabbing several items into the same sublist numbers them `1.` `2.` `3.`
instead of leaving duplicate markers. Shift+Tab joins the target-level
sequence (number = next after the preceding sibling there). In both
directions the sequence left behind closes its gap, and Shift+Tab also
renumbers the target sequence. Dash items under numbered parents (and vice
versa) are never rewritten - each level keeps its list type.

With `markdownWorkbench.indent.respectExistingStops` on (off by default),
Tab/Shift+Tab snap onto the indentation levels that already exist around the
line - the content columns of the surrounding list items - instead of always
shifting by one marker width; with no matching level they fall back to the
marker-width step. This keeps items aligned under parents whose marker width
differs from the moved item's.

### Ordered list outline in the view
Ordered lists render with classic outline markers by depth: `1.` on level 1,
`a.` on level 2, `i.` on level 3, repeating from level 4. Only `ol` levels
count, and each level renumbers for itself. The markers are pure preview
styling - the source always keeps portable CommonMark digit markers
(`1.` / `1)`), never letters.

### Smart Ctrl+Delete (opt-in)
With `markdownWorkbench.editing.smartForwardDelete` on (off by default),
Ctrl+Delete in a markdown editor pulls an indented continuation line up when
the cursor is at the end of a line's visible content: it removes the line
break and the next line's leading indentation, joining its text with exactly
one space. In every other position it is the plain Delete Word Right.

### Custom list markers (opt-in)
`markdownWorkbench.lists.extraMarkers` lets the editor treat extra,
non-CommonMark markers as list items (empty by default). Pick from a closed
set: symbol bullets `->`, `→`, `❯` (repeat, like dashes); lettered markers
`a)`, `A)`, `a.`, `A.`, `a:`, `A:` (count up a, b, … z, za; upper-case kept
separate; the delimiter is preserved); and digit markers `1)`, `1:` (count
like numbers). Enter continues them, Tab/Shift+Tab nest them.

- On Tab, the deeper level's marker comes from
  `markdownWorkbench.lists.markerCycle` by depth (default `1.` → `a)` → `1)`
  → `a.`, cycling), unless a sibling already sits at that level - then its
  sequence continues. Typing a different marker overrides it from there on.
- Changing the marker type of the **first** item of a level pulls its
  same-level siblings to the new type and sequence (`a) b) c)` with the first
  set to `1)` → `1) 2) 3)`); child and parent levels are never touched.
- These markers are a deliberate deviation from CommonMark, meant for working
  notes. The **source stays portable**: with
  `markdownWorkbench.lists.renderExtraMarkers` on (and only then), the preview
  renders these lines as lists with the same outline styling as native lists;
  everywhere else (GitHub/GitLab/Forgejo), and with the setting off, they
  remain plain text. Nesting renders cleanly when every level uses a
  non-CommonMark marker; levels written with native markers (`1.`, `1)`) stay
  separate native lists.

### Code fences
- Typing the language after ``` (or ~~~) pops IntelliSense with the bundled
  shiki languages and common aliases (ps1, bash, sh, yml, js, ts, batch)
- Enter at the end of an unclosed opening fence inserts the closing fence
  and puts the cursor on the empty line in between (delimiter and
  indentation preserved; already-closed fences get a normal newline)

### Authoring shortcuts (Alt+D chords, Alt+M menu)
Modeled on the Learn Markdown bindings:

| Key | Action |
|---|---|
| Alt+D B / I / C | Toggle bold / italic / inline code (wraps selection or word under cursor, unwraps when already wrapped) |
| Alt+D K | Insert web link `[text](url)` as snippet with tabstops |
| Alt+D L | Insert relative link to a workspace file (quick pick) |
| Alt+M | Authoring menu with all commands below |
| Alt+P | Toggle Workbench to the Side (close when open; also closes a focused panel) |

Menu/palette only: Bulleted / Numbered / Task list (prefixes the selected
lines or inserts a marker), Insert Table (size prompt, snippet with
tabstops), Evenly Distribute Table / Consolidate Table (reflows the table at
the cursor or in the selection, keeps `:---:` alignment markers), Sort
Selection Ascending/Descending (numeric-aware), Insert Language Identifier
(quick pick over the bundled shiki languages).

Note: other extensions that also bind Enter/Tab or Alt+D for markdown
(e.g. Learn Markdown, Markdown All in One) conflict with this — keep only
one such handler enabled.

## Commands

| Command | Title | Binding |
|---|---|---|
| `markdownWorkbench.showPreview` | Open Workbench | tab context, explorer context, Alt-variant of tab-row button |
| `markdownWorkbench.showPreviewToSide` | Open Workbench to the Side | tab-row icon |
| `markdownWorkbench.open` | Open as Workbench | tab-row icon, tab context |
| `markdownWorkbench.formatBold` / `formatItalic` / `formatCode` | Bold / Italic / Code | Alt+D B / I / C |
| `markdownWorkbench.insertWebLink` / `insertFileLink` | Link to Web / File | Alt+D K / L |
| `markdownWorkbench.authoringMenu` | Markdown Authoring Menu | Alt+M |
| `markdownWorkbench.insert*List`, `insertTable`, `distributeTable`, `consolidateTable`, `sort*`, `insertLanguageIdentifier` | see authoring menu | palette / Alt+M |
| `markdownWorkbench.onEnterKey` / `onTabKey` / `onShiftTabKey` | (internal) | Enter / Tab / Shift+Tab in markdown editors |
| `markdownWorkbench.smartDeleteWordRight` | Smart Delete Word Right | Ctrl+Delete (only when `editing.smartForwardDelete` is on) |

Untitled files: the `*.md` selector does not match untitled documents, so use
the command palette ("Open as Workbench" / "Open Workbench...") while the
untitled tab is active.

## Install (local)

Publishing to the VS Code Marketplace is planned as the future install path
(link follows after the first publish). Until then, install the vsix from
the Releases page:

Download the latest `.vsix` from the
[Releases page](https://github.com/ww3d/markdown-workbench/releases) (every
green build on `main` publishes one), then:

```sh
code --install-extension markdown-workbench-<version>.vsix
```

Each release ships the vsix as a direct download plus `SHA256SUMS.txt`, and
the vsix carries a build-provenance attestation. To verify it came from this
repo's CI before installing:

```sh
gh attestation verify markdown-workbench-<version>.vsix --repo ww3d/markdown-workbench
```

## Build from source

```powershell
npm install
npx @vscode/vsce package
```

No build step; plain JavaScript. Dependencies: markdown-it,
markdown-it-front-matter, shiki.

## Development

```powershell
npm ci
./build.ps1            # version check + coverage gate + package
```

See `CONTRIBUTING.md` for the workflow, `docs/ARCHITECTURE.md` for how the
pieces fit together and `docs/DECISIONS.md` for the decision log including
rejected approaches.
