// Emphasis marker alignment for the clipboard diff style pass (docs/DECISIONS.md
// #1, #48 F2): swaps _x_ / __x__ (or *x* / **x**) delimiters to the baseline's
// markers, with code spans and inline HTML masked first so nothing inside them
// moves. Pure, no vscode.

// Rewrites _x_ / __x__ (or *x* / **x**) delimiters to the profile's markers.
// Code spans and inline HTML are masked first, so nothing inside them moves.
function swapEmphasis(line, profile) {
  const masked = maskInline(line);
  let out = line;
  for (const [from, to] of emphasisSwaps(profile)) {
    out = replaceDelimiters(out, masked, from, to);
  }
  return out;
}

function emphasisSwaps(profile) {
  const swaps = [];
  if (profile.strong === '**') swaps.push(['__', '**']);
  if (profile.strong === '__') swaps.push(['**', '__']);
  if (profile.emphasis === '*') swaps.push(['_', '*']);
  if (profile.emphasis === '_') swaps.push(['*', '_']);
  return swaps;
}

// Blanks code spans and inline HTML tags, index-preserving, in one linear
// pass (a regex would backtrack quadratically on runs of "`" or "<").
function maskInline(line) {
  const out = line.split('');
  const runs = []; // [index, length] of backtick runs
  for (let i = 0; i < line.length; ) {
    if (line[i] !== '`') {
      i++;
      continue;
    }
    let j = i;
    while (line[j] === '`') j++;
    runs.push([i, j - i]);
    i = j;
  }
  const nextOfLength = new Map(); // run length -> indexes into runs, ascending
  runs.forEach(([, len], k) => {
    if (!nextOfLength.has(len)) nextOfLength.set(len, []);
    nextOfLength.get(len).push(k);
  });
  const cursor = new Map();
  let maskedTo = 0;
  for (let k = 0; k < runs.length; k++) {
    const [at, len] = runs[k];
    if (at < maskedTo) continue;
    const list = nextOfLength.get(len);
    let c = cursor.get(len) ?? 0;
    while (c < list.length && list[c] <= k) c++;
    cursor.set(len, c);
    if (c === list.length) continue;
    const [closeAt] = runs[list[c]];
    for (let x = at; x < closeAt + len; x++) out[x] = ' ';
    maskedTo = closeAt + len;
  }
  const masked = out.join('');
  let result = '';
  let last = 0;
  for (let i = masked.indexOf('<'); i !== -1; i = masked.indexOf('<', last)) {
    const close = masked.indexOf('>', i);
    if (close === -1) break;
    result += masked.slice(last, i) + ' '.repeat(close - i + 1);
    last = close + 1;
  }
  return result + masked.slice(last);
}

// Replaces delimiter runs of exactly `from` (a run of one repeated character)
// that open or close emphasis per the flanking rules, at positions where the
// masked line still shows them.
function replaceDelimiters(line, masked, from, to) {
  const ch = from[0] === '*' ? '\\*' : '_';
  const re = new RegExp(`(?<![${ch}\\\\])${ch}{${from.length}}(?!${ch})`, 'g');
  let out = '';
  let last = 0;
  for (const m of masked.matchAll(re)) {
    const i = m.index;
    const prev = line[i - 1] || ' ';
    const next = line[i + from.length] || ' ';
    const opens =
      /\S/.test(next) && !(from[0] === '_' && /[\p{L}\p{N}]/u.test(prev));
    const closes =
      /\S/.test(prev) && !(from[0] === '_' && /[\p{L}\p{N}]/u.test(next));
    if (!opens && !closes) continue;
    out += line.slice(last, i) + to;
    last = i + from.length;
  }
  return out + line.slice(last);
}

module.exports = {
  swapEmphasis,
  _internal: { maskInline, replaceDelimiters, emphasisSwaps },
};
