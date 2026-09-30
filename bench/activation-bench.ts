#!/usr/bin/env node
// Activation benchmark of the extension-host bundle (P7, REQ-053 of docs/tasks/92-typescript-webview.md).
//
// Measures the time from loading dist/extension.cjs to the first `render` message the host
// posts after the webview's `ready`: require of the bundle, `activate`, resolving a custom
// editor and answering `ready`, in the topology of the bundle smoke (dist/ copied to a
// fresh directory under os.tmpdir(), vscode replaced by the test mock). A second value
// runs to the first render with highlighted code (`class="shiki`): Shiki loads in the
// background after activation, so the first value alone does not show what the reader
// waits for to see highlighted code. Every measurement is a fresh Node process, so no run
// profits from an earlier one's module cache; the result is the median of --runs runs
// (21 by default).
//
// It runs dist/, so build first (`pnpm run build`).
//
// Usage:
//   node bench/activation-bench.ts              # 21 isolated runs
//   node bench/activation-bench.ts --runs 5
//   node bench/activation-bench.ts --once       # one run, prints both milliseconds (first, highlighted)

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { layoutPath } from '../eng/layout.ts';
import { install, MockDocument } from '../tests/helpers/vscode-mock.ts';
import { formatStats, stats } from './dist-page.ts';
import { cli } from './harness.ts';

const { flag, opt } = cli(process.argv.slice(2));

/** The document of the run: a heading, a paragraph and a fenced block Shiki highlights. */
const SOURCE = '# T\n\ntext\n\n```js\nconst answer = 42;\n```\n';

/** Gives up on a render that never comes highlighted instead of spinning forever. */
const HIGHLIGHT_TIMEOUT_MS = 30_000;

/** A message the host posted; `html` is set on `render`. */
interface Posted {
  readonly type: string;
  readonly html?: string;
}

/** Milliseconds from the bundle load to the first render and to the first highlighted one. */
interface Timings {
  readonly first: number;
  readonly highlighted: number;
}

/** One measurement in this process. */
async function once(): Promise<Timings> {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-activation-'));
  try {
    fs.cpSync(layoutPath('dist'), tmp, { recursive: true });
    const vscode = install();
    vscode.window.activeColorTheme = { kind: 2 };
    const posted: Posted[] = [];
    let onMessage: (message: { type: string }) => void = () => {};
    const panel = {
      webview: {
        cspSource: 'vscode-webview://bench',
        asWebviewUri: (uri: unknown) => `https://webview/${String(uri)}`,
        set options(_v: unknown) {},
        set html(_v: string) {},
        postMessage: (m: Posted) => posted.push(m),
        onDidReceiveMessage: (f: typeof onMessage) => {
          onMessage = f;
          return { dispose() {} };
        },
      },
      onDidDispose: () => ({ dispose() {} }),
      onDidChangeViewState: () => ({ dispose() {} }),
    };
    const t0 = performance.now();
    const ext: { activate?: (context: object) => void } = createRequire(
      import.meta.url,
    )(path.join(tmp, 'extension.cjs'));
    if (typeof ext.activate !== 'function')
      throw new Error('the bundle does not export activate()');
    ext.activate({ subscriptions: [], extensionUri: 'EXT' });
    const provider = vscode._customEditorProvider;
    if (!provider) throw new Error('the bundle registers no custom editor');
    await provider.resolveCustomTextEditor(new MockDocument(SOURCE), panel);
    onMessage({ type: 'ready' });
    const isRender = (m: Posted) => m.type === 'render';
    const isHighlighted = (m: Posted) =>
      isRender(m) && m.html?.includes('class="shiki') === true;
    let first: number | undefined;
    while (true) {
      const now = performance.now() - t0;
      if (first === undefined && posted.some(isRender)) first = now;
      if (posted.some(isHighlighted))
        return { first: first ?? now, highlighted: now };
      if (now > HIGHLIGHT_TIMEOUT_MS)
        throw new Error('no highlighted render within the timeout');
      await new Promise((r) => setImmediate(r));
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

if (flag('--once')) {
  const { first, highlighted } = await once();
  console.log(`${first.toFixed(2)} ${highlighted.toFixed(2)}`);
  process.exit(0);
}

const runs = Number(opt('--runs', '21'));
const firsts: number[] = [];
const highlights: number[] = [];
for (let i = 0; i < runs; i++) {
  const child = spawnSync(process.execPath, [import.meta.filename, '--once'], {
    encoding: 'utf8',
  });
  const [first, highlighted] = (child.stdout.trim().split('\n').at(-1) ?? '')
    .split(' ')
    .map(Number);
  if (
    child.status !== 0 ||
    first === undefined ||
    highlighted === undefined ||
    Number.isNaN(first) ||
    Number.isNaN(highlighted)
  ) {
    console.error(`run ${i + 1} failed: ${child.stderr || child.stdout}`);
    process.exit(1);
  }
  firsts.push(first);
  highlights.push(highlighted);
}
console.log(
  formatStats(
    'P7 activation (bundle load to first render)',
    stats(firsts),
    'ms',
  ),
);
console.log(
  formatStats(
    'P7 activation (bundle load to first highlighted render)',
    stats(highlights),
    'ms',
  ),
);
