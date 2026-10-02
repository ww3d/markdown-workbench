// Invariants of the source tree that only lint and the compiler half-cover (REQ-016, REQ-018,
// REQ-019 of docs/tasks/92-typescript-webview.md): the sources are TypeScript only, no type
// assertion stands in for a type (`as const` is the exception), and every exported symbol
// carries a TSDoc comment. Biome has no rule for these; without a test the next change breaks
// them unnoticed.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';
import { repoRoot } from '../eng/layout.ts';

const srcDir = path.join(repoRoot, 'src');

/** Every file under `dir`, as a path relative to the repository root with forward slashes. */
function filesUnder(dir: string): string[] {
  return fs
    .readdirSync(dir, { withFileTypes: true, recursive: true })
    .filter((entry) => entry.isFile())
    .map((entry) =>
      path
        .relative(repoRoot, path.join(entry.parentPath, entry.name))
        .replaceAll('\\', '/'),
    )
    .sort();
}

const sources = filesUnder(srcDir).filter((f) => f.endsWith('.ts'));

function read(file: string): string {
  return fs.readFileSync(path.join(repoRoot, file), 'utf8');
}

/** The source with comments and the contents of string and template literals blanked out. */
function code(text: string): string {
  return (
    text
      .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
      .replace(/\/\/[^\n]*/g, '')
      // Regex literals, told from a division by what precedes them.
      .replace(
        /(?<=(?:^|[(,=:[!&|?{};]|\breturn)\s*)\/(?![*/])(?:[^/\\\n[]|\\.|\[(?:[^\]\\\n]|\\.)*\])+\/[dgimsuvy]*/gm,
        '/./',
      )
      .replace(
        /'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\[\s\S])*`/g,
        "''",
      )
  );
}

test('the sources under src/ are TypeScript only', () => {
  assert.ok(sources.length > 50, 'the walk finds the source tree');
  const scripts = filesUnder(srcDir).filter((f) => /\.[cm]?jsx?$/.test(f));
  assert.deepStrictEqual(scripts, []);
});

test('no source uses a type assertion other than as const', () => {
  const hits: string[] = [];
  for (const file of sources) {
    const stripped = code(read(file))
      // Renames are not assertions: `import { a as b }`, `export * as ns`, `import * as ns`.
      .replace(/\b(?:import|export)\b[^;]*?\bfrom\b\s*''/g, '')
      .replace(/\bexport\s*\{[^}]*\}/g, '');
    stripped.split('\n').forEach((line, i) => {
      if (/\bas\s+(?!const\b)\S/.test(line)) hits.push(`${file}:${i + 1}`);
    });
  }
  assert.deepStrictEqual(hits, []);
});

/** The exported names of a source and whether each one is documented. */
function undocumentedExports(file: string): string[] {
  const lines = read(file).split('\n');
  const declared =
    /^(?:export\s+)?(?:declare\s+)?(?:async\s+)?(?:function\*?|const|let|class|interface|type|abstract class)\s+([A-Za-z_$][\w$]*)/;
  const documented = (index: number): boolean => {
    let i = index - 1;
    // Overloads share the comment of the first signature.
    while (
      i >= 0 &&
      /^\s*(?:export\s+)?function\s/.test(lines[i] ?? '') &&
      /;\s*$/.test(lines[i] ?? '')
    )
      i--;
    return (lines[i] ?? '').trim().endsWith('*/');
  };
  const missing: string[] = [];
  const listed = new Set<string>();
  // `export { a, b }` at the end of a file: the names are declared (and documented) above.
  const text = code(read(file));
  for (const list of text.matchAll(
    /^export\s*(?:type\s*)?\{([^}]*)\}\s*;?$/gm,
  )) {
    for (const part of (list[1] ?? '').split(',')) {
      const name = part
        .trim()
        .split(/\s+as\s+/)[0]
        ?.replace(/^type\s+/, '');
      if (name) listed.add(name);
    }
  }
  lines.forEach((line, index) => {
    const m = declared.exec(line);
    const name = m?.[1];
    if (name === undefined) return;
    const exported = line.startsWith('export ') || listed.has(name);
    if (exported && !documented(index))
      missing.push(`${file}:${index + 1} ${name}`);
  });
  return missing;
}

test('every exported symbol under src/ carries a TSDoc comment', () => {
  const missing = sources.flatMap(undocumentedExports);
  assert.deepStrictEqual(missing, []);
});
