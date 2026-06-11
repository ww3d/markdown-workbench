// Workbench view machinery shared by both entry modes (WebviewPanel preview
// and CustomTextEditorProvider): the webview HTML skeleton (loading the
// webview script/style as real media assets), render + bidirectional
// scroll-sync wiring, configuration resolution, and the surgical toggle paths
// that mirror every checkbox change into the source file.

const vscode = require('vscode');
const crypto = require('crypto');
const { md, activePosts } = require('./render');

// Matches task list items: "- [ ] text", "* [x] text", "1. [X] text", with indentation.
const CHECKBOX_RE = /^(\s*(?:[-*+]|\d+[.)])\s+)\[( |x|X)\](\s.*)?$/;

// Tab/panel title prefix for every workbench view (single constant: both the
// preview panel and the custom editor read it, so it is defined once).
const TAB_TITLE_PREFIX = 'Workbench: ';

// Extension root, set in activate; used for the tab icon and the webview
// media assets (script/style URIs, localResourceRoots).
let extensionUri = null;
function setExtensionUri(uri) { extensionUri = uri; }

function workbenchIconPath() {
  return {
    light: vscode.Uri.joinPath(extensionUri, 'media', 'checklist-light.svg'),
    dark: vscode.Uri.joinPath(extensionUri, 'media', 'checklist-dark.svg')
  };
}

// Document uri of the currently active workbench custom editor (for
// markdownWorkbench.reopenAsSource when invoked without a uri argument).
let activeCustomDocUri = null;
function getActiveCustomDocUri() { return activeCustomDocUri; }

// Scroll-position handoff between source editor and workbench views:
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

class WorkbenchEditorProvider {
  resolveCustomTextEditor(document, webviewPanel) {
    // Like the built-in "Open as Preview": the tab gets the view's icon and
    // title instead of the plain file icon (preview.ts sets iconPath/title
    // for both its static and dynamic previews).
    webviewPanel.iconPath = workbenchIconPath();
    webviewPanel.title = TAB_TITLE_PREFIX + (document.uri.path.split('/').pop() || 'Untitled');
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
  webviewPanel.webview.options = {
    enableScripts: true,
    // The webview script/style ship as media assets; scope the webview to
    // that folder so asWebviewUri can load them.
    localResourceRoots: [vscode.Uri.joinPath(extensionUri, 'media')]
  };
  webviewPanel.webview.html = getWebviewHtml(webviewPanel.webview);

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

// --- Webview HTML skeleton ---------------------------------------------------

// The webview runs untrusted-looking but author-owned content. The script is
// gated by a per-load nonce; styles/images come from the webview origin only.
function makeNonce() {
  return crypto.randomBytes(16).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 24);
}

// Slim skeleton that loads the real media/webview.css and media/webview.js via
// webview.asWebviewUri. Both files ship in the vsix and run in the webview, so
// they are not part of the extension-host bundle.
function getWebviewHtml(webview) {
  const nonce = makeNonce();
  const scriptUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'webview.js'));
  const styleUri = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, 'media', 'webview.css'));
  const csp = [
    "default-src 'none'",
    // http: is kept alongside https:/data: so remote images in user markdown
    // keep loading as they did before (the inline view had no CSP at all).
    'img-src ' + webview.cspSource + ' https: http: data:',
    // 'unsafe-inline' is required for styles: Shiki emits per-token colors as
    // inline style="color:..." attributes in the rendered HTML (injected via
    // innerHTML), and the rendered markdown may carry inline styles too. The
    // script stays nonce-gated; only styles are relaxed.
    'style-src ' + webview.cspSource + " 'unsafe-inline'",
    "script-src 'nonce-" + nonce + "'"
  ].join('; ');
  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="Content-Security-Policy" content="${csp}">
<link rel="stylesheet" href="${styleUri}">
</head>
<body>
<div id="content"></div>
<div id="minimap"><div id="minimap-content"></div><div id="minimap-slider"></div></div>
<div class="hint">Click = toggle &middot; Ctrl+Click = select &middot; Shift+Click = select range &middot; toggle inside selection = toggle all &middot; Esc = clear selection</div>
<script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
}

module.exports = {
  CHECKBOX_RE, TAB_TITLE_PREFIX,
  setExtensionUri, getActiveCustomDocUri,
  workbenchIconPath, configuredViewConfig,
  captureScrollPosition, revealLastKnownLine, scrollEditorToLine,
  WorkbenchEditorProvider, wireWebview,
  applyToggle, applyCellToggle, getWebviewHtml,
  // Exported for tests only.
  _internal: {
    CHECKBOX_RE, configuredViewConfig,
    getVisibleLine, scrollEditorToLine,
    applyToggle, applyCellToggle, getWebviewHtml
  }
};
