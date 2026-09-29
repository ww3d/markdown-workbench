// Render YAML frontmatter as a compact property card instead of the default
// (which would mis-render the delimiters as hr / setext heading). Flat
// "key: value" lines become a key/value grid; anything more complex falls
// back to a monospace block inside the same card.
function registerFrontmatterRenderer(md) {
  md.renderer.rules.front_matter = (tokens, idx) => {
    const token = tokens[idx];
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    const e = md.utils.escapeHtml;
    const lines = (token.meta || '')
      .split(/\r?\n/)
      .filter((l) => l.trim() !== '');
    const pairs = lines.map((l) => /^([\w.-]+)\s*:\s*(.*)$/.exec(l));
    if (lines.length && pairs.every(Boolean)) {
      const rows = pairs
        .map(
          (m) =>
            '<div class="fm-key">' +
            e(m[1]) +
            '</div><div class="fm-val">' +
            e(m[2]) +
            '</div>',
        )
        .join('');
      return `<div class="frontmatter"${line}>${rows}</div>\n`;
    }
    return (
      '<div class="frontmatter fm-raw"' +
      line +
      '><pre>' +
      e(token.meta || '') +
      '</pre></div>\n'
    );
  };
}

export { registerFrontmatterRenderer };
