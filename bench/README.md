# Preview benchmarks

Two diagnostics that render the real `media/webview.{js,css}` into a generated
document and drive it in a headless Chromium: `scroll-bench.js` (scrolling) and
`fold-bench.js` (folding a section). They are **diagnostics**, not CI gates:
numbers are relative and machine-dependent — compare a change against its
baseline on the same machine.

`harness.js` is the shared part: it builds the page (webview skeleton, theme
tokens, the vendored `morphdom` the webview loads, a `getBoundingClientRect`
counter as a forced-layout proxy), launches the browser and drives it over the
Chrome DevTools Protocol. A page error is reported as the result instead of
timing out silently.

## Requirements

- Node >= 21 (uses the built-in `WebSocket` and `fetch` — **no npm dependency**).
- A Chromium/Chrome binary. It is found via `CHROME_BIN`, else the Playwright
  cache (`PLAYWRIGHT_BROWSERS_PATH`), else common system locations. The browser is
  launched headless and driven over the Chrome DevTools Protocol; nothing is
  installed.

## scroll-bench.js

Scrolls the document top to bottom; reports wall time and rect calls per frame.

```sh
node bench/scroll-bench.js                          # 300 sections, all bars on
node bench/scroll-bench.js --tables 240             # + 240 tables (native sticky th)
node bench/scroll-bench.js --tables 240 --no-sticky # sticky-scroll stack disabled
node bench/scroll-bench.js --tables 240 --profile   # + a CPU self-time table
```

Flags: `--sections N`, `--tables N`, `--no-sticky`, `--profile`.

### What it found (docs/DECISIONS.md #36)

The round-8 table-header pin wrote a `--sticky-head-top` custom property on
`documentElement` on every stack-depth change during a scroll. Because every `th`
consumes that property, on a table-heavy document Chromium recomputed every table
header on almost every frame:

```
--tables 240            (sticky-scroll ON,  per-scroll write) ~22 ms/frame
--tables 240 --no-sticky (stack off)                          ~17 ms/frame
```

The property is now a constant published once per config, so the scroll path
writes nothing and the gap closes. `--profile` also showed that a naive reading of
the CPU profile ("`sourceLineAtTop` 54%") is the sampler attributing forced layout
to the last JS frame — isolating that call changed nothing; the dominant cost is
`(program)`, the browser painting a very tall document.

## fold-bench.js

Folds and unfolds one section at a time and reports what the user waits for:
`click` (the synchronous work before the browser can paint), `gap` (the longest
frame gap in the settle window afterwards, i.e. the batched re-measure as felt
blocking time) and `gbcr` (rect calls per toggle).

```sh
node bench/fold-bench.js                        # 300 sections, 12 samples
node bench/fold-bench.js --sections 600         # bigger document
node bench/fold-bench.js --tables 200           # + tables
node bench/fold-bench.js --no-minimap           # rail off: the clone's own share
node bench/fold-bench.js --profile              # + a CPU self-time table
```

Flags: `--sections N`, `--tables N`, `--samples N`, `--settle MS`, `--no-minimap`,
`--from-top`, `--trace`, `--profile`.

`janky=N/Mms` is the honest jank metric: how many frames in the settle window ran over
a 20 ms budget and their total over-budget time. `gap` alone hides a double hitch.
`sync=N` counts the `scrolled` messages a toggle posted to the host - each one makes
the host reveal a range in the source editor, a round trip the headless stub cannot
show but the real editor feels. `--trace` prints the frame timeline plus who
re-measured (`collect`/`refresh`/`spyMetrics`/`rebuild`/`resizeObserver`) and how long
the batched pass took, which is how a multi-hitch toggle gets attributed instead of
guessed at.

### What it found (docs/DECISIONS.md #47)

The minimap rebuilt its `cloneNode` copy of the whole document on every toggle
(10.5 % total CPU self-time at 72 % idle — the largest entry), the click path
forced a synchronous layout via `offsetParent`, and the `ResizeObserver` then
re-measured every cached position a second time. Mirroring the clone, deriving the
fold mask without a layout read and skipping the duplicated re-measure:

```
600 sections (3600 blocks)  before: click  9.80ms gap 113.50ms gbcr 9595
                            after:  click  9.20ms gap  32.30ms gbcr 4799
```

Round 2 then found, via `--trace`, that the pass mirrored the minimap *before*
measuring — so the first read forced the clone's relayout synchronously inside the
pass. Reads first, minimap mirror last and in idle time: over-budget time per toggle
27.4 → 12.0 ms.

What is left is the clone itself:

```
3600 blocks, rail on   janky 1/13.4ms (fold)  2/16.1ms (unfold)
3600 blocks, rail off  janky 1/ 0.6ms (fold)  0/ 0.0ms (unfold)
1800 blocks, rail on   janky 0/ 0.0ms (fold)  0/ 0.0ms (unfold)
```

A second full document that re-lays-out on every fold — which is what issue #49
(canvas minimap) exists for. Also measured and rejected here: `contain: layout style`
on the blocks (breaks margin collapsing) and `content-visibility: auto` even with
measured `contain-intrinsic-size` (worse: reading a rect on a skipped subtree forces
it to render — browser-native virtualisation and per-element measurement exclude each
other). Details in docs/DECISIONS.md #47.

## Bench rot warning

Both benches inject the real webview script into a hand-built page. When the
webview starts depending on something new in its skeleton, the bench page has to
follow, or the render throws inside the message listener and the bench happily
measures an **empty** document. That happened once (`lines=0` after the morphdom
change), which is why the harness now loads the vendored asset and surfaces page
errors as the result. Sanity-check the `lines=` / `blocks=` counts in the output.
