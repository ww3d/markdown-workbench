// Shared vscode API mock. Registered with the module hooks (vscode-hooks.ts) so
// that `import * as vscode from 'vscode'` inside the extension sources resolves
// to this object.
// Provides editable documents and editors rich enough to drive the editing
// commands end to end and to capture WorkspaceEdits from the toggle paths.
//
// The types describe the mock as the tests drive it, not the vscode API: the
// sources are checked against @types/vscode, the tests against these. Values a
// source hands to the mock (providers, listeners, panels) stay `unknown` in
// their arguments; a test narrows what it reads.

import { nextGeneration, registerMock } from './vscode-hooks.ts';

/** A zero-based line/character position. */
class Position {
  line: number;
  character: number;
  constructor(line: number, character: number) {
    this.line = line;
    this.character = character;
  }
  translate(dl: number, dc: number): Position {
    return new Position(this.line + dl, this.character + dc);
  }
}

/** A range between two positions, built from them or from four numbers. */
class Range {
  start: Position;
  end: Position;
  constructor(start: Position, end: Position);
  constructor(
    startLine: number,
    startCharacter: number,
    endLine: number,
    endCharacter: number,
  );
  constructor(
    a: Position | number,
    b: Position | number,
    c?: number,
    d?: number,
  ) {
    if (typeof a === 'number') {
      this.start = new Position(a, numberArg(b));
      this.end = new Position(numberArg(c), numberArg(d));
    } else {
      this.start = a;
      this.end = positionArg(b);
    }
  }
  get isEmpty(): boolean {
    return (
      this.start.line === this.end.line &&
      this.start.character === this.end.character
    );
  }
}

// The overloads keep the argument kinds apart; these narrow them for the
// implementation signature, where a mixed call is a caller error.
function numberArg(v: Position | number | undefined): number {
  if (typeof v !== 'number') throw new TypeError('Range: expected a number');
  return v;
}

function positionArg(v: Position | number): Position {
  if (typeof v === 'number') throw new TypeError('Range: expected a Position');
  return v;
}

/** A selection; `active` is its end, `anchor` its start. */
class Selection extends Range {
  active: Position;
  anchor: Position;
  constructor(anchor: Position, active: Position);
  constructor(
    anchorLine: number,
    anchorCharacter: number,
    activeLine: number,
    activeCharacter: number,
  );
  constructor(
    a: Position | number,
    b: Position | number,
    c?: number,
    d?: number,
  ) {
    if (typeof a === 'number')
      super(a, numberArg(b), numberArg(c), numberArg(d));
    else super(a, positionArg(b));
    this.active = this.end;
    this.anchor = this.start;
  }
}

/** A snippet as the sources build it; only its text is kept. */
class SnippetString {
  value: string;
  constructor(value: string) {
    this.value = value;
  }
}

/** An edit-builder operation on one document. */
type EditOp =
  | { kind: 'insert'; pos: Position; text: string }
  | { kind: 'delete'; range: Range }
  | { kind: 'replace'; range: Range; text: string };

/** A WorkspaceEdit operation: an edit-builder operation plus its document. */
type WorkspaceEditOp = EditOp & { uri: MockUri };

// Where an operation starts; operations apply from the last start backwards.
function opStart(op: EditOp): Position {
  return op.kind === 'insert' ? op.pos : op.range.start;
}

/** Records replace/delete/insert operations; applyEdit applies them. */
class WorkspaceEdit {
  ops: WorkspaceEditOp[];
  constructor() {
    this.ops = [];
  }
  replace(uri: MockUri, range: Range, text: string): void {
    this.ops.push({ kind: 'replace', uri, range, text });
  }
  delete(uri: MockUri, range: Range): void {
    this.ops.push({ kind: 'delete', uri, range });
  }
  insert(uri: MockUri, pos: Position, text: string): void {
    this.ops.push({ kind: 'insert', uri, pos, text });
  }
}

/** A Uri-like value as the mock builds it. */
interface MockUri {
  scheme: string;
  path: string;
  fsPath: string;
  toString(): string;
}

/** A line of a mock document; `text` is undefined past the last line. */
interface MockTextLine {
  text: string | undefined;
  lineNumber: number;
  range: Range;
}

/** Options of MockDocument.save, as document.save takes them. */
interface SaveOptions {
  skipParticipants?: boolean;
}

// An editable in-memory text document. `uri` is a string (legacy form, file
// scheme) or a Uri-like object from Uri.from / Uri.file / Uri.parse.
class MockDocument {
  lines: string[];
  uri: MockUri;
  version: number;
  _history: string[][];
  isDirty: boolean;
  languageId: string;
  eol: number;
  saves: number;
  /** Writes the document; set by the owning mock. */
  onSave: ((doc: MockDocument) => boolean | Promise<boolean>) | null;
  /** Save participants and will-save; set by the owning mock. */
  onWillSave: ((doc: MockDocument) => void | Promise<void>) | null;
  /** Did-save notification; set by the owning mock. */
  onDidSave: ((doc: MockDocument) => void) | null;
  constructor(text: string, uri?: string | MockUri) {
    this.lines = text.split('\n');
    this.uri =
      uri && typeof uri === 'object'
        ? uri
        : {
            toString: () => uri || 'mock://doc.md',
            scheme: 'file',
            fsPath: '/ws/doc.md',
            path: '/ws/doc.md',
          };
    this.version = 1;
    this._history = [];
    this.isDirty = false;
    this.languageId = 'markdown';
    this.eol = 1; // EndOfLine.LF
    this.saves = 0;
    this.onSave = null; // (doc) => Promise<boolean>, set by the owning mock
    this.onWillSave = null; // (doc) => Promise, set by the owning mock
    this.onDidSave = null; // (doc) => void, set by the owning mock
  }
  // The text of line `n`; a line past the end is a caller error.
  _line(n: number): string {
    const text = this.lines[n];
    if (text === undefined) throw new RangeError(`no line ${n}`);
    return text;
  }
  offsetAt(pos: Position): number {
    let off = 0;
    for (let l = 0; l < pos.line; l++) off += this._line(l).length + 1;
    return off + pos.character;
  }
  positionAt(offset: number): Position {
    let rest = Math.max(0, offset);
    for (let l = 0; l < this.lines.length; l++) {
      const length = this._line(l).length;
      if (rest <= length) return new Position(l, rest);
      rest -= length + 1;
    }
    const last = this.lines.length - 1;
    return new Position(last, this._line(last).length);
  }
  // Like an extension's document.save(): save participants and will-save (both
  // in onWillSave, set by the owning mock), write through onSave, then did-save.
  save(options: SaveOptions = {}): Promise<boolean> {
    this.saves++;
    const willSave = options.skipParticipants ? null : this.onWillSave;
    let written: number | undefined;
    return Promise.resolve(willSave?.(this))
      .then(() => {
        written = this.version; // an edit after this point stays unsaved
        return this.onSave ? this.onSave(this) : true;
      })
      .then((ok) => {
        if (ok) {
          this.isDirty = this.version !== written;
          this.onDidSave?.(this);
        }
        return ok;
      });
  }
  get lineCount(): number {
    return this.lines.length;
  }
  lineAt(line: number | Position): MockTextLine {
    const n = typeof line === 'number' ? line : line.line;
    const text = this.lines[n];
    return {
      text,
      lineNumber: n,
      range: new Range(n, 0, n, (text || '').length),
    };
  }
  getText(range?: Range): string {
    if (!range) return this.lines.join('\n');
    if (range.start.line === range.end.line) {
      return this._line(range.start.line).slice(
        range.start.character,
        range.end.character,
      );
    }
    const parts = [this._line(range.start.line).slice(range.start.character)];
    for (let l = range.start.line + 1; l < range.end.line; l++)
      parts.push(this._line(l));
    parts.push(this._line(range.end.line).slice(0, range.end.character));
    return parts.join('\n');
  }
  getWordRangeAtPosition(pos: Position): Range | undefined {
    const text = this._line(pos.line);
    let s = pos.character,
      e = pos.character;
    while (s > 0 && /\w/.test(text.charAt(s - 1))) s--;
    while (e < text.length && /\w/.test(text.charAt(e))) e++;
    return s === e ? undefined : new Range(pos.line, s, pos.line, e);
  }
  // Apply edit-builder operations (single line ops only - all the editing
  // commands operate that way, multi-line replaces use start/end columns).
  // Restore the text before the last edit() call - one call is one undo step,
  // like a single TextEditor.edit in VS Code.
  undo(): void {
    const previous = this._history.pop();
    if (previous) this.lines = previous;
    this.version++;
  }
  _apply(ops: EditOp[]): void {
    this._history.push(this.lines.slice());
    this.version++;
    // Apply bottom-up / right-to-left so positions stay valid.
    ops.sort((a, b) => {
      const sa = opStart(a);
      const sb = opStart(b);
      if (sa.line !== sb.line) return sb.line - sa.line;
      return sb.character - sa.character;
    });
    for (const op of ops) {
      if (op.kind === 'insert') {
        const { line, character } = op.pos;
        const txt = this._line(line);
        const merged = txt.slice(0, character) + op.text + txt.slice(character);
        this.lines.splice(line, 1, ...merged.split('\n'));
      } else {
        const { start, end } = op.range;
        const head = this._line(start.line).slice(0, start.character);
        const tail = this._line(end.line).slice(end.character);
        const replacement = op.kind === 'replace' ? op.text : '';
        const merged = head + replacement + tail;
        this.lines.splice(
          start.line,
          end.line - start.line + 1,
          ...merged.split('\n'),
        );
      }
    }
  }
}

/** The builder a TextEditor.edit callback receives. */
interface MockEditBuilder {
  insert(pos: Position, text: string): void;
  delete(range: Range): void;
  replace(range: Range, text: string): void;
}

/** A text editor on a mock document; records snippets, reveals and edit calls. */
class MockEditor {
  document: MockDocument;
  selection: Selection;
  selections: Selection[];
  insertedSnippets: { snippet: SnippetString; location: unknown }[];
  revealed: { range: Range; type: unknown }[];
  editCalls: number;
  options: { tabSize: number; insertSpaces: boolean };
  visibleRanges: Range[];
  constructor(document: MockDocument, selection?: Selection) {
    this.document = document;
    this.selection = selection || new Selection(0, 0, 0, 0);
    this.selections = [this.selection];
    this.insertedSnippets = [];
    this.revealed = [];
    this.editCalls = 0;
    this.options = { tabSize: 4, insertSpaces: true };
    this.visibleRanges = [
      new Range(0, 0, Math.max(0, document.lineCount - 1), 0),
    ];
  }
  edit(cb: (builder: MockEditBuilder) => void): Promise<boolean> {
    this.editCalls++;
    const ops: EditOp[] = [];
    cb({
      insert: (pos, text) => ops.push({ kind: 'insert', pos, text }),
      delete: (range) => ops.push({ kind: 'delete', range }),
      replace: (range, text) => ops.push({ kind: 'replace', range, text }),
    });
    this.document._apply(ops);
    return Promise.resolve(true);
  }
  insertSnippet(snippet: SnippetString, location?: unknown): Promise<boolean> {
    this.insertedSnippets.push({ snippet, location });
    return Promise.resolve(true);
  }
  revealRange(range: Range, type?: unknown): void {
    this.revealed.push({ range, type });
  }
}

// Wraps a synchronous mock body into a promise-returning API function (throws
// become rejections), like the async VS Code API it stands in for.
function settle<A extends unknown[], R>(
  fn: (...args: A) => Promise<R>,
): (...args: A) => Promise<R>;
function settle<A extends unknown[], R>(
  fn: (...args: A) => R,
): (...args: A) => Promise<R>;
function settle<A extends unknown[], R>(fn: (...args: A) => R | Promise<R>) {
  return (...args: A): Promise<R> => Promise.resolve().then(() => fn(...args));
}

// --- Clipboard-diff surface: events, file systems, tabs, diagnostics ---------

/** Runs its callback once on dispose. */
class Disposable {
  _fn: (() => void) | null;
  constructor(fn: () => void) {
    this._fn = fn;
  }
  dispose(): void {
    if (this._fn) this._fn();
    this._fn = null;
  }
}

/** A listener as a source registers it; tests call it with any event. */
type Listener = (event: unknown) => unknown;

/** An event source: `event` subscribes, `fire` notifies every listener. */
class EventEmitter<T = unknown> {
  listeners: ((e: T) => unknown)[];
  event: (f: (e: T) => unknown) => Disposable;
  constructor() {
    this.listeners = [];
    this.event = (f) => {
      this.listeners.push(f);
      return new Disposable(() => {
        this.listeners = this.listeners.filter((l) => l !== f);
      });
    };
  }
  fire(e: T): void {
    for (const l of this.listeners.slice()) l(e);
  }
  dispose(): void {
    this.listeners = [];
  }
}

// Uri-like value with a stable string form "<scheme>:<path>".
function makeUri(scheme: string, path: string): MockUri {
  return {
    scheme,
    path,
    fsPath: path,
    toString: () => `${scheme}:${path}`,
  };
}

/** A file-system error with the `code` VS Code sets on its factories' results. */
class FileSystemError extends Error {
  code?: string;
  static FileNotFound(uri: unknown): FileSystemError {
    const e = new FileSystemError(`FileNotFound: ${uri}`);
    e.code = 'FileNotFound';
    return e;
  }
  static FileExists(uri: unknown): FileSystemError {
    const e = new FileSystemError(`FileExists: ${uri}`);
    e.code = 'FileExists';
    return e;
  }
}

/** An editor tab input on one document. */
class TabInputText {
  uri: MockUri;
  constructor(uri: MockUri) {
    this.uri = uri;
  }
}

/** A diff tab input. */
class TabInputTextDiff {
  original: MockUri;
  modified: MockUri;
  constructor(original: MockUri, modified: MockUri) {
    this.original = original;
    this.modified = modified;
  }
}

/** A diagnostic as the sources create it. */
class Diagnostic {
  range: Range;
  message: string;
  severity: number | undefined;
  constructor(range: Range, message: string, severity?: number) {
    this.range = range;
    this.message = message;
    this.severity = severity;
  }
}

/** A code action as the sources create it. */
class CodeAction {
  title: string;
  kind: unknown;
  constructor(title: string, kind?: unknown) {
    this.title = title;
    this.kind = kind;
  }
}

/** A completion item as the sources create it. */
class CompletionItem {
  label: unknown;
  kind: unknown;
  constructor(label: unknown, kind?: unknown) {
    this.label = label;
    this.kind = kind;
  }
}

/** A paste edit as the sources create it. */
class DocumentPasteEdit {
  insertText: unknown;
  title: string;
  kind: unknown;
  constructor(insertText: unknown, title: string, kind: unknown) {
    this.insertText = insertText;
    this.title = title;
    this.kind = kind;
  }
}

/** The file-system provider members the mock calls; a source's provider has more. */
interface MockFsProvider {
  readFile(uri: MockUri): Uint8Array;
  writeFile(
    uri: MockUri,
    content: Uint8Array,
    options: { create: boolean; overwrite: boolean },
  ): void;
  stat(uri: MockUri): unknown;
  [member: string]: unknown;
}

/** An editor tab: its input, label and, where a test sets it, unsaved state. */
interface MockTab {
  input: unknown;
  label: string;
  isDirty?: boolean;
}

/** An editor group of the mock's tab model. */
interface MockTabGroup {
  tabs: MockTab[];
  activeTab: MockTab | undefined;
  isActive: boolean;
}

/** The change event of the tab model. */
interface MockTabChange {
  opened: MockTab[];
  closed: MockTab[];
  changed: MockTab[];
}

/** A document change as onDidChangeTextDocument reports it. */
interface MockDocumentChange {
  document: MockDocument;
  contentChanges: {
    range: Range;
    rangeOffset: number;
    rangeLength: number;
    text: string;
  }[];
}

/** The will-save event; `waitUntil` holds the save until its promise settles. */
interface MockWillSaveEvent {
  document: MockDocument;
  waitUntil(p: Promise<unknown>): void;
}

/** The provider the extension registers with `registerCustomEditorProvider`. */
interface MockCustomEditorProvider {
  resolveCustomTextEditor(
    document: MockDocument,
    panel: unknown,
    token?: unknown,
  ): unknown;
}

/** A diagnostic collection keyed by the document's Uri string. */
interface MockDiagnosticCollection {
  set(uri: MockUri, list: unknown): void;
  delete(uri: MockUri): void;
  get(uri: MockUri): unknown;
  dispose(): void;
}

// Resolves a prompt answer the test set: a value, or a function of the call.
function answer(r: unknown, ...args: unknown[]): unknown {
  return typeof r === 'function' ? r(...args) : r;
}

// Offset-based text replace used by the live applyEdit path below; returns the
// contentChanges entry VS Code would report.
function replaceInDocument(doc: MockDocument, range: Range, text: string) {
  const start = doc.offsetAt(range.start);
  const end = doc.offsetAt(range.end);
  const full = doc.getText();
  doc.lines = (full.slice(0, start) + text + full.slice(end)).split('\n');
  doc.version++;
  return { range, rangeOffset: start, rangeLength: end - start, text };
}

// A Uri-like value the sources hand to a command (vscode.diff).
function isMockUri(v: unknown): v is MockUri {
  return typeof v === 'object' && v !== null && 'scheme' in v && 'path' in v;
}

// Throws like calling an unset function member did: a test that needs the
// member sets it first.
function required<T>(value: T | undefined, name: string): T {
  if (value === undefined) throw new TypeError(`mock.${name} is not set`);
  return value;
}

/** What a registration returns. */
interface MockDisposable {
  dispose(): void;
}

/** The mock's tab model: one group to start, `_addGroup` adds more. */
interface MockTabGroups {
  all: MockTabGroup[];
  activeTabGroup: MockTabGroup;
  onDidChangeTabs: (f: (e: MockTabChange) => unknown) => Disposable;
  close(tabs: MockTab | MockTab[]): Promise<boolean>;
}

/**
 * The installed mock: the vscode API members the sources use, plus the state the
 * tests set up and read (the `_`-prefixed members). Optional members appear only
 * once the matching API ran.
 */
type VscodeMock = {
  Position: typeof Position;
  Range: typeof Range;
  Selection: typeof Selection;
  SnippetString: typeof SnippetString;
  WorkspaceEdit: typeof WorkspaceEdit;
  Uri: {
    from(parts: { scheme: string; path: string }): MockUri;
    joinPath(...parts: unknown[]): string;
    file(p: string): MockUri;
    parse(s: string): MockUri;
  };
  ViewColumn: { Active: number; Beside: number; One: number; Two: number };
  TextEditorRevealType: { AtTop: number; Default: number };
  ConfigurationTarget: { Global: number };
  CompletionItem: typeof CompletionItem;
  CompletionItemKind: { Value: number };
  DocumentPasteEdit: typeof DocumentPasteEdit;
  DocumentDropOrPasteEditKind: {
    Empty: { value: string; append(...p: string[]): { value: string } };
    Text: { value: string };
  };
  EndOfLine: { LF: number; CRLF: number };
  Disposable: typeof Disposable;
  EventEmitter: typeof EventEmitter;
  FileSystemError: typeof FileSystemError;
  FileType: { File: number; Directory: number };
  FileChangeType: { Changed: number; Created: number; Deleted: number };
  TabInputText: typeof TabInputText;
  TabInputTextDiff: typeof TabInputTextDiff;
  Diagnostic: typeof Diagnostic;
  DiagnosticSeverity: {
    Error: number;
    Warning: number;
    Information: number;
    Hint: number;
  };
  CodeAction: typeof CodeAction;
  CodeActionKind: { QuickFix: string; RefactorRewrite: string };

  /** Every executeCommand call, in order. */
  _executed: { id: string; args: unknown[] }[];
  /** Every WorkspaceEdit operation passed to applyEdit. */
  _applied: WorkspaceEditOp[];
  /** Settings getConfiguration().get reads, by key. */
  _config: Record<string, unknown>;
  /** Answer of showQuickPick: a value or `(items) => value`. */
  _quickPickResult: unknown;
  _inputBoxResult: unknown;
  // Clipboard-diff state: clipboard text, answers for modal warnings (a value
  // or a function (message, ...items) => value), recorded messages, context
  // keys, registered file-system and code-action providers, per-command
  // handlers for executeCommand.
  _clipboard: string;
  _warningResult: unknown;
  _warnings: { message: unknown; rest: unknown[] }[];
  _errors: unknown[];
  _statusMessages: unknown[];
  _context: Record<string, unknown>;
  _fsProviders: Record<string, MockFsProvider>;
  _fsWrites: { uri: MockUri; content: Uint8Array }[];
  // applyEdit resolves to this (false = VS Code refused the edit); a save
  // participant (doc) => void|Promise runs inside every document.save(), before
  // the write; _afterWrite (doc) => void|Promise runs after it, before did-save.
  _applyEditResult: boolean;
  _saveParticipant: ((doc: MockDocument) => unknown) | null;
  _afterWrite: ((doc: MockDocument) => unknown) | null;
  _codeActionProviders: {
    selector: unknown;
    provider: unknown;
    meta: unknown;
  }[];
  _commandHandlers: Record<string, (...args: unknown[]) => unknown>;
  _docChangeListeners: Listener[];

  commands: {
    registerCommand(
      id: string,
      fn: (...args: unknown[]) => unknown,
    ): MockDisposable;
    executeCommand(id: string, ...args: unknown[]): Promise<unknown>;
  };
  window: {
    activeTextEditor: MockEditor | undefined;
    visibleTextEditors: MockEditor[];
    activeColorTheme: { kind: number };
    registerCustomEditorProvider(
      id: string,
      provider: MockCustomEditorProvider,
      options?: unknown,
    ): MockDisposable;
    onDidChangeTextEditorVisibleRanges(f: Listener): MockDisposable;
    onDidChangeTextEditorSelection(f: Listener): MockDisposable;
    onDidChangeActiveTextEditor(f: Listener): MockDisposable;
    onDidChangeActiveColorTheme(f: Listener): MockDisposable;
    showInformationMessage(msg: unknown): void;
    showQuickPick(items: unknown, options?: unknown): Promise<unknown>;
    showWarningMessage(message: unknown, ...rest: unknown[]): Promise<unknown>;
    showErrorMessage(message: unknown): Promise<void>;
    setStatusBarMessage(message: unknown): MockDisposable;
    tabGroups: MockTabGroups;
    showInputBox(options?: unknown): Promise<unknown>;
    showTextDocument(document: MockDocument): Promise<MockEditor>;
    createWebviewPanel(...args: unknown[]): unknown;
    registerWebviewPanelSerializer(
      viewType: string,
      serializer: unknown,
    ): MockDisposable;
  };
  env: {
    clipboard: {
      readText(): Promise<string>;
      writeText(text: string): Promise<void>;
    };
  };
  workspace: {
    textDocuments: MockDocument[];
    onWillSaveTextDocument(f: (e: MockWillSaveEvent) => unknown): Disposable;
    onDidSaveTextDocument(f: (doc: MockDocument) => unknown): Disposable;
    registerFileSystemProvider(
      scheme: string,
      provider: MockFsProvider,
    ): MockDisposable;
    fs: {
      readFile(uri: MockUri): Promise<Uint8Array>;
      writeFile(uri: MockUri, content: Uint8Array): Promise<void>;
      stat(uri: MockUri): Promise<unknown>;
    };
    getConfiguration(section?: string): {
      get(key: string, dflt?: unknown): unknown;
    };
    applyEdit(edit: WorkspaceEdit): Promise<boolean>;
    onDidChangeTextDocument(f: Listener): MockDisposable;
    onDidCloseTextDocument(f: Listener): MockDisposable;
    onDidChangeConfiguration(f: Listener): MockDisposable;
    openTextDocument(uri?: MockUri | string): Promise<MockDocument>;
    onDidOpenTextDocument(f: Listener): MockDisposable;
    findFiles(...args: unknown[]): Promise<unknown[]>;
    asRelativePath(uri: MockUri): string;
  };
  languages: {
    createDiagnosticCollection(name?: string): MockDiagnosticCollection;
    registerCodeActionsProvider(
      selector: unknown,
      provider: unknown,
      meta?: unknown,
    ): MockDisposable;
    setTextDocumentLanguage(
      doc: MockDocument,
      languageId: string,
    ): Promise<MockDocument>;
    registerCompletionItemProvider(
      selector: unknown,
      provider: unknown,
      ...triggers: string[]
    ): MockDisposable;
    registerDocumentPasteEditProvider(
      selector: unknown,
      provider: unknown,
      meta?: unknown,
    ): MockDisposable;
  };
  extensions: { all: unknown[] };

  MockDocument: typeof MockDocument;
  MockEditor: typeof MockEditor;

  _willSave: EventEmitter<MockWillSaveEvent>;
  _didSave: EventEmitter<MockDocument>;
  /** Reports a document change to every onDidChangeTextDocument listener. */
  _fireDocChange(e: MockDocumentChange): void;
  /** Opens a tab with `input` in the active group and makes it active. */
  _openTab(input: unknown): MockTab;
  _closeTab(tab: MockTab): Promise<boolean>;
  /** Adds a second editor group (split editor); `activate` makes it the active one. */
  _addGroup(activate?: boolean): MockTabGroup;

  _commands?: Record<string, (...args: unknown[]) => unknown>;
  _customEditorProvider?: MockCustomEditorProvider;
  _customEditorOptions?: unknown;
  _selectionListener?: Listener;
  _activeEditorListener?: Listener;
  _themeListener?: Listener;
  _infos?: unknown[];
  _quickPickCalls?: { items: unknown; options: unknown }[];
  _panelArgs?: unknown[];
  /** Builds the panel createWebviewPanel returns; a test sets it first. */
  _panelFactory?: () => unknown;
  _panelSerializers?: Record<string, unknown>;
  _docChangeListener?: Listener;
  _docCloseListener?: Listener;
  _configListener?: Listener;
  _docOpenListener?: Listener;
  _diagnostics?: Map<string, unknown>;
  _codeActionProvider?: unknown;
  _codeActionMeta?: unknown;
  _completionProvider?: unknown;
  _pasteProvider?: unknown;
  _pasteMeta?: unknown;
  _savedWithoutFormatting?: number;
};

function createMock(): VscodeMock {
  const willSave = new EventEmitter<MockWillSaveEvent>();
  const didSave = new EventEmitter<MockDocument>();
  // Tabs: one group; a tab is { input, label }. vscode.diff opens a diff tab
  // and swapSides swaps the active one, like the real commands.
  const tabsChanged = new EventEmitter<MockTabChange>();
  const group: MockTabGroup = {
    tabs: [],
    activeTab: undefined,
    isActive: true,
  };
  const tabGroups: MockTabGroups = {
    all: [group],
    activeTabGroup: group,
    onDidChangeTabs: tabsChanged.event,
    close: settle((tabs: MockTab | MockTab[]) => {
      const list = Array.isArray(tabs) ? tabs : [tabs];
      for (const g of mock.window.tabGroups.all) {
        g.tabs = g.tabs.filter((t) => !list.includes(t));
        if (g.activeTab && list.includes(g.activeTab))
          g.activeTab = g.tabs.at(-1);
      }
      tabsChanged.fire({ opened: [], closed: list, changed: [] });
      return true;
    }),
  };

  const mock: VscodeMock = {
    Position,
    Range,
    Selection,
    SnippetString,
    WorkspaceEdit,
    Uri: {
      from: ({ scheme, path }) => makeUri(scheme, path),
      joinPath: (...parts) => parts.join('/'),
      file: (p) => ({
        fsPath: p,
        path: p,
        scheme: 'file',
        toString: () => `file://${p}`,
      }),
      parse: (s) => ({
        fsPath: s,
        path: s,
        scheme: String(s).split(':')[0] || 'file',
        toString: () => String(s),
      }),
    },
    ViewColumn: { Active: -1, Beside: -2, One: 1, Two: 2 },
    TextEditorRevealType: { AtTop: 3, Default: 0 },
    ConfigurationTarget: { Global: 1 },
    CompletionItem,
    CompletionItemKind: { Value: 12 },
    DocumentPasteEdit,
    DocumentDropOrPasteEditKind: {
      Empty: { value: '', append: (...p) => ({ value: p.join('.') }) },
      Text: { value: 'text' },
    },
    EndOfLine: { LF: 1, CRLF: 2 },
    Disposable,
    EventEmitter,
    FileSystemError,
    FileType: { File: 1, Directory: 2 },
    FileChangeType: { Changed: 1, Created: 2, Deleted: 3 },
    TabInputText,
    TabInputTextDiff,
    Diagnostic,
    DiagnosticSeverity: { Error: 0, Warning: 1, Information: 2, Hint: 3 },
    CodeAction,
    CodeActionKind: {
      QuickFix: 'quickfix',
      RefactorRewrite: 'refactor.rewrite',
    },

    _executed: [],
    _applied: [],
    _config: {},
    _quickPickResult: undefined,
    _inputBoxResult: undefined,
    _clipboard: '',
    _warningResult: undefined,
    _warnings: [],
    _errors: [],
    _statusMessages: [],
    _context: {},
    _fsProviders: {},
    _fsWrites: [],
    _applyEditResult: true,
    _saveParticipant: null,
    _afterWrite: null,
    _codeActionProviders: [],
    _commandHandlers: {},
    _docChangeListeners: [],

    commands: {
      registerCommand: (id, fn) => {
        mock._commands = mock._commands || {};
        mock._commands[id] = fn;
        return { dispose() {} };
      },
      executeCommand: (id, ...args) => {
        mock._executed.push({ id, args });
        const handler = mock._commandHandlers[id];
        return Promise.resolve(handler ? handler(...args) : undefined);
      },
    },
    window: {
      activeTextEditor: undefined,
      visibleTextEditors: [],
      activeColorTheme: { kind: 2 },
      registerCustomEditorProvider: (_id, provider, options) => {
        mock._customEditorProvider = provider;
        mock._customEditorOptions = options;
        return { dispose() {} };
      },
      onDidChangeTextEditorVisibleRanges: () => ({ dispose() {} }),
      onDidChangeTextEditorSelection: (f) => {
        mock._selectionListener = f;
        return { dispose() {} };
      },
      onDidChangeActiveTextEditor: (f) => {
        mock._activeEditorListener = f;
        return { dispose() {} };
      },
      onDidChangeActiveColorTheme: (f) => {
        mock._themeListener = f;
        return { dispose() {} };
      },
      showInformationMessage: (msg) => {
        mock._infos = mock._infos || [];
        mock._infos.push(msg);
      },
      showQuickPick: async (items, options) => {
        mock._quickPickCalls = mock._quickPickCalls || [];
        mock._quickPickCalls.push({ items: await items, options });
        return answer(mock._quickPickResult, await items);
      },
      showWarningMessage: settle((message: unknown, ...rest: unknown[]) => {
        mock._warnings.push({ message, rest });
        return answer(mock._warningResult, message, ...rest);
      }),
      showErrorMessage: settle((message: unknown) => {
        mock._errors.push(message);
      }),
      setStatusBarMessage: (message) => {
        mock._statusMessages.push(message);
        return { dispose() {} };
      },
      tabGroups,
      showInputBox: async () => mock._inputBoxResult,
      showTextDocument: (document) => {
        const editor = new MockEditor(document);
        mock.window.activeTextEditor = editor;
        return Promise.resolve(editor);
      },
      createWebviewPanel: (...args) => {
        mock._panelArgs = args;
        return required(mock._panelFactory, '_panelFactory')();
      },
      registerWebviewPanelSerializer: (viewType, serializer) => {
        mock._panelSerializers = mock._panelSerializers || {};
        mock._panelSerializers[viewType] = serializer;
        return { dispose() {} };
      },
    },
    env: {
      clipboard: {
        readText: async () => mock._clipboard,
        writeText: settle((t: string) => {
          mock._clipboard = t;
        }),
      },
    },
    workspace: {
      textDocuments: [],
      onWillSaveTextDocument: (f) => mock._willSave.event(f),
      onDidSaveTextDocument: (f) => mock._didSave.event(f),
      registerFileSystemProvider: (scheme, provider) => {
        mock._fsProviders[scheme] = provider;
        return { dispose() {} };
      },
      fs: {
        readFile: settle((uri: MockUri): Uint8Array => {
          const provider = mock._fsProviders[uri.scheme];
          if (provider) return provider.readFile(uri);
          const doc = mock.workspace.textDocuments.find(
            (d) => d.uri.toString() === uri.toString(),
          );
          if (!doc) throw FileSystemError.FileNotFound(uri);
          return Buffer.from(doc.getText(), 'utf8');
        }),
        // Through the registered provider like VS Code; only a scheme without
        // one (a disk-backed file) counts as a write in _fsWrites.
        writeFile: settle((uri: MockUri, content: Uint8Array) => {
          const provider = mock._fsProviders[uri.scheme];
          if (provider) {
            provider.writeFile(uri, content, { create: true, overwrite: true });
            return;
          }
          mock._fsWrites.push({ uri, content });
        }),
        stat: settle((uri: MockUri): unknown => {
          const provider = mock._fsProviders[uri.scheme];
          if (provider) return provider.stat(uri);
          const doc = mock.workspace.textDocuments.find(
            (d) => d.uri.toString() === uri.toString(),
          );
          if (!doc) throw FileSystemError.FileNotFound(uri);
          return { type: 1, size: Buffer.byteLength(doc.getText()) };
        }),
      },
      getConfiguration: () => ({
        get: (key, dflt) => (key in mock._config ? mock._config[key] : dflt),
      }),
      // Records every op; ops on a document in workspace.textDocuments are
      // also applied to it and reported to all change listeners, like VS Code.
      applyEdit: (edit) => {
        mock._applied.push(...edit.ops);
        if (mock._applyEditResult === false) return Promise.resolve(false);
        const byDoc = new Map<MockDocument, WorkspaceEditOp[]>();
        for (const op of edit.ops) {
          const doc = mock.workspace.textDocuments.find(
            (d) => d.uri.toString() === op.uri.toString(),
          );
          if (!doc) continue;
          let list = byDoc.get(doc);
          if (!list) {
            list = [];
            byDoc.set(doc, list);
          }
          list.push(op);
        }
        for (const [doc, ops] of byDoc) {
          ops.sort(
            (a, b) => doc.offsetAt(opStart(b)) - doc.offsetAt(opStart(a)),
          );
          const contentChanges = ops.map((op) =>
            op.kind === 'insert'
              ? replaceInDocument(doc, new Range(op.pos, op.pos), op.text)
              : replaceInDocument(
                  doc,
                  op.range,
                  op.kind === 'delete' ? '' : op.text,
                ),
          );
          doc.isDirty = true;
          mock._fireDocChange({ document: doc, contentChanges });
        }
        return Promise.resolve(true);
      },
      onDidChangeTextDocument: (f) => {
        mock._docChangeListener = f;
        mock._docChangeListeners.push(f);
        return {
          dispose: () => {
            if (mock._docChangeListener === f)
              mock._docChangeListener = undefined;
            mock._docChangeListeners = mock._docChangeListeners.filter(
              (l) => l !== f,
            );
          },
        };
      },
      onDidCloseTextDocument: (f) => {
        mock._docCloseListener = f;
        return {
          dispose: () => {
            if (mock._docCloseListener === f)
              mock._docCloseListener = undefined;
          },
        };
      },
      onDidChangeConfiguration: (f) => {
        mock._configListener = f;
        return {
          dispose: () => {
            if (mock._configListener === f) mock._configListener = undefined;
          },
        };
      },
      // Known documents first, then pages of a registered file system (read
      // through the provider, saved back to it), else an empty legacy doc.
      openTextDocument: settle((uri?: MockUri | string): MockDocument => {
        const known = mock.workspace.textDocuments.find(
          (d) => d.uri.toString() === String(uri),
        );
        if (known) return known;
        const provider =
          uri && typeof uri === 'object'
            ? mock._fsProviders[uri.scheme]
            : undefined;
        if (!provider || typeof uri !== 'object')
          return new MockDocument('', String(uri));
        const text = Buffer.from(provider.readFile(uri)).toString('utf8');
        const doc = new MockDocument(text, uri);
        // Save participants first, then will-save, as measured on VS Code 1.100;
        // a will-save listener may hold the save with waitUntil, as in VS Code.
        doc.onWillSave = async (d) => {
          if (mock._saveParticipant) await mock._saveParticipant(d);
          const waits: Promise<unknown>[] = [];
          mock._willSave.fire({
            document: d,
            waitUntil: (p) => waits.push(p),
          });
          await Promise.all(waits);
        };
        doc.onDidSave = (d) => mock._didSave.fire(d);
        doc.onSave = settle(async (d: MockDocument) => {
          provider.writeFile(uri, Buffer.from(d.getText(), 'utf8'), {
            create: true,
            overwrite: true,
          });
          if (mock._afterWrite) await mock._afterWrite(d);
          return true;
        });
        mock.workspace.textDocuments.push(doc);
        return doc;
      }),
      onDidOpenTextDocument: (f) => {
        mock._docOpenListener = f;
        return { dispose() {} };
      },
      findFiles: async () => [],
      asRelativePath: (uri) => uri.path,
    },
    languages: {
      createDiagnosticCollection: () => {
        const map = new Map<string, unknown>();
        mock._diagnostics = map;
        return {
          set: (uri, list) => map.set(uri.toString(), list),
          delete: (uri) => map.delete(uri.toString()),
          get: (uri) => map.get(uri.toString()),
          dispose: () => map.clear(),
        };
      },
      registerCodeActionsProvider: (selector, provider, meta) => {
        mock._codeActionProviders.push({ selector, provider, meta });
        // The last registered provider, for tests that register only one.
        mock._codeActionProvider = provider;
        mock._codeActionMeta = meta;
        return { dispose() {} };
      },
      setTextDocumentLanguage: settle(
        (doc: MockDocument, languageId: string) => {
          doc.languageId = languageId;
          return doc;
        },
      ),
      registerCompletionItemProvider: (_lang, provider, ..._triggers) => {
        mock._completionProvider = provider;
        return { dispose() {} };
      },
      registerDocumentPasteEditProvider: (_sel, provider, meta) => {
        mock._pasteProvider = provider;
        mock._pasteMeta = meta;
        return { dispose() {} };
      },
    },
    extensions: { all: [] },

    MockDocument,
    MockEditor,

    _willSave: willSave,
    _didSave: didSave,
    _fireDocChange: (e) => {
      for (const l of mock._docChangeListeners.slice()) l(e);
    },
    _openTab: (input) => {
      const tab = { input, label: '' };
      const g = mock.window.tabGroups.activeTabGroup;
      g.tabs.push(tab);
      g.activeTab = tab;
      tabsChanged.fire({ opened: [tab], closed: [], changed: [] });
      return tab;
    },
    _closeTab: (tab) => mock.window.tabGroups.close(tab),
    // A second editor group (split editor); `activate` makes it the active one.
    _addGroup: (activate = true) => {
      const g2: MockTabGroup = {
        tabs: [],
        activeTab: undefined,
        isActive: activate,
      };
      mock.window.tabGroups.all.push(g2);
      if (activate) mock.window.tabGroups.activeTabGroup = g2;
      return g2;
    },
  };

  // "Save without Formatting": saves the active editor's document, skipping
  // the save participants (and with them onWillSaveTextDocument).
  mock._commandHandlers['workbench.action.files.saveWithoutFormatting'] =
    () => {
      mock._savedWithoutFormatting = (mock._savedWithoutFormatting || 0) + 1;
      // Like VS Code, the command resolves to nothing, success or not.
      return mock.window.activeTextEditor?.document
        .save({ skipParticipants: true })
        .then(() => undefined);
    };
  mock._commandHandlers['vscode.diff'] = (left, right) => {
    if (!isMockUri(left) || !isMockUri(right))
      throw new TypeError('vscode.diff: expected two Uris');
    mock._openTab(new TabInputTextDiff(left, right));
  };
  // Like VS Code, the swap replaces the tab in two steps: the old tab closes,
  // the swapped one opens a moment later.
  mock._commandHandlers['workbench.action.compareEditor.swapSides'] = () => {
    const g = mock.window.tabGroups.activeTabGroup;
    const tab = required(g.activeTab, 'activeTab');
    const input = tab.input;
    if (!(input instanceof TabInputTextDiff))
      throw new TypeError('swapSides: the active tab is no diff');
    const at = g.tabs.indexOf(tab);
    g.tabs.splice(at, 1);
    tabsChanged.fire({ opened: [], closed: [tab], changed: [] });
    return Promise.resolve().then(() => {
      const swapped = {
        input: new TabInputTextDiff(input.modified, input.original),
        label: '',
      };
      g.tabs.splice(at, 0, swapped);
      g.activeTab = swapped;
      tabsChanged.fire({ opened: [swapped], closed: [], changed: [] });
    });
  };
  mock._commandHandlers.setContext = (key, value) => {
    mock._context[String(key)] = value;
  };
  return mock;
}

/**
 * Installs a fresh mock for `import 'vscode'` and returns it. Modules loaded
 * before keep the mock they were loaded with (fresh state per suite comes from
 * loadFresh after install).
 */
function install(): VscodeMock {
  const mock = createMock();
  registerMock(mock);
  return mock;
}

/**
 * Loads a project module (path relative to the repository root) in a new src/
 * generation so module state does not leak between suites. The whole src/
 * graph is fresh, not just the entry: the modules import each other
 * (extension -> views/render/editing) and each binds `vscode` at load time, so
 * the new generation binds the mock consistently to the currently installed one.
 *
 * `M` names the module's type (`typeof import('../../src/x.ts')`); like any
 * dynamic import of a computed specifier it is not checked against the path.
 */
function loadFresh<M = Record<string, unknown>>(
  rootRelativePath: string,
): Promise<M> {
  const url = new URL(`../../${rootRelativePath}`, import.meta.url);
  url.searchParams.set('gen', String(nextGeneration()));
  return import(url.href);
}

/**
 * Narrows a mock member that exists only once a source used the matching API
 * (`_commands`, `_pasteProvider` ...); a missing one fails the test by name.
 */
function defined<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new TypeError(`the mock has no ${what}`);
  return value;
}

/** The extension context as the sources use it: subscriptions only. */
interface MockContext {
  subscriptions: { dispose?: () => void }[];
}

/** An edit runner as the editing commands hand it to the table branches. */
type MockEditFn = (
  editor: MockEditor,
  cb: (builder: MockEditBuilder) => void,
) => Promise<boolean>;

export {
  install,
  loadFresh,
  defined,
  makeUri,
  TabInputText,
  TabInputTextDiff,
  MockDocument,
  MockEditor,
  Position,
  Range,
  Selection,
};
export type {
  MockUri,
  MockTab,
  MockTabGroup,
  VscodeMock,
  MockContext,
  MockEditFn,
  MockEditBuilder,
};
