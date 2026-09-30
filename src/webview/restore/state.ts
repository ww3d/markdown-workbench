// What the webview persists via setState (REQ-041/042, REQ-068): the document URI the
// panel serializer reads, plus the last render as the stand a restart shows at once -
// the host's HTML and key, the scroll position and the build id. The HTML goes in only
// up to MAX_RESTORE_HTML_CHARS. A render or a scroll only schedules the write; it runs
// once the view has been quiet for STATE_SAVE_QUIET_MS, so a render burst or a scroll
// costs one setState, not one per frame.

import { flushFoldMetrics } from '../folding/refresh.ts';
import { vscodeApi } from '../host.ts';
import type { WebviewState } from '../protocol.ts';
import { sourceLineAtTop } from '../scroll-sync/line-metrics.ts';

// Set by tsdown's `define` from package.json `version` (tsdown.config.ts); the unit tests
// put a fixed value on globalThis (tests/setup.ts).
declare const BUILD_ID: string;

/**
 * Upper bound of the persisted HTML in characters (512 KiB, inclusive). VS Code documents no limit
 * for setState, but each call sends the whole state to the host as JSON and a restore
 * embeds it URL-encoded in the webview's start script; the bound holds large documents
 * with their Shiki spans without bloating the workspace state (docs/tasks/92, REQ-041).
 */
export const MAX_RESTORE_HTML_CHARS = 512 * 1024;

/** Quiet time after the last render or scroll before the state is written. */
export const STATE_SAVE_QUIET_MS = 250;

/** A persisted stand of this build that can be shown before the host's first render. */
export interface SavedStand {
  readonly buildId: string;
  readonly key: string;
  readonly html: string;
  readonly scrollLine: number | undefined;
}

let documentUri: string | undefined;
let html: string | undefined;
let key: string | undefined;
let lastActivity = 0;
let saveTimer: ReturnType<typeof setTimeout> | null = null;

function currentState(): WebviewState {
  if (html === undefined || key === undefined) {
    return { documentUri, buildId: BUILD_ID };
  }
  if (html.length > MAX_RESTORE_HTML_CHARS) {
    return { documentUri, buildId: BUILD_ID };
  }
  flushFoldMetrics(); // a fold may have left the tops stale; never persist from those
  const line = sourceLineAtTop();
  return {
    documentUri,
    buildId: BUILD_ID,
    key,
    html,
    scrollLine: line === null ? undefined : Math.max(0, line),
  };
}

function writeState(): void {
  vscodeApi().setState(currentState());
}

// Runs STATE_SAVE_QUIET_MS after the first activity of a burst; while activity went on
// meanwhile it re-arms for the rest of the quiet time instead of writing.
function saveWhenQuiet(): void {
  const quietFor = Date.now() - lastActivity;
  if (quietFor < STATE_SAVE_QUIET_MS) {
    saveTimer = setTimeout(saveWhenQuiet, STATE_SAVE_QUIET_MS - quietFor);
    return;
  }
  saveTimer = null;
  writeState();
}

/**
 * Note a change of what the state holds (a render, a scroll): the write follows once
 * the view is quiet. Allocation-free on the hot path: a timestamp, and a timer only for
 * the first call of a burst.
 */
export function scheduleStateSave(): void {
  lastActivity = Date.now();
  if (saveTimer === null)
    saveTimer = setTimeout(saveWhenQuiet, STATE_SAVE_QUIET_MS);
}

/** Keep the document URI for the panel serializer; written at once, as it is rare. */
export function persistDocumentUri(uri: string): void {
  documentUri = uri;
  writeState();
}

/** Keep the HTML and key of a render for the next restore (written once quiet). */
export function persistRender(
  renderedHtml: string,
  renderKey: string | undefined,
): void {
  html = renderedHtml;
  key = renderKey;
  scheduleStateSave();
}

/**
 * Read the persisted state at start. The document URI is kept whatever else it holds;
 * a stand of this build is returned, one of another build is discarded (REQ-073).
 */
export function takeSavedStand(): SavedStand | undefined {
  const saved = vscodeApi().getState();
  documentUri = saved?.documentUri;
  if (saved?.html === undefined || saved.key === undefined) return undefined;
  if (saved.buildId !== BUILD_ID) {
    writeState(); // drop the stand of the other build, keep the document URI
    return undefined;
  }
  return {
    buildId: saved.buildId,
    key: saved.key,
    html: saved.html,
    scrollLine: saved.scrollLine,
  };
}
