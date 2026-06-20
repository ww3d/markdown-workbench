// Markdown editing helpers for the text editor (not the workbench view):
// Enter list continuation, Tab/Shift+Tab nesting, formatting shortcuts,
// link/table insertion, table reflow, selection sorting. Modeled on the
// generic authoring features of Learn Markdown / Markdown All in One.

const vscode = require('vscode');
const path = require('path');

// Matches any list item: "- text", "* text", "3. text", optional "[ ] " checkbox.
const LIST_ITEM_RE = /^(\s*)([-*+]|\d+[.)])(\s+)(\[(?: |x|X)\]\s+)?(.*)$/;

// --- Enter: continue list ------------------------------------------------------

// Matches a code fence delimiter line: ``` or ~~~ (3+), optional language info.
const FENCE_RE = /^(\s*)(`{3,}|~{3,})\s*([\w-]*)\s*$/;

// Matches the content of a compound task item, i.e. a second list marker
// plus box ("- [ ] foo" as the content of "1. - [ ] foo"). Group 1 =
// marker + gap, group 3 = gap after the box (empty at line end), group 4 =
// label. Mirrors the compound branch of CHECKBOX_RE in views.js.
const COMPOUND_TASK_RE = /^((?:[-*+]|\d+[.)])\s+)\[( |x|X)\](\s+|$)(.*)$/;

// CommonMark ordered markers are digits + "." or ")" - nothing else. The
// letter look of outline levels comes from the preview stylesheet, never
// from the source (docs/DECISIONS.md #24).
function numericMarker(bullet) {
  const m = /^(\d+)([.)])$/.exec(bullet);
  return m ? { n: parseInt(m[1], 10), delim: m[2] } : null;
}

// --- Custom (non-CommonMark) list markers, opt-in via lists.extraMarkers ------
//
// LIST_ITEM_RE (native markers) is never touched. Instead a matcher is built
// from the configured markers and cached, rebuilt when the setting changes.
// Each configured token enables a family: a symbol bullet that repeats
// ("->", "→", "❯"), a letter sequence that counts (a) b) ... z) za); upper-case
// kept separate), or a digit sequence with a delimiter (1: ; 1) is already
// CommonMark). Letter sequences are bounded to two characters to limit false
// positives on ordinary prose. These markers are a deliberate non-CommonMark
// deviation for working notes (docs/DECISIONS.md).
function regexEscape(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const SYMBOL_MARKERS = ['->', '→', '❯'];

function buildCustomMatcher(markers) {
  if (!markers || !markers.length) return null;
  const symbols = [], lowerDelims = new Set(), upperDelims = new Set(), digitDelims = new Set();
  for (const tok of markers) {
    if (SYMBOL_MARKERS.includes(tok)) symbols.push(tok);
    else if (/^[a-z][).:]$/.test(tok)) lowerDelims.add(tok[1]);
    else if (/^[A-Z][).:]$/.test(tok)) upperDelims.add(tok[1]);
    else if (/^1[).:]$/.test(tok)) digitDelims.add(tok[1]);
  }
  const alts = [];
  if (symbols.length) alts.push(symbols.map(regexEscape).join('|'));
  const cls = (set) => '[' + [...set].join('') + ']';
  if (lowerDelims.size) alts.push('[a-z]{1,2}' + cls(lowerDelims));
  if (upperDelims.size) alts.push('[A-Z]{1,2}' + cls(upperDelims));
  if (digitDelims.size) alts.push('\\d+' + cls(digitDelims));
  if (!alts.length) return null;
  return new RegExp('^(\\s*)((?:' + alts.join('|') + '))(\\s+)(.*)$');
}

let _matcherCache = { key: null, matcher: null };
function configuredExtraMarkers() {
  return vscode.workspace.getConfiguration('markdownWorkbench').get('lists.extraMarkers', []);
}
function extraMarkersEnabled() {
  return configuredExtraMarkers().length > 0;
}
function customMatcher() {
  const markers = configuredExtraMarkers();
  const key = markers.join('\x00');
  if (_matcherCache.key !== key) _matcherCache = { key, matcher: buildCustomMatcher(markers) };
  return _matcherCache.matcher;
}

// Match a line as a list item, native first then (when enabled) custom markers.
// Returns a LIST_ITEM_RE-shaped array: [full, indent, bullet, gap, checkbox,
// rest]. Custom markers carry no checkbox (group 4 is undefined).
function execListItem(text) {
  const native = LIST_ITEM_RE.exec(text);
  if (native) return native;
  const matcher = customMatcher();
  if (matcher) {
    const m = matcher.exec(text);
    if (m) return [m[0], m[1], m[2], m[3], undefined, m[4]];
  }
  return null;
}

function isCustomBullet(bullet) {
  return !numericMarker(bullet) && !/^[-*+]$/.test(bullet);
}

// The next letter sequence: a->b ... y->z, then z->za, za->zb ... (a deliberate
// prepend-z overflow, not base-26 carry), upper-case kept separate.
function nextLetterSeq(seq) {
  const upper = seq === seq.toUpperCase();
  const a = upper ? 'A' : 'a', z = upper ? 'Z' : 'z';
  const chars = seq.split('');
  const last = chars.length - 1;
  if (chars[last] !== z) {
    chars[last] = String.fromCharCode(chars[last].charCodeAt(0) + 1);
    return chars.join('');
  }
  chars[last] = a;
  return z + chars.join('');
}

// The next marker in a marker's own sequence: numeric and letter markers count
// up (delimiter preserved), symbol bullets repeat unchanged.
function advanceMarker(bullet) {
  const num = numericMarker(bullet);
  if (num) return String(num.n + 1) + num.delim;
  const letter = /^([a-z]+|[A-Z]+)([).:])$/.exec(bullet);
  if (letter) return nextLetterSeq(letter[1]) + letter[2];
  return bullet; // symbols and dashes repeat
}

// Width of the leading whitespace of a line (spaces or tabs counted as one
// each), i.e. the indentation column of its first non-blank character.
function leadingWhitespace(text) {
  return /^[ \t]*/.exec(text)[0].length;
}

// Content column ("Inhaltsspalte") of a list item: the column where its text
// begins - indent + bullet + gap + checkbox (+ compound prefix). This is the
// same prefix width onEnterKey computes to place the next marker, reused here
// so continuation lines can be recognized by their indentation.
function contentColumn(m) {
  const checkbox = m[4] || '';
  const comp = checkbox ? null : COMPOUND_TASK_RE.exec(m[5]);
  const compLen = comp ? comp[1].length + 3 + comp[3].length : 0;
  return m[1].length + m[2].length + m[3].length + checkbox.length + compLen;
}

// The list item a given line belongs to, with its content column. The line is
// its own item when it matches LIST_ITEM_RE; otherwise the owning item is found
// by walking up from the start line's own indentation: the first item whose
// content column is at or shallower than that indentation owns it. Deeper items
// in between (children of the owner, e.g. a `3.1`/`3.2` sublist hanging under a
// continuation line of `3.`) are stepped over instead of ending the search -
// otherwise a continuation line below such children loses its owner. A blank
// line, or a markerless line shallower than the start indentation (a foreign
// line), ends the search with null. A whitespace-indented blank start line is a
// hanging continuation and is resolved by its indentation; a flush-left or
// empty start line has nothing to hang from (no item has content column 0).
function enclosingListItem(document, line) {
  const here = execListItem(document.lineAt(line).text);
  if (here) return { line, m: here, contentCol: contentColumn(here) };

  const startIndent = leadingWhitespace(document.lineAt(line).text);
  for (let l = line - 1; l >= 0; l--) {
    const text = document.lineAt(l).text;
    if (text.trim() === '') return null;
    const m = execListItem(text);
    if (m) {
      const contentCol = contentColumn(m);
      if (contentCol <= startIndent) return { line: l, m, contentCol };
      continue; // a deeper item is a child between the line and its owner
    }
    if (leadingWhitespace(text) < startIndent) return null; // foreign line
  }
  return null;
}

// Renumber the contiguous run of numbered siblings at exactly `indentLen`,
// walking down from startLine: matching items get sequential numbers from
// `from`. Deeper-indented list items are skipped (children of a sibling);
// a shallower item, a different delimiter or a dash item ends the run -
// per-level list types are never rewritten. A markerless line ends the run
// too, unless it is a continuation of the run: with `contentCol` given (the
// trigger item's content column), a non-blank line indented to at least that
// column is skipped, not treated as a boundary. `contentCol` is a stable
// lower bound for the whole run - numbers only grow downward, so every later
// sibling's text hangs at least that deep, and a continuation that hung under
// the narrower marker before a one-/two-digit transition still counts.
function renumberSiblingsBelow(document, builder, startLine, indentLen, delim, from, contentCol) {
  let next = from;
  for (let l = startLine; l < document.lineCount; l++) {
    const text = document.lineAt(l).text;
    const m = execListItem(text);
    if (!m) {
      if (contentCol !== undefined && text.trim() !== ''
          && leadingWhitespace(text) >= contentCol) continue;
      break;
    }
    if (m[1].length > indentLen) continue;
    if (m[1].length < indentLen) break;
    const num = numericMarker(m[2]);
    if (!num || num.delim !== delim) break;
    if (num.n !== next) {
      builder.replace(new vscode.Range(l, indentLen, l, indentLen + String(num.n).length), String(next));
    }
    next++;
  }
}

// Number of the nearest numbered sibling above `line` at exactly `indentLen`
// (skipping deeper-indented children); 0 when the sequence starts there or
// the preceding sibling is not a numbered item with the same delimiter.
// Markerless continuation lines between the siblings are stepped over: only a
// markerless line shallower than the sibling's content column (a foreign line)
// or a blank line ends the search.
function previousSiblingNumber(document, line, indentLen, delim) {
  let minMarkerless = Infinity;
  for (let l = line - 1; l >= 0; l--) {
    const text = document.lineAt(l).text;
    const m = execListItem(text);
    if (!m) {
      if (text.trim() === '') break;
      minMarkerless = Math.min(minMarkerless, leadingWhitespace(text));
      continue;
    }
    if (m[1].length > indentLen) continue;
    if (m[1].length < indentLen) break;
    if (minMarkerless < contentColumn(m)) break;
    const num = numericMarker(m[2]);
    return (num && num.delim === delim) ? num.n : 0;
  }
  return 0;
}

// The bullet of the nearest sibling above `line` at exactly `indentLen`, or
// null when the sequence starts there. Like previousSiblingNumber but returns
// the marker token (any family), used to continue a custom-marker sequence when
// indenting an item into a populated deeper level.
function previousSiblingBullet(document, line, indentLen) {
  let minMarkerless = Infinity;
  for (let l = line - 1; l >= 0; l--) {
    const text = document.lineAt(l).text;
    const m = execListItem(text);
    if (!m) {
      if (text.trim() === '') break;
      minMarkerless = Math.min(minMarkerless, leadingWhitespace(text));
      continue;
    }
    if (m[1].length > indentLen) continue;
    if (m[1].length < indentLen) break;
    if (minMarkerless < contentColumn(m)) break;
    return m[2];
  }
  return null;
}

// Number of distinct ancestor indentation levels above `line` shallower than
// `newIndent` (within the current block). The depth index into markerCycle for
// an item moved to `newIndent`.
function nestingDepth(document, line, newIndent) {
  const levels = new Set();
  for (let l = line - 1; l >= 0; l--) {
    const text = document.lineAt(l).text;
    if (text.trim() === '') break;
    const m = execListItem(text);
    if (m && m[1].length < newIndent) levels.add(m[1].length);
  }
  return levels.size;
}

// The ordered per-depth marker scheme. markerCycle[depth % length] gives the
// first marker of the level a freshly indented item lands on.
function markerCycle() {
  const cycle = vscode.workspace.getConfiguration('markdownWorkbench').get('lists.markerCycle', ['1.', 'a)', '1)', 'a.']);
  return cycle.length ? cycle : ['1.'];
}

// True when `line` is the first item of its level - no preceding sibling at the
// same indentation.
function isFirstOfLevel(document, line, indentLen) {
  return previousSiblingBullet(document, line, indentLen) === null;
}

// Type propagation (local, per docs/DECISIONS.md): when the first item of a
// level changes marker type, its same-level siblings follow in type and
// sequence (`a) b) c)` with the first set to `1)` -> `1) 2) 3)`). Reads the
// first item's current marker and advances it per following sibling. Deeper
// children are skipped and never rewritten; a shallower or blank line ends the
// run. Mechanics mirror renumberSiblingsBelow but carry the whole marker, not
// just the number.
function propagateMarkerType(document, builder, line) {
  const m = execListItem(document.lineAt(line).text);
  if (!m) return;
  const indentLen = m[1].length;
  let cur = m[2];
  for (let l = line + 1; l < document.lineCount; l++) {
    const text = document.lineAt(l).text;
    const sm = execListItem(text);
    if (!sm) {
      if (text.trim() === '' || leadingWhitespace(text) < indentLen) break;
      continue; // continuation line of a sibling
    }
    if (sm[1].length > indentLen) continue; // child level, never rewritten
    if (sm[1].length < indentLen) break;    // back to a shallower level
    cur = advanceMarker(cur);
    if (sm[2] !== cur) {
      builder.replace(new vscode.Range(l, indentLen, l, indentLen + sm[2].length), cur);
    }
  }
}

// True if the fence-delimiter line at lineNo opens a block that is never
// closed: an even number of delimiter lines below means all later fences
// pair among themselves, leaving this one open.
function fenceIsUnclosed(document, lineNo) {
  let later = 0;
  for (let l = lineNo + 1; l < document.lineCount; l++) {
    if (FENCE_RE.test(document.lineAt(l).text)) later++;
  }
  return later % 2 === 0;
}

async function onEnterKey() {
  const fallback = () => vscode.commands.executeCommand('default:type', { text: '\n' });
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selections.length !== 1 || !editor.selection.isEmpty) return fallback();

  const pos = editor.selection.active;
  const lineText = editor.document.lineAt(pos.line).text;

  // Opening code fence + Enter at line end -> insert the closing fence and
  // place the cursor on the empty line in between. The snippet contains no
  // indentation: VS Code auto-indents snippet continuation lines to the
  // current line's indentation, so including fence[1] would double it.
  const fence = FENCE_RE.exec(lineText);
  if (fence && pos.character === lineText.length && fenceIsUnclosed(editor.document, pos.line)) {
    await editor.insertSnippet(new vscode.SnippetString('\n$0\n' + fence[2]), pos);
    return;
  }

  const m = execListItem(lineText);
  if (!m) {
    // Not a list line itself, but a continuation line of one (a wrapped or
    // Shift+Enter-hung line): Enter still continues the enclosing item with a
    // fresh sibling at its level, renumbering what follows.
    const encl = enclosingListItem(editor.document, pos.line);
    if (!encl) return fallback();
    return continueSibling(editor, pos, encl.m, encl.contentCol);
  }

  const indent = m[1], checkbox = m[4] || '';
  // Compound task item: the content is itself a one-line task list
  // ("1. - [ ] foo"). Only the leading marker follows its continuation
  // rule below; the rest of the compound prefix continues verbatim with a
  // fresh box (an inner number is content of the new line, never
  // incremented).
  const comp = checkbox ? null : COMPOUND_TASK_RE.exec(m[5]);
  const prefixLen = contentColumn(m);
  if (pos.character < prefixLen) return fallback(); // cursor inside indentation/marker

  if (m[5] === '' || (comp && comp[4] === '')) {
    // Empty item + Enter -> terminate the list by removing the marker.
    await editor.edit((b) => b.delete(new vscode.Range(pos.line, indent.length, pos.line, prefixLen)));
    return;
  }

  return continueSibling(editor, pos, m, prefixLen);
}

// Insert a fresh sibling below pos for the list item described by `m`, whose
// text hangs at `contentCol`. Numbered markers advance and the following
// siblings renumber; bullets and the compound prefix repeat with a fresh box.
// Text right of the cursor moves onto the new line, after the marker.
async function continueSibling(editor, pos, m, contentCol) {
  const indent = m[1], gap = m[3], checkbox = m[4] || '';
  const comp = checkbox ? null : COMPOUND_TASK_RE.exec(m[5]);
  const num = numericMarker(m[2]);
  // Numeric and letter markers count up, symbol/dash markers repeat.
  const nextBullet = advanceMarker(m[2]);

  await editor.edit((b) => {
    b.insert(pos, '\n' + indent + nextBullet + gap + (comp ? comp[1] + '[ ] ' : checkbox ? '[ ] ' : ''));
    // Mid-sequence Enter: following siblings continue after the new item.
    if (num) renumberSiblingsBelow(editor.document, b, pos.line + 1, indent.length, num.delim, num.n + 2, contentCol);
  });
}

// Shift+Enter: hanging continuation of a list item. Inside an item or one of
// its continuation lines, split at the cursor and indent the new line with
// whitespace to the item's content column - no marker, no number. Text right
// of the cursor moves down with it. Outside any list, the editor default.
async function onShiftEnterKey() {
  const fallback = () => vscode.commands.executeCommand('default:type', { text: '\n' });
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selections.length !== 1 || !editor.selection.isEmpty) return fallback();

  const pos = editor.selection.active;
  const item = enclosingListItem(editor.document, pos.line);
  if (!item) return fallback();
  // Cursor still inside the marker/indentation (before the content column):
  // there is nothing to hang yet, so defer to the default newline - same
  // guard onEnterKey applies with prefixLen.
  if (pos.character < item.contentCol) return fallback();

  await editor.edit((b) => b.insert(pos, '\n' + ' '.repeat(item.contentCol)));
}

// --- Tab / Shift+Tab: nest and un-nest list items -------------------------------

// Lines covered by the current selection (or just the cursor line).
function coveredLines(editor) {
  const lines = [];
  for (const sel of editor.selections) {
    for (let l = sel.start.line; l <= sel.end.line; l++) {
      if (!lines.includes(l)) lines.push(l);
    }
  }
  return lines;
}

// Adaptive indent unit per CommonMark: child content aligns under the parent
// content, i.e. indent by marker + gap width ("- " -> 2, "10. " -> 4).
function indentUnitFor(match) {
  return ' '.repeat(match[2].length + match[3].length);
}

// --- Column stops for markerless continuation lines -----------------------------
//
// Tab/Shift+Tab on a line that is NOT a list item (execListItem null) does not
// shift by a fixed amount; it snaps the line's indentation onto a column stop.
// List-item lines are untouched by this path - their structural nesting and
// renumbering stay exactly as before.

function continuationStopRadius() {
  const n = vscode.workspace.getConfiguration('markdownWorkbench').get('indent.continuationStopRadius', 5);
  return Number.isFinite(n) && n >= 0 ? n : 5;
}

// Visual column width of a leading-whitespace string, tabs expanding to the
// next multiple of tabSize.
function indentColumns(ws, tabSize) {
  let col = 0;
  for (const ch of ws) col = ch === '\t' ? (Math.floor(col / tabSize) + 1) * tabSize : col + 1;
  return col;
}

// Columns at which a word begins on a line (each whitespace -> non-whitespace
// transition), tab-expanded, in the same column space as the indentation.
function wordStartColumns(text, tabSize) {
  const cols = [];
  let col = 0, prevWs = true;
  for (const ch of text) {
    const ws = ch === ' ' || ch === '\t';
    if (!ws && prevWs) cols.push(col);
    prevWs = ws;
    col = ch === '\t' ? (Math.floor(col / tabSize) + 1) * tabSize : col + 1;
  }
  return cols;
}

// The sorted column stops for a markerless line: column 0, the indent and
// content columns of nearby list items, every word start of nearby lines (all
// within `radius` lines above and below), plus the multiples of tabSize so a
// forward step is always available.
function collectColumnStops(document, line, tabSize, radius, currentCol) {
  const stops = new Set([0]);
  let maxDetected = 0;
  const lo = Math.max(0, line - radius), hi = Math.min(document.lineCount - 1, line + radius);
  for (let l = lo; l <= hi; l++) {
    if (l === line) continue;
    const text = document.lineAt(l).text;
    const m = execListItem(text);
    if (m) {
      const indent = indentColumns(m[1], tabSize);
      const content = indent + (contentColumn(m) - m[1].length);
      stops.add(indent); stops.add(content);
      maxDetected = Math.max(maxDetected, content);
    }
    for (const c of wordStartColumns(text, tabSize)) {
      stops.add(c); maxDetected = Math.max(maxDetected, c);
    }
  }
  const bound = Math.max(maxDetected, currentCol) + tabSize;
  for (let c = tabSize; c <= bound; c += tabSize) stops.add(c);
  return [...stops].sort((a, b) => a - b);
}

// Render `col` columns of indentation per the editor's insertSpaces/tabSize.
function makeIndent(col, tabSize, insertSpaces) {
  if (insertSpaces) return ' '.repeat(col);
  return '\t'.repeat(Math.floor(col / tabSize)) + ' '.repeat(col % tabSize);
}

// Re-indent a markerless line onto the next column stop in direction `dir`
// (+1 Tab, -1 Shift+Tab). Only the leading whitespace is replaced.
function applyColumnStop(document, b, line, dir, tabSize, insertSpaces, radius) {
  const text = document.lineAt(line).text;
  const wsLen = leadingWhitespace(text);
  const cur = indentColumns(text.slice(0, wsLen), tabSize);
  const stops = collectColumnStops(document, line, tabSize, radius, cur);
  let target;
  if (dir > 0) target = stops.find((s) => s > cur);
  else { const lower = stops.filter((s) => s < cur); target = lower.length ? lower[lower.length - 1] : 0; }
  if (target === undefined || target === cur) return;
  b.replace(new vscode.Range(line, 0, line, wsLen), makeIndent(target, tabSize, insertSpaces));
}

// Split covered lines into list items (structural nesting) and markerless lines
// (column-stop indentation). Returns { items, markerless }.
function splitTabTargets(editor) {
  const items = [], markerless = [];
  for (const l of coveredLines(editor)) {
    const m = execListItem(editor.document.lineAt(l).text);
    (m ? items : markerless).push({ line: l, m });
  }
  return { items, markerless };
}

function editorTabWidth(editor) {
  return Number(editor.options && editor.options.tabSize) || 4;
}
function editorInsertSpaces(editor) {
  return !(editor.options && editor.options.insertSpaces === false);
}

async function onTabKey() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('tab');
  if (!editor) return fallback();

  const { items, markerless } = splitTabTargets(editor);
  if (!items.length && !markerless.length) return fallback();

  const tabSize = editorTabWidth(editor), insertSpaces = editorInsertSpaces(editor);
  const radius = continuationStopRadius();
  const custom = extraMarkersEnabled();
  await editor.edit((b) => {
    for (const t of markerless) {
      applyColumnStop(editor.document, b, t.line, +1, tabSize, insertSpaces, radius);
    }
    for (const t of items) {
      const unit = indentUnitFor(t.m);
      const doc = editor.document;
      const num = numericMarker(t.m[2]);
      const single = items.length === 1;
      // Multi-line selections only reindent: rewriting every covered marker
      // would mangle a moved sequence.
      if (single && custom && (num || isCustomBullet(t.m[2]))) {
        // Custom markers active: the deeper level's marker comes from the
        // markerCycle by depth, unless a preceding sibling already sits there -
        // then its sequence continues. The number sequence left behind on the
        // old level still closes its gap.
        const newIndent = t.m[1].length + unit.length;
        const prev = previousSiblingBullet(doc, t.line, newIndent);
        const newBullet = prev ? advanceMarker(prev)
          : markerCycle()[nestingDepth(doc, t.line, newIndent) % markerCycle().length];
        b.replace(new vscode.Range(t.line, 0, t.line, t.m[1].length + t.m[2].length),
          unit + t.m[1] + newBullet);
        if (num) {
          renumberSiblingsBelow(doc, b, t.line + 1, t.m[1].length, num.delim,
            previousSiblingNumber(doc, t.line, t.m[1].length, num.delim) + 1);
        }
      } else if (single && num) {
        // A numbered item moves one level deeper, same delimiter (one replace:
        // indent and marker change together). It joins the sequence already
        // present at the deeper level - number = next after the preceding
        // sibling there, restarting at 1 only when none exists - so tabbing a
        // second item into a populated sublist no longer duplicates markers
        // (`1.`/`1.`). The sequence it leaves closes its gap, symmetric to
        // onShiftTabKey.
        const newIndent = t.m[1].length + unit.length;
        const newNum = previousSiblingNumber(doc, t.line, newIndent, num.delim) + 1;
        b.replace(new vscode.Range(t.line, 0, t.line, t.m[1].length + t.m[2].length),
          unit + t.m[1] + String(newNum) + num.delim);
        renumberSiblingsBelow(doc, b, t.line + 1, t.m[1].length, num.delim,
          previousSiblingNumber(doc, t.line, t.m[1].length, num.delim) + 1);
      } else {
        b.insert(new vscode.Position(t.line, 0), unit);
      }
    }
  });
}

async function onShiftTabKey() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('outdent');
  if (!editor) return fallback();

  const { items, markerless } = splitTabTargets(editor);
  const targets = items.filter((t) => t.m[1].length > 0);
  if (!targets.length && !markerless.length) return fallback();

  const tabSize = editorTabWidth(editor), insertSpaces = editorInsertSpaces(editor);
  const radius = continuationStopRadius();
  await editor.edit((b) => {
    for (const t of markerless) {
      applyColumnStop(editor.document, b, t.line, -1, tabSize, insertSpaces, radius);
    }
    for (const t of targets) {
      const indent = t.m[1];
      const remove = indent.startsWith('\t') ? 1 : Math.min(indent.length, indentUnitFor(t.m).length);
      b.delete(new vscode.Range(t.line, 0, t.line, remove));
      // A single numbered item joins the target-level sequence: number =
      // next after the preceding sibling there (or 1). The sequence it
      // leaves closes its gap, the target sequence continues after it.
      // Multi-line selections only reindent, as in onTabKey.
      const num = targets.length === 1 && numericMarker(t.m[2]);
      if (num) {
        const doc = editor.document;
        const newIndent = indent.length - remove;
        const newNum = previousSiblingNumber(doc, t.line, newIndent, num.delim) + 1;
        if (newNum !== num.n) {
          b.replace(new vscode.Range(t.line, indent.length, t.line, indent.length + String(num.n).length), String(newNum));
        }
        renumberSiblingsBelow(doc, b, t.line + 1, indent.length, num.delim,
          previousSiblingNumber(doc, t.line, indent.length, num.delim) + 1);
        renumberSiblingsBelow(doc, b, t.line + 1, newIndent, num.delim, newNum + 1);
      }
    }
  });
}

// --- Ctrl+Delete: smart forward delete across continuation lines ----------------

// Ctrl+Delete with editing.smartForwardDelete on: when the cursor sits at the
// end of a line's visible content (only whitespace to its right) and the next
// line is an indented continuation, pull that line up - remove the line break
// and the next line's leading indentation so its text follows with exactly one
// space. In every other situation it is the plain deleteWordRight, so the key
// keeps its normal behavior everywhere else.
async function smartDeleteWordRight() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('deleteWordRight');
  if (!editor || editor.selections.length !== 1 || !editor.selection.isEmpty) return fallback();
  if (!vscode.workspace.getConfiguration('markdownWorkbench').get('editing.smartForwardDelete', false)) {
    return fallback();
  }

  const pos = editor.selection.active;
  const doc = editor.document;
  const lineText = doc.lineAt(pos.line).text;
  // Cursor must be at the end of the visible content, on a non-empty line, with
  // an indented non-empty line following.
  if (/\S/.test(lineText.slice(pos.character)) || lineText.trim() === '') return fallback();
  if (pos.line + 1 >= doc.lineCount) return fallback();
  const nextText = doc.lineAt(pos.line + 1).text;
  const nextIndent = leadingWhitespace(nextText);
  if (nextIndent === 0 || nextText.trim() === '') return fallback();

  const visibleEnd = lineText.replace(/[ \t]+$/, '').length;
  await editor.edit((b) =>
    b.replace(new vscode.Range(pos.line, visibleEnd, pos.line + 1, nextIndent), ' '));
}

// --- Formatting: bold, italic, code ---------------------------------------------

function escapeSnippet(s) {
  return s.replace(/[\\$}]/g, '\\$&');
}

async function toggleWrap(marker) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;

  // Empty single cursor on no word: drop markers and put the cursor inside.
  if (editor.selections.length === 1 && editor.selection.isEmpty
      && !doc.getWordRangeAtPosition(editor.selection.active)) {
    await editor.insertSnippet(new vscode.SnippetString(escapeSnippet(marker) + '$0' + escapeSnippet(marker)));
    return;
  }

  await editor.edit((b) => {
    for (const sel of editor.selections) {
      let range = sel;
      if (sel.isEmpty) {
        const word = doc.getWordRangeAtPosition(sel.active);
        if (!word) continue;
        range = word;
      }
      const text = doc.getText(range);
      if (text.length >= marker.length * 2 && text.startsWith(marker) && text.endsWith(marker)) {
        b.replace(range, text.slice(marker.length, text.length - marker.length));
        continue;
      }
      // Selection sits inside existing markers -> unwrap them.
      const ext = new vscode.Range(
        range.start.translate(0, -Math.min(marker.length, range.start.character)),
        range.end.translate(0, marker.length)
      );
      const extText = doc.getText(ext);
      if (extText === marker + text + marker) {
        b.replace(ext, text);
        continue;
      }
      b.replace(range, marker + text + marker);
    }
  });
}

// --- Links -----------------------------------------------------------------------

async function insertWebLink() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const text = editor.document.getText(editor.selection);
  const snippet = '[${1:' + escapeSnippet(text || 'text') + '}](${2:https://})';
  await editor.insertSnippet(new vscode.SnippetString(snippet), editor.selection);
}

async function insertFileLink() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const files = await vscode.workspace.findFiles('**/*', '{**/node_modules/**,**/.git/**}', 2000);
  if (!files.length) {
    vscode.window.showInformationMessage('No workspace files found.');
    return;
  }
  const items = files
    .map((uri) => ({ label: vscode.workspace.asRelativePath(uri), uri }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Link to file in workspace' });
  if (!pick) return;

  let target;
  if (editor.document.uri.scheme === 'file') {
    target = path.relative(path.dirname(editor.document.uri.fsPath), pick.uri.fsPath).split(path.sep).join('/');
  } else {
    target = pick.label.split(path.sep).join('/');
  }
  const selText = editor.document.getText(editor.selection);
  const label = selText || path.basename(pick.uri.fsPath);
  await editor.edit((b) => b.replace(editor.selection, '[' + label + '](' + target + ')'));
}

// --- Lists (insert / convert selection) -------------------------------------------

async function insertList(kind) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const prefix = (i) => kind === 'numbered' ? (i + 1) + '. ' : kind === 'task' ? '- [ ] ' : '- ';

  if (editor.selection.isEmpty) {
    await editor.edit((b) => b.insert(editor.selection.active, prefix(0)));
    return;
  }
  const lines = coveredLines(editor);
  await editor.edit((b) => {
    let i = 0;
    for (const l of lines) {
      if (editor.document.lineAt(l).text.trim() === '') continue;
      b.insert(new vscode.Position(l, 0), prefix(i++));
    }
  });
}

// --- Tables ------------------------------------------------------------------------

async function insertTable() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const input = await vscode.window.showInputBox({
    prompt: 'Table size: columns x rows (data rows)',
    value: '3x2',
    validateInput: (v) => /^\s*\d+\s*[xX*]\s*\d+\s*$/.test(v) ? null : 'Format: 3x2'
  });
  if (!input) return;
  const [, c, r] = /^\s*(\d+)\s*[xX*]\s*(\d+)\s*$/.exec(input);
  const cols = Math.min(20, parseInt(c, 10)), rows = Math.min(50, parseInt(r, 10));

  let tab = 1, out = '';
  const row = (cell) => '| ' + Array.from({ length: cols }, cell).join(' | ') + ' |\n';
  out += row(() => '${' + (tab++) + ':Header}');
  out += row(() => '---');
  for (let i = 0; i < rows; i++) out += row(() => '$' + (tab++));
  await editor.insertSnippet(new vscode.SnippetString(out));
}

// Pure helpers (exported for tests): reflow a block of table lines.
function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

function isSeparatorRow(cells) {
  return cells.length > 0 && cells.every((c) => /^:?-+:?$/.test(c));
}

function reflowTable(lines, mode) {
  const rows = lines.map(splitRow);
  const colCount = Math.max(...rows.map((r) => r.length));
  for (const r of rows) while (r.length < colCount) r.push('');

  const widths = Array.from({ length: colCount }, (_, i) =>
    Math.max(3, ...rows.filter((r) => !isSeparatorRow(r)).map((r) => r[i].length))
  );

  return rows.map((r) => {
    if (isSeparatorRow(r)) {
      return '| ' + r.map((c, i) => {
        const left = c.startsWith(':'), right = c.endsWith(':');
        const w = mode === 'distribute' ? widths[i] : 3;
        let dashes = '-'.repeat(Math.max(1, w - (left ? 1 : 0) - (right ? 1 : 0)));
        return (left ? ':' : '') + dashes + (right ? ':' : '');
      }).join(' | ') + ' |';
    }
    const cells = mode === 'distribute' ? r.map((c, i) => c.padEnd(widths[i])) : r;
    return '| ' + cells.join(' | ') + ' |';
  });
}

function tableRangeAt(editor) {
  const doc = editor.document;
  let start, end;
  if (!editor.selection.isEmpty) {
    start = editor.selection.start.line;
    end = editor.selection.end.line;
  } else {
    start = end = editor.selection.active.line;
    while (start > 0 && /^\s*\|/.test(doc.lineAt(start - 1).text)) start--;
    while (end < doc.lineCount - 1 && /^\s*\|/.test(doc.lineAt(end + 1).text)) end++;
  }
  const lines = [];
  for (let l = start; l <= end; l++) {
    const text = doc.lineAt(l).text;
    if (!/^\s*\|/.test(text)) return null;
    lines.push(text);
  }
  return { start, end, lines };
}

async function reflowTableCommand(mode) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const t = tableRangeAt(editor);
  if (!t) {
    vscode.window.showInformationMessage('Place the cursor inside a markdown table (lines starting with |).');
    return;
  }
  const out = reflowTable(t.lines, mode).join('\n');
  const range = new vscode.Range(t.start, 0, t.end, editor.document.lineAt(t.end).text.length);
  await editor.edit((b) => b.replace(range, out));
}

// --- Sorting -------------------------------------------------------------------------

async function sortSelection(descending) {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selection.isEmpty) {
    vscode.window.showInformationMessage('Select the lines to sort first.');
    return;
  }
  const start = editor.selection.start.line;
  const end = editor.selection.end.line;
  const lines = [];
  for (let l = start; l <= end; l++) lines.push(editor.document.lineAt(l).text);
  lines.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));
  if (descending) lines.reverse();
  const range = new vscode.Range(start, 0, end, editor.document.lineAt(end).text.length);
  await editor.edit((b) => b.replace(range, lines.join('\n')));
}

// --- Language identifier ----------------------------------------------------------------

async function insertLanguageIdentifier(shikiLangs) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const pick = await vscode.window.showQuickPick(shikiLangs.slice().sort(), {
    placeHolder: 'Language identifier for the code fence'
  });
  if (!pick) return;
  await editor.edit((b) => b.replace(editor.selection, pick));
}

// --- Authoring menu (Alt+M) ----------------------------------------------------------------

async function authoringMenu() {
  const items = [
    { label: '$(bold) Bold', cmd: 'markdownWorkbench.formatBold' },
    { label: '$(italic) Italic', cmd: 'markdownWorkbench.formatItalic' },
    { label: '$(symbol-string) Code', cmd: 'markdownWorkbench.formatCode' },
    { label: '$(link) Link to web', cmd: 'markdownWorkbench.insertWebLink' },
    { label: '$(file) Link to file in workspace', cmd: 'markdownWorkbench.insertFileLink' },
    { label: '$(list-unordered) Bulleted list', cmd: 'markdownWorkbench.insertBulletedList' },
    { label: '$(list-ordered) Numbered list', cmd: 'markdownWorkbench.insertNumberedList' },
    { label: '$(checklist) Task list', cmd: 'markdownWorkbench.insertTaskList' },
    { label: '$(table) Insert table', cmd: 'markdownWorkbench.insertTable' },
    { label: '$(arrow-both) Distribute table', cmd: 'markdownWorkbench.distributeTable' },
    { label: '$(fold) Consolidate table', cmd: 'markdownWorkbench.consolidateTable' },
    { label: '$(sort-precedence) Sort selection ascending', cmd: 'markdownWorkbench.sortAscending' },
    { label: '$(sort-precedence) Sort selection descending', cmd: 'markdownWorkbench.sortDescending' },
    { label: '$(code) Insert language identifier', cmd: 'markdownWorkbench.insertLanguageIdentifier' }
  ];
  const pick = await vscode.window.showQuickPick(items, { placeHolder: 'Markdown authoring' });
  if (pick) vscode.commands.executeCommand(pick.cmd);
}

// --- Fence language completion -------------------------------------------------------------

// Suggests language identifiers while typing after ``` (or ~~~).
function registerFenceLanguageCompletion(context, shikiLangs) {
  // Bundled language ids plus the aliases shiki resolves for them.
  const langs = [...new Set([
    ...shikiLangs,
    'bash', 'sh', 'shell', 'zsh', 'ps', 'ps1', 'batch', 'js', 'ts', 'yml'
  ])].sort();

  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider('markdown', {
      provideCompletionItems(document, position) {
        const before = document.lineAt(position.line).text.slice(0, position.character);
        const m = /^(\s*)(`{3,}|~{3,})([\w-]*)$/.exec(before);
        if (!m) return undefined;
        const replaceRange = new vscode.Range(
          position.line, position.character - m[3].length,
          position.line, position.character
        );
        return langs.map((lang) => {
          const item = new vscode.CompletionItem(lang, vscode.CompletionItemKind.Value);
          item.range = replaceRange;
          return item;
        });
      }
    }, '`', '~')
  );
}

// --- Marker type propagation (document change listener) -----------------------------------------

// Re-entrancy guard: the propagation applies its own edit, which fires another
// change event we must ignore.
let propagating = false;

// When custom markers are active and an edit changes the marker of the first
// item of a level, pull its same-level siblings to the new type. Only the first
// item of a level triggers it (changing a later item is the user overriding
// that one); the rewrite touches siblings, never children or parents.
function registerMarkerTypePropagation(context) {
  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument((e) => {
    if (propagating || !extraMarkersEnabled()) return;
    if (!e.contentChanges || !e.contentChanges.length) return;
    const document = e.document;
    const lines = new Set();
    for (const c of e.contentChanges) {
      if (c.range) lines.add(c.range.start.line);
    }
    const edit = new vscode.WorkspaceEdit();
    let queued = 0;
    const builder = { replace: (range, text) => { queued++; edit.replace(document.uri, range, text); } };
    for (const line of lines) {
      if (line >= document.lineCount) continue;
      const m = execListItem(document.lineAt(line).text);
      if (m && isFirstOfLevel(document, line, m[1].length)) {
        propagateMarkerType(document, builder, line);
      }
    }
    if (queued) {
      // Suppress the echoed change event from our own edit.
      propagating = true;
      Promise.resolve(vscode.workspace.applyEdit(edit)).finally(() => { propagating = false; });
    }
  }));
}

// --- Registration ------------------------------------------------------------------------------

function registerEditingCommands(context, shikiLangs) {
  registerFenceLanguageCompletion(context, shikiLangs);
  registerMarkerTypePropagation(context);
  const reg = (id, fn) => context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  reg('markdownWorkbench.onEnterKey', onEnterKey);
  reg('markdownWorkbench.onShiftEnterKey', onShiftEnterKey);
  reg('markdownWorkbench.onTabKey', onTabKey);
  reg('markdownWorkbench.onShiftTabKey', onShiftTabKey);
  reg('markdownWorkbench.smartDeleteWordRight', smartDeleteWordRight);
  reg('markdownWorkbench.formatBold', () => toggleWrap('**'));
  reg('markdownWorkbench.formatItalic', () => toggleWrap('*'));
  reg('markdownWorkbench.formatCode', () => toggleWrap('`'));
  reg('markdownWorkbench.insertWebLink', insertWebLink);
  reg('markdownWorkbench.insertFileLink', insertFileLink);
  reg('markdownWorkbench.insertBulletedList', () => insertList('bulleted'));
  reg('markdownWorkbench.insertNumberedList', () => insertList('numbered'));
  reg('markdownWorkbench.insertTaskList', () => insertList('task'));
  reg('markdownWorkbench.insertTable', insertTable);
  reg('markdownWorkbench.distributeTable', () => reflowTableCommand('distribute'));
  reg('markdownWorkbench.consolidateTable', () => reflowTableCommand('consolidate'));
  reg('markdownWorkbench.sortAscending', () => sortSelection(false));
  reg('markdownWorkbench.sortDescending', () => sortSelection(true));
  reg('markdownWorkbench.insertLanguageIdentifier', () => insertLanguageIdentifier(shikiLangs));
  reg('markdownWorkbench.authoringMenu', authoringMenu);
}

module.exports = {
  registerEditingCommands, reflowTable, splitRow, LIST_ITEM_RE,
  // Exported for tests only.
  _internal: { FENCE_RE, COMPOUND_TASK_RE, fenceIsUnclosed, isSeparatorRow, indentUnitFor, escapeSnippet, numericMarker, contentColumn, enclosingListItem, onEnterKey, onShiftEnterKey, onTabKey, onShiftTabKey, smartDeleteWordRight, sortSelection, toggleWrap, execListItem, advanceMarker, nextLetterSeq, propagateMarkerType }
};
