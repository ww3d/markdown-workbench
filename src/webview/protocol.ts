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
export type HostToWebview = RenderMessage | ConfigMessage | ScrollToMessage;

/** Webview -> host: the script is loaded and its listeners are registered. */
export interface ReadyMessage {
  readonly type: 'ready';
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

/** What the webview persists via `setState`; the panel serializer reads `documentUri`. */
export interface WebviewState {
  readonly documentUri?: string;
}
