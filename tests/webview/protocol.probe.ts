// Type-level probe of the message protocol (REQ-040 of docs/tasks/92-typescript-webview.md).
// `pnpm run typecheck` checks this file (tests scope); nothing runs or bundles it. A message
// outside the unions is a compile error in either direction - and should a union ever widen
// to accept one of these, its directive goes unused and the typecheck fails (TS2578).
import type {
  HostToWebview,
  WebviewToHost,
} from '../../src/webview/protocol.ts';

// @ts-expect-error - the host posts no such message
export const unknownToWebview: HostToWebview = { type: 'bogus' };

// @ts-expect-error - the webview posts no such message
export const unknownToHost: WebviewToHost = { type: 'bogus', line: 1 };

// @ts-expect-error - a known type still needs its fields: scrollTo carries the line
export const incompleteToWebview: HostToWebview = { type: 'scrollTo' };

// @ts-expect-error - a known type with a field of the wrong type
export const mistypedToHost: WebviewToHost = { type: 'scrolled', line: '3' };
