import * as vscode from 'vscode';

// Render env passed to markdown-it: the custom-marker preview options. Read per
// render so a settings change takes effect on the next re-render (the
// markdownWorkbench config-change listener re-renders via post(), so these apply
// live without reopening the view).
function configuredRenderEnv() {
  const cfg = vscode.workspace.getConfiguration('markdownWorkbench');
  return {
    markdownWorkbench: {
      renderExtraMarkers: cfg.get('lists.renderExtraMarkers', false),
      extraMarkers: cfg.get('lists.extraMarkers', []),
    },
  };
}

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
      side: cfg.get('minimap.side', 'right'),
    },
    // Preview readability knobs (#25 follow-up). Same defensive defaults as
    // the minimap: the contributed schema may be inactive right after an
    // in-place update, and the defaults must reproduce the #25 behavior.
    textSelection: cfg.get('preview.textSelection', true),
    taskBatchSelect: cfg.get('preview.taskBatchSelect', 'checkbox'),
    taskRowTextCursor: cfg.get('preview.taskRowTextCursor', false),
    // Table-of-contents navigation (#32). Same defensive defaults - undefined
    // (schema not yet active after an in-place update) must never disable the
    // TOC or force a mode; the webview merges over its own defaults too. The
    // rail side is derived in the webview from minimap.side (opposite side),
    // so it is deliberately not part of this config.
    toc: {
      enabled: cfg.get('toc.enabled', true),
      mode: cfg.get('toc.mode', 'auto'),
    },
    // Top-bar navigation (#33): the breadcrumb and the sticky-scroll stack, both
    // consumers of the same scroll-spy. Independent toggles, same defensive
    // defaults as the minimap/TOC - undefined (schema not yet active after an
    // in-place update) must never disable a bar; the webview merges over its own
    // defaults too.
    breadcrumb: {
      enabled: cfg.get('breadcrumb.enabled', true),
    },
    stickyScroll: {
      enabled: cfg.get('stickyScroll.enabled', true),
    },
    // The header sort button (docs/DECISIONS.md #49); same defensive default.
    tables: {
      previewSort: cfg.get('tables.previewSort', true),
    },
  };
}

export { configuredRenderEnv, configuredViewConfig };
