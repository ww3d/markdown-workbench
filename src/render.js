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
      // The label may be empty ("8. [ ]"): every fresh Enter-continuation
      // line looks like that, so it must render as a task row, not as
      // literal text (editing-oriented deviation from the built-in preview,
      // docs/DECISIONS.md #25).
      const m = /^\[( |x|X)\](?:\s+|$)/.exec(children[0].content);
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

// --- Custom (non-CommonMark) list markers in the preview ----------------------
//
// Opt-in via lists.renderExtraMarkers (with lists.extraMarkers non-empty),
// passed through render env from views.js. Lines that start with an enabled
// custom marker are plain text to CommonMark, so markdown-it leaves them in a
// paragraph; this core rule turns such paragraphs into real ol/ul lists so they
// get the same outline styling and depth as native lists (the source marker is
// dropped, the visual marker comes from the stylesheet, exactly as for native
// ordered lists). A deliberate, documented deviation from CommonMark for
// working notes (docs/DECISIONS.md): the same document renders as plain text
// anywhere else. Off by default. The marker matcher mirrors editing.js but is
// kept local so render.js stays decoupled from the editor module.
const SYMBOL_MARKERS = ['->', '→', '❯'];

function buildExtraMarkerMatcher(markers) {
  if (!markers || !markers.length) return null;
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const symbols = [], lower = new Set(), upper = new Set(), digit = new Set();
  for (const tok of markers) {
    if (SYMBOL_MARKERS.includes(tok)) symbols.push(tok);
    else if (/^[a-z][).:]$/.test(tok)) lower.add(tok[1]);
    else if (/^[A-Z][).:]$/.test(tok)) upper.add(tok[1]);
    else if (/^1[).:]$/.test(tok)) digit.add(tok[1]);
  }
  const alts = [];
  if (symbols.length) alts.push(symbols.map(esc).join('|'));
  const cls = (set) => '[' + [...set].join('') + ']';
  if (lower.size) alts.push('[a-z]{1,2}' + cls(lower));
  if (upper.size) alts.push('[A-Z]{1,2}' + cls(upper));
  if (digit.size) alts.push('\\d+' + cls(digit));
  if (!alts.length) return null;
  return new RegExp('^(\\s*)(?:' + alts.join('|') + ')(\\s+)(.*)$');
}

// Ordered (letters/digits count) vs. bullet (symbols repeat) - decides ol/ul.
function isOrderedExtra(marker) {
  return /^(?:\d+|[a-zA-Z]{1,2})[).:]$/.test(marker);
}

function parseExtraLine(line, matcher) {
  const m = matcher.exec(line);
  if (!m) return null;
  return { indent: m[1].length, marker: line.slice(m[1].length).match(/^\S+/)[0], text: m[3] };
}

// Build ol/ul list tokens for a run of parsed custom-marker lines, nesting by
// indentation. Items deeper than the run's base indent become a child list.
function buildExtraListTokens(state, items) {
  function build(lo, hi) {
    const out = [];
    const base = items[lo].indent;
    const ordered = isOrderedExtra(items[lo].marker);
    const tag = ordered ? 'ol' : 'ul';
    const type = ordered ? 'ordered_list' : 'bullet_list';
    const open = new state.Token(type + '_open', tag, 1);
    open.map = [items[lo].line, items[hi - 1].line + 1];
    open.block = true;
    out.push(open);
    let k = lo;
    while (k < hi) {
      const it = items[k];
      const li = new state.Token('list_item_open', 'li', 1);
      li.map = [it.line, it.line + 1];
      li.block = true;
      out.push(li);
      const inline = new state.Token('inline', '', 0);
      inline.content = it.text;
      inline.map = [it.line, it.line + 1];
      inline.children = [];
      out.push(inline);
      let c = k + 1;
      while (c < hi && items[c].indent > base) c++;
      if (c > k + 1) out.push(...build(k + 1, c));
      out.push(new state.Token('list_item_close', 'li', -1));
      k = c;
    }
    out.push(new state.Token(type + '_close', tag, -1));
    return out;
  }
  return build(0, items.length);
}

function extraMarkerListsPlugin(md) {
  md.core.ruler.before('inline', 'extra-marker-lists', (state) => {
    const cfg = (state.env && state.env.markdownWorkbench) || {};
    if (!cfg.renderExtraMarkers) return false;
    const matcher = buildExtraMarkerMatcher(cfg.extraMarkers);
    if (!matcher) return false;

    // Read raw source lines (not inline.content, which has the indentation of
    // continuation lines stripped - nesting needs the real columns).
    const srcLines = state.src.split('\n');
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'paragraph_open') continue;
      const inline = tokens[i + 1];
      if (!inline || inline.type !== 'inline' || !tokens[i].map) continue;
      const [start, end] = tokens[i].map;
      const parsed = srcLines.slice(start, end).map((l) => parseExtraLine(l, matcher));
      if (!parsed.length || !parsed.every(Boolean)) continue; // not an all-marker paragraph
      parsed.forEach((p, k) => { p.line = start + k; });
      const newTokens = buildExtraListTokens(state, parsed);
      tokens.splice(i, 3, ...newTokens);
      i += newTokens.length - 1;
    }
    return true;
  });
}

// --- Heading anchors (GitHub-compatible slugs) --------------------------------
//
// Give every heading an id derived from its visible text so in-document TOC
// links ([Text](#slug)) resolve in the preview (docs/DECISIONS.md #31). The
// slug rule follows github-slugger: lowercase, then strip every character that
// is not a Unicode letter, mark, decimal/letter number or connector
// punctuation, hyphen or space, then turn spaces into hyphens. Duplicate slugs
// get -1, -2, ... via the same occurrences bookkeeping github-slugger uses.
// github-slugger ships that set as a generated explicit character-class; this
// compact property-escape form matches it for the realistic cases but is not
// bitwise identical - it diverges only on obscure code points (Unicode
// assignments newer than github-slugger's pinned data, and 130 enclosed
// alphanumeric Latin letters in \p{So} - U+24B6..U+24E9 plus three blocks in
// U+1F130..U+1F189 - that github-slugger keeps). \p{Nd}\p{Nl}, NOT \p{N}: the
// latter also keeps \p{No} (m^2, fractions, circled digits) that github-slugger
// strips. See DECISIONS.md #31.
const SLUG_REMOVE = /[^\p{L}\p{M}\p{Nd}\p{Nl}\p{Pc}\- ]/gu;

function slugify(text) {
  return text.toLowerCase().replace(SLUG_REMOVE, '').replace(/ /g, '-');
}

// The visible text of a heading is the concatenated content of its inline
// text and code_inline children; markup tokens (emphasis, link delimiters)
// carry no content and do not contribute.
function headingText(inline) {
  let text = '';
  for (const child of inline.children || []) {
    if (child.type === 'text' || child.type === 'code_inline') text += child.content;
  }
  return text;
}

function headingAnchorsPlugin(md) {
  md.core.ruler.push('heading-anchors', (state) => {
    // Per-render occurrences map: the md instance is shared across renders, so
    // this state must live in the rule run, never at module scope, or the
    // duplicate suffix would leak between documents.
    const occurrences = Object.create(null);
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'heading_open') continue;
      const inline = tokens[i + 1];
      if (!inline || inline.type !== 'inline') continue;
      const base = slugify(headingText(inline));
      let slug = base;
      while (slug in occurrences) { occurrences[base]++; slug = base + '-' + occurrences[base]; }
      occurrences[slug] = 0;
      tokens[i].attrSet('id', slug);
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
  .use(extraMarkerListsPlugin)
  .use(taskListPlugin)
  .use(tableCheckboxPlugin)
  .use(headingAnchorsPlugin)
  .use(injectLineNumbers);

// Wrap every table in a breakout wrapper so tables wider than the reading
// column can grow symmetrically into both margins (webview.css .table-wrap).
// The wrapper itself carries no data-line - scroll sync and the cell toggles
// keep reading the table's and rows' own attributes.
md.renderer.rules.table_open = (tokens, idx, options, env, self) =>
  '<div class="table-wrap">' + self.renderToken(tokens, idx, options);
md.renderer.rules.table_close = (tokens, idx, options, env, self) =>
  self.renderToken(tokens, idx, options) + '</div>\n';

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
