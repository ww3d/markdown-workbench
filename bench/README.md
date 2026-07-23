# Scroll benchmark

`scroll-bench.js` renders the real `media/webview.{js,css}` into a generated
document, drives a scroll sweep in a headless Chromium, and reports wall time per
frame plus the number of `getBoundingClientRect` calls per frame (a forced-layout
proxy). It is a **diagnostic**, not a CI gate: numbers are relative and
machine-dependent — compare a change against its baseline on the same machine.

## Requirements

- Node >= 21 (uses the built-in `WebSocket` and `fetch` — **no npm dependency**).
- A Chromium/Chrome binary. It is found via `CHROME_BIN`, else the Playwright
  cache (`PLAYWRIGHT_BROWSERS_PATH`), else common system locations. The browser is
  launched headless and driven over the Chrome DevTools Protocol; nothing is
  installed.

## Usage

```sh
node bench/scroll-bench.js                          # 300 sections, all bars on
node bench/scroll-bench.js --tables 240             # + 240 tables (native sticky th)
node bench/scroll-bench.js --tables 240 --no-sticky # sticky-scroll stack disabled
node bench/scroll-bench.js --tables 240 --profile   # + a CPU self-time table
```

Flags: `--sections N`, `--tables N`, `--no-sticky`, `--profile`.

## What it found (docs/DECISIONS.md #36)

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
