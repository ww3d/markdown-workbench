// The config message: apply the view options to every part of the webview.

import { vscodeApi } from '../host.ts';
import { applyMinimapCfg } from '../minimap/minimap.ts';
import type { ConfigMessage } from '../protocol.ts';
import { scrollSpy } from '../scroll-spy/spy.ts';
import {
  refreshScrollingHeads,
  updateStickyHeads,
} from '../tables/sticky-head.ts';
import { applyPreviewCfg } from '../tasks/preview-config.ts';
import {
  applyTocCfg,
  resolveCssWidthPx,
  setTocMaxWidthPx,
  updateTocLayout,
} from '../toc/layout.ts';
import {
  applyTopBarsCfg,
  publishHeadingScrollMargins,
} from '../top-bars/bars.ts';

/** Apply a config message: width, readability, minimap, TOC and top-bar options. */
export function onConfig(msg: ConfigMessage): void {
  // Persist the document URI so VS Code can restore this preview panel after a
  // restart (read back by the panel serializer in src/extension.js).
  if (msg.documentUri) vscodeApi().setState({ documentUri: msg.documentUri });
  document.documentElement.style.setProperty('--mc-max-width', msg.maxWidth);
  applyPreviewCfg(msg);
  applyMinimapCfg(msg.minimap); // rebuilds; column width drives the scale
  applyTocCfg(msg.toc);
  applyTopBarsCfg(msg.breadcrumb, msg.stickyScroll);
  setTocMaxWidthPx(resolveCssWidthPx(msg.maxWidth)); // rail-fit threshold input
  updateTocLayout(); // side (opposite the minimap) + rail/fab decision
  // Apply the new top-bar flags at once (force-emit), like updateTocLayout for
  // the TOC: scrollSpy.update() alone emits only when the active heading
  // changes, so a live enabled-toggle would otherwise wait for the next scroll.
  scrollSpy.update(true);
  publishHeadingScrollMargins(); // enabling/disabling a bar changes each heading's dock height
  refreshScrollingHeads(); // width/bar changes shift the cached table tops
  updateStickyHeads();
}
