// Unwrapping an AI answer and guarding against its omission placeholders.
// Pure, no vscode.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  unwrapAnswer,
  placeholderRule,
  findPlaceholders,
  fillPlaceholders,
  PLACEHOLDER_PATTERNS,
} = require('../../src/clipboard-diff/unwrap');

// --- unwrapAnswer: fences ---

test('unwrapAnswer strips a leading "Sure, here is ...:" and a trailing "Let me know ..." around a ```markdown fence', () => {
  const text = [
    'Sure, here is the updated section:',
    '```markdown',
    '# Title',
    'content',
    '```',
    'Let me know if you need anything else.',
  ].join('\n');
  const result = unwrapAnswer(text);
  assert.strictEqual(result.text, '# Title\ncontent');
  assert.deepStrictEqual(result.removed, [
    'leading-chat:assent',
    'trailing-chat:offer',
    'outer-fence',
  ]);
});

test('unwrapAnswer strips a ~~~ fence just like a backtick fence', () => {
  const text = ['Here is the code:', '~~~', 'foo', '~~~'].join('\n');
  const result = unwrapAnswer(text);
  assert.strictEqual(result.text, 'foo');
  assert.ok(result.removed.includes('outer-fence'));
});

test('unwrapAnswer does not unwrap when an inner line could already close the fence', () => {
  const text = ['Here is the code:', '```', 'foo', '```', 'bar', '```'].join(
    '\n',
  );
  const result = unwrapAnswer(text);
  assert.strictEqual(result.text, '```\nfoo\n```\nbar\n```');
  assert.ok(!result.removed.includes('outer-fence'));
});

test('unwrapAnswer recognizes German assent/here-is and offer patterns', () => {
  const text = [
    'Gerne, hier ist die aktualisierte Version:',
    '```',
    'foo',
    '```',
    'Lass mich wissen falls du noch etwas brauchst.',
  ].join('\n');
  const result = unwrapAnswer(text);
  assert.strictEqual(result.text, 'foo');
  assert.deepStrictEqual(result.removed, [
    'leading-chat:assent-de',
    'trailing-chat:offer-de',
    'outer-fence',
  ]);
});

test('(counter-check) a leading "Sure" sentence directly followed by content, no blank line, stays', () => {
  const text = 'Sure thing, this works great.\nMore text right after.';
  const result = unwrapAnswer(text);
  assert.strictEqual(result.text, text);
  assert.deepStrictEqual(result.removed, []);
});

// --- placeholders ---

test('every PLACEHOLDER_PATTERNS entry has a positive case', () => {
  const cases = {
    'ellipsis-note': '... rest unchanged',
    'bracketed-ellipsis': '[...]',
    'html-comment': '<!-- unchanged -->',
    'code-comment': '// ... existing code',
    'bare-ellipsis': '...',
  };
  assert.strictEqual(Object.keys(cases).length, PLACEHOLDER_PATTERNS.length);
  for (const p of PLACEHOLDER_PATTERNS) {
    assert.ok(
      Object.hasOwn(cases, p.name),
      `missing case for pattern ${p.name}`,
    );
    assert.strictEqual(placeholderRule(cases[p.name]), p.name);
  }
});

test('findPlaceholders returns the 0-based line numbers of placeholder lines', () => {
  const text = ['keep', '...', 'keep', '[...]'].join('\n');
  assert.deepStrictEqual(findPlaceholders(text), [1, 3]);
});

test('(counter-check, REQ-39) an ellipsis in running text is not a placeholder', () => {
  assert.strictEqual(placeholderRule('Das war ... erstaunlich.'), null);
  assert.strictEqual(placeholderRule('Wait... what'), null);
});

// --- fillPlaceholders ---

test('fillPlaceholders fills a middle gap between two anchored lines', () => {
  const base = ['line1', 'line2', 'line3', 'line4', 'line5'].join('\n');
  const cand = ['line1', '...', 'line5'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, base);
  assert.deepStrictEqual(result.filled, [{ line: 1, count: 3 }]);
  assert.deepStrictEqual(result.unresolved, []);
});

test('fillPlaceholders fills a start gap with no line above the placeholder', () => {
  const base = ['line1', 'line2', 'line3', 'line4', 'line5'].join('\n');
  const cand = ['...', 'line4', 'line5'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, base);
  assert.deepStrictEqual(result.filled, [{ line: 0, count: 3 }]);
});

test('fillPlaceholders fills an end gap with no line below the placeholder', () => {
  const base = ['line1', 'line2', 'line3', 'line4', 'line5'].join('\n');
  const cand = ['line1', 'line2', '...'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, base);
  assert.deepStrictEqual(result.filled, [{ line: 2, count: 3 }]);
});

test('fillPlaceholders treats a run of consecutive placeholder lines as one gap', () => {
  const base = ['line1', 'line2', 'line3', 'line4', 'line5'].join('\n');
  const cand = ['line1', '...', '...', 'line5'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, base);
  assert.deepStrictEqual(result.filled, [{ line: 1, count: 3 }]);
});

test('fillPlaceholders leaves the gap unresolved when the neighbours tie between two equally likely places', () => {
  const base = ['A', 'x1', 'B', 'A', 'x2', 'B', 'end'].join('\n');
  const cand = ['A', '...', 'B'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, cand);
  assert.deepStrictEqual(result.filled, []);
  assert.deepStrictEqual(result.unresolved, [1]);
});

test('fillPlaceholders leaves the gap unresolved when the line above it ties, even with a unique line below', () => {
  const base = ['A', 'x1', 'B', 'A', 'x2', 'C'].join('\n');
  const cand = ['A', '...', 'C'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, cand);
  assert.deepStrictEqual(result.filled, []);
  assert.deepStrictEqual(result.unresolved, [1]);
});

test('fillPlaceholders leaves the gap unresolved when a neighbour is missing from the baseline', () => {
  const base = ['line1', 'line2', 'line3', 'line4', 'line5'].join('\n');
  const cand = ['nomatch', '...', 'line5'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, cand);
  assert.deepStrictEqual(result.unresolved, [1]);
});

test('(counter-check) fillPlaceholders resolves a duplicate neighbour when the surrounding context disambiguates it', () => {
  const base = ['ctx1', 'A', 'x1', 'B', 'ctx2', 'A', 'x2', 'B', 'end'].join(
    '\n',
  );
  const cand = ['ctx2', 'A', '...', 'B'].join('\n');
  const result = fillPlaceholders(base, cand);
  assert.strictEqual(result.text, 'ctx2\nA\nx2\nB');
  assert.deepStrictEqual(result.unresolved, []);
});

// --- edges never eat the only content ---

test('a single chat-like line with a trailing break is content, not chat', () => {
  for (const text of [
    'OK\n',
    'Sure thing\n',
    'Great, thanks!\n',
    'Gerne\n',
    'Let me know\n',
  ]) {
    assert.deepStrictEqual(unwrapAnswer(text), { text, removed: [] }, text);
  }
});

test('an empty fence is content, not a wrapper', () => {
  assert.deepStrictEqual(unwrapAnswer('```\n```'), {
    text: '```\n```',
    removed: [],
  });
});

test('every LEADING_CHAT_PATTERNS and TRAILING_CHAT_PATTERNS rule has a case that it wins', () => {
  const {
    LEADING_CHAT_PATTERNS,
    TRAILING_CHAT_PATTERNS,
  } = require('../../src/clipboard-diff/unwrap');
  const leading = {
    assent: 'Sure, here you go.',
    'here-is': 'Here is the updated file:',
    'did-update': 'I have updated the section:',
    'assent-de': 'Gerne, bitte sehr.',
    'here-is-de': 'Hier ist die neue Fassung:',
  };
  const trailing = {
    offer: 'Let me know if that works.',
    'offer-de': 'Sag Bescheid, wenn noch etwas fehlt.',
  };
  assert.deepStrictEqual(
    Object.keys(leading).sort(),
    LEADING_CHAT_PATTERNS.map((p) => p.name).sort(),
  );
  assert.deepStrictEqual(
    Object.keys(trailing).sort(),
    TRAILING_CHAT_PATTERNS.map((p) => p.name).sort(),
  );
  for (const [name, line] of Object.entries(leading)) {
    assert.deepStrictEqual(
      unwrapAnswer(`${line}\n\n# Body\n`).removed,
      [`leading-chat:${name}`],
      line,
    );
  }
  for (const [name, line] of Object.entries(trailing)) {
    assert.deepStrictEqual(
      unwrapAnswer(`# Body\n\n${line}\n`).removed,
      [`trailing-chat:${name}`],
      line,
    );
  }
});

// --- placeholder alignment asks where the end is ambiguous ---

test('a line below the placeholder that repeats inside the gap makes it unresolved', () => {
  const r = fillPlaceholders(
    '## Steps\n\n1. one\n\n---\n\n2. two\n\n---\n\nDone.\n',
    '## Steps\n\n1. one\n\n… rest unchanged …\n\n---\n\nDone!\n',
  );
  assert.deepStrictEqual(r.unresolved, [4]);
  assert.ok(r.text.includes('… rest unchanged …'));
});

test('a repeated line below the placeholder is resolved by the lines after it', () => {
  const r = fillPlaceholders(
    'A\nB\n}\nC\n}\nD',
    'A\n// ... existing code\n}\nD',
  );
  assert.strictEqual(r.text, 'A\nB\n}\nC\n}\nD');
  assert.deepStrictEqual(r.unresolved, []);
});

// --- linear on hostile input ---

test('placeholder checks stay fast on a very long line (no backtracking)', () => {
  const lines = [
    ' '.repeat(100000),
    `${' '.repeat(100000)}x`,
    `<!--${' '.repeat(100000)}`,
  ];
  const t = Date.now();
  for (const l of lines) assert.strictEqual(placeholderRule(l), null);
  assert.ok(Date.now() - t < 50, `took ${Date.now() - t} ms`);
});

test('a short line of spaces before a placeholder still matches', () => {
  assert.strictEqual(
    placeholderRule(`${' '.repeat(20)}… rest unchanged …`),
    'ellipsis-note',
  );
  assert.strictEqual(placeholderRule('<!--   unchanged -->'), 'html-comment');
});
