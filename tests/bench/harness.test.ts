// The bench harness's Chromium lookup per platform and its profile cleanup (bench/harness.ts). No
// Chromium runs here: the lookup takes the platform facts as arguments, so every platform is covered.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { chromeCandidates, removeProfile } from '../../bench/harness.ts';

const cache = ['chromium-1148', 'ffmpeg-1011', 'firefox-1490'];

test('Windows: the Playwright cache under %LOCALAPPDATA% comes first, win64 before win', () => {
  const local = 'C:\\Users\\dev\\AppData\\Local';
  const asked: string[] = [];
  const found = chromeCandidates({
    platform: 'win32',
    env: { LOCALAPPDATA: local },
    readdir: (dir) => {
      asked.push(dir);
      return cache;
    },
  });
  assert.deepStrictEqual(asked, [`${local}\\ms-playwright`]);
  assert.deepStrictEqual(found.slice(0, 2), [
    `${local}\\ms-playwright\\chromium-1148\\chrome-win64\\chrome.exe`,
    `${local}\\ms-playwright\\chromium-1148\\chrome-win\\chrome.exe`,
  ]);
});

test('Windows: the usual Chrome install paths follow, from each Program Files root', () => {
  const found = chromeCandidates({
    platform: 'win32',
    env: {
      PROGRAMFILES: 'C:\\Program Files',
      'PROGRAMFILES(X86)': 'C:\\Program Files (x86)',
      LOCALAPPDATA: 'C:\\Users\\dev\\AppData\\Local',
    },
    readdir: () => [],
  });
  assert.deepStrictEqual(found, [
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Users\\dev\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe',
  ]);
});

test('Windows: PLAYWRIGHT_BROWSERS_PATH wins over the default cache', () => {
  const asked: string[] = [];
  chromeCandidates({
    platform: 'win32',
    env: { PLAYWRIGHT_BROWSERS_PATH: 'D:\\pw', LOCALAPPDATA: 'C:\\L' },
    readdir: (dir) => {
      asked.push(dir);
      return [];
    },
  });
  assert.deepStrictEqual(asked, ['D:\\pw']);
});

test('Linux: the Playwright cache names chrome-linux, then the system paths; no Windows path', () => {
  const found = chromeCandidates({
    platform: 'linux',
    env: { PLAYWRIGHT_BROWSERS_PATH: '/opt/pw', LOCALAPPDATA: 'C:\\L' },
    readdir: () => cache,
  });
  assert.strictEqual(found[0], '/opt/pw/chromium-1148/chrome-linux/chrome');
  assert.ok(found.includes('/usr/bin/chromium'));
  assert.ok(!found.some((c) => c.endsWith('.exe')));
});

test('removeProfile deletes a profile with its files and accepts one that is gone', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-profile-'));
  fs.mkdirSync(path.join(dir, 'Default'));
  fs.writeFileSync(path.join(dir, 'Default', 'Cookies'), 'x');
  removeProfile(dir);
  assert.ok(!fs.existsSync(dir));
  removeProfile(dir);
});
