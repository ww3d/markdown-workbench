// Workbench webview script: renders the markdown HTML pushed from the host,
// handles checkbox toggles and selection, bidirectional fractional scroll
// sync, and the minimap. Runs in the webview (browser) context, not the
// extension host - it ships as a media asset and is loaded via a nonce'd
// <script src> from getWebviewHtml (views.js).
const vscode = acquireVsCodeApi();
const content = document.getElementById('content');
let selection = new Set(); // source line numbers of selected tasks
let anchor = null;         // last clicked task line (for shift-range)

// --- Fractional scroll sync (algorithms modeled on the built-in preview) ---

function lineEntries() {
  return [...content.querySelectorAll('[data-line]')].map((el) => ({
    el,
    line: Number(el.dataset.line),
    endLine: el.dataset.lineEnd ? Number(el.dataset.lineEnd) : undefined
  }));
}

function absTop(el) { return el.getBoundingClientRect().top + window.scrollY; }

// Scroll so that the (fractional) source line sits at the viewport top.
function scrollToSourceLine(line) {
  if (line <= 0) { window.scrollTo(window.scrollX, 0); return; }
  const entries = lineEntries();
  if (!entries.length) return;
  const lineNumber = Math.floor(line);
  let previous = entries[0], next = null;
  for (const entry of entries) {
    if (entry.line === lineNumber) { previous = entry; next = null; break; }
    if (entry.line > lineNumber) { next = entry; break; }
    previous = entry;
  }
  const rect = previous.el.getBoundingClientRect();
  const previousTop = rect.top + window.scrollY;
  let target;
  if (previous.endLine && previous.endLine > previous.line && line < previous.endLine) {
    // Inside a multi-line code block: scroll proportionally through it.
    const progress = (line - previous.line) / (previous.endLine - previous.line);
    target = previousTop + rect.height * progress;
  } else if (next && next.line !== previous.line) {
    const progress = (line - previous.line) / (next.line - previous.line);
    target = previousTop + (absTop(next.el) - previousTop) * progress;
  } else {
    target = previousTop + rect.height * Math.min(1, Math.max(0, line - previous.line));
  }
  window.scrollTo(window.scrollX, target);
}

// Fractional source line currently at the viewport top.
function sourceLineAtTop() {
  const entries = lineEntries();
  if (!entries.length) return null;
  const offset = window.scrollY;
  let previous = null, next = null;
  for (const entry of entries) {
    if (absTop(entry.el) <= offset + 1) { previous = entry; } // later (deeper) entries win
    else if (!next) { next = entry; }
  }
  if (!previous) return 0;
  const rect = previous.el.getBoundingClientRect();
  const previousTop = rect.top + window.scrollY;
  if (previous.endLine && previous.endLine > previous.line && rect.height > 0
      && offset <= previousTop + rect.height) {
    // Inside a multi-line code block.
    const progress = (offset - previousTop) / rect.height;
    return previous.line + progress * (previous.endLine - previous.line);
  }
  if (next) {
    const nextTop = absTop(next.el);
    if (nextTop > previousTop) {
      const progress = (offset - previousTop) / (nextTop - previousTop);
      return previous.line + Math.min(1, Math.max(0, progress)) * (next.line - previous.line);
    }
  }
  if (rect.height > 0) {
    return previous.line + Math.min(1, Math.max(0, (offset - previousTop) / rect.height));
  }
  return previous.line;
}

window.addEventListener('message', (e) => {
  if (e.data.type === 'render') {
    content.innerHTML = e.data.html;
    applySelection();
    rebuildMinimap();
  } else if (e.data.type === 'config') {
    document.documentElement.style.setProperty('--mc-max-width', e.data.maxWidth);
    applyMinimapCfg(e.data.minimap); // rebuilds; column width drives the scale
  } else if (e.data.type === 'scrollTo') {
    // Source editor was scrolled -> mirror the fractional position.
    // Suppress the echo from our own scrolling.
    suppressScrollEvents = Date.now() + 200;
    scrollToSourceLine(e.data.line);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { selection.clear(); applySelection(); }
});

function tasks() { return [...content.querySelectorAll('li.task')]; }

function applySelection() {
  for (const li of tasks()) {
    li.classList.toggle('selected', selection.has(Number(li.dataset.line)));
  }
}

// Delegated click handling: innermost task row wins (nested tasks bubble).
content.addEventListener('click', (e) => {
  if (e.target.closest('a')) return; // let links work normally
  const cell = e.target.closest('input.cell-task');
  if (cell) {
    e.preventDefault();
    // At click time the input has already flipped its live .checked and
    // preventDefault reverts it afterwards - the rendered attribute is
    // the reliable original state.
    vscode.postMessage({
      type: 'toggleCell',
      line: Number(cell.dataset.line),
      idx: Number(cell.dataset.idx),
      checked: !cell.hasAttribute('checked')
    });
    return;
  }
  // Click anywhere in a table cell that holds exactly one checkbox
  // toggles that checkbox.
  const td = e.target.closest('td');
  if (td) {
    const boxes = td.querySelectorAll('input.cell-task');
    if (boxes.length === 1) {
      e.preventDefault();
      const box = boxes[0];
      vscode.postMessage({
        type: 'toggleCell',
        line: Number(box.dataset.line),
        idx: Number(box.dataset.idx),
        checked: !box.hasAttribute('checked')
      });
    }
    return;
  }
  const row = e.target.closest('.task-row');
  if (!row) return;
  e.preventDefault();

  const li = row.closest('li.task');
  const line = Number(li.dataset.line);

  if (e.shiftKey && anchor !== null) {
    // Range select between anchor and clicked task (document order).
    const lines = tasks().map(t => Number(t.dataset.line));
    const a = lines.indexOf(anchor), b = lines.indexOf(line);
    if (a !== -1 && b !== -1) {
      for (let i = Math.min(a, b); i <= Math.max(a, b); i++) selection.add(lines[i]);
    }
    applySelection();
    return;
  }

  if (e.ctrlKey || e.metaKey) {
    selection.has(line) ? selection.delete(line) : selection.add(line);
    anchor = line;
    applySelection();
    return;
  }

  // Plain click: toggle. If the clicked task is part of the selection,
  // toggle the whole selection in parallel to the clicked task's new state.
  anchor = line;
  const newState = li.dataset.checked !== 'true';
  const lines = selection.has(line) ? [...selection] : [line];
  vscode.postMessage({ type: 'toggle', lines, checked: newState });
});

// Webview scrolled by the user -> tell the extension which source line is
// at the top so it can reveal it in the text editor.
let suppressScrollEvents = 0;
let scrollPending = false;
window.addEventListener('scroll', () => {
  if (scrollPending) return;
  scrollPending = true;
  requestAnimationFrame(() => {
    scrollPending = false;
    updateMinimap(); // always - also for editor-driven (suppressed) scrolls
    if (Date.now() < suppressScrollEvents) return;
    const line = sourceLineAtTop();
    if (line !== null) {
      vscode.postMessage({ type: 'scrolled', line: Math.max(0, line) });
    }
  });
}, { passive: true });

// --- Minimap: scaled clone, proportional panning, click/drag to navigate ---
const minimap = document.getElementById('minimap');
const mapContent = document.getElementById('minimap-content');
const mapSlider = document.getElementById('minimap-slider');
let minimapCfg = { enabled: true, size: 'proportional', showSlider: 'mouseover', side: 'right' };
let mapKx = 0.1;     // horizontal scale: rail width / content width
let mapSy = 0.1;     // vertical scale of the active size mode
let mapOffset = 0;   // translateY pan (proportional mode only)

function applyMinimapCfg(cfg) {
  // Merge over defaults so a missing or partial config can never null
  // out minimapCfg or hide the rail via undefined.
  minimapCfg = Object.assign(
    { enabled: true, size: 'proportional', showSlider: 'mouseover', side: 'right' },
    cfg || {}
  );
  if (minimapCfg.enabled === undefined) minimapCfg.enabled = true;
  cfg = minimapCfg;
  document.body.classList.toggle('minimap-left', cfg.side === 'left');
  minimap.classList.toggle('slider-mouseover', cfg.showSlider === 'mouseover');
  rebuildMinimap();
}

function rebuildMinimap() {
  // Visibility first: while the rail is display:none its clientWidth is 0,
  // which would bake a scale of 0 into the clone on the very first render.
  const needed = minimapCfg.enabled
    && document.documentElement.scrollHeight - window.innerHeight > 0;
  document.body.classList.toggle('has-minimap', needed);
  mapContent.innerHTML = '';
  if (!needed) return;
  const clone = content.cloneNode(true);
  for (const input of clone.querySelectorAll('input')) input.disabled = true;
  mapContent.appendChild(clone);
  mapKx = content.clientWidth > 0 ? minimap.clientWidth / content.clientWidth : 0.1;
  mapContent.style.width = content.clientWidth + 'px';
  updateMinimap();
}

function updateMinimap() {
  const docH = document.documentElement.scrollHeight;
  const viewH = window.innerHeight;
  const scrollMax = docH - viewH;
  if (!minimapCfg.enabled || scrollMax <= 0) {
    document.body.classList.remove('has-minimap');
    return;
  }
  document.body.classList.add('has-minimap');
  const railH = minimap.clientHeight;
  if (minimapCfg.size === 'fill') {
    // Whole document maps linearly onto the full rail: the slider stays
    // aligned with the real scrollbar, nothing pans.
    mapSy = railH / docH;
    mapOffset = 0;
  } else if (minimapCfg.size === 'fit') {
    // Downscale until the document fits the rail, never stretch.
    mapSy = Math.min(mapKx, railH / docH);
    mapOffset = 0;
  } else { // proportional
    mapSy = mapKx;
    const overflow = Math.max(0, docH * mapKx - railH);
    mapOffset = -(window.scrollY / scrollMax) * overflow;
  }
  mapContent.style.transform =
    'translateY(' + mapOffset + 'px) scale(' + mapKx + ', ' + mapSy + ')';
  mapSlider.style.top = (window.scrollY * mapSy + mapOffset) + 'px';
  mapSlider.style.height = Math.max(12, viewH * mapSy) + 'px';
}

function minimapNavigate(clientY) {
  const y = clientY - minimap.getBoundingClientRect().top;
  const docY = (y - mapOffset) / mapSy;
  window.scrollTo(window.scrollX, docY - window.innerHeight / 2);
}

minimap.addEventListener('pointerdown', (e) => {
  e.preventDefault();
  minimap.classList.add('dragging');
  minimap.setPointerCapture(e.pointerId);
  minimapNavigate(e.clientY);
});
minimap.addEventListener('pointermove', (e) => {
  if (minimap.classList.contains('dragging')) minimapNavigate(e.clientY);
});
minimap.addEventListener('pointerup', (e) => {
  minimap.classList.remove('dragging');
  minimap.releasePointerCapture(e.pointerId);
});
window.addEventListener('resize', rebuildMinimap, { passive: true });

vscode.postMessage({ type: 'ready' });
