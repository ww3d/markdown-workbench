// Types of the vscode mock (vscode-mock.js) for the TypeScript files that import it (the bundle smoke); the
// JavaScript itself is not type-checked. Only the members those files use are spelled out.

/** A position in a mock document. */
export class Position {
  constructor(line: number, character: number);
  line: number;
  character: number;
  translate(lineDelta: number, characterDelta: number): Position;
}

/** A range between two positions. */
export class Range {
  constructor(
    startLine: number,
    startCharacter: number,
    endLine: number,
    endCharacter: number,
  );
  constructor(start: Position, end: Position);
  start: Position;
  end: Position;
  readonly isEmpty: boolean;
}

/** A selection; `active` is its end, `anchor` its start. */
export class Selection extends Range {
  active: Position;
  anchor: Position;
}

/** A Uri-like value as the mock builds it. */
export interface MockUri {
  scheme: string;
  path: string;
  fsPath: string;
  toString(): string;
}

/** An editable in-memory text document. */
export class MockDocument {
  constructor(text: string, uri?: string | MockUri);
  lines: string[];
  uri: MockUri;
  version: number;
  getText(range?: Range): string;
}

/** A text editor on a mock document. */
export class MockEditor {
  constructor(document: MockDocument, selection?: Selection);
  document: MockDocument;
  selection: Selection;
  selections: Selection[];
}

/** An editor tab input on one document. */
export class TabInputText {
  constructor(uri: MockUri);
  uri: MockUri;
}

/** A diff tab input. */
export class TabInputTextDiff {
  constructor(original: MockUri, modified: MockUri);
  original: MockUri;
  modified: MockUri;
}

/** The installed mock: the vscode API surface plus the recorded state tests read. */
export interface VscodeMock {
  window: {
    activeColorTheme: { kind: number };
    activeTextEditor: MockEditor | undefined;
  };
  /** The provider the extension registered with `registerCustomEditorProvider`. */
  _customEditorProvider: {
    resolveCustomTextEditor(
      document: MockDocument,
      panel: unknown,
    ): Promise<void>;
  };
  /** Registered command handlers by command id. */
  _commands: Record<string, (...args: unknown[]) => unknown>;
  [member: string]: unknown;
}

/** Installs a fresh mock for `import 'vscode'` and returns it. */
export function install(): VscodeMock;

/** Loads a repository-relative module in a fresh src/ generation. */
export function loadFresh(
  rootRelativePath: string,
): Promise<Record<string, unknown>>;

/** A Uri-like value with the string form `<scheme>:<path>`. */
export function makeUri(scheme: string, path: string): MockUri;
