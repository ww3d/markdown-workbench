// Tracks the baseline region of a clipboard diff through edits of its file, so
// "Apply Candidate" replaces the region where it is now, not where it was when
// the diff opened (docs/DECISIONS.md #48). Offsets are character offsets into
// the document; a change is { offset, length, text } as VS Code reports it in
// contentChanges (rangeOffset, rangeLength, text). Pure, no vscode.

/**
 * A region [start, end). `touched` turns true once an edit that is not our own
 * overlaps it, which makes "Apply Candidate" ask before replacing.
 */
function createRegion(start, end) {
  return { start, end, touched: false };
}

/**
 * Moves `region` for one change. An edit before the region shifts it, one after
 * it leaves it, one that overlaps it widens it to cover the edit. An insertion
 * exactly at the start or end of a non-empty region counts as outside, so
 * typing right next to the region does not grow it; an insertion into an empty
 * region counts as inside. `own` marks our own write, which always lands inside
 * the region (a write-through or Apply) and never sets touched.
 */
function applyChange(region, change, own) {
  const { offset, length, text } = change;
  const delta = text.length - length;
  const changeEnd = offset + length;
  const empty = region.start === region.end;
  if (own && offset >= region.start && changeEnd <= region.end) {
    return { ...region, end: region.end + delta };
  }
  if (empty && length === 0 && offset === region.start) {
    return { ...region, end: region.end + delta, touched: true };
  }
  if (changeEnd <= region.start) {
    return { ...region, start: region.start + delta, end: region.end + delta };
  }
  if (offset >= region.end) return region;
  return {
    start: Math.min(region.start, offset),
    end: Math.max(region.end, changeEnd) + delta,
    touched: region.touched || !own,
  };
}

/**
 * Applies all changes of one change event. VS Code reports their offsets
 * against the document before the event, so they are applied from the back.
 */
function applyChanges(region, changes, own) {
  const ordered = [...changes].sort((a, b) => b.offset - a.offset);
  let r = region;
  for (const c of ordered) r = applyChange(r, c, own);
  return r;
}

module.exports = { createRegion, applyChange, applyChanges };
