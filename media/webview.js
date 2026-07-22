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

// Scroll the window to a document-y position. Smooth for deliberate jumps
// (TOC clicks); instant for the internal anchor links so the source editor
// mirrors the final position immediately (as before the TOC existed).
function scrollWindowTo(top, smooth) {
  if (smooth) window.scrollTo({ top, left: window.scrollX, behavior: 'smooth' });
  else window.scrollTo(window.scrollX, top);
}

// Resolve a "#slug" fragment to a heading inside #content and scroll to it.
// Returns true when a target was found and scrolled to. Shared by the content
// anchor links and the TOC entries. The lookup is scoped to #content (the
// skeleton carries its own ids), guards the empty hash, and tolerates a
// malformed percent-escape (a raw HTML anchor may carry one).
function navigateToHash(fragment, smooth) {
  let hash = fragment;
  try { hash = decodeURIComponent(hash); } catch (_) { /* keep the literal hash */ }
  const target = hash ? content.querySelector('#' + CSS.escape(hash)) : null;
  if (!target) return false;
  scrollWindowTo(absTop(target), smooth);
  return true;
}

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
    rebuildToc(); // new headings -> rebuild the TOC and re-run the scroll-spy
  } else if (e.data.type === 'config') {
    document.documentElement.style.setProperty('--mc-max-width', e.data.maxWidth);
    applyPreviewCfg(e.data);
    applyMinimapCfg(e.data.minimap); // rebuilds; column width drives the scale
    applyTocCfg(e.data.toc);
    tocMaxWidthPx = resolveCssWidthPx(e.data.maxWidth); // rail-fit threshold input
    updateTocLayout(); // side (opposite the minimap) + rail/fab decision
  } else if (e.data.type === 'scrollTo') {
    // Source editor was scrolled -> mirror the fractional position.
    // Suppress the echo from our own scrolling.
    suppressScrollEvents = Date.now() + 200;
    scrollToSourceLine(e.data.line);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  // An open TOC overlay swallows Escape (close it first); otherwise Escape
  // clears the task selection as before.
  if (tocOpen) { setTocOpen(false); return; }
  selection.clear();
  applySelection();
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
    // Internal anchors do not self-navigate in a webview: resolve and scroll
    // (instant, so the source editor mirrors it at once). A missing target is
    // left alone - no scroll, no fallthrough to the task-toggle logic below.
    if (navigateToHash(link.getAttribute('href').slice(1), false)) e.preventDefault();
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
    scrollSpy.update(); // active heading tracks the scroll position
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
// A viewport resize rebuilds the minimap (clone scale) and re-decides the TOC
// rail/fab split; heading positions shift with reflow, so refresh their cached
// tops and re-run the scroll-spy.
function onViewportResize() {
  rebuildMinimap();
  scrollSpy.refreshMetrics();
  updateTocLayout();
  scrollSpy.update();
}
window.addEventListener('resize', onViewportResize, { passive: true });

// --- Scroll-spy: active heading + ancestor chain (shared base) ---------------
//
// A small, self-contained module that tracks which heading the reader is
// currently under (the last one scrolled past an activation line near the top)
// and that heading's ancestor chain (h1..h6 hierarchy), and notifies
// subscribers on change. The TOC rail/FAB below is the first consumer; the
// breadcrumb + sticky-scroll stack (#44) subscribes to the same signal.
//
// IntersectionObserver drives the "a heading crossed the activation line"
// trigger; the active index itself is decided by geometry (pure functions
// below) so it stays correct when several or no headings are on screen. The
// existing scroll rAF also pumps update(), so the highlight tracks every frame.

// Index of the active heading: the last one whose top edge has scrolled above
// the activation line (scrollY + offset). -1 when none has (reader is above
// the first heading). Pure; unit-tested.
function activeHeadingIndex(tops, scrollY, offset) {
  const line = scrollY + offset;
  let active = -1;
  for (let i = 0; i < tops.length; i++) {
    if (tops[i] <= line + 1) active = i; else break;
  }
  return active;
}

// Ancestor chain of a heading = itself plus, walking upward, the nearest
// preceding heading of each strictly smaller level. Returns indices root-first.
// Handles level jumps (h1 -> h4): it simply takes the nearest shallower
// heading, whatever its level. Pure; unit-tested.
function ancestorChain(levels, index) {
  if (index < 0 || index >= levels.length) return [];
  const chain = [index];
  let minLevel = levels[index];
  for (let i = index - 1; i >= 0 && minLevel > 1; i--) {
    if (levels[i] < minLevel) { chain.unshift(i); minLevel = levels[i]; }
  }
  return chain;
}

const scrollSpy = (() => {
  let headings = [];   // [{ el, id, level, text, top }] in document order
  // Flat caches of the tops and levels, rebuilt on collect and (tops) on
  // refreshMetrics only. update() runs in the scroll hot path, so it reads
  // these instead of allocating a fresh array every frame.
  let tops = [];
  let levels = [];
  let active = -1;
  let observer = null;
  const subscribers = [];

  // (Re)read the headings from the rendered content and (re)observe them.
  function collect() {
    if (observer) { observer.disconnect(); observer = null; }
    headings = [...content.querySelectorAll('h1,h2,h3,h4,h5,h6')].map((el) => ({
      el,
      id: el.id,
      level: Number(el.tagName.slice(1)),
      text: (el.textContent || '').trim(),
      top: absTop(el)
    }));
    tops = headings.map((h) => h.top);
    levels = headings.map((h) => h.level);
    active = -1;
    if (typeof IntersectionObserver === 'function' && headings.length) {
      // The activation band is the top of the viewport; a heading entering it
      // retriggers the geometry decision. rootMargin shrinks the root to that
      // band so the callback fires as headings cross the top, not the bottom.
      observer = new IntersectionObserver(() => update(), {
        rootMargin: '0px 0px -70% 0px', threshold: 0
      });
      for (const h of headings) observer.observe(h.el);
    }
  }

  // Re-measure cached tops after a reflow (resize, image load) - tops are
  // document coordinates, so they only change on layout, not on scroll.
  function refreshMetrics() {
    for (let i = 0; i < headings.length; i++) tops[i] = headings[i].top = absTop(headings[i].el);
  }

  function emit() {
    const info = { active, chain: ancestorChain(levels, active), headings };
    for (const fn of subscribers) fn(info);
  }

  // Recompute the active heading; notify subscribers only when it changes.
  // Hot path (scroll rAF): reads the cached tops, allocates nothing.
  function update() {
    const idx = activeHeadingIndex(tops, window.scrollY, ACTIVATION_OFFSET);
    if (idx === active) return;
    active = idx;
    emit();
  }

  function onChange(fn) { subscribers.push(fn); }

  return {
    collect, refreshMetrics, update, onChange,
    get headings() { return headings; },
    get active() { return active; }
  };
})();

// --- Table of contents: sticky rail, FAB + overlay fallback ------------------

const ACTIVATION_OFFSET = 8; // px below the viewport top where a heading counts as reached
const TOC_RESERVE = 240;     // body padding reserved on the TOC side in rail mode
const TOC_SIDE_MARGIN = 32;  // the plain 2em gutter on the non-minimap side
const MINIMAP_RESERVE = 104; // matches body.has-minimap padding (88px rail + gap)

const tocPanel = document.getElementById('toc');
const tocList = document.getElementById('toc-list');
const tocFab = document.getElementById('toc-fab');
const tocBackdrop = document.getElementById('toc-backdrop');
let tocCfg = { enabled: true, mode: 'auto' };
let tocMaxWidthPx = 980;      // resolved content max-width, the rail-fit input
let tocOpen = false;          // overlay open (fab mode only)
let tocLinks = [];            // per heading index: its rail <a>
let tocBranches = [];         // per heading index: its child <ol> (or null)

// The rail fits when the viewport can hold the centered content column plus the
// TOC rail and the opposite-side rail/gutter, side by side. Pure; unit-tested.
function railFits(viewportWidth, contentWidth, tocReserve, sideReserve) {
  return viewportWidth >= contentWidth + tocReserve + sideReserve;
}

// Resolve a CSS width value (the configured content max-width) to pixels. px is
// parsed directly; a font-relative value (72ch) is measured with a hidden probe
// and falls back to a ~8px/ch estimate if measurement is unavailable.
function resolveCssWidthPx(value) {
  const parsed = parseFloat(value);
  if (/px\s*$/.test(String(value))) return parsed;
  try {
    const probe = document.createElement('div');
    probe.style.cssText = 'position:absolute;visibility:hidden;height:0;width:' + value;
    document.body.appendChild(probe);
    const w = probe.getBoundingClientRect().width;
    probe.remove();
    if (w && isFinite(w)) return w;
  } catch (_) { /* no layout available (headless) -> estimate below */ }
  return parsed * 8;
}

// Nested tree of heading indices, honoring level jumps: a deeper heading nests
// under the current node, a shallower/equal one pops back up. Each node is
// { idx, level, children }. Pure; unit-tested.
function tocTree(levels) {
  const root = { idx: -1, level: 0, children: [] };
  const stack = [root];
  levels.forEach((level, idx) => {
    while (stack.length > 1 && level <= stack[stack.length - 1].level) stack.pop();
    const node = { idx, level, children: [] };
    stack[stack.length - 1].children.push(node);
    stack.push(node);
  });
  return root.children;
}

// Store the TOC flags defensively (undefined must not disable it or force a
// mode), mirroring the minimap config handling.
function applyTocCfg(cfg) {
  tocCfg = Object.assign({ enabled: true, mode: 'auto' }, cfg || {});
  if (tocCfg.enabled === undefined) tocCfg.enabled = true;
  if (tocCfg.mode !== 'rail' && tocCfg.mode !== 'fab') tocCfg.mode = 'auto';
}

// Render the heading tree into a list element, recording each link and each
// branch's child list for the active-state updates. Uses textContent (never
// innerHTML) so heading text can never inject markup into the TOC.
function renderTocInto(listEl, nodes, headings) {
  tocLinks = [];
  tocBranches = [];
  listEl.innerHTML = '';
  const build = (parentOl, node) => {
    const li = document.createElement('li');
    li.className = 'toc-item';
    const a = document.createElement('a');
    a.className = 'toc-link';
    a.href = '#' + headings[node.idx].id;
    a.dataset.idx = String(node.idx);
    a.textContent = headings[node.idx].text;
    li.appendChild(a);
    tocLinks[node.idx] = a;
    let childOl = null;
    if (node.children.length) {
      childOl = document.createElement('ol');
      childOl.className = 'toc-sublist';
      for (const c of node.children) build(childOl, c);
      li.appendChild(childOl);
    }
    tocBranches[node.idx] = childOl;
    parentOl.appendChild(li);
  };
  for (const n of nodes) build(listEl, n);
}

// Reflect the active heading + its ancestor chain: highlight the active entry,
// mark the ancestors on the path, expand only the active section (collapse the
// rest), and keep the active entry visible in a long panel.
function applyTocActive(info) {
  const inPath = new Set(info.chain);
  for (let i = 0; i < tocLinks.length; i++) {
    const a = tocLinks[i];
    if (!a) continue;
    a.classList.toggle('toc-active', i === info.active);
    a.classList.toggle('toc-in-path', inPath.has(i) && i !== info.active);
    const branch = tocBranches[i];
    if (branch) branch.classList.toggle('toc-collapsed', !inPath.has(i));
  }
  const activeLink = info.active >= 0 ? tocLinks[info.active] : null;
  if (activeLink && activeLink.scrollIntoView) activeLink.scrollIntoView({ block: 'nearest' });
}

// Open/close the FAB overlay (fab mode only). Reflected as body.toc-open and on
// the FAB's aria-expanded.
function setTocOpen(open) {
  tocOpen = !!open && document.body.classList.contains('toc-fab');
  document.body.classList.toggle('toc-open', tocOpen);
  if (tocFab) tocFab.setAttribute('aria-expanded', tocOpen ? 'true' : 'false');
}

// Decide the TOC side (opposite the minimap) and the rail/fab presentation, and
// hide everything when the TOC is disabled or the document has no headings.
function updateTocLayout() {
  const enabled = tocCfg.enabled && scrollSpy.headings.length > 0;
  document.body.classList.toggle('has-toc', enabled);
  document.body.classList.toggle('toc-left', minimapCfg.side !== 'left');
  if (!enabled) {
    document.body.classList.remove('toc-rail');
    document.body.classList.remove('toc-fab');
    setTocOpen(false);
    return;
  }
  let rail;
  if (tocCfg.mode === 'rail') rail = true;
  else if (tocCfg.mode === 'fab') rail = false;
  else rail = railFits(window.innerWidth, tocMaxWidthPx,
    TOC_RESERVE, minimapCfg.enabled ? MINIMAP_RESERVE : TOC_SIDE_MARGIN);
  document.body.classList.toggle('toc-rail', rail);
  document.body.classList.toggle('toc-fab', !rail);
  if (rail) setTocOpen(false); // leaving fab mode closes any open overlay
}

// Rebuild the TOC from the freshly rendered content (called on every render).
function rebuildToc() {
  scrollSpy.collect();
  const headings = scrollSpy.headings;
  renderTocInto(tocList, tocTree(headings.map((h) => h.level)), headings);
  updateTocLayout();
  scrollSpy.update(); // set the initial active entry for the new content
}

scrollSpy.onChange(applyTocActive);

// A click on a TOC entry jumps to its heading (smooth) via the shared anchor
// mechanism and closes the overlay if it was open.
tocPanel.addEventListener('click', (e) => {
  const link = e.target.closest('.toc-link');
  if (!link) return;
  e.preventDefault();
  navigateToHash(link.getAttribute('href').slice(1), true);
  if (tocOpen) setTocOpen(false);
});
tocFab.addEventListener('click', () => setTocOpen(!tocOpen));
tocBackdrop.addEventListener('click', () => setTocOpen(false));

// Content-box changes (image loads, minimap padding) shift heading positions
// and can flip the rail/fab threshold without a window resize.
if (typeof ResizeObserver === 'function') {
  new ResizeObserver(() => {
    scrollSpy.refreshMetrics();
    updateTocLayout();
    scrollSpy.update();
  }).observe(document.body);
}

vscode.postMessage({ type: 'ready' });
