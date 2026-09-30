// Hints on the candidate page of a clipboard diff: omission placeholders (F3)
// and the Markdown check (F4) as diagnostics, with one-click fixes as quick
// fixes - "fill placeholders from the baseline" and "keep checkbox states from
// the baseline" (docs/DECISIONS.md #48). Hints only, nothing blocks.

import * as vscode from 'vscode';
import { SCHEME } from './store.ts';
import { findPlaceholders, fillPlaceholders } from './unwrap.ts';
import {
  checkCandidate,
  restoreCheckboxStates,
  collectAnchorRefs,
  FINDING,
} from './check.ts';
import { splitLines } from './lines.ts';

const SOURCE = 'Markdown Workbench';
const PLACEHOLDER = 'placeholder';
/** Pause after the last keystroke before the candidate is checked again. */
const DIAGNOSTICS_DELAY_MS = 200;

class CandidateDiagnostics {
  constructor(sessions) {
    this.sessions = sessions;
    this.collection = vscode.languages.createDiagnosticCollection(
      'markdownWorkbench.clipboardDiff',
    );
    this.timers = new Map();
    this.refsCache = new WeakMap(); // session -> { version, refs }
  }

  /** Re-checks the session's candidate after DIAGNOSTICS_DELAY_MS. */
  schedule(session) {
    const key = session.candidateUri.toString();
    clearTimeout(this.timers.get(key));
    this.timers.set(
      key,
      setTimeout(() => {
        this.timers.delete(key);
        this.update(session).catch(() =>
          this.collection.delete(session.candidateUri),
        );
      }, DIAGNOSTICS_DELAY_MS),
    );
  }

  /** Checks the candidate now and publishes the diagnostics. */
  async update(session) {
    const ctx = await this.context(session);
    if (!ctx) {
      this.collection.delete(session.candidateUri);
      return;
    }
    const { baseline, clip, firstLine, file } = ctx;
    const diagnostics = [];
    for (const line of findPlaceholders(clip)) {
      diagnostics.push(
        this.diagnostic(
          firstLine + line,
          'Placeholder line: Apply Candidate fills in the baseline text it stands for.',
          vscode.DiagnosticSeverity.Warning,
          PLACEHOLDER,
        ),
      );
    }
    const refs = this.ownAnchorRefs(session, file);
    for (const f of checkCandidate(baseline, clip, refs)) {
      diagnostics.push(
        this.diagnostic(
          firstLine + (f.line ?? 0),
          f.message,
          vscode.DiagnosticSeverity.Information,
          f.kind,
        ),
      );
    }
    this.collection.set(session.candidateUri, diagnostics);
  }

  diagnostic(line, message, severity, code) {
    const d = new vscode.Diagnostic(
      new vscode.Range(line, 0, line, Number.MAX_SAFE_INTEGER),
      message,
      severity,
    );
    d.source = SOURCE;
    d.code = code;
    return d;
  }

  // Baseline region text, candidate clip part and where it starts in the page.
  async context(session) {
    const candidate = vscode.workspace.textDocuments.find(
      (d) => d.uri.toString() === session.candidateUri.toString(),
    );
    if (!candidate) return undefined;
    const clip = this.sessions.clipOf(session, candidate.getText());
    if (clip === undefined) return undefined;
    const file = await this.sessions.fileOf(session);
    if (!file) return undefined;
    return {
      candidate,
      clip,
      baseline: file.getText(this.sessions.rangeOf(file, session)),
      firstLine:
        session.shape === 'page' ? 0 : splitLines(session.prefix).length - 1,
      file,
    };
  }

  // The file's own #anchor links, parsed once per file version: the candidate
  // changes on every keystroke, the file rarely. The workspace-wide scan runs
  // only at Apply (apply.js).
  ownAnchorRefs(session, file) {
    const cached = this.refsCache.get(session);
    if (cached?.version === file.version) return cached.refs;
    const refs = new Map(
      [...collectAnchorRefs(file.getText())].map((id) => [id, ['this file']]),
    );
    this.refsCache.set(session, { version: file.version, refs });
    return refs;
  }

  forget(session) {
    clearTimeout(this.timers.get(session.candidateUri.toString()));
    this.timers.delete(session.candidateUri.toString());
    this.collection.delete(session.candidateUri);
  }

  dispose() {
    for (const t of this.timers.values()) clearTimeout(t);
    this.timers.clear();
    this.collection.dispose();
  }

  /** CodeActionProvider for the candidate pages. */
  async provideCodeActions(document, _range, context) {
    const codes = new Set(
      context.diagnostics.filter((d) => d.source === SOURCE).map((d) => d.code),
    );
    const session = this.sessions.forUri(document.uri);
    if (!session || !codes.size) return [];
    const ctx = await this.context(session);
    if (!ctx) return [];
    const actions = [];
    const fix = (title, text) => {
      if (text === ctx.clip) return;
      const action = new vscode.CodeAction(
        title,
        vscode.CodeActionKind.QuickFix,
      );
      action.edit = new vscode.WorkspaceEdit();
      action.edit.replace(
        document.uri,
        this.clipRange(document, session, ctx.clip),
        text,
      );
      action.diagnostics = context.diagnostics.filter(
        (d) => d.source === SOURCE,
      );
      actions.push(action);
    };
    if (codes.has(FINDING.CHECKBOX_RESET)) {
      fix(
        'Keep checkbox states from the baseline',
        restoreCheckboxStates(ctx.baseline, ctx.clip).text,
      );
    }
    if (codes.has(PLACEHOLDER)) {
      fix(
        'Fill placeholders from the baseline',
        fillPlaceholders(ctx.baseline, ctx.clip).text,
      );
    }
    return actions;
  }

  clipRange(document, session, clip) {
    const start = session.shape === 'page' ? 0 : session.prefix.length;
    return new vscode.Range(
      document.positionAt(start),
      document.positionAt(start + clip.length),
    );
  }

  /** Registers the quick-fix provider for the candidate pages. */
  register() {
    return vscode.languages.registerCodeActionsProvider(
      { scheme: SCHEME },
      {
        provideCodeActions: (doc, range, ctx) =>
          this.provideCodeActions(doc, range, ctx),
      },
      { providedCodeActionKinds: [vscode.CodeActionKind.QuickFix] },
    );
  }
}

export { CandidateDiagnostics, DIAGNOSTICS_DELAY_MS, PLACEHOLDER };
