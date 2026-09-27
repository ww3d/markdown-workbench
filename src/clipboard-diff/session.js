// The live clipboard diffs: which file and region each one compares, its
// virtual pages, the region tracking through file edits, the immediate save of
// every page change and the release of a diff's memory once no tab shows it
// (docs/DECISIONS.md #48). A diff is one of two shapes:
// - 'page': the baseline is a virtual "(Selection)" page holding the region's
//   text, kept as a two-way mirror of the region in the file;
// - 'file': the baseline is the live file itself, and the candidate is the file
//   with the region replaced (whole file, or a section the anchor found).

const vscode = require('vscode');
const { SCHEME } = require('./store');
const { createRegion, applyChanges } = require('./region');
const { PageSaver } = require('./saving');
const sync = require('./sync');

let nextId = 1;

/** File-name stem and extension of a document URI ("notes", ".md"). */
function nameParts(uri) {
  const base = uri.path.split('/').pop() || 'Untitled';
  const dot = base.lastIndexOf('.');
  return dot > 0
    ? { stem: base.slice(0, dot), ext: base.slice(dot) }
    : { stem: base, ext: '' };
}

/** The changes of a change event as { offset, length, text }. */
function changesOf(e) {
  return e.contentChanges.map((c) => ({
    offset: c.rangeOffset,
    length: c.rangeLength,
    text: c.text,
  }));
}

class ClipboardDiffSessions {
  constructor(store) {
    this.store = store;
    this.saver = new PageSaver();
    this.byCandidate = new Map(); // candidate uri string -> session
    this.onChanged = () => {}; // set by the binding: (session) => void
  }

  /**
   * Registers a new diff. `region` is [start, end) in character offsets of the
   * file; `prefix`/`suffix` are the file text around it in 'file' shape. The
   * session stays `opening` (never released) until the binding shows it.
   * Returns the session with its page URIs, their content already stored.
   */
  create({
    document,
    shape,
    region,
    clip,
    prefix = '',
    suffix = '',
    role = 'Selection',
  }) {
    const id = nextId++;
    const { stem, ext } = nameParts(document.uri);
    const page = (label) =>
      vscode.Uri.from({
        scheme: SCHEME,
        path: `/${id}/${stem} (${label})${ext}`,
      });
    const candidateUri = page('Candidate');
    const baselineUri = shape === 'page' ? page(role) : document.uri;
    const session = {
      id,
      shape,
      fileUri: document.uri,
      languageId: document.languageId,
      candidateUri,
      baselineUri,
      region: createRegion(region[0], region[1]),
      regionText: '',
      prefix,
      suffix,
      rawClip: clip,
      lastSetClip: clip,
      styled: false,
      opening: true,
      ownFileEdits: 0,
      ownPageEdits: 0,
    };
    session.regionText = document.getText(this.rangeOf(document, session));
    session.pageText = session.regionText; // the selection page as last seen
    this.store.put(candidateUri, prefix + clip + suffix);
    if (shape === 'page') this.store.put(baselineUri, session.regionText);
    this.byCandidate.set(candidateUri.toString(), session);
    return session;
  }

  /** The session whose candidate or page is `uri`, if any. */
  forUri(uri) {
    const key = uri.toString();
    for (const s of this.byCandidate.values()) {
      if (
        s.candidateUri.toString() === key ||
        (s.shape === 'page' && s.baselineUri.toString() === key)
      )
        return s;
    }
    return undefined;
  }

  /** The session of the active tab (a diff with one of its pages), if any. */
  forActiveTab() {
    const input = vscode.window.tabGroups.activeTabGroup?.activeTab?.input;
    if (input instanceof vscode.TabInputTextDiff)
      return this.forUri(input.modified) || this.forUri(input.original);
    if (input instanceof vscode.TabInputText) return this.forUri(input.uri);
    return undefined;
  }

  all() {
    return [...this.byCandidate.values()];
  }

  /** The session's region as a Range of `document`. */
  rangeOf(document, session) {
    return new vscode.Range(
      document.positionAt(session.region.start),
      document.positionAt(session.region.end),
    );
  }

  /** The candidate's clipboard part: its text without the file around it. */
  clipOf(session, candidateText) {
    if (session.shape === 'page') return candidateText;
    const { prefix, suffix } = session;
    if (candidateText.length < prefix.length + suffix.length) return undefined;
    if (!candidateText.startsWith(prefix) || !candidateText.endsWith(suffix))
      return undefined;
    return candidateText.slice(
      prefix.length,
      candidateText.length - suffix.length,
    );
  }

  /**
   * The open baseline document of `session`, or undefined when an untitled
   * baseline was closed - opening its URI again would give a new, empty one.
   */
  fileOf(session) {
    const key = session.fileUri.toString();
    const open = vscode.workspace.textDocuments.find(
      (d) => d.uri.toString() === key,
    );
    if (open || session.fileUri.scheme === 'untitled')
      return Promise.resolve(open);
    return vscode.workspace.openTextDocument(session.fileUri);
  }

  /** Runs `edit` as our own edit of the file or a page; resolves to its result. */
  async applyOwn(session, which, edit) {
    const key = which === 'file' ? 'ownFileEdits' : 'ownPageEdits';
    session[key]++;
    try {
      return await vscode.workspace.applyEdit(edit);
    } finally {
      session[key]--;
    }
  }

  /**
   * Document change hook. Saves every dirty page at once (saving.js); tracks
   * regions through file edits; mirrors the selection page and its region
   * both ways and, in 'file' shape, the file around the region into the
   * candidate (sync.js).
   */
  handleChange(e) {
    const doc = e.document;
    if (doc.uri.scheme === SCHEME) {
      this.handlePageChange(e);
      return;
    }
    if (!this.byCandidate.size || !e.contentChanges.length) return;
    const key = doc.uri.toString();
    for (const s of this.byCandidate.values()) {
      if (s.fileUri.toString() !== key) continue;
      const own = s.ownFileEdits > 0;
      const before = s.region;
      const changes = changesOf(e);
      s.region = applyChanges(before, changes, own);
      if (own) s.regionText = doc.getText(this.rangeOf(doc, s));
      else if (s.shape === 'page')
        sync.mirrorToPage(this, s, doc.getText(this.rangeOf(doc, s)));
      else sync.mirrorAround(this, s, before, changes);
      this.onChanged(s);
    }
  }

  handlePageChange(e) {
    const doc = e.document;
    const s = this.forUri(doc.uri);
    // A save's own edits (save actions) arrive while it runs; never pass them on.
    const saveAction = this.saver.isSaving(doc);
    if (doc.isDirty && !saveAction)
      this.saver.save(doc, () => this.warnSaveFailed());
    if (!s || !e.contentChanges.length) return;
    const isBaselinePage =
      s.shape === 'page' && doc.uri.toString() === s.baselineUri.toString();
    if (isBaselinePage) {
      const pageBefore = s.pageText;
      s.pageText = doc.getText();
      if (s.ownPageEdits === 0 && !saveAction)
        sync.writeThrough(this, s, changesOf(e), pageBefore);
    }
    this.onChanged(s);
  }

  // Deliberately without the error text: it may quote the page content.
  warnSaveFailed() {
    vscode.window.showWarningMessage(
      'Markdown Workbench could not keep a clipboard diff page in memory. VS Code may back up its unsaved text.',
    );
  }

  warnSyncFailed() {
    vscode.window.showWarningMessage(
      'Markdown Workbench could not sync a clipboard diff page with its file.',
    );
  }

  /**
   * Frees every diff whose candidate no tab shows any more, and every stored
   * page no tab shows and no diff owns (e.g. a "Save As" copy). A diff still
   * opening is kept. Returns the released sessions.
   */
  releaseClosed() {
    const shown = new Set();
    for (const group of vscode.window.tabGroups.all) {
      for (const tab of group.tabs) {
        const input = tab.input;
        if (input instanceof vscode.TabInputTextDiff) {
          shown.add(input.original.toString());
          shown.add(input.modified.toString());
        } else if (input instanceof vscode.TabInputText) {
          shown.add(input.uri.toString());
        }
      }
    }
    const released = [];
    for (const [key, s] of this.byCandidate) {
      if (s.opening || shown.has(key)) continue;
      this.byCandidate.delete(key);
      this.store.release(s.candidateUri);
      if (s.shape === 'page') this.store.release(s.baselineUri);
      released.push(s);
    }
    const owned = new Set();
    for (const s of this.byCandidate.values())
      owned.add(s.candidateUri.path).add(s.baselineUri.path);
    for (const path of [...this.store.files.keys()]) {
      const uri = vscode.Uri.from({ scheme: SCHEME, path });
      if (!owned.has(path) && !shown.has(uri.toString()))
        this.store.release(uri);
    }
    return released;
  }

  /** Frees everything (deactivate). */
  dispose() {
    this.byCandidate.clear();
    this.store.clear();
  }
}

module.exports = { ClipboardDiffSessions, nameParts };
