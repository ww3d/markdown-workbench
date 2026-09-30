// --- Syntax highlighting (shiki, same grammars/themes as VS Code) -------------

import type { MarkdownIt } from 'markdown-it';
import type { BundledLanguage, Highlighter, ShikiTransformer } from 'shiki';
import * as vscode from 'vscode';

let highlighter: Highlighter | null = null;

/**
 * Where the highlighter is: never started, loading, ready, or failed (fences stay plain).
 * A restored view waits on `loading` to learn whether its highlighted stand still holds.
 */
type HighlighterState = 'idle' | 'loading' | 'ready' | 'failed';
let state: HighlighterState = 'idle';

/** Re-render callbacks of all open views; initHighlighter calls each once Shiki is ready. */
const activePosts: Set<() => void> = new Set();

// Called once the load has ended either way, after the re-render of the open views.
const settledListeners: Set<() => void> = new Set();

/** The highlighter's current state. */
function highlighterState(): HighlighterState {
  return state;
}

/**
 * Call `listener` once the highlighter load ends (ready or failed), after
 * {@link activePosts} ran. Returns the function that unregisters it.
 */
function onHighlighterSettled(listener: () => void): () => void {
  settledListeners.add(listener);
  return () => settledListeners.delete(listener);
}

/** Language ids bundled into the shiki highlighter. */
const SHIKI_LANGS: BundledLanguage[] = [
  'powershell',
  'bat',
  'shellscript',
  'json',
  'jsonc',
  'yaml',
  'ini',
  'xml',
  'javascript',
  'typescript',
  'html',
  'css',
  'markdown',
  'csharp',
  'python',
  'sql',
  'diff',
  'docker',
];

/**
 * Load the shiki highlighter for {@link SHIKI_LANGS}, then re-render every open
 * view. Logs and leaves `highlighter` null on failure, so fences fall back to
 * plain code blocks instead of breaking the preview.
 */
async function initHighlighter(): Promise<void> {
  state = 'loading';
  try {
    const { createHighlighter } = await import('shiki');
    // JS regex engine, NOT Shiki's default Oniguruma WASM engine: the WASM
    // binary is loaded via a template-literal import('shiki/wasm') that no
    // bundler can resolve statically, so it survives bundling as a bare
    // specifier. That works in the repo (node_modules next to dist/) and
    // dies in the installed vsix, which ships no node_modules -
    // ERR_MODULE_NOT_FOUND, silent plain-code fallback. Guarded by
    // scripts/bundle-smoke.ts, which runs the bundle without node_modules.
    const { createJavaScriptRegexEngine } = await import(
      'shiki/engine/javascript'
    );
    highlighter = await createHighlighter({
      engine: createJavaScriptRegexEngine(),
      themes: ['dark-plus', 'light-plus'],
      langs: SHIKI_LANGS,
    });
    state = 'ready';
    for (const post of activePosts) post(); // re-render already open views
  } catch (err) {
    if (!highlighter) state = 'failed'; // a throwing re-render leaves a loaded highlighter ready
    console.error(
      'markdown-workbench: shiki init failed, falling back to plain code blocks',
      err,
    );
  }
  for (const listener of [...settledListeners]) listener();
}

/** The shiki theme matching the active VS Code color theme's kind. */
function shikiTheme(): 'dark-plus' | 'light-plus' {
  const kind = vscode.window.activeColorTheme.kind;
  // 2 = Dark, 3 = HighContrast (dark); 1 = Light, 4 = HighContrastLight
  return kind === 2 || kind === 3 ? 'dark-plus' : 'light-plus';
}

// The preview paints code blocks with its own --code-bg (webview.css); shiki's
// inline theme background would override the stylesheet, so it is dropped.
const dropShikiBackground: ShikiTransformer = {
  pre(node) {
    node.properties.style = String(node.properties.style || '')
      .split(';')
      .filter((d) => d && !/^\s*background(-color)?\s*:/.test(d))
      .join(';');
  },
};

/**
 * Custom fence renderer: shiki output with data-line injected, plain fallback
 * for unknown languages or while the highlighter is still loading.
 */
function registerFenceRenderer(md: MarkdownIt): void {
  md.renderer.rules.fence = (tokens, idx) => {
    const token = tokens[idx];
    if (!token) return ''; // markdown-it calls a rule only for a token it has
    const lang = (
      (token.info || '').trim().split(/\s+/)[0] ?? ''
    ).toLowerCase();
    let line = '';
    if (token.map) {
      line = ` data-line="${token.map[0]}"`;
      // End line (closing fence) enables proportional scrolling inside the block.
      if (token.map[1] - 1 > token.map[0])
        line += ` data-line-end="${token.map[1] - 1}"`;
    }
    if (highlighter && lang) {
      try {
        return highlighter
          .codeToHtml(token.content, {
            lang,
            theme: shikiTheme(),
            transformers: [dropShikiBackground],
          })
          .replace('<pre', `<pre${line}`);
      } catch (_) {
        /* unknown language -> plain fallback below */
      }
    }
    const cls = lang ? ` class="language-${md.utils.escapeHtml(lang)}"` : '';
    return (
      '<pre' +
      line +
      '><code' +
      cls +
      '>' +
      md.utils.escapeHtml(token.content) +
      '</code></pre>\n'
    );
  };
}

export type { HighlighterState };
export {
  activePosts,
  highlighterState,
  onHighlighterSettled,
  SHIKI_LANGS,
  initHighlighter,
  shikiTheme,
  registerFenceRenderer,
};
