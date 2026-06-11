// Markdown Workbench - activation entry point. Wires the rendering pipeline
// (render.js), the workbench view machinery (views.js) and the editor
// authoring commands (editing.js) into VS Code, and owns the WebviewPanel
// preview orchestration (one panel per document, mirroring the built-in
// markdown preview). The view itself works as a custom editor
// ("Open as Workbench") and as a side preview.

const vscode = require('vscode');
const { initHighlighter, SHIKI_LANGS } = require('./render');
const {
  setExtensionUri, getActiveCustomDocUri, workbenchIconPath, TAB_TITLE_PREFIX,
  captureScrollPosition, revealLastKnownLine,
  WorkbenchEditorProvider, wireWebview
} = require('./views');

function activate(context) {
  setExtensionUri(context.extensionUri);
  initHighlighter();

  require('./editing').registerEditingCommands(context, SHIKI_LANGS);

  context.subscriptions.push(
    vscode.window.registerCustomEditorProvider(
      'markdownWorkbench.editor',
      new WorkbenchEditorProvider(),
      { webviewOptions: { retainContextWhenHidden: true } }
    )
  );

  // Analog to built-in markdown.reopenAsPreview: replaces the editor tab
  // with the workbench custom editor.
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
      TAB_TITLE_PREFIX + name,
      { viewColumn, preserveFocus: false },
      { enableScripts: true, retainContextWhenHidden: true }
    );
    panel.iconPath = workbenchIconPath();
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
    // Analog to markdown.reopenAsSource: replace the active workbench custom
    // editor with the default text editor.
    vscode.commands.registerCommand('markdownWorkbench.reopenAsSource', async (uri) => {
      const target = uri || getActiveCustomDocUri();
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

module.exports = {
  activate,
  deactivate: () => {}
};
