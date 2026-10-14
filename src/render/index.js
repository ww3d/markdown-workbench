// Markdown rendering pipeline for the workbench view: the shared markdown-it
// instance (./parser.js - the same engine as the built-in VS Code preview, with
// the task-list, table-checkbox, line-number and frontmatter plugins) plus
// Shiki syntax highlighting (same grammars/themes as the built-in preview).

const { md, injectLineNumbers } = require('./parser');
const { taskListPlugin } = require('./task-lists');
const { CELL_BOX_RE, tableCheckboxPlugin } = require('./table-checkboxes');
const {
  activePosts,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  registerFenceRenderer,
} = require('./fence-highlight');

registerFenceRenderer(md);

module.exports = {
  md,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  activePosts,
  // Exported for tests only.
  _internal: {
    md,
    CELL_BOX_RE,
    shikiTheme,
    taskListPlugin,
    tableCheckboxPlugin,
    injectLineNumbers,
  },
};
