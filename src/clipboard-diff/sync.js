// Keeps a clipboard diff's pages and its file in step (docs/DECISIONS.md #48):
// - writeThrough: a user edit of the selection page goes into the file region,
//   change by change, so an edit of the page's save actions never follows;
// - mirrorToPage: a user edit of the file region replaces the selection page;
// - mirrorAround: in 'file' shape, a user edit of the file outside the region
//   goes into the candidate's copy of that text, so the diff shows only the
//   clipboard's changes;
// - reconcileSaved: a user edit of the selection page that arrived while a save
//   ran (after its write) goes into the file after all; a focused page that then
//   still holds text the file lacks is reported.
// Each diff's syncs run one after another; a refused edit is reported.

import * as vscode from 'vscode';
import { commonAffixes, splitLines } from './lines.js';

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
  return enqueue(sessions, session, () =>
    writeChanges(sessions, session, changes, pageBefore),
  );
}

// The queued part of writeThrough; resolves to false when nothing could be written.
async function writeChanges(sessions, session, changes, pageBefore) {
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
  return enqueue(sessions, session, () =>
    carryAround(sessions, session, before, outside, fileLengthBefore),
  );
}

// The queued part of mirrorAround. The alignment check runs here, not in the
// event handler: only once the earlier events' jobs ran are prefix/suffix the
// file around the region as of this event.
async function carryAround(sessions, session, before, outside, lengthBefore) {
  // Once the copy around the clipboard part is not the file around the region
  // (an earlier change was left out), mirroring would land in the wrong place.
  const aligned =
    session.prefix.length === before.start &&
    session.suffix.length === lengthBefore - before.end;
  if (!aligned) session.aroundDetached = true;
  if (session.aroundDetached) return true;
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
        prefix.slice(0, c.offset) + c.text + prefix.slice(c.offset + c.length);
      edits.push({ at: c.offset, length: c.length, text: c.text });
    } else {
      const rel = c.offset - before.end;
      suffix = suffix.slice(0, rel) + c.text + suffix.slice(rel + c.length);
      edits.push({ at: suffixStart + rel, length: c.length, text: c.text });
    }
  }
  const ok = await editCandidate(sessions, session, doc, text, edits);
  if (ok) {
    session.prefix = prefix;
    session.suffix = suffix;
  }
  return ok;
}

// Applies `edits` ({ at, length, text } offsets into `text`) to the candidate:
// its open document, or its stored text.
function editCandidate(sessions, session, doc, text, edits) {
  if (doc) {
    const edit = new vscode.WorkspaceEdit();
    for (const e of edits) {
      edit.replace(
        doc.uri,
        new vscode.Range(doc.positionAt(e.at), doc.positionAt(e.at + e.length)),
        e.text,
      );
    }
    return sessions.applyOwn(session, 'page', edit);
  }
  let next = text;
  for (const e of [...edits].sort((a, b) => b.at - a.at))
    next = next.slice(0, e.at) + e.text + next.slice(e.at + e.length);
  sessions.store.put(session.candidateUri, next);
  return Promise.resolve(true);
}

/**
 * Called after a save whose edits counted as save actions (saving.js). Save
 * actions run before the write, so the text as written (the store) holds them;
 * what the selection page holds beyond it came after the write and is the
 * user's: it goes into the file instead of being dropped. What the user typed
 * before the write cannot be told from a save action; when the page is focused
 * by then (typing needs focus), a page that differs from the file region in
 * more than whitespace is reported.
 */
function reconcileSaved(sessions, doc, focused = false) {
  const s = sessions.forUri(doc.uri);
  if (s?.shape !== 'page' || s.baselineUri.toString() !== doc.uri.toString())
    return Promise.resolve();
  const written = sessions.store.textOf(doc.uri);
  const text = doc.getText();
  // A page equal to the region lacks nothing in the file (e.g. a mirror edit).
  const lacking =
    written !== undefined && text !== written && text !== s.regionText;
  if (!lacking && !focused) return Promise.resolve();
  return enqueue(sessions, s, async () => {
    if (lacking) {
      const { prefix, suffix } = commonAffixes(written, text);
      const change = {
        offset: prefix,
        length: written.length - prefix - suffix,
        text: text.slice(prefix, text.length - suffix),
      };
      if (!(await writeChanges(sessions, s, [change], written))) return false;
    }
    // Queued, so the region holds every earlier page edit by now.
    return (
      !focused || withoutSpaceEnds(text) === withoutSpaceEnds(s.regionText)
    );
  });
}

// `text` without trailing blanks on its lines and trailing line breaks - what
// trim-whitespace and final-newline save actions change.
function withoutSpaceEnds(text) {
  return text.replace(/[ \t]+(?=\r?\n|$)/g, '').replace(/(\r?\n)+$/, '');
}

export { writeThrough, mirrorToPage, mirrorAround, reconcileSaved };
// Exported for tests only.
export const _internal = { offsetMap };
