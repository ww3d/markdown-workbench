// Render YAML frontmatter as a compact property card instead of the default
// (which would mis-render the delimiters as hr / setext heading). Flat
// "key: value" lines become a key/value grid; anything more complex falls
// back to a monospace block inside the same card.
import type { MarkdownIt } from 'markdown-it';

/**
 * Installs the frontmatter renderer on `md`: a key/value card for flat
 * "key: value" lines, a monospace block in the same card otherwise.
 */
function registerFrontmatterRenderer(md: MarkdownIt): void {
  md.renderer.rules.front_matter = (tokens, idx) => {
    const token = tokens[idx];
    if (!token) return ''; // markdown-it calls a rule only for a token it has
    const line = token.map ? ` data-line="${token.map[0]}"` : '';
    const e = md.utils.escapeHtml;
    // markdown-it-front-matter keeps the raw YAML text in `meta`.
    const meta = typeof token.meta === 'string' ? token.meta : '';
    const lines = meta.split(/\r?\n/).filter((l) => l.trim() !== '');
    const pairs = lines.map((l) => /^([\w.-]+)\s*:\s*(.*)$/.exec(l));
    if (lines.length && pairs.every((m) => m !== null)) {
      const rows = pairs
        .map(
          (m) =>
            '<div class="fm-key">' +
            e(m[1] ?? '') +
            '</div><div class="fm-val">' +
            e(m[2] ?? '') +
            '</div>',
        )
        .join('');
      return `<div class="frontmatter"${line}>${rows}</div>\n`;
    }
    return (
      '<div class="frontmatter fm-raw"' +
      line +
      '><pre>' +
      e(meta) +
      '</pre></div>\n'
    );
  };
}

export { registerFrontmatterRenderer };
