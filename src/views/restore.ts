// The host half of the instant stand after a restart (docs/tasks/92-typescript-webview.md,
// REQ-068 to REQ-075): the webview persists its last render with the build id and a key,
// shows it at once on restore and reports both with `ready`; the host compares them with
// its own and skips the render when they match.

import { createHash } from 'node:crypto';
import * as vscode from 'vscode';
import { highlighterState, onHighlighterSettled } from '../render/index.ts';
import type { ReadyMessage } from '../webview/protocol.ts';
import type { RenderEnv } from './config.ts';

// Set by tsdown's `define` from package.json `version` in both bundles (tsdown.config.ts);
// the unit tests put a fixed value on globalThis (tests/helpers/build-id.ts).
declare const BUILD_ID: string;

/**
 * Build id of this extension host bundle; a restored stand of another build is not trusted.
 * Read on use, not at load: a tool that loads the sources unbundled for other parts
 * (the webview smoke builds its skeleton from them) never defines it.
 */
export function hostBuildId(): string {
  return BUILD_ID;
}

/**
 * How long a restored view whose highlighted stand matches waits for a still-loading
 * highlighter before rendering plain code after all: the stand stays on screen meanwhile,
 * the bound only matters when the highlighter never settles.
 */
export const HIGHLIGHTER_WAIT_MS = 5000;

/** Everything a rendered HTML depends on besides the build. */
export interface RenderInputs {
  readonly text: string;
  readonly env: RenderEnv;
  /** `vscode.window.activeColorTheme.kind`: the fence colors follow it. */
  readonly themeKind: number;
  /** Whether fences are highlighted (Shiki ready) or plain. */
  readonly highlighted: boolean;
}

/**
 * The key of a render: SHA-256 (hex, full length) over the render inputs. Full length,
 * because shortening saves nothing next to the persisted HTML and a collision would show
 * a wrong document; the text goes in last and unescaped, after a JSON head of fixed shape.
 */
export function renderKey(inputs: RenderInputs): string {
  return createHash('sha256')
    .update(JSON.stringify([inputs.env, inputs.themeKind, inputs.highlighted]))
    .update('\n')
    .update(inputs.text)
    .digest('hex');
}

/** The key of a render of `text` with `env` under the active color theme. */
export function currentKey(
  text: string,
  env: RenderEnv,
  highlighted: boolean = highlighterState() === 'ready',
): string {
  return renderKey({
    text,
    env,
    themeKind: vscode.window.activeColorTheme.kind,
    highlighted,
  });
}

/** One view's decision whether its restored stand stands in for a host render. */
export interface RestoreGate {
  /** On `ready`: whether the stand it names is kept (then the version went out, no render). */
  keepOnReady(msg: ReadyMessage, text: string, env: RenderEnv): boolean;
  /** Before a render: whether the kept stand still is current (then the version went out). */
  keepRestored(text: string, env: RenderEnv): boolean;
  /** Forget the kept stand and stop a running wait (a reloaded webview, a closed panel). */
  reset(): void;
}

/**
 * The restore gate of one view. `sendVersion` posts the document version; `rerender`
 * posts a render (it asks {@link RestoreGate.keepRestored} first). A highlighted stand
 * whose key only matches once the loading highlighter is ready waits for it: the
 * highlighter start re-posts and finds the stand current; failure or the time bound
 * renders after all.
 */
export function createRestoreGate(
  sendVersion: () => void,
  rerender: () => void,
): RestoreGate {
  // Key of the kept stand, until the first host render replaces it.
  let restoredKey: string | undefined;
  let waitTimer: ReturnType<typeof setTimeout> | undefined;
  let offSettled: (() => void) | undefined;
  const endWait = () => {
    clearTimeout(waitTimer);
    offSettled?.();
    waitTimer = undefined;
    offSettled = undefined;
  };
  const settle = () => {
    endWait();
    rerender();
  };
  const reset = () => {
    restoredKey = undefined;
    endWait();
  };
  return {
    keepOnReady(msg, text, env) {
      if (msg.buildId !== hostBuildId() || msg.key === undefined) return false;
      if (currentKey(text, env) !== msg.key) {
        const loading = highlighterState() === 'loading';
        if (!loading || currentKey(text, env, true) !== msg.key) return false;
        waitTimer = setTimeout(settle, HIGHLIGHTER_WAIT_MS);
        offSettled = onHighlighterSettled(settle);
      }
      restoredKey = msg.key;
      sendVersion();
      return true;
    },
    keepRestored(text, env) {
      if (restoredKey === undefined) return false;
      // During the wait the stand counts as highlighted: the render it waits for will be.
      const ready = highlighterState() === 'ready';
      if (
        currentKey(text, env, ready || offSettled !== undefined) === restoredKey
      ) {
        if (ready) endWait();
        sendVersion();
        return true;
      }
      reset();
      return false;
    },
    reset,
  };
}

/**
 * Render bookkeeping of one wired view, read by the integration suite's restart
 * measurement (P8, REQ-075) through the extension's exports.
 */
export interface ViewStats {
  readonly documentUri: string;
  /** `render` messages posted to this view. */
  renders: number;
  /** Whether the last `ready` brought a restored stand the host kept (no render). */
  restored: boolean;
  /** Milliseconds from the webview's start until its restored content was in the DOM. */
  restoredInMs: number | undefined;
}

/** The stats of every open view; a view removes its entry when its panel closes. */
export const viewStats: Set<ViewStats> = new Set();
