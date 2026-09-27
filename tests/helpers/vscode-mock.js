// Shared vscode API mock. Installed via Module._load hook so that
// require('vscode') inside the extension sources resolves to this object.
// Provides editable documents and editors rich enough to drive the editing
// commands end to end and to capture WorkspaceEdits from the toggle paths.

const Module = require('node:module');

class Position {
  constructor(line, character) {
    this.line = line;
    this.character = character;
  }
  translate(dl, dc) {
    return new Position(this.line + dl, this.character + dc);
  }
}

class Range {
  constructor(a, b, c, d) {
    if (typeof a === 'number') {
      this.start = new Position(a, b);
      this.end = new Position(c, d);
    } else {
      this.start = a;
      this.end = b;
    }
  }
  get isEmpty() {
    return (
      this.start.line === this.end.line &&
      this.start.character === this.end.character
    );
  }
}

class Selection extends Range {
  constructor(a, b, c, d) {
    super(a, b, c, d);
    this.active = this.end;
    this.anchor = this.start;
  }
}

class SnippetString {
  constructor(value) {
    this.value = value;
  }
}
class WorkspaceEdit {
  constructor() {
    this.ops = [];
  }
  replace(uri, range, text) {
    this.ops.push({ kind: 'replace', uri, range, text });
  }
  delete(uri, range) {
    this.ops.push({ kind: 'delete', uri, range });
  }
  insert(uri, pos, text) {
    this.ops.push({ kind: 'insert', uri, pos, text });
  }
}

// An editable in-memory text document. `uri` is a string (legacy form, file
// scheme) or a Uri-like object from Uri.from / Uri.file / Uri.parse.
class MockDocument {
  constructor(text, uri) {
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
    this.isDirty = false;
    this.languageId = 'markdown';
    this.eol = 1; // EndOfLine.LF
    this.saves = 0;
    this.onSave = null; // (doc) => Promise<boolean>, set by the owning mock
  }
  offsetAt(pos) {
    let off = 0;
    for (let l = 0; l < pos.line; l++) off += this.lines[l].length + 1;
    return off + pos.character;
  }
  positionAt(offset) {
    let rest = Math.max(0, offset);
    for (let l = 0; l < this.lines.length; l++) {
      if (rest <= this.lines[l].length) return new Position(l, rest);
      rest -= this.lines[l].length + 1;
    }
    const last = this.lines.length - 1;
    return new Position(last, this.lines[last].length);
  }
  save() {
    this.saves++;
    const done = this.onSave ? this.onSave(this) : Promise.resolve(true);
    return Promise.resolve(done).then((ok) => {
      if (ok) this.isDirty = false;
      return ok;
    });
  }
  get lineCount() {
    return this.lines.length;
  }
  lineAt(line) {
    const n = typeof line === 'number' ? line : line.line;
    const text = this.lines[n];
    return {
      text,
      lineNumber: n,
      range: new Range(n, 0, n, (text || '').length),
    };
  }
  getText(range) {
    if (!range) return this.lines.join('\n');
    if (range.start.line === range.end.line) {
      return this.lines[range.start.line].slice(
        range.start.character,
        range.end.character,
      );
    }
    const parts = [this.lines[range.start.line].slice(range.start.character)];
    for (let l = range.start.line + 1; l < range.end.line; l++)
      parts.push(this.lines[l]);
    parts.push(this.lines[range.end.line].slice(0, range.end.character));
    return parts.join('\n');
  }
  getWordRangeAtPosition(pos) {
    const text = this.lines[pos.line];
    let s = pos.character,
      e = pos.character;
    while (s > 0 && /\w/.test(text[s - 1])) s--;
    while (e < text.length && /\w/.test(text[e])) e++;
    return s === e ? undefined : new Range(pos.line, s, pos.line, e);
  }
  // Apply edit-builder operations (single line ops only - all the editing
  // commands operate that way, multi-line replaces use start/end columns).
  _apply(ops) {
    // Apply bottom-up / right-to-left so positions stay valid.
    ops.sort((a, b) => {
      const la = a.range ? a.range.start.line : a.pos.line;
      const lb = b.range ? b.range.start.line : b.pos.line;
      if (la !== lb) return lb - la;
      const ca = a.range ? a.range.start.character : a.pos.character;
      const cb = b.range ? b.range.start.character : b.pos.character;
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
        this.lines.splice(
          start.line,
          end.line - start.line + 1,
          ...merged.split('\n'),
        );
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
    this.options = { tabSize: 4, insertSpaces: true };
    this.visibleRanges = [
      new Range(0, 0, Math.max(0, document.lineCount - 1), 0),
    ];
  }
  edit(cb) {
    const ops = [];
    cb({
      insert: (pos, text) => ops.push({ kind: 'insert', pos, text }),
      delete: (range) => ops.push({ kind: 'delete', range }),
      replace: (range, text) => ops.push({ kind: 'replace', range, text }),
    });
    this.document._apply(ops);
    return Promise.resolve(true);
  }
  insertSnippet(snippet, location) {
    this.insertedSnippets.push({ snippet, location });
    return Promise.resolve(true);
  }
  revealRange(range, type) {
    this.revealed.push({ range, type });
  }
}

// Wraps a synchronous mock body into a promise-returning API function (throws
// become rejections), like the async VS Code API it stands in for.
const settle =
  (fn) =>
  (...args) =>
    Promise.resolve().then(() => fn(...args));

// --- Clipboard-diff surface: events, file systems, tabs, diagnostics ---------

class Disposable {
  constructor(fn) {
    this._fn = fn;
  }
  dispose() {
    if (this._fn) this._fn();
    this._fn = null;
  }
}

class EventEmitter {
  constructor() {
    this.listeners = [];
    this.event = (f) => {
      this.listeners.push(f);
      return new Disposable(() => {
        this.listeners = this.listeners.filter((l) => l !== f);
      });
    };
  }
  fire(e) {
    for (const l of this.listeners.slice()) l(e);
  }
  dispose() {
    this.listeners = [];
  }
}

// Uri-like value with a stable string form "<scheme>:<path>".
function makeUri(scheme, path) {
  return {
    scheme,
    path,
    fsPath: path,
    toString: () => `${scheme}:${path}`,
  };
}

class FileSystemError extends Error {
  static FileNotFound(uri) {
    const e = new FileSystemError(`FileNotFound: ${uri}`);
    e.code = 'FileNotFound';
    return e;
  }
  static FileExists(uri) {
    const e = new FileSystemError(`FileExists: ${uri}`);
    e.code = 'FileExists';
    return e;
  }
}

class TabInputText {
  constructor(uri) {
    this.uri = uri;
  }
}

class TabInputTextDiff {
  constructor(original, modified) {
    this.original = original;
    this.modified = modified;
  }
}

class Diagnostic {
  constructor(range, message, severity) {
    this.range = range;
    this.message = message;
    this.severity = severity;
  }
}

class CodeAction {
  constructor(title, kind) {
    this.title = title;
    this.kind = kind;
  }
}

// Offset-based text replace used by the live applyEdit path below; returns the
// contentChanges entry VS Code would report.
function replaceInDocument(doc, range, text) {
  const start = doc.offsetAt(range.start);
  const end = doc.offsetAt(range.end);
  const full = doc.getText();
  doc.lines = (full.slice(0, start) + text + full.slice(end)).split('\n');
  doc.version++;
  return { range, rangeOffset: start, rangeLength: end - start, text };
}

function createMock() {
  const mock = {
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
    CompletionItem: function (label, kind) {
      this.label = label;
      this.kind = kind;
    },
    CompletionItemKind: { Value: 12 },
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
    CodeActionKind: { QuickFix: 'quickfix' },

    _executed: [],
    _applied: [],
    _config: {},
    _quickPickResult: undefined,
    _inputBoxResult: undefined,
    // Clipboard-diff state: clipboard text, answers for modal warnings (a value
    // or a function (message, ...items) => value), recorded messages, context
    // keys, registered file-system and code-action providers, per-command
    // handlers for executeCommand.
    _clipboard: '',
    _warningResult: undefined,
    _warnings: [],
    _errors: [],
    _statusMessages: [],
    _context: {},
    _fsProviders: {},
    _fsWrites: [],
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
        const r = mock._quickPickResult;
        return typeof r === 'function' ? r(await items) : r;
      },
      showWarningMessage: settle((message, ...rest) => {
        mock._warnings.push({ message, rest });
        const r = mock._warningResult;
        return typeof r === 'function' ? r(message, ...rest) : r;
      }),
      showErrorMessage: settle((message) => {
        mock._errors.push(message);
      }),
      setStatusBarMessage: (message) => {
        mock._statusMessages.push(message);
        return { dispose() {} };
      },
      onDidChangeActiveTextEditor: () => ({ dispose() {} }),
      tabGroups: null, // set below
      showInputBox: async () => mock._inputBoxResult,
      showTextDocument: (document) => {
        const editor = new MockEditor(document);
        mock.window.activeTextEditor = editor;
        return Promise.resolve(editor);
      },
      createWebviewPanel: (...args) => {
        mock._panelArgs = args;
        return mock._panelFactory();
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
        writeText: settle((t) => {
          mock._clipboard = t;
        }),
      },
    },
    workspace: {
      textDocuments: [],
      registerFileSystemProvider: (scheme, provider) => {
        mock._fsProviders[scheme] = provider;
        return { dispose() {} };
      },
      fs: {
        readFile: settle((uri) => {
          const provider = mock._fsProviders[uri.scheme];
          if (provider) return provider.readFile(uri);
          const doc = mock.workspace.textDocuments.find(
            (d) => d.uri.toString() === uri.toString(),
          );
          if (!doc) throw FileSystemError.FileNotFound(uri);
          return Buffer.from(doc.getText(), 'utf8');
        }),
        writeFile: settle((uri, content) => {
          mock._fsWrites.push({ uri, content });
        }),
      },
      getConfiguration: () => ({
        get: (key, dflt) => (key in mock._config ? mock._config[key] : dflt),
      }),
      // Records every op; ops on a document in workspace.textDocuments are
      // also applied to it and reported to all change listeners, like VS Code.
      applyEdit: (edit) => {
        mock._applied.push(...edit.ops);
        const byDoc = new Map();
        for (const op of edit.ops) {
          const doc = mock.workspace.textDocuments.find(
            (d) => d.uri.toString() === op.uri.toString(),
          );
          if (!doc) continue;
          if (!byDoc.has(doc)) byDoc.set(doc, []);
          byDoc.get(doc).push(op);
        }
        for (const [doc, ops] of byDoc) {
          ops.sort(
            (a, b) =>
              doc.offsetAt(b.range ? b.range.start : b.pos) -
              doc.offsetAt(a.range ? a.range.start : a.pos),
          );
          const contentChanges = ops.map((op) =>
            replaceInDocument(
              doc,
              op.range || new Range(op.pos, op.pos),
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
      openTextDocument: settle((uri) => {
        const known = mock.workspace.textDocuments.find(
          (d) => d.uri.toString() === String(uri),
        );
        if (known) return known;
        const provider = uri && mock._fsProviders[uri.scheme];
        if (!provider) return new MockDocument('', String(uri));
        const text = Buffer.from(provider.readFile(uri)).toString('utf8');
        const doc = new MockDocument(text, uri);
        doc.onSave = settle((d) => {
          provider.writeFile(uri, Buffer.from(d.getText(), 'utf8'), {
            create: true,
            overwrite: true,
          });
          return true;
        });
        mock.workspace.textDocuments.push(doc);
        return doc;
      }),
      findFiles: async () => [],
      asRelativePath: (uri) => uri.path,
    },
    languages: {
      createDiagnosticCollection: () => {
        const map = new Map();
        mock._diagnostics = map;
        return {
          set: (uri, list) => map.set(uri.toString(), list),
          delete: (uri) => map.delete(uri.toString()),
          get: (uri) => map.get(uri.toString()),
          dispose: () => map.clear(),
        };
      },
      registerCodeActionsProvider: (selector, provider) => {
        mock._codeActionProviders.push({ selector, provider });
        return { dispose() {} };
      },
      setTextDocumentLanguage: settle((doc, languageId) => {
        doc.languageId = languageId;
        return doc;
      }),
      registerCompletionItemProvider: (_lang, provider, ..._triggers) => {
        mock._completionProvider = provider;
        return { dispose() {} };
      },
    },
    extensions: { all: [] },

    MockDocument,
    MockEditor,
  };

  mock._fireDocChange = (e) => {
    for (const l of mock._docChangeListeners.slice()) l(e);
  };

  // Tabs: one group; a tab is { input, label }. vscode.diff opens a diff tab
  // and swapSides swaps the active one, like the real commands.
  const tabsChanged = new EventEmitter();
  const group = { tabs: [], activeTab: undefined, isActive: true };
  mock.window.tabGroups = {
    all: [group],
    activeTabGroup: group,
    onDidChangeTabs: tabsChanged.event,
    close: settle((tabs) => {
      const list = Array.isArray(tabs) ? tabs : [tabs];
      group.tabs = group.tabs.filter((t) => !list.includes(t));
      if (list.includes(group.activeTab)) group.activeTab = group.tabs.at(-1);
      tabsChanged.fire({ opened: [], closed: list, changed: [] });
      return true;
    }),
  };
  mock._openTab = (input) => {
    const tab = { input, label: '' };
    group.tabs.push(tab);
    group.activeTab = tab;
    tabsChanged.fire({ opened: [tab], closed: [], changed: [] });
    return tab;
  };
  mock._closeTab = (tab) => mock.window.tabGroups.close(tab);
  mock._commandHandlers['vscode.diff'] = (left, right) => {
    mock._openTab(new TabInputTextDiff(left, right));
  };
  mock._commandHandlers['workbench.action.compareEditor.swapSides'] = () => {
    const tab = group.activeTab;
    tab.input = new TabInputTextDiff(tab.input.modified, tab.input.original);
    tabsChanged.fire({ opened: [], closed: [], changed: [tab] });
  };
  mock._commandHandlers.setContext = (key, value) => {
    mock._context[key] = value;
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
  const path = require('node:path');
  const srcDir = path.resolve(__dirname, '..', '..', 'src') + path.sep;
  for (const key of Object.keys(require.cache)) {
    if (key.startsWith(srcDir)) delete require.cache[key];
  }
  const full = require.resolve(
    path.resolve(__dirname, '..', '..', rootRelativePath),
  );
  delete require.cache[full];
  return require(full);
}

module.exports = {
  install,
  loadFresh,
  makeUri,
  TabInputText,
  TabInputTextDiff,
  MockDocument,
  MockEditor,
  Position,
  Range,
  Selection,
};
