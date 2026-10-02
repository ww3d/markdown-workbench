// Stylesheet lookups for the webview's CSS contract tests. The stylesheets live next
// to their modules (src/webview/**/*.css); main.ts imports them all first, in cascade
// order, and that order is what the bundle keeps. sheet() reads the named files in that
// same order, so "the first rule that matches" means what it means in dist/webview.css.

import fs from 'node:fs';
import path from 'node:path';

const WEBVIEW_DIR = path.resolve(
  import.meta.dirname,
  '..',
  '..',
  'src',
  'webview',
);

/** Every webview stylesheet (relative to src/webview/), in the cascade order main.ts pins. */
export const CASCADE: readonly string[] = [
  ...fs
    .readFileSync(path.join(WEBVIEW_DIR, 'main.ts'), 'utf8')
    .matchAll(/^import '\.\/([^']+\.css)';$/gm),
].map((m) => m[1] ?? '');

/** Rule lookups over a set of stylesheets, comments dropped. */
export interface Sheet {
  /** The concatenated stylesheet text (comments dropped so they cannot carry braces). */
  readonly text: string;
  /** Declarations of the first rule whose selector list contains `selector`; throws for none. */
  ruleBody(selector: string): string;
  /** Position of the first rule whose selector list contains `selector` (-1 for none). */
  ruleIndex(selector: string): number;
}

// Selectors are compared normalized (attribute quotes, whitespace, spacing
// around combinators), so a formatter's layout of the stylesheet cannot break
// the lookup.
function normSelector(s: string): string {
  return s
    .replace(/"/g, '')
    .replace(/\s*([>+~])\s*/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * The named stylesheets (paths under src/webview/, e.g. 'top-bars/top-bars.css'),
 * concatenated in cascade order whatever order they are named in. The stylesheets
 * have no nesting, so a rule is `selectors { declarations }`.
 */
export function sheet(...files: string[]): Sheet {
  for (const f of files) {
    if (!CASCADE.includes(f))
      throw new Error(`${f} is not imported by main.ts`);
  }
  const text = CASCADE.filter((f) => files.includes(f))
    .map((f) => fs.readFileSync(path.join(WEBVIEW_DIR, f), 'utf8'))
    .join('\n')
    .replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = text.match(/[^{}]+\{[^{}]*\}/g) || [];
  const selectorsOf = (rule: string) =>
    rule.slice(0, rule.indexOf('{')).split(',').map(normSelector);
  return {
    text,
    ruleBody(selector) {
      const wanted = normSelector(selector);
      const rule = rules.find((r) => selectorsOf(r).includes(wanted));
      if (!rule) throw new Error(`no rule for ${selector}`);
      return rule.slice(rule.indexOf('{') + 1, -1);
    },
    ruleIndex(selector) {
      const wanted = normSelector(selector);
      return rules.findIndex((r) => selectorsOf(r).includes(wanted));
    },
  };
}
