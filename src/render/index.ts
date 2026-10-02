// Markdown rendering pipeline for the workbench view: the shared markdown-it
// instance (./parser.ts - the same engine as the built-in VS Code preview, with
// the task-list, table-checkbox, line-number and frontmatter plugins) plus
// Shiki syntax highlighting (same grammars/themes as the built-in preview).

import { md, injectLineNumbers } from './parser.ts';
import { taskListPlugin } from './task-lists.ts';
import { CELL_BOX_RE, tableCheckboxPlugin } from './table-checkboxes.ts';
import {
  activePosts,
  highlighterState,
  onHighlighterSettled,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  registerFenceRenderer,
} from './fence-highlight.ts';

registerFenceRenderer(md);

export {
  md,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  activePosts,
  highlighterState,
  onHighlighterSettled,
};
export type { HighlighterState } from './fence-highlight.ts';
/** Exported for tests only: the parts of the pipeline the tests drive directly. */
export const _internal = {
  md,
  CELL_BOX_RE,
  shikiTheme,
  taskListPlugin,
  tableCheckboxPlugin,
  injectLineNumbers,
};
