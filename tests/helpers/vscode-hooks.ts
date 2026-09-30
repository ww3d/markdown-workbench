// Module hooks that stand the `vscode` mock in for the real API under ESM. Registered on first
// import (tests/helpers/setup.ts via `node --import`; vscode-mock.ts imports it too, for the bundle smoke).
//
// - `vscode` resolves to a virtual module per installed mock, generated with one named export per
//   key of that mock, so `import * as vscode from 'vscode'` sees the mock installed at load time.
// - Every src/ URL carries `?gen=N`, inherited from the importing URL (else the current
//   generation): `loadFresh` bumps the generation and gets a fresh src/ graph with its own module
//   state, bound to the mock installed at that moment.

import {
  type LoadHookSync,
  type ResolveHookSync,
  registerHooks,
} from 'node:module';

/** A `vscode` mock as `install()` creates it: a plain object of API members. */
export type VscodeMock = Record<string, unknown>;

const SRC_URL = new URL('../../src/', import.meta.url).href;
const MOCK_URL = 'mock:vscode';
const IDENTIFIER = /^[A-Za-z_$][\w$]*$/;

const mocks: VscodeMock[] = [];
let generation = 0;

/** Makes `mock` the one every later `import 'vscode'` resolves to. */
export function registerMock(mock: VscodeMock): void {
  mocks.push(mock);
}

/** Starts a new src/ generation and returns its number (for a fresh `?gen=N` import). */
export function nextGeneration(): number {
  generation += 1;
  return generation;
}

/** The mock registered as number `id`; the generated `vscode` modules read their exports here. */
export function mockAt(id: number): VscodeMock {
  const mock = mocks[id];
  if (!mock) throw new Error(`no vscode mock #${id}`);
  return mock;
}

function generationOf(url: string | undefined): string {
  const gen = url?.startsWith('file:')
    ? new URL(url).searchParams.get('gen')
    : null;
  return gen ?? String(generation);
}

// The source of `mock:vscode?gen=N&mock=M`. Without an installed mock the import fails loudly,
// as loading `vscode` did outside the extension host.
function mockSource(url: string): string {
  const id = Number(new URL(url).searchParams.get('mock'));
  const mock = mocks[id];
  if (!mock) {
    return "throw new Error('vscode mock not installed: call install() from tests/helpers/vscode-mock.ts first');";
  }
  const names = Object.keys(mock).filter((k) => IDENTIFIER.test(k));
  return [
    `import { mockAt } from ${JSON.stringify(import.meta.url)};`,
    `const mock = mockAt(${id});`,
    ...names.map((k) => `export const ${k} = mock[${JSON.stringify(k)}];`),
  ].join('\n');
}

// A new generation re-imports the same files: resolution and source are the same in every
// generation, only the module instances differ. Kept per file (URL without `?gen`), so a fresh
// graph skips the file-system walk and the read and pays only for compiling and evaluating.
type Resolved = ReturnType<Parameters<ResolveHookSync>[2]>;
type Loaded = ReturnType<Parameters<LoadHookSync>[2]>;
const resolvedFromSrc = new Map<string, Resolved>();
const loadedFromSrc = new Map<string, Loaded>();

const withoutQuery = (url: string): string => url.split('?', 1)[0] ?? url;

function resolveOnce(
  specifier: string,
  context: Parameters<ResolveHookSync>[1],
  nextResolve: Parameters<ResolveHookSync>[2],
): Resolved {
  const parent = context.parentURL;
  if (!parent?.startsWith(SRC_URL)) return nextResolve(specifier, context);
  const key = `${withoutQuery(parent)}\0${specifier}\0${context.conditions.join()}`;
  let resolved = resolvedFromSrc.get(key);
  if (!resolved) {
    resolved = nextResolve(specifier, context);
    resolvedFromSrc.set(key, resolved);
  }
  return { ...resolved, shortCircuit: true };
}

function loadOnce(
  url: string,
  context: Parameters<LoadHookSync>[1],
  nextLoad: Parameters<LoadHookSync>[2],
): Loaded {
  const file = withoutQuery(url);
  let loaded = loadedFromSrc.get(file);
  if (!loaded) {
    loaded = nextLoad(url, context);
    loadedFromSrc.set(file, loaded);
  }
  return { ...loaded, shortCircuit: true };
}

registerHooks({
  resolve(specifier, context, nextResolve) {
    const gen = generationOf(context.parentURL);
    if (specifier === 'vscode') {
      return {
        url: `${MOCK_URL}?gen=${gen}&mock=${mocks.length - 1}`,
        format: 'module',
        shortCircuit: true,
      };
    }
    const resolved = resolveOnce(specifier, context, nextResolve);
    if (resolved.url.startsWith(SRC_URL) && !resolved.url.includes('?')) {
      return { ...resolved, url: `${resolved.url}?gen=${gen}` };
    }
    return resolved;
  },
  load(url, context, nextLoad) {
    if (url.startsWith(`${MOCK_URL}?`)) {
      return { format: 'module', source: mockSource(url), shortCircuit: true };
    }
    if (url.startsWith(SRC_URL)) return loadOnce(url, context, nextLoad);
    return nextLoad(url, context);
  },
});
