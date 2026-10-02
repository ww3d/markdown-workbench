// List structure: the content column of an item, the item enclosing a given
// line (including continuation lines), sibling lookup/renumbering and the
// marker-type propagation those siblings follow.
import * as vscode from 'vscode';
import {
  COMPOUND_TASK_RE,
  execListItem,
  markerFamily,
  sameFamily,
  advanceMarker,
} from './list-markers.ts';
import type { ListItemMatch } from './list-markers.ts';

/**
 * The read side of a document the list helpers need: its line count and each
 * line's text. A `vscode.TextDocument` satisfies it.
 */
export interface TextLines {
  readonly lineCount: number;
  lineAt(line: number): { readonly text: string };
}

/**
 * The write side of an edit block the resequencing helpers need. A
 * `vscode.TextEditorEdit` satisfies it.
 */
export interface ReplaceBuilder {
  replace(range: vscode.Range, text: string): void;
}

/** A list item found for a line: where it is, how it matched, its content column. */
export interface EnclosingItem {
  readonly line: number;
  readonly m: ListItemMatch;
  readonly contentCol: number;
}

/**
 * Width of the leading whitespace of a line (spaces or tabs counted as one
 * each), i.e. the indentation column of its first non-blank character.
 */
function leadingWhitespace(text: string): number {
  return /^[ \t]*/.exec(text)?.[0].length ?? 0;
}

/**
 * Content column ("Inhaltsspalte") of a list item: the column where its text
 * begins - indent + bullet + gap + checkbox (+ compound prefix). This is the
 * same prefix width onEnterKey computes to place the next marker, reused here
 * so continuation lines can be recognized by their indentation.
 */
function contentColumn(m: ListItemMatch): number {
  const checkbox = m[4] || '';
  const comp = checkbox ? null : COMPOUND_TASK_RE.exec(m[5]);
  const compLen = comp
    ? (comp[1]?.length ?? 0) + 3 + (comp[3]?.length ?? 0)
    : 0;
  return m[1].length + m[2].length + m[3].length + checkbox.length + compLen;
}

/**
 * The list item a given line belongs to, with its content column. The line is
 * its own item when it matches LIST_ITEM_RE; otherwise the owning item is found
 * by walking up from the start line's own indentation: the first item whose
 * content column is at or shallower than that indentation owns it. Deeper items
 * in between (children of the owner, e.g. a `3.1`/`3.2` sublist hanging under a
 * continuation line of `3.`) are stepped over instead of ending the search -
 * otherwise a continuation line below such children loses its owner. A blank
 * line, or a markerless line shallower than the start indentation (a foreign
 * line), ends the search with null. A whitespace-indented blank start line is a
 * hanging continuation and is resolved by its indentation; a flush-left or
 * empty start line has nothing to hang from (no item has content column 0).
 */
function enclosingListItem(
  document: TextLines,
  line: number,
): EnclosingItem | null {
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

/**
 * Re-sequence the run of same-family siblings at exactly `indentLen`, starting
 * from `startBullet` and advancing per item (numbers and letters count up, the
 * delimiter preserved). A symbol/dash startBullet is not countable and nothing
 * happens; a different family or delimiter ends the run. Deeper-indented items are skipped (children of a sibling);
 * a shallower item, a blank line or a foreign markerless line ends the run.
 * With `contentCol` given, a non-blank line indented to at least that column is
 * a continuation and is stepped over instead of ending the run. Only the marker
 * token is rewritten - the following gap and text keep their alignment.
 */
function resequenceSiblingsBelow(
  document: TextLines,
  builder: ReplaceBuilder,
  startLine: number,
  indentLen: number,
  startBullet: string,
  contentCol?: number,
): void {
  if (markerFamily(startBullet) === null) return;
  let cur = startBullet;
  for (let l = startLine; l < document.lineCount; l++) {
    const text = document.lineAt(l).text;
    const m = execListItem(text);
    if (!m) {
      if (
        contentCol !== undefined &&
        text.trim() !== '' &&
        leadingWhitespace(text) >= contentCol
      )
        continue;
      break;
    }
    if (m[1].length > indentLen) continue;
    if (m[1].length < indentLen) break;
    if (!sameFamily(m[2], cur)) break;
    if (m[2] !== cur) {
      builder.replace(
        new vscode.Range(l, indentLen, l, indentLen + m[2].length),
        cur,
      );
    }
    cur = advanceMarker(cur);
  }
}

/**
 * The bullet of the nearest sibling above `line` at exactly `indentLen`, or
 * null when the sequence starts there. Returns the marker token (any family),
 * used to continue a sequence when
 * indenting an item into a populated deeper level.
 */
function previousSiblingBullet(
  document: TextLines,
  line: number,
  indentLen: number,
): string | null {
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

/**
 * Number of distinct ancestor indentation levels above `line` shallower than
 * `newIndent` (within the current block). The depth index into markerCycle for
 * an item moved to `newIndent`.
 */
function nestingDepth(
  document: TextLines,
  line: number,
  newIndent: number,
): number {
  const levels = new Set();
  for (let l = line - 1; l >= 0; l--) {
    const text = document.lineAt(l).text;
    if (text.trim() === '') break;
    const m = execListItem(text);
    if (m && m[1].length < newIndent) levels.add(m[1].length);
  }
  return levels.size;
}

/**
 * The ordered per-depth marker scheme. markerCycle[depth % length] gives the
 * first marker of the level a freshly indented item lands on.
 */
function markerCycle(): string[] {
  const value = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get<unknown>('lists.markerCycle', ['1.', 'a)', '1)', 'a.']);
  const cycle = Array.isArray(value)
    ? value.filter((tok): tok is string => typeof tok === 'string')
    : [];
  return cycle.length ? cycle : ['1.'];
}

/**
 * True when `line` is the first item of its level - no preceding sibling at the
 * same indentation.
 */
function isFirstOfLevel(
  document: TextLines,
  line: number,
  indentLen: number,
): boolean {
  return previousSiblingBullet(document, line, indentLen) === null;
}

/**
 * Type propagation (local, per docs/DECISIONS.md): when the first item of a
 * level changes marker type, its same-level siblings follow in type and
 * sequence (`a) b) c)` with the first set to `1)` -> `1) 2) 3)`). Reads the
 * first item's current marker and advances it per following sibling. Deeper
 * children are skipped and never rewritten; a shallower or blank line ends the
 * run. Mechanics mirror resequenceSiblingsBelow but carry the whole marker, not
 * just the number.
 */
function propagateMarkerType(
  document: TextLines,
  builder: ReplaceBuilder,
  line: number,
): void {
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
    if (sm[1].length < indentLen) break; // back to a shallower level
    cur = advanceMarker(cur);
    if (sm[2] !== cur) {
      builder.replace(
        new vscode.Range(l, indentLen, l, indentLen + sm[2].length),
        cur,
      );
    }
  }
}

export {
  leadingWhitespace,
  contentColumn,
  enclosingListItem,
  resequenceSiblingsBelow,
  previousSiblingBullet,
  nestingDepth,
  markerCycle,
  isFirstOfLevel,
  propagateMarkerType,
};
