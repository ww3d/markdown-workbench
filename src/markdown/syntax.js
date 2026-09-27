// Markdown source primitives shared by the editor commands, the preview's toggle
// paths and the clipboard diff. Pure and free of the vscode module, so modules
// that must run without the extension host (src/clipboard-diff/) can reuse the
// one definition instead of a copy.

// Matches task list items: "- [ ] text", "* [x] text", "1. [X] text", with
// indentation; the label may be empty. Compound items carry a second list
// marker between the first marker and the box ("1. - [ ] text",
// "- 1. [ ] text") - generically (marker, whitespace) x2, box. Group 1
// spans the whole prefix up to the box, so applyToggle keeps hitting the
// box character exactly. Must classify the same lines as the render-side
// task-list plugin.
const CHECKBOX_RE =
  /^(\s*(?:[-*+]|\d+[.)])\s+(?:(?:[-*+]|\d+[.)])\s+)?)\[( |x|X)\](\s.*)?$/;

// Pure helpers: reflow a block of table lines.
function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

function isSeparatorRow(cells) {
  return cells.length > 0 && cells.every((c) => /^:?-+:?$/.test(c));
}

function reflowTable(lines, mode) {
  const rows = lines.map(splitRow);
  const colCount = Math.max(...rows.map((r) => r.length));
  for (const r of rows) while (r.length < colCount) r.push('');

  const widths = Array.from({ length: colCount }, (_, i) =>
    Math.max(
      3,
      ...rows.filter((r) => !isSeparatorRow(r)).map((r) => r[i].length),
    ),
  );

  return rows.map((r) => {
    if (isSeparatorRow(r)) {
      return (
        '| ' +
        r
          .map((c, i) => {
            const left = c.startsWith(':'),
              right = c.endsWith(':');
            const w = mode === 'distribute' ? widths[i] : 3;
            const dashes = '-'.repeat(
              Math.max(1, w - (left ? 1 : 0) - (right ? 1 : 0)),
            );
            return (left ? ':' : '') + dashes + (right ? ':' : '');
          })
          .join(' | ') +
        ' |'
      );
    }
    const cells =
      mode === 'distribute' ? r.map((c, i) => c.padEnd(widths[i])) : r;
    return `| ${cells.join(' | ')} |`;
  });
}

module.exports = { CHECKBOX_RE, splitRow, isSeparatorRow, reflowTable };
