#!/usr/bin/env node
// Headless-Chromium render benchmark for the preview webview: the morphdom update
// path against the innerHTML replace it superseded (docs/DECISIONS.md #46).
//
// Reports, as medians over --iterations runs on a generated document:
//
//   edit      - a one-block content change through the real render path (morphdom
//               against the post-processed incoming tree)
//   replace   - the same change through the old path (#content.innerHTML = html,
//               then the same client-side post-processing)
//   identical - a re-render that produced byte-identical HTML (the string guard)
//   whole     - a full-document change, i.e. switching file: morphdom's worst case
//   selection - whether a live text selection survives each path (the other half
//               of the morphdom decision, not a timing)
//
// Each measurement forces the layout it triggers, so the number is the cost the
// user waits for, not just the JS.
//
// Usage:
//   node bench/render-bench.js                    # 400 blocks, 60 iterations
//   node bench/render-bench.js --blocks 1200 --iterations 30
//   node bench/render-bench.js --profile
//
// Numbers are relative and machine-dependent; compare a change against its
// baseline on the same machine, not against an absolute target.

const { buildPage, runPage, cli } = require('./harness');

const { flag, opt } = cli(process.argv.slice(2));
const BLOCKS = Number(opt('--blocks', '400'));
const ITERATIONS = Number(opt('--iterations', '60'));

// A document of BLOCKS top-level blocks: headings (so the fold controls and the
// heading ids morphdom keys on are in play) plus paragraphs.
function doc(marker) {
  let h = '', line = 1;
  for (let i = 0; i < BLOCKS; i++) {
    if (i % 6 === 0) h += `<h2 id="s${i}" data-line="${line++}">Section ${i}</h2>`;
    else h += `<p data-line="${line++}">Paragraph ${i} lorem ipsum dolor sit amet consectetur adipiscing elit.</p>`;
  }
  // The edited document differs in exactly one block, like a keystroke in the source.
  return marker ? h.replace('Paragraph 1 lorem', 'Paragraph 1 EDITED lorem') : h;
}

const driver = `
const BASE = ${JSON.stringify(doc(false))};
const EDITED = ${JSON.stringify(doc(true))};
const ITERATIONS = ${ITERATIONS};
const config = {
  type: 'config', maxWidth: '980px',
  minimap: { enabled: true, side: 'right', size: 'proportional', showSlider: 'always' },
  toc: { enabled: true, mode: 'auto' }, breadcrumb: { enabled: true }, stickyScroll: { enabled: true }
};
const render = (html) => window.dispatchEvent(new MessageEvent('message', { data: { type: 'render', html } }));

// The content-update step of the render path, isolated. Both variants run the SAME
// client-side post-processing (in-page anchors -> buttons, fold controls), because
// that is what the real path does either way - only the DOM update differs.
function morphUpdate(html) {
  const incoming = document.createElement('div');
  incoming.innerHTML = html;
  convertInternalAnchors(incoming);
  injectFoldToggles(incoming);
  morphdom(content, incoming, { childrenOnly: true });
}
function replaceUpdate(html) {
  content.innerHTML = html;
  convertInternalAnchors(content);
  injectFoldToggles(content);
}

// Time one update and force the layout it triggers into the measurement.
function timed(fn, html) {
  const t0 = performance.now();
  fn(html);
  void document.documentElement.scrollHeight;
  return performance.now() - t0;
}

// Does a live text selection survive the update? The morphdom decision rested on
// this as much as on the timing: the replace destroyed every node, so the reader's
// selection vanished on every keystroke in the source.
function selectionSurvives(update, html) {
  // Pick a paragraph the edit does NOT touch: a selection inside the changed block
  // is destroyed by definition (its text is what changed), which would make the
  // comparison meaningless.
  const paragraphs = [...content.querySelectorAll('p')].filter((p) => !/EDITED/.test(p.textContent));
  const target = paragraphs[Math.floor(paragraphs.length / 2)];
  const range = document.createRange();
  range.selectNodeContents(target);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  const before = sel.toString().trim();
  update(html);
  const after = window.getSelection().toString().trim();
  sel.removeAllRanges();
  return before.length > 0 && after === before;
}

async function run() {
  window.dispatchEvent(new MessageEvent('message', { data: config }));
  render(BASE);
  await raf(); await raf(); await sleep(200);

  const edit = [], replace = [], identical = [], whole = [];
  for (let i = 0; i < ITERATIONS; i++) {
    // Alternate between the two documents so every iteration is a real one-block
    // change rather than a no-op.
    edit.push(timed(morphUpdate, i % 2 ? BASE : EDITED));
    await raf();
    replace.push(timed(replaceUpdate, i % 2 ? EDITED : BASE));
    await raf();
  }
  // Identical re-render: the full render path, guarded by the last-HTML string.
  morphUpdate(BASE);
  render(BASE);
  await raf();
  for (let i = 0; i < ITERATIONS; i++) {
    const t0 = performance.now();
    render(BASE);
    void document.documentElement.scrollHeight;
    identical.push(performance.now() - t0);
  }
  // Whole-document change (a file switch): every block differs.
  const OTHER = BASE.replace(/Paragraph /g, 'Absatz ').replace(/Section /g, 'Abschnitt ');
  for (let i = 0; i < ITERATIONS; i++) {
    whole.push(timed(morphUpdate, i % 2 ? BASE : OTHER));
    await raf();
  }
  const selMorph = selectionSurvives(morphUpdate, EDITED);
  morphUpdate(BASE);
  await raf();
  const selReplace = selectionSurvives(replaceUpdate, EDITED);

  report('blocks=' + content.children.length + ' iterations=' + ITERATIONS
    + ' edit(morphdom)=' + ms(median(edit)) + 'ms edit(innerHTML)=' + ms(median(replace)) + 'ms'
    + ' identical(guarded)=' + ms(median(identical)) + 'ms whole(morphdom)=' + ms(median(whole)) + 'ms'
    + ' selection: morphdom=' + (selMorph ? 'survives' : 'lost')
    + ' innerHTML=' + (selReplace ? 'survives' : 'lost'));
}
run();
`;

runPage(buildPage(driver), { profile: flag('--profile'), name: 'render-bench' });
