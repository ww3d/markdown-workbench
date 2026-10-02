// Type-level probe of the webview scope (tsconfig.webview.json): no Node types, so a webview
// module cannot use Node globals or built-ins. `pnpm run typecheck` checks this file in the
// webview scope only (tsconfig.tests.json leaves it out); should the scope ever gain Node
// types, the directives go unused and the typecheck fails (TS2578).

// @ts-expect-error - the webview runs in a browser: no Node global
export const noProcess = process;

// @ts-expect-error - the webview runs in a browser: no Node built-in
export type NoNodeModule = typeof import('node:fs');
