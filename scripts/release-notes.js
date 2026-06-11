#!/usr/bin/env node
// Extract the CHANGELOG.md section for a given version - the curated release
// notes body. A section runs from its `## <version>` heading to the next
// `## ` heading (or end of file). A missing or empty section is an error: the
// same source-of-truth discipline as build.ps1's version check, continued
// into the release path.
'use strict';

const HEADING = /^## (.+?)\s*$/;

function extractReleaseNotes(changelog, version) {
  const lines = changelog.split(/\r?\n/);
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    const m = HEADING.exec(lines[i]);
    if (m && m[1] === version) { start = i; break; }
  }
  if (start === -1) {
    throw new Error('CHANGELOG.md has no "## ' + version + '" section');
  }
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (HEADING.test(lines[i])) { end = i; break; }
  }
  const body = lines.slice(start + 1, end).join('\n').trim();
  if (!body) {
    throw new Error('CHANGELOG.md section for "## ' + version + '" is empty');
  }
  return body;
}

module.exports = { extractReleaseNotes };

// CLI: node scripts/release-notes.js <version> [changelogPath] [outFile]
// Writes the extracted notes to outFile (or stdout). Exits non-zero on a
// missing/empty section so a release job fails loudly instead of publishing
// blank notes.
if (require.main === module) {
  const fs = require('fs');
  const path = require('path');
  const [version, changelogPath, outFile] = process.argv.slice(2);
  if (!version) {
    console.error('usage: release-notes.js <version> [changelogPath] [outFile]');
    process.exit(2);
  }
  const file = changelogPath || path.resolve(__dirname, '..', 'CHANGELOG.md');
  try {
    const notes = extractReleaseNotes(fs.readFileSync(file, 'utf8'), version);
    if (outFile) fs.writeFileSync(outFile, notes + '\n');
    else process.stdout.write(notes + '\n');
  } catch (err) {
    console.error('release-notes: ' + err.message);
    process.exit(1);
  }
}
