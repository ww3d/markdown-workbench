// Release-notes extraction from CHANGELOG.md: the section between a
// `## <version>` heading and the next `## ` heading (or end of file).
// Expected texts are written out explicitly, not derived from the source.
const { test } = require('node:test');
const assert = require('node:assert');
const { extractReleaseNotes } = require('../scripts/release-notes');

const CHANGELOG = [
  '# Changelog',
  '',
  '## 0.24.2',
  '- Top entry line one',
  '- Top entry line two',
  '',
  '## 0.24.1',
  '- Middle entry',
  '',
  '## 0.24.0',
  '- Last entry line',
  ''
].join('\n');

test('extracts a middle section up to the next heading', () => {
  assert.strictEqual(extractReleaseNotes(CHANGELOG, '0.24.1'), '- Middle entry');
});

test('extracts the topmost section', () => {
  assert.strictEqual(
    extractReleaseNotes(CHANGELOG, '0.24.2'),
    '- Top entry line one\n- Top entry line two');
});

test('extracts the last section through end of file', () => {
  assert.strictEqual(extractReleaseNotes(CHANGELOG, '0.24.0'), '- Last entry line');
});

test('throws for a version with no section', () => {
  assert.throws(() => extractReleaseNotes(CHANGELOG, '9.9.9'),
    /no "## 9\.9\.9" section/);
});

test('throws for an empty section', () => {
  const empty = '# Changelog\n\n## 1.0.0\n\n## 0.9.0\n- old\n';
  assert.throws(() => extractReleaseNotes(empty, '1.0.0'),
    /section for "## 1\.0\.0" is empty/);
});

test('matches the real CHANGELOG section for the manifest version', () => {
  const fs = require('fs');
  const path = require('path');
  const version = require('../package.json').version;
  const changelog = fs.readFileSync(path.resolve(__dirname, '..', 'CHANGELOG.md'), 'utf8');
  const notes = extractReleaseNotes(changelog, version);
  assert.ok(notes.length > 0, 'current version has non-empty release notes');
});
