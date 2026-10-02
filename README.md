# Markdown Workbench

VS Code extension for working with markdown checklists. Renders markdown
(markdown-it, the same engine as the built-in preview) with clickable
checkboxes; every toggle is mirrored surgically into the source file.

## Features

### Workbench view

- Preview text is selectable and copyable (prose, code, tables); copying
  yields the rendered text, not the markdown source
- Click directly on a checkbox to toggle it; a click elsewhere in the task row
  (the label) toggles only when no text is selected and it is a single click,
  so selecting or double-clicking the label text never toggles
- Ctrl+Click / Shift+Click **on a checkbox** selects multiple tasks; clicking a
  checkbox inside the selection toggles all selected tasks in parallel, as a
  single WorkspaceEdit (one undo step). The batch gestures live on the checkbox
  so Shift in the label stays normal text selection
- Ctrl+F opens VS Code's find widget over the rendered text (highlight,
  next/previous, match count) when the preview or workbench editor is focused
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
  checkbox, clicking anywhere in the cell toggles it - gated like the task row,
  so selecting the cell text does not toggle.
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
- **Instant after a restart**: when VS Code restarts, a workbench panel shows its
  last content at its last scroll position at once, before the document is rendered
  again - and when nothing changed meanwhile, it is not rendered again at all. A
  very large document (more than 512 KiB of rendered HTML) or an update of the
  extension brings the view back without this instant content; it then renders as
  usual.

Menu placement mirrors the built-in preview: two icon buttons at the end of
the tab row (the split-workbench glyph opens to the side, Alt held switches it
to the workbench glyph that opens in the active group), tab context menu
entries in group `1_open`, and an explorer context entry.

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
- Headings get GitHub-compatible slug ids; clicking an in-document link
  (`[Text](#slug)`, e.g. a generated table of contents) scrolls to its target
  heading in the view. Cross-file and external links are unaffected
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

### Table of contents

A navigable table of contents built from the document's headings, tracking your
scroll position (scroll-spy): the current heading is highlighted, its section is
expanded (others collapse), the active entry is kept in view, and a click jumps
smoothly to the heading.

- **Rail** - a sticky panel on the side **opposite the minimap** (so the two
  never collide; there is no separate side setting). Its width is reserved so
  the content is never overlapped.
- **Floating button** - when the view is too narrow to hold the rail beside the
  content, a button on the TOC side opens the same TOC in an overlay instead
  (close by clicking outside or pressing Escape).
- The switch between the two is **content-relative** (the rail appears once the
  viewport can hold the content column plus the rail and the opposite-side
  gutter) and updates live as you resize.

Configurable via `markdownWorkbench.toc.*`:

- `enabled` (default `true`): show the table of contents.
- `mode` (`auto` default / `rail` / `fab`): `auto` picks rail or floating button
  by the available width; `rail` and `fab` force one mode.

### Breadcrumb and sticky scroll

Two orientation bars at the top of the view, tracking your scroll position with
the same scroll-spy as the table of contents (both are on by default and toggle
independently):

- **Breadcrumb** - a single-line trail of the heading you are under
  (H1 > H2 > H3). Each segment scrolls to its heading and opens a picker of the
  sibling headings at that level (like the VS Code editor breadcrumb; selection
  navigates, Escape or a click outside closes it).
- **Sticky scroll** - directly below the breadcrumb, the parent headings of your
  position stay pinned as a stack while you scroll (like the editor's sticky
  scroll). A click on a pinned heading scrolls to it.

Above the first heading the breadcrumb is empty and the stack is hidden. The bars
stay clear of the minimap and the TOC rail, and anchor jumps land below them.

Configurable:

- `markdownWorkbench.breadcrumb.enabled` (default `true`): show the breadcrumb
  bar.
- `markdownWorkbench.stickyScroll.enabled` (default `true`): show the
  sticky-scroll stack.

### Preview readability settings

Three settings tune how selectable text and the task toggle coexist (all apply
live; the defaults reproduce the 0.30.0 behavior):

- `markdownWorkbench.preview.textSelection` (default `true`): preview text is
  selectable and copyable. Set `false` to lock selection (as before 0.30.0) - a
  click anywhere in a task row then toggles it, ungated.
- `markdownWorkbench.preview.taskBatchSelect` (`checkbox` default / `row`):
  where the Shift/Ctrl multi-select fires. `checkbox` keeps it on the checkbox
  so Shift in the label stays a normal text selection; `row` fires it anywhere
  in the row (the price: Shift in the label no longer extends a selection).
- `markdownWorkbench.preview.taskRowTextCursor` (default `false`, only when
  `textSelection` is on): show a text caret over a task row label so it reads
  as selectable; the checkbox keeps the pointer hand.

To restore the pre-0.30.0 behavior (no selectable text, the whole row toggles
and carries the batch gesture), set `textSelection: false` and
`taskBatchSelect: row`.

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
- `  - [ ]` + Shift+Enter -> indented by 9, `1. - [ ] ` likewise
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

On a markerless line (not a list item - a wrapped or hung continuation line,
or plain text), Tab/Shift+Tab instead snap the line's indentation onto a column
stop: column 0, the indent/content columns of nearby list items, every word
start of nearby lines, and the editor's tab-size multiples. Tab moves to the
next stop to the right, Shift+Tab to the next to the left (so a continuation
line can be aligned under a word above it, not just by a fixed step); with no
detected stop nearby it steps by the tab size, so a forward step is always
available. `markdownWorkbench.indent.continuationStopRadius` (default 5) sets
how many lines above and below are scanned for stops. List-item lines are
unaffected by this - they keep the structural nesting/renumbering above.

When more than one line is selected, the whole selection - list items and
markerless lines together - moves as a block by one common delta, so the
relative indentation is preserved and nothing drifts apart: the topmost selected
line snaps to its next stop and every line shifts by that amount. A Shift+Tab
left shift is capped by the flattest line in the selection, so nothing slides
below column 0. Markers are not renumbered in a multi-line selection - it is
pure indentation (a single list item still nests and renumbers structurally, as
above). A single markerless line snaps to its own stop.

### Auto-renumber on manual edits

When you change a numbered marker by hand (e.g. type `2.` over to `5.`), the
following siblings of the same level continue from it - `1. a / 5. b / 6. c`.
The sequence follows your input; it is never reset to `1`, so a list may start
at any number. Only editing the marker triggers it - editing a line's text
leaves an intentionally non-sequential list alone. This runs behind the same
guard as Enter/Tab/Shift+Tab, so those structural edits do their own
renumbering without the manual pass firing on top. (For custom markers, changing
the first item of a level propagates the type to its siblings, as above.)

### Ordered list outline in the view

Ordered lists render with classic outline markers by depth: `1.` on level 1,
`a.` on level 2, `i.` on level 3, repeating from level 4. Only `ol` levels
count, and each level renumbers for itself. The markers are pure preview
styling - the source always keeps portable CommonMark digit markers
(`1.` / `1)`), never letters.

### Join content lines on Ctrl+Delete / Ctrl+Backspace (opt-in)

Two mirror-image joins, each off by default and bound only when its setting is on:

- **Ctrl+Delete** (`markdownWorkbench.editing.forwardJoin.enabled`): at the end
  of a line's visible content, merge it with the **next** line that has content.
- **Ctrl+Backspace** (`markdownWorkbench.editing.backwardJoin.enabled`): at the
  start of a line's visible content, append it to the **previous** line that has
  content.

They also work with the cursor on an empty (or whitespace-only) line - it counts
as being at both the line's end and start, so Ctrl+Delete pulls the next content
line up to the cursor and Ctrl+Backspace moves the cursor to the end of the
previous content line.

Both delete any blank or whitespace-only lines in between (the next content line
is pulled in even across empty lines, and it need not be indented), and they
normalize the seam: existing trailing/leading whitespace and the removed line
breaks become exactly `markdownWorkbench.editing.joinSpaces` spaces (default 1;
set 0 to join with no space) - never a double space. The join spaces are added
only when both sides have visible content; joining onto or from an empty line
adds no space (the texts meet directly). In any other position - or
when there is no content line to join - each runs its fallback command
(`forwardJoin.fallbackCommand`, default `deleteWordRight`;
`backwardJoin.fallbackCommand`, default `deleteWordLeft`), executed directly so
it is safe even when bound to the same key.

Note: a personal `ctrl+delete` / `ctrl+backspace` keybinding with no `when`
clause overrides the workbench binding. To keep both, scope your own binding
with `when: editorLangId != markdown` - otherwise the workbench handler never
fires in markdown editors.

### Custom list markers (opt-in)

Turn on `markdownWorkbench.lists.extraMarkersEnabled` and list the markers in
`markdownWorkbench.lists.extraMarkers` (both required; off by default) to let
the editor treat extra, non-CommonMark markers as list items. Pick from a closed
set: symbol bullets `->`, `→`, `❯` (repeat, like dashes); lettered markers
`a)`, `A)`, `a.`, `A.`, `a:`, `A:` (count up a, b, … z, za; upper-case kept
separate; the delimiter is preserved); and digit markers `1)`, `1:` (count
like numbers, `:` included). Enter continues them, and Tab/Shift+Tab nest and
renumber them with the same machinery as native numbered lists.

- On Tab, the deeper level's marker comes from
  `markdownWorkbench.lists.markerCycle` by depth (default `1.` → `a)` → `1)`
  → `a.`, cycling), unless a sibling already sits at that level - then its
  sequence continues. A symbol item keeps its bullet (symbols just repeat).
  Typing a different marker overrides it from there on.
- Tab/Shift+Tab renumber lettered and digit sequences just like numbers: the
  level left behind closes its gap (`a) b) c) d)`, Tab on `c)` leaves
  `a) b) c)`), and Shift+Tab joins the target level's sequence, adopting its
  family (a `1)` moved up under an `a)` list becomes `b)`). Only the marker
  token is rewritten, so a multi-space gap after it is preserved.
- Changing the marker type of the **first** item of a level pulls its
  same-level siblings to the new type and sequence (`a) b) c)` with the first
  set to `1)` → `1) 2) 3)`); child and parent levels are never touched.
- Because these markers are not CommonMark, an enabled letter/digit family can
  also match ordinary prose at the start of a line (e.g. `ok) go` or `is: this`
  with `a)` / `a:` on). Recognition - and thus Enter continuation and
  Tab/Shift+Tab - then applies on those lines too. This is inherent to opting
  in; the two-character letter bound keeps it to short tokens (`note:` / `foo)`
  with three or more letters are not matched), but 1-2 letter collisions remain.
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

### Tables

Editing a GFM table in the editor, on a table model that sees exactly the
table the preview renders: rows split like GFM (`\|` stays content, a `|`
inside a code span splits), tables without border pipes, inside list items and
in blockquotes (the `>` / indent prefix is kept byte for byte). Column widths
count display columns per grapheme, so CJK and emoji line up.

- **Enter** in a row adds an empty row below with the cursor in its first cell;
  before the first cell a row above; in the header or delimiter row a row
  under the delimiter. On a typed header (`| Name | Age`) Enter adds the
  delimiter row and an empty row. Enter in the last, empty row ends the table.
  The table is aligned in the same undo step; only changed characters are
  replaced. Several cursors, a selection, code blocks and the frontmatter keep
  the normal Enter.
- **Shift+Enter** inside a cell inserts `<br>` (`tables.cellLineBreak`).
- **Tab / Shift+Tab** move to the next / previous cell and select its content,
  over the delimiter row and across rows; Tab in the last cell adds a row;
  Shift+Tab never outdents a table row. Short rows are filled. `|` + Tab on a
  new line closes the cell and opens the next one.
- **Up / Down** stay in the same column (with `editor.wordWrap` off), at the
  same visual position or the end of a shorter cell.
- **New rows continue checkbox columns** with `[ ]`.
- **Sort** the table by the column at the cursor (Alt+M, ascending or
  descending; numbers by value, empty cells last) - or click the sort button
  that appears on a header cell in the preview: the source is sorted, one
  undo step.
- **Columns**: insert left/right, delete, move left/right (Alt+M).
- **Paste** tab- or comma-separated data (Excel, CSV) and pick "Insert as
  Markdown table" in the paste menu; `|` in the data is escaped.
- **Warnings** for cells beyond the header width (GFM drops them silently),
  with the quick fix "Add column to header"; a code action right-aligns a
  number column (`--:`).
- The automatic alignment switches to the compact form when a line would
  exceed `tables.maxAlignedWidth` (100); Evenly Distribute / Consolidate
  always do what they say.

Settings (`markdownWorkbench.tables.*`, all on by default): `enabled`,
`enterBehavior` (`newRow` / `nextRowSameColumn`), `tabSelectsCell`,
`tabAddsRow`, `arrowNavigation`, `autoAlign`, `maxAlignedWidth`,
`ambiguousWidth` (`narrow` / `wide`), `cellLineBreak`, `createFromPipe`,
`continueCheckboxes`, `suggestNumericAlign`, `previewSort`, `pasteAsTable`,
`validate`.

### Authoring shortcuts (Alt+D chords, Alt+M menu)

Modeled on the Learn Markdown bindings:

| Key             | Action                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------- |
| Alt+D B / I / C | Toggle bold / italic / inline code (wraps selection or word under cursor, unwraps when already wrapped) |
| Alt+D K         | Insert web link `[text](url)` as snippet with tabstops                                                  |
| Alt+D L         | Insert relative link to a workspace file (quick pick)                                                   |
| Alt+M           | Authoring menu with all commands below                                                                  |
| Alt+P           | Toggle Workbench to the Side (close when open; also closes a focused panel)                             |

Menu/palette only: Bulleted / Numbered / Task list (prefixes the selected
lines or inserts a marker), Insert Table (size prompt, snippet with
tabstops), Evenly Distribute Table / Consolidate Table (reflows every table the
selection touches, or the table at the cursor; keeps `:---:` alignment markers), the table sort and column
commands (see Tables), Sort
Selection Ascending/Descending (numeric-aware), Insert Language Identifier
(quick pick over the bundled shiki languages).

Note: other extensions that also bind Enter/Tab or Alt+D for markdown
(e.g. Learn Markdown, Markdown All in One) conflict with this — keep only
one such handler enabled.

### Clipboard diff (baseline -> candidate)

Compare the clipboard - typically an AI answer - with your file in VS Code's own
diff editor, edit the proposal there and apply it. VS Code's built-in "Compare
Active File with Clipboard" puts the clipboard left and cannot swap; here the
**baseline** (your text) is on the left and the **candidate** (the clipboard) on the
right, and the candidate is editable.

- **Compare with Clipboard** picks the baseline: a selection (several selections
  are combined into one range from the first to the last), otherwise the section
  the clipboard replaces (**section anchor**, below), otherwise the whole file.
  The tab reads `notes.md ↔ notes (Candidate).md` (or `notes (Selection).md`), and
  stays right after a swap. The candidate keeps the file's language and line
  endings.
- **Swap Diff Sides** swaps the active text diff - this one or any other - with VS
  Code's own swap, keeping the tab's position and pin; bind it freely in
  `keybindings.json`. Its tab-bar button shows only where VS Code shows none of its
  own - in a Git diff as opened, whose left side is read-only - so there is always
  one. After a swap one tab of the two sides is left: a Git change reopened from
  Source Control opens in its first order beside the swapped tab, and the next swap
  closes the extra one. A diff VS Code cannot swap gets a message instead of silence.
- **Apply Candidate** (check icon in the tab bar) writes the candidate into the
  baseline range as one undo step. The range follows your edits of the file; if the
  range itself changed since the diff opened, it asks before replacing.
- **Per hunk, with the built-in arrows.** VS Code's arrow ("Revert Block") always
  copies a hunk from left to right:
  - baseline left, candidate right (as opened): the arrow **drops** that candidate
    hunk - it takes the file's text back into the candidate. Drop what you do not
    want, then Apply Candidate writes the rest.
  - after a swap, candidate left, file right: the arrow **takes** that candidate hunk
    straight into the file (with a selection baseline, into the selected range).
- **Section anchor.** Without a selection, a clipboard that starts with a heading
  is compared with the same-named section of the file (up to the next heading of
  the same or a higher level); any other snippet is located by its first and last
  line. The diff opens with the matched lines selected and a note names them; an
  unsure or ambiguous match asks, with "Whole file" as a choice.
- **Earlier clipboards.** **Compare with Earlier Clipboard** lists the clipboard
  texts compared in this session (time and first line, newest first; at most 10,
  none larger than 1 MB) and compares the picked one against the same baseline
  logic. Kept in memory only, never saved; the clipboard is never polled.
- **Style switch.** The paint-bucket / palette button in the tab bar switches the
  candidate between the raw clipboard and a version in the file's own Markdown
  style - its dominant list bullet, emphasis markers (`*`/`_`, `**`/`__`) and table
  padding. Only markers change at their place; code, HTML and front matter are
  never touched. The button shows the current state; after your own edits it asks
  before replacing them.
- **Unwrapping an AI answer.** An outer code fence around the whole answer and
  chat lines at its edges ("Sure, here is the updated section:", "Let me know if
  ...") are stripped when the diff opens.
- **Placeholder guard.** Lines like `… rest unchanged …`, `<!-- unchanged -->` or
  `// ... existing code ...` are marked in the candidate; Apply fills in the file
  text they stand for instead of deleting it, and asks when it cannot tell where
  that text is. An ellipsis inside a sentence is left alone.
- **Markdown check before Apply.** The candidate is checked against the baseline
  for checked tasks it unchecks (one-click fix "Keep checkbox states from the
  baseline"), footnote and link-reference definitions it drops, front matter it
  removes or changes, and renamed or removed headings that a `#anchor` link still
  points at in the same file (as you edit) - and, with
  `markdownWorkbench.clipboardDiff.checkWorkspaceAnchors` on, links from the rest
  of the workspace when you apply. These are hints on the candidate and one
  question at Apply, never a block.
- **Your save actions stay out of the way.** The candidate is kept in memory by
  saving every change at once. While you type in it or in the selection page,
  that save skips "trim trailing whitespace", "insert final newline" and
  "format on save". A page changed without focus (for example by a diff arrow while the other side is
  focused) is saved normally, so those actions may tidy that page - but they
  never reach your file.

**The clipboard text never reaches the disk.** The candidate lives in memory only.
The promise, as decided (DECISIONS.md #48):

> Die Extension schreibt den Clipboard-Inhalt nie auf die Platte. Damit VS Code
> keine Sicherung anlegt, speichert sie jede Aenderung sofort in den Speicher;
> gemessen durch den Waechter-Test (`tests/integration/guard/scenario.ts`).
> Ausnahmen: 'Speichern unter' auf ein lokales Ziel ist eine ausdrueckliche
> Nutzerhandlung. Scheitert das Speichern, kann VS Code eine Sicherung anlegen.

In English: the extension never writes the clipboard text to disk. So that VS Code
makes no backup of it, every change is saved to memory at once - measured by the
guard test `tests/integration/guard/scenario.ts` in a real VS Code (a normal window
with the packaged extension, minimum and current version), which fails on any backup
file, on a page left unsaved long enough to be backed up, and on any file write or
log line with the clipboard text. Exceptions: "Save
As" to a local target is an explicit action of yours; if saving to memory ever
fails, VS Code may create a backup (you get a warning).

## Commands

| Command                                                                                                                    | Title                           | Binding                                                         |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | --------------------------------------------------------------- |
| `markdownWorkbench.showPreview`                                                                                            | Open Workbench                  | tab context, explorer context, Alt-variant of tab-row button    |
| `markdownWorkbench.showPreviewToSide`                                                                                      | Open Workbench to the Side      | tab-row icon                                                    |
| `markdownWorkbench.open`                                                                                                   | Open as Workbench               | tab-row icon, tab context                                       |
| `markdownWorkbench.formatBold` / `formatItalic` / `formatCode`                                                             | Bold / Italic / Code            | Alt+D B / I / C                                                 |
| `markdownWorkbench.insertWebLink` / `insertFileLink`                                                                       | Link to Web / File              | Alt+D K / L                                                     |
| `markdownWorkbench.authoringMenu`                                                                                          | Markdown Authoring Menu         | Alt+M                                                           |
| `markdownWorkbench.insert*List`, `insertTable`, `distributeTable`, `consolidateTable`, `sort*`, `insertLanguageIdentifier` | see authoring menu              | palette / Alt+M                                                 |
| `markdownWorkbench.sortTableAscending` / `sortTableDescending`                                                             | Sort Table by Column            | palette / Alt+M                                                 |
| `markdownWorkbench.insertColumnLeft` / `insertColumnRight` / `deleteColumn` / `moveColumnLeft` / `moveColumnRight`         | Table column commands           | palette / Alt+M                                                 |
| `markdownWorkbench.onEnterKey` / `onTabKey` / `onShiftTabKey`                                                              | (internal)                      | Enter / Tab / Shift+Tab in markdown editors                     |
| `markdownWorkbench.onUpKey` / `onDownKey`                                                                                  | (internal)                      | Up / Down inside a table (`markdownWorkbench.inTable`)          |
| `markdownWorkbench.joinForwardOrFallback`                                                                                  | Join Next Content Line          | Ctrl+Delete (only when `editing.forwardJoin.enabled` is on)     |
| `markdownWorkbench.joinBackwardOrFallback`                                                                                 | Join With Previous Content Line | Ctrl+Backspace (only when `editing.backwardJoin.enabled` is on) |
| `markdownWorkbench.compareWithClipboard`                                                                                   | Compare with Clipboard          | palette; bind in `keybindings.json`                             |
| `markdownWorkbench.compareWithEarlierClipboard`                                                                            | Compare with Earlier Clipboard  | palette                                                         |
| `markdownWorkbench.swapDiffSides`                                                                                          | Swap Diff Sides                 | tab-row icon where VS Code has none; bind in `keybindings.json` |
| `markdownWorkbench.applyCandidate`                                                                                         | Apply Candidate                 | tab-row icon in a clipboard diff                                |
| `markdownWorkbench.alignCandidateStyle` / `showRawCandidate`                                                               | Align Candidate / Show Raw      | tab-row icon in a clipboard diff (shows the current state)      |

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
.\Build.cmd                                  # Windows; build.sh on Linux / macOS
eng\common\build.ps1 -Task Package           # the .vsix; eng/common/build.sh --task Package
```

The scripts fetch the pinned Node and pnpm into `.tools/`; nothing needs to be installed
beforehand.

TypeScript, bundled by tsdown into `dist/` (the extension host and the webview).
Runtime dependencies, bundled: markdown-it, markdown-it-front-matter, shiki,
get-east-asian-width; the webview bundles morphdom.

## Development

```powershell
eng\common\build.ps1   # version check + coverage gate + package (eng/common/build.sh on Linux / macOS)
```

See `CONTRIBUTING.md` for the workflow, `docs/ARCHITECTURE.md` for how the
pieces fit together and `docs/DECISIONS.md` for the decision log including
rejected approaches.
