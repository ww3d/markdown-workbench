// Shared headless-Chromium harness for the bench scripts.
//
// Builds the webview the way the extension ships it - the same sources, bundler and
// minify settings as dist/webview.{js,css} - into a bench-only bundle that also hands
// the drivers its internals on globalThis.__mw (bench/webview-internals.ts), loads it
// into a VS-Code-like skeleton, launches a Chromium you already have, drives it over
// the Chrome DevTools Protocol (Node's built-in WebSocket + fetch, no npm dependency)
// and prints whatever the page reports into its #prof element.
//
// A bench script supplies only its driver: the document to render and the
// measurement loop. Everything below is identical for every bench.

import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { build } from 'tsdown';
import { layoutPath } from '../eng/layout.ts';

const repo = path.resolve(import.meta.dirname, '..');

/** The platform facts {@link chromeCandidates} reads, so a test can give it any platform. */
interface ChromeEnv {
  readonly platform: NodeJS.Platform;
  readonly env: Readonly<Record<string, string | undefined>>;
  /** The entries of a directory; none for one that does not exist. */
  readonly readdir: (dir: string) => readonly string[];
}

/**
 * The places a Chromium may stand, best first: the Playwright cache (PLAYWRIGHT_BROWSERS_PATH, on
 * Windows by default %LOCALAPPDATA%\ms-playwright), then the usual install paths of the platform.
 */
function chromeCandidates({ platform, env, readdir }: ChromeEnv): string[] {
  const win = platform === 'win32';
  const cands: string[] = [];
  const pw =
    env.PLAYWRIGHT_BROWSERS_PATH ||
    (win && env.LOCALAPPDATA
      ? path.win32.join(env.LOCALAPPDATA, 'ms-playwright')
      : undefined);
  // The platform's own separator, whatever machine runs this (the tests give it any platform).
  const join = win ? path.win32.join : path.posix.join;
  for (const d of pw ? readdir(pw) : []) {
    if (!d.startsWith('chromium')) continue;
    if (win)
      cands.push(
        join(pw ?? '', d, 'chrome-win64', 'chrome.exe'),
        join(pw ?? '', d, 'chrome-win', 'chrome.exe'),
      );
    else cands.push(join(pw ?? '', d, 'chrome-linux', 'chrome'));
  }
  if (win) {
    for (const root of [
      env.PROGRAMFILES,
      env['PROGRAMFILES(X86)'],
      env.LOCALAPPDATA,
    ])
      if (root)
        cands.push(join(root, 'Google', 'Chrome', 'Application', 'chrome.exe'));
  } else {
    cands.push(
      '/usr/bin/google-chrome',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    );
  }
  return cands;
}

/**
 * Locate a Chromium: CHROME_BIN, else the first of {@link chromeCandidates} that exists.
 * Nothing is installed.
 */
function findChrome(): string | undefined {
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN))
    return process.env.CHROME_BIN;
  return chromeCandidates({
    platform: process.platform,
    env: process.env,
    readdir: (dir) => {
      try {
        return fs.readdirSync(dir);
      } catch {
        return [];
      }
    },
  }).find((c) => {
    try {
      return fs.existsSync(c);
    } catch {
      return false;
    }
  });
}

/**
 * Delete a Chromium profile after its browser has exited. On Windows a helper process of the
 * browser can still hold a file for a moment (EPERM/EBUSY), so the delete is retried.
 */
function removeProfile(dir: string): void {
  fs.rmSync(dir, {
    recursive: true,
    force: true,
    maxRetries: 10,
    retryDelay: 200,
  });
}

// Representative dark-theme values for the --vscode-* custom properties the
// stylesheet reads (VS Code injects these into a real webview).
const THEME = `--vscode-editor-background:#1e1e1e;--vscode-editor-foreground:#d4d4d4;--vscode-foreground:#ccc;--vscode-focusBorder:#0a84ff;--vscode-list-hoverBackground:#2a2d2e;--vscode-list-activeSelectionBackground:#094771;--vscode-list-activeSelectionForeground:#fff;--vscode-list-inactiveSelectionBackground:#37373d;--vscode-editorWidget-background:#252526;--vscode-editorWidget-border:#454545;--vscode-textCodeBlock-background:#0a0a0a;--vscode-textLink-foreground:#3794ff;--vscode-scrollbarSlider-background:#79797966;--vscode-scrollbarSlider-hoverBackground:#646464b3;--vscode-scrollbarSlider-activeBackground:#bfbfbf66;--vscode-minimapSlider-background:#79797933;--vscode-minimapSlider-hoverBackground:#64646459;--vscode-minimapSlider-activeBackground:#bfbfbf59;--vscode-font-family:sans-serif;--vscode-editor-font-family:monospace;--vscode-button-hoverBackground:#1177bb;--vscode-button-secondaryBackground:#3a3d41;--vscode-checkbox-selectBackground:#0a84ff;`;

/** The elements of the webview skeleton (src/views/html.ts) the script looks up by id. */
const SKELETON = `<nav id="breadcrumb" tabindex="-1"></nav><div id="sticky-scroll"></div><div id="breadcrumb-dropdown" tabindex="-1"></div>
<div id="content"></div><div id="minimap"><div id="minimap-content"></div><div id="minimap-slider"></div></div>
<nav id="toc"><div id="toc-title">On this page</div><ol id="toc-list"></ol></nav><button id="toc-fab" tabindex="-1"></button><div id="toc-backdrop"></div><div class="hint">h</div>`;

/** The bench webview bundle: script and stylesheet text. */
interface Bundle {
  readonly js: string;
  readonly css: string;
}

/**
 * Build the bench bundle into the layout's tmp folder: the shipped webview entry plus
 * the internals hand-over, with the shipped entry's format and minify settings. The
 * fold trace hook stays in (only the shipped bundle defines it away).
 */
async function buildBundle(): Promise<Bundle> {
  const outDir = path.join(layoutPath('tmp'), 'bench-webview');
  await build({
    config: false,
    entry: { webview: path.join(repo, 'bench', 'webview-internals.ts') },
    format: 'iife',
    platform: 'browser',
    minify: true,
    // The shipped entry's target (tsdown.config.ts): it also decides how the stylesheet is lowered.
    target: 'chrome132',
    outDir,
    clean: true,
    outputOptions: { entryFileNames: '[name].js' },
    css: { fileName: 'webview.css', minify: true },
    // The build id the shipped bundle gets from tsdown.config.ts; the benches never restore.
    define: { BUILD_ID: JSON.stringify('bench') },
    logLevel: 'warn',
  });
  return {
    js: fs.readFileSync(path.join(outDir, 'webview.js'), 'utf8'),
    css: fs.readFileSync(path.join(outDir, 'webview.css'), 'utf8'),
  };
}

/**
 * The webview skeleton (src/views/html.ts getWebviewHtml) plus the instrumentation
 * every bench uses: a getBoundingClientRect counter (a forced-layout proxy) and the
 * acquireVsCodeApi stand-in. `driver` is the bench's own module-free script; it runs
 * last, reads the webview internals from `__mw`, and must write a line starting with
 * RESULT into #prof when it is done.
 */
async function buildPage(driver: string): Promise<string> {
  const { js, css } = await buildBundle();
  return `<!doctype html><html><head><meta charset="utf-8"><style>:root{${THEME}}${css}</style></head><body>
${SKELETON}
<pre id="prof" style="position:fixed;bottom:0;left:0;z-index:99;background:#000;color:#0f0;font:12px monospace;padding:4px">pending</pre>
<script>window.__gbcr=0;const _g=Element.prototype.getBoundingClientRect;Element.prototype.getBoundingClientRect=function(){window.__gbcr++;return _g.apply(this,arguments)};window.__posted=[];window.acquireVsCodeApi=()=>({postMessage(m){window.__posted.push(m)},setState(){},getState(){return null}});
// Surface a page error as the result instead of leaving the poll to time out on
// "pending" - a silent bench is worse than a red one.
const fail=(m)=>{const p=document.getElementById('prof');if(p&&!p.textContent.startsWith('RESULT'))p.textContent='RESULT ERROR '+m;};
window.addEventListener('error',(e)=>fail((e.message||'error')+' @'+(e.lineno||'?')));
window.addEventListener('unhandledrejection',(e)=>fail('rejection '+((e.reason&&e.reason.message)||e.reason)));</script>
<script>${js}</script>
<script>
const { content } = window.__mw;
const raf = () => new Promise((r) => requestAnimationFrame(r));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const report = (text) => { document.getElementById('prof').textContent = 'RESULT ' + text; };
// Median of a numeric sample - the bench statistic (robust against a single
// scheduling outlier, unlike a mean).
const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[s.length >> 1] : 0;
};
const ms = (x) => x.toFixed(2);
${driver}
</script></body></html>`;
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Options of one bench run. */
interface RunOptions {
  /** Also print a CPU self-time table (sampling profiler). */
  readonly profile?: boolean;
  /** Page file name (without .html) under the layout's tmp folder. */
  readonly name?: string;
  /** Print nothing; the caller reads the returned {@link PageRun}. */
  readonly quiet?: boolean;
  /** Also read the page's CDP `Performance.getMetrics` once it has reported. */
  readonly metrics?: boolean;
}

/** What one page run reported: the #prof text and, on request, the CDP performance metrics. */
export interface PageRun {
  readonly text: string;
  readonly metrics: Readonly<Record<string, number>>;
}

// A CDP value as JSON: objects are read field by field through these guards.
type Json = unknown;
const field = (v: Json, key: string): Json =>
  typeof v === 'object' && v !== null ? Reflect.get(v, key) : undefined;
const str = (v: Json): string => (typeof v === 'string' ? v : '');
const num = (v: Json): number => (typeof v === 'number' ? v : 0);
const list = (v: Json): Json[] => (Array.isArray(v) ? v : []);

/**
 * Launch, navigate, poll the page's #prof until it reports, print it. With
 * profile: true it also prints a CPU self-time table (sampling profiler).
 */
async function runPage(html: string, opts: RunOptions = {}): Promise<PageRun> {
  const chrome = findChrome();
  if (!chrome) {
    console.error('No Chromium found. Set CHROME_BIN=/path/to/chrome');
    process.exit(2);
  }
  const port = 9222 + (process.pid % 500);
  const pageDir = layoutPath('tmp');
  fs.mkdirSync(pageDir, { recursive: true });
  const pagePath = path.join(pageDir, `${opts.name || 'bench'}.html`);
  fs.writeFileSync(pagePath, html);
  const profileDir = fs.mkdtempSync(path.join(pageDir, 'chrome-profile-'));
  const proc = spawn(
    chrome,
    [
      '--headless=new',
      `--user-data-dir=${profileDir}`,
      '--no-sandbox',
      '--disable-gpu',
      `--remote-debugging-port=${port}`,
      '--remote-allow-origins=*',
      '--window-size=1400,900',
      'about:blank',
    ],
    { stdio: 'ignore' },
  );
  try {
    let ver: Json;
    for (let i = 0; i < 40 && !ver; i++) {
      try {
        ver = await (
          await fetch(`http://127.0.0.1:${port}/json/version`)
        ).json();
      } catch {
        await wait(150);
      }
    }
    if (!ver) throw new Error('CDP endpoint did not come up');
    const targets = list(
      await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(),
    );
    const tab = targets.find((t) => field(t, 'type') === 'page') || targets[0];
    const ws = new WebSocket(str(field(tab, 'webSocketDebuggerUrl')));
    let id = 0;
    const pend = new Map<number, (result: Json) => void>();
    const send = (m: string, p?: object) =>
      new Promise<Json>((r) => {
        const i = ++id;
        pend.set(i, r);
        ws.send(JSON.stringify({ id: i, method: m, params: p }));
      });
    await new Promise((r) => ws.addEventListener('open', r));
    ws.addEventListener('message', (ev) => {
      const m: Json = JSON.parse(String(ev.data));
      const mid = num(field(m, 'id'));
      const resolve = pend.get(mid);
      if (mid && resolve) {
        resolve(field(m, 'result'));
        pend.delete(mid);
      }
    });
    await send('Runtime.enable', {});
    await send('Page.enable', {});
    // Metrics count from the moment they are enabled: before the navigation.
    if (opts.metrics) await send('Performance.enable', {});
    if (opts.profile) {
      await send('Profiler.enable', {});
      await send('Profiler.setSamplingInterval', { interval: 100 });
    }
    await send('Page.navigate', { url: pathToFileURL(pagePath).href });
    if (opts.profile) {
      await wait(600);
      await send('Profiler.start', {});
    }
    let text = '';
    for (let i = 0; i < 120 && !text.startsWith('RESULT'); i++) {
      await wait(500);
      const r = await send('Runtime.evaluate', {
        expression: "document.getElementById('prof').textContent",
        returnByValue: true,
      });
      text = str(field(field(r, 'result'), 'value'));
    }
    const metrics: Record<string, number> = {};
    if (opts.metrics) {
      const got = await send('Performance.getMetrics', {});
      for (const m of list(field(got, 'metrics')))
        metrics[str(field(m, 'name'))] = num(field(m, 'value'));
    }
    if (!opts.quiet) {
      console.log(`chrome: ${chrome}`);
      console.log(text || '(no result - the page did not finish)');
      if (opts.profile) printProfile(await send('Profiler.stop', {}));
    }
    return { text, metrics };
  } finally {
    const exited = new Promise((r) => proc.once('exit', r));
    proc.kill('SIGKILL');
    await exited;
    removeProfile(profileDir);
  }
}

function printProfile(prof: Json): void {
  const profile = field(prof, 'profile');
  if (!profile) return;
  const self = new Map<string, number>();
  for (const n of list(field(profile, 'nodes'))) {
    const frame = field(n, 'callFrame');
    const key =
      (str(field(frame, 'functionName')) || '(anonymous)') +
      ' @' +
      str(field(frame, 'url')).replace(/^.*\//, '') +
      ':' +
      num(field(frame, 'lineNumber'));
    self.set(key, (self.get(key) || 0) + num(field(n, 'hitCount')));
  }
  const total = [...self.values()].reduce((a, b) => a + b, 0) || 1;
  console.log(`--- CPU self-time (top 12, ${total} samples) ---`);
  for (const [k, v] of [...self.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 12)) {
    console.log(`${(`${((100 * v) / total).toFixed(1)}%`).padStart(6)}  ${k}`);
  }
}

/** Tiny argv reader shared by the benches. */
function cli(argv: readonly string[]): {
  flag(name: string): boolean;
  opt(name: string, dflt: string): string;
} {
  return {
    flag: (n) => argv.includes(n),
    opt: (n, d) => {
      const i = argv.indexOf(n);
      return i >= 0 && argv[i + 1] ? (argv[i + 1] ?? d) : d;
    },
  };
}

export {
  chromeCandidates,
  removeProfile,
  findChrome,
  buildPage,
  runPage,
  cli,
  SKELETON,
  THEME,
};
