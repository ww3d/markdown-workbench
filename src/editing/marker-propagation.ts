// --- Marker type propagation (document change listener) -----------------------------------------
import * as vscode from 'vscode';
import {
  extraMarkersEnabled,
  execListItem,
  numericMarker,
  advanceMarker,
} from './list-markers.ts';
import {
  isFirstOfLevel,
  propagateMarkerType,
  resequenceSiblingsBelow,
} from './list-structure.ts';
import type { ReplaceBuilder } from './list-structure.ts';
import { isPropagating, setPropagating } from './edit-guard.ts';

/**
 * Listen for document changes: when custom markers are active and an edit
 * changes the marker of the first item of a level, pull its same-level siblings
 * to the new type. Only the first item of a level triggers it (changing a later
 * item is the user overriding that one); the rewrite touches siblings, never
 * children or parents. A hand-edited native number resequences the siblings
 * below it.
 */
function registerMarkerTypePropagation(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (isPropagating()) return; // our own structural edits must not re-trigger this
      if (!e.contentChanges?.length) return;
      const document = e.document;
      const custom = extraMarkersEnabled();
      // Per changed line, the earliest changed column - to tell a marker edit from
      // a content edit.
      const touched = new Map<number, number>();
      for (const c of e.contentChanges) {
        if (!c.range) continue;
        const l = c.range.start.line;
        const ch = Number(c.range.start.character) || 0;
        touched.set(l, Math.min(touched.get(l) ?? Infinity, ch));
      }
      const edit = new vscode.WorkspaceEdit();
      let queued = 0;
      const builder: ReplaceBuilder = {
        replace: (range, text) => {
          queued++;
          edit.replace(document.uri, range, text);
        },
      };
      for (const [line, minChar] of touched) {
        if (line >= document.lineCount) continue;
        const m = execListItem(document.lineAt(line).text);
        if (!m) continue;
        if (custom && isFirstOfLevel(document, line, m[1].length)) {
          // Custom markers active: changing the first item of a level pulls its
          // same-level siblings to the new type and sequence.
          propagateMarkerType(document, builder, line);
        } else if (
          numericMarker(m[2]) &&
          minChar <= m[1].length + m[2].length
        ) {
          // A native number changed by hand: the following siblings continue from
          // it (Variant A - the sequence follows the input, no reset to 1). Only
          // when the edit actually touched the marker, so editing the text of a
          // line in a list that intentionally starts at e.g. 5 does not reflow it.
          resequenceSiblingsBelow(
            document,
            builder,
            line + 1,
            m[1].length,
            advanceMarker(m[2]),
          );
        }
      }
      if (queued) {
        // Suppress the echoed change event from our own edit.
        setPropagating(true);
        Promise.resolve(vscode.workspace.applyEdit(edit)).finally(() => {
          setPropagating(false);
        });
      }
    }),
  );
}

export { registerMarkerTypePropagation };
