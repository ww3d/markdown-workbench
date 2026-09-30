// The message protocol between the extension host and the webview: one union per
// direction, types only (no runtime code). Both type-check scopes read this file -
// the host (src/views/, src/tables/) and the webview - so neither side can post a
// message the other does not know (docs/DECISIONS.md, D4-1 of #92).

/**
 * Minimap options. Every field is optional: right after an in-place update the
 * settings schema may be inactive, and the webview merges over its own defaults.
 */
export interface MinimapConfig {
  readonly enabled?: boolean;
  readonly size?: 'proportional' | 'fill' | 'fit';
  readonly showSlider?: 'mouseover' | 'always';
  readonly side?: 'right' | 'left';
}

/** Table-of-contents options; optional for the same reason as {@link MinimapConfig}. */
export interface TocConfig {
  readonly enabled?: boolean;
  readonly mode?: 'auto' | 'rail' | 'fab';
}

/** Options of one top bar (breadcrumb or sticky-scroll stack). */
export interface BarConfig {
  readonly enabled?: boolean;
}

/** Host -> webview: the rendered document HTML and the document version it came from. */
export interface RenderMessage {
  readonly type: 'render';
  readonly html: string;
  /** Echoed back by `sortTable`, so a click on an outdated view is dropped. */
  readonly version?: number;
  /**
   * Hash of what the HTML was rendered from (text, render settings, theme kind,
   * highlighter state; src/views/restore.ts). The webview persists it with the HTML and
   * reports it with `ready` after a restore; without it nothing is persisted.
   */
  readonly key?: string;
}

/**
 * Host -> webview: the document version, for a view that keeps its restored render.
 * A message of its own because the version otherwise only rides `render`.
 */
export interface VersionMessage {
  readonly type: 'version';
  readonly version: number;
}

/**
 * Host -> webview: the view options. `documentUri` rides along so the webview can
 * persist it for the panel serializer; the rest is optional as in {@link MinimapConfig}.
 */
export interface ConfigMessage {
  readonly type: 'config';
  readonly documentUri?: string;
  /** Any CSS width; the host sends `980px` or `72ch`, the webview resolves both. */
  readonly maxWidth: string;
  readonly minimap?: MinimapConfig;
  readonly textSelection?: boolean;
  readonly taskBatchSelect?: 'checkbox' | 'row';
  readonly taskRowTextCursor?: boolean;
  readonly toc?: TocConfig;
  readonly breadcrumb?: BarConfig;
  readonly stickyScroll?: BarConfig;
  readonly tables?: { readonly previewSort?: boolean };
}

/** Host -> webview: the source editor scrolled; `line` is a fractional source line. */
export interface ScrollToMessage {
  readonly type: 'scrollTo';
  readonly line: number;
}

/** Every message the host posts to the webview. */
export type HostToWebview =
  | RenderMessage
  | VersionMessage
  | ConfigMessage
  | ScrollToMessage;

/**
 * Webview -> host: the script is loaded and its listeners are registered. After a
 * restore it names the stand it shows; all three fields are absent otherwise.
 */
export interface ReadyMessage {
  readonly type: 'ready';
  /** `BUILD_ID` of the build that persisted the shown stand. */
  readonly buildId?: string;
  /** The `render.key` of the shown stand. */
  readonly key?: string;
  /** Milliseconds from the webview's start until the stand was in the DOM (P8 measurement). */
  readonly restoredInMs?: number;
}

/** Webview -> host: set the list tasks on these source lines to `checked` (one undo step). */
export interface ToggleMessage {
  readonly type: 'toggle';
  readonly lines: readonly number[];
  readonly checked: boolean;
}

/** Webview -> host: set the `idx`-th checkbox on the table row at `line` to `checked`. */
export interface ToggleCellMessage {
  readonly type: 'toggleCell';
  readonly line: number;
  readonly idx: number;
  readonly checked: boolean;
}

/** Webview -> host: the preview scrolled; `line` is the fractional source line at its top. */
export interface ScrolledMessage {
  readonly type: 'scrolled';
  readonly line: number;
}

/**
 * Webview -> host: sort the table whose header sits on `line` by column `col`.
 * `version` is the document version of the last render; undefined before the first
 * one, which the host then rejects as stale.
 */
export interface SortTableMessage {
  readonly type: 'sortTable';
  readonly line: number;
  readonly col: number;
  readonly dir: 'asc' | 'desc';
  readonly version: number | undefined;
}

/** Every message the webview posts to the host. */
export type WebviewToHost =
  | ReadyMessage
  | ToggleMessage
  | ToggleCellMessage
  | ScrolledMessage
  | SortTableMessage;

/**
 * What the webview persists via `setState`; the panel serializer reads `documentUri`.
 * `key`, `html` and `scrollLine` are the stand shown at once after a restart; they are
 * left out when the HTML exceeds the persist bound (src/webview/restore/state.ts).
 */
export interface WebviewState {
  readonly documentUri?: string;
  /** `BUILD_ID` of the build that wrote the state; another build discards the stand. */
  readonly buildId?: string;
  readonly key?: string;
  /** The last rendered HTML as the host sent it. */
  readonly html?: string;
  /** Fractional source line at the top of the view, as `scrolled` reports it. */
  readonly scrollLine?: number;
}
