// Markdown rendering pipeline for the workbench view: markdown-it (the same
// engine as the built-in VS Code preview) with the task-list, table-checkbox
// and line-number plugins, a frontmatter property-card renderer, and Shiki
// syntax highlighting (same grammars/themes as the built-in preview).

const vscode = require('vscode');
const MarkdownIt = require('markdown-it');

// --- markdown-it setup -------------------------------------------------------

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
      const m = /^\[( |x|X)\]\s+/.exec(children[0].content);
      if (!m) continue;

      const checked = m[1].toLowerCase() === 'x';
      children[0].content = children[0].content.slice(m[0].length);

      const li = tokens[i - 2];
      li.attrJoin('class', 'task' + (checked ? ' done' : ''));
      li.attrSet('data-checked', checked ? 'true' : 'false');

      const open = new state.Token('html_inline', '', 0);
      open.content = '<span class="task-row"><input type="checkbox"'
        + (checked ? ' checked' : '') + ' tabindex="-1"><span class="task-label">';
      const close = new state.Token('html_inline', '', 0);
      close.content = '</span></span>';
      children.unshift(open);
      children.push(close);
    }
    return true;
  });
}

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
      if (token.type === 'tr_open') { rowLine = token.map ? token.map[0] : null; rowIdx = 0; }
      else if (token.type === 'td_open') { inCell = true; } // th excluded: header cells stay literal (documented contract)
      else if (token.type === 'td_close' || token.type === 'th_close') { inCell = false; }
      else if (token.type === 'inline' && inCell && rowLine !== null && token.children) {
        const out = [];
        for (const child of token.children) {
          if (child.type !== 'text' || !CELL_BOX_RE.test(child.content)) {
            out.push(child);
            continue;
          }
          CELL_BOX_RE.lastIndex = 0;
          let last = 0, m;
          while ((m = CELL_BOX_RE.exec(child.content))) {
            if (m.index > last) {
              const t = new state.Token('text', '', 0);
              t.content = child.content.slice(last, m.index);
              out.push(t);
            }
            const checked = m[1].toLowerCase() === 'x';
            const box = new state.Token('html_inline', '', 0);
            box.content = '<input type="checkbox" class="cell-task"'
              + (checked ? ' checked' : '')
              + ' data-line="' + rowLine + '" data-idx="' + (rowIdx++) + '" tabindex="-1">';
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
  .use(require('markdown-it-front-matter'), () => { /* rendered via rule below */ })
  .use(taskListPlugin)
  .use(tableCheckboxPlugin)
  .use(injectLineNumbers);

// Render YAML frontmatter as a compact property card instead of the default
// (which would mis-render the delimiters as hr / setext heading). Flat
// "key: value" lines become a key/value grid; anything more complex falls
// back to a monospace block inside the same card.
md.renderer.rules.front_matter = (tokens, idx) => {
  const token = tokens[idx];
  const line = token.map ? ' data-line="' + token.map[0] + '"' : '';
  const e = md.utils.escapeHtml;
  const lines = (token.meta || '').split(/\r?\n/).filter((l) => l.trim() !== '');
  const pairs = lines.map((l) => /^([\w.-]+)\s*:\s*(.*)$/.exec(l));
  if (lines.length && pairs.every(Boolean)) {
    const rows = pairs.map((m) =>
      '<div class="fm-key">' + e(m[1]) + '</div><div class="fm-val">' + e(m[2]) + '</div>'
    ).join('');
    return '<div class="frontmatter"' + line + '>' + rows + '</div>\n';
  }
  return '<div class="frontmatter fm-raw"' + line + '><pre>' + e(token.meta || '') + '</pre></div>\n';
};

// --- Syntax highlighting (shiki, same grammars/themes as VS Code) -------------

let highlighter = null;
const activePosts = new Set(); // re-render callbacks of all open views

const SHIKI_LANGS = [
  'powershell', 'bat', 'shellscript', 'json', 'jsonc', 'yaml', 'ini', 'xml',
  'javascript', 'typescript', 'html', 'css', 'markdown', 'csharp', 'python',
  'sql', 'diff', 'docker'
];

async function initHighlighter() {
  try {
    const { createHighlighter } = require('shiki');
    // JS regex engine, NOT Shiki's default Oniguruma WASM engine: the WASM
    // binary is loaded via a template-literal import('shiki/wasm') that no
    // bundler can resolve statically, so it survives bundling as a bare
    // specifier. That works in the repo (node_modules next to dist/) and
    // dies in the installed vsix, which ships no node_modules -
    // ERR_MODULE_NOT_FOUND, silent plain-code fallback. Guarded by
    // scripts/bundle-smoke.js, which runs the bundle without node_modules.
    const { createJavaScriptRegexEngine } = require('shiki/engine/javascript');
    highlighter = await createHighlighter({
      engine: createJavaScriptRegexEngine(),
      themes: ['dark-plus', 'light-plus'],
      langs: SHIKI_LANGS
    });
    for (const post of activePosts) post(); // re-render already open views
  } catch (err) {
    console.error('markdown-workbench: shiki init failed, falling back to plain code blocks', err);
  }
}

function shikiTheme() {
  const kind = vscode.window.activeColorTheme.kind;
  // 2 = Dark, 3 = HighContrast (dark); 1 = Light, 4 = HighContrastLight
  return (kind === 2 || kind === 3) ? 'dark-plus' : 'light-plus';
}

// Custom fence renderer: shiki output with data-line injected, plain fallback
// for unknown languages or while the highlighter is still loading.
md.renderer.rules.fence = (tokens, idx) => {
  const token = tokens[idx];
  const lang = (token.info || '').trim().split(/\s+/)[0].toLowerCase();
  let line = '';
  if (token.map) {
    line = ' data-line="' + token.map[0] + '"';
    // End line (closing fence) enables proportional scrolling inside the block.
    if (token.map[1] - 1 > token.map[0]) line += ' data-line-end="' + (token.map[1] - 1) + '"';
  }
  if (highlighter && lang) {
    try {
      return highlighter
        .codeToHtml(token.content, { lang, theme: shikiTheme() })
        .replace('<pre', '<pre' + line);
    } catch (_) { /* unknown language -> plain fallback below */ }
  }
  const cls = lang ? ' class="language-' + md.utils.escapeHtml(lang) + '"' : '';
  return '<pre' + line + '><code' + cls + '>' + md.utils.escapeHtml(token.content) + '</code></pre>\n';
};

module.exports = {
  md, SHIKI_LANGS, initHighlighter, shikiTheme, activePosts,
  // Exported for tests only.
  _internal: {
    md, CELL_BOX_RE, shikiTheme,
    taskListPlugin, tableCheckboxPlugin, injectLineNumbers
  }
};
