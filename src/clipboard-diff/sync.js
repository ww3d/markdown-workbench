// Keeps a clipboard diff's pages and its file in step (docs/DECISIONS.md #48):
// - writeThrough: a user edit of the selection page goes into the file region,
//   change by change, so an edit of the page's save actions never follows;
// - mirrorToPage: a user edit of the file region replaces the selection page;
// - mirrorAround: in 'file' shape, a user edit of the file outside the region
//   goes into the candidate's copy of that text, so the diff shows only the
//   clipboard's changes.
// Each diff's syncs run one after another; a refused edit is reported.

const vscode = require('vscode');
const { commonAffixes } = require('./lines');

// Runs `task` after the diff's earlier syncs; a failure is reported, not thrown.
function enqueue(sessions, session, task) {
  session.syncChain = (session.syncChain || Promise.resolve()).then(task).then(
    (ok) => {
      if (ok === false) sessions.warnSyncFailed();
    },
    () => sessions.warnSyncFailed(),
  );
  return session.syncChain;
}

/**
 * Applies the page's `changes` (offsets into `pageBefore`, the page text before
 * the edit) to the file region. Where the page drifted from the region (a save
 * action changed the page only), offsets are mapped around the drifted span;
 * an edit inside that span cannot be mapped and is reported instead.
 */
function writeThrough(sessions, session, changes, pageBefore) {
  return enqueue(sessions, session, async () => {
    const file = await sessions.fileOf(session);
    if (!file) return false;
    const regionText = file.getText(sessions.rangeOf(file, session));
    const map = offsetMap(pageBefore, regionText);
    const edit = new vscode.WorkspaceEdit();
    for (const c of changes) {
      const at = map(c.offset, c.offset + c.length);
      if (at === null) return false;
      const start = session.region.start + at;
      edit.replace(
        file.uri,
        new vscode.Range(
          file.positionAt(start),
          file.positionAt(start + c.length),
        ),
        c.text,
      );
    }
    return sessions.applyOwn(session, 'file', edit);
  });
}

// Maps an offset range of `pageBefore` to its offset in `regionText`, or null.
function offsetMap(pageBefore, regionText) {
  if (pageBefore === regionText) return (start) => start;
  const { prefix, suffix } = commonAffixes(pageBefore, regionText);
  const driftEnd = pageBefore.length - suffix;
  const shift = regionText.length - pageBefore.length;
  return (start, end) => {
    if (end <= prefix) return start;
    if (start >= driftEnd) return start + shift;
    return null;
  };
}

/** Sets the selection page to `text` (the region changed in the file). */
function mirrorToPage(sessions, session, text) {
  return enqueue(sessions, session, () => {
    const page = vscode.workspace.textDocuments.find(
      (d) => d.uri.toString() === session.baselineUri.toString(),
    );
    if (!page) {
      sessions.store.put(session.baselineUri, text);
      session.pageText = text;
      return true;
    }
    if (page.getText() === text) return true;
    const edit = new vscode.WorkspaceEdit();
    edit.replace(
      page.uri,
      new vscode.Range(
        page.positionAt(0),
        page.positionAt(page.getText().length),
      ),
      text,
    );
    return sessions.applyOwn(session, 'page', edit);
  });
}

/**
 * Carries file `changes` outside the region (`before`, the region before the
 * event) into the candidate's copy of the text around the clipboard part.
 * Changes inside the region are left out; so is everything when the text
 * around the clipboard part was edited in the candidate itself.
 */
function mirrorAround(sessions, session, before, changes) {
  const outside = [...changes]
    .sort((a, b) => b.offset - a.offset)
    .filter((c) => {
      const end = c.offset + c.length;
      const intoEmpty =
        before.start === before.end &&
        c.length === 0 &&
        c.offset === before.start;
      return !intoEmpty && (end <= before.start || c.offset >= before.end);
    });
  if (!outside.length) return Promise.resolve();
  return enqueue(sessions, session, async () => {
    const doc = vscode.workspace.textDocuments.find(
      (d) => d.uri.toString() === session.candidateUri.toString(),
    );
    const text = doc
      ? doc.getText()
      : sessions.store.textOf(session.candidateUri);
    if (text === undefined || sessions.clipOf(session, text) === undefined)
      return true;
    let { prefix, suffix } = session;
    const suffixStart = text.length - suffix.length;
    const edits = [];
    for (const c of outside) {
      if (c.offset + c.length <= before.start) {
        prefix =
          prefix.slice(0, c.offset) +
          c.text +
          prefix.slice(c.offset + c.length);
        edits.push({ at: c.offset, length: c.length, text: c.text });
      } else {
        const rel = c.offset - before.end;
        suffix = suffix.slice(0, rel) + c.text + suffix.slice(rel + c.length);
        edits.push({ at: suffixStart + rel, length: c.length, text: c.text });
      }
    }
    let ok = true;
    if (doc) {
      const edit = new vscode.WorkspaceEdit();
      for (const e of edits) {
        edit.replace(
          doc.uri,
          new vscode.Range(
            doc.positionAt(e.at),
            doc.positionAt(e.at + e.length),
          ),
          e.text,
        );
      }
      ok = await sessions.applyOwn(session, 'page', edit);
    } else {
      const sorted = [...edits].sort((a, b) => b.at - a.at);
      let next = text;
      for (const e of sorted)
        next = next.slice(0, e.at) + e.text + next.slice(e.at + e.length);
      sessions.store.put(session.candidateUri, next);
    }
    if (ok) {
      session.prefix = prefix;
      session.suffix = suffix;
    }
    return ok;
  });
}

module.exports = {
  writeThrough,
  mirrorToPage,
  mirrorAround,
  _internal: { offsetMap },
};
