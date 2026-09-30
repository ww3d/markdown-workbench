#!/usr/bin/env node
// Activation benchmark of the extension-host bundle (P7, REQ-053 of docs/tasks/92-typescript-webview.md).
//
// Measures the time from loading dist/extension.cjs to the first `render` message the host
// posts after the webview's `ready`: require of the bundle, `activate`, resolving a custom
// editor and answering `ready`, in the topology of the bundle smoke (dist/ copied to a
// fresh directory under os.tmpdir(), vscode replaced by the test mock). Every measurement
// is a fresh Node process, so no run profits from an earlier one's module cache; the
// result is the median of --runs runs (21 by default).
//
// It runs dist/, so build first (`pnpm run build`).
//
// Usage:
//   node bench/activation-bench.ts              # 21 isolated runs
//   node bench/activation-bench.ts --runs 5
//   node bench/activation-bench.ts --once       # one run, prints the milliseconds only

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

/** One measurement in this process: milliseconds from the bundle load to the first render. */
async function once(): Promise<number> {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-activation-'));
  try {
    fs.cpSync(layoutPath('dist'), tmp, { recursive: true });
    const vscode = install();
    vscode.window.activeColorTheme = { kind: 2 };
    const posted: { type: string }[] = [];
    let onMessage: (message: { type: string }) => void = () => {};
    const panel = {
      webview: {
        cspSource: 'vscode-webview://bench',
        asWebviewUri: (uri: unknown) => `https://webview/${String(uri)}`,
        set options(_v: unknown) {},
        set html(_v: string) {},
        postMessage: (m: { type: string }) => posted.push(m),
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
    await provider.resolveCustomTextEditor(
      new MockDocument('# T\n\ntext\n'),
      panel,
    );
    onMessage({ type: 'ready' });
    while (!posted.some((m) => m.type === 'render'))
      await new Promise((r) => setImmediate(r));
    return performance.now() - t0;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

if (flag('--once')) {
  console.log((await once()).toFixed(2));
  process.exit(0);
}

const runs = Number(opt('--runs', '21'));
const times: number[] = [];
for (let i = 0; i < runs; i++) {
  const child = spawnSync(process.execPath, [import.meta.filename, '--once'], {
    encoding: 'utf8',
  });
  const value = Number(child.stdout.trim().split('\n').at(-1));
  if (child.status !== 0 || Number.isNaN(value)) {
    console.error(`run ${i + 1} failed: ${child.stderr || child.stdout}`);
    process.exit(1);
  }
  times.push(value);
}
console.log(
  formatStats(
    'P7 activation (bundle load to first render)',
    stats(times),
    'ms',
  ),
);
