// Entry of the bench-only webview bundle (never shipped; bench/harness.ts builds it into
// the layout's tmp folder). It starts the webview exactly like src/webview/main.ts - it IS
// main.ts - and hands the drivers the internals they measure on globalThis.__mw, which the
// shipped IIFE keeps private. Type-checked in the webview scope (DOM, no Node types).

import '../src/webview/main.ts';
import morphdom from 'morphdom';
import { convertInternalAnchors } from '../src/webview/anchors/anchors.ts';
import { injectFoldToggles } from '../src/webview/folding/sections.ts';
import { content } from '../src/webview/page/content.ts';
import { scrollSpy } from '../src/webview/scroll-spy/spy.ts';
import { lineMetrics } from '../src/webview/scroll-sync/line-metrics.ts';

Object.assign(globalThis, {
  __mw: {
    content,
    lineMetrics,
    scrollSpy,
    convertInternalAnchors,
    injectFoldToggles,
    morphdom,
  },
});
