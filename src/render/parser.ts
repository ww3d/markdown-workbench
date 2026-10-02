// The one markdown-it instance of the extension: the preview renders with it,
// and the table editor reads its block structure (src/tables/blocks.ts), so the
// editor sees exactly the tables the preview shows (docs/DECISIONS.md #49, D1).
// No vscode import - the Shiki fence renderer is added in ./index.ts.
/// <reference path="./markdown-it-lib.d.ts" />

import MarkdownIt from 'markdown-it';
import type { MarkdownIt as MarkdownItInstance } from 'markdown-it';
import frontMatter from 'markdown-it-front-matter';
import { extraMarkerListsPlugin } from './extra-markers.ts';
import { taskListPlugin } from './task-lists.ts';
import { tableCheckboxPlugin } from './table-checkboxes.ts';
import { headingAnchorsPlugin } from './heading-anchors.ts';
import { registerFrontmatterRenderer } from './frontmatter.ts';

/**
 * Attach the source start line to every block token that has a map. Used for
 * toggling (tasks) and bidirectional scroll sync.
 */
function injectLineNumbers(md: MarkdownItInstance): void {
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
 */
function lineStartsPlugin(md: MarkdownItInstance): void {
  for (const name of ['table', 'paragraph']) {
    const rule = md.block.ruler.__rules__.find((r) => r.name === name);
    if (!rule) throw new Error(`markdown-it has no block rule '${name}'`);
    const fn = rule.fn;
    md.block.ruler.at(
      name,
      (state, start, end, silent) => {
        const ok = fn(state, start, end, silent);
        const out = state.env.lineStarts;
        if (ok && !silent && Array.isArray(out))
          for (let l = start; l < state.line; l++)
            out[l] = {
              kind: name,
              start,
              // Every line the rule consumed has its marks.
              at: (state.bMarks[l] ?? 0) + (state.tShift[l] ?? 0),
            };
        return ok;
      },
      { alt: rule.alt },
    );
  }
}

/** The shared instance, wired with every plugin and renderer override below. */
const md: MarkdownItInstance = new MarkdownIt({ html: true, linkify: true })
  .use(frontMatter, () => {
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
// column can grow symmetrically into both margins (src/webview/tables/tables.css).
// The wrapper itself carries no data-line - scroll sync and the cell toggles
// keep reading the table's and rows' own attributes.
md.renderer.rules.table_open = (tokens, idx, options, _env, self) =>
  `<div class="table-wrap">${self.renderToken(tokens, idx, options)}`;
md.renderer.rules.table_close = (tokens, idx, options, _env, self) =>
  `${self.renderToken(tokens, idx, options)}</div>\n`;

// Every header cell carries a sort button; the webview (src/webview/tasks/) turns a click into
// a sortTable message, the stylesheet hides it unless tables.previewSort is on
// (docs/DECISIONS.md #49). data-col is the cell's column index.
md.renderer.rules.th_open = (tokens, idx, options, _env, self) => {
  let col = 0;
  for (let i = idx - 1; i >= 0 && tokens[i]?.type !== 'tr_open'; i--)
    if (tokens[i]?.type === 'th_open') col++;
  return (
    self.renderToken(tokens, idx, options) +
    `<button type="button" class="mw-sort codicon codicon-sort-precedence" data-col="${col}"` +
    ' title="Sort by this column" aria-label="Sort by this column"></button>'
  );
};

registerFrontmatterRenderer(md);

export { md, injectLineNumbers };
