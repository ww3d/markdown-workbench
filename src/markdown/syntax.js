// Markdown source primitives shared by the editor commands, the preview's toggle
// paths and the clipboard diff. Pure and free of the vscode module, so modules
// that must run without the extension host (src/clipboard-diff/) can reuse the
// one definition instead of a copy.

// Matches task list items: "- [ ] text", "* [x] text", "1. [X] text", with
// indentation; the label may be empty. Compound items carry a second list
// marker between the first marker and the box ("1. - [ ] text",
// "- 1. [ ] text") - generically (marker, whitespace) x2, box. Group 1
// spans the whole prefix up to the box, so applyToggle keeps hitting the
// box character exactly. Must classify the same lines as the render-side
// task-list plugin.
const CHECKBOX_RE =
  /^(\s*(?:[-*+]|\d+[.)])\s+(?:(?:[-*+]|\d+[.)])\s+)?)\[( |x|X)\](\s.*)?$/;

/**
 * Index, within the line a CHECKBOX_RE match came from, of the box's content
 * character (the space or x between the brackets). Takes the match array so
 * every call site derives the position from CHECKBOX_RE's own group 1 instead
 * of duplicating the offset.
 */
function checkboxBoxPos(match) {
  return match[1].length + 1;
}

module.exports = {
  CHECKBOX_RE,
  checkboxBoxPos,
};
