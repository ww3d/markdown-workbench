// Checkboxes inside table cells: "[ ]" / "[x]" in a td becomes a clickable
// checkbox. A table row is a single source line that can hold several
// checkboxes, so each one carries the row line plus its occurrence index on
// that line for the surgical toggle.
const CELL_BOX_RE = /\[( |x|X)\]/g;

function tableCheckboxPlugin(md) {
  md.core.ruler.after('inline', 'table-checkboxes', (state) => {
    let rowLine = null;
    let rowIdx = 0; // occurrence counter within the current source line
    let inCell = false;
    for (const token of state.tokens) {
      if (token.type === 'tr_open') {
        rowLine = token.map ? token.map[0] : null;
        rowIdx = 0;
      } else if (token.type === 'td_open') {
        inCell = true;
      } // th excluded: header cells stay literal (documented contract)
      else if (token.type === 'td_close' || token.type === 'th_close') {
        inCell = false;
      } else if (
        token.type === 'inline' &&
        inCell &&
        rowLine !== null &&
        token.children
      ) {
        const out = [];
        for (const child of token.children) {
          if (child.type !== 'text' || !CELL_BOX_RE.test(child.content)) {
            out.push(child);
            continue;
          }
          CELL_BOX_RE.lastIndex = 0;
          let last = 0;
          for (const m of child.content.matchAll(CELL_BOX_RE)) {
            if (m.index > last) {
              const t = new state.Token('text', '', 0);
              t.content = child.content.slice(last, m.index);
              out.push(t);
            }
            const checked = m[1].toLowerCase() === 'x';
            const box = new state.Token('html_inline', '', 0);
            box.content =
              '<input type="checkbox" class="cell-task"' +
              (checked ? ' checked' : '') +
              ' data-line="' +
              rowLine +
              '" data-idx="' +
              rowIdx++ +
              '" tabindex="-1">';
            out.push(box);
            last = m.index + m[0].length;
          }
          if (last < child.content.length) {
            const t = new state.Token('text', '', 0);
            t.content = child.content.slice(last);
            out.push(t);
          }
        }
        token.children = out;
      }
    }
    return true;
  });
}

export { CELL_BOX_RE, tableCheckboxPlugin };
