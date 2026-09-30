// A mock document as the read-only line source the editing helpers take.

import type { TextLines } from '../../src/editing/list-structure.ts';
import type { MockDocument } from './vscode-mock.ts';

/**
 * `doc` as a {@link TextLines}. The mock returns `undefined` text past the last
 * line; `vscode.TextDocument` throws there, and so does this view.
 */
export function textLines(doc: MockDocument): TextLines {
  return {
    lineCount: doc.lineCount,
    lineAt(line) {
      const text = doc.lineAt(line).text;
      if (text === undefined) throw new RangeError(`no line ${line}`);
      return { text };
    },
  };
}
