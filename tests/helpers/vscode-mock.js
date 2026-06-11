// Shared vscode API mock. Installed via Module._load hook so that
// require('vscode') inside the extension sources resolves to this object.
// Provides editable documents and editors rich enough to drive the editing
// commands end to end and to capture WorkspaceEdits from the toggle paths.

const Module = require('module');

class Position {
  constructor(line, character) { this.line = line; this.character = character; }
  translate(dl, dc) { return new Position(this.line + dl, this.character + dc); }
}

class Range {
  constructor(a, b, c, d) {
    if (typeof a === 'number') {
      this.start = new Position(a, b); this.end = new Position(c, d);
    } else {
      this.start = a; this.end = b;
    }
  }
  get isEmpty() {
    return this.start.line === this.end.line && this.start.character === this.end.character;
  }
}

class Selection extends Range {
  constructor(a, b, c, d) { super(a, b, c, d); this.active = this.end; this.anchor = this.start; }
}

class SnippetString { constructor(value) { this.value = value; } }
class WorkspaceEdit {
  constructor() { this.ops = []; }
  replace(uri, range, text) { this.ops.push({ kind: 'replace', uri, range, text }); }
  delete(uri, range) { this.ops.push({ kind: 'delete', uri, range }); }
  insert(uri, pos, text) { this.ops.push({ kind: 'insert', uri, pos, text }); }
}

// An editable in-memory text document.
class MockDocument {
  constructor(text, uriString) {
    this.lines = text.split('\n');
    this.uri = {
      toString: () => uriString || 'mock://doc.md',
      scheme: 'file',
      fsPath: '/ws/doc.md',
      path: '/ws/doc.md'
    };
  }
  get lineCount() { return this.lines.length; }
  lineAt(line) {
    const n = typeof line === 'number' ? line : line.line;
    return { text: this.lines[n], lineNumber: n };
  }
  getText(range) {
    if (!range) return this.lines.join('\n');
    if (range.start.line === range.end.line) {
      return this.lines[range.start.line].slice(range.start.character, range.end.character);
    }
    const parts = [this.lines[range.start.line].slice(range.start.character)];
    for (let l = range.start.line + 1; l < range.end.line; l++) parts.push(this.lines[l]);
    parts.push(this.lines[range.end.line].slice(0, range.end.character));
    return parts.join('\n');
  }
  getWordRangeAtPosition(pos) {
    const text = this.lines[pos.line];
    let s = pos.character, e = pos.character;
    while (s > 0 && /\w/.test(text[s - 1])) s--;
    while (e < text.length && /\w/.test(text[e])) e++;
    return s === e ? undefined : new Range(pos.line, s, pos.line, e);
  }
  // Apply edit-builder operations (single line ops only - all the editing
  // commands operate that way, multi-line replaces use start/end columns).
  _apply(ops) {
    // Apply bottom-up / right-to-left so positions stay valid.
    ops.sort((a, b) => {
      const la = (a.range ? a.range.start.line : a.pos.line);
      const lb = (b.range ? b.range.start.line : b.pos.line);
      if (la !== lb) return lb - la;
      const ca = (a.range ? a.range.start.character : a.pos.character);
      const cb = (b.range ? b.range.start.character : b.pos.character);
      return cb - ca;
    });
    for (const op of ops) {
      if (op.kind === 'insert') {
        const { line, character } = op.pos;
        const txt = this.lines[line];
        const merged = txt.slice(0, character) + op.text + txt.slice(character);
        this.lines.splice(line, 1, ...merged.split('\n'));
      } else {
        const { start, end } = op.range;
        const head = this.lines[start.line].slice(0, start.character);
        const tail = this.lines[end.line].slice(end.character);
        const replacement = op.kind === 'replace' ? op.text : '';
        const merged = head + replacement + tail;
        this.lines.splice(start.line, end.line - start.line + 1, ...merged.split('\n'));
      }
    }
  }
}

class MockEditor {
  constructor(document, selection) {
    this.document = document;
    this.selection = selection || new Selection(0, 0, 0, 0);
    this.selections = [this.selection];
    this.insertedSnippets = [];
    this.revealed = [];
    this.visibleRanges = [new Range(0, 0, Math.max(0, document.lineCount - 1), 0)];
  }
  async edit(cb) {
    const ops = [];
    cb({
      insert: (pos, text) => ops.push({ kind: 'insert', pos, text }),
      delete: (range) => ops.push({ kind: 'delete', range }),
      replace: (range, text) => ops.push({ kind: 'replace', range, text })
    });
    this.document._apply(ops);
    return true;
  }
  async insertSnippet(snippet, location) {
    this.insertedSnippets.push({ snippet, location });
    return true;
  }
  revealRange(range, type) { this.revealed.push({ range, type }); }
}

function createMock() {
  const mock = {
    Position, Range, Selection, SnippetString, WorkspaceEdit,
    Uri: { joinPath: (...parts) => parts.join('/'), file: (p) => ({ fsPath: p, path: p, scheme: 'file', toString: () => 'file://' + p }) },
    ViewColumn: { Active: -1, Beside: -2, One: 1, Two: 2 },
    TextEditorRevealType: { AtTop: 3, Default: 0 },
    ConfigurationTarget: { Global: 1 },
    CompletionItem: function (label, kind) { this.label = label; this.kind = kind; },
    CompletionItemKind: { Value: 12 },
    EndOfLine: { LF: 1, CRLF: 2 },

    _executed: [],
    _applied: [],
    _config: {},
    _quickPickResult: undefined,
    _inputBoxResult: undefined,

    commands: {
      registerCommand: (id, fn) => { mock._commands = mock._commands || {}; mock._commands[id] = fn; return { dispose() {} }; },
      executeCommand: (id, ...args) => { mock._executed.push({ id, args }); return Promise.resolve(); }
    },
    window: {
      activeTextEditor: undefined,
      visibleTextEditors: [],
      activeColorTheme: { kind: 2 },
      registerCustomEditorProvider: (id, provider) => { mock._customEditorProvider = provider; return { dispose() {} }; },
      onDidChangeTextEditorVisibleRanges: () => ({ dispose() {} }),
      onDidChangeActiveColorTheme: (f) => { mock._themeListener = f; return { dispose() {} }; },
      showInformationMessage: (msg) => { mock._infos = mock._infos || []; mock._infos.push(msg); },
      showQuickPick: async () => mock._quickPickResult,
      showInputBox: async () => mock._inputBoxResult,
      showTextDocument: async (document) => {
        const editor = new MockEditor(document);
        mock.window.activeTextEditor = editor;
        return editor;
      },
      createWebviewPanel: () => mock._panelFactory()
    },
    workspace: {
      getConfiguration: () => ({ get: (key, dflt) => (key in mock._config ? mock._config[key] : dflt) }),
      applyEdit: (edit) => { mock._applied.push(...edit.ops); return Promise.resolve(true); },
      onDidChangeTextDocument: (f) => { mock._docChangeListener = f; return { dispose: () => { if (mock._docChangeListener === f) mock._docChangeListener = undefined; } }; },
      onDidCloseTextDocument: (f) => { mock._docCloseListener = f; return { dispose: () => { if (mock._docCloseListener === f) mock._docCloseListener = undefined; } }; },
      onDidChangeConfiguration: (f) => { mock._configListener = f; return { dispose: () => { if (mock._configListener === f) mock._configListener = undefined; } }; },
      openTextDocument: async (uri) => new MockDocument('', String(uri)),
      findFiles: async () => [],
      asRelativePath: (uri) => uri.path
    },
    languages: {
      registerCompletionItemProvider: (lang, provider, ...triggers) => {
        mock._completionProvider = provider; return { dispose() {} };
      }
    },
    extensions: { all: [] },

    MockDocument, MockEditor
  };
  return mock;
}

let installed = null;
const originalLoad = Module._load;

// Install the mock for require('vscode'); returns the mock. Re-installing
// replaces the previous instance (fresh state per test file is achieved by
// creating one mock per suite via fresh()).
function install() {
  installed = createMock();
  Module._load = function (request, parent, isMain) {
    if (request === 'vscode') return installed;
    return originalLoad.call(this, request, parent, isMain);
  };
  return installed;
}

// Load a project module (path relative to the repository root) with a fresh
// require cache so module state does not leak between suites. The whole src/
// graph is dropped, not just the entry: the modules require each other
// (extension -> views/render/editing) and each captures require('vscode') at
// load time, so re-requiring all of them rebinds the mock consistently to the
// currently installed instance.
function loadFresh(rootRelativePath) {
  const path = require('path');
  const srcDir = path.resolve(__dirname, '..', '..', 'src') + path.sep;
  for (const key of Object.keys(require.cache)) {
    if (key.startsWith(srcDir)) delete require.cache[key];
  }
  const full = require.resolve(path.resolve(__dirname, '..', '..', rootRelativePath));
  delete require.cache[full];
  return require(full);
}

module.exports = { install, loadFresh, MockDocument, MockEditor, Position, Range, Selection };
