// Keeps a clipboard diff's pages and its file in step (docs/DECISIONS.md #48):
// - writeThrough: a user edit of the selection page goes into the file region,
//   change by change, so an edit of the page's save actions never follows;
// - mirrorToPage: a user edit of the file region replaces the selection page;
// - mirrorAround: in 'file' shape, a user edit of the file outside the region
//   goes into the candidate's copy of that text, so the diff shows only the
//   clipboard's changes.
// Each diff's syncs run one after another; a refused edit is reported.

const vscode = require('vscode');
const { commonAffixes, splitLines } = require('./lines');

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
    if (regionText !== session.regionText) {
      // The file changed without an event (closed, changed on disk): the
      // region offsets are stale; write nothing and let Apply ask.
      session.region = { ...session.region, touched: true };
      return false;
    }
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
// With the same line count (a save action trims or pads lines, it does not add
// or remove them) each line maps on its own, so several drifted lines do not
// swallow the lines between them; otherwise the texts map around their one
// differing span.
function offsetMap(pageBefore, regionText) {
  if (pageBefore === regionText) return (start) => start;
  const pageLines = splitLines(pageBefore);
  const regionLines = splitLines(regionText);
  if (
    pageLines.length !== regionLines.length ||
    /\r/.test(pageBefore + regionText)
  ) {
    return spanMap(pageBefore, regionText, 0, 0);
  }
  const pageStarts = starts(pageLines);
  const regionStarts = starts(regionLines);
  return (start, end) => {
    const line = lineOf(pageStarts, start);
    if (lineOf(pageStarts, end) !== line) {
      // A change across lines needs every line it touches unchanged.
      for (let l = line; l <= lineOf(pageStarts, end); l++)
        if (pageLines[l] !== regionLines[l]) return null;
      return regionStarts[line] + (start - pageStarts[line]);
    }
    const inLine = spanMap(
      pageLines[line],
      regionLines[line],
      pageStarts[line],
      regionStarts[line],
    );
    return inLine(start, end);
  };
}

// Maps offsets of `a` (starting at `aBase`) into `b` (at `bBase`) around the
// one span where the two differ; null for an edit inside that span.
function spanMap(a, b, aBase, bBase) {
  if (a === b) return (start) => start - aBase + bBase;
  const { prefix, suffix } = commonAffixes(a, b);
  const driftEnd = a.length - suffix;
  const shift = b.length - a.length;
  return (start, end) => {
    const s = start - aBase;
    if (end - aBase <= prefix) return s + bBase;
    if (s >= driftEnd) return s + shift + bBase;
    return null;
  };
}

function starts(lines) {
  const out = [];
  let at = 0;
  for (const l of lines) {
    out.push(at);
    at += l.length + 1;
  }
  return out;
}

// The line of `offset` for line start offsets `lineStarts` (binary search).
function lineOf(lineStarts, offset) {
  let lo = 0;
  let hi = lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= offset) lo = mid;
    else hi = mid - 1;
  }
  return lo;
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
function mirrorAround(sessions, session, before, changes, fileLengthBefore) {
  // The copy around the clipboard part must still be the file around the
  // region; once it is not (an earlier change was left out), mirroring into it
  // would land in the wrong place, so this diff stops mirroring.
  const aligned =
    session.prefix.length === before.start &&
    session.suffix.length === fileLengthBefore - before.end;
  if (!aligned) session.aroundDetached = true;
  if (session.aroundDetached) return Promise.resolve();
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
