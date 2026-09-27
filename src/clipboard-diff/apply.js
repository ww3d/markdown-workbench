// "Apply Candidate": writes the candidate into the baseline region of the file
// as one undo step, after filling in omission placeholders and checking the
// Markdown; asks before replacing a region that changed since the diff opened
// (docs/DECISIONS.md #48).

const vscode = require('vscode');
const { fillPlaceholders } = require('./unwrap');
const {
  checkCandidate,
  restoreCheckboxStates,
  collectAnchorRefs,
  FINDING,
} = require('./check');
const { normalizeEol } = require('./lines');

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
  const file = await vscode.workspace.openTextDocument(session.fileUri);
  const candidateText = candidateTextOf(sessions, session);
  let clip = sessions.clipOf(session, candidateText);
  if (clip === undefined) {
    // The text around the section was edited in the candidate too: the whole
    // candidate replaces the whole file - which counts as changed when the file
    // no longer consists of the snapshot around the region.
    const whole = file.getText();
    const unchanged =
      whole ===
      session.prefix +
        file.getText(sessions.rangeOf(file, session)) +
        session.suffix;
    session.region = {
      start: 0,
      end: whole.length,
      touched: session.region.touched || !unchanged,
    };
    session.prefix = '';
    session.suffix = '';
    clip = candidateText;
  }
  if (
    session.region.touched &&
    !(await confirm(
      'The baseline range changed since the diff was opened. Replace it with the candidate anyway?',
      REPLACE,
    ))
  ) {
    return false;
  }
  const baseline = file.getText(sessions.rangeOf(file, session));
  const filled = fillPlaceholders(baseline, clip);
  if (filled.unresolved.length) {
    const n = filled.unresolved.length;
    const ok = await confirm(
      `${n} placeholder line${n > 1 ? 's' : ''} could not be matched to the baseline. Apply ${n > 1 ? 'them' : 'it'} as text?`,
      APPLY_AS_TEXT,
    );
    if (!ok) return false;
  }
  clip = filled.text;
  const findings = checkCandidate(baseline, clip, await anchorRefs(file));
  if (findings.length) {
    const actions = [APPLY];
    if (findings.some((f) => f.kind === FINDING.CHECKBOX_RESET))
      actions.unshift(KEEP_BOXES);
    const choice = await vscode.window.showWarningMessage(
      'The candidate changes Markdown that other parts may depend on.',
      { modal: true, detail: findings.map((f) => `• ${f.message}`).join('\n') },
      ...actions,
    );
    if (!choice) return false;
    if (choice === KEEP_BOXES)
      clip = restoreCheckboxStates(baseline, clip).text;
  }
  const text = normalizeEol(
    clip,
    file.eol === vscode.EndOfLine.CRLF ? '\r\n' : '\n',
  );
  const edit = new vscode.WorkspaceEdit();
  edit.replace(file.uri, sessions.rangeOf(file, session), text);
  const ok = await sessions.applyOwn(session, 'file', edit);
  if (!ok) {
    vscode.window.showWarningMessage(
      'Markdown Workbench could not apply the candidate.',
    );
    return false;
  }
  session.region = { ...session.region, touched: false };
  if (session.shape === 'page') await sessions.mirrorToPage(session, text);
  vscode.window.setStatusBarMessage(
    'Markdown Workbench: candidate applied',
    3000,
  );
  return true;
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

/**
 * Heading ids that links point at: always the file's own links, and with
 * markdownWorkbench.clipboardDiff.checkWorkspaceAnchors on also the links of
 * every other Markdown file in the workspace (read only). id -> [sources].
 */
async function anchorRefs(file) {
  const refs = new Map();
  const add = (id, source) => refs.set(id, [...(refs.get(id) || []), source]);
  for (const id of collectAnchorRefs(file.getText())) add(id, 'this file');
  const workspaceWide = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get('clipboardDiff.checkWorkspaceAnchors', false);
  if (!workspaceWide || file.uri.scheme !== 'file') return refs;
  const name = file.uri.path.split('/').pop();
  const others = await vscode.workspace.findFiles(
    '**/*.md',
    '**/node_modules/**',
    2000,
  );
  for (const uri of others) {
    if (uri.toString() === file.uri.toString()) continue;
    const text = Buffer.from(await vscode.workspace.fs.readFile(uri)).toString(
      'utf8',
    );
    for (const id of collectAnchorRefs(text, name))
      add(id, vscode.workspace.asRelativePath(uri));
  }
  return refs;
}

module.exports = { applyCandidate, anchorRefs };
