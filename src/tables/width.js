// Display width of table cell text in monospace columns: what an editor font
// shows, not what String.length counts. Pure, no vscode import.

import { eastAsianWidth } from 'get-east-asian-width';

// One segmenter for the whole process; building one per call is the expensive part.
const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

// Printable ASCII only: width equals length, no segmentation needed (the common case).
const ASCII_RE = /^[\x20-\x7e]*$/;
// An emoji grapheme renders two columns: emoji presentation, a VS16 (U+FE0F)
// request, or a regional-indicator flag pair.
const EMOJI_RE = /\p{Emoji_Presentation}|\u{FE0F}|\p{Regional_Indicator}/u;
// Graphemes that take no column: a lone combining mark, a control or format
// character (zero-width space, joiners, bidi marks) - but not a tab, which takes
// space in the editor (counted as one column).
const ZERO_RE = /^(?!\t)[\p{M}\p{Cc}\p{Cf}]/u;

/**
 * Width of one grapheme cluster: 2 for East-Asian wide/fullwidth and emoji, 0 for
 * combining marks and control/format characters, 1 otherwise. East-Asian
 * ambiguous counts 1, or 2 with `ambiguousWide`.
 * @param {string} g
 * @param {boolean} ambiguousWide
 * @returns {number}
 */
function graphemeWidth(g, ambiguousWide) {
  if (ZERO_RE.test(g)) return 0;
  if (EMOJI_RE.test(g)) return 2;
  return eastAsianWidth(g.codePointAt(0), { ambiguousAsWide: ambiguousWide });
}

/**
 * Display width of a string, measured per grapheme (`Intl.Segmenter`).
 * @param {string} text
 * @param {boolean} [ambiguousWide] true for `tables.ambiguousWidth: "wide"`
 * @returns {number}
 */
function displayWidth(text, ambiguousWide = false) {
  if (ASCII_RE.test(text)) return text.length;
  let w = 0;
  for (const { segment } of graphemes.segment(text))
    w += graphemeWidth(segment, ambiguousWide);
  return w;
}

export { displayWidth, graphemes };
