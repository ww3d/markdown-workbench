const vscode = require('vscode');
const { md, activePosts } = require('../render');
const {
  TAB_TITLE_PREFIX,
  getExtensionUri,
  workbenchIconPath,
} = require('./identity');
const { configuredRenderEnv, configuredViewConfig } = require('./config');
const {
  pendingInitialScroll,
  lastKnownTopLine,
  lastRevealedLine,
  lastPostedScrollTo,
  SYNC_LINE_DELTA,
  getVisibleLine,
  scrollEditorToLine,
} = require('./scroll-sync');
const { applyToggle, applyCellToggle } = require('./toggles');
const { getWebviewHtml } = require('./html');

// Document uri of the currently active workbench custom editor (for
// markdownWorkbench.reopenAsSource when invoked without a uri argument).
let activeCustomDocUri = null;
function getActiveCustomDocUri() {
  return activeCustomDocUri;
}

class WorkbenchEditorProvider {
  resolveCustomTextEditor(document, webviewPanel) {
    // Like the built-in "Open as Preview": the tab gets the view's icon and
    // title instead of the plain file icon (preview.ts sets iconPath/title
    // for both its static and dynamic previews).
    webviewPanel.iconPath = workbenchIconPath();
    webviewPanel.title =
      TAB_TITLE_PREFIX + (document.uri.path.split('/').pop() || 'Untitled');
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
    localResourceRoots: [vscode.Uri.joinPath(getExtensionUri(), 'media')],
  };
  webviewPanel.webview.html = getWebviewHtml(webviewPanel.webview);

  const post = () => {
    webviewPanel.webview.postMessage({
      type: 'render',
      html: md.render(document.getText(), configuredRenderEnv()),
    });
  };

  const subs = [];
  activePosts.add(post);
  subs.push({ dispose: () => activePosts.delete(post) });

  // Re-highlight when the user switches between dark/light themes.
  subs.push(vscode.window.onDidChangeActiveColorTheme(() => post()));

  subs.push(
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (e.document.uri.toString() === document.uri.toString()) {
        post();
      }
    }),
  );

  const postConfig = () => {
    // documentUri rides the config message so the webview can persist it via
    // setState; the preview panel serializer reads it back to restore the panel
    // after a VS Code restart (the custom editor restores without it).
    webviewPanel.webview.postMessage(
      Object.assign(
        { type: 'config', documentUri: document.uri.toString() },
        configuredViewConfig(),
      ),
    );
  };
  subs.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('markdownWorkbench')) {
        postConfig();
        post(); // render-relevant settings (renderExtraMarkers/extraMarkers) apply live
      }
    }),
  );

  // In preview mode, close the panel when the source document is closed.
  if (closeWithDocument) {
    subs.push(
      vscode.workspace.onDidCloseTextDocument((doc) => {
        if (doc.uri.toString() === document.uri.toString()) {
          webviewPanel.dispose();
        }
      }),
    );
  }

  // --- Scroll sync (bidirectional, with echo suppression) ---
  let suppressEditorEvents = 0;

  subs.push(
    vscode.window.onDidChangeTextEditorVisibleRanges((e) => {
      if (e.textEditor.document.uri.toString() !== document.uri.toString())
        return;
      const line = getVisibleLine(e.textEditor);
      if (line === undefined) return;
      const key = document.uri.toString();
      lastKnownTopLine.set(key, line);
      if (Date.now() < suppressEditorEvents) return;
      const prev = lastPostedScrollTo.get(key);
      if (prev !== undefined && Math.abs(line - prev) < SYNC_LINE_DELTA) return; // sub-threshold: skip
      lastPostedScrollTo.set(key, line);
      webviewPanel.webview.postMessage({ type: 'scrollTo', line });
    }),
  );

  webviewPanel.onDidDispose(() => {
    for (const s of subs) s.dispose();
  });

  webviewPanel.webview.onDidReceiveMessage((msg) => {
    if (msg.type === 'toggle') {
      applyToggle(document, msg.lines, msg.checked);
    } else if (msg.type === 'toggleCell') {
      applyCellToggle(document, msg.line, msg.idx, msg.checked);
    } else if (msg.type === 'scrolled') {
      // Webview was scrolled by the user -> reveal the same line in any
      // visible text editor of this document. Suppress the resulting
      // visible-range events so they don't bounce back. The reveal itself is
      // delta-gated so a sub-line change does not call revealRange again
      // (suppression + lastKnownTopLine still update every message).
      const key = document.uri.toString();
      lastKnownTopLine.set(key, msg.line);
      suppressEditorEvents = Date.now() + 200;
      const prev = lastRevealedLine.get(key);
      if (prev !== undefined && Math.abs(msg.line - prev) < SYNC_LINE_DELTA)
        return;
      lastRevealedLine.set(key, msg.line);
      for (const editor of vscode.window.visibleTextEditors) {
        if (editor.document.uri.toString() === key) {
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
        webviewPanel.webview.postMessage({
          type: 'scrollTo',
          line: initialLine,
        });
      }
    }
  });
}

module.exports = {
  WorkbenchEditorProvider,
  wireWebview,
  getActiveCustomDocUri,
};
