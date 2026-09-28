// Markdown rendering pipeline for the workbench view: markdown-it (the same
// engine as the built-in VS Code preview) with the task-list, table-checkbox
// and line-number plugins, a frontmatter property-card renderer, and Shiki
// syntax highlighting (same grammars/themes as the built-in preview).

const MarkdownIt = require('markdown-it');
const { extraMarkerListsPlugin } = require('./extra-markers');
const { taskListPlugin } = require('./task-lists');
const { CELL_BOX_RE, tableCheckboxPlugin } = require('./table-checkboxes');
const { headingAnchorsPlugin } = require('./heading-anchors');
const { registerFrontmatterRenderer } = require('./frontmatter');
const {
  activePosts,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  registerFenceRenderer,
} = require('./fence-highlight');

// Attach the source start line to every block token that has a map.
// Used for toggling (tasks) and bidirectional scroll sync.
function injectLineNumbers(md) {
  md.core.ruler.push('inject_lines', (state) => {
    for (const token of state.tokens) {
      if (token.map && token.nesting >= 0) {
        token.attrSet('data-line', String(token.map[0]));
      }
    }
    return true;
  });
}

const md = new MarkdownIt({ html: true, linkify: true })
  .use(require('markdown-it-front-matter'), () => {
    /* rendered via rule below */
  })
  .use(extraMarkerListsPlugin)
  .use(taskListPlugin)
  .use(tableCheckboxPlugin)
  .use(headingAnchorsPlugin)
  .use(injectLineNumbers);
// linkify-it 6 (markdown-it 15) turned fuzzy links off by default; the preview
// keeps linking bare `www.example.com` as before.
md.linkify.set({ fuzzyLink: true });

// Wrap every table in a breakout wrapper so tables wider than the reading
// column can grow symmetrically into both margins (webview.css .table-wrap).
// The wrapper itself carries no data-line - scroll sync and the cell toggles
// keep reading the table's and rows' own attributes.
md.renderer.rules.table_open = (tokens, idx, options, _env, self) =>
  `<div class="table-wrap">${self.renderToken(tokens, idx, options)}`;
md.renderer.rules.table_close = (tokens, idx, options, _env, self) =>
  `${self.renderToken(tokens, idx, options)}</div>\n`;

registerFrontmatterRenderer(md);
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
