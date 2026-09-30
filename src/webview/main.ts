// Workbench webview entry: renders the markdown HTML pushed from the host,
// handles checkbox toggles and selection, bidirectional fractional scroll
// sync, the minimap, the TOC and the top bars. Runs in the webview (browser)
// context, not the extension host; bundled as dist/webview.js (+ .css) and
// loaded by getWebviewHtml (src/views/html.ts) through one nonce'd <script>.
//
// The stylesheets are imported first, in cascade order: the modules import each
// other in an order that does not follow the cascade, and the first import of a
// stylesheet fixes its place in the bundle. Every module imports its own
// stylesheet as well. Then the listeners are registered in a fixed order - the
// order matters for same-type listeners and for the two scroll-spy subscribers
// (TOC before top bars) - then a persisted stand is restored and `ready` goes out last.

import './page/page.css';
import './minimap/minimap.css';
import './render/document.css';
import './tables/tables.css';
import './render/lists.css';
import './tasks/tasks.css';
import './render/frontmatter.css';
import './toc/rail.css';
import './page/codicon.css';
import './toc/tree.css';
import './folding/folding.css';
import './toc/fab.css';
import './top-bars/top-bars.css';
import './page/hint.css';
import { vscodeApi } from './host.ts';
import { installMinimapDrag } from './minimap/drag.ts';
import { installFocusSuppression } from './page/focus.ts';
import {
  installResizeObserver,
  installViewportResize,
} from './page/viewport.ts';
import { installMessages } from './render/messages.ts';
import { type RestoredStand, restoreSavedStand } from './restore/restore.ts';
import { scrollSpy } from './scroll-spy/spy.ts';
import { installScrollReport } from './scroll-sync/report.ts';
import { installContentClick, installEscape } from './tasks/listeners.ts';
import { installTocOverlay } from './toc/layout.ts';
import { installTocClick } from './toc/toggle.ts';
import { applyTocActive } from './toc/tree.ts';
import { installStickyClick, updateTopBars } from './top-bars/bars.ts';
import {
  installBreadcrumbClicks,
  installOutsideClose,
} from './top-bars/dropdown.ts';
import { publishTopBarVars } from './top-bars/geometry.ts';

vscodeApi(); // acquire the VS Code API at load, as a single call per webview allows
installMessages();
installEscape();
installContentClick();
installScrollReport();
installMinimapDrag();
installViewportResize();
scrollSpy.onChange(applyTocActive);
installTocClick();
installTocOverlay();
installResizeObserver();
installBreadcrumbClicks();
installStickyClick();
installOutsideClose();
installFocusSuppression();
scrollSpy.onChange(updateTopBars);
publishTopBarVars(); // constant CSS vars, written once - never during a scroll

// The persisted stand goes on screen before the host's first render; ready names it. A stand
// that fails to restore is logged and left out, so the host renders instead.
let restored: RestoredStand = {};
try {
  restored = restoreSavedStand();
} catch (err) {
  console.error('markdown-workbench: restoring the saved view failed', err);
}
vscodeApi().postMessage({ type: 'ready', ...restored });
