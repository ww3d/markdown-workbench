// Wrap the inline content of task list items in a clickable row with a
// checkbox. The li carries data-checked; data-line comes from injectLineNumbers.
function taskListPlugin(md) {
  md.core.ruler.after('inline', 'task-lists', (state) => {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i++) {
      if (tokens[i].type !== 'inline') continue;
      if (tokens[i - 1].type !== 'paragraph_open') continue;
      if (tokens[i - 2].type !== 'list_item_open') continue;
      const children = tokens[i].children;
      if (!children || children.length === 0) continue;
      // The label may be empty ("8. [ ]"): every fresh Enter-continuation
      // line looks like that, so it must render as a task row, not as
      // literal text (editing-oriented deviation from the built-in preview,
      // docs/DECISIONS.md #25).
      const m = /^\[( |x|X)\](?:\s+|$)/.exec(children[0].content);
      if (!m) continue;

      const checked = m[1].toLowerCase() === 'x';
      children[0].content = children[0].content.slice(m[0].length);

      const li = tokens[i - 2];
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
