// Session list of the clipboard texts the extension itself read, for "Compare
// with Earlier Clipboard" (docs/DECISIONS.md #48). Memory only: nothing is
// persisted, and the clipboard is never polled. Pure, no vscode.

/** Most entries the list keeps; the oldest drops out first. */
const MAX_HISTORY_ENTRIES = 10;
/** Largest entry in UTF-8 bytes; a larger text is dropped, never truncated. */
const MAX_ENTRY_BYTES = 1024 * 1024;
/** Length of the one-line preview a picker shows for an entry. */
const PREVIEW_LENGTH = 60;

class ClipboardHistory {
  constructor() {
    this.entries = [];
  }

  /**
   * Records `text` as the newest entry. An identical earlier entry moves to the
   * front instead of appearing twice. Returns false when the text is empty or
   * larger than MAX_ENTRY_BYTES and was therefore not recorded.
   */
  add(text, time = Date.now()) {
    if (!text || Buffer.byteLength(text, 'utf8') > MAX_ENTRY_BYTES)
      return false;
    const i = this.entries.findIndex((e) => e.text === text);
    if (i !== -1) this.entries.splice(i, 1);
    this.entries.unshift({ text, time });
    if (this.entries.length > MAX_HISTORY_ENTRIES)
      this.entries.length = MAX_HISTORY_ENTRIES;
    return true;
  }

  /** The entries, newest first. */
  list() {
    return this.entries.slice();
  }

  clear() {
    this.entries = [];
  }
}

/** First non-blank line of `text`, whitespace collapsed, cut to PREVIEW_LENGTH. */
function previewOf(text) {
  const line = (text.split(/\r\n|\r|\n/).find((l) => l.trim()) || '')
    .trim()
    .replace(/\s+/g, ' ');
  return line.length > PREVIEW_LENGTH
    ? `${line.slice(0, PREVIEW_LENGTH - 1)}…`
    : line;
}

export {
  ClipboardHistory,
  previewOf,
  MAX_HISTORY_ENTRIES,
  MAX_ENTRY_BYTES,
  PREVIEW_LENGTH,
};
