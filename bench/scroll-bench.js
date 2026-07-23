#!/usr/bin/env node
// Headless-Chromium scroll benchmark for the preview webview.
//
// Renders the REAL media/webview.{js,css} into a generated document, drives a
// scroll sweep in a headless Chromium, and reports wall time per frame plus the
// number of getBoundingClientRect calls per frame (a forced-layout proxy).
//
// No npm dependency: it launches a Chromium binary you already have and drives it
// over the Chrome DevTools Protocol using Node's built-in WebSocket + fetch
// (Node >= 21). Point it at a browser with CHROME_BIN, or it will try common
// locations and the Playwright cache (PLAYWRIGHT_BROWSERS_PATH).
//
// Usage:
//   node bench/scroll-bench.js                 # 300 sections, all bars on
//   node bench/scroll-bench.js --tables 240    # add N tables (native sticky th)
//   node bench/scroll-bench.js --tables 240 --no-sticky   # stack disabled
//   node bench/scroll-bench.js --profile       # also print a CPU self-time table
//
// Numbers are relative and machine-dependent; use it to compare a change against
// its baseline on the same machine, not as an absolute target.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const repo = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 && args[i + 1] ? args[i + 1] : d; };
const SECTIONS = Number(opt('--sections', '300'));
const TABLES = Number(opt('--tables', '0'));
const STICKY = !flag('--no-sticky');
const PROFILE = flag('--profile');
const PORT = 9222 + (process.pid % 500);

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

function doc() {
  let h = '', line = 1;
  for (let s = 0; s < SECTIONS; s++) {
    h += `<h2 id="s${s}" data-line="${line++}">Section ${s}</h2>`;
    h += `<h3 id="s${s}a" data-line="${line++}">Subsection ${s}.a</h3>`;
    for (let p = 0; p < 3; p++) h += `<p data-line="${line++}">Paragraph ${s}.${p} lorem ipsum dolor sit amet consectetur.</p>`;
    if (TABLES && s < TABLES) {
      let rows = '';
      for (let r = 0; r < 6; r++) rows += `<tr><td>${r}a</td><td>${r}b</td><td>${r}c</td></tr>`;
      h += `<div class="table-wrap" data-line="${line++}"><table><thead><tr><th>A</th><th>B</th><th>C</th></tr></thead><tbody>${rows}</tbody></table></div>`;
    }
  }
  return h;
}

// Representative dark-theme values for the --vscode-* custom properties the
// stylesheet reads (VS Code injects these into a real webview).
const THEME = `--vscode-editor-background:#1e1e1e;--vscode-editor-foreground:#d4d4d4;--vscode-foreground:#ccc;--vscode-focusBorder:#0a84ff;--vscode-list-hoverBackground:#2a2d2e;--vscode-list-activeSelectionBackground:#094771;--vscode-list-activeSelectionForeground:#fff;--vscode-list-inactiveSelectionBackground:#37373d;--vscode-editorWidget-background:#252526;--vscode-editorWidget-border:#454545;--vscode-textCodeBlock-background:#0a0a0a;--vscode-textLink-foreground:#3794ff;--vscode-scrollbarSlider-background:#79797966;--vscode-scrollbarSlider-hoverBackground:#646464b3;--vscode-scrollbarSlider-activeBackground:#bfbfbf66;--vscode-minimapSlider-background:#79797933;--vscode-minimapSlider-hoverBackground:#64646459;--vscode-minimapSlider-activeBackground:#bfbfbf59;--vscode-font-family:sans-serif;--vscode-editor-font-family:monospace;--vscode-button-hoverBackground:#1177bb;--vscode-button-secondaryBackground:#3a3d41;--vscode-checkbox-selectBackground:#0a84ff;`;

function buildPage() {
  const css = fs.readFileSync(path.join(repo, 'media/webview.css'), 'utf8');
  const js = fs.readFileSync(path.join(repo, 'media/webview.js'), 'utf8')
    .replace('const vscode = acquireVsCodeApi();', 'const vscode = window.__vscode;');
  const config = {
    type: 'config', maxWidth: '980px',
    minimap: { enabled: true, side: 'right', size: 'proportional', showSlider: 'always' },
    toc: { enabled: true, mode: 'auto' }, breadcrumb: { enabled: true }, stickyScroll: { enabled: STICKY }
  };
  return `<!doctype html><html><head><meta charset="utf-8"><style>:root{${THEME}}${css}</style></head><body>
<nav id="breadcrumb" tabindex="-1"></nav><div id="sticky-scroll"></div><div id="breadcrumb-dropdown" tabindex="-1"></div>
<div id="content"></div><div id="minimap"><div id="minimap-content"></div><div id="minimap-slider"></div></div>
<nav id="toc"><div id="toc-title">On this page</div><ol id="toc-list"></ol></nav><button id="toc-fab" tabindex="-1"></button><div id="toc-backdrop"></div><div class="hint">h</div>
<pre id="prof" style="position:fixed;bottom:0;left:0;z-index:99;background:#000;color:#0f0;font:12px monospace;padding:4px">pending</pre>
<script>window.__gbcr=0;const _g=Element.prototype.getBoundingClientRect;Element.prototype.getBoundingClientRect=function(){window.__gbcr++;return _g.apply(this,arguments)};window.__vscode={postMessage(){},setState(){},getState(){return null}};</script>
<script>${js}</script>
<script>
const DOC=${JSON.stringify(doc())};const config=${JSON.stringify(config)};const raf=()=>new Promise(r=>requestAnimationFrame(r));
async function run(){
  window.dispatchEvent(new MessageEvent('message',{data:config}));
  window.dispatchEvent(new MessageEvent('message',{data:{type:'render',html:DOC}}));
  await raf();await raf();
  const maxY=document.documentElement.scrollHeight-window.innerHeight;
  window.scrollTo(0,0);window.dispatchEvent(new Event('scroll'));await raf();
  window.__gbcr=0;const F=120;const t0=performance.now();
  for(let i=1;i<=F;i++){window.scrollTo(0,Math.round(maxY*i/F));window.dispatchEvent(new Event('scroll'));await raf();}
  const dt=performance.now()-t0;
  document.getElementById('prof').textContent='RESULT frames='+F+' perFrame='+(dt/F).toFixed(2)+'ms gbcrPerFrame='+(window.__gbcr/F).toFixed(1)
    +' lines='+document.querySelectorAll('[data-line]').length+' tables='+document.querySelectorAll('table').length+' scrollHeight='+document.documentElement.scrollHeight;
}
run();
</script></body></html>`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const chrome = findChrome();
  if (!chrome) { console.error('No Chromium found. Set CHROME_BIN=/path/to/chrome'); process.exit(2); }
  const pagePath = path.join(__dirname, '.scroll-bench.html');
  fs.writeFileSync(pagePath, buildPage());
  const proc = spawn(chrome, ['--headless=new', '--no-sandbox', '--disable-gpu',
    '--remote-debugging-port=' + PORT, '--remote-allow-origins=*', '--window-size=1400,900', 'about:blank'],
    { stdio: 'ignore' });
  try {
    let ver;
    for (let i = 0; i < 40 && !ver; i++) { try { ver = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json(); } catch { await sleep(150); } }
    if (!ver) throw new Error('CDP endpoint did not come up');
    const targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
    const tab = targets.find((t) => t.type === 'page') || targets[0];
    const ws = new WebSocket(tab.webSocketDebuggerUrl);
    let id = 0; const pend = new Map();
    const send = (m, p) => new Promise((r) => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method: m, params: p })); });
    await new Promise((r) => ws.addEventListener('open', r));
    ws.addEventListener('message', (ev) => { const m = JSON.parse(ev.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m.result); pend.delete(m.id); } });
    await send('Runtime.enable', {}); await send('Page.enable', {});
    if (PROFILE) { await send('Profiler.enable', {}); await send('Profiler.setSamplingInterval', { interval: 100 }); }
    await send('Page.navigate', { url: 'file://' + pagePath });
    if (PROFILE) { await sleep(600); await send('Profiler.start', {}); }
    let text = '';
    for (let i = 0; i < 60 && !text.startsWith('RESULT'); i++) {
      await sleep(500);
      const r = await send('Runtime.evaluate', { expression: "document.getElementById('prof').textContent", returnByValue: true });
      text = (r && r.result && r.result.value) || '';
    }
    console.log('chrome: ' + chrome);
    console.log(text || '(no result - the page did not finish)');
    if (PROFILE) {
      const prof = await send('Profiler.stop', {});
      if (prof && prof.profile) {
        const self = new Map();
        for (const n of prof.profile.nodes) {
          const key = (n.callFrame.functionName || '(anonymous)') + ' @' + (n.callFrame.url || '').replace(/^.*\//, '') + ':' + n.callFrame.lineNumber;
          self.set(key, (self.get(key) || 0) + (n.hitCount || 0));
        }
        const total = [...self.values()].reduce((a, b) => a + b, 0) || 1;
        console.log('--- CPU self-time (top 12, ' + total + ' samples) ---');
        for (const [k, v] of [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)) {
          console.log(('' + (100 * v / total).toFixed(1) + '%').padStart(6) + '  ' + k);
        }
      }
    }
  } finally { try { proc.kill('SIGKILL'); } catch {} }
}

main().catch((e) => { console.error('bench error: ' + e.message); process.exit(1); });
