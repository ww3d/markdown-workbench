// Shared headless-Chromium harness for the bench scripts.
//
// Builds a page that loads the REAL media/webview.{js,css} into a VS-Code-like
// skeleton, launches a Chromium you already have, drives it over the Chrome
// DevTools Protocol (Node's built-in WebSocket + fetch, no npm dependency) and
// prints whatever the page reports into its #prof element.
//
// A bench script supplies only its driver: the document to render and the
// measurement loop. Everything below is identical for every bench.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const repo = path.resolve(__dirname, '..');

// Locate a Chromium: CHROME_BIN, else the Playwright cache, else the usual
// system paths. Nothing is installed.
function findChrome() {
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) return process.env.CHROME_BIN;
  const cands = [];
  const pw = process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (pw && fs.existsSync(pw)) {
    for (const d of fs.readdirSync(pw)) {
      if (d.startsWith('chromium')) cands.push(path.join(pw, d, 'chrome-linux', 'chrome'));
    }
  }
  cands.push('/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome');
  return cands.find((c) => { try { return fs.existsSync(c); } catch { return false; } });
}

// Representative dark-theme values for the --vscode-* custom properties the
// stylesheet reads (VS Code injects these into a real webview).
const THEME = `--vscode-editor-background:#1e1e1e;--vscode-editor-foreground:#d4d4d4;--vscode-foreground:#ccc;--vscode-focusBorder:#0a84ff;--vscode-list-hoverBackground:#2a2d2e;--vscode-list-activeSelectionBackground:#094771;--vscode-list-activeSelectionForeground:#fff;--vscode-list-inactiveSelectionBackground:#37373d;--vscode-editorWidget-background:#252526;--vscode-editorWidget-border:#454545;--vscode-textCodeBlock-background:#0a0a0a;--vscode-textLink-foreground:#3794ff;--vscode-scrollbarSlider-background:#79797966;--vscode-scrollbarSlider-hoverBackground:#646464b3;--vscode-scrollbarSlider-activeBackground:#bfbfbf66;--vscode-minimapSlider-background:#79797933;--vscode-minimapSlider-hoverBackground:#64646459;--vscode-minimapSlider-activeBackground:#bfbfbf59;--vscode-font-family:sans-serif;--vscode-editor-font-family:monospace;--vscode-button-hoverBackground:#1177bb;--vscode-button-secondaryBackground:#3a3d41;--vscode-checkbox-selectBackground:#0a84ff;`;

// The webview skeleton (views.js getWebviewHtml) plus the instrumentation every
// bench uses: a getBoundingClientRect counter (a forced-layout proxy) and the
// acquireVsCodeApi stand-in. `driver` is the bench's own module-free script; it
// runs last, with every top-level webview binding in scope, and must write a line
// starting with RESULT into #prof when it is done.
function buildPage(driver) {
  const css = fs.readFileSync(path.join(repo, 'media/webview.css'), 'utf8');
  const morphdom = fs.readFileSync(path.join(repo, 'media/morphdom.js'), 'utf8');
  const js = fs.readFileSync(path.join(repo, 'media/webview.js'), 'utf8')
    .replace('const vscode = acquireVsCodeApi();', 'const vscode = window.__vscode;');
  return `<!doctype html><html><head><meta charset="utf-8"><style>:root{${THEME}}${css}</style></head><body>
<nav id="breadcrumb" tabindex="-1"></nav><div id="sticky-scroll"></div><div id="breadcrumb-dropdown" tabindex="-1"></div>
<div id="content"></div><div id="minimap"><div id="minimap-content"></div><div id="minimap-slider"></div></div>
<nav id="toc"><div id="toc-title">On this page</div><ol id="toc-list"></ol></nav><button id="toc-fab" tabindex="-1"></button><div id="toc-backdrop"></div><div class="hint">h</div>
<pre id="prof" style="position:fixed;bottom:0;left:0;z-index:99;background:#000;color:#0f0;font:12px monospace;padding:4px">pending</pre>
<script>window.__gbcr=0;const _g=Element.prototype.getBoundingClientRect;Element.prototype.getBoundingClientRect=function(){window.__gbcr++;return _g.apply(this,arguments)};window.__vscode={postMessage(){},setState(){},getState(){return null}};
// Surface a page error as the result instead of leaving the poll to time out on
// "pending" - a silent bench is worse than a red one.
const fail=(m)=>{const p=document.getElementById('prof');if(p&&!p.textContent.startsWith('RESULT'))p.textContent='RESULT ERROR '+m;};
window.addEventListener('error',(e)=>fail((e.message||'error')+' @'+(e.lineno||'?')));
window.addEventListener('unhandledrejection',(e)=>fail('rejection '+((e.reason&&e.reason.message)||e.reason)));</script>
<script>${morphdom}</script>
<script>${js}</script>
<script>
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

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// Launch, navigate, poll the page's #prof until it reports, print it. With
// profile: true it also prints a CPU self-time table (sampling profiler).
async function runPage(html, opts = {}) {
  const chrome = findChrome();
  if (!chrome) { console.error('No Chromium found. Set CHROME_BIN=/path/to/chrome'); process.exit(2); }
  const port = 9222 + (process.pid % 500);
  const pagePath = path.join(__dirname, '.' + (opts.name || 'bench') + '.html');
  fs.writeFileSync(pagePath, html);
  const proc = spawn(chrome, ['--headless=new', '--no-sandbox', '--disable-gpu',
    '--remote-debugging-port=' + port, '--remote-allow-origins=*', '--window-size=1400,900', 'about:blank'],
    { stdio: 'ignore' });
  try {
    let ver;
    for (let i = 0; i < 40 && !ver; i++) {
      try { ver = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json(); } catch { await wait(150); }
    }
    if (!ver) throw new Error('CDP endpoint did not come up');
    const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const tab = targets.find((t) => t.type === 'page') || targets[0];
    const ws = new WebSocket(tab.webSocketDebuggerUrl);
    let id = 0; const pend = new Map();
    const send = (m, p) => new Promise((r) => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method: m, params: p })); });
    await new Promise((r) => ws.addEventListener('open', r));
    ws.addEventListener('message', (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); }
    });
    await send('Runtime.enable', {}); await send('Page.enable', {});
    if (opts.profile) { await send('Profiler.enable', {}); await send('Profiler.setSamplingInterval', { interval: 100 }); }
    await send('Page.navigate', { url: 'file://' + pagePath });
    if (opts.profile) { await wait(600); await send('Profiler.start', {}); }
    let text = '';
    for (let i = 0; i < 120 && !text.startsWith('RESULT'); i++) {
      await wait(500);
      const r = await send('Runtime.evaluate', { expression: "document.getElementById('prof').textContent", returnByValue: true });
      text = (r && r.result && r.result.value) || '';
    }
    console.log('chrome: ' + chrome);
    console.log(text || '(no result - the page did not finish)');
    if (opts.profile) printProfile(await send('Profiler.stop', {}));
  } finally { try { proc.kill('SIGKILL'); } catch {} }
}

function printProfile(prof) {
  if (!prof || !prof.profile) return;
  const self = new Map();
  for (const n of prof.profile.nodes) {
    const key = (n.callFrame.functionName || '(anonymous)') + ' @'
      + (n.callFrame.url || '').replace(/^.*\//, '') + ':' + n.callFrame.lineNumber;
    self.set(key, (self.get(key) || 0) + (n.hitCount || 0));
  }
  const total = [...self.values()].reduce((a, b) => a + b, 0) || 1;
  console.log('--- CPU self-time (top 12, ' + total + ' samples) ---');
  for (const [k, v] of [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)) {
    console.log(('' + (100 * v / total).toFixed(1) + '%').padStart(6) + '  ' + k);
  }
}

// Tiny argv reader shared by the benches.
function cli(argv) {
  return {
    flag: (n) => argv.includes(n),
    opt: (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; }
  };
}

module.exports = { findChrome, buildPage, runPage, cli };
