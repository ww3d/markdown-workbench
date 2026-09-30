// The host's messages to the webview, dispatched by type.

import type { HostToWebview } from '../protocol.ts';
import { scrollToSourceLine } from '../scroll-sync/follow.ts';
import { suppressScrollEventsUntil } from '../scroll-sync/report.ts';
import { setDocVersion } from '../tables/sort.ts';
import { onConfig } from './config.ts';
import { onRender } from './render.ts';

/** Register the window message listener that dispatches the host's messages. */
export function installMessages(): void {
  window.addEventListener('message', (e: MessageEvent<HostToWebview>) => {
    const msg = e.data;
    if (msg.type === 'render') {
      onRender(msg);
    } else if (msg.type === 'version') {
      setDocVersion(msg.version); // the restored render stays; sortTable echoes this version
    } else if (msg.type === 'config') {
      onConfig(msg);
    } else if (msg.type === 'scrollTo') {
      // Source editor was scrolled -> mirror the fractional position.
      // Suppress the echo from our own scrolling.
      suppressScrollEventsUntil(Date.now() + 200);
      scrollToSourceLine(msg.line);
    }
  });
}
