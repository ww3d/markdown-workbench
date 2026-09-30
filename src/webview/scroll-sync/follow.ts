// Editor -> webview: follow the source editor's fractional top line.

import { flushFoldMetrics } from '../folding/refresh.ts';
import { absTop } from '../page/content.ts';
import { type LineEntry, lineMetrics } from './line-metrics.ts';

/** Scroll so that the (fractional) source line sits at the viewport top. */
export function scrollToSourceLine(line: number): void {
  if (line <= 0) {
    window.scrollTo(window.scrollX, 0);
    return;
  }
  flushFoldMetrics(); // editor-driven scroll: the fold's tops must be current first
  const entries = lineMetrics.entries;
  const first = entries[0];
  if (!first) return;
  const lineNumber = Math.floor(line);
  let previous = first;
  let next: LineEntry | null = null;
  for (const entry of entries) {
    if (entry.line === lineNumber) {
      previous = entry;
      next = null;
      break;
    }
    if (entry.line > lineNumber) {
      next = entry;
      break;
    }
    previous = entry;
  }
  const rect = previous.el.getBoundingClientRect();
  const previousTop = rect.top + window.scrollY;
  let target: number;
  if (
    previous.endLine &&
    previous.endLine > previous.line &&
    line < previous.endLine
  ) {
    // Inside a multi-line code block: scroll proportionally through it.
    const progress =
      (line - previous.line) / (previous.endLine - previous.line);
    target = previousTop + rect.height * progress;
  } else if (next && next.line !== previous.line) {
    const progress = (line - previous.line) / (next.line - previous.line);
    target = previousTop + (absTop(next.el) - previousTop) * progress;
  } else {
    target =
      previousTop +
      rect.height * Math.min(1, Math.max(0, line - previous.line));
  }
  window.scrollTo(window.scrollX, target);
}
