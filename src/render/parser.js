// The one markdown-it instance of the extension: the preview renders with it,
// and the table editor reads its block structure (src/tables/blocks.js), so the
// editor sees exactly the tables the preview shows (docs/DECISIONS.md #49, D1).
// No vscode import - the Shiki fence renderer is added in ./index.js.

const MarkdownIt = require('markdown-it');
const { extraMarkerListsPlugin } = require('./extra-markers');
const { taskListPlugin } = require('./task-lists');
const { tableCheckboxPlugin } = require('./table-checkboxes');
const { headingAnchorsPlugin } = require('./heading-anchors');
const { registerFrontmatterRenderer } = require('./frontmatter');

/**
 * Attach the source start line to every block token that has a map. Used for
 * toggling (tasks) and bidirectional scroll sync.
 * @param {MarkdownIt} md
 */
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

/**
 * Record, per source line a `table` or `paragraph` rule consumes, where the
 * line's content starts after its container prefix (quote markers, list
 * indent, a list marker on the item's own line). Active only when the caller
 * passes `env.lineStarts` (an array); rendering is unchanged.
 * @param {MarkdownIt} md
 */
function lineStartsPlugin(md) {
  for (const name of ['table', 'paragraph']) {
    const rule = md.block.ruler.__rules__.find((r) => r.name === name);
    const fn = rule.fn;
    md.block.ruler.at(
      name,
      (state, start, end, silent) => {
        const ok = fn(state, start, end, silent);
        const out = state.env.lineStarts;
        if (ok && !silent && out)
          for (let l = start; l < state.line; l++)
            out[l] = {
              kind: name,
              start,
              at: state.bMarks[l] + state.tShift[l],
            };
        return ok;
      },
      { alt: rule.alt },
    );
  }
}

// The shared instance, wired with every plugin and renderer override below.
const md = new MarkdownIt({ html: true, linkify: true })
  .use(require('markdown-it-front-matter'), () => {
    /* rendered via rule below */
  })
  .use(extraMarkerListsPlugin)
  .use(taskListPlugin)
  .use(tableCheckboxPlugin)
  .use(headingAnchorsPlugin)
  .use(injectLineNumbers)
  .use(lineStartsPlugin);
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

// Every header cell carries a sort button; media/webview.js turns a click into
// a sortTable message, the stylesheet hides it unless tables.previewSort is on
// (docs/DECISIONS.md #49). data-col is the cell's column index.
md.renderer.rules.th_open = (tokens, idx, options, _env, self) => {
  let col = 0;
  for (let i = idx - 1; i >= 0 && tokens[i].type !== 'tr_open'; i--)
    if (tokens[i].type === 'th_open') col++;
  return (
    self.renderToken(tokens, idx, options) +
    `<button type="button" class="mw-sort codicon codicon-sort-precedence" data-col="${col}"` +
    ' title="Sort by this column" aria-label="Sort by this column"></button>'
  );
};

registerFrontmatterRenderer(md);

module.exports = { md, injectLineNumbers };
