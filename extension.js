// Markdown Workbench - renders markdown via markdown-it (same engine as the
// built-in VS Code preview), lets the user toggle checkboxes (multi-select
// toggles in parallel), and mirrors every change surgically into the source.
// Works as custom editor ("Open as Markdown Workbench") and as side preview.

const vscode = require('vscode');
const MarkdownIt = require('markdown-it');

// Matches task list items: "- [ ] text", "* [x] text", "1. [X] text", with indentation.
const CHECKBOX_RE = /^(\s*(?:[-*+]|\d+[.)])\s+)\[( |x|X)\](\s.*)?$/;

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
    highlighter = await createHighlighter({
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

// --- Activation --------------------------------------------------------------

function activate(context) {
  extensionUri = context.extensionUri;
  initHighlighter();

  require('./editing').registerEditingCommands(context, SHIKI_LANGS);

  context.subscriptions.push(
    vscode.window.registerCustomEditorProvider(
      'markdownWorkbench.editor',
      new ChecklistEditorProvider(),
      { webviewOptions: { retainContextWhenHidden: true } }
    )
  );

  // Analog to built-in markdown.reopenAsPreview: replaces the editor tab
  // with the checklist custom editor.
  context.subscriptions.push(
    vscode.commands.registerCommand('markdownWorkbench.open', (uri) => {
      const active = vscode.window.activeTextEditor && vscode.window.activeTextEditor.document.uri;
      const target = uri || active;
      if (!target) return;
      captureScrollPosition(target);
      if (!uri || (active && uri.toString() === active.toString())) {
        // In-place swap of the active editor, like the built-in
        // reopenAsPreview - vscode.openWith would open a second tab because
        // tabs are keyed by resource + editor type.
        vscode.commands.executeCommand('reopenActiveEditorWith', 'markdownWorkbench.editor');
      } else {
        // Invoked for a non-active resource (e.g. tab context on an
        // inactive tab): no active editor to swap, open it instead.
        vscode.commands.executeCommand('vscode.openWith', target, 'markdownWorkbench.editor');
      }
    })
  );

  // Preview panels, analog to the built-in markdown preview:
  // showPreview opens in the active editor group, showPreviewToSide beside it;
  // focus moves to the preview (like the built-in). The source file stays
  // open; panels close independently. One per document.
  const previews = new Map(); // uri string -> WebviewPanel
  let activePreviewDoc = null; // document of the focused preview panel

  async function openPreviewPanel(uri, viewColumn) {
    let document;
    if (uri) {
      document = await vscode.workspace.openTextDocument(uri);
    } else {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      document = editor.document;
    }
    const key = document.uri.toString();

    const existing = previews.get(key);
    if (existing) {
      existing.reveal(undefined, false);
      return;
    }

    captureScrollPosition(document.uri);
    const name = document.uri.path.split('/').pop() || 'Untitled';
    const panel = vscode.window.createWebviewPanel(
      'markdownWorkbench.preview',
      'Checklist: ' + name,
      { viewColumn, preserveFocus: false },
      { enableScripts: true, retainContextWhenHidden: true }
    );
    panel.iconPath = checklistIconPath();
    previews.set(key, panel);
    activePreviewDoc = document;
    panel.onDidChangeViewState((e) => {
      if (e.webviewPanel.active) activePreviewDoc = document;
    });
    panel.onDidDispose(() => {
      previews.delete(key);
      if (activePreviewDoc === document) activePreviewDoc = null;
    });

    wireWebview(document, panel, /* closeWithDocument: */ true);
  }

  context.subscriptions.push(
    vscode.commands.registerCommand('markdownWorkbench.showPreview', (uri) =>
      openPreviewPanel(uri, vscode.ViewColumn.Active)),
    vscode.commands.registerCommand('markdownWorkbench.showPreviewToSide', (uri) =>
      openPreviewPanel(uri, vscode.ViewColumn.Beside)),
    // Toggle: close the document's preview panel if one is open, otherwise
    // open it to the side. Analog to the built-in markdown.togglePreview.
    vscode.commands.registerCommand('markdownWorkbench.togglePreview', () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) return;
      const existing = previews.get(editor.document.uri.toString());
      if (existing) {
        existing.dispose();
        return;
      }
      openPreviewPanel(undefined, vscode.ViewColumn.Beside);
    }),
    // Analog to markdown.showSource: from the focused preview panel back to
    // the source editor. A visible editor wins; otherwise the source is shown
    // in the panel's own group - when the preview was opened in the active
    // group, the source tab sits there in the background (not in
    // visibleTextEditors!) and gets focused instead of opening a new group.
    vscode.commands.registerCommand('markdownWorkbench.showSource', async () => {
      if (!activePreviewDoc) return;
      const open = vscode.window.visibleTextEditors
        .find((e) => e.document.uri.toString() === activePreviewDoc.uri.toString());
      const panel = previews.get(activePreviewDoc.uri.toString());
      const viewColumn = open ? open.viewColumn
        : (panel && panel.viewColumn) || vscode.ViewColumn.Active;
      const editor = await vscode.window.showTextDocument(activePreviewDoc, { viewColumn });
      if (!open) revealLastKnownLine(editor); // visible editors are already live-synced
    }),
    // Analog to markdown.reopenAsSource: replace the active checklist custom
    // editor with the default text editor.
    vscode.commands.registerCommand('markdownWorkbench.reopenAsSource', async (uri) => {
      const target = uri || activeCustomDocUri;
      if (!target) return;
      // In-place swap back to the text editor, like markdown.reopenAsSource.
      await vscode.commands.executeCommand('reopenActiveEditorWith', 'default');
      if (vscode.window.activeTextEditor
          && vscode.window.activeTextEditor.document.uri.toString() === target.toString()) {
        revealLastKnownLine(vscode.window.activeTextEditor);
      }
    }),
    // Save/undo/redo bridges for the focused preview panel. A webview panel
    // is not a text editor, so the default Ctrl+S/Z/Y bindings go nowhere;
    // these route them to the source document. Undo/redo need a focused text
    // editor, so focus hops to the source editor and back to the panel.
    vscode.commands.registerCommand('markdownWorkbench.savePreviewSource', () => {
      if (activePreviewDoc) activePreviewDoc.save();
    }),
    vscode.commands.registerCommand('markdownWorkbench.undoPreviewSource', () => undoRedoInSource('undo')),
    vscode.commands.registerCommand('markdownWorkbench.redoPreviewSource', () => undoRedoInSource('redo'))
  );

  async function undoRedoInSource(command) {
    if (!activePreviewDoc) return;
    const panel = previews.get(activePreviewDoc.uri.toString());
    const open = vscode.window.visibleTextEditors
      .find((e) => e.document.uri.toString() === activePreviewDoc.uri.toString());
    const viewColumn = open ? open.viewColumn
      : (panel && panel.viewColumn) || vscode.ViewColumn.Active;
    await vscode.window.showTextDocument(activePreviewDoc, { viewColumn, preserveFocus: false });
    await vscode.commands.executeCommand(command);
    if (panel) panel.reveal(undefined, false);
  }
}

// Extension root, set in activate; used for the tab icon of all views.
let extensionUri = null;

function checklistIconPath() {
  return {
    light: vscode.Uri.joinPath(extensionUri, 'media', 'checklist-light.svg'),
    dark: vscode.Uri.joinPath(extensionUri, 'media', 'checklist-dark.svg')
  };
}

// Document uri of the currently active checklist custom editor (for
// markdownWorkbench.reopenAsSource when invoked without a uri argument).
let activeCustomDocUri = null;

// Scroll-position handoff between source editor and checklist views:
// pendingInitialScroll carries the editor's top line into a freshly opened
// view; lastKnownTopLine tracks the current top line per document (updated
// from both sync directions) for the way back to the source.
const pendingInitialScroll = new Map(); // uri string -> line
const lastKnownTopLine = new Map();     // uri string -> line

// Resolve the configured view options (content width + minimap behavior).
function configuredViewConfig() {
  const cfg = vscode.workspace.getConfiguration('markdownWorkbench');
  return {
    maxWidth: cfg.get('preview.maxWidth') === 'narrow' ? '72ch' : '980px',
    // Explicit fallbacks: right after an in-place extension update the
    // contributed settings schema may not be active yet and get() would
    // return undefined - which must never disable the minimap.
    minimap: {
      enabled: cfg.get('minimap.enabled', true),
      size: cfg.get('minimap.size', 'proportional'),
      showSlider: cfg.get('minimap.showSlider', 'mouseover'),
      side: cfg.get('minimap.side', 'right')
    }
  };
}

// Fractional top line of an editor, like the built-in preview: line number
// plus how far the viewport top has progressed into that (wrapped) line.
function getVisibleLine(editor) {
  if (!editor.visibleRanges.length) return undefined;
  const firstVisiblePosition = editor.visibleRanges[0].start;
  const lineNumber = firstVisiblePosition.line;
  const line = editor.document.lineAt(lineNumber);
  const progress = firstVisiblePosition.character / (line.text.length + 2);
  return lineNumber + progress;
}

// Reveal a fractional line: the fraction is encoded as a character offset
// into the line, which AtTop positions proportionally (built-in technique).
function scrollEditorToLine(line, editor) {
  line = Math.max(0, line);
  const sourceLine = Math.floor(line);
  if (sourceLine >= editor.document.lineCount) {
    const last = editor.document.lineCount - 1;
    editor.revealRange(new vscode.Range(last, 0, last, 0), vscode.TextEditorRevealType.AtTop);
    return;
  }
  const fraction = line - sourceLine;
  const text = editor.document.lineAt(sourceLine).text;
  const start = Math.floor(fraction * text.length);
  editor.revealRange(
    new vscode.Range(sourceLine, start, sourceLine + 1, 0),
    vscode.TextEditorRevealType.AtTop
  );
}

function captureScrollPosition(uri) {
  const target = uri.toString();
  const editor = vscode.window.visibleTextEditors
    .find((e) => e.document.uri.toString() === target);
  if (editor) {
    const line = getVisibleLine(editor);
    if (line !== undefined) pendingInitialScroll.set(target, line);
  }
}

function revealLastKnownLine(editor) {
  const line = lastKnownTopLine.get(editor.document.uri.toString());
  if (line != null) scrollEditorToLine(line, editor);
}

class ChecklistEditorProvider {
  resolveCustomTextEditor(document, webviewPanel) {
    // Like the built-in "Open as Preview": the tab gets the view's icon and
    // title instead of the plain file icon (preview.ts sets iconPath/title
    // for both its static and dynamic previews).
    webviewPanel.iconPath = checklistIconPath();
    webviewPanel.title = 'Checklist: ' + (document.uri.path.split('/').pop() || 'Untitled');
    activeCustomDocUri = document.uri;
    webviewPanel.onDidChangeViewState((e) => {
      if (e.webviewPanel.active) activeCustomDocUri = document.uri;
    });
    wireWebview(document, webviewPanel, /* closeWithDocument: */ false);
  }
}

// Shared wiring for both the custom editor and the side preview:
// render, document change updates, bidirectional scroll sync, toggles.
function wireWebview(document, webviewPanel, closeWithDocument) {
  webviewPanel.webview.options = { enableScripts: true };
  webviewPanel.webview.html = getWebviewHtml();

  const post = () => {
    webviewPanel.webview.postMessage({
      type: 'render',
      html: md.render(document.getText())
    });
  };

  const subs = [];
  activePosts.add(post);
  subs.push({ dispose: () => activePosts.delete(post) });

  // Re-highlight when the user switches between dark/light themes.
  subs.push(vscode.window.onDidChangeActiveColorTheme(() => post()));

  subs.push(vscode.workspace.onDidChangeTextDocument((e) => {
    if (e.document.uri.toString() === document.uri.toString()) {
      post();
    }
  }));

  const postConfig = () => {
    webviewPanel.webview.postMessage(Object.assign({ type: 'config' }, configuredViewConfig()));
  };
  subs.push(vscode.workspace.onDidChangeConfiguration((e) => {
    if (e.affectsConfiguration('markdownWorkbench')) postConfig();
  }));

  // In preview mode, close the panel when the source document is closed.
  if (closeWithDocument) {
    subs.push(vscode.workspace.onDidCloseTextDocument((doc) => {
      if (doc.uri.toString() === document.uri.toString()) {
        webviewPanel.dispose();
      }
    }));
  }

  // --- Scroll sync (bidirectional, with echo suppression) ---
  let suppressEditorEvents = 0;

  subs.push(vscode.window.onDidChangeTextEditorVisibleRanges((e) => {
    if (e.textEditor.document.uri.toString() !== document.uri.toString()) return;
    const line = getVisibleLine(e.textEditor);
    if (line === undefined) return;
    lastKnownTopLine.set(document.uri.toString(), line);
    if (Date.now() < suppressEditorEvents) return;
    webviewPanel.webview.postMessage({ type: 'scrollTo', line });
  }));

  webviewPanel.onDidDispose(() => subs.forEach((s) => s.dispose()));

  webviewPanel.webview.onDidReceiveMessage((msg) => {
    if (msg.type === 'toggle') {
      applyToggle(document, msg.lines, msg.checked);
    } else if (msg.type === 'toggleCell') {
      applyCellToggle(document, msg.line, msg.idx, msg.checked);
    } else if (msg.type === 'scrolled') {
      // Webview was scrolled by the user -> reveal the same line in any
      // visible text editor of this document. Suppress the resulting
      // visible-range events so they don't bounce back.
      lastKnownTopLine.set(document.uri.toString(), msg.line);
      suppressEditorEvents = Date.now() + 200;
      for (const editor of vscode.window.visibleTextEditors) {
        if (editor.document.uri.toString() === document.uri.toString()) {
          scrollEditorToLine(msg.line, editor);
        }
      }
    } else if (msg.type === 'ready') {
      postConfig(); // before render so the layout is right for the initial scroll
      post();
      // Jump to the position the source editor was scrolled to when the
      // view was opened (the built-in preview does the same). Messages are
      // processed in order, so the render has built the DOM by then.
      const key = document.uri.toString();
      const initialLine = pendingInitialScroll.get(key);
      pendingInitialScroll.delete(key);
      if (initialLine != null && initialLine > 0) {
        webviewPanel.webview.postMessage({ type: 'scrollTo', line: initialLine });
      }
    }
  });
}

// Flip the nth "[ ]"/"[x]" occurrence on a source line (table cells).
// Code spans are blanked out (index-preserving) before counting, because the
// renderer does not convert brackets inside them either - otherwise the
// occurrence indices would drift apart.
function applyCellToggle(document, lineNo, idx, checked) {
  if (lineNo < 0 || lineNo >= document.lineCount) return;
  const text = document.lineAt(lineNo).text;
  const scannable = text.replace(/(`+)[^`]*?\1/g, (m) => ' '.repeat(m.length));
  const re = /\[( |x|X)\]/g;
  let m, i = 0;
  while ((m = re.exec(scannable))) {
    if (i++ === idx) {
      const edit = new vscode.WorkspaceEdit();
      edit.replace(
        document.uri,
        new vscode.Range(lineNo, m.index + 1, lineNo, m.index + 2),
        checked ? 'x' : ' '
      );
      vscode.workspace.applyEdit(edit);
      return;
    }
  }
}

// Flip the single character inside [ ] / [x] on each given line.
// One WorkspaceEdit -> all toggles happen in parallel and form a single undo step.
function applyToggle(document, lines, checked) {
  const edit = new vscode.WorkspaceEdit();
  for (const lineNo of lines) {
    if (lineNo < 0 || lineNo >= document.lineCount) continue;
    const text = document.lineAt(lineNo).text;
    const m = CHECKBOX_RE.exec(text);
    if (!m) continue;
    const bracketContentPos = m[1].length + 1; // position of the char between [ ]
    edit.replace(
      document.uri,
      new vscode.Range(lineNo, bracketContentPos, lineNo, bracketContentPos + 1),
      checked ? 'x' : ' '
    );
  }
  vscode.workspace.applyEdit(edit);
}

// --- Webview -----------------------------------------------------------------

function getWebviewHtml() {
  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
  :root {
    --border: var(--vscode-editorWidget-border, color-mix(in srgb, var(--vscode-editor-foreground) 14%, transparent));
    --muted: color-mix(in srgb, var(--vscode-editor-foreground) 62%, var(--vscode-editor-background));
    --code-bg: var(--vscode-textCodeBlock-background, color-mix(in srgb, var(--vscode-editor-foreground) 7%, var(--vscode-editor-background)));
    --accent: var(--vscode-textLink-foreground, var(--vscode-focusBorder));
  }
  html { scroll-behavior: auto; }
  /* Custom scrollbar - functionally required, not cosmetic: scrollbar
     pseudo-element rules only take effect once ::-webkit-scrollbar itself
     is styled (custom mode). Only then can the native arrow buttons be
     removed, whose height shortened the thumb track at both ends and
     offset it against the full-height minimap rail. Thumb uses the
     editor's scrollbarSlider tokens. */
  html {
    /* VS Code injects scrollbar-color into every webview (@layer
       vscode-default in the webview host); a non-auto scrollbar-color
       disables ALL ::-webkit-scrollbar styling in Chromium - which is why
       the rules below would otherwise be inert and Windows keeps its
       Fluent arrow buttons. Resetting to auto re-enables them; unlayered
       author styles beat the injected layer. */
    scrollbar-color: auto;
    scrollbar-width: auto;
  }
  ::-webkit-scrollbar { width: 14px; height: 14px; }
  ::-webkit-scrollbar-button { display: none; height: 0; }
  ::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
  ::-webkit-scrollbar-thumb { background: var(--vscode-scrollbarSlider-background); }
  ::-webkit-scrollbar-thumb:hover { background: var(--vscode-scrollbarSlider-hoverBackground); }
  ::-webkit-scrollbar-thumb:active { background: var(--vscode-scrollbarSlider-activeBackground); }
  body {
    font-family: var(--vscode-font-family);
    color: var(--vscode-editor-foreground);
    background: var(--vscode-editor-background);
    font-size: 15px;
    line-height: 1.7;
    padding: 1.5em 2em 4em;
    user-select: none;
    -webkit-font-smoothing: antialiased;
  }
  #content { max-width: var(--mc-max-width, 980px); margin: 0 auto; } /* configurable: markdownWorkbench.preview.maxWidth */
  body.has-minimap { padding-right: 104px; }
  body.has-minimap.minimap-left { padding-right: 2em; padding-left: 104px; }
  body.minimap-left #minimap {
    left: 0; right: auto;
    border-left: none; border-right: 1px solid var(--border);
  }
  #minimap.slider-mouseover #minimap-slider { opacity: 0; transition: opacity .12s; }
  #minimap.slider-mouseover:hover #minimap-slider,
  #minimap.slider-mouseover.dragging #minimap-slider { opacity: 1; }

  /* Minimap: scaled clone of the rendered content, editor minimap tokens */
  #minimap {
    position: fixed; top: 0; right: 0; bottom: 0; width: 88px; /* full height: same mapping length as the scrollbar, no drift */
    overflow: hidden; z-index: 5; display: none;
    border-left: 1px solid var(--border);
    background: var(--vscode-editor-background);
    cursor: default; user-select: none;
  }
  body.has-minimap #minimap { display: block; }
  #minimap-content {
    transform-origin: top left; pointer-events: none; will-change: transform;
  }
  #minimap-slider {
    position: absolute; left: 0; right: 0;
    background: var(--vscode-minimapSlider-background);
  }
  #minimap:hover #minimap-slider { background: var(--vscode-minimapSlider-hoverBackground); }
  #minimap.dragging #minimap-slider { background: var(--vscode-minimapSlider-activeBackground); }

  /* Typography */
  h1, h2, h3, h4, h5, h6 {
    font-weight: 650; line-height: 1.25; letter-spacing: -0.015em;
    margin: 1.6em 0 0.5em;
  }
  h1 { font-size: 1.9em; margin-top: 0.4em; padding-bottom: 0.35em; border-bottom: 1px solid var(--border); }
  h2 { font-size: 1.45em; padding-bottom: 0.25em; border-bottom: 1px solid var(--border); }
  h3 { font-size: 1.2em; }
  h4 { font-size: 1.05em; }
  p { margin: 0.6em 0; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  strong { font-weight: 650; }
  hr { border: none; border-top: 1px solid var(--border); margin: 2em 0; }
  img { max-width: 100%; border-radius: 8px; }

  /* Code */
  code {
    font-family: var(--vscode-editor-font-family, ui-monospace, monospace);
    font-size: 0.88em;
    background: var(--code-bg);
    padding: 0.15em 0.4em; border-radius: 4px;
  }
  pre {
    background: var(--code-bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.9em 1.1em;
    overflow-x: auto;
    line-height: 1.55;
  }
  pre code { background: none; padding: 0; font-size: 0.85em; }
  pre.shiki { background: var(--code-bg) !important; }
  pre.shiki code { font-size: 0.85em; }

  /* Blockquote */
  blockquote {
    margin: 0.8em 0; padding: 0.1em 1.1em;
    border-left: 3px solid var(--accent);
    color: var(--muted);
  }
  blockquote > p { margin: 0.4em 0; }

  /* Tables - horizontal hairlines only, sticky header.
     border-collapse: separate is required: with collapse, the borders of a
     position:sticky th scroll away with the body (known Chromium behavior). */
  table {
    border-collapse: separate; border-spacing: 0;
    width: 100%; margin: 1.2em 0; font-size: 0.95em;
  }
  th {
    position: sticky; top: 0; z-index: 2;
    text-align: left; font-weight: 600;
    font-size: 0.76em; text-transform: uppercase; letter-spacing: 0.07em;
    color: var(--muted);
    background: var(--vscode-editor-background);
    padding: 0.55em 0.9em;
    border-bottom: 1px solid var(--border);
  }
  td {
    padding: 0.45em 0.9em;
    border-bottom: 1px solid color-mix(in srgb, var(--vscode-editor-foreground) 8%, transparent);
  }
  tbody tr:nth-child(even) td {
    background: color-mix(in srgb, var(--vscode-editor-foreground) 4%, var(--vscode-editor-background));
  }
  tbody tr:hover td {
    background: color-mix(in srgb, var(--vscode-editor-foreground) 7%, var(--vscode-editor-background));
  }
  td:has(input.cell-task):not(:has(input.cell-task ~ input.cell-task)) {
    cursor: pointer;
  }
  td:has(input.cell-task):not(:has(input.cell-task ~ input.cell-task)):hover {
    background: var(--vscode-list-hoverBackground);
  }
  input.cell-task {
    cursor: pointer; width: 15px; height: 15px; transform: translateY(2px);
    accent-color: var(--vscode-checkbox-selectBackground, var(--vscode-focusBorder));
  }

  /* Lists */
  ul, ol { padding-left: 1.6em; margin: 0.5em 0; }
  li { margin: 0.2em 0; }
  li > ul, li > ol { margin: 0.15em 0; }

  /* Task list items */
  li.task { list-style: none; }
  .task-row {
    display: flex; align-items: baseline; gap: 0.55em;
    margin-left: -1.6em; padding: 0.18em 0.55em;
    border-radius: 6px; cursor: pointer;
  }
  .task-row:hover { background: var(--vscode-list-hoverBackground); }
  li.task.selected > .task-row,
  li.task.selected > p > .task-row {
    background: var(--vscode-list-activeSelectionBackground);
    color: var(--vscode-list-activeSelectionForeground);
  }
  li.task.selected > .task-row a,
  li.task.selected > p > .task-row a { color: inherit; }
  .task-row input[type=checkbox] {
    cursor: pointer; flex: none; transform: translateY(2px);
    width: 15px; height: 15px;
    accent-color: var(--vscode-checkbox-selectBackground, var(--vscode-focusBorder));
  }
  li.task.done > .task-row .task-label,
  li.task.done > p > .task-row .task-label { opacity: 0.55; }
  .task-label { min-width: 0; }
  .task-label p { margin: 0; display: inline; }

  /* Frontmatter property card */
  .frontmatter {
    display: grid; grid-template-columns: max-content 1fr;
    column-gap: 1.6em; row-gap: 0.15em; align-items: baseline;
    border: 1px solid var(--border); border-radius: 10px;
    background: color-mix(in srgb, var(--vscode-editor-foreground) 3%, var(--vscode-editor-background));
    padding: 0.85em 1.2em; margin: 0 0 1.6em;
  }
  .frontmatter .fm-key {
    color: var(--muted); font-size: 0.72em; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.09em;
  }
  .frontmatter .fm-val {
    font-family: var(--vscode-editor-font-family, ui-monospace, monospace);
    font-size: 0.88em; overflow-wrap: anywhere;
  }
  .frontmatter.fm-raw { display: block; }
  .frontmatter.fm-raw pre { border: none; background: none; padding: 0; margin: 0; }

  /* Hint bar */
  .hint {
    position: fixed; bottom: 0; left: 0; right: 0;
    padding: 0.3em 1.5em; font-size: 0.78em; color: var(--muted);
    background: var(--vscode-editor-background);
    border-top: 1px solid var(--border);
  }
  body.has-minimap .hint { right: 88px; }
  body.has-minimap.minimap-left .hint { right: 0; left: 88px; }
</style>
</head>
<body>
<div id="content"></div>
<div id="minimap"><div id="minimap-content"></div><div id="minimap-slider"></div></div>
<div class="hint">Click = toggle &middot; Ctrl+Click = select &middot; Shift+Click = select range &middot; toggle inside selection = toggle all &middot; Esc = clear selection</div>
<script>
  const vscode = acquireVsCodeApi();
  const content = document.getElementById('content');
  let selection = new Set(); // source line numbers of selected tasks
  let anchor = null;         // last clicked task line (for shift-range)

  // --- Fractional scroll sync (algorithms modeled on the built-in preview) ---

  function lineEntries() {
    return [...content.querySelectorAll('[data-line]')].map((el) => ({
      el,
      line: Number(el.dataset.line),
      endLine: el.dataset.lineEnd ? Number(el.dataset.lineEnd) : undefined
    }));
  }

  function absTop(el) { return el.getBoundingClientRect().top + window.scrollY; }

  // Scroll so that the (fractional) source line sits at the viewport top.
  function scrollToSourceLine(line) {
    if (line <= 0) { window.scrollTo(window.scrollX, 0); return; }
    const entries = lineEntries();
    if (!entries.length) return;
    const lineNumber = Math.floor(line);
    let previous = entries[0], next = null;
    for (const entry of entries) {
      if (entry.line === lineNumber) { previous = entry; next = null; break; }
      if (entry.line > lineNumber) { next = entry; break; }
      previous = entry;
    }
    const rect = previous.el.getBoundingClientRect();
    const previousTop = rect.top + window.scrollY;
    let target;
    if (previous.endLine && previous.endLine > previous.line && line < previous.endLine) {
      // Inside a multi-line code block: scroll proportionally through it.
      const progress = (line - previous.line) / (previous.endLine - previous.line);
      target = previousTop + rect.height * progress;
    } else if (next && next.line !== previous.line) {
      const progress = (line - previous.line) / (next.line - previous.line);
      target = previousTop + (absTop(next.el) - previousTop) * progress;
    } else {
      target = previousTop + rect.height * Math.min(1, Math.max(0, line - previous.line));
    }
    window.scrollTo(window.scrollX, target);
  }

  // Fractional source line currently at the viewport top.
  function sourceLineAtTop() {
    const entries = lineEntries();
    if (!entries.length) return null;
    const offset = window.scrollY;
    let previous = null, next = null;
    for (const entry of entries) {
      if (absTop(entry.el) <= offset + 1) { previous = entry; } // later (deeper) entries win
      else if (!next) { next = entry; }
    }
    if (!previous) return 0;
    const rect = previous.el.getBoundingClientRect();
    const previousTop = rect.top + window.scrollY;
    if (previous.endLine && previous.endLine > previous.line && rect.height > 0
        && offset <= previousTop + rect.height) {
      // Inside a multi-line code block.
      const progress = (offset - previousTop) / rect.height;
      return previous.line + progress * (previous.endLine - previous.line);
    }
    if (next) {
      const nextTop = absTop(next.el);
      if (nextTop > previousTop) {
        const progress = (offset - previousTop) / (nextTop - previousTop);
        return previous.line + Math.min(1, Math.max(0, progress)) * (next.line - previous.line);
      }
    }
    if (rect.height > 0) {
      return previous.line + Math.min(1, Math.max(0, (offset - previousTop) / rect.height));
    }
    return previous.line;
  }

  window.addEventListener('message', (e) => {
    if (e.data.type === 'render') {
      content.innerHTML = e.data.html;
      applySelection();
      rebuildMinimap();
    } else if (e.data.type === 'config') {
      document.documentElement.style.setProperty('--mc-max-width', e.data.maxWidth);
      applyMinimapCfg(e.data.minimap); // rebuilds; column width drives the scale
    } else if (e.data.type === 'scrollTo') {
      // Source editor was scrolled -> mirror the fractional position.
      // Suppress the echo from our own scrolling.
      suppressScrollEvents = Date.now() + 200;
      scrollToSourceLine(e.data.line);
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { selection.clear(); applySelection(); }
  });

  function tasks() { return [...content.querySelectorAll('li.task')]; }

  function applySelection() {
    for (const li of tasks()) {
      li.classList.toggle('selected', selection.has(Number(li.dataset.line)));
    }
  }

  // Delegated click handling: innermost task row wins (nested tasks bubble).
  content.addEventListener('click', (e) => {
    if (e.target.closest('a')) return; // let links work normally
    const cell = e.target.closest('input.cell-task');
    if (cell) {
      e.preventDefault();
      // At click time the input has already flipped its live .checked and
      // preventDefault reverts it afterwards - the rendered attribute is
      // the reliable original state.
      vscode.postMessage({
        type: 'toggleCell',
        line: Number(cell.dataset.line),
        idx: Number(cell.dataset.idx),
        checked: !cell.hasAttribute('checked')
      });
      return;
    }
    // Click anywhere in a table cell that holds exactly one checkbox
    // toggles that checkbox.
    const td = e.target.closest('td');
    if (td) {
      const boxes = td.querySelectorAll('input.cell-task');
      if (boxes.length === 1) {
        e.preventDefault();
        const box = boxes[0];
        vscode.postMessage({
          type: 'toggleCell',
          line: Number(box.dataset.line),
          idx: Number(box.dataset.idx),
          checked: !box.hasAttribute('checked')
        });
      }
      return;
    }
    const row = e.target.closest('.task-row');
    if (!row) return;
    e.preventDefault();

    const li = row.closest('li.task');
    const line = Number(li.dataset.line);

    if (e.shiftKey && anchor !== null) {
      // Range select between anchor and clicked task (document order).
      const lines = tasks().map(t => Number(t.dataset.line));
      const a = lines.indexOf(anchor), b = lines.indexOf(line);
      if (a !== -1 && b !== -1) {
        for (let i = Math.min(a, b); i <= Math.max(a, b); i++) selection.add(lines[i]);
      }
      applySelection();
      return;
    }

    if (e.ctrlKey || e.metaKey) {
      selection.has(line) ? selection.delete(line) : selection.add(line);
      anchor = line;
      applySelection();
      return;
    }

    // Plain click: toggle. If the clicked task is part of the selection,
    // toggle the whole selection in parallel to the clicked task's new state.
    anchor = line;
    const newState = li.dataset.checked !== 'true';
    const lines = selection.has(line) ? [...selection] : [line];
    vscode.postMessage({ type: 'toggle', lines, checked: newState });
  });

  // Webview scrolled by the user -> tell the extension which source line is
  // at the top so it can reveal it in the text editor.
  let suppressScrollEvents = 0;
  let scrollPending = false;
  window.addEventListener('scroll', () => {
    if (scrollPending) return;
    scrollPending = true;
    requestAnimationFrame(() => {
      scrollPending = false;
      updateMinimap(); // always - also for editor-driven (suppressed) scrolls
      if (Date.now() < suppressScrollEvents) return;
      const line = sourceLineAtTop();
      if (line !== null) {
        vscode.postMessage({ type: 'scrolled', line: Math.max(0, line) });
      }
    });
  }, { passive: true });

  // --- Minimap: scaled clone, proportional panning, click/drag to navigate ---
  const minimap = document.getElementById('minimap');
  const mapContent = document.getElementById('minimap-content');
  const mapSlider = document.getElementById('minimap-slider');
  let minimapCfg = { enabled: true, size: 'proportional', showSlider: 'mouseover', side: 'right' };
  let mapKx = 0.1;     // horizontal scale: rail width / content width
  let mapSy = 0.1;     // vertical scale of the active size mode
  let mapOffset = 0;   // translateY pan (proportional mode only)

  function applyMinimapCfg(cfg) {
    // Merge over defaults so a missing or partial config can never null
    // out minimapCfg or hide the rail via undefined.
    minimapCfg = Object.assign(
      { enabled: true, size: 'proportional', showSlider: 'mouseover', side: 'right' },
      cfg || {}
    );
    if (minimapCfg.enabled === undefined) minimapCfg.enabled = true;
    cfg = minimapCfg;
    document.body.classList.toggle('minimap-left', cfg.side === 'left');
    minimap.classList.toggle('slider-mouseover', cfg.showSlider === 'mouseover');
    rebuildMinimap();
  }

  function rebuildMinimap() {
    // Visibility first: while the rail is display:none its clientWidth is 0,
    // which would bake a scale of 0 into the clone on the very first render.
    const needed = minimapCfg.enabled
      && document.documentElement.scrollHeight - window.innerHeight > 0;
    document.body.classList.toggle('has-minimap', needed);
    mapContent.innerHTML = '';
    if (!needed) return;
    const clone = content.cloneNode(true);
    for (const input of clone.querySelectorAll('input')) input.disabled = true;
    mapContent.appendChild(clone);
    mapKx = content.clientWidth > 0 ? minimap.clientWidth / content.clientWidth : 0.1;
    mapContent.style.width = content.clientWidth + 'px';
    updateMinimap();
  }

  function updateMinimap() {
    const docH = document.documentElement.scrollHeight;
    const viewH = window.innerHeight;
    const scrollMax = docH - viewH;
    if (!minimapCfg.enabled || scrollMax <= 0) {
      document.body.classList.remove('has-minimap');
      return;
    }
    document.body.classList.add('has-minimap');
    const railH = minimap.clientHeight;
    if (minimapCfg.size === 'fill') {
      // Whole document maps linearly onto the full rail: the slider stays
      // aligned with the real scrollbar, nothing pans.
      mapSy = railH / docH;
      mapOffset = 0;
    } else if (minimapCfg.size === 'fit') {
      // Downscale until the document fits the rail, never stretch.
      mapSy = Math.min(mapKx, railH / docH);
      mapOffset = 0;
    } else { // proportional
      mapSy = mapKx;
      const overflow = Math.max(0, docH * mapKx - railH);
      mapOffset = -(window.scrollY / scrollMax) * overflow;
    }
    mapContent.style.transform =
      'translateY(' + mapOffset + 'px) scale(' + mapKx + ', ' + mapSy + ')';
    mapSlider.style.top = (window.scrollY * mapSy + mapOffset) + 'px';
    mapSlider.style.height = Math.max(12, viewH * mapSy) + 'px';
  }

  function minimapNavigate(clientY) {
    const y = clientY - minimap.getBoundingClientRect().top;
    const docY = (y - mapOffset) / mapSy;
    window.scrollTo(window.scrollX, docY - window.innerHeight / 2);
  }

  minimap.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    minimap.classList.add('dragging');
    minimap.setPointerCapture(e.pointerId);
    minimapNavigate(e.clientY);
  });
  minimap.addEventListener('pointermove', (e) => {
    if (minimap.classList.contains('dragging')) minimapNavigate(e.clientY);
  });
  minimap.addEventListener('pointerup', (e) => {
    minimap.classList.remove('dragging');
    minimap.releasePointerCapture(e.pointerId);
  });
  window.addEventListener('resize', rebuildMinimap, { passive: true });

  vscode.postMessage({ type: 'ready' });
</script>
</body>
</html>`;
}

module.exports = {
  activate,
  deactivate: () => {},
  // Exported for tests only - VS Code calls activate/deactivate.
  _internal: {
    md, CHECKBOX_RE, CELL_BOX_RE,
    taskListPlugin, tableCheckboxPlugin, injectLineNumbers,
    shikiTheme, configuredViewConfig,
    getVisibleLine, scrollEditorToLine,
    applyToggle, applyCellToggle,
    getWebviewHtml
  }
};
