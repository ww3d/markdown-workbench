// Tab / Shift+Tab: nest and un-nest list items, and re-indent markerless lines
// via column stops.
const vscode = require('vscode');
const {
  execListItem,
  numericMarker,
  advanceMarker,
  isCustomBullet,
  markerFamily,
  sameFamily,
  firstOfFamily,
  extraMarkersEnabled,
  SYMBOL_MARKERS,
} = require('./list-markers');
const {
  previousSiblingBullet,
  resequenceSiblingsBelow,
  nestingDepth,
  markerCycle,
} = require('./list-structure');
const { suppressedEdit } = require('./edit-guard');
const { tableTab } = require('../tables');
const {
  applyColumnStop,
  applyColumnStopBlock,
  continuationStopRadius,
} = require('./column-stops');

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

// The marker the first sibling of a run (starting at `line`) should carry to
// continue the sequence above it: the preceding sibling's marker advanced when
// it shares the family, otherwise the family's first marker.
function seedBullet(document, line, indentLen, refBullet) {
  const prev = previousSiblingBullet(document, line, indentLen);
  return prev && sameFamily(prev, refBullet)
    ? advanceMarker(prev)
    : firstOfFamily(refBullet);
}

// Split covered lines into list items (structural nesting) and markerless lines
// (column-stop indentation). Returns { items, markerless }.
function splitTabTargets(editor) {
  const items = [],
    markerless = [];
  for (const l of coveredLines(editor)) {
    const m = execListItem(editor.document.lineAt(l).text);
    (m ? items : markerless).push({ line: l, m });
  }
  return { items, markerless };
}

function editorTabWidth(editor) {
  return Number(editor.options?.tabSize) || 4;
}
function editorInsertSpaces(editor) {
  return !(editor.options && editor.options.insertSpaces === false);
}

async function onTabKey() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('tab');
  if (!editor) return fallback();
  // The table branch runs before the column-stop branch for markerless lines
  // (docs/DECISIONS.md #27): a table row has no list marker (#48).
  if (await tableTab(editor, 1, suppressedEdit)) return;

  const { items, markerless } = splitTabTargets(editor);
  const lines = [...items, ...markerless].map((t) => t.line);
  if (!lines.length) return fallback();

  const tabSize = editorTabWidth(editor),
    insertSpaces = editorInsertSpaces(editor);
  const radius = continuationStopRadius();
  const custom = extraMarkersEnabled();
  await suppressedEdit(editor, (b) => {
    // A multi-line selection (markers and/or markerless lines) moves as one
    // block by a common delta - form-stable, markers never renumbered.
    if (lines.length > 1) {
      applyColumnStopBlock(
        editor.document,
        b,
        lines,
        +1,
        tabSize,
        insertSpaces,
        radius,
      );
      return;
    }
    if (markerless.length) {
      applyColumnStop(
        editor.document,
        b,
        markerless[0].line,
        +1,
        tabSize,
        insertSpaces,
        radius,
      );
      return;
    }
    // Exactly one list item: structural nesting + renumber (unchanged).
    const t = items[0],
      doc = editor.document,
      unit = indentUnitFor(t.m),
      oldBullet = t.m[2];
    const num = numericMarker(oldBullet);
    const countable =
      num ||
      (custom && isCustomBullet(oldBullet) && markerFamily(oldBullet) !== null);
    const symbol = custom && SYMBOL_MARKERS.includes(oldBullet);
    if (countable || symbol) {
      // The item moves one level deeper. A symbol keeps its bullet (symbols
      // repeat, no sequence); otherwise it joins the sequence already present
      // at the deeper level (adopting that level's family), and when that level
      // is empty restarts via the markerCycle by depth (custom) or at the
      // family's first marker (native). The level it leaves closes its gap.
      const newIndent = t.m[1].length + unit.length;
      let newBullet;
      if (symbol) {
        newBullet = oldBullet;
      } else {
        const prev = previousSiblingBullet(doc, t.line, newIndent);
        if (prev && markerFamily(prev)) newBullet = advanceMarker(prev);
        else if (custom)
          newBullet =
            markerCycle()[
              nestingDepth(doc, t.line, newIndent) % markerCycle().length
            ];
        else newBullet = firstOfFamily(oldBullet);
      }
      b.replace(
        new vscode.Range(t.line, 0, t.line, t.m[1].length + t.m[2].length),
        unit + t.m[1] + newBullet,
      );
      resequenceSiblingsBelow(
        doc,
        b,
        t.line + 1,
        t.m[1].length,
        seedBullet(doc, t.line, t.m[1].length, oldBullet),
      );
    } else {
      b.insert(new vscode.Position(t.line, 0), unit);
    }
  });
}

async function onShiftTabKey() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () => vscode.commands.executeCommand('outdent');
  if (!editor) return fallback();
  if (await tableTab(editor, -1, suppressedEdit)) return;

  const { items, markerless } = splitTabTargets(editor);
  const lines = [...items, ...markerless].map((t) => t.line);
  if (!lines.length) return fallback();
  // A single top-level item with nothing else: nothing to outdent -> default.
  if (lines.length === 1 && items.length === 1 && items[0].m[1].length === 0)
    return fallback();

  const tabSize = editorTabWidth(editor),
    insertSpaces = editorInsertSpaces(editor);
  const radius = continuationStopRadius();
  const custom = extraMarkersEnabled();
  await suppressedEdit(editor, (b) => {
    // A multi-line selection moves as one block by a common delta - form-stable,
    // markers never renumbered, left shift capped so nothing crosses column 0.
    if (lines.length > 1) {
      applyColumnStopBlock(
        editor.document,
        b,
        lines,
        -1,
        tabSize,
        insertSpaces,
        radius,
      );
      return;
    }
    if (markerless.length) {
      applyColumnStop(
        editor.document,
        b,
        markerless[0].line,
        -1,
        tabSize,
        insertSpaces,
        radius,
      );
      return;
    }
    // Exactly one list item at indent > 0: structural outdent + renumber.
    const t = items[0],
      doc = editor.document,
      indent = t.m[1],
      oldBullet = t.m[2];
    const remove = indent.startsWith('\t')
      ? 1
      : Math.min(indent.length, indentUnitFor(t.m).length);
    b.delete(new vscode.Range(t.line, 0, t.line, remove));
    const num = numericMarker(oldBullet);
    const countable =
      num ||
      (custom && isCustomBullet(oldBullet) && markerFamily(oldBullet) !== null);
    const symbol = custom && SYMBOL_MARKERS.includes(oldBullet);
    // A countable item joins the target (shallower) level, adopting its family -
    // next after the preceding sibling there, or the family's first marker when
    // empty - so a `1)` moved up under an `a)` list becomes `b)`. The level it
    // leaves closes its gap, the target level continues after it. Symbols only
    // reindent.
    if (countable && !symbol) {
      const newIndent = indent.length - remove;
      const prev = previousSiblingBullet(doc, t.line, newIndent);
      const newBullet =
        prev && markerFamily(prev)
          ? advanceMarker(prev)
          : firstOfFamily(oldBullet);
      if (newBullet !== oldBullet) {
        b.replace(
          new vscode.Range(
            t.line,
            indent.length,
            t.line,
            indent.length + oldBullet.length,
          ),
          newBullet,
        );
      }
      resequenceSiblingsBelow(
        doc,
        b,
        t.line + 1,
        indent.length,
        seedBullet(doc, t.line, indent.length, oldBullet),
      );
      resequenceSiblingsBelow(
        doc,
        b,
        t.line + 1,
        newIndent,
        advanceMarker(newBullet),
      );
    }
  });
}

module.exports = {
  coveredLines,
  indentUnitFor,
  splitTabTargets,
  editorTabWidth,
  editorInsertSpaces,
  onTabKey,
  onShiftTabKey,
};
