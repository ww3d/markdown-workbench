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
// Combined pixel height of the breadcrumb + sticky-scroll bars (#33). Anchor
// jumps subtract it so a heading lands below the bars instead of behind them;
// 0 while both bars are hidden. Computed (not measured) by topBarsHeight in
// updateTopBars.
let topBarsOffset = 0;

// --- Fractional scroll sync (algorithms modeled on the built-in preview) ---

function absTop(el) { return el.getBoundingClientRect().top + window.scrollY; }

// Cached line-map entries and their document-coordinate tops. Tops change on
// layout (render / reflow), never on scroll, so they are read once per rebuild -
// sourceLineAtTop (the scroll hot path) then binary-searches the cached tops
// instead of calling getBoundingClientRect on every [data-line] element each
// frame (O(N) forced layout per frame on a large document). Entries are in
// document order, which for normal-flow block content means non-decreasing tops.
const lineMetrics = (() => {
  let entries = []; // { el, line, endLine }
  let tops = [];    // document-coordinate top of entries[i], ascending
  let heights = []; // its height (both read once per rebuild, never on scroll)
  function measure(el) {
    const rect = el.getBoundingClientRect();
    return { top: rect.top + window.scrollY, height: rect.height };
  }
  function collect() {
    entries = [...content.querySelectorAll('[data-line]')].map((el) => ({
      el, line: Number(el.dataset.line),
      endLine: el.dataset.lineEnd ? Number(el.dataset.lineEnd) : undefined
    }));
    tops = []; heights = [];
    for (const e of entries) { const m = measure(e.el); tops.push(m.top); heights.push(m.height); }
  }
  function refresh() {
    for (let i = 0; i < entries.length; i++) { const m = measure(entries[i].el); tops[i] = m.top; heights[i] = m.height; }
  }
  return {
    collect, refresh,
    get entries() { return entries; }, get tops() { return tops; }, get heights() { return heights; }
  };
})();

// Largest index i with sorted[i] <= value, or -1. Allocation-free binary search
// over the ascending line tops; equal tops resolve to the last (deepest) entry.
function lastIndexAtOrBelow(sorted, value) {
  let lo = 0, hi = sorted.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (sorted[mid] <= value) { ans = mid; lo = mid + 1; } else { hi = mid - 1; }
  }
  return ans;
}

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
  // Land below the fixed top bars using the TARGET heading's own bars height (its
  // published scroll-margin-top), not the transient global topBarsOffset: on the
  // first navigation from the top the active chain - and thus the sticky stack -
  // is not built yet, so the global offset lands the heading a few px off and it
  // shifts once the stack appears (#44). Falls back to the global offset when the
  // heading carries no per-heading margin yet (bars off / before the first render).
  const perHeading = target.style ? parseFloat(target.style.scrollMarginTop) : NaN;
  const offset = isNaN(perHeading) ? topBarsOffset : perHeading;
  scrollWindowTo(Math.max(0, absTop(target) - offset), smooth);
  return true;
}

// Scroll so that the (fractional) source line sits at the viewport top.
function scrollToSourceLine(line) {
  if (line <= 0) { window.scrollTo(window.scrollX, 0); return; }
  const entries = lineMetrics.entries;
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
  const entries = lineMetrics.entries, tops = lineMetrics.tops, heights = lineMetrics.heights;
  if (!entries.length) return null;
  const offset = window.scrollY;
  // Fully cached: previous = last entry at or above the viewport top (binary
  // search, not an O(N) scan), and its top/height come from the cache - NO
  // getBoundingClientRect here. That read used to force a full-document layout
  // every frame (the minimap slider and top bars write styles earlier in the same
  // frame), which was the real scroll stutter on large documents.
  const p = lastIndexAtOrBelow(tops, offset + 1);
  if (p < 0) return 0;
  const previous = entries[p];
  const previousTop = tops[p];
  const height = heights[p];
  if (previous.endLine && previous.endLine > previous.line && height > 0
      && offset <= previousTop + height) {
    // Inside a multi-line code block.
    const progress = (offset - previousTop) / height;
    return previous.line + progress * (previous.endLine - previous.line);
  }
  const next = p + 1 < entries.length ? entries[p + 1] : null;
  if (next) {
    const nextTop = tops[p + 1];
    if (nextTop > previousTop) {
      const progress = (offset - previousTop) / (nextTop - previousTop);
      return previous.line + Math.min(1, Math.max(0, progress)) * (next.line - previous.line);
    }
  }
  if (height > 0) {
    return previous.line + Math.min(1, Math.max(0, (offset - previousTop) / height));
  }
  return previous.line;
}

window.addEventListener('message', (e) => {
  if (e.data.type === 'render') {
    content.innerHTML = e.data.html;
    convertInternalAnchors(); // in-page [..](#id) links -> buttons, so no native #id jump (#44)
    injectFoldToggles();   // a fold control on each foldable heading (#44 P2)
    applyFolds();          // re-apply persisted folds (they survive a re-render, like VS Code)
    lineMetrics.collect(); // cache the new [data-line] tops for the scroll-sync hot path
    applySelection();
    rebuildMinimap();
    rebuildToc(); // new headings -> rebuild the TOC and re-run the scroll-spy
    refreshScrollingHeads(); // re-measure now the breadcrumb padding (has-breadcrumb) is applied
    updateStickyHeads();
  } else if (e.data.type === 'config') {
    // Persist the document URI so VS Code can restore this preview panel after a
    // restart (read back by the panel serializer, views.js). Guarded: the DOM
    // test harness provides no setState.
    if (e.data.documentUri && vscode.setState) vscode.setState({ documentUri: e.data.documentUri });
    document.documentElement.style.setProperty('--mc-max-width', e.data.maxWidth);
    applyPreviewCfg(e.data);
    applyMinimapCfg(e.data.minimap); // rebuilds; column width drives the scale
    applyTocCfg(e.data.toc);
    applyTopBarsCfg(e.data.breadcrumb, e.data.stickyScroll);
    tocMaxWidthPx = resolveCssWidthPx(e.data.maxWidth); // rail-fit threshold input
    updateTocLayout(); // side (opposite the minimap) + rail/fab decision
    // Apply the new top-bar flags at once (force-emit), like updateTocLayout for
    // the TOC: scrollSpy.update() alone emits only when the active heading
    // changes, so a live enabled-toggle would otherwise wait for the next scroll.
    scrollSpy.update(true);
    publishHeadingScrollMargins(); // enabling/disabling a bar changes each heading's dock height
    refreshScrollingHeads(); // width/bar changes shift the cached table tops
    updateStickyHeads();
  } else if (e.data.type === 'scrollTo') {
    // Source editor was scrolled -> mirror the fractional position.
    // Suppress the echo from our own scrolling.
    suppressScrollEvents = Date.now() + 200;
    scrollToSourceLine(e.data.line);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  // An open breadcrumb dropdown or TOC overlay swallows Escape (close it
  // first); otherwise Escape clears the task selection as before.
  if (dropdownIdx >= 0) { closeDropdown(); return; }
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

// Convert in-page anchors ([..](#id)) to buttons so the webview performs NO native
// #id fragment jump: strip the href (which triggers the jump), keep the id in
// data-id, and tag them .mw-anchor for the click handler. External and cross-file
// links (href not starting with '#', and the bare '#') are left untouched. Run once
// per render, before the metrics are measured.
function convertInternalAnchors() {
  const anchors = content.querySelectorAll ? content.querySelectorAll('a[href^="#"]') : [];
  for (const a of anchors) {
    const href = a.getAttribute ? a.getAttribute('href') : null;
    if (!href || href === '#') continue; // a bare "#" is not a navigable target
    a.dataset.id = href.slice(1);
    if (a.removeAttribute) a.removeAttribute('href');
    a.setAttribute('role', 'button');
    if (a.classList) a.classList.add('mw-anchor');
  }
}

// Delegated click handling: innermost task row wins (nested tasks bubble).
content.addEventListener('click', (e) => {
  // A click on a heading's fold control toggles that section (folds the rendered
  // content), synced with the sticky-row twistie (#44 P2). Handled before the
  // anchor/task logic so it never navigates or toggles a task.
  const foldToggle = e.target.closest('.mw-fold-toggle');
  if (foldToggle) { e.preventDefault(); e.stopPropagation(); toggleFold(foldToggle.dataset.foldId); return; }
  // Internal anchors are converted to buttons at render (convertInternalAnchors):
  // .mw-anchor with the id in data-id and no href. So navigateToHash - scoped to
  // #content, CSS.escaped, collision-safe - is the SOLE scroll. As real <a href>
  // they also triggered the webview's native #id jump, a second scroll to a
  // rounding-different spot that shifted the whole view 2-4px once the bars gave
  // headings a scroll-margin (#44). The scroll listener still reports the new
  // position so the source editor follows. Cross-file (./other.md#x) and external
  // (http[s]://) links keep their href and the browser default.
  const link = e.target.closest('.mw-anchor'); // not the module-level `anchor` (task shift-range)
  if (link) {
    e.preventDefault();
    navigateToHash(link.dataset.id, false); // instant; a missing target is a no-op
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
    updateMinimap(); // always - also for editor-driven (suppressed) scrolls
    scrollSpy.update(); // active heading tracks the scroll; refreshes the header inset first
    updateStickyHeads(); // emulated wide-table pin - uses the inset just refreshed above
    if (Date.now() < suppressScrollEvents) return;
    maybePostScrolled();
  });
}, { passive: true });

// The 'scrolled' message drives a revealRange on the host (IPC + host work) - at
// ~60Hz in both directions a big source file lags. It is coalesced to ~30Hz with
// a delta gate: skip a sub-line change, post immediately once the window has
// elapsed, else defer a single trailing post so the final rest position always
// syncs (last value wins).
const SCROLL_POST_MIN_INTERVAL = 33; // ms, ~30Hz
const SCROLL_LINE_EPSILON = 0.01;    // fractional-line delta below which a post is pointless
let lastPostedLine = -1;
let lastPostTime = 0;
let scrollTrailingTimer = null;

// Pure decision: 'skip' (no meaningful move), 'post' (window elapsed), or
// 'defer' (within the window -> trailing post). Unit-tested.
function scrollPostDecision(line, lastLine, now, lastTime, minIntervalMs, epsilon) {
  if (lastLine >= 0 && Math.abs(line - lastLine) < epsilon) return 'skip';
  return now - lastTime >= minIntervalMs ? 'post' : 'defer';
}

function sendScrolled(line) {
  lastPostedLine = line;
  lastPostTime = Date.now();
  vscode.postMessage({ type: 'scrolled', line: Math.max(0, line) });
}

function maybePostScrolled() {
  const line = sourceLineAtTop();
  if (line === null) return;
  const decision = scrollPostDecision(line, lastPostedLine, Date.now(), lastPostTime,
    SCROLL_POST_MIN_INTERVAL, SCROLL_LINE_EPSILON);
  if (decision === 'skip') return;
  if (decision === 'post') {
    if (scrollTrailingTimer) { clearTimeout(scrollTrailingTimer); scrollTrailingTimer = null; }
    sendScrolled(line);
    return;
  }
  if (!scrollTrailingTimer) { // defer: one trailing post with the latest position
    scrollTrailingTimer = setTimeout(() => {
      scrollTrailingTimer = null;
      if (Date.now() < suppressScrollEvents) return;
      const latest = sourceLineAtTop();
      if (latest === null) return;
      if (lastPostedLine >= 0 && Math.abs(latest - lastPostedLine) < SCROLL_LINE_EPSILON) return;
      sendScrolled(latest);
    }, SCROLL_POST_MIN_INTERVAL);
  }
}

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
// Toggle the .scrolls class on wide tables (runs on render / config / resize, not
// per scroll) and record whether any table needs the emulated header, so the
// scroll hot path can skip updateStickyHeads' DOM query entirely when none do.
// A table that just stopped scrolling gets its leftover thead transform cleared
// here, so the hot-path skip never leaves a stale pin.
// Cached geometry of the tables that need the emulated header: the document top,
// the table height and the header height are layout values, so they change on
// render/config/resize, never on scroll. Caching them here lets updateStickyHeads
// run from plain numbers on the scroll path - no getBoundingClientRect, which
// forced a synchronous layout every frame and froze scrolling on table-heavy
// documents.
let scrollingHeads = [];
function updateTableScroll() {
  scrollingHeads = [];
  for (const wrap of content.querySelectorAll(':scope > .table-wrap')) {
    const scrolls = wrap.scrollWidth > wrap.clientWidth;
    wrap.classList.toggle('scrolls', scrolls);
    const head = wrap.querySelector('thead');
    if (head) head.style.transform = ''; // clear before measuring (and clear a stopped-scrolling pin)
    if (!scrolls || !head) continue;
    scrollingHeads.push({ head, table: wrap.querySelector('table'), tableTop: 0, tableHeight: 0, headHeight: 0 });
  }
  refreshScrollingHeads();
}

// Re-measure the cached table geometry after a reflow. The dock offset depends on
// the table's document top, which the breadcrumb's body padding-top shifts - and
// that padding is applied (has-breadcrumb) after updateTableScroll first runs, so
// the render path re-measures here once the bars are up. Also on resize/image
// reflow, mirroring scrollSpy.refreshMetrics.
function refreshScrollingHeads() {
  for (const t of scrollingHeads) {
    t.tableTop = absTop(t.table);
    t.tableHeight = t.table.getBoundingClientRect().height;
    t.headHeight = t.head.getBoundingClientRect().height;
  }
}

// Vertical header offset for an element-scrolling table: inside a scrolls
// wrapper the wrapper is the th's scrollport, so native position: sticky is
// inert against the window scroll - the pin is emulated by translating the
// thead. topInset docks the pin below the top bars (the constant stickyHeadInsetPx,
// a plain JS number - no CSS-var write), mirroring the native path. Clamped to
// [0, tableHeight - headHeight] so the header stops at the table's bottom edge
// instead of ghosting below it. Document coordinates.
function stickyHeadOffset(scrollY, tableTop, tableHeight, headHeight, topInset) {
  return Math.max(0, Math.min(scrollY + topInset - tableTop, tableHeight - headHeight));
}

// Apply the emulated sticky header to every element-scrolling table, from the
// cached geometry - no DOM query, no getBoundingClientRect, so the scroll hot
// path forces no layout. The thead stays in-flow, so it keeps scrolling
// horizontally with the wrapper - columns stay aligned.
function updateStickyHeads() {
  if (!scrollingHeads.length) return; // no element-scrolling table -> nothing to emulate
  const scrollY = window.scrollY;
  for (const t of scrollingHeads) {
    const offset = stickyHeadOffset(scrollY, t.tableTop, t.tableHeight, t.headHeight, stickyHeadInsetPx);
    t.head.style.transform = offset > 0 ? 'translateY(' + offset + 'px)' : '';
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
  lineMetrics.refresh(); // reflow shifts the cached line tops
  refreshScrollingHeads(); // reflow shifts the cached table tops too
  updateTocLayout();
  scrollSpy.update(); // bar heights are constant, so no rebuild is needed here
  updateStickyHeads();
}
window.addEventListener('resize', onViewportResize, { passive: true });

// --- Content section folding (#44 P2) ---------------------------------------
//
// Fold state keyed by heading id, preserved across re-renders (re-applied after
// each render, like VS Code folding survives edits). A heading's section is every
// following block up to the next heading of the same or a higher level; folding
// hides those blocks. Reachable from the document fold control and (P2 part 2) the
// sticky-row twistie, kept in sync. The height change is absorbed by re-running the
// existing layout refresh (onViewportResize) - the minimap and scroll-sync logic
// itself is untouched, only its refresh is triggered.
const foldedIds = new Set();

// Which blocks are hidden given the folded heading ids: a block is hidden iff it
// sits inside a folded heading's section, with nesting handled by a level stack (a
// folded ancestor hides a folded descendant's blocks too). The folded heading
// itself stays visible (it carries the collapsed chevron). Pure; unit-tested.
function computeFoldHidden(blocks, folded) {
  const hidden = new Array(blocks.length);
  const stack = []; // levels of folded headings whose section we are currently inside
  for (let i = 0; i < blocks.length; i++) {
    const level = blocks[i].level;
    if (level > 0) {
      while (stack.length && stack[stack.length - 1] >= level) stack.pop();
      hidden[i] = stack.length > 0;
      if (folded.has(blocks[i].id)) stack.push(level);
    } else {
      hidden[i] = stack.length > 0;
    }
  }
  return hidden;
}

// Whether the heading at index i is foldable: it has a following block before the
// next heading of the same or a higher level (an empty section is not foldable).
// Pure; unit-tested.
function isFoldable(blocks, i) {
  const next = blocks[i + 1];
  return !!next && !(next.level > 0 && next.level <= blocks[i].level);
}

// The content's direct children as {el, level (0 = non-heading), id} in order.
function contentBlocks() {
  const kids = content.children ? [...content.children] : [];
  return kids.map((el) => {
    const m = /^H([1-6])$/.exec(el.tagName || '');
    return { el, level: m ? Number(m[1]) : 0, id: el.id };
  });
}

// Prepend a fold control to every foldable heading (idempotent: skips one that
// already has it, so a re-render does not stack controls).
function injectFoldToggles() {
  const blocks = contentBlocks();
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];
    if (b.level === 0 || !isFoldable(blocks, i)) continue;
    if (b.el.querySelector && b.el.querySelector('.mw-fold-toggle')) continue;
    const t = document.createElement('span');
    t.className = 'mw-fold-toggle codicon codicon-chevron-right';
    t.setAttribute('role', 'button');
    t.setAttribute('aria-hidden', 'true');
    t.dataset.foldId = b.id;
    if (b.el.insertBefore) b.el.insertBefore(t, b.el.firstChild);
  }
}

function setBlockHidden(el, hidden) {
  if (el && el.classList) el.classList.toggle('mw-fold-hidden', hidden);
}

// Reflect a heading's own fold control (chevron rotation) from the fold state.
function reflectFoldToggle(headingEl, folded) {
  const t = headingEl && headingEl.querySelector && headingEl.querySelector('.mw-fold-toggle');
  if (t && t.classList) t.classList.toggle('mw-folded', folded);
}

// Hide/show every content block from the current fold set and reflect each
// heading's chevron. O(blocks); run on a toggle and after a render, never in the
// scroll hot path.
function applyFolds() {
  const blocks = contentBlocks();
  const hidden = computeFoldHidden(blocks, foldedIds);
  for (let i = 0; i < blocks.length; i++) {
    setBlockHidden(blocks[i].el, hidden[i]);
    if (blocks[i].level > 0) reflectFoldToggle(blocks[i].el, foldedIds.has(blocks[i].id));
  }
}

// Toggle a heading's fold and re-apply. The hidden blocks change the rendered
// height, so the existing layout refresh re-measures the minimap, scroll-spy and
// line-metric tops (their logic is untouched - only re-run).
function toggleFold(id) {
  if (!id) return;
  if (foldedIds.has(id)) foldedIds.delete(id);
  else foldedIds.add(id);
  applyFolds();
  onViewportResize();
}

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
// its activation line (scrollY + offset + its own inset). -1 when none has
// (reader is above the first heading). Each heading docks below a bar stack of
// its own depth, so its activation line is per-heading, not one global line -
// this is what keeps the highlight on the heading a #id jump actually lands on,
// whatever depth it is (#44). `insets` is optional: absent, every heading shares
// the flat `offset` line (the pre-top-bars behaviour). Pure; unit-tested.
function activeHeadingIndex(tops, scrollY, offset, insets) {
  let active = -1;
  for (let i = 0; i < tops.length; i++) {
    const line = scrollY + offset + (insets ? insets[i] : 0);
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
  // Height of fixed UI above the content (the #33 top bars). The activation line
  // sits below it, so a heading scrolled just under the bars counts as active -
  // which keeps the TOC/anchor highlight consistent with where navigateToHash
  // lands a target (it scrolls the target to just below the same bars). A
  // generic inset on the shared base, set by whichever consumer owns the bars.
  let topInset = 0;
  // Per-heading activation insets (px), one per heading in document order: the
  // bar-stack height under which THAT heading docks. When present (same length as
  // tops) they replace the flat topInset, so a deep heading is marked active only
  // once it clears its own taller stack - matching where a #id jump lands it.
  // Set by the bar owner on render/config; layout-stable, so scroll never rewrites it.
  let insets = [];
  const subscribers = [];

  // (Re)read the headings from the rendered content. No IntersectionObserver:
  // the scroll rAF pumps update() every frame already, so an IO on every heading
  // would only fire redundant callbacks during a drag (and on a large document
  // it observes hundreds of nodes). update() is driven by scroll / render /
  // resize instead - the single trigger that is actually needed.
  function collect() {
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
  // Hot path (scroll rAF): reads the cached tops, allocates nothing. `force`
  // emits even when the index is unchanged - used once after a rebuild so the
  // initial state (including active = -1, above the first heading) is applied
  // deterministically instead of leaving the freshly rendered TOC in its
  // default-expanded DOM state.
  function update(force) {
    const perHeading = insets.length === tops.length;
    const idx = activeHeadingIndex(tops, window.scrollY,
      ACTIVATION_OFFSET + (perHeading ? 0 : topInset), perHeading ? insets : null);
    if (idx === active && !force) return;
    active = idx;
    emit();
  }

  // Set the fixed top inset (px) used by the activation line. Stored only; the
  // next update() applies it, so setting it never re-enters the emit cycle. Falls
  // back to this flat line whenever no per-heading insets are set.
  function setTopInset(px) { topInset = px || 0; }

  // Set the per-heading activation insets (see `insets` above). A length that no
  // longer matches the current headings (stale array after a rebuild) is ignored
  // by update() until the next matching set, which keeps the flat fallback safe.
  function setInsets(arr) { insets = arr || []; }

  function onChange(fn) { subscribers.push(fn); }

  return {
    collect, refreshMetrics, update, onChange, setTopInset, setInsets,
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
const tocLinks = [];          // per heading index: its rail <a>
const tocBranches = [];       // per heading index: its child <ol> (or null)
let tocActiveIdx = -1;        // last highlighted index (delta baseline)
const tocActivePath = [];     // last in-path indices (delta baseline, reused)
// Sticky manual expand/collapse state (#48). Kept as small sets outside the
// scroll hot path; the automatic delta consults them (O(1) lookups) so it never
// re-expands a manually collapsed branch nor re-collapses a manually expanded
// one. Cleared on re-render (fresh tree).
const tocManualExpanded = new Set();
const tocManualCollapsed = new Set();

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
  tocLinks.length = 0;
  tocBranches.length = 0;
  listEl.innerHTML = '';
  const build = (parentOl, node) => {
    const li = document.createElement('li');
    li.className = 'toc-item';
    const a = document.createElement('a');
    a.className = 'toc-link';
    a.setAttribute('role', 'button'); // a control, not a native #id anchor (#44 follow-up)
    a.dataset.id = headings[node.idx].id;
    a.dataset.idx = String(node.idx);
    a.tabIndex = -1;
    // A fixed gutter carries the native codicon chevron twistie for a parent, or
    // stays empty for a leaf so labels align at each depth; the label is a
    // separate ellipsized span. A click on the gutter toggles, on the label
    // navigates (isChevronClick).
    const gutter = document.createElement('span');
    gutter.className = 'toc-gutter';
    if (node.children.length) {
      const twistie = document.createElement('i');
      twistie.className = 'codicon codicon-chevron-right toc-twistie';
      twistie.setAttribute('aria-hidden', 'true');
      gutter.appendChild(twistie);
    }
    a.appendChild(gutter);
    const label = document.createElement('span');
    label.className = 'toc-label';
    label.textContent = headings[node.idx].text;
    a.appendChild(label);
    li.appendChild(a);
    tocLinks[node.idx] = a;
    let childOl = null;
    if (node.children.length) {
      // The sublist is wrapped so the expand/collapse can animate via the
      // wrapper's grid-template-rows (0fr<->1fr) without a magic height.
      const wrap = document.createElement('div');
      wrap.className = 'toc-sublist-wrap';
      childOl = document.createElement('ol');
      // Collapsed by default; applyTocActive only expands the active path. This
      // lets the highlight run as an O(path) delta instead of an O(headings)
      // sweep per active-heading change (the fresh tree starts fully collapsed).
      childOl.className = 'toc-sublist';
      childOl.classList.add('toc-collapsed');
      for (const c of node.children) build(childOl, c);
      wrap.appendChild(childOl);
      li.appendChild(wrap);
    }
    tocBranches[node.idx] = childOl;
    parentOl.appendChild(li);
  };
  for (const n of nodes) build(listEl, n);
  // A fresh tree resets the delta baseline (nothing highlighted, all collapsed)
  // and the sticky manual state (#48: a re-render starts clean, like VS Code).
  tocActiveIdx = -1;
  tocActivePath.length = 0;
  tocManualExpanded.clear();
  tocManualCollapsed.clear();
}

// Reflect the active heading + its ancestor chain as a delta from the previous
// state: only the links whose active/in-path/collapsed status actually changed
// are touched (O(path depth), not O(headings)), so a fast scroll that crosses
// many headings does not re-sweep the whole tree each frame. The fresh tree is
// built fully collapsed (renderTocInto), so the first apply only expands the
// active path.
function applyTocActive(info) {
  const chain = info.chain;
  if (tocActiveIdx !== info.active) {
    const prev = tocLinks[tocActiveIdx];
    if (prev) prev.classList.toggle('toc-active', false);
    const next = tocLinks[info.active];
    if (next) next.classList.toggle('toc-active', true);
  }
  // Links that left the path: drop the marker, collapse their branch again -
  // unless the user manually expanded it (#48: sticky, stays open off the path).
  for (let k = 0; k < tocActivePath.length; k++) {
    const i = tocActivePath[k];
    if (!includesIndex(chain, i)) {
      const a = tocLinks[i]; if (a) a.classList.toggle('toc-in-path', false);
      const branch = tocBranches[i];
      if (branch && !tocManualExpanded.has(i)) branch.classList.toggle('toc-collapsed', true);
    }
  }
  // Links on the new path: mark ancestors, expand their branch - unless the user
  // manually collapsed it (#48: sticky, stays closed on the path).
  for (let k = 0; k < chain.length; k++) {
    const i = chain[k];
    const a = tocLinks[i]; if (a) a.classList.toggle('toc-in-path', i !== info.active);
    const branch = tocBranches[i];
    if (branch && !tocManualCollapsed.has(i)) branch.classList.toggle('toc-collapsed', false);
  }
  tocActiveIdx = info.active;
  tocActivePath.length = chain.length;
  for (let k = 0; k < chain.length; k++) tocActivePath[k] = chain[k];
  scheduleActiveReveal();
}

// Keep the active TOC entry visible without a forced reflow per active change.
// The old code called scrollIntoView synchronously on every change - during a
// fast drag that is a per-frame forced layout in the panel. This coalesces into
// a single rAF (separate from the class-toggle writes above, so no read follows
// a write), and scrolls only when the entry is actually outside the panel's
// viewport - a drag that keeps the active entry in view then costs no scroll.
let tocRevealPending = false;
function scheduleActiveReveal() {
  if (tocRevealPending) return;
  tocRevealPending = true;
  requestAnimationFrame(() => {
    tocRevealPending = false;
    const link = tocActiveIdx >= 0 ? tocLinks[tocActiveIdx] : null;
    if (!link || !link.getBoundingClientRect || !tocPanel.getBoundingClientRect) return;
    const panelRect = tocPanel.getBoundingClientRect();
    const linkRect = link.getBoundingClientRect();
    if (linkRect.top < panelRect.top || linkRect.bottom > panelRect.bottom) {
      if (link.scrollIntoView) link.scrollIntoView({ block: 'nearest' });
    }
  });
}

// Small-array membership test, allocation-free (chains are <= 6 entries).
function includesIndex(arr, value) {
  for (let k = 0; k < arr.length; k++) if (arr[k] === value) return true;
  return false;
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
  publishHeadingScrollMargins(); // per-heading scroll-margin so native #id jumps land right
  stickyTables = [...content.querySelectorAll('thead')]; // dock target for the table headers
  lastStickyHeadVar = ''; // fresh tables carry no inline var yet - force the next dock write
  renderTocInto(tocList, tocTree(headings.map((h) => h.level)), headings);
  updateTocLayout();
  scrollSpy.update(true); // force-apply the initial state (incl. active = -1)
}

scrollSpy.onChange(applyTocActive);

// Whether a click landed on an entry's twistie gutter (vs. its label). The
// twistie is a real node, so the hit is an exact ancestor check - a click on the
// codicon or its gutter toggles, a click on the label navigates. Pure.
function isChevronClick(e) {
  return !!(e.target && e.target.closest && e.target.closest('.toc-gutter'));
}

// Arm the sublist expand/collapse transition for a manual toggle only. The class
// enables the grid-template-rows transition (webview.css); a timer clears it so
// the scroll-driven auto expand/collapse (applyTocActive, hot path) stays instant
// - never a per-frame animation during a scroll.
let tocAnimateTimer = null;
function armTocAnimation() {
  document.body.classList.add('toc-animating');
  if (tocAnimateTimer !== null) clearTimeout(tocAnimateTimer);
  tocAnimateTimer = setTimeout(() => {
    document.body.classList.remove('toc-animating');
    tocAnimateTimer = null;
  }, 250);
}

// Manual expand/collapse of a TOC branch (#48), sticky against the scroll-spy
// automatic: what the user opened stays open, what they closed stays closed,
// until they toggle it again (a re-render resets it). Records the choice so
// applyTocActive skips this branch. Animated (armTocAnimation) because it is the
// manual path.
function toggleTocBranch(idx) {
  const branch = tocBranches[idx];
  if (!branch) return;
  const collapsed = branch.classList.contains('toc-collapsed');
  armTocAnimation();
  branch.classList.toggle('toc-collapsed', !collapsed);
  if (collapsed) { tocManualExpanded.add(idx); tocManualCollapsed.delete(idx); }
  else { tocManualCollapsed.add(idx); tocManualExpanded.delete(idx); }
}

// A click on the twistie of an entry that has children toggles it (manual,
// sticky); anything else - the label, or any click on a leaf entry - jumps to
// the heading (smooth) via navigateToHash and closes the overlay.
tocPanel.addEventListener('click', (e) => {
  const link = e.target.closest('.toc-link');
  if (!link) return;
  e.preventDefault();
  const idx = Number(link.dataset && link.dataset.idx);
  if (tocBranches[idx] && isChevronClick(e)) { toggleTocBranch(idx); return; }
  navigateToHash(link.dataset.id, true);
  if (tocOpen) setTocOpen(false);
});
tocFab.addEventListener('click', () => setTocOpen(!tocOpen));
tocBackdrop.addEventListener('click', () => setTocOpen(false));

// Content-box changes (image loads, minimap padding) shift heading positions
// and can flip the rail/fab threshold without a window resize.
if (typeof ResizeObserver === 'function') {
  new ResizeObserver(() => {
    scrollSpy.refreshMetrics();
    lineMetrics.refresh(); // image loads / reflow shift the cached line tops
    updateTocLayout();
    scrollSpy.update();
  }).observe(document.body);
}

// --- Breadcrumb + sticky-scroll stack (docs/DECISIONS.md #33) ----------------
//
// Two fixed bars pinned to the top of the content region, both consumers of the
// shared scroll-spy (no scroll-spy change): a single-line breadcrumb of the
// active heading's ancestor chain (each segment scrolls to its heading and
// opens a sibling picker), and, directly below it, a sticky-scroll stack of the
// same chain rendered as pinned heading rows (like VS Code's editor sticky
// scroll). The breadcrumb is a constant-height reserved bar; the stack overlays
// content without reserving space, so it swaps in place as the active section
// changes. At active = -1 (reader above the first heading) the breadcrumb is
// empty and the stack is hidden - deterministic via the rebuild's force-emit.

const breadcrumb = document.getElementById('breadcrumb');
const stickyScroll = document.getElementById('sticky-scroll');
const dropdown = document.getElementById('breadcrumb-dropdown');
const SCROLL_MARGIN_GAP = 8; // px breathing room below the bars for anchor jumps
// Fixed bar geometry (docs/DECISIONS.md #36). The bars have fixed heights in the
// stylesheet, so the stack height is *computed* (rows x row height), never
// measured - no getBoundingClientRect in the scroll path. These px values must
// match the stylesheet (#breadcrumb / .sticky-row heights); a contract test
// asserts they stay in sync.
const BREADCRUMB_HEIGHT_PX = 28; // #breadcrumb height (box-sizing: border-box)
const STICKY_ROW_HEIGHT_PX = 22; // .sticky-row height (box-sizing: border-box)
const MAX_STICKY_ROWS = 5;       // cap the pinned stack (VS Code bounds it too)

let breadcrumbCfg = { enabled: true };
let stickyCfg = { enabled: true };
let dropdownIdx = -1;   // heading index the open sibling dropdown belongs to; -1 = closed
let lastHeadings = [];  // headings from the last scroll-spy emit (dropdown source)

// Scroll-hot-path change detection. updateTopBars runs on every active-heading
// change; during a fast drag that is nearly every frame. It rebuilds the DOM
// only when something that affects the bars actually changed - a different
// chain, a different heading set (a re-render), or a structural bump (config /
// resize) - and then only incrementally. topBarsGen is the structural bump.
let topBarsGen = 0;
let renderedGen = -1;
let renderedHeadings = null;
const renderedChain = [];

// Store the bar flags defensively (undefined must never disable a bar), like the
// minimap/TOC config. Independent toggles: either bar can be off alone. A config
// change is a structural bump so the next emit rebuilds even if the chain is
// unchanged (e.g. a live enable/disable).
function applyTopBarsCfg(breadcrumbConfig, stickyConfig) {
  breadcrumbCfg = Object.assign({ enabled: true }, breadcrumbConfig || {});
  if (breadcrumbCfg.enabled === undefined) breadcrumbCfg.enabled = true;
  stickyCfg = Object.assign({ enabled: true }, stickyConfig || {});
  if (stickyCfg.enabled === undefined) stickyCfg.enabled = true;
  topBarsGen++; // the next (forced) emit rebuilds the bars and re-docks the header
}

// Sibling headings of `index`: the headings that share its parent and level, in
// document order (index itself included). Walking outward, a strictly shallower
// heading is the parent boundary and ends the run; deeper headings (children of
// a sibling) are skipped; equal-level headings are siblings. Handles level jumps
// (an h4 with no h2/h3 above bounds on the nearest shallower heading) and the
// single-child case (returns just [index]). Pure; unit-tested.
function siblingHeadings(levels, index) {
  if (index < 0 || index >= levels.length) return [];
  const level = levels[index];
  const out = [index];
  for (let i = index - 1; i >= 0; i--) {
    if (levels[i] < level) break;
    if (levels[i] === level) out.unshift(i);
  }
  for (let i = index + 1; i < levels.length; i++) {
    if (levels[i] < level) break;
    if (levels[i] === level) out.push(i);
  }
  return out;
}

// Combined top-bar height (px), computed from the fixed geometry - never
// measured, so there is no getBoundingClientRect in the scroll path (the round-6
// fix for the scroll freeze on large documents). Feeds topBarsOffset
// (navigateToHash) and the scroll-spy inset. Pure; unit-tested.
function topBarsHeight(breadcrumbShown, stickyRows) {
  return (breadcrumbShown ? BREADCRUMB_HEIGHT_PX : 0) + stickyRows * STICKY_ROW_HEIGHT_PX;
}

// Publish the constant CSS vars once. --breadcrumb-height positions the stack and
// reserves the body's top padding; --toc-scroll-margin is set once to the
// *maximum* stack height (breadcrumb + MAX_STICKY_ROWS x row + gap) so a scroll
// never rewrites it - and thus never invalidates every heading's scroll-margin
// style, which was the document-wide recalc behind the freeze. Our own navigation
// subtracts the exact offset itself; this var only coarsely catches native hash
// jumps, so an over-estimate is fine.
function publishTopBarVars() {
  const root = document.documentElement.style;
  root.setProperty('--breadcrumb-height', BREADCRUMB_HEIGHT_PX + 'px');
  root.setProperty('--toc-scroll-margin',
    (BREADCRUMB_HEIGHT_PX + MAX_STICKY_ROWS * STICKY_ROW_HEIGHT_PX + SCROLL_MARGIN_GAP) + 'px');
}

// Give each heading its OWN dock height (breadcrumb + its ancestor-chain depth in
// sticky rows) and publish it two ways: as the heading's scroll-margin-top AND as
// the scroll-spy's activation inset. A VS Code webview performs the native fragment
// jump when a control link (#id) is clicked, and preventDefault does not stop it, so
// that jump - not our navigateToHash - lands the final position, using the heading's
// scroll-margin-top. Feeding the SAME value to the activation line makes the landed
// heading the active one at every depth. (The earlier single-margin approach used the
// document-*maximum* for the margin but a lagging global inset for the activation line,
// so a #id jump from the top - stale inset 0 - marked the previous heading; and a
// per-heading margin alone still mismatched the flat activation line by a few pixels.)
// Both are layout-stable, written once per render/config, never on scroll.
function publishHeadingScrollMargins() {
  const headings = scrollSpy.headings;
  const levels = headings.map((h) => h.level);
  const breadcrumbShown = breadcrumbCfg.enabled && headings.length > 0;
  const insets = new Array(headings.length);
  for (let i = 0; i < headings.length; i++) {
    const rows = stickyCfg.enabled ? Math.min(ancestorChain(levels, i).length, MAX_STICKY_ROWS) : 0;
    const bars = topBarsHeight(breadcrumbShown, rows);
    insets[i] = bars;
    const el = headings[i].el;
    if (el && el.style) el.style.scrollMarginTop = bars + 'px';
  }
  // Same per-heading bars drive the activation line, so the heading a #id jump
  // lands (at its scroll-margin) is exactly the one the scroll-spy marks active.
  scrollSpy.setInsets(insets);
}

// Where the sticky table header docks: FLUSH under the *current* bars. The dock
// follows the live stack height (breadcrumb + the current chain's rows), so a
// shallow section docks the header directly under its shorter stack instead of
// under a document-wide maximum that left a visible gap. Set from updateTopBars,
// which recomputes it only when the chain changes; the write is value-gated, so a
// scroll that stays inside a section rewrites nothing. Every th consumes the var,
// so a *per-frame* write was the stutter - but a per-depth-crossing write is rare
// (a handful of tables on a real document) and measured smooth. Emulated
// wide-table headers read stickyHeadInsetPx.
let stickyHeadInsetPx = 0, lastStickyHeadVar = '';
let stickyTables = []; // the document's tables, cached per render (the only --sticky-head-top consumers)
function setStickyHeadInset(px) {
  stickyHeadInsetPx = px;
  const v = px + 'px';
  if (v === lastStickyHeadVar) return;
  lastStickyHeadVar = v;
  // Scope the write to the tables, not :root. --sticky-head-top is an inherited
  // custom property, so writing it on :root forces the WHOLE document tree to
  // re-resolve inheritance (measured: a 10x style-recalc blow-up on a large doc).
  // The tables are its only consumers, so each write invalidates just their small
  // thead subtrees.
  for (const t of stickyTables) t.style.setProperty('--sticky-head-top', v);
}

// Label for the root breadcrumb segment shown above the first heading: the
// document's leading H1 (its de-facto title) when present, else a neutral
// fallback. Pure; unit-tested.
function rootLabel(headings) {
  const first = headings[0];
  return first && first.level === 1 && first.text ? first.text : 'Document';
}

// Reconcile a bar's <a> children to exactly `count`, reusing existing nodes
// (create/remove only the delta) and calling setup(link, i) for each. Keeps the
// live nodes on the element so a same-count re-render only touches text/attrs,
// not the node list - no innerHTML reparse, minimal layout churn. Separators are
// pure CSS (.breadcrumb-seg::before), so there are no separator nodes to manage.
function reconcileLinks(barEl, count, setup) {
  const links = barEl._links || (barEl._links = []);
  while (links.length < count) {
    const link = document.createElement('a');
    // A control, not a link: no href, so the VS Code webview cannot run its
    // native (instant) #id jump that would override the smooth navigateToHash
    // (#44 follow-up). role="button" keeps the semantics; the target id lives in
    // data-id.
    link.setAttribute('role', 'button');
    link.tabIndex = -1;
    barEl.appendChild(link);
    links.push(link);
  }
  while (links.length > count) {
    const link = links.pop();
    if (link.remove) link.remove();
  }
  for (let i = 0; i < count; i++) setup(links[i], i);
}

// Set a link's class/href/index/text, skipping DOM writes that would not change
// anything (cached on the node) so an in-place re-render is cheap.
function setLink(link, className, id, idx, text) {
  if (link._cls !== className) { link.className = className; link._cls = className; }
  if (link._id !== id) { link.dataset.id = id; link._id = id; }
  const idxStr = String(idx);
  if (link.dataset.idx !== idxStr) link.dataset.idx = idxStr;
  if (link._text !== text) { link.textContent = text; link._text = text; }
}

// Set a breadcrumb segment: the label text lives in a child `.breadcrumb-label`
// span (built once) so the highlight/hover background is a pill around the text
// only, and the separator (a ::before on the segment, outside the label) sits
// between segments rather than inside a segment's highlight (#44 review 8). The
// segment itself is a fixed-height flex box, so every segment - highlighted or
// not, short label or long - has the same box height.
function setBreadcrumbSeg(link, className, id, idx, text) {
  if (link._cls !== className) { link.className = className; link._cls = className; }
  if (link._id !== id) { link.dataset.id = id; link._id = id; }
  const idxStr = String(idx);
  if (link.dataset.idx !== idxStr) link.dataset.idx = idxStr;
  if (!link._label) {
    const label = document.createElement('span');
    label.className = 'breadcrumb-label';
    link.appendChild(label);
    link._label = label;
  }
  if (link._text !== text) { link._label.textContent = text; link._text = text; }
}

// Render the breadcrumb: one segment per chain entry, or a single root segment
// above the first heading (sentinel index -1: no picker, click scrolls to top).
function renderBreadcrumb(chain, headings) {
  if (chain.length) {
    reconcileLinks(breadcrumb, chain.length, (link, i) => {
      const heading = headings[chain[i]];
      setBreadcrumbSeg(link, 'breadcrumb-seg', heading.id, chain[i], heading.text);
    });
  } else {
    reconcileLinks(breadcrumb, 1, (link) =>
      setBreadcrumbSeg(link, 'breadcrumb-seg breadcrumb-root', '', -1, rootLabel(headings)));
  }
}

// Render the sticky-scroll stack: one pinned row per chain entry (root-first),
// classed by heading level for the indent/size, capped at MAX_STICKY_ROWS (the
// nearest ancestors kept; the full path stays in the breadcrumb). Returns the
// number of rows rendered, for the computed height. No layout read.
function renderSticky(chain, headings) {
  const start = Math.max(0, chain.length - MAX_STICKY_ROWS);
  const rows = chain.length - start;
  reconcileLinks(stickyScroll, rows, (link, i) => {
    const heading = headings[chain[start + i]];
    setLink(link, 'sticky-row sticky-level-' + heading.level, heading.id, chain[start + i], heading.text);
  });
  return rows;
}

// Reflect the active chain in both bars. Subscribed to scroll-spy, so it runs on
// the initial force-emit and on every active-heading change (the scroll hot
// path). It rebuilds only when the chain, the heading set (a re-render) or a
// structural bump (config / resize) changed - so a scroll that does not change
// the active heading, or a force-emit with the same state, costs nothing.
function updateTopBars(info) {
  const chain = info.chain;
  if (info.headings === renderedHeadings && topBarsGen === renderedGen
      && !indexArraysDiffer(chain, renderedChain)) return;
  renderedHeadings = info.headings;
  renderedGen = topBarsGen;
  copyIndices(chain, renderedChain);
  lastHeadings = info.headings;

  const breadcrumbShown = breadcrumbCfg.enabled && info.headings.length > 0;
  const stickyShown = stickyCfg.enabled && chain.length > 0;
  document.body.classList.toggle('has-breadcrumb', breadcrumbShown);
  document.body.classList.toggle('has-sticky', stickyShown);

  if (breadcrumbShown) renderBreadcrumb(chain, info.headings);
  else reconcileLinks(breadcrumb, 0, () => {});
  const stickyRows = stickyShown ? renderSticky(chain, info.headings) : 0;
  if (!stickyShown) reconcileLinks(stickyScroll, 0, () => {});

  // A rebuild changed the segments: keep an open dropdown only while its heading
  // is still on the chain, otherwise it has lost its anchor.
  if (dropdownIdx >= 0 && !includesIndex(chain, dropdownIdx)) closeDropdown();
  else if (dropdownIdx >= 0) positionDropdown(dropdownIdx);
  // Computed height only - no getBoundingClientRect. The table-header dock and the
  // scroll-spy inset both follow the current bars height; the dock write is
  // value-gated, so only a depth change (not every scroll frame) touches the var.
  topBarsOffset = topBarsHeight(breadcrumbShown, stickyRows);
  setStickyHeadInset(topBarsOffset);
  scrollSpy.setTopInset(topBarsOffset);
}

function getTopBarsOffset() { return topBarsOffset; } // exposed for tests

// Whether two index arrays differ; allocation-free (chains are <= 6 entries).
function indexArraysDiffer(a, b) {
  if (a.length !== b.length) return true;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return true;
  return false;
}
function copyIndices(from, into) {
  into.length = from.length;
  for (let i = 0; i < from.length; i++) into[i] = from[i];
}

// Build and open the sibling picker for a breadcrumb segment (its heading and
// the headings at the same level under the same parent). Selection navigates;
// Escape and an outside click close it.
function openDropdown(idx) {
  dropdown.innerHTML = '';
  const siblings = siblingHeadings(lastHeadings.map((h) => h.level), idx);
  for (const s of siblings) {
    const option = document.createElement('a');
    option.className = 'breadcrumb-option' + (s === idx ? ' breadcrumb-option-current' : '');
    option.setAttribute('role', 'button'); // a control, not a native #id anchor (#44 follow-up)
    option.dataset.id = lastHeadings[s].id;
    option.dataset.idx = String(s);
    option.textContent = lastHeadings[s].text;
    option.tabIndex = -1;
    dropdown.appendChild(option);
  }
  dropdownIdx = idx;
  document.body.classList.add('breadcrumb-dropdown-open');
  positionDropdown(idx);
}

function positionDropdown(idx) {
  const seg = breadcrumb.querySelector
    ? breadcrumb.querySelector('.breadcrumb-seg[data-idx="' + idx + '"]') : null;
  if (!seg) return;
  const rect = seg.getBoundingClientRect();
  dropdown.style.left = (rect.left || 0) + 'px';
  dropdown.style.top = (rect.bottom || topBarsOffset || 0) + 'px';
}

function closeDropdown() {
  if (dropdownIdx < 0) return;
  dropdownIdx = -1;
  dropdown.innerHTML = '';
  document.body.classList.remove('breadcrumb-dropdown-open');
}

// A breadcrumb segment scrolls to its heading (smooth) and opens the sibling
// picker (the VS Code breadcrumb gesture: navigate + pick).
breadcrumb.addEventListener('click', (e) => {
  const seg = e.target.closest('.breadcrumb-seg');
  if (!seg) return;
  e.preventDefault();
  // The root segment (index -1, above the first heading) scrolls to the top and
  // has no sibling picker; a heading segment navigates and opens the picker.
  if (seg.dataset.idx === '-1') { scrollWindowTo(0, true); closeDropdown(); return; }
  navigateToHash(seg.dataset.id, true);
  openDropdown(Number(seg.dataset.idx));
});

// A dropdown option navigates to its sibling and closes the picker.
dropdown.addEventListener('click', (e) => {
  const option = e.target.closest('.breadcrumb-option');
  if (!option) return;
  e.preventDefault();
  navigateToHash(option.dataset.id, true);
  closeDropdown();
});

// A sticky-scroll row scrolls to its heading.
stickyScroll.addEventListener('click', (e) => {
  const row = e.target.closest('.sticky-row');
  if (!row) return;
  e.preventDefault();
  navigateToHash(row.dataset.id, true);
});

// A click outside the breadcrumb and its dropdown closes an open picker.
document.addEventListener('click', (e) => {
  if (dropdownIdx < 0) return;
  const t = e.target;
  if (t && t.closest && (t.closest('#breadcrumb-dropdown') || t.closest('.breadcrumb-seg'))) return;
  closeDropdown();
});

// Central click-focus suppression (docs/DECISIONS.md #40): a mouse click on any
// focusable element must not focus it. A newly focused element is scrolled into
// view by the browser/webview (measured: focusing an off-screen link scrolls the
// page), so every click on a link, a checkbox, or a navigation control jumped the
// page - "one level up" as the target slid under the fixed top bars. It also let
// Chromium re-class the focus as :focus-visible and re-show the ring. One
// delegated mousedown listener over every focusable target - content links and
// task/table checkboxes (`a`, `input`), the FAB (`button`) and the nav controls -
// calls preventDefault, which stops the focus (and its scroll) without touching
// the click: links still navigate, checkboxes still toggle. Keyboard focus is
// untouched (mousedown is pointer-only; :focus-visible still rings on Tab), and
// plain text (headings, paragraphs, table-cell prose) is not matched, so text
// selection stays normal.
const CLICK_FOCUS_TARGETS =
  'a, input, button, .breadcrumb-seg, .breadcrumb-option, .toc-link, .sticky-row';
document.addEventListener('mousedown', (e) => {
  if (e.target.closest && e.target.closest(CLICK_FOCUS_TARGETS)) e.preventDefault();
});

scrollSpy.onChange(updateTopBars);
publishTopBarVars(); // constant CSS vars, written once - never during a scroll

vscode.postMessage({ type: 'ready' });
