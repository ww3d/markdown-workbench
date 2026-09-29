// Markdown rendering pipeline for the workbench view: the shared markdown-it
// instance (./parser.js - the same engine as the built-in VS Code preview, with
// the task-list, table-checkbox, line-number and frontmatter plugins) plus
// Shiki syntax highlighting (same grammars/themes as the built-in preview).

import { md, injectLineNumbers } from './parser.js';
import { taskListPlugin } from './task-lists.js';
import { CELL_BOX_RE, tableCheckboxPlugin } from './table-checkboxes.js';
import {
  activePosts,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  registerFenceRenderer,
} from './fence-highlight.js';

registerFenceRenderer(md);

export { md, SHIKI_LANGS, initHighlighter, shikiTheme, activePosts };
// Exported for tests only.
export const _internal = {
  md,
  CELL_BOX_RE,
  shikiTheme,
  taskListPlugin,
  tableCheckboxPlugin,
  injectLineNumbers,
};
