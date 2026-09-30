// Type-level probe of the extension-host scope (tsconfig.host.json): no DOM library, so a host
// module cannot touch `document`. `pnpm run typecheck` checks this file in the host scope only
// (tsconfig.tests.json leaves it out); should the scope ever gain the DOM lib, the directive
// goes unused and the typecheck fails (TS2578).

// @ts-expect-error - the extension host has no DOM
export const noDocument = document;
