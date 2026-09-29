// Wrap the inline content of task list items in a clickable row with a
// checkbox. The li carries data-checked; data-line comes from injectLineNumbers.
import type { MarkdownIt } from 'markdown-it';

/** markdown-it core rule: render "[ ]" / "[x]" list items as task rows with a checkbox. */
function taskListPlugin(md: MarkdownIt): void {
  md.core.ruler.after('inline', 'task-lists', (state) => {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i++) {
      const inline = tokens[i];
      if (inline?.type !== 'inline') continue;
      if (tokens[i - 1]?.type !== 'paragraph_open') continue;
      const li = tokens[i - 2];
      if (li?.type !== 'list_item_open') continue;
      const children = inline.children;
      const first = children?.[0];
      if (!children || !first) continue;
      // The label may be empty ("8. [ ]"): every fresh Enter-continuation
      // line looks like that, so it must render as a task row, not as
      // literal text (editing-oriented deviation from the built-in preview,
      // docs/DECISIONS.md #25).
      const m = /^\[( |x|X)\](?:\s+|$)/.exec(first.content);
      if (!m) continue;

      const checked = m[1]?.toLowerCase() === 'x';
      first.content = first.content.slice(m[0].length);

      li.attrJoin('class', `task${checked ? ' done' : ''}`);
      li.attrSet('data-checked', checked ? 'true' : 'false');

      const open = new state.Token('html_inline', '', 0);
      open.content =
        '<span class="task-row"><input type="checkbox"' +
        (checked ? ' checked' : '') +
        ' tabindex="-1"><span class="task-label">';
      const close = new state.Token('html_inline', '', 0);
      close.content = '</span></span>';
      children.unshift(open);
      children.push(close);
    }
    return true;
  });
}

export { taskListPlugin };
