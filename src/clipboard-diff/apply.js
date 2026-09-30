// "Apply Candidate": writes the candidate into the baseline region of the file
// as one undo step, after filling in omission placeholders and checking the
// Markdown; asks before replacing a region that changed since the diff opened
// (docs/DECISIONS.md #48).

import { posix } from 'node:path';
import * as vscode from 'vscode';
import { fillPlaceholders } from './unwrap.ts';
import {
  checkCandidate,
  restoreCheckboxStates,
  collectAnchorRefs,
  FINDING,
} from './check.ts';
import { normalizeEol } from './lines.ts';
import * as sync from './sync.js';

const REPLACE = 'Replace';
const APPLY = 'Apply';
const KEEP_BOXES = 'Keep Checkbox States and Apply';
const APPLY_AS_TEXT = 'Apply as Text';

/** Applies the active clipboard diff's candidate. Returns true when written. */
async function applyCandidate(sessions) {
  const session = sessions.forActiveTab();
  if (!session) {
    vscode.window.showInformationMessage(
      'Apply Candidate needs an active clipboard diff.',
    );
    return false;
  }
  const file = await sessions.fileOf(session);
  if (!file) {
    vscode.window.showInformationMessage(
      'The baseline document of this clipboard diff was closed.',
    );
    return false;
  }
  const first = targetOf(sessions, session, file);
  if (first.touched && !(await confirm(STALE_QUESTION, REPLACE))) return false;
  const baseline = file.getText(first.range);
  const clip = await reviewedClip(baseline, first.clip, file);
  if (clip === undefined) return false;
  const text = normalizeEol(
    clip,
    file.eol === vscode.EndOfLine.CRLF ? '\r\n' : '\n',
  );
  // The awaits above give an edit time to land: write where the region is now.
  const target = await freshTarget(sessions, session, file, baseline);
  if (!target) return false;
  const edit = new vscode.WorkspaceEdit();
  edit.replace(file.uri, target.range, text);
  if (!(await sessions.applyOwn(session, 'file', edit))) {
    vscode.window.showWarningMessage(
      'Markdown Workbench could not apply the candidate.',
    );
    return false;
  }
  await afterApply(sessions, session, target, text);
  return true;
}

// The clip to write: placeholders filled from `baseline`, the Markdown check
// answered. Undefined when the user backs out of a question.
async function reviewedClip(baseline, rawClip, file) {
  const filled = fillPlaceholders(baseline, rawClip);
  if (filled.unresolved.length) {
    const n = filled.unresolved.length;
    const ok = await confirm(
      `${n} placeholder line${n > 1 ? 's' : ''} could not be matched to the baseline. Apply ${n > 1 ? 'them' : 'it'} as text?`,
      APPLY_AS_TEXT,
    );
    if (!ok) return undefined;
  }
  const clip = filled.text;
  const findings = checkCandidate(baseline, clip, await anchorRefs(file));
  if (!findings.length) return clip;
  const actions = [APPLY];
  if (findings.some((f) => f.kind === FINDING.CHECKBOX_RESET))
    actions.unshift(KEEP_BOXES);
  const choice = await vscode.window.showWarningMessage(
    'The candidate changes Markdown that other parts may depend on.',
    { modal: true, detail: findings.map((f) => `• ${f.message}`).join('\n') },
    ...actions,
  );
  if (!choice) return undefined;
  return choice === KEEP_BOXES
    ? restoreCheckboxStates(baseline, clip).text
    : clip;
}

// The target as the file stands now. While the region's text moved on from
// what was checked, Apply asks again; undefined when the user declines.
async function freshTarget(sessions, session, file, checked) {
  for (;;) {
    const target = targetOf(sessions, session, file);
    const now = file.getText(target.range);
    if (now === checked) return target;
    if (!(await confirm(STALE_QUESTION, REPLACE))) return undefined;
    checked = now;
  }
}

async function afterApply(sessions, session, target, text) {
  session.region = { ...session.region, touched: false };
  if (target.whole) {
    // The candidate was the whole file; from now on the diff is a whole-file one.
    session.prefix = '';
    session.suffix = '';
    session.rawClip = target.clip;
    session.lastSetClip = target.clip;
  }
  if (session.shape === 'page')
    await sync.mirrorToPage(sessions, session, text);
  vscode.window.setStatusBarMessage(
    'Markdown Workbench: candidate applied',
    3000,
  );
}

const STALE_QUESTION =
  'The baseline range changed since the diff was opened. Replace it with the candidate anyway?';

// What Apply replaces, without touching the session: { range, clip, touched,
// whole }. The region counts as changed when an edit overlapped it or its text
// is no longer what the diff last wrote or saw (e.g. the file was closed and
// changed on disk, which no change event reports). When the text around the
// clipboard part was edited in the candidate too, the whole candidate
// replaces the whole file.
function targetOf(sessions, session, file) {
  const candidateText = candidateTextOf(sessions, session);
  const range = sessions.rangeOf(file, session);
  const regionText = file.getText(range);
  const touched = session.region.touched || regionText !== session.regionText;
  const clip = sessions.clipOf(session, candidateText);
  if (clip !== undefined) return { range, clip, touched, whole: false };
  const all = file.getText();
  return {
    range: new vscode.Range(file.positionAt(0), file.positionAt(all.length)),
    clip: candidateText,
    touched: touched || all !== session.prefix + regionText + session.suffix,
    whole: true,
  };
}

function candidateTextOf(sessions, session) {
  const open = vscode.workspace.textDocuments.find(
    (d) => d.uri.toString() === session.candidateUri.toString(),
  );
  return open
    ? open.getText()
    : (sessions.store.textOf(session.candidateUri) ?? '');
}

async function confirm(message, action) {
  return (
    (await vscode.window.showWarningMessage(
      message,
      { modal: true },
      action,
    )) === action
  );
}

/** Largest Markdown file the workspace-wide anchor check reads. */
const MAX_SCAN_BYTES = 1024 * 1024;

/**
 * Heading ids that links point at: always the file's own links, and with
 * markdownWorkbench.clipboardDiff.checkWorkspaceAnchors on also the links of
 * every other Markdown file in the workspace that resolve to this file (read
 * only, files up to MAX_SCAN_BYTES). id -> [sources].
 */
async function anchorRefs(file) {
  const refs = new Map();
  const add = (id, source) => refs.set(id, [...(refs.get(id) || []), source]);
  for (const id of collectAnchorRefs(file.getText())) add(id, 'this file');
  const workspaceWide = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get('clipboardDiff.checkWorkspaceAnchors', false);
  if (!workspaceWide || file.uri.scheme !== 'file') return refs;
  const others = await vscode.workspace.findFiles(
    '**/*.md',
    '**/node_modules/**',
    2000,
  );
  for (const uri of others) {
    if (uri.toString() === file.uri.toString()) continue;
    const text = await readSmall(uri);
    if (text === undefined) continue;
    const linksHere = (linkPath) =>
      posix.join(posix.dirname(uri.path), linkPath) ===
      posix.normalize(file.uri.path);
    for (const id of collectAnchorRefs(text, linksHere))
      add(id, vscode.workspace.asRelativePath(uri));
  }
  return refs;
}

// The text of a workspace file, or undefined when it is too large or cannot be
// read (deleted meanwhile, no permission): the check is a hint, so such a file
// is skipped instead of failing Apply.
async function readSmall(uri) {
  try {
    if ((await vscode.workspace.fs.stat(uri)).size > MAX_SCAN_BYTES)
      return undefined;
    return Buffer.from(await vscode.workspace.fs.readFile(uri)).toString(
      'utf8',
    );
  } catch {
    return undefined;
  }
}

export { applyCandidate, anchorRefs, MAX_SCAN_BYTES };
