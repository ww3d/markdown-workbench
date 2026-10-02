// REQ-081/082 of docs/tasks/92-typescript-webview.md: the webview entry of tsdown.config.ts
// has a fixed Chromium target (the Electron of the minimum VS Code), and the stylesheet
// build does not lower CSS below it. The probe sends a small fixture through the webview
// entry's own settings: CSS nesting (rewritten for targets before Chrome 120) and a
// `color-mix()` over a custom property must come out as written. A second build of the same
// fixture with an old target proves the probe can tell the difference (nesting is the
// discriminator; a `color-mix()` over literal colors is folded at any target, so the
// fixture takes a variable, like the real stylesheet). The entry's own `css` settings go into
// the probe (only the file name is replaced), so a `css.target` there shows in the result.
// Package layer (tests/package/): it runs a bundler build, which the unit tests do not.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { build } from 'tsdown';
import config from '../../tsdown.config.ts';

const FIXTURE_CSS = `.card {
  color: color-mix(in srgb, var(--fg) 30%, transparent);
  & .title { font-weight: bold; }
}
`;

const webview = config.find(
  (entry) => typeof entry.entry === 'object' && 'webview' in entry.entry,
);

async function buildFixture(target?: string): Promise<string> {
  assert.ok(webview, 'tsdown.config.ts has a webview entry');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-css-target-'));
  try {
    const entry = path.join(dir, 'probe.js');
    fs.writeFileSync(entry, "import './probe.css';\n");
    fs.writeFileSync(path.join(dir, 'probe.css'), FIXTURE_CSS);
    await build({
      ...webview,
      config: false,
      entry: { probe: entry },
      outDir: path.join(dir, 'out'),
      clean: true,
      ...(target === undefined ? {} : { target }),
      css: { ...webview.css, fileName: 'probe.css' },
      logLevel: 'error',
    });
    return fs.readFileSync(path.join(dir, 'out', 'probe.css'), 'utf8');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('the webview entry targets Chrome 132, the Electron of the minimum VS Code', () => {
  assert.strictEqual(webview?.target, 'chrome132');
});

test('the webview stylesheet build keeps nesting and color-mix as written', async () => {
  const css = await buildFixture();
  assert.match(css, /color-mix\(in srgb/);
  assert.match(css, /&\s*\.title/);
  assert.doesNotMatch(css, /\.card\s+\.title/);
});

test('an older target lowers the same fixture, so the probe can fail', async () => {
  const css = await buildFixture('chrome100');
  assert.doesNotMatch(css, /&\s*\.title/);
  assert.match(css, /\.card\s+\.title/);
});
