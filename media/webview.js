// Workbench webview script: renders the markdown HTML pushed from the host,
// handles checkbox toggles and selection, bidirectional fractional scroll
// sync, and the minimap. Runs in the webview (browser) context, not the
// extension host - it ships as a media asset and is loaded via a nonce'd
// <script src> from getWebviewHtml (views.js).
const vscode = acquireVsCodeApi();
const content = document.getElementById('content');
let selection = new Set(); // source line numbers of selected tasks
let anchor = null;         // last clicked task line (for shift-range)
// Preview readability config (#25 follow-up). Defaults reproduce #25: text is
// selectable, the batch gesture lives on the checkbox, the row keeps the
// pointer hand. The host overwrites these on every 'config' message.
let previewCfg = { textSelection: true, taskBatchSelect: 'checkbox', taskRowTextCursor: false };

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
    applyPreviewCfg(e.data);
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

// Store the readability flags (safe defaults if a field is absent) and reflect
// them as body classes the stylesheet keys off: mw-no-text-select locks
// selection, mw-task-text-cursor swaps the row's pointer hand for a text
// caret. The cursor swap only applies while text is selectable.
function applyPreviewCfg(cfg) {
  previewCfg = {
    textSelection: cfg.textSelection !== false,
    taskBatchSelect: cfg.taskBatchSelect === 'row' ? 'row' : 'checkbox',
    taskRowTextCursor: cfg.taskRowTextCursor === true
  };
  document.body.classList.toggle('mw-no-text-select', previewCfg.textSelection === false);
  document.body.classList.toggle('mw-task-text-cursor',
    previewCfg.textSelection !== false && previewCfg.taskRowTextCursor === true);
}

// A bare click (anywhere but directly on a checkbox input) may toggle a task
// only when it produced no text selection and is not part of a multi-click -
// so dragging out a selection or double-clicking to select a word reads as
// text interaction, not a toggle. Pure function, exposed for tests.
function canToggleFromBareClick(selectionText, detail) {
  return selectionText === '' && detail === 1;
}

// Gate for bare (non-checkbox) clicks. With selection disabled there is no text
// interaction to protect, so a bare click always toggles (pre-#25 behavior);
// otherwise it defers to the selection/multi-click guard. Exposed for tests.
function bareClickToggles(textSelectionEnabled, selectionText, detail) {
  return !textSelectionEnabled ? true : canToggleFromBareClick(selectionText, detail);
}

// At click time a clicked checkbox input has already flipped its live .checked
// and preventDefault reverts it afterwards - the rendered `checked` attribute
// is the reliable original state.
function postCellToggle(box) {
  vscode.postMessage({
    type: 'toggleCell',
    line: Number(box.dataset.line),
    idx: Number(box.dataset.idx),
    checked: !box.hasAttribute('checked')
  });
}

// Plain list toggle. If the clicked task is part of the selection, toggle the
// whole selection in parallel to the clicked task's new state.
function toggleListTask(li) {
  const line = Number(li.dataset.line);
  anchor = line;
  const newState = li.dataset.checked !== 'true';
  const lines = selection.has(line) ? [...selection] : [line];
  vscode.postMessage({ type: 'toggle', lines, checked: newState });
}

// Batch gestures live on the checkbox only (#15): Shift = range, Ctrl/Meta =
// membership. Driving them from the label would collide with normal text
// range-selection (Shift+click) once the body is selectable.
function batchSelectListTask(li, e) {
  const line = Number(li.dataset.line);
  if (e.shiftKey && anchor !== null) {
    // Range select between anchor and clicked task (document order).
    const lines = tasks().map(t => Number(t.dataset.line));
    const a = lines.indexOf(anchor), b = lines.indexOf(line);
    if (a !== -1 && b !== -1) {
      for (let i = Math.min(a, b); i <= Math.max(a, b); i++) selection.add(lines[i]);
    }
    applySelection();
    return true;
  }
  if (e.ctrlKey || e.metaKey) {
    selection.has(line) ? selection.delete(line) : selection.add(line);
    anchor = line;
    applySelection();
    return true;
  }
  return false;
}

// Delegated click handling: innermost task row wins (nested tasks bubble).
content.addEventListener('click', (e) => {
  // Internal anchor links ([Text](#slug)) do not self-navigate in a webview:
  // resolve the target heading by id and scroll to it. The scroll listener then
  // reports the new position, so the source editor follows. A missing target is
  // left alone (no error, no fallthrough to the task-toggle logic). Cross-file
  // (./other.md#x) and external (http[s]://) links keep the browser default.
  const link = e.target.closest('a[href^="#"]'); // not the module-level `anchor` (task shift-range)
  if (link) {
    let hash = link.getAttribute('href').slice(1);
    // decodeURIComponent throws on a malformed escape; a raw HTML anchor
    // (html: true) can carry one (e.g. href="#100%"), so fall back to the
    // literal hash instead of letting the click die with an URIError.
    try { hash = decodeURIComponent(hash); } catch (_) { /* keep the literal hash */ }
    // Scope the lookup to the content root: the webview skeleton carries its own
    // ids (content, minimap, ...), and a heading like "# Content" slugs to
    // "content" - a document-wide getElementById would resolve the container
    // instead. Guard the empty hash (href="#"): '#' alone is an invalid selector.
    const target = hash ? content.querySelector('#' + CSS.escape(hash)) : null;
    if (target) { e.preventDefault(); window.scrollTo(window.scrollX, absTop(target)); }
    return;
  }
  if (e.target.closest('a')) return; // let links work normally

  // Direct click on a table cell checkbox: toggles always, ungated.
  const cell = e.target.closest('input.cell-task');
  if (cell) {
    e.preventDefault();
    postCellToggle(cell);
    return;
  }

  // Direct click on a list task checkbox: toggles always, ungated, and carries
  // the batch gestures (Shift/Ctrl) - the only place batch is triggered.
  const checkbox = e.target.closest('.task-row input[type=checkbox]');
  if (checkbox) {
    e.preventDefault();
    const li = checkbox.closest('li.task');
    if (!batchSelectListTask(li, e)) toggleListTask(li);
    return;
  }

  // Bare click in a table cell with exactly one checkbox (not on the input):
  // toggles only when no fresh text selection / multi-click is in play (gate
  // collapses to "always" when text selection is disabled).
  const td = e.target.closest('td');
  if (td) {
    const boxes = td.querySelectorAll('input.cell-task');
    if (boxes.length === 1
        && bareClickToggles(previewCfg.textSelection, window.getSelection().toString(), e.detail)) {
      e.preventDefault();
      postCellToggle(boxes[0]);
    }
    return;
  }

  // Bare click in the task row label area (not the checkbox).
  const row = e.target.closest('.task-row');
  if (!row) return;
  const li = row.closest('li.task');
  // In 'row' batch mode the label carries the batch gesture too (the price:
  // Shift in the label no longer extends a text selection). In 'checkbox' mode
  // the label only plain-toggles, gated so a text selection / multi-click wins.
  if (previewCfg.taskBatchSelect === 'row' && (e.shiftKey || e.ctrlKey || e.metaKey)) {
    e.preventDefault();
    if (!batchSelectListTask(li, e)) toggleListTask(li);
    return;
  }
  if (!bareClickToggles(previewCfg.textSelection, window.getSelection().toString(), e.detail)) return;
  e.preventDefault();
  toggleListTask(li);
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
    updateStickyHeads(); // emulated pin follows the window scroll
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

// Top-level table wrappers (render.js) whose table is wider than the breakout
// cap (webview.css) get a horizontal scroll container of their own so the
// window never h-scrolls because of a table. Toggled here and not statically
// in CSS: an unconditional overflow-x would make every wrapper the th
// scrollport and silently disable the sticky table header.
function updateTableScroll() {
  for (const wrap of content.querySelectorAll(':scope > .table-wrap')) {
    wrap.classList.toggle('scrolls', wrap.scrollWidth > wrap.clientWidth);
  }
}

// Vertical header offset for an element-scrolling table: inside a scrolls
// wrapper the wrapper is the th's scrollport, so native position: sticky is
// inert against the window scroll - the pin is emulated by translating the
// thead. Clamped to [0, tableHeight - headHeight] so the header stops at the
// table's bottom edge instead of ghosting below it. Document coordinates.
function stickyHeadOffset(scrollY, tableTop, tableHeight, headHeight) {
  return Math.max(0, Math.min(scrollY - tableTop, tableHeight - headHeight));
}

// Apply the emulated sticky header to every element-scrolling table; tables
// without the scrolls class keep native sticky and get any leftover
// transform cleared. The thead stays in-flow, so it keeps scrolling
// horizontally with the wrapper - columns stay aligned.
function updateStickyHeads() {
  for (const wrap of content.querySelectorAll(':scope > .table-wrap')) {
    const head = wrap.querySelector('thead');
    if (!head) continue;
    if (!wrap.classList.contains('scrolls')) {
      head.style.transform = '';
      continue;
    }
    const rect = wrap.querySelector('table').getBoundingClientRect();
    const offset = stickyHeadOffset(
      window.scrollY, rect.top + window.scrollY, rect.height,
      head.getBoundingClientRect().height);
    head.style.transform = offset > 0 ? 'translateY(' + offset + 'px)' : '';
  }
}

function rebuildMinimap() {
  // Visibility first: while the rail is display:none its clientWidth is 0,
  // which would bake a scale of 0 into the clone on the very first render.
  const needed = minimapCfg.enabled
    && document.documentElement.scrollHeight - window.innerHeight > 0;
  document.body.classList.toggle('has-minimap', needed);
  // After the has-minimap toggle (the breakout cap depends on it) and before
  // measuring: wrapper scrollbars change content height. rebuildMinimap runs
  // on render, config and resize - exactly the moments the cap can change.
  updateTableScroll();
  updateStickyHeads();
  mapContent.innerHTML = '';
  if (!needed) return;
  const clone = content.cloneNode(true);
  for (const input of clone.querySelectorAll('input')) input.disabled = true;
  // cloneNode duplicates every heading id into the minimap; duplicate ids are
  // invalid HTML, so strip them from the clone. (The anchor lookup is separately
  // scoped to #content, so the clone could never win it either.)
  for (const el of clone.querySelectorAll('[id]')) el.removeAttribute('id');
  // The clone must not freeze the emulated sticky state: the minimap shows
  // the document, not the current header pin.
  for (const head of clone.querySelectorAll('thead')) head.style.transform = '';
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

// Geometric slider hit test from the live mapping (same math as
// updateMinimap), NOT from CSS: with showSlider 'mouseover' the slider is
// only visually hidden and must stay grabbable.
function sliderHit(railY) {
  const top = window.scrollY * mapSy + mapOffset;
  const height = Math.max(12, window.innerHeight * mapSy);
  return railY >= top && railY <= top + height ? railY - top : null;
}

// Rail-px offset between the pointer and the slider top while the slider is
// grabbed; null while a rail (centering) drag is active.
let grabOffset = null;

minimap.addEventListener('pointerdown', (e) => {
  e.preventDefault();
  minimap.classList.add('dragging');
  minimap.setPointerCapture(e.pointerId);
  // Like the editor minimap: grabbing the slider itself must not jump - the
  // viewport moves only relative to the grab point. Clicks on the rail
  // outside the slider keep the centering jump (and keep centering while
  // held).
  grabOffset = sliderHit(e.clientY - minimap.getBoundingClientRect().top);
  if (grabOffset === null) minimapNavigate(e.clientY);
});
minimap.addEventListener('pointermove', (e) => {
  if (!minimap.classList.contains('dragging')) return;
  if (grabOffset === null) { minimapNavigate(e.clientY); return; }
  const sliderTop = e.clientY - minimap.getBoundingClientRect().top - grabOffset;
  window.scrollTo(window.scrollX, (sliderTop - mapOffset) / mapSy);
});
minimap.addEventListener('pointerup', (e) => {
  minimap.classList.remove('dragging');
  minimap.releasePointerCapture(e.pointerId);
  grabOffset = null;
});
window.addEventListener('resize', rebuildMinimap, { passive: true });

vscode.postMessage({ type: 'ready' });
