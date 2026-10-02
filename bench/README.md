# Preview benchmarks

Diagnostics that drive the webview in a headless Chromium, and two that run in
plain Node. Three render a generated document into the webview and drive it:
`scroll-bench.ts` (scrolling), `fold-bench.ts` (folding a section) and
`render-bench.ts` (updating the content). Three time the shipped bundles:
`start-bench.ts` (the webview's first render), `load-bench.ts` (the webview script
up to `ready`) and `activation-bench.ts` (the extension host up to its first
render). They are **diagnostics**, not CI gates: numbers are relative and
machine-dependent — compare a change against its baseline on the same machine. The
one gate on the bundles is their size (below).

`harness.ts` is the shared part: it builds the webview the way the extension ships
it - the same sources (`src/webview/main.ts`), bundler and minify settings as
`dist/webview.{js,css}` - into a bench-only bundle under `artifacts/tmp/bench-webview/`
that also hands the drivers its internals on `globalThis.__mw`
(`webview-internals.ts`; never packaged). It builds the page around it (webview
skeleton, theme tokens, a `getBoundingClientRect` counter as a forced-layout proxy),
launches the browser and drives it over the Chrome DevTools Protocol. A page error
is reported as the result instead of timing out silently. `start-bench.ts` and
`load-bench.ts` load the built `dist/webview.{js,css}` themselves
(`dist-page.ts`), so build first (`pnpm run build`).

## Requirements

- Node 26, as for the repo (the benches are TypeScript, run by type stripping; they
  use the built-in `WebSocket` and `fetch` — **no npm dependency** for the browser).
- A Chromium/Chrome binary. It is found via `CHROME_BIN`, else the Playwright
  cache (`PLAYWRIGHT_BROWSERS_PATH`), else common system locations. The browser is
  launched headless and driven over the Chrome DevTools Protocol; nothing is
  installed.

## scroll-bench.ts

Scrolls the document top to bottom; reports wall time and rect calls per frame.

```sh
node bench/scroll-bench.ts                          # 300 sections, all bars on
node bench/scroll-bench.ts --tables 240             # + 240 tables (native sticky th)
node bench/scroll-bench.ts --tables 240 --no-sticky # sticky-scroll stack disabled
node bench/scroll-bench.ts --tables 240 --profile   # + a CPU self-time table
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

## fold-bench.ts

Folds and unfolds one section at a time and reports what the user waits for:
`click` (the synchronous work before the browser can paint), `gap` (the longest
frame gap in the settle window afterwards, i.e. the batched re-measure as felt
blocking time) and `gbcr` (rect calls per toggle).

```sh
node bench/fold-bench.ts                        # 300 sections, 12 samples
node bench/fold-bench.ts --sections 600         # bigger document
node bench/fold-bench.ts --tables 200           # + tables
node bench/fold-bench.ts --no-minimap           # rail off: the clone's own share
node bench/fold-bench.ts --profile              # + a CPU self-time table
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

Round 2 then found, via `--trace`, that the pass mirrored the minimap _before_
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

## render-bench.ts

Times the content-update step of the morphdom render path against the `innerHTML`
replace it superseded, and checks whether a live text selection survives each.

```sh
node bench/render-bench.ts                        # 400 blocks, 60 iterations
node bench/render-bench.ts --blocks 1200 --iterations 30
node bench/render-bench.ts --profile
```

Flags: `--blocks N`, `--iterations N`, `--profile`.

### What it shows (docs/DECISIONS.md #46)

```
edit(morphdom)=2.20-2.40ms  edit(innerHTML)=6.70-7.00ms
identical(guarded)=0.00ms   whole(morphdom)=6.10-6.80ms
selection: morphdom=survives  innerHTML=lost
```

A one-block edit is ~3x cheaper and keeps the reader's selection; an identical
re-render is free (the string guard); a full-document change is morphdom's worst
case and roughly matches the replace. The selection probe deliberately picks a
paragraph the edit does **not** touch — a selection inside the changed block is
destroyed by definition, and measuring that would say nothing about the two paths.

## start-bench.ts

The start of the shipped webview (P3 of docs/DECISIONS.md #50): from the start of the
page navigation until the first render is on screen - two animation frames after the
`config` and `render` messages of a 400-block document. Each run is a fresh Chromium
with a fresh page; median of 21 runs, with minimum and maximum.

The window opens at the navigation, so it contains a fixed share the change under test
cannot touch: Chromium starting the page and laying out the skeleton. An empty page with
the same skeleton (`node bench/start-bench.ts --blocks 1`) measured, on the reference machine, a
median of 60.3 ms (minimum 36.9 ms, 15 runs, machine load 22) of the 153 ms reported below.
Another machine gives another number, and a difference of a few milliseconds lies within the
spread of that share. Read the numbers as "not slower than the base", and compare a
smaller effect with `load-bench.ts`, which starts at the script.

```sh
node bench/start-bench.ts                  # 400 blocks, 21 runs
node bench/start-bench.ts --runs 5 --blocks 1200
node bench/start-bench.ts --base ../base   # the base revision's unsplit webview
```

Flags: `--runs N`, `--blocks N`, `--base DIR`.

## load-bench.ts

The load time of `dist/webview.js`: from the start of the script to its `ready`
message. A marker script right before it records `performance.now()`, the stand-in
of `acquireVsCodeApi` records it again at `ready`; `load` is the difference - parse,
compile, top-level run and module setup, nothing before the script. The same run
prints the CDP metric `Performance.getMetrics` `ScriptDuration` as `cdp`, a
cross-check that also counts the markers and the reporting. Median of 21 fresh runs.

```sh
node bench/load-bench.ts                   # 21 runs
node bench/load-bench.ts --runs 5
node bench/load-bench.ts --base ../base    # the base revision's unsplit webview
```

Flags: `--runs N`, `--base DIR`.

`--base DIR` (here and in `start-bench.ts`) replaces the built `dist/webview.{js,css}` by
`DIR/media/morphdom.js`, `DIR/media/webview.js` and `DIR/media/webview.css`: `DIR` is a
worktree of the base revision (`git worktree add ../base 98f7590`), which needs no
build. Run both alternately, run for run, in the same session.

## activation-bench.ts

The activation of the extension host bundle (P7 of docs/DECISIONS.md #50): from
loading `dist/extension.cjs` to the first `render` it posts after the webview's
`ready` - `require`, `activate`, resolving a custom editor and answering `ready`.
A second value runs on to the first `render` with highlighted code (`class="shiki`): the
document carries one fenced block, and Shiki loads in the background after `activate`, so
the first value ends before the highlighter is there. Compare a change on both values -
one alone hides a shift between them.
Plain Node, no browser, in the topology of the bundle smoke (`dist/` copied to a
fresh temp directory, `vscode` replaced by the test mock); every run is a fresh Node
process. Median of 21 runs.

```sh
node bench/activation-bench.ts             # 21 isolated runs
node bench/activation-bench.ts --runs 5
node bench/activation-bench.ts --once      # one run, prints both milliseconds
```

Flags: `--runs N`, `--once`.

### What they showed (docs/DECISIONS.md #50)

Base `98f7590` (the unsplit webview, `media/webview.js` plus `media/morphdom.js`)
against the split, bundled webview, measured alternately run for run in one session
on a loaded machine, medians of 21:

```
start (P3)       157 ms  -> 153 ms
load             3.50 ms -> 2.80 ms
activation (P7)  79.16 ms -> 46.21 ms
```

The activation gain comes from Shiki's core moving into a lazy chunk: it loads in the
background right after `activate` instead of with `dist/extension.cjs`, so the first
render no longer waits for it. The time to the first highlighted render is the second
value of `activation-bench.ts`, and is not part of this gain.

## Size gate

Not a bench but the one hard gate on the bundles: `scripts/size-gate.ts` runs at the
end of the Build task (`eng/build.ts`) and fails the run when a bundle outgrows its
limit - gzip (level 9) of `dist/webview.js` + `dist/webview.css` (28 000 B) and of
`dist/extension.cjs`, and the uncompressed bytes of `dist/webview.js` and
`dist/webview.css` each, which is what the webview parses. It prints measured value
against limit for every check, so a pass shows the room left.

```sh
pnpm run build && node scripts/size-gate.ts
```

## Bench rot warning

The browser benches inject the webview into a hand-built page. When the webview
starts depending on something new in its skeleton, the bench page has to follow, or
the render throws inside the message listener and the bench happily measures an
**empty** document. That happened once (`lines=0` after the morphdom change), which
is why the harness builds the webview from the shipped entry and surfaces page
errors as the result. Sanity-check the `lines=` / `blocks=` counts in the output.

## table-bench.ts

The editor-side table model (`src/tables/`) on one generated table, in plain Node
(no browser): detection, the `markdownWorkbench.inTable` context key with and
without its cached span, and both alignment modes (docs/DECISIONS.md #49).

```sh
node bench/table-bench.ts                 # 10000 rows, ASCII cells
node bench/table-bench.ts --rows 5000 --cjk
```

Flags: `--rows N`, `--cjk`.

## anchor-bench.ts

Times the clipboard diff's section anchor (`src/clipboard-diff/anchor.ts`) on a
generated 10 000-line baseline: a heading-led candidate and a 20-line snippet from
the middle with two changed lines. Plain Node, no browser.

```sh
node bench/anchor-bench.ts                       # 10 000 lines, 21 runs
node bench/anchor-bench.ts --lines 50000 --iterations 11
```

Target from the design round (docs/DECISIONS.md #48): below 100 ms at 10 000
lines.
